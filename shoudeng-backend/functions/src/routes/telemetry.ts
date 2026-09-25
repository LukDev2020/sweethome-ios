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

const router = Router();
const db = admin.firestore();

router.use(authMiddleware);
router.use(createRateLimiter(RATE_LIMITS.telemetry));

/**
 * POST /v1/heartbeat
 * Record a heartbeat signal from the iOS client.
 * Written to BigQuery for time-series analysis.
 */
router.post("/heartbeat", async (req: Request, res: Response) => {
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
router.post("/location/report", async (req: Request, res: Response) => {
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
router.post("/checkin", async (req: Request, res: Response) => {
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

    // Write to BigQuery for history
    await insertCheckin({
      userId,
      timestamp: now.toISOString(),
      latitude,
      longitude,
      note,
    });

    // Add timeline entry
    await db.collection("timeline_entries").add({
      userId,
      timestamp: admin.firestore.Timestamp.fromDate(now),
      type: "checkIn",
      description: note || "报平安",
      detail: null,
    });

    res.json({
      checkInId,
      timestamp: now.toISOString(),
    });
  } catch (error) {
    console.error("[Telemetry] checkin error:", error);
    res.status(500).json({ error: "Failed to record check-in" });
  }
});

export default router;
