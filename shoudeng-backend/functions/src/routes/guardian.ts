import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import { authMiddleware } from "../middleware/auth";
import { getLatestHeartbeat } from "../services/bigquery";
import { reverseGeocode } from "../services/geocoding";

const router = Router();
const db = admin.firestore();

router.use(authMiddleware);

/**
 * GET /v1/guardian/protected-persons
 * Get all protected persons that this guardian is watching, with their current status.
 * This is the main data source for GuardianHomeView.
 */
router.get(
  "/protected-persons",
  async (req: Request, res: Response) => {
    const uid = req.uid!;

    try {
      // Find all active guardian links where this user is the guardian
      const linksSnapshot = await db
        .collection("guardian_links")
        .where("guardianId", "==", uid)
        .where("status", "==", "active")
        .get();

      if (linksSnapshot.empty) {
        res.json([]);
        return;
      }

      const result = [];

      for (const linkDoc of linksSnapshot.docs) {
        const link = linkDoc.data();
        const personId = link.protectedPersonId;

        // Fetch user profile
        const userDoc = await db.collection("users").doc(personId).get();
        if (!userDoc.exists) continue;
        const user = userDoc.data()!;

        // Count protection layers (number of active guardians)
        const guardianCount = await db
          .collection("guardian_links")
          .where("protectedPersonId", "==", personId)
          .where("status", "==", "active")
          .count()
          .get();

        // Get latest heartbeat from BigQuery
        const latestHeartbeat = await getLatestHeartbeat(personId);

        // Get latest check-in from Firestore
        const checkinSnapshot = await db
          .collection("checkins")
          .where("userId", "==", personId)
          .orderBy("timestamp", "desc")
          .limit(1)
          .get();
        const lastCheckIn = checkinSnapshot.empty
          ? null
          : checkinSnapshot.docs[0].data().timestamp.toDate().toISOString();

        // Check location permission granted by protected person
        const canSeeLocation = link.permissions?.canSeeLocation !== false;

        // Get latest location from BigQuery heartbeat
        const lat = latestHeartbeat?.latitude ?? null;
        const lng = latestHeartbeat?.longitude ?? null;
        const locationTimestamp = latestHeartbeat?.timestamp ?? null;

        // Compute safety status
        const status = computeSafetyStatus(
          lastCheckIn ? new Date(lastCheckIn) : null,
          latestHeartbeat?.timestamp
            ? new Date(String(latestHeartbeat.timestamp))
            : null
        );

        result.push({
          personId,
          displayName: user.displayName,
          status,
          latitude: canSeeLocation ? (lat as number | null) : null,
          longitude: canSeeLocation ? (lng as number | null) : null,
          locationTimestamp: canSeeLocation ? locationTimestamp : null,
          locationAddress:
            canSeeLocation && lat != null && lng != null
              ? await reverseGeocode(lat as number, lng as number)
              : null,
          locationAccuracy: canSeeLocation
            ? ((latestHeartbeat?.accuracy as number) ?? null)
            : null,
          batteryLevel: (latestHeartbeat?.battery_level as number) ?? null,
          batteryState: (latestHeartbeat?.battery_state as string) ?? "unknown",
          lastCheckIn,
          lastPhoneActivity: latestHeartbeat?.timestamp
            ? String(latestHeartbeat.timestamp)
            : null,
          protectionLayers: guardianCount.data().count,
          timeZoneId: user.timeZone ?? null,
          countryCode: user.countryCode ?? null,
          cityName: user.cityName ?? null,
        });
      }

      res.json(result);
    } catch (error) {
      console.error("[Guardian] fetch protected persons error:", error);
      res.status(500).json({ error: "Failed to fetch protected persons" });
    }
  }
);

/**
 * Compute safety status based on check-in and heartbeat recency.
 */
function computeSafetyStatus(
  lastCheckIn: Date | null,
  lastHeartbeat: Date | null
): string {
  const now = Date.now();

  // No data at all
  if (!lastCheckIn && !lastHeartbeat) return "unreachable";

  // Check heartbeat (phone connectivity)
  if (lastHeartbeat) {
    const heartbeatAge = now - lastHeartbeat.getTime();
    // No heartbeat for 30+ minutes → unreachable
    if (heartbeatAge > 30 * 60 * 1000) return "unreachable";
  }

  // Check check-in recency
  if (lastCheckIn) {
    const checkinAge = now - lastCheckIn.getTime();
    if (checkinAge > 8 * 60 * 60 * 1000) return "overdue"; // 8 hours
    if (checkinAge > 6 * 60 * 60 * 1000) return "pendingCheckIn"; // 6 hours
  } else {
    // Never checked in
    return "pendingCheckIn";
  }

  return "normal";
}

export default router;
