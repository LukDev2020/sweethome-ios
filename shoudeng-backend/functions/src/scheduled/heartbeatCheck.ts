import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { getLatestHeartbeat, bqTimestampToIso } from "../services/bigquery";
import { sendHeartbeatMissingAlert } from "../services/fcm";

const db = admin.firestore();

// Threshold in minutes before alerting guardians
const HEARTBEAT_MISSING_THRESHOLD_MIN = 30;

/**
 * Scheduled function: runs every 5 minutes.
 * Checks for protected persons whose heartbeat is missing beyond threshold.
 * Sends alert to their guardians.
 */
export const checkHeartbeatMissing = functions.pubsub
  .schedule("every 5 minutes")
  .onRun(async () => {
    console.log("[Scheduled] Running heartbeat missing check");

    try {
      // Get all protected users
      const usersSnapshot = await db
        .collection("users")
        .where("role", "==", "protected")
        .get();

      for (const userDoc of usersSnapshot.docs) {
        try {
          await checkUser(userDoc.id, userDoc.data().displayName);
        } catch (err) {
          console.error(`[Scheduled] Heartbeat check failed for ${userDoc.id}:`, err);
        }
      }
    } catch (error) {
      console.error("[Scheduled] Heartbeat check error:", error);
    }
  });

/**
 * Returns the ISO time of the user's last heartbeat: Firestore real-time
 * telemetry first, BigQuery history as fallback.
 */
export async function lastHeartbeatIso(userId: string): Promise<string | null> {
  const tel = await db.collection("user_telemetry").doc(userId).get();
  const fromFirestore = tel.exists ? tel.data()?.lastHeartbeat : null;
  if (fromFirestore?.toDate) return fromFirestore.toDate().toISOString();
  const latest = await getLatestHeartbeat(userId);
  return bqTimestampToIso(latest?.timestamp);
}

export async function checkUser(
  userId: string,
  userName: string,
  now: Date = new Date()
): Promise<boolean> {
  const lastIso = await lastHeartbeatIso(userId);
  // No heartbeat ever recorded — skip (might be new user)
  if (!lastIso) return false;

  const minutesAgo = (now.getTime() - new Date(lastIso).getTime()) / (1000 * 60);
  if (!(minutesAgo > HEARTBEAT_MISSING_THRESHOLD_MIN)) return false;

  // Alert once per silent period, not every 5 minutes.
  const telRef = db.collection("user_telemetry").doc(userId);
  const tel = await telRef.get();
  if (tel.exists && tel.data()?.heartbeatAlertedFor === lastIso) return false;

  console.log(
    `[Scheduled] Heartbeat missing for ${userName} (${Math.round(minutesAgo)} min)`
  );

  const linksSnapshot = await db
    .collection("guardian_links")
    .where("protectedPersonId", "==", userId)
    .where("status", "==", "active")
    .get();

  for (const linkDoc of linksSnapshot.docs) {
    await sendHeartbeatMissingAlert(
      linkDoc.data().guardianId,
      userName,
      Math.round(minutesAgo)
    );
  }
  await telRef.set({ heartbeatAlertedFor: lastIso }, { merge: true });
  return true;
}
