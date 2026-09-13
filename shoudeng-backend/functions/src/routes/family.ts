import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import { authMiddleware } from "../middleware/auth";

const router = Router();
const db = admin.firestore();

router.use(authMiddleware);

/**
 * Helper: get all user IDs in the caller's family group.
 * Family = all users linked via guardian_links (both directions).
 */
async function getFamilyGroup(uid: string): Promise<string[]> {
  const familyIds = new Set<string>();
  familyIds.add(uid);

  // Links where user is guardian
  const asGuardian = await db
    .collection("guardian_links")
    .where("guardianId", "==", uid)
    .where("status", "==", "active")
    .get();
  asGuardian.docs.forEach((d) => familyIds.add(d.data().protectedPersonId));

  // Links where user is protected person
  const asProtected = await db
    .collection("guardian_links")
    .where("protectedPersonId", "==", uid)
    .where("status", "==", "active")
    .get();
  asProtected.docs.forEach((d) => familyIds.add(d.data().guardianId));

  return Array.from(familyIds);
}

/**
 * GET /v1/family/posts
 * Get the family feed (posts from all linked family members).
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

    // Fetch comments for each post (last 10)
    const result = await Promise.all(
      allPosts.slice(0, 50).map(async (post) => {
        const commentsSnap = await db
          .collection("family_posts")
          .doc(post.id)
          .collection("comments")
          .orderBy("createdAt", "asc")
          .limit(10)
          .get();

        const comments = commentsSnap.docs.map((c) => {
          const cd = c.data();
          return {
            id: c.id,
            authorId: cd.authorId,
            authorName: cd.authorName,
            authorInitial: cd.authorInitial,
            text: cd.text,
            createdAt: cd.createdAt?.toDate?.()?.toISOString() || new Date().toISOString(),
          };
        });

        return {
          id: post.id,
          authorId: post.authorId,
          authorName: post.authorName,
          authorInitial: post.authorInitial,
          text: post.text || "",
          mediaURLs: post.mediaURLs || [],
          createdAt: post.createdAt?.toDate?.()?.toISOString() || new Date().toISOString(),
          comments,
          commentCount: post.commentCount || comments.length,
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
 */
router.post("/posts", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { text, mediaURLs } = req.body;

  if (!text && (!mediaURLs || mediaURLs.length === 0)) {
    res.status(400).json({ error: "Post must have text or media" });
    return;
  }

  try {
    // Get author info
    const userDoc = await db.collection("users").doc(uid).get();
    if (!userDoc.exists) {
      res.status(404).json({ error: "User not found" });
      return;
    }
    const user = userDoc.data()!;

    const postDoc = {
      authorId: uid,
      authorName: user.displayName,
      authorInitial: user.avatarInitial || user.displayName?.charAt(0) || "?",
      text: text || "",
      mediaURLs: mediaURLs || [],
      commentCount: 0,
      createdAt: admin.firestore.Timestamp.now(),
    };

    const ref = await db.collection("family_posts").add(postDoc);

    res.status(201).json({ postId: ref.id });
  } catch (error) {
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
 * Upload media (base64 encoded) and return the download URL.
 * In production, clients should upload directly to Firebase Storage.
 */
router.post("/upload", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { data, mimeType } = req.body;

  if (!data) {
    res.status(400).json({ error: "Missing data" });
    return;
  }

  try {
    const bucket = admin.storage().bucket();
    const extension_ = mimeType === "image/jpeg" ? ".jpg" : mimeType === "video/mp4" ? ".mp4" : ".bin";
    const fileName = `family/${uid}/${Date.now()}${extension_}`;
    const file = bucket.file(fileName);

    const buffer = Buffer.from(data, "base64");
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
