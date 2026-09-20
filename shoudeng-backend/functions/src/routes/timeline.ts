import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import { authMiddleware } from "../middleware/auth";

const router = Router();
const db = admin.firestore();

router.use(authMiddleware);

/**
 * GET /v1/timeline
 * Retrieve timeline entries for the authenticated user.
 * Supports pagination via ?limit=N&before=ISO_DATE
 */
router.get("/", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const limit = Math.min(parseInt(req.query.limit as string) || 50, 200);
  const before = req.query.before as string | undefined;

  try {
    let query = db
      .collection("timeline_entries")
      .where("userId", "==", uid)
      .orderBy("timestamp", "desc")
      .limit(limit);

    if (before) {
      const beforeDate = new Date(before);
      if (!isNaN(beforeDate.getTime())) {
        query = query.where(
          "timestamp",
          "<",
          admin.firestore.Timestamp.fromDate(beforeDate)
        );
      }
    }

    const snapshot = await query.get();

    const entries = snapshot.docs.map((doc) => {
      const data = doc.data();
      return {
        id: doc.id,
        type: data.type,
        description: data.description,
        detail: data.detail || null,
        timestamp:
          data.timestamp?.toDate?.()?.toISOString() || null,
      };
    });

    res.json({ entries });
  } catch (error) {
    console.error("[Timeline] fetch error:", error);
    res.status(500).json({ error: "Failed to fetch timeline" });
  }
});

export default router;
