import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import { authMiddleware } from "../middleware/auth";
import { toIso } from "../services/time";

const router = Router();
const db = admin.firestore();

router.use(authMiddleware);

/**
 * GET /v1/timeline
 * Retrieve timeline entries for the authenticated user, or — with ?personId= —
 * for someone they actively guard (member detail screen).
 * Supports pagination via ?limit=N&before=ISO_DATE
 */
router.get("/", async (req: Request, res: Response) => {
  const caller = req.uid!;
  const personId = typeof req.query.personId === "string" ? req.query.personId : "";
  let uid = caller;
  if (personId && personId !== caller) {
    const link = await db.collection("guardian_links").doc(`${caller}_${personId}`).get();
    if (!link.exists || link.data()?.status !== "active") {
      res.status(403).json({ error: "Not authorized to view this person's timeline" });
      return;
    }
    uid = personId;
  }
  const limit = Math.min(parseInt(req.query.limit as string) || 50, 200);
  const before = req.query.before as string | undefined;

  try {
    let query = db
      .collection("timeline_entries")
      .where("userId", "==", uid)
      .orderBy("timestamp", "desc")
      .limit(limit + 1); // one extra row tells us whether there is another page

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
    const hasMore = snapshot.docs.length > limit;

    const entries = snapshot.docs.slice(0, limit).flatMap((doc) => {
      const data = doc.data();
      const timestamp = toIso(data.timestamp);
      // iOS TimelineEntry requires a timestamp — skip malformed rows instead of
      // failing the whole page.
      if (!timestamp || typeof data.type !== "string") return [];
      return [{
        id: doc.id,
        type: data.type,
        description: typeof data.description === "string" ? data.description : "",
        detail: data.detail || null,
        timestamp,
      }];
    });

    res.json({
      entries,
      hasMore,
      nextBefore: hasMore && entries.length > 0 ? entries[entries.length - 1].timestamp : null,
    });
  } catch (error) {
    console.error("[Timeline] fetch error:", error);
    res.status(500).json({ error: "Failed to fetch timeline" });
  }
});

export default router;
