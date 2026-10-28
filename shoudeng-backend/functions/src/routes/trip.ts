import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import { authMiddleware } from "../middleware/auth";
import { v4 as uuidv4 } from "uuid";

const router = Router();
const db = admin.firestore();

router.use(authMiddleware);

/**
 * POST /v1/trip/start
 * Start a new trip recording.
 */
router.post("/start", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const tripId = uuidv4();
  const now = admin.firestore.Timestamp.now();

  try {
    await db.collection("trips").doc(tripId).set({
      userId: uid,
      status: "recording",
      startTime: now,
      endTime: null,
      totalDistanceMeters: 0,
      pointCount: 0,
      durationSeconds: 0,
      primaryTransportMode: null,
      segments: [],
      createdAt: now,
    });

    res.status(201).json({
      tripId,
      startTime: now.toDate().toISOString(),
    });
  } catch (error) {
    console.error("[Trip] start error:", error);
    res.status(500).json({ error: "Failed to start trip" });
  }
});

/**
 * POST /v1/trip/:tripId/points
 * Add GPS points to an active trip.
 */
router.post("/:tripId/points", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { tripId } = req.params;
  const { points } = req.body;

  if (!Array.isArray(points) || points.length === 0) {
    res.status(400).json({ error: "points array is required" });
    return;
  }

  try {
    // Verify trip ownership
    const tripDoc = await db.collection("trips").doc(tripId).get();
    if (!tripDoc.exists || tripDoc.data()?.userId !== uid) {
      res.status(404).json({ error: "Trip not found" });
      return;
    }
    if (tripDoc.data()?.status !== "recording") {
      res.status(400).json({ error: "Trip is not recording" });
      return;
    }

    // Batch write points (cap at 100 per request)
    const batch = db.batch();
    const capped = points.slice(0, 100);
    for (const point of capped) {
      const pointRef = db.collection("trips").doc(tripId).collection("points").doc();
      batch.set(pointRef, {
        latitude: point.latitude,
        longitude: point.longitude,
        accuracy: point.accuracy || 0,
        altitude: point.altitude || null,
        speed: point.speed || null,
        timestamp: point.timestamp || new Date().toISOString(),
        activityType: point.activityType || null,
      });
    }

    // Update point count on trip doc
    batch.update(db.collection("trips").doc(tripId), {
      pointCount: admin.firestore.FieldValue.increment(capped.length),
    });

    await batch.commit();
    res.json({ success: true, added: capped.length });
  } catch (error) {
    console.error("[Trip] add points error:", error);
    res.status(500).json({ error: "Failed to add points" });
  }
});

/**
 * POST /v1/trip/:tripId/end
 * End a recording trip. Calculates summary stats.
 */
router.post("/:tripId/end", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { tripId } = req.params;

  try {
    const tripRef = db.collection("trips").doc(tripId);
    const tripDoc = await tripRef.get();
    if (!tripDoc.exists || tripDoc.data()?.userId !== uid) {
      res.status(404).json({ error: "Trip not found" });
      return;
    }
    if (tripDoc.data()?.status !== "recording") {
      res.status(400).json({ error: "Trip is not recording" });
      return;
    }

    const tripData = tripDoc.data()!;
    const now = admin.firestore.Timestamp.now();
    const startTime = tripData.startTime.toDate();
    const durationSeconds = (now.toDate().getTime() - startTime.getTime()) / 1000;

    // Fetch all points to compute distance and segments
    const pointsSnap = await tripRef.collection("points")
      .orderBy("timestamp", "asc")
      .get();

    let totalDistance = 0;
    let prevLat = 0, prevLng = 0;
    const speeds: number[] = [];

    pointsSnap.docs.forEach((doc, i) => {
      const p = doc.data();
      if (i > 0) {
        const d = haversine(prevLat, prevLng, p.latitude, p.longitude);
        totalDistance += d;
      }
      prevLat = p.latitude;
      prevLng = p.longitude;
      if (p.speed != null && p.speed >= 0) speeds.push(p.speed);
    });

    // Infer primary transport mode from average speed
    const avgSpeed = speeds.length > 0
      ? speeds.reduce((a, b) => a + b, 0) / speeds.length
      : 0;
    const avgSpeedKmh = avgSpeed * 3.6;
    let primaryMode = "stationary";
    if (avgSpeedKmh > 80) primaryMode = "driving";
    else if (avgSpeedKmh > 15) primaryMode = "cycling";
    else if (avgSpeedKmh > 1) primaryMode = "walking";

    await tripRef.update({
      status: "completed",
      endTime: now,
      totalDistanceMeters: Math.round(totalDistance),
      durationSeconds: Math.round(durationSeconds),
      primaryTransportMode: primaryMode,
    });

    res.json({
      tripId,
      totalDistanceMeters: Math.round(totalDistance),
      pointCount: pointsSnap.size,
      durationSeconds: Math.round(durationSeconds),
    });
  } catch (error) {
    console.error("[Trip] end error:", error);
    res.status(500).json({ error: "Failed to end trip" });
  }
});

/**
 * POST /v1/trip/:tripId/cancel
 * Cancel a recording trip.
 */
router.post("/:tripId/cancel", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { tripId } = req.params;

  try {
    const tripRef = db.collection("trips").doc(tripId);
    const tripDoc = await tripRef.get();
    if (!tripDoc.exists || tripDoc.data()?.userId !== uid) {
      res.status(404).json({ error: "Trip not found" });
      return;
    }

    await tripRef.update({
      status: "cancelled",
      endTime: admin.firestore.Timestamp.now(),
    });

    res.json({ success: true });
  } catch (error) {
    console.error("[Trip] cancel error:", error);
    res.status(500).json({ error: "Failed to cancel trip" });
  }
});

/**
 * GET /v1/trip/list
 * List trips for current user or a linked protected person.
 */
router.get("/list", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const targetUserId = (req.query.userId as string) || uid;

  try {
    // If querying another user's trips, verify guardian relationship
    if (targetUserId !== uid) {
      const linkId = `${uid}_${targetUserId}`;
      const linkDoc = await db.collection("guardian_links").doc(linkId).get();
      if (!linkDoc.exists || linkDoc.data()?.status !== "active") {
        res.status(403).json({ error: "Not authorized to view this user's trips" });
        return;
      }
    }

    const tripsSnap = await db.collection("trips")
      .where("userId", "==", targetUserId)
      .where("status", "in", ["completed", "recording"])
      .orderBy("startTime", "desc")
      .limit(50)
      .get();

    const trips = tripsSnap.docs.map(doc => {
      const d = doc.data();
      return {
        id: doc.id,
        userId: d.userId,
        status: d.status,
        startTime: d.startTime?.toDate().toISOString(),
        endTime: d.endTime?.toDate().toISOString() || null,
        totalDistanceMeters: d.totalDistanceMeters || 0,
        pointCount: d.pointCount || 0,
        durationSeconds: d.durationSeconds || 0,
        primaryTransportMode: d.primaryTransportMode || null,
      };
    });

    res.json({ trips });
  } catch (error) {
    console.error("[Trip] list error:", error);
    res.status(500).json({ error: "Failed to list trips" });
  }
});

/**
 * GET /v1/trip/:tripId
 * Get trip detail with all points.
 */
router.get("/:tripId", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { tripId } = req.params;

  try {
    const tripDoc = await db.collection("trips").doc(tripId).get();
    if (!tripDoc.exists) {
      res.status(404).json({ error: "Trip not found" });
      return;
    }

    const tripData = tripDoc.data()!;

    // Check access: owner or linked guardian
    if (tripData.userId !== uid) {
      const linkId = `${uid}_${tripData.userId}`;
      const linkDoc = await db.collection("guardian_links").doc(linkId).get();
      if (!linkDoc.exists || linkDoc.data()?.status !== "active") {
        res.status(403).json({ error: "Not authorized" });
        return;
      }
    }

    // Fetch points
    const pointsSnap = await db.collection("trips").doc(tripId)
      .collection("points")
      .orderBy("timestamp", "asc")
      .get();

    const points = pointsSnap.docs.map(doc => doc.data());

    const trip = {
      id: tripDoc.id,
      userId: tripData.userId,
      status: tripData.status,
      startTime: tripData.startTime?.toDate().toISOString(),
      endTime: tripData.endTime?.toDate().toISOString() || null,
      totalDistanceMeters: tripData.totalDistanceMeters || 0,
      pointCount: tripData.pointCount || 0,
      durationSeconds: tripData.durationSeconds || 0,
      primaryTransportMode: tripData.primaryTransportMode || null,
    };

    res.json({ trip, points, segments: tripData.segments || [] });
  } catch (error) {
    console.error("[Trip] detail error:", error);
    res.status(500).json({ error: "Failed to get trip" });
  }
});

/**
 * GET /v1/trip/:tripId/export
 * Export trip as GPX format.
 */
router.get("/:tripId/export", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { tripId } = req.params;

  try {
    const tripDoc = await db.collection("trips").doc(tripId).get();
    if (!tripDoc.exists) {
      res.status(404).json({ error: "Trip not found" });
      return;
    }

    const tripData = tripDoc.data()!;

    // Check access
    if (tripData.userId !== uid) {
      const linkId = `${uid}_${tripData.userId}`;
      const linkDoc = await db.collection("guardian_links").doc(linkId).get();
      if (!linkDoc.exists || linkDoc.data()?.status !== "active") {
        res.status(403).json({ error: "Not authorized" });
        return;
      }
    }

    const pointsSnap = await db.collection("trips").doc(tripId)
      .collection("points")
      .orderBy("timestamp", "asc")
      .get();

    const startDate = tripData.startTime?.toDate().toISOString().split("T")[0] || "trip";

    let gpx = `<?xml version="1.0" encoding="UTF-8"?>\n`;
    gpx += `<gpx version="1.1" creator="Lantern Care">\n`;
    gpx += `  <trk>\n    <name>Trip ${startDate}</name>\n    <trkseg>\n`;

    for (const doc of pointsSnap.docs) {
      const p = doc.data();
      gpx += `      <trkpt lat="${p.latitude}" lon="${p.longitude}">\n`;
      if (p.altitude != null) gpx += `        <ele>${p.altitude}</ele>\n`;
      if (p.timestamp) gpx += `        <time>${p.timestamp}</time>\n`;
      if (p.speed != null) gpx += `        <speed>${p.speed}</speed>\n`;
      gpx += `      </trkpt>\n`;
    }

    gpx += `    </trkseg>\n  </trk>\n</gpx>`;

    res.set("Content-Type", "application/gpx+xml");
    res.set("Content-Disposition", `attachment; filename="trip-${startDate}.gpx"`);
    res.send(gpx);
  } catch (error) {
    console.error("[Trip] export error:", error);
    res.status(500).json({ error: "Failed to export trip" });
  }
});

// Haversine distance in meters
function haversine(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371000;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

export default router;
