import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { sendPushToUser } from "../services/push";
import { PUSH_SECRETS } from "../config/params";
import { checkOverdueShifts, checkStillOk } from "../services/crew";
import { escalateUnansweredFalls } from "../services/safetyEvents";
import { alertCopyFor, nameOr } from "../services/pushCopy";

const db = admin.firestore();

/**
 * Scheduled function: runs every 1 minute.
 * Checks for expired home timers and sends escalation notifications to guardians.
 */
export const checkHomeTimerExpiry = functions
  .runWith({ secrets: PUSH_SECRETS })
  .pubsub
  .schedule("every 1 minutes")
  .onRun(async () => {
    // Rider shifts past their planned end without a check-in (same 1-minute cadence)
    try {
      await checkOverdueShifts();
    } catch (error) {
      console.error("[Crew] shift check failed:", error);
    }
    // "Still OK?" during night shifts
    try {
      await checkStillOk();
    } catch (error) {
      console.error("[Crew] still-OK check failed:", error);
    }
    // A detected fall the phone never answered (locked face-down, app killed, battery dead)
    try {
      await escalateUnansweredFalls();
    } catch (error) {
      console.error("[Fall] unanswered fall check failed:", error);
    }
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
        const userName = userDoc.data()?.displayName;

        // Notify all guardians
        const linksSnapshot = await db
          .collection("guardian_links")
          .where("protectedPersonId", "==", userId)
          .where("status", "==", "active")
          .get();

        for (const linkDoc of linksSnapshot.docs) {
          const guardianId = linkDoc.data().guardianId;
          const copy = await alertCopyFor(guardianId);
          await sendPushToUser(guardianId, {
            notification: {
              title: copy.homeTimerOverdueTitle,
              body: copy.homeTimerOverdueBody(nameOr(userName, copy), timer.label || undefined),
            },
            priority: 10,
            aps: {
              sound: "default",
              "interruption-level": "time-sensitive",
            },
            data: {
              action: "home_timer_expired",
              userId,
            },
          }, "home timer expired");
        }

        console.log(
          `[HomeTimer] Timer expired for ${userName}, notified ${linksSnapshot.size} guardians`
        );
      }
    } catch (error) {
      console.error("[HomeTimer] Scheduled check error:", error);
    }
  });
