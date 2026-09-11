import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { sendCheckinReminder } from "../services/fcm";

const db = admin.firestore();

// Default check-in interval (hours) — can be per-user configurable later
const CHECKIN_OVERDUE_HOURS = 8;

/**
 * Scheduled function: runs every 15 minutes.
 * Checks for protected persons who haven't checked in within threshold.
 * Sends reminder to their guardians.
 */
export const checkCheckinOverdue = functions.pubsub
  .schedule("every 15 minutes")
  .onRun(async () => {
    console.log("[Scheduled] Running check-in overdue check");

    try {
      const cutoff = admin.firestore.Timestamp.fromDate(
        new Date(Date.now() - CHECKIN_OVERDUE_HOURS * 60 * 60 * 1000)
      );

      // Get all protected users
      const usersSnapshot = await db
        .collection("users")
        .where("role", "==", "protected")
        .get();

      for (const userDoc of usersSnapshot.docs) {
        const userId = userDoc.id;
        const userName = userDoc.data().displayName;

        // Get latest check-in
        const checkinSnapshot = await db
          .collection("checkins")
          .where("userId", "==", userId)
          .orderBy("timestamp", "desc")
          .limit(1)
          .get();

        let isOverdue = false;
        if (checkinSnapshot.empty) {
          // Never checked in — overdue if account is older than threshold
          const createdAt = userDoc.data().createdAt;
          if (createdAt && createdAt.toDate() < cutoff.toDate()) {
            isOverdue = true;
          }
        } else {
          const lastCheckin = checkinSnapshot.docs[0].data().timestamp;
          if (lastCheckin.toDate() < cutoff.toDate()) {
            isOverdue = true;
          }
        }

        if (isOverdue) {
          console.log(`[Scheduled] Check-in overdue for ${userName}`);

          // Add timeline entry (only once — check if already added today)
          const todayStart = new Date();
          todayStart.setHours(0, 0, 0, 0);

          const existingEntry = await db
            .collection("timeline_entries")
            .where("userId", "==", userId)
            .where("type", "==", "missedCheckIn")
            .where(
              "timestamp",
              ">=",
              admin.firestore.Timestamp.fromDate(todayStart)
            )
            .limit(1)
            .get();

          if (existingEntry.empty) {
            await db.collection("timeline_entries").add({
              userId,
              timestamp: admin.firestore.Timestamp.now(),
              type: "missedCheckIn",
              description: "超时未报平安",
              detail: null,
            });
          }

          // Notify guardians
          const linksSnapshot = await db
            .collection("guardian_links")
            .where("protectedPersonId", "==", userId)
            .where("status", "==", "active")
            .get();

          for (const linkDoc of linksSnapshot.docs) {
            const guardianId = linkDoc.data().guardianId;
            await sendCheckinReminder(guardianId, userName);
          }
        }
      }
    } catch (error) {
      console.error("[Scheduled] Check-in overdue check error:", error);
    }
  });
