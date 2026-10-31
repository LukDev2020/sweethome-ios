import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import { authMiddleware } from "../middleware/auth";
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
  // My own guardians are already known; the other anchors need a lookup each.
  asProtected.forEach((l) => l.guardianId && familyIds.add(l.guardianId));
  const others = [...anchors].filter((a) => a !== uid);
  const guardiansOfOthers = await Promise.all(others.map((a) => activeLinks("protectedPersonId", a)));
  guardiansOfOthers.flat().forEach((l) => l.guardianId && familyIds.add(l.guardianId));

  return Array.from(familyIds);
}

function isoOrNow(value: any): string {
  return value?.toDate?.()?.toISOString() || new Date().toISOString();
}

function finiteOrNull(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

/**
 * GET /v1/family/posts
 * Get the family feed (posts from everyone in the caller's family circle).
 */
router.get("/posts", async (req: Request, res: Response) => {
  const uid = req.uid!;

  try {
    const familyIds = await getFamilyGroup(uid);

    // Firestore "in" query supports max 30 items
    const chunks: string[][] = [];
    for (let i = 0; i < familyIds.length; i += 30) {
      chunks.push(familyIds.slice(i, i + 30));
    }

    const allPosts: FirebaseFirestore.DocumentData[] = [];

    for (const chunk of chunks) {
      const snapshot = await db
        .collection("family_posts")
        .where("authorId", "in", chunk)
        .orderBy("createdAt", "desc")
        .limit(50)
        .get();
      snapshot.docs.forEach((d) => allPosts.push({ id: d.id, ...d.data() }));
    }

    // Sort merged results by createdAt desc
    allPosts.sort((a, b) => {
      const aTime = a.createdAt?.toDate?.() || new Date(0);
      const bTime = b.createdAt?.toDate?.() || new Date(0);
      return bTime.getTime() - aTime.getTime();
    });

    // The newest comments of each post, oldest first (chat order)
    const result = await Promise.all(
      allPosts.slice(0, 50).map(async (post) => {
        const commentsSnap = await db
          .collection("family_posts")
          .doc(post.id)
          .collection("comments")
          .orderBy("createdAt", "desc")
          .limit(COMMENTS_PER_POST)
          .get();

        const comments = commentsSnap.docs.reverse().map((c) => {
          const cd = c.data();
          return {
            id: c.id,
            authorId: cd.authorId,
            authorName: cd.authorName || "",
            authorInitial: cd.authorInitial || "?",
            text: cd.text || "",
            createdAt: isoOrNow(cd.createdAt),
          };
        });

        const latitude = finiteOrNull(post.latitude);
        const longitude = finiteOrNull(post.longitude);
        return {
          id: post.id,
          authorId: post.authorId,
          authorName: post.authorName || "",
          authorInitial: post.authorInitial || "?",
          text: post.text || "",
          mediaURLs: Array.isArray(post.mediaURLs) ? post.mediaURLs : [],
          createdAt: isoOrNow(post.createdAt),
          comments,
          // The stored count covers every comment, not just the ones returned
          commentCount: typeof post.commentCount === "number" ? Math.max(post.commentCount, comments.length) : comments.length,
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
  const media: string[] = (mediaURLs || []).filter((u: string) => /^https:\/\//i.test(u));
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

    const ref = await postRef.collection("comments").add(commentDoc);

    // Increment comment count
    await postRef.update({
      commentCount: admin.firestore.FieldValue.increment(1),
    });

    res.status(201).json({ commentId: ref.id });
  } catch (error) {
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

    // Make file publicly readable (or use signed URL)
    await file.makePublic();
    const url = `https://storage.googleapis.com/${bucket.name}/${fileName}`;

    res.json({ url });
  } catch (error) {
    console.error("[Family] upload error:", error);
    res.status(500).json({ error: "Failed to upload media" });
  }
});

export default router;
