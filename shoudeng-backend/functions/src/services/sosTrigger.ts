import * as admin from "firebase-admin";
import { v4 as uuidv4 } from "uuid";
import { initialEscalationFields } from "./escalation";

// ---------------------------------------------------------------------------
// Creating an SOS
// ---------------------------------------------------------------------------
//
// One path for every SOS: the phone (POST /v1/sos/trigger) and the server's own
// fallbacks (a fall nobody answered — safetyEvents.ts). While an SOS is open a new
// trigger joins it instead of starting a second one, and the device-side ids are
// remembered, so a phone and the server firing for the same fall end up as one SOS.
// onSOSCreated starts the escalation to guardians.

export const CLIENT_ID_RE = /^[A-Za-z0-9-]{8,64}$/;

export interface SOSTriggerInput {
  personId: string;
  triggerMethod?: unknown;
  latitude?: unknown;
  longitude?: unknown;
  batteryLevel?: unknown;
  clientSOSId?: unknown;
  clientTriggeredAt?: unknown;
}

export interface SOSTriggerResult {
  sosEventId: string;
  escalationState: string;
  /** false when an SOS was already open and this trigger joined it */
  created: boolean;
}

export async function createSOSEvent(input: SOSTriggerInput): Promise<SOSTriggerResult> {
  const db = admin.firestore();
  const { personId, triggerMethod, latitude, longitude, batteryLevel, clientSOSId, clientTriggeredAt } = input;
  const clientId = typeof clientSOSId === "string" && CLIENT_ID_RE.test(clientSOSId) ? clientSOSId : null;
  const method = typeof triggerMethod === "string" ? triggerMethod.slice(0, 40) : "longPress";
  const sosId = uuidv4();
  const now = admin.firestore.Timestamp.now();

  const existing = await db.runTransaction(async (tx) => {
    const active = await tx.get(
      db.collection("sos_events")
        .where("protectedPersonId", "==", personId)
        .where("resolvedAt", "==", null)
        .limit(1)
    );
    if (!active.empty) {
      const doc = active.docs[0];
      // Remember this device-side id too, so a later resolve sent with it maps here
      if (clientId) {
        tx.update(doc.ref, { clientSOSIds: admin.firestore.FieldValue.arrayUnion(clientId) });
      }
      return { sosEventId: doc.id, escalationState: doc.data().escalationState as string };
    }
    tx.set(db.collection("sos_events").doc(sosId), {
      protectedPersonId: personId,
      triggeredAt: now,
      createdAt: now,
      triggerMethod: method,
      latitude: typeof latitude === "number" ? latitude : null,
      longitude: typeof longitude === "number" ? longitude : null,
      accuracy: null,
      batteryLevel: typeof batteryLevel === "number" && batteryLevel >= 0 ? batteryLevel : null,
      resolvedAt: null,
      resolvedBy: null,
      resolution: null,
      acknowledgedBy: null,
      clientSOSIds: clientId ? [clientId] : [],
      clientTriggeredAt: typeof clientTriggeredAt === "string" ? clientTriggeredAt.slice(0, 40) : null,
      ...initialEscalationFields(now),
    });
    return null;
  });

  if (existing) return { ...existing, created: false };

  // Informational, outside the transaction
  await db.collection("timeline_entries").add({
    userId: personId,
    timestamp: now,
    type: "sosTriggered",
    description: `SOS triggered (${method})`,
    detail: null,
  });
  return { sosEventId: sosId, escalationState: "initiated", created: true };
}
