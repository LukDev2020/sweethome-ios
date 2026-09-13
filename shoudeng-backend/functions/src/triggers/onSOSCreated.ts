import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { sendSOSAlert } from "../services/fcm";
import { sendSOSSms, hasAppInstalled } from "../services/sms";

const db = admin.firestore();

/**
 * Firestore trigger: fires when a new SOS event is created.
 * Implements the 4-hop escalation chain:
 *   Hop 1 (0s):  Push to on-duty guardian
 *   Hop 2 (30s): Push to ALL guardians
 *   Hop 3 (90s): Twilio voice call loop
 *   Hop 4 (120s): Generate emergency share link
 */
export const onSOSCreated = functions
  .runWith({ timeoutSeconds: 300, memory: "512MB" })
  .firestore.document("sos_events/{sosId}")
  .onCreate(async (snapshot, context) => {
    const sosId = context.params.sosId;
    const sosData = snapshot.data();
    const protectedPersonId = sosData.protectedPersonId;

    console.log(
      `[Escalation] SOS ${sosId} created for person ${protectedPersonId}`
    );

    // Fetch protected person's name
    const userDoc = await db
      .collection("users")
      .doc(protectedPersonId)
      .get();
    const personName = userDoc.exists
      ? userDoc.data()!.displayName
      : "被守护者";

    // Find all guardians
    const linksSnapshot = await db
      .collection("guardian_links")
      .where("protectedPersonId", "==", protectedPersonId)
      .where("status", "==", "active")
      .get();

    if (linksSnapshot.empty) {
      console.warn(
        `[Escalation] No guardians found for person ${protectedPersonId}`
      );
      return;
    }

    const guardianIds = linksSnapshot.docs.map(
      (doc) => doc.data().guardianId
    );

    // Find on-duty guardians
    const now = new Date();
    const currentHour = now.getHours();
    const currentDay = now.getDay() || 7;

    const onDutyGuardians: string[] = [];
    for (const gid of guardianIds) {
      const schedules = await db
        .collection("duty_schedules")
        .where("guardianId", "==", gid)
        .where("protectedPersonId", "==", protectedPersonId)
        .where("isActive", "==", true)
        .where("dayOfWeek", "==", currentDay)
        .get();

      let isOnDuty = false;
      if (schedules.empty) {
        // No schedule = always on duty
        isOnDuty = true;
      } else {
        for (const doc of schedules.docs) {
          const s = doc.data();
          if (currentHour >= s.startHour && currentHour < s.endHour) {
            isOnDuty = true;
            break;
          }
        }
      }

      if (isOnDuty) onDutyGuardians.push(gid);
    }

    // === HOP 1: Notify on-duty guardian(s) immediately ===
    console.log(
      `[Escalation] Hop 1: Notifying ${onDutyGuardians.length} on-duty guardians`
    );

    const hop1Targets =
      onDutyGuardians.length > 0 ? onDutyGuardians : [guardianIds[0]];

    for (const guardianId of hop1Targets) {
      await sendSOSAlert(guardianId, personName, sosId);

      // Log to escalation_log
      await snapshot.ref.update({
        escalationState: "hop1_notified",
        escalationLog: admin.firestore.FieldValue.arrayUnion({
          hop: 1,
          targetId: guardianId,
          sentAt: admin.firestore.Timestamp.now(),
          deliveredAt: null,
          readAt: null,
          respondedAt: null,
          response: null,
        }),
      });
    }

    // === HOP 2: Schedule notification to ALL guardians after 30s ===
    // Using setTimeout in Cloud Functions (runs in same execution if under 9 min limit)
    await delay(30000);

    // Re-check if SOS is still active (guardian may have responded)
    const refreshed = await snapshot.ref.get();
    const refreshedData = refreshed.data();
    if (
      !refreshedData ||
      refreshedData.resolvedAt ||
      refreshedData.escalationState === "frozen"
    ) {
      console.log("[Escalation] SOS already resolved/frozen before Hop 2");
      return;
    }

    console.log(
      `[Escalation] Hop 2: Notifying ALL ${guardianIds.length} guardians`
    );

    for (const guardianId of guardianIds) {
      // Send push notification
      await sendSOSAlert(guardianId, personName, sosId);

      // SMS fallback for guardians who don't have the app installed
      const hasApp = await hasAppInstalled(guardianId);
      if (!hasApp) {
        await sendSOSSms(guardianId, personName, sosId);
        console.log(`[Escalation] SMS fallback sent to ${guardianId} (no app)`);
      }

      await snapshot.ref.update({
        escalationState: "hop2_allNotified",
        escalationLog: admin.firestore.FieldValue.arrayUnion({
          hop: 2,
          targetId: guardianId,
          sentAt: admin.firestore.Timestamp.now(),
          deliveredAt: null,
          readAt: null,
          respondedAt: null,
          response: null,
          channel: hasApp ? "push" : "sms",
        }),
      });
    }

    // === HOP 3: Voice call after another 60s ===
    await delay(60000);

    const refreshed2 = await snapshot.ref.get();
    const refreshedData2 = refreshed2.data();
    if (
      !refreshedData2 ||
      refreshedData2.resolvedAt ||
      refreshedData2.escalationState === "frozen"
    ) {
      console.log("[Escalation] SOS already resolved/frozen before Hop 3");
      return;
    }

    console.log("[Escalation] Hop 3: Initiating voice calls");

    try {
      const { initiateVoiceCall } = await import("../services/twilio");
      const callbackUrl = `https://${process.env.GCLOUD_PROJECT}.cloudfunctions.net/api/v1/voice-callback`;

      for (const guardianId of hop1Targets) {
        const callSid = await initiateVoiceCall(
          guardianId,
          sosId,
          personName,
          callbackUrl
        );
        if (callSid) {
          await snapshot.ref.update({
            escalationState: "hop3_voiceCalling",
            escalationLog: admin.firestore.FieldValue.arrayUnion({
              hop: 3,
              targetId: guardianId,
              sentAt: admin.firestore.Timestamp.now(),
              deliveredAt: null,
              readAt: null,
              respondedAt: null,
              response: null,
            }),
          });
        }
      }
    } catch (error) {
      console.error("[Escalation] Hop 3 voice call failed:", error);
      await snapshot.ref.update({
        escalationState: "hop3_exhausted",
      });
    }

    // === HOP 4: Generate emergency share link after another 30s ===
    await delay(30000);

    const refreshed3 = await snapshot.ref.get();
    const refreshedData3 = refreshed3.data();
    if (
      !refreshedData3 ||
      refreshedData3.resolvedAt ||
      refreshedData3.escalationState === "frozen"
    ) {
      console.log("[Escalation] SOS resolved/frozen before Hop 4");
      return;
    }

    console.log("[Escalation] Hop 4: Generating emergency share link");

    try {
      const { createShareToken } = await import("../services/evidence");
      const token = await createShareToken({
        protectedPersonId,
        createdBy: "system_escalation",
        expiresInHours: 48,
      });
      console.log(`[Escalation] Emergency share token created: ${token}`);
    } catch (error) {
      console.error("[Escalation] Hop 4 share link creation failed:", error);
    }
  });

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
