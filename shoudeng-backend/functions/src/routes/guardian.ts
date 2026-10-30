import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import { authMiddleware } from "../middleware/auth";
import { getLatestHeartbeat } from "../services/bigquery";
import { toIso } from "../services/time";
import { activeSOSDoc, sosStatus, SOSStatus } from "../services/escalation";
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
        // One person with bad data must not blank the whole dashboard.
        try {
          const row = await loadPersonStatus(personId, link);
          if (row) result.push(row);
        } catch (err) {
          console.error(`[Guardian] status for ${personId} failed:`, err);
        }
      }

      res.json(result);
    } catch (error) {
      console.error("[Guardian] fetch protected persons error:", error);
      res.status(500).json({ error: "Failed to fetch protected persons" });
    }
  }
);

async function loadPersonStatus(
  personId: string,
  link: admin.firestore.DocumentData
): Promise<ProtectedPersonStatus | null> {
  const userDoc = await db.collection("users").doc(personId).get();
  if (!userDoc.exists) return null;
  const user = userDoc.data()!;

  // Count protection layers (number of active guardians)
  const guardianCount = await db
    .collection("guardian_links")
    .where("protectedPersonId", "==", personId)
    .where("status", "==", "active")
    .count()
    .get();

  // Real-time telemetry (Firestore) first; BigQuery history as fallback.
  const telemetryDoc = await db.collection("user_telemetry").doc(personId).get();
  const telemetry = telemetryDoc.exists ? telemetryDoc.data()! : null;
  let heartbeat: Record<string, unknown> | null = null;
  if (!telemetry?.lastHeartbeat) {
    try {
      heartbeat = await getLatestHeartbeat(personId);
    } catch (err) {
      console.warn(`[Guardian] BigQuery heartbeat lookup failed for ${personId}:`, err);
    }
  }

  const checkinSnapshot = await db
    .collection("checkins")
    .where("userId", "==", personId)
    .orderBy("timestamp", "desc")
    .limit(1)
    .get();
  const lastCheckIn = checkinSnapshot.empty
    ? null
    : toIso(checkinSnapshot.docs[0].data().timestamp);

  const sosDoc = await activeSOSDoc(personId);
  const activeSOS = sosDoc ? await sosStatus(sosDoc) : null;

  const row = await buildPersonStatus({
    personId,
    user,
    permissions: link.permissions,
    telemetry,
    heartbeat,
    lastCheckIn,
    protectionLayers: guardianCount.data().count,
    reverseGeocode,
  });
  return {
    ...row,
    // An active SOS overrides every other status
    status: activeSOS ? "alert" : row.status,
    activeSOS,
  };
}

/**
 * GET /v1/guardian/sos/active?personId=
 * The protected person's unresolved SOS (location, battery, escalation step,
 * who acknowledged, elapsed time) for GuardianAlertResponseView.
 * Requires an active guardian link.
 */
router.get("/sos/active", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const personId = typeof req.query.personId === "string" ? req.query.personId : "";
  if (!personId) {
    res.status(400).json({ error: "personId is required" });
    return;
  }
  try {
    const link = await db.collection("guardian_links").doc(`${uid}_${personId}`).get();
    if (!link.exists || link.data()?.status !== "active") {
      res.status(403).json({ error: "No active guardian link for this person" });
      return;
    }
    const doc = await activeSOSDoc(personId);
    if (!doc) {
      res.json({ active: false, sos: null });
      return;
    }
    const sos = await sosStatus(doc);
    // Location is shared during an SOS only if the person allows this guardian to see it
    if (link.data()?.permissions?.canSeeLocation === false) {
      sos.latitude = null;
      sos.longitude = null;
    }
    res.json({ active: true, sos });
  } catch (error) {
    console.error("[Guardian] active SOS error:", error);
    res.status(500).json({ error: "Failed to load SOS" });
  }
});

/** Shape decoded by iOS `ProtectedPersonStatusResponse` (see ContractFixtures). */
export interface ProtectedPersonStatus {
  personId: string;
  displayName: string;
  status: string;
  latitude: number | null;
  longitude: number | null;
  locationTimestamp: string | null;
  locationAddress: string | null;
  locationAccuracy: number | null;
  batteryLevel: number | null;
  batteryState: string;
  lastCheckIn: string | null;
  lastPhoneActivity: string | null;
  protectionLayers: number;
  timeZoneId: string | null;
  countryCode: string | null;
  cityName: string | null;
  activeSOS?: SOSStatus | null;
}

const num = (v: unknown): number | null =>
  typeof v === "number" && isFinite(v) ? v : null;

export async function buildPersonStatus(input: {
  personId: string;
  user: admin.firestore.DocumentData;
  permissions?: Record<string, unknown>;
  telemetry: admin.firestore.DocumentData | null;
  heartbeat: Record<string, unknown> | null;
  lastCheckIn: string | null;
  protectionLayers: number;
  reverseGeocode: (lat: number, lng: number) => Promise<string | null>;
  now?: Date;
}): Promise<ProtectedPersonStatus> {
  const { user, telemetry, heartbeat } = input;
  const canSeeLocation = input.permissions?.canSeeLocation !== false;
  const canSeeBattery = input.permissions?.canSeeBattery !== false;
  const canSeePhoneActivity = input.permissions?.canSeePhoneActivity !== false;

  const lastHeartbeat = toIso(telemetry?.lastHeartbeat) ?? toIso(heartbeat?.timestamp);
  const lat = num(telemetry?.latitude) ?? num(heartbeat?.latitude);
  const lng = num(telemetry?.longitude) ?? num(heartbeat?.longitude);
  const locationTimestamp =
    toIso(telemetry?.locationTimestamp) ?? (lat != null ? lastHeartbeat : null);
  const accuracy = num(telemetry?.accuracy) ?? num(heartbeat?.accuracy);
  const batteryLevel = num(telemetry?.batteryLevel) ?? num(heartbeat?.battery_level);
  const batteryState =
    (telemetry?.batteryState as string) ?? (heartbeat?.battery_state as string) ?? "unknown";

  const status = computeSafetyStatus(
    input.lastCheckIn ? new Date(input.lastCheckIn) : null,
    lastHeartbeat ? new Date(lastHeartbeat) : null,
    input.now
  );

  const showLocation = canSeeLocation && lat != null && lng != null;
  let address: string | null = null;
  if (showLocation) {
    try {
      address = await input.reverseGeocode(lat!, lng!);
    } catch {
      address = null;
    }
  }

  return {
    personId: input.personId,
    displayName: String(user.displayName ?? ""),
    status,
    latitude: showLocation ? lat : null,
    longitude: showLocation ? lng : null,
    locationTimestamp: showLocation ? locationTimestamp : null,
    locationAddress: address,
    locationAccuracy: showLocation ? accuracy : null,
    batteryLevel: canSeeBattery ? batteryLevel : null,
    batteryState: canSeeBattery ? batteryState : "unknown",
    lastCheckIn: input.lastCheckIn,
    lastPhoneActivity: canSeePhoneActivity ? lastHeartbeat : null,
    protectionLayers: input.protectionLayers,
    timeZoneId: user.timeZone ?? null,
    countryCode: user.countryCode ?? null,
    cityName: user.cityName ?? null,
  };
}

/**
 * Compute safety status based on check-in and heartbeat recency.
 */
export function computeSafetyStatus(
  lastCheckIn: Date | null,
  lastHeartbeat: Date | null,
  nowDate?: Date
): string {
  const now = (nowDate ?? new Date()).getTime();

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
