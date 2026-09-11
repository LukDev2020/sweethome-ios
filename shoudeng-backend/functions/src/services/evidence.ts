import * as admin from "firebase-admin";
import * as crypto from "crypto";
import { v4 as uuidv4 } from "uuid";
import { queryLocations, queryHeartbeats } from "./bigquery";
import { insertConsentAudit } from "./bigquery";

const db = admin.firestore();

/**
 * Generate an evidence bundle for a protected person within a time window.
 * Returns structured data that can be rendered as PDF/JSON/GPX by the caller.
 */
export async function generateEvidenceBundle(params: {
  protectedPersonId: string;
  timeWindowStart: string;
  timeWindowEnd: string;
  format: "pdf" | "json" | "gpx";
  requestedBy: string;
  reason: string;
}): Promise<{
  bundleId: string;
  user: Record<string, unknown> | null;
  locations: Record<string, unknown>[];
  heartbeats: Record<string, unknown>[];
  sosEvents: Record<string, unknown>[];
  timeline: Record<string, unknown>[];
  integrityProofs: Record<string, unknown>[];
  generatedAt: string;
}> {
  const bundleId = uuidv4();

  // Fetch user profile
  const userDoc = await db
    .collection("users")
    .doc(params.protectedPersonId)
    .get();
  const user = userDoc.exists ? userDoc.data() ?? null : null;

  // Fetch location trail from BigQuery
  const locations = await queryLocations(
    params.protectedPersonId,
    params.timeWindowStart,
    params.timeWindowEnd
  );

  // Fetch heartbeat signals from BigQuery
  const heartbeats = await queryHeartbeats(
    params.protectedPersonId,
    params.timeWindowStart,
    params.timeWindowEnd
  );

  // Fetch SOS events from Firestore
  const sosSnapshot = await db
    .collection("sos_events")
    .where("protectedPersonId", "==", params.protectedPersonId)
    .where(
      "triggeredAt",
      ">=",
      admin.firestore.Timestamp.fromDate(new Date(params.timeWindowStart))
    )
    .where(
      "triggeredAt",
      "<=",
      admin.firestore.Timestamp.fromDate(new Date(params.timeWindowEnd))
    )
    .get();
  const sosEvents = sosSnapshot.docs.map((d) => ({ id: d.id, ...d.data() }));

  // Fetch timeline entries
  const timelineSnapshot = await db
    .collection("timeline_entries")
    .where("userId", "==", params.protectedPersonId)
    .where(
      "timestamp",
      ">=",
      admin.firestore.Timestamp.fromDate(new Date(params.timeWindowStart))
    )
    .where(
      "timestamp",
      "<=",
      admin.firestore.Timestamp.fromDate(new Date(params.timeWindowEnd))
    )
    .orderBy("timestamp", "desc")
    .get();
  const timeline = timelineSnapshot.docs.map((d) => ({
    id: d.id,
    ...d.data(),
  }));

  // Fetch integrity proofs for covered dates
  const startDate = params.timeWindowStart.substring(0, 10);
  const endDate = params.timeWindowEnd.substring(0, 10);
  const proofsSnapshot = await db
    .collection("integrity_proofs")
    .where("date", ">=", startDate)
    .where("date", "<=", endDate)
    .get();
  const integrityProofs = proofsSnapshot.docs.map((d) => ({
    id: d.id,
    ...d.data(),
  }));

  // Log this access in consent audit
  await insertConsentAudit({
    userId: params.protectedPersonId,
    consentType: "data_export",
    action: "exported",
    grantedTo: params.requestedBy,
    detail: `Evidence bundle ${bundleId} generated: ${params.reason}, format: ${params.format}`,
  });

  return {
    bundleId,
    user,
    locations,
    heartbeats,
    sosEvents,
    timeline,
    integrityProofs,
    generatedAt: new Date().toISOString(),
  };
}

/**
 * Generate a GPX track from location data.
 */
export function generateGPX(
  locations: Record<string, unknown>[],
  personName: string
): string {
  const trackPoints = locations
    .map((loc) => {
      const lat = loc.latitude;
      const lon = loc.longitude;
      const ele = loc.altitude ?? 0;
      const time = loc.timestamp;
      return `      <trkpt lat="${lat}" lon="${lon}">
        <ele>${ele}</ele>
        <time>${time}</time>
      </trkpt>`;
    })
    .join("\n");

  return `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="ShouDeng Safety App"
     xmlns="http://www.topografix.com/GPX/1/1">
  <metadata>
    <name>${personName} - 位置轨迹</name>
    <time>${new Date().toISOString()}</time>
  </metadata>
  <trk>
    <name>${personName}</name>
    <trkseg>
${trackPoints}
    </trkseg>
  </trk>
</gpx>`;
}

/**
 * Create a time-limited share token for emergency data sharing.
 * Returns a token that can be used to access data without authentication.
 */
export async function createShareToken(params: {
  protectedPersonId: string;
  createdBy: string;
  expiresInHours: number;
}): Promise<string> {
  const token = crypto.randomBytes(32).toString("hex");

  await db.collection("evidence_shares").doc(token).set({
    protectedPersonId: params.protectedPersonId,
    createdBy: params.createdBy,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: admin.firestore.Timestamp.fromDate(
      new Date(Date.now() + params.expiresInHours * 60 * 60 * 1000)
    ),
    accessCount: 0,
    maxAccess: 10,
  });

  // Log in consent audit
  await insertConsentAudit({
    userId: params.protectedPersonId,
    consentType: "data_export",
    action: "accessed",
    grantedTo: "public_share",
    detail: `Share token created by ${params.createdBy}, expires in ${params.expiresInHours}h`,
  });

  return token;
}
