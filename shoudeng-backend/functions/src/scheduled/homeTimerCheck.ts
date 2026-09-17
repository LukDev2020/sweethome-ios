import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

const db = admin.firestore();

/**
 * Scheduled function: runs every 1 minute.
 * Checks for expired home timers and sends escalation notifications to guardians.
 */
export const checkHomeTimerExpiry = functions.pubsub
  .schedule("every 1 minutes")
  .onRun(async () => {
    try {
      const now = admin.firestore.Timestamp.now();

      // Find all active timers that have passed their deadline
      const expiredSnapshot = await db
        .collection("home_timers")
        .where("status", "==", "active")
        .where("deadline", "<=", now)
        .get();

      for (const timerDoc of expiredSnapshot.docs) {
        const timer = timerDoc.data();
        const userId = timer.userId;

        // Mark as escalated
        await timerDoc.ref.update({
          status: "escalated",
          escalatedAt: now,
        });

        // Add timeline entry
        await db.collection("timeline_entries").add({
          userId,
          timestamp: now,
          type: "homeTimerExpired",
          description: `回家计时超时：${timer.label}`,
          detail: null,
        });

        // Get user info
        const userDoc = await db.collection("users").doc(userId).get();
        const userName = userDoc.exists
          ? userDoc.data()!.displayName
          : "被守护者";

        // Notify all guardians
        const linksSnapshot = await db
          .collection("guardian_links")
          .where("protectedPersonId", "==", userId)
          .where("status", "==", "active")
          .get();

        for (const linkDoc of linksSnapshot.docs) {
          const guardianId = linkDoc.data().guardianId;

          const tokenSnapshot = await db
            .collection("device_tokens")
            .where("userId", "==", guardianId)
            .get();

          const tokens = tokenSnapshot.docs.map((d) => d.data().token);
          if (tokens.length > 0) {
            try {
              await admin.messaging().sendEachForMulticast({
                tokens,
                notification: {
                  title: "回家计时超时",
                  body: `${userName}设置的「${timer.label}」计时已到期，但未关闭`,
                },
                apns: {
                  headers: { "apns-priority": "10" },
                  payload: {
                    aps: {
                      sound: "default",
                      "interruption-level": "time-sensitive",
                    },
                  },
                },
                data: {
                  action: "home_timer_expired",
                  userId,
                },
              });
            } catch (e) {
              console.error(
                `[HomeTimer] Failed to notify guardian ${guardianId}:`,
                e
              );
            }
          }
        }

        console.log(
          `[HomeTimer] Timer expired for ${userName}, notified ${linksSnapshot.size} guardians`
        );
      }
    } catch (error) {
      console.error("[HomeTimer] Scheduled check error:", error);
    }
  });
