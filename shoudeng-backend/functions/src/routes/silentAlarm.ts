import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import { authMiddleware } from "../middleware/auth";

const router = Router();
const db = admin.firestore();

// POST /v1/silent-alarm/schedule — Set or update silent alarm schedule
router.post("/schedule", authMiddleware, async (req: Request, res: Response) => {
  const userId = req.uid!;
  const { enabled, times, windowMinutes, gracePeriodMisses, timeZone } = req.body ?? {};

  if (typeof enabled !== "boolean") {
    return res.status(400).json({ error: "enabled must be a boolean" });
  }

  if (enabled) {
    if (!Array.isArray(times) || times.length === 0 || times.length > 12) {
      return res.status(400).json({ error: "times must list 1–12 check-in times" });
    }
    for (const t of times) {
      if (!t || typeof t.hour !== "number" || typeof t.minute !== "number"
        || !Number.isInteger(t.hour) || !Number.isInteger(t.minute)) {
        return res.status(400).json({ error: "each time must have hour and minute" });
      }
      if (t.hour < 0 || t.hour > 23 || t.minute < 0 || t.minute > 59) {
        return res.status(400).json({ error: "invalid time values" });
      }
    }
  }

  const clamp = (v: unknown, min: number, max: number, dflt: number) =>
    typeof v === "number" && Number.isFinite(v) ? Math.min(max, Math.max(min, Math.round(v))) : dflt;

  try {
    await db.collection("silent_alarm_schedules").doc(userId).set({
      enabled,
      times: enabled ? times.map((t: { hour: number; minute: number }) => ({ hour: t.hour, minute: t.minute })) : [],
      windowMinutes: clamp(windowMinutes, 5, 180, 30),
      gracePeriodMisses: clamp(gracePeriodMisses, 1, 10, 3),
      ...(typeof timeZone === "string" && timeZone.length <= 64 ? { timeZone } : {}),
      consecutiveMisses: 0,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return res.json({ success: true });
  } catch (error) {
    console.error("[SilentAlarm] schedule error:", error);
    return res.status(500).json({ error: "Failed to save the schedule" });
  }
});

// POST /v1/silent-alarm/confirm — User confirms they are safe
router.post("/confirm", authMiddleware, async (req: Request, res: Response) => {
  const userId = req.uid!;

  try {
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
      description: "Safety check-in confirmed",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    return res.json({ success: true });
  } catch (error) {
    console.error("[SilentAlarm] confirm error:", error);
    return res.status(500).json({ error: "Failed to confirm" });
  }
});

// GET /v1/silent-alarm — Get current schedule
router.get("/", authMiddleware, async (req: Request, res: Response) => {
  const userId = req.uid!;
  try {
    const doc = await db.collection("silent_alarm_schedules").doc(userId).get();

    if (!doc.exists) {
      return res.json({ enabled: false, times: [], windowMinutes: 30, gracePeriodMisses: 3 });
    }

    const d = doc.data()!;
    return res.json({
      enabled: d.enabled === true,
      times: d.times ?? [],
      windowMinutes: d.windowMinutes ?? 30,
      gracePeriodMisses: d.gracePeriodMisses ?? 3,
      consecutiveMisses: d.consecutiveMisses ?? 0,
    });
  } catch (error) {
    console.error("[SilentAlarm] get error:", error);
    return res.status(500).json({ error: "Failed to load the schedule" });
  }
});

export default router;
