import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import { authMiddleware } from "../middleware/auth";

const router = Router();
const db = admin.firestore();

// POST /v1/silent-alarm/schedule — Set or update silent alarm schedule
router.post("/schedule", authMiddleware, async (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const { enabled, times, windowMinutes, gracePeriodMisses } = req.body;

  if (typeof enabled !== "boolean") {
    return res.status(400).json({ error: "enabled must be a boolean" });
  }

  if (enabled) {
    if (!Array.isArray(times) || times.length === 0) {
      return res.status(400).json({ error: "times must be a non-empty array" });
    }
    for (const t of times) {
      if (typeof t.hour !== "number" || typeof t.minute !== "number") {
        return res.status(400).json({ error: "each time must have hour and minute" });
      }
      if (t.hour < 0 || t.hour > 23 || t.minute < 0 || t.minute > 59) {
        return res.status(400).json({ error: "invalid time values" });
      }
    }
  }

  await db.collection("silent_alarm_schedules").doc(userId).set({
    enabled,
    times: enabled ? times : [],
    windowMinutes: windowMinutes || 30,
    gracePeriodMisses: gracePeriodMisses || 3,
    consecutiveMisses: 0,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  return res.json({ success: true });
});

// POST /v1/silent-alarm/confirm — User confirms they are safe
router.post("/confirm", authMiddleware, async (req: Request, res: Response) => {
  const userId = (req as any).userId;

  const ref = db.collection("silent_alarm_schedules").doc(userId);
  const doc = await ref.get();

  if (!doc.exists) {
    return res.status(404).json({ error: "No silent alarm configured" });
  }

  await ref.update({
    consecutiveMisses: 0,
    lastConfirmedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // Log the check-in to timeline
  await db.collection("timeline_entries").add({
    userId,
    type: "silent_alarm_confirmed",
    description: "安全确认已完成",
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });

  return res.json({ success: true });
});

// GET /v1/silent-alarm — Get current schedule
router.get("/", authMiddleware, async (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const doc = await db.collection("silent_alarm_schedules").doc(userId).get();

  if (!doc.exists) {
    return res.json({ enabled: false, times: [], windowMinutes: 30, gracePeriodMisses: 3 });
  }

  return res.json(doc.data());
});

export default router;
