import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

const db = admin.firestore();

/**
 * Runs every 5 minutes. For each enabled silent alarm schedule,
 * checks if a check-in was due and not confirmed within the window.
 * If consecutiveMisses >= gracePeriodMisses, escalates to guardians.
 */
export const checkSilentAlarms = functions.pubsub
  .schedule("every 5 minutes")
  .onRun(async () => {
    const now = new Date();
    const currentHour = now.getHours();
    const currentMinute = now.getMinutes();

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

      // Check if any scheduled time has passed within the last window
      for (const t of times) {
        const scheduledMinutes = t.hour * 60 + t.minute;
        const nowMinutes = currentHour * 60 + currentMinute;
        const elapsed = nowMinutes - scheduledMinutes;

        // Check if we're past the window end (scheduled time + window)
        if (elapsed >= windowMinutes && elapsed < windowMinutes + 5) {
          // Window just closed — check if user confirmed
          const lastConfirmed = data.lastConfirmedAt?.toDate();
          const windowStart = new Date(now);
          windowStart.setHours(t.hour, t.minute, 0, 0);

          const confirmed = lastConfirmed && lastConfirmed >= windowStart;

          if (!confirmed) {
            const newMisses = consecutiveMisses + 1;
            await doc.ref.update({ consecutiveMisses: newMisses });

            // Log the miss
            await db.collection("timeline_entries").add({
              userId,
              type: "silent_alarm_missed",
              description: `沉默报警签到未确认 (${newMisses}/${gracePeriodMisses})`,
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
  const tokensSnapshot = await db
    .collection("device_tokens")
    .where("userId", "==", userId)
    .get();

  const tokens = tokensSnapshot.docs.map((d) => d.data().token);
  if (tokens.length === 0) return;

  try {
    await admin.messaging().sendEachForMulticast({
      tokens,
      data: { action: "silent_alarm_checkin" },
      apns: {
        payload: { aps: { "content-available": 1 } },
      },
    });
  } catch (err) {
    console.error(`[SilentAlarm] Failed to send check-in push to ${userId}:`, err);
  }
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
  const userName = userDoc.exists ? userDoc.data()!.displayName : "被守护者";

  for (const linkDoc of linksSnapshot.docs) {
    const guardianId = linkDoc.data().guardianId;
    const tokensSnapshot = await db
      .collection("device_tokens")
      .where("userId", "==", guardianId)
      .get();

    const tokens = tokensSnapshot.docs.map((d) => d.data().token);
    if (tokens.length === 0) continue;

    try {
      await admin.messaging().sendEachForMulticast({
        tokens,
        notification: {
          title: "沉默报警触发",
          body: `${userName}连续多次未确认安全签到，请立即确认其状况。`,
        },
        data: {
          action: "silent_alarm_escalation",
          protectedPersonId: userId,
        },
      });
    } catch (err) {
      console.error(`[SilentAlarm] Failed to notify guardian ${guardianId}:`, err);
    }
  }

  // Log escalation
  await db.collection("timeline_entries").add({
    userId,
    type: "silent_alarm_escalated",
    description: "沉默报警已升级，已通知所有守护者",
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });
}
