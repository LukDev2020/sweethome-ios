import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { initialEscalationFields, runEscalationInline } from "../services/escalation";

/**
 * Firestore trigger: a new SOS event starts the escalation state machine
 * (see services/escalation.ts). The steps run inline while this instance is
 * alive; the advanceEscalations scheduler takes over for anything still due
 * after the budget, after a crash, or when this trigger is re-delivered —
 * step claims make re-delivery harmless.
 */
export const onSOSCreated = functions
  .runWith({ timeoutSeconds: 300, memory: "512MB" })
  .firestore.document("sos_events/{sosId}")
  .onCreate(async (snapshot, context) => {
    const sosId = context.params.sosId;
    const data = snapshot.data();
    console.log(`[Escalation] SOS ${sosId} created for person ${data.protectedPersonId}`);

    // Documents created by older clients/paths may lack the state-machine fields
    if (data.escalationNextStep === undefined) {
      const init = initialEscalationFields(data.triggeredAt ?? admin.firestore.Timestamp.now());
      await snapshot.ref.update({
        escalationNextStep: init.escalationNextStep,
        escalationNextAt: init.escalationNextAt,
        escalationLeaseUntil: null,
        escalationSent: data.escalationSent ?? {},
      });
    }

    // Leave headroom under the 300 s function timeout
    await runEscalationInline(sosId, 270_000);
  });
