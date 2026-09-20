import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import { authMiddleware } from "../middleware/auth";

const router = Router();
const db = admin.firestore();

router.use(authMiddleware);

/**
 * POST /v1/home-timer
 * Create or update a home timer. Protected person sets "I'll be home by X".
 * If not dismissed before deadline, escalation chain triggers.
 */
router.post("/", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { deadline, label, latitude, longitude } = req.body;

  if (!deadline) {
    res.status(400).json({ error: "deadline is required (ISO 8601)" });
    return;
  }

  try {
    const deadlineDate = new Date(deadline);
    if (deadlineDate <= new Date()) {
      res.status(400).json({ error: "deadline must be in the future" });
      return;
    }

    const timerRef = db.collection("home_timers").doc(uid);
    const now = admin.firestore.Timestamp.now();

    await timerRef.set({
      userId: uid,
      deadline: admin.firestore.Timestamp.fromDate(deadlineDate),
      label: label || "回家",
      latitude: latitude || null,
      longitude: longitude || null,
      status: "active",
      createdAt: now,
      dismissedAt: null,
      escalatedAt: null,
    });

    // Add timeline entry
    await db.collection("timeline_entries").add({
      userId: uid,
      timestamp: now,
      type: "homeTimerSet",
      description: `设置了回家计时：${label || "回家"}`,
      detail: deadlineDate.toISOString(),
    });

    res.status(201).json({
      success: true,
      deadline: deadlineDate.toISOString(),
    });
  } catch (error) {
    console.error("[HomeTimer] create error:", error);
    res.status(500).json({ error: "Failed to create home timer" });
  }
});

/**
 * GET /v1/home-timer
 * Get the current active home timer for the user.
 */
router.get("/", async (req: Request, res: Response) => {
  const uid = req.uid!;

  try {
    const timerDoc = await db.collection("home_timers").doc(uid).get();
    if (!timerDoc.exists || timerDoc.data()!.status !== "active") {
      res.json(null);
      return;
    }

    const data = timerDoc.data()!;
    res.json({
      userId: data.userId,
      deadline: data.deadline.toDate().toISOString(),
      label: data.label,
      status: data.status,
      createdAt: data.createdAt.toDate().toISOString(),
    });
  } catch (error) {
    console.error("[HomeTimer] get error:", error);
    res.status(500).json({ error: "Failed to get home timer" });
  }
});

/**
 * POST /v1/home-timer/dismiss
 * Dismiss the timer (user arrived safely).
 */
router.post("/dismiss", async (req: Request, res: Response) => {
  const uid = req.uid!;

  try {
    const timerRef = db.collection("home_timers").doc(uid);
    const now = admin.firestore.Timestamp.now();

    // M1 fix: use transaction to prevent race condition
    await db.runTransaction(async (transaction) => {
      const timerDoc = await transaction.get(timerRef);
      if (!timerDoc.exists || timerDoc.data()!.status !== "active") {
        throw new Error("NO_ACTIVE_TIMER");
      }
      transaction.update(timerRef, {
        status: "dismissed",
        dismissedAt: now,
      });
    });

    // Add timeline entry
    await db.collection("timeline_entries").add({
      userId: uid,
      timestamp: now,
      type: "homeTimerDismissed",
      description: "已安全到达",
      detail: null,
    });

    // Notify guardians that the person arrived safely
    const linksSnapshot = await db
      .collection("guardian_links")
      .where("protectedPersonId", "==", uid)
      .where("status", "==", "active")
      .get();

    const userDoc = await db.collection("users").doc(uid).get();
    const userName = userDoc.exists ? userDoc.data()!.displayName : "被守护者";

    for (const linkDoc of linksSnapshot.docs) {
      const guardianId = linkDoc.data().guardianId;
      const tokens = await getTokensForUser(guardianId);
      if (tokens.length > 0) {
        await admin.messaging().sendEachForMulticast({
          tokens,
          notification: {
            title: "已安全到达",
            body: `${userName}已关闭回家计时器`,
          },
          data: { action: "home_timer_dismissed" },
        });
      }
    }

    res.json({ success: true });
  } catch (error: any) {
    if (error.message === "NO_ACTIVE_TIMER") {
      res.status(404).json({ error: "No active timer" });
      return;
    }
    console.error("[HomeTimer] dismiss error:", error);
    res.status(500).json({ error: "Failed to dismiss timer" });
  }
});

/**
 * GET /v1/home-timer/guardian
 * Guardian endpoint: get active home timers for all protected persons.
 */
router.get("/guardian", async (req: Request, res: Response) => {
  const uid = req.uid!;

  try {
    const linksSnapshot = await db
      .collection("guardian_links")
      .where("guardianId", "==", uid)
      .where("status", "==", "active")
      .get();

    const timers = [];
    for (const linkDoc of linksSnapshot.docs) {
      const personId = linkDoc.data().protectedPersonId;
      const timerDoc = await db.collection("home_timers").doc(personId).get();
      if (timerDoc.exists && timerDoc.data()!.status === "active") {
        const data = timerDoc.data()!;
        const userDoc = await db.collection("users").doc(personId).get();
        timers.push({
          userId: personId,
          displayName: userDoc.exists ? userDoc.data()!.displayName : "未知",
          deadline: data.deadline.toDate().toISOString(),
          label: data.label,
          status: data.status,
        });
      }
    }

    res.json(timers);
  } catch (error) {
    console.error("[HomeTimer] guardian get error:", error);
    res.status(500).json({ error: "Failed to get timers" });
  }
});

async function getTokensForUser(userId: string): Promise<string[]> {
  const snapshot = await db
    .collection("device_tokens")
    .where("userId", "==", userId)
    .get();
  return snapshot.docs.map((doc) => doc.data().token);
}

export default router;
