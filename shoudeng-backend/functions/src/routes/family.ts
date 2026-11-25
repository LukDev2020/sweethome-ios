import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import { authMiddleware } from "../middleware/auth";
import { docsWhereIn } from "../services/batchRead";
import { createRateLimiter, RATE_LIMITS } from "../middleware/rateLimit";

const router = Router();
const db = admin.firestore();

router.use(authMiddleware);

/** Largest decoded upload accepted. The app sends ~1600 px JPEGs (~0.3–0.8 MB). */
export const MAX_UPLOAD_BYTES = 5 * 1024 * 1024;
/** JSON body limit for POST /v1/family/upload only (base64 adds ~33 %, so > MAX_UPLOAD_BYTES). Mounted in app.ts. */
export const UPLOAD_JSON_LIMIT = "8mb";

/** Newest comments returned per post in the feed. */
const COMMENTS_PER_POST = 10;

/** App-generated id for a post (lets a retried send land on the same document). */
const CLIENT_POST_ID = /^[A-Za-z0-9_-]{8,64}$/;

async function activeLinks(field: "guardianId" | "protectedPersonId", uid: string) {
  const snap = await db
    .collection("guardian_links")
    .where(field, "==", uid)
    .where("status", "==", "active")
    .get();
  return snap.docs.map((d) => d.data());
}

/**
 * Everyone whose posts the caller sees (and may comment on) in the family circle.
 *
 * The circle is built around protected persons ("anchors"):
 *   - anchors = the people I look out for, plus me if anyone looks out for me;
 *   - circle  = me + every anchor + every active guardian of every anchor.
 *
 * So a protected person sees their guardians; a guardian sees the people they look
 * out for and every other guardian of those people (siblings looking out for the
 * same parent see each other). It is symmetric: A sees B exactly when B sees A.
 *
 * Deliberately NOT included: other people my guardian looks out for (a guardian may
 * be a carer for unrelated people), or anyone further away (no transitive closure).
 */
export async function getFamilyGroup(uid: string): Promise<string[]> {
  const [asGuardian, asProtected] = await Promise.all([
    activeLinks("guardianId", uid),
    activeLinks("protectedPersonId", uid),
  ]);

  const anchors = new Set<string>(asGuardian.map((l) => l.protectedPersonId).filter(Boolean));
  if (asProtected.length > 0) anchors.add(uid);

  const familyIds = new Set<string>([uid, ...anchors]);
  // My own guardians are already known.
  asProtected.forEach((l) => l.guardianId && familyIds.add(l.guardianId));
  // The other anchors' guardians: one `in` query per 30 anchors, not one per anchor
  const others = [...anchors].filter((a) => a !== uid);
  const guardiansOfOthers = await docsWhereIn(others, (part) => db
    .collection("guardian_links")
    .where("protectedPersonId", "in", part)
    .where("status", "==", "active"));
  guardiansOfOthers.forEach((d) => { const g = d.get("guardianId"); if (g) familyIds.add(g); });

  return Array.from(familyIds);
}

/** How long a feed photo link works; the app refetches the feed far more often */
const MEDIA_LINK_HOURS = 24;

/**
 * Family photos are private objects. For someone allowed to see the post, turn
 * each stored photo id (https://storage.googleapis.com/<bucket>/family/…) into a
 * signed link. Anything else (older or external URLs) passes through.
 */
async function signedFamilyMedia(urls: unknown): Promise<string[]> {
  if (!Array.isArray(urls)) return [];
  const bucket = admin.storage().bucket();
  const prefix = `https://storage.googleapis.com/${bucket.name}/`;
  return Promise.all(urls.filter((u): u is string => typeof u === "string").map(async (u) => {
    if (!u.startsWith(prefix)) return u;
    const path = decodeURIComponent(u.slice(prefix.length));
    if (!path.startsWith("family/") || path.includes("..")) return u;
    try {
      const [signed] = await bucket.file(path).getSignedUrl({
        action: "read",
        expires: Date.now() + MEDIA_LINK_HOURS * 60 * 60 * 1000,
      });
      return signed;
    } catch (error) {
      console.warn("[Family] could not sign a photo link:", (error as Error).message);
      return u;
    }
  }));
}

function isoOrNow(value: any): string {
  return value?.toDate?.()?.toISOString() || new Date().toISOString();
}

function finiteOrNull(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

interface StoredComment {
  id: string;
  authorId: string;
  authorName?: string;
  authorInitial?: string;
  text?: string;
  createdAt?: FirebaseFirestore.Timestamp;
}

/** A post's newest comments, newest first: the copy on the post, else the subcollection. */
async function newestComments(post: FirebaseFirestore.DocumentData): Promise<StoredComment[]> {
  if (Array.isArray(post.recentComments)) {
    return (post.recentComments as StoredComment[]).slice(-COMMENTS_PER_POST).reverse();
  }
  const snap = await db
    .collection("family_posts")
    .doc(post.id)
    .collection("comments")
    .orderBy("createdAt", "desc")
    .limit(COMMENTS_PER_POST)
    .get();
  return snap.docs.map((c) => ({ id: c.id, ...c.data() } as StoredComment));
}

/** The post was deleted while a comment was being added. */
class PostGone extends Error {}

/**
 * GET /v1/family/posts
 * Get the family feed (posts from everyone in the caller's family circle).
 */
router.get("/posts", async (req: Request, res: Response) => {
  const uid = req.uid!;

  try {
    const familyIds = await getFamilyGroup(uid);
    const family = new Set(familyIds);

    // Firestore "in" query supports max 30 items
    const chunks: string[][] = [];
    for (let i = 0; i < familyIds.length; i += 30) {
      chunks.push(familyIds.slice(i, i + 30));
    }

    const snapshots = await Promise.all(chunks.map((chunk) => db
      .collection("family_posts")
      .where("authorId", "in", chunk)
      .orderBy("createdAt", "desc")
      .limit(50)
      .get()));
    const allPosts: FirebaseFirestore.DocumentData[] = snapshots
      .flatMap((snapshot) => snapshot.docs.map((d) => ({ id: d.id, ...d.data() })));

    // Sort merged results by createdAt desc
    allPosts.sort((a, b) => {
      const aTime = a.createdAt?.toDate?.() || new Date(0);
      const bTime = b.createdAt?.toDate?.() || new Date(0);
      return bTime.getTime() - aTime.getTime();
    });

    // The newest comments of each post, oldest first (chat order). Posts carry them
    // (`recentComments`), so the feed is one query, not one more per post; only
    // posts from before that field existed still read their comments.
    const result = await Promise.all(
      allPosts.slice(0, 50).map(async (post) => {
        const newest = await newestComments(post);

        // A carer who looks after two unrelated people is in both families; on the
        // carer's posts each family sees only its own members' comments.
        const visible = newest.filter((c) => family.has(c.authorId));
        const someHidden = visible.length < newest.length;
        const comments = visible.reverse().map((c) => ({
          id: c.id,
          authorId: c.authorId,
          authorName: c.authorName || "",
          authorInitial: c.authorInitial || "?",
          text: c.text || "",
          createdAt: isoOrNow(c.createdAt),
        }));

        const latitude = finiteOrNull(post.latitude);
        const longitude = finiteOrNull(post.longitude);
        return {
          id: post.id,
          authorId: post.authorId,
          authorName: post.authorName || "",
          authorInitial: post.authorInitial || "?",
          text: post.text || "",
          mediaURLs: await signedFamilyMedia(post.mediaURLs),
          createdAt: isoOrNow(post.createdAt),
          comments,
          // The stored count covers every comment, not just the ones returned
          commentCount: someHidden || typeof post.commentCount !== "number"
            ? comments.length
            : Math.max(post.commentCount, comments.length),
          latitude: latitude !== null && longitude !== null ? latitude : null,
          longitude: latitude !== null && longitude !== null ? longitude : null,
          locationName: typeof post.locationName === "string" && post.locationName ? post.locationName : null,
        };
      })
    );

    res.json(result);
  } catch (error) {
    console.error("[Family] fetch posts error:", error);
    res.status(500).json({ error: "Failed to fetch posts" });
  }
});

/**
 * POST /v1/family/posts
 * Create a new post in the family feed.
 *
 * Body: { text, mediaURLs, latitude?, longitude?, locationName?, clientPostId? }
 * `clientPostId` makes a retried send idempotent: the post is stored under that id,
 * and sending it again returns the same post instead of a duplicate.
 */
router.post("/posts", createRateLimiter(RATE_LIMITS.general), async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { text, mediaURLs, latitude, longitude, locationName, clientPostId } = req.body;

  if (mediaURLs !== undefined && (!Array.isArray(mediaURLs) || mediaURLs.some((u: unknown) => typeof u !== "string"))) {
    res.status(400).json({ error: "mediaURLs must be an array of URLs" });
    return;
  }
  // Only links everyone in the family can open (a phone's file:// path is not one)
  // Our own storage links only for the author's own uploads (the feed signs them,
  // so someone else's photo path must not be attachable)
  const storagePrefix = `https://storage.googleapis.com/${admin.storage().bucket().name}/`;
  const media: string[] = (mediaURLs || []).filter((u: string) =>
    /^https:\/\//i.test(u)
    && (!u.startsWith(storagePrefix) || decodeURIComponent(u.slice(storagePrefix.length)).startsWith(`family/${req.uid!}/`)));
  if (media.length > 9) {
    res.status(400).json({ error: "At most 9 photos per post" });
    return;
  }

  if (!text && media.length === 0) {
    res.status(400).json({ error: "Post must have text or media" });
    return;
  }

  if (text && (typeof text !== "string" || text.length > 5000)) {
    res.status(400).json({ error: "Post text must be 5000 characters or less" });
    return;
  }

  if (clientPostId !== undefined && (typeof clientPostId !== "string" || !CLIENT_POST_ID.test(clientPostId))) {
    res.status(400).json({ error: "Invalid clientPostId" });
    return;
  }

  // Location is optional; a pair of valid coordinates or nothing
  const lat = finiteOrNull(latitude);
  const lng = finiteOrNull(longitude);
  const hasLocation = lat !== null && lng !== null && Math.abs(lat) <= 90 && Math.abs(lng) <= 180;
  const place = typeof locationName === "string" ? locationName.trim().slice(0, 200) : "";

  try {
    const postRef = clientPostId
      ? db.collection("family_posts").doc(clientPostId)
      : db.collection("family_posts").doc();

    if (clientPostId) {
      const existing = await postRef.get();
      if (existing.exists) {
        if (existing.data()!.authorId === uid) {
          res.status(200).json({ postId: postRef.id });
        } else {
          res.status(409).json({ error: "Post id already used", code: "POST_ID_TAKEN" });
        }
        return;
      }
    }

    // Get author info
    const userDoc = await db.collection("users").doc(uid).get();
    if (!userDoc.exists) {
      res.status(404).json({ error: "User not found" });
      return;
    }
    const user = userDoc.data()!;

    const postDoc: Record<string, unknown> = {
      authorId: uid,
      authorName: user.displayName || "",
      authorInitial: user.avatarInitial || user.displayName?.charAt(0) || "?",
      text: text || "",
      mediaURLs: media,
      commentCount: 0,
      recentComments: [],
      createdAt: admin.firestore.Timestamp.now(),
    };
    if (hasLocation) {
      postDoc.latitude = lat;
      postDoc.longitude = lng;
    }
    if (place) postDoc.locationName = place;

    await postRef.create(postDoc);

    res.status(201).json({ postId: postRef.id });
  } catch (error: any) {
    // Two sends of the same clientPostId raced; the other one created it
    if (clientPostId && error?.code === 6) {
      res.status(200).json({ postId: clientPostId });
      return;
    }
    console.error("[Family] create post error:", error);
    res.status(500).json({ error: "Failed to create post" });
  }
});

/**
 * POST /v1/family/posts/:postId/comments
 * Add a comment to a post.
 */
router.post("/posts/:postId/comments", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { postId } = req.params;
  const { text } = req.body;

  if (!text || text.trim().length === 0) {
    res.status(400).json({ error: "Comment text is required" });
    return;
  }

  if (text.length > 2000) {
    res.status(400).json({ error: "Comment text must be 2000 characters or less" });
    return;
  }

  try {
    // Verify post exists
    const postRef = db.collection("family_posts").doc(postId);
    const postDoc = await postRef.get();
    if (!postDoc.exists) {
      res.status(404).json({ error: "Post not found" });
      return;
    }

    // Verify user is in the same family group
    const familyIds = await getFamilyGroup(uid);
    const postAuthor = postDoc.data()!.authorId;
    if (!familyIds.includes(postAuthor) && postAuthor !== uid) {
      res.status(403).json({ error: "You are not in this family group" });
      return;
    }

    // Get commenter info
    const userDoc = await db.collection("users").doc(uid).get();
    const user = userDoc.exists ? userDoc.data()! : { displayName: "Unknown", avatarInitial: "?" };

    const commentDoc = {
      authorId: uid,
      authorName: user.displayName,
      authorInitial: user.avatarInitial || user.displayName?.charAt(0) || "?",
      text: text.trim(),
      createdAt: admin.firestore.Timestamp.now(),
    };

    const ref = postRef.collection("comments").doc();
    await db.runTransaction(async (tx) => {
      const fresh = await tx.get(postRef);
      if (!fresh.exists) throw new PostGone();
      const update: Record<string, unknown> = { commentCount: admin.firestore.FieldValue.increment(1) };
      // The feed's copy of the newest comments. A post from before the copy existed
      // keeps reading its subcollection until it is rebuilt from there.
      const recent = fresh.data()!.recentComments;
      if (Array.isArray(recent)) {
        update.recentComments = [...recent, { id: ref.id, ...commentDoc }].slice(-COMMENTS_PER_POST);
      }
      tx.create(ref, commentDoc);
      tx.update(postRef, update);
    });

    res.status(201).json({ commentId: ref.id });
  } catch (error) {
    if (error instanceof PostGone) {
      res.status(404).json({ error: "Post not found" });
      return;
    }
    console.error("[Family] add comment error:", error);
    res.status(500).json({ error: "Failed to add comment" });
  }
});

/**
 * PUT /v1/family/posts/:postId
 * Edit a post (author only).
 */
router.put("/posts/:postId", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { postId } = req.params;
  const { text } = req.body;

  if (!text || text.trim().length === 0) {
    res.status(400).json({ error: "Post text is required" });
    return;
  }

  try {
    const postRef = db.collection("family_posts").doc(postId);
    const postDoc = await postRef.get();

    if (!postDoc.exists) {
      res.status(404).json({ error: "Post not found" });
      return;
    }

    if (postDoc.data()!.authorId !== uid) {
      res.status(403).json({ error: "Only the author can edit this post" });
      return;
    }

    await postRef.update({
      text: text.trim(),
      updatedAt: admin.firestore.Timestamp.now(),
    });

    res.json({ success: true });
  } catch (error) {
    console.error("[Family] edit post error:", error);
    res.status(500).json({ error: "Failed to edit post" });
  }
});

/**
 * DELETE /v1/family/posts/:postId
 * Delete a post and its comments (author only).
 */
router.delete("/posts/:postId", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { postId } = req.params;

  try {
    const postRef = db.collection("family_posts").doc(postId);
    const postDoc = await postRef.get();

    if (!postDoc.exists) {
      res.status(404).json({ error: "Post not found" });
      return;
    }

    if (postDoc.data()!.authorId !== uid) {
      res.status(403).json({ error: "Only the author can delete this post" });
      return;
    }

    // Delete comments subcollection
    const commentsSnap = await postRef.collection("comments").get();
    const batch = db.batch();
    commentsSnap.docs.forEach((doc) => batch.delete(doc.ref));
    batch.delete(postRef);
    await batch.commit();

    res.json({ success: true });
  } catch (error) {
    console.error("[Family] delete post error:", error);
    res.status(500).json({ error: "Failed to delete post" });
  }
});

/**
 * POST /v1/family/upload
 * Upload a photo (base64 JPEG in JSON) and return its URL.
 *
 * The app downsizes photos to ~1600 px before sending, so bodies are well under the
 * route's own JSON limit (UPLOAD_JSON_LIMIT, mounted in app.ts ahead of the global
 * 100 kB parser). Anything bigger gets 413 with code UPLOAD_TOO_LARGE.
 */
router.post("/upload", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { data, mimeType } = req.body;

  if (!data || typeof data !== "string") {
    res.status(400).json({ error: "Missing data" });
    return;
  }

  try {
    const buffer = Buffer.from(data, "base64");
    if (buffer.length === 0) {
      res.status(400).json({ error: "Missing data" });
      return;
    }
    if (buffer.length > MAX_UPLOAD_BYTES) {
      res.status(413).json({ error: "File too large", code: "UPLOAD_TOO_LARGE", maxBytes: MAX_UPLOAD_BYTES });
      return;
    }

    const bucket = admin.storage().bucket();
    const extension_ = mimeType === "image/jpeg" ? ".jpg" : mimeType === "video/mp4" ? ".mp4" : ".bin";
    const fileName = `family/${uid}/${Date.now()}${extension_}`;
    const file = bucket.file(fileName);

    await file.save(buffer, {
      metadata: {
        contentType: mimeType || "image/jpeg",
      },
    });

    // Private: the feed hands out short-lived signed links to family members only
    // (signedFamilyMedia). This URL is the photo's stable id, not a public link.
    const url = `https://storage.googleapis.com/${bucket.name}/${fileName}`;

    res.json({ url });
  } catch (error) {
    console.error("[Family] upload error:", error);
    res.status(500).json({ error: "Failed to upload media" });
  }
});

export default router;
