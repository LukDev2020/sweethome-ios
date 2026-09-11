import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { getLatestHeartbeat } from "../services/bigquery";
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
        const userId = userDoc.id;
        const userName = userDoc.data().displayName;

        // Get latest heartbeat from BigQuery
        const latest = await getLatestHeartbeat(userId);

        if (!latest || !latest.timestamp) {
          // No heartbeat ever recorded — skip (might be new user)
          continue;
        }

        const lastTime = new Date(String(latest.timestamp));
        const minutesAgo = (Date.now() - lastTime.getTime()) / (1000 * 60);

        if (minutesAgo > HEARTBEAT_MISSING_THRESHOLD_MIN) {
          console.log(
            `[Scheduled] Heartbeat missing for ${userName} (${Math.round(minutesAgo)} min)`
          );

          // Find guardians
          const linksSnapshot = await db
            .collection("guardian_links")
            .where("protectedPersonId", "==", userId)
            .where("status", "==", "active")
            .get();

          for (const linkDoc of linksSnapshot.docs) {
            const guardianId = linkDoc.data().guardianId;
            await sendHeartbeatMissingAlert(
              guardianId,
              userName,
              Math.round(minutesAgo)
            );
          }
        }
      }
    } catch (error) {
      console.error("[Scheduled] Heartbeat check error:", error);
    }
  });
