import { recordSOSLocation } from "../services/sosTracking";
import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import { authMiddleware } from "../middleware/auth";
import { createRateLimiter, RATE_LIMITS } from "../middleware/rateLimit";
import {
  insertHeartbeat,
  insertLocationReport,
  insertCheckin,
} from "../services/bigquery";
import { v4 as uuidv4 } from "uuid";
import { sendHomeSafeNotification } from "../services/fcm";
import { hhmm } from "../services/localTime";

const router = Router();
const db = admin.firestore();

// This router is mounted at bare /v1: auth and the telemetry limiter are applied
// PER ROUTE. A router-level router.use() would run for every later /v1 route
// (Twilio callbacks, public share links, SOS) — 401s and a shared 429 bucket.
const telemetryLimit = createRateLimiter(RATE_LIMITS.telemetry);

/**
 * POST /v1/heartbeat
 * Record a heartbeat signal from the iOS client.
 * Written to BigQuery for time-series analysis.
 */
router.post("/heartbeat", authMiddleware, telemetryLimit, async (req: Request, res: Response) => {
  const {
    userId,
    timestamp,
    source,
    batteryLevel,
    batteryState,
    latitude,
    longitude,
    accuracy,
  } = req.body;

  if (!userId || !timestamp) {
    res.status(400).json({ error: "userId and timestamp are required" });
    return;
  }

  if (userId !== req.uid) {
    res.status(403).json({ error: "Cannot submit heartbeat for another user" });
    return;
  }

  // Real-time state in Firestore first (guardian dashboard, widget) — it must not
  // depend on BigQuery being reachable.
  try {
    await db.collection("user_telemetry").doc(userId).set(
      {
        ...(typeof batteryLevel === "number" && { batteryLevel }),
        ...(batteryState && { batteryState }),
        ...(typeof latitude === "number" && typeof longitude === "number" && {
          latitude,
          longitude,
          accuracy: typeof accuracy === "number" ? accuracy : null,
          locationTimestamp: admin.firestore.Timestamp.now(),
        }),
        lastHeartbeat: admin.firestore.Timestamp.now(),
      },
      { merge: true }
    );
  } catch (error) {
    console.warn("[Telemetry] user_telemetry heartbeat write failed:", error);
  }

  try {
    await insertHeartbeat({
      userId,
      timestamp,
      source: source || "unknown",
      batteryLevel,
      batteryState,
      latitude,
      longitude,
      accuracy,
    });
    res.json({ success: true });
  } catch (error) {
    console.error("[Telemetry] heartbeat insert error:", error);
    // Don't fail the request — heartbeats are best-effort
    res.json({ success: true, warning: "Queued for retry" });
  }
});

/**
 * POST /v1/location/report
 * Record a location report from the iOS client.
 * Written to BigQuery for time-series and trail reconstruction.
 */
router.post("/location/report", authMiddleware, telemetryLimit, async (req: Request, res: Response) => {
  const {
    userId,
    latitude,
    longitude,
    accuracy,
    altitude,
    speed,
    timestamp,
    isInSafeZone,
    safeZoneName,
    activityType,
    encryptedPayload,
  } = req.body;

  if (!userId || latitude === undefined || longitude === undefined) {
    res
      .status(400)
      .json({ error: "userId, latitude, and longitude are required" });
    return;
  }

  if (userId !== req.uid) {
    res.status(403).json({ error: "Cannot submit location for another user" });
    return;
  }

  try {
    await db.collection("user_telemetry").doc(userId).set(
      {
        latitude,
        longitude,
        accuracy: typeof accuracy === "number" ? accuracy : null,
        locationTimestamp: admin.firestore.Timestamp.now(),
      },
      { merge: true }
    );
  } catch (error) {
    console.warn("[Telemetry] user_telemetry location write failed:", error);
  }

  // During an SOS the guardians' map follows this position
  await recordSOSLocation(userId, latitude, longitude);

  try {
    await insertLocationReport({
      userId,
      latitude,
      longitude,
      accuracy: accuracy || 0,
      altitude,
      speed,
      timestamp: timestamp || new Date().toISOString(),
      isInSafeZone,
      safeZoneName,
      ...(activityType && { activityType }),
      ...(encryptedPayload && { encryptedPayload }),
    });

    res.json({ success: true });
  } catch (error) {
    console.error("[Telemetry] location insert error:", error);
    res.json({ success: true, warning: "Queued for retry" });
  }
});

/**
 * POST /v1/checkin
 * Record a check-in ("报平安") from the protected person.
 * Written to both Firestore (for real-time) and BigQuery (for history).
 */
router.post("/checkin", authMiddleware, telemetryLimit, async (req: Request, res: Response) => {
  const { userId, latitude, longitude, note } = req.body;

  if (!userId) {
    res.status(400).json({ error: "userId is required" });
    return;
  }

  if (userId !== req.uid) {
    res.status(403).json({ error: "Cannot submit checkin for another user" });
    return;
  }

  const now = new Date();
  const checkInId = uuidv4();

  try {
    // Write to Firestore for real-time status
    await db
      .collection("checkins")
      .doc(checkInId)
      .set({
        userId,
        timestamp: admin.firestore.Timestamp.fromDate(now),
        latitude: latitude || null,
        longitude: longitude || null,
        note: note || null,
      });

    // Write to BigQuery for history (non-blocking — table may not exist yet)
    try {
      await insertCheckin({
        userId,
        timestamp: now.toISOString(),
        latitude,
        longitude,
        note,
      });
    } catch (bqError) {
      console.warn("[Telemetry] BigQuery insertCheckin failed (non-fatal):", bqError);
    }

    // Add timeline entry
    await db.collection("timeline_entries").add({
      userId,
      timestamp: admin.firestore.Timestamp.fromDate(now),
      type: "checkIn",
      description: note || "报平安",
      detail: null,
    });

    // Tell the guardians ("Mom is home safe · Chengdu 18:58"), at most once per
    // person per 10 minutes so repeated taps / retried requests don't spam.
    let guardiansNotified = 0;
    try {
      guardiansNotified = await notifyGuardiansOfCheckin(userId, now, note);
    } catch (pushError) {
      console.error("[Telemetry] check-in push failed (non-fatal):", pushError);
    }

    res.json({
      checkInId,
      timestamp: now.toISOString(),
      guardiansNotified,
    });
  } catch (error) {
    console.error("[Telemetry] checkin error:", error);
    res.status(500).json({ error: "Failed to record check-in" });
  }
});

/**
 * POST /v1/location/pause
 * Protected person pauses / resumes location sharing (privacy). Max 4 hours;
 * an SOS always overrides a pause on the device.
 * Body: { userId, paused: boolean, expiresAt?: ISO }
 */
export const MAX_PAUSE_MS = 4 * 60 * 60 * 1000;

router.post("/location/pause", authMiddleware, telemetryLimit, async (req: Request, res: Response) => {
  const { userId, paused, expiresAt } = req.body;
  if (userId !== req.uid) {
    res.status(403).json({ error: "Cannot pause tracking for another user" });
    return;
  }
  if (typeof paused !== "boolean") {
    res.status(400).json({ error: "paused (boolean) is required" });
    return;
  }

  const now = Date.now();
  let until: Date | null = null;
  if (paused) {
    const requested = expiresAt ? new Date(expiresAt).getTime() : now + MAX_PAUSE_MS;
    if (isNaN(requested) || requested <= now) {
      res.status(400).json({ error: "expiresAt must be a future ISO timestamp" });
      return;
    }
    until = new Date(Math.min(requested, now + MAX_PAUSE_MS));
  }

  try {
    await db.collection("user_telemetry").doc(userId).set(
      {
        trackingPaused: paused,
        trackingPausedUntil: until ? admin.firestore.Timestamp.fromDate(until) : null,
      },
      { merge: true }
    );
    await db.collection("timeline_entries").add({
      userId,
      timestamp: admin.firestore.Timestamp.now(),
      type: paused ? "trackingPaused" : "trackingResumed",
      description: paused ? "暂停了位置共享" : "恢复了位置共享",
      detail: until ? until.toISOString() : null,
    });
    res.json({ success: true, pausedUntil: until ? until.toISOString() : null });
  } catch (error) {
    console.error("[Telemetry] location pause error:", error);
    res.status(500).json({ error: "Failed to update tracking pause" });
  }
});

export const CHECKIN_PUSH_DEDUPE_MS = 10 * 60 * 1000;

/** Returns how many guardians were pushed (0 when deduped). */
export async function notifyGuardiansOfCheckin(userId: string, now: Date, note?: string): Promise<number> {
  const telRef = db.collection("user_telemetry").doc(userId);
  const claimed = await db.runTransaction(async (tx) => {
    const tel = await tx.get(telRef);
    const last = tel.exists ? tel.data()?.lastCheckinPushAt?.toMillis?.() : undefined;
    if (last && now.getTime() - last < CHECKIN_PUSH_DEDUPE_MS) return false;
    tx.set(telRef, { lastCheckinPushAt: admin.firestore.Timestamp.fromDate(now) }, { merge: true });
    return true;
  });
  if (!claimed) return 0;

  const [userDoc, links] = await Promise.all([
    db.collection("users").doc(userId).get(),
    db.collection("guardian_links")
      .where("protectedPersonId", "==", userId)
      .where("status", "==", "active")
      .get(),
  ]);
  const user = userDoc.data() ?? {};
  const name = user.displayName || "";
  const city = user.cityName || "";
  const time = hhmm(now, user.timeZone);
  const cleanNote = typeof note === "string" && note.trim() && note.trim() !== "报平安" ? note.trim().slice(0, 80) : undefined;

  let sent = 0;
  for (const link of links.docs) {
    if (await sendHomeSafeNotification(link.data().guardianId, userId, name, city, time, cleanNote)) sent++;
  }
  return sent;
}

/**
 * POST /v1/location/batch
 * Accept an array of queued location reports (from offline queue).
 * Reduces round-trips when device comes back online after being
 * in a tunnel, airplane, or poor connectivity area.
 */
router.post("/location/batch", authMiddleware, telemetryLimit, async (req: Request, res: Response) => {
  const { reports } = req.body;

  if (!Array.isArray(reports) || reports.length === 0) {
    res.status(400).json({ error: "reports array is required" });
    return;
  }

  // Cap at 100 reports per batch to prevent abuse
  const batch = reports.slice(0, 100);
  let successCount = 0;
  let errorCount = 0;

  for (const report of batch) {
    const {
      userId, latitude, longitude, accuracy, altitude,
      speed, timestamp, isInSafeZone, safeZoneName,
      activityType, encryptedPayload,
    } = report;

    // Skip reports that don't belong to the authenticated user
    if (userId !== req.uid) {
      errorCount++;
      continue;
    }

    if (latitude === undefined || longitude === undefined) {
      errorCount++;
      continue;
    }

    try {
      await insertLocationReport({
        userId,
        latitude,
        longitude,
        accuracy: accuracy || 0,
        altitude,
        speed,
        timestamp: timestamp || new Date().toISOString(),
        isInSafeZone,
        safeZoneName,
        ...(activityType && { activityType }),
        ...(encryptedPayload && { encryptedPayload }),
      });
      successCount++;
    } catch (error) {
      errorCount++;
      // Continue processing — don't fail the whole batch
    }
  }

  // The newest point of the batch moves an open SOS (sent after a dead zone)
  const newest = batch.filter((r: any) => r.userId === req.uid && typeof r.latitude === "number")
    .sort((a: any, b: any) => Date.parse(a.timestamp ?? 0) - Date.parse(b.timestamp ?? 0)).pop();
  if (newest) {
    const at = Date.parse(newest.timestamp);
    await recordSOSLocation(req.uid!, newest.latitude, newest.longitude, Number.isFinite(at) ? new Date(at) : new Date());
  }

  res.json({ success: true, processed: successCount, errors: errorCount });
});

export default router;
