import * as admin from "firebase-admin";
import { createSOSEvent, CLIENT_ID_RE } from "./sosTrigger";

/**
 * The safety timer ("dead man's switch") on the server.
 *
 * The phone runs the countdown and raises the SOS itself when it can. But iOS may
 * kill or suspend the app, and the battery may die — exactly the cases the timer is
 * for. So the phone also keeps its deadline here, and if it passes without a
 * check-in, this side raises the SOS. The phone's own SOS (same clientSOSId) and
 * this one land on the same SOS event, so nobody is alerted twice.
 *
 * safety_timers/{uid}: { status: "active"|"cancelled"|"fired", deadline, clientSOSId,
 *   latitude, longitude, batteryLevel, updatedAt, firedAt?, sosEventId? }
 */

/** Head start for the phone's own SOS before the server steps in */
export const SAFETY_TIMER_GRACE_MS = 60_000;
/** Longest timer the app offers is a few hours; refuse anything silly */
export const SAFETY_TIMER_MAX_MS = 24 * 60 * 60 * 1000;

const db = () => admin.firestore();
const COLLECTION = "safety_timers";

export class SafetyTimerError extends Error {
  constructor(public status: number, message: string) { super(message); }
}

function num(v: unknown, min: number, max: number): number | null {
  return typeof v === "number" && Number.isFinite(v) && v >= min && v <= max ? v : null;
}

/**
 * Set (start / extend / resume) or clear (check-in / cancel / pause) the deadline.
 * body: { deadline: ISO string | null, clientSOSId?, latitude?, longitude?, batteryLevel? }
 */
export async function setSafetyTimer(uid: string, body: Record<string, unknown>, now = Date.now()) {
  const ref = db().collection(COLLECTION).doc(uid);
  const ts = admin.firestore.Timestamp;
  if (body.deadline === null || body.deadline === undefined) {
    // Only an active timer is cleared: a timer that already fired stays "fired"
    await db().runTransaction(async (tx) => {
      const cur = (await tx.get(ref)).data();
      if (cur?.status === "active") tx.update(ref, { status: "cancelled", updatedAt: ts.fromMillis(now) });
    });
    return { active: false };
  }
  if (typeof body.deadline !== "string") throw new SafetyTimerError(400, "deadline must be an ISO 8601 string or null");
  const deadline = Date.parse(body.deadline);
  if (!Number.isFinite(deadline)) throw new SafetyTimerError(400, "deadline must be an ISO 8601 string or null");
  if (deadline <= now) throw new SafetyTimerError(400, "deadline must be in the future");
  if (deadline - now > SAFETY_TIMER_MAX_MS) throw new SafetyTimerError(400, "deadline is too far away");
  const clientSOSId = typeof body.clientSOSId === "string" && CLIENT_ID_RE.test(body.clientSOSId)
    ? body.clientSOSId : null;
  await ref.set({
    userId: uid,
    status: "active",
    deadline: ts.fromMillis(deadline),
    clientSOSId,
    latitude: num(body.latitude, -90, 90),
    longitude: num(body.longitude, -180, 180),
    batteryLevel: num(body.batteryLevel, 0, 1),
    updatedAt: ts.fromMillis(now),
    firedAt: null,
    sosEventId: null,
  });
  return { active: true, deadline: new Date(deadline).toISOString() };
}

/** Scheduler (every minute): timers past deadline + grace become an SOS. */
export async function escalateExpiredSafetyTimers(now = Date.now()): Promise<number> {
  const due = await db().collection(COLLECTION)
    .where("status", "==", "active")
    .where("deadline", "<=", admin.firestore.Timestamp.fromMillis(now - SAFETY_TIMER_GRACE_MS))
    .limit(50)
    .get();
  let fired = 0;
  for (const doc of due.docs) {
    // Claim it first: a late check-in may land meanwhile
    const claimed = await db().runTransaction(async (tx) => {
      const fresh = (await tx.get(doc.ref)).data();
      if (fresh?.status !== "active") return null;
      tx.update(doc.ref, { status: "fired", firedAt: admin.firestore.Timestamp.fromMillis(now) });
      return fresh;
    });
    if (!claimed) continue;
    try {
      const sos = await createSOSEvent({
        personId: claimed.userId,
        triggerMethod: "deadManSwitch",
        latitude: claimed.latitude ?? undefined,
        longitude: claimed.longitude ?? undefined,
        batteryLevel: claimed.batteryLevel ?? undefined,
        clientSOSId: claimed.clientSOSId ?? undefined,
      });
      await doc.ref.update({ sosEventId: sos.sosEventId });
      fired++;
      console.warn(`[SafetyTimer] ${claimed.userId}: no check-in by the deadline, server raised SOS ${sos.sosEventId}`);
    } catch (error) {
      // Give it back so the next run tries again
      console.error("[SafetyTimer] server SOS failed:", error);
      await doc.ref.update({ status: "active", firedAt: null }).catch(() => undefined);
    }
  }
  return fired;
}
