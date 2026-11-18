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

/** An open SOS older than this no longer absorbs a new press */
export const SOS_JOIN_WINDOW_MS = 30 * 60 * 1000;

/**
 * Whether an open SOS is finished in all but name: its escalation ran out (or
 * there was nobody to escalate to), or it is older than the join window.
 * A new trigger then starts a fresh SOS instead of silently joining this one.
 */
export function isStaleSOS(data: admin.firestore.DocumentData, nowMs: number): boolean {
  if (data.escalationState === "exhausted" || data.escalationState === "no_guardians") return true;
  const at = data.triggeredAt as { toMillis?: () => number } | undefined;
  const triggeredMs = at && typeof at.toMillis === "function" ? at.toMillis() : nowMs;
  return nowMs - triggeredMs > SOS_JOIN_WINDOW_MS;
}

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
      const data = doc.data();
      const sameTrigger = clientId !== null && Array.isArray(data.clientSOSIds) && data.clientSOSIds.includes(clientId);
      if (sameTrigger || !isStaleSOS(data, now.toMillis())) {
        // Remember this device-side id too, so a later resolve sent with it maps here
        if (clientId && !sameTrigger) {
          tx.update(doc.ref, { clientSOSIds: admin.firestore.FieldValue.arrayUnion(clientId) });
        }
        return { sosEventId: doc.id, escalationState: data.escalationState as string };
      }
      // An old SOS nobody closed (escalation finished, or a guardian said
      // "I've got it" long ago): a new press is a new emergency and must alert
      // everyone again, so close the old one and fall through to a fresh SOS.
      tx.update(doc.ref, {
        resolvedAt: now,
        resolvedBy: "system",
        resolution: "timeout",
        escalationNextStep: null,
        escalationNextAt: null,
        escalationLeaseUntil: null,
      });
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

  // "I've crashed — hurt": the crash report may have reached the server first
  const linkCrash = async (sosEventId: string) => {
    if (method !== "crashReport" || !clientId) return;
    const crash = db.collection("safety_events").doc(`${personId}_${clientId}`);
    try {
      const snap = await crash.get();
      if (snap.exists && !snap.data()?.sosEventId) await crash.update({ sosEventId });
    } catch (error) {
      console.warn("[SOS] crash report link failed:", (error as Error).message);
    }
  };

  if (existing) {
    await linkCrash(existing.sosEventId);
    return { ...existing, created: false };
  }
  await linkCrash(sosId);

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
