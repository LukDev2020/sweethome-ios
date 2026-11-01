import * as admin from "firebase-admin";

/**
 * Fair use of SOS SMS and voice calls (docs/pricing/PRICING.md): SMS fallback and voice
 * escalation are part of every plan, up to this much per protected person per calendar
 * month (UTC). Beyond it, escalation goes on with push notifications only — the SOS
 * itself, its push alerts, and texts to emergency contacts when nobody else can be
 * reached are never blocked.
 *
 * Usage lives in sos_usage/{personId}_{YYYY-MM}: smsCount, voiceMinutes.
 * A call reserves 1 minute when it is placed; the Twilio status callback settles it to
 * the billed minutes (rounded up, 0 when unanswered) — see settleVoiceCall.
 */
export const FAIR_USE = {
  smsPerMonth: 50,
  voiceMinutesPerMonth: 30,
} as const;

const db = admin.firestore();
const USAGE = "sos_usage";

/** "2026-11" — calendar month in UTC */
export function usageMonth(d: Date = new Date()): string {
  return d.toISOString().slice(0, 7);
}

function usageRef(personId: string, month: string) {
  return db.collection(USAGE).doc(`${personId}_${month}`);
}

/** Take `count` SMS from this month's allowance; false (nothing taken) if it would go over. */
export async function reserveSms(personId: string, count = 1, now: Date = new Date()): Promise<boolean> {
  const month = usageMonth(now);
  const ref = usageRef(personId, month);
  return db.runTransaction(async (tx) => {
    const used = Number((await tx.get(ref)).data()?.smsCount ?? 0);
    if (used + count > FAIR_USE.smsPerMonth) return false;
    tx.set(ref, {
      personId, month,
      smsCount: used + count,
      updatedAt: admin.firestore.Timestamp.now(),
    }, { merge: true });
    return true;
  });
}

/** Count SMS that are sent regardless of the cap (emergency contacts when there are no guardians). */
export async function recordSms(personId: string, count = 1, now: Date = new Date()): Promise<void> {
  const month = usageMonth(now);
  await usageRef(personId, month).set({
    personId, month,
    smsCount: admin.firestore.FieldValue.increment(count),
    updatedAt: admin.firestore.Timestamp.now(),
  }, { merge: true });
}

export interface VoiceReservation { personId: string; month: string }

/** Reserve one minute for a call about to be placed; null when the month's minutes are used up. */
export async function reserveVoiceMinute(personId: string, now: Date = new Date()): Promise<VoiceReservation | null> {
  const month = usageMonth(now);
  const ref = usageRef(personId, month);
  return db.runTransaction(async (tx) => {
    const used = Number((await tx.get(ref)).data()?.voiceMinutes ?? 0);
    if (used + 1 > FAIR_USE.voiceMinutesPerMonth) return null;
    tx.set(ref, {
      personId, month,
      voiceMinutes: used + 1,
      updatedAt: admin.firestore.Timestamp.now(),
    }, { merge: true });
    return { personId, month };
  });
}

/** Give back a reservation whose call was never placed. */
export async function releaseVoiceMinute(r: VoiceReservation): Promise<void> {
  await usageRef(r.personId, r.month).set({
    voiceMinutes: admin.firestore.FieldValue.increment(-1),
    updatedAt: admin.firestore.Timestamp.now(),
  }, { merge: true });
}

/** Billed minutes of a finished call: answered calls round up, others are free. */
export function billedMinutes(status: string, durationSeconds: number): number {
  if (status !== "completed" || !(durationSeconds > 0)) return 0;
  return Math.ceil(durationSeconds / 60);
}

const FINAL_STATUSES = new Set(["completed", "busy", "failed", "no-answer", "canceled"]);

/**
 * Twilio status callback for a call placed with a reservation: replace the reserved
 * minute with the billed minutes. Settles each call once.
 */
export async function settleVoiceCall(callSid: string, status: string, durationSeconds: number): Promise<void> {
  if (!FINAL_STATUSES.has(status)) return;
  const callRef = db.collection("voice_calls").doc(callSid);
  await db.runTransaction(async (tx) => {
    const call = (await tx.get(callRef)).data();
    const r = call?.fairUse as VoiceReservation | undefined;
    if (!r || call?.fairUseSettled) return;
    const delta = billedMinutes(status, durationSeconds) - 1;
    if (delta !== 0) {
      tx.set(usageRef(r.personId, r.month), {
        voiceMinutes: admin.firestore.FieldValue.increment(delta),
        updatedAt: admin.firestore.Timestamp.now(),
      }, { merge: true });
    }
    tx.update(callRef, { fairUseSettled: true });
  });
}
