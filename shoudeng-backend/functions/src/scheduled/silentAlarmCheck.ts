import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { sendPushToUser } from "../services/push";
import { PUSH_SECRETS } from "../config/params";

import { localTime } from "../services/localTime";
import { alertCopyFor, nameOr } from "../services/pushCopy";

const db = admin.firestore();

/**
 * Runs every 5 minutes. For each enabled silent alarm schedule,
 * checks if a check-in was due and not confirmed within the window.
 * If consecutiveMisses >= gracePeriodMisses, escalates to guardians.
 */
export const checkSilentAlarms = functions
  .runWith({ secrets: PUSH_SECRETS })
  .pubsub
  .schedule("every 5 minutes")
  .onRun(async () => {
    const now = new Date();

    const schedulesSnapshot = await db
      .collection("silent_alarm_schedules")
      .where("enabled", "==", true)
      .get();

    for (const doc of schedulesSnapshot.docs) {
      const data = doc.data();
      const userId = doc.id;
      const times: { hour: number; minute: number }[] = data.times || [];
      const windowMinutes: number = data.windowMinutes || 30;
      const gracePeriodMisses: number = data.gracePeriodMisses || 3;
      const consecutiveMisses: number = data.consecutiveMisses || 0;

      // Scheduled times are the user's wall-clock times; the server runs in UTC.
      const tz = data.timeZone ?? (await db.collection("users").doc(userId).get()).data()?.timeZone;
      const lt = localTime(now, tz);
      const currentHour = lt.hour;
      const currentMinute = lt.minute;

      // Check if any scheduled time has passed within the last window
      for (const t of times) {
        const scheduledMinutes = t.hour * 60 + t.minute;
        const nowMinutes = currentHour * 60 + currentMinute;
        // Minutes since the most recent occurrence of this time (a window that
        // runs past midnight, e.g. 23:45 + 30 min, is still measured correctly)
        const elapsed = (((nowMinutes - scheduledMinutes) % 1440) + 1440) % 1440;

        // Check if we're past the window end (scheduled time + window)
        if (elapsed >= windowMinutes && elapsed < windowMinutes + 5) {
          // Window just closed — check if user confirmed
          const lastConfirmed = data.lastConfirmedAt?.toDate();
          // Scheduled instant = now minus the elapsed local minutes
          const windowStart = new Date(now.getTime() - elapsed * 60 * 1000);
          windowStart.setSeconds(0, 0);

          const confirmed = lastConfirmed && lastConfirmed >= windowStart;

          if (!confirmed) {
            const newMisses = consecutiveMisses + 1;
            await doc.ref.update({ consecutiveMisses: newMisses });

            // Log the miss
            await db.collection("timeline_entries").add({
              userId,
              type: "silent_alarm_missed",
              description: `Silent alarm check-in missed (${newMisses}/${gracePeriodMisses})`,
              timestamp: admin.firestore.FieldValue.serverTimestamp(),
            });

            if (newMisses >= gracePeriodMisses) {
              // ESCALATE: notify all guardians
              console.log(`[SilentAlarm] Escalating for user ${userId} — ${newMisses} consecutive misses`);
              await escalateToGuardians(userId);
              // Reset counter after escalation
              await doc.ref.update({ consecutiveMisses: 0 });
            }
          }
        }

        // Check if a check-in is due now (within 2 minutes of scheduled time)
        if (elapsed >= 0 && elapsed < 5) {
          // Send silent push to trigger local notification
          await sendCheckInPush(userId);
        }
      }
    }
  });

async function sendCheckInPush(userId: string): Promise<void> {
  await sendPushToUser(userId, {
    data: { action: "silent_alarm_checkin" },
    aps: { "content-available": 1 },
  }, "silent alarm check-in");
}

async function escalateToGuardians(userId: string): Promise<void> {
  const linksSnapshot = await db
    .collection("guardian_links")
    .where("protectedPersonId", "==", userId)
    .where("status", "==", "active")
    .get();

  if (linksSnapshot.empty) {
    console.warn(`[SilentAlarm] No guardians found for user ${userId}`);
    return;
  }

  const userDoc = await db.collection("users").doc(userId).get();
  const userName = userDoc.data()?.displayName;

  for (const linkDoc of linksSnapshot.docs) {
    const guardianId = linkDoc.data().guardianId;
    const copy = await alertCopyFor(guardianId);
    await sendPushToUser(guardianId, {
      notification: {
        title: copy.silentAlarmTitle,
        body: copy.silentAlarmBody(nameOr(userName, copy)),
      },
      data: {
        action: "silent_alarm_escalation",
        protectedPersonId: userId,
      },
    }, "silent alarm escalation");
  }

  // Log escalation
  await db.collection("timeline_entries").add({
    userId,
    type: "silent_alarm_escalated",
    description: (await alertCopyFor(userId)).silentAlarmTimeline,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });
}
