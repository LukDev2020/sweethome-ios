import * as admin from "firebase-admin";
import { createSOSEvent, CLIENT_ID_RE } from "./sosTrigger";
import { activeGuardianIds } from "./sosTracking";
import { sendFallDismissed } from "./fcm";

// ---------------------------------------------------------------------------
// Safety events: detected falls
// ---------------------------------------------------------------------------
//
// When the phone detects a fall it asks "Are you OK?" for 60 s, and tells the server
// straight away (outcome "pending", escalateAt = now + countdown). Then either:
//  - the person taps "I'm OK" → "dismissed" (guardians get a quiet note);
//  - the countdown ends on the phone → the phone sends the SOS → "escalated";
//  - the phone goes silent (locked face-down, app killed, battery dead) → the
//    every-minute job sends the SOS itself → "escalated_by_server".
// The SOS goes through createSOSEvent with the fall's clientSOSId, so phone and
// server firing for the same fall make one SOS, not two.
// Every detection is kept (police / incident reports, tuning the detector).

export class SafetyEventError extends Error {
  constructor(public status: number, message: string) { super(message); }
}

/** help_requested: they tapped "I need help — send SOS now" (escalated: nobody answered) */
export type FallOutcome = "pending" | "dismissed" | "escalated" | "help_requested" | "escalated_by_server";
const CLIENT_OUTCOMES = new Set(["pending", "dismissed", "escalated", "help_requested"]);

/** The phone's countdown plus this much before the server steps in */
export const SERVER_GRACE_MS = 30_000;
export const DEFAULT_COUNTDOWN_SEC = 60;

const db = () => admin.firestore();
const ref = (uid: string, clientEventId: string) => db().collection("safety_events").doc(`${uid}_${clientEventId}`);

const num = (v: unknown, min: number, max: number): number | null =>
  typeof v === "number" && Number.isFinite(v) && v >= min && v <= max ? v : null;

function cleanMetrics(m: unknown): Record<string, number | string | null> {
  const x = (m && typeof m === "object" ? m : {}) as Record<string, unknown>;
  return {
    peakImpactG: num(x.peakImpactG, 0, 50),
    freeFallMs: num(x.freeFallMs, 0, 10_000),
    orientationChangeDeg: num(x.orientationChangeDeg, 0, 180),
    stillnessVariance: num(x.stillnessVariance, 0, 100),
    detector: typeof x.detector === "string" ? x.detector.slice(0, 40) : null,
  };
}

function parseDate(v: unknown): Date | null {
  if (typeof v !== "string") return null;
  const t = Date.parse(v);
  return Number.isFinite(t) ? new Date(t) : null;
}

export interface FallReport {
  clientEventId?: unknown;
  clientSOSId?: unknown;
  outcome?: unknown;
  detectedAt?: unknown;
  countdownSec?: unknown;
  latitude?: unknown;
  longitude?: unknown;
  accuracy?: unknown;
  batteryLevel?: unknown;
  metrics?: unknown;
  respondedAfterSec?: unknown;
  sosEventId?: unknown;
}

/**
 * The phone reports a fall, then its outcome (same clientEventId). Returns the
 * outcome the server holds — "escalated_by_server" tells a late "I'm OK" that the
 * SOS is already out (the person ends it from the SOS screen).
 */
export async function reportFall(uid: string, body: FallReport): Promise<{ outcome: FallOutcome; sosEventId: string | null }> {
  const { clientEventId, clientSOSId, outcome } = body;
  if (typeof clientEventId !== "string" || !CLIENT_ID_RE.test(clientEventId)) throw new SafetyEventError(400, "clientEventId is required");
  if (typeof outcome !== "string" || !CLIENT_OUTCOMES.has(outcome)) throw new SafetyEventError(400, "outcome must be pending, dismissed, escalated or help_requested");

  const docRef = ref(uid, clientEventId);
  const now = admin.firestore.Timestamp.now();
  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(docRef);
    const existing = snap.data();

    if (!existing) {
      // The server's clock decides when it steps in, never the phone's
      const countdown = num(body.countdownSec, 10, 300) ?? DEFAULT_COUNTDOWN_SEC;
      const detectedAt = parseDate(body.detectedAt);
      const sosId = typeof clientSOSId === "string" && CLIENT_ID_RE.test(clientSOSId) ? clientSOSId : null;
      tx.set(docRef, {
        userId: uid,
        type: "fall",
        clientEventId,
        clientSOSId: sosId,
        // A phone clock far off is replaced by the server's
        detectedAt: detectedAt && Math.abs(detectedAt.getTime() - Date.now()) < 6 * 3600_000
          ? admin.firestore.Timestamp.fromDate(detectedAt) : now,
        receivedAt: now,
        escalateAt: admin.firestore.Timestamp.fromMillis(now.toMillis() + countdown * 1000),
        latitude: num(body.latitude, -90, 90),
        longitude: num(body.longitude, -180, 180),
        accuracy: num(body.accuracy, 0, 100_000),
        batteryLevel: num(body.batteryLevel, 0, 1),
        metrics: cleanMetrics(body.metrics),
        outcome,
        respondedAfterSec: outcome === "pending" ? null : num(body.respondedAfterSec, 0, 3600),
        sosEventId: typeof body.sosEventId === "string" ? body.sosEventId.slice(0, 64) : null,
        updatedAt: now,
      });
      return { outcome: outcome as FallOutcome, sosEventId: null, firstReport: true, wasPending: false };
    }

    const current = existing.outcome as FallOutcome;
    if (current !== "pending" || outcome === "pending") {
      // Final already (or a repeat): only fill in what's missing, never change the outcome
      const fill: Record<string, unknown> = {};
      if (existing.sosEventId == null && typeof body.sosEventId === "string") fill.sosEventId = body.sosEventId.slice(0, 64);
      if (current === "escalated_by_server" && outcome === "dismissed") fill.dismissedAfterServerSOS = true;
      if (Object.keys(fill).length) tx.update(docRef, { ...fill, updatedAt: now });
      return { outcome: current, sosEventId: (existing.sosEventId as string) ?? null, firstReport: false, wasPending: false };
    }
    tx.update(docRef, {
      outcome,
      respondedAfterSec: num(body.respondedAfterSec, 0, 3600),
      sosEventId: typeof body.sosEventId === "string" ? body.sosEventId.slice(0, 64) : null,
      updatedAt: now,
    });
    return { outcome: outcome as FallOutcome, sosEventId: null, firstReport: false, wasPending: true };
  });

  if (result.outcome === "dismissed" && (result.wasPending || result.firstReport)) {
    await noteDismissedFall(uid, num(body.respondedAfterSec, 0, 3600));
  }
  return { outcome: result.outcome, sosEventId: result.sosEventId };
}

/** "Fall detected — they said they're OK": on the timeline, and a quiet push to guardians. */
async function noteDismissedFall(uid: string, afterSec: number | null): Promise<void> {
  await db().collection("timeline_entries").add({
    userId: uid,
    timestamp: admin.firestore.Timestamp.now(),
    type: "fallDetected",
    description: "Fall detected — confirmed OK",
    detail: afterSec != null ? `respondedAfterSec=${Math.round(afterSec)}` : null,
  });
  try {
    const name = ((await db().collection("users").doc(uid).get()).data()?.displayName as string) ?? "";
    for (const g of await activeGuardianIds(uid)) await sendFallDismissed(g, name).catch(() => undefined);
  } catch (error) {
    console.warn("[Fall] dismissed note failed:", error);
  }
}

/**
 * Every minute: a fall still pending past its countdown + grace means the phone
 * never answered — send the SOS from here. Returns how many were escalated.
 */
export async function escalateUnansweredFalls(now = Date.now()): Promise<number> {
  const due = await db().collection("safety_events")
    .where("outcome", "==", "pending")
    .where("escalateAt", "<=", admin.firestore.Timestamp.fromMillis(now - SERVER_GRACE_MS))
    .limit(50)
    .get();

  let escalated = 0;
  for (const doc of due.docs) {
    // Claim it first: a late "I'm OK" or the phone's own SOS may land meanwhile
    const claimed = await db().runTransaction(async (tx) => {
      const fresh = (await tx.get(doc.ref)).data();
      if (fresh?.outcome !== "pending") return null;
      tx.update(doc.ref, { outcome: "escalated_by_server", updatedAt: admin.firestore.Timestamp.now() });
      return fresh;
    });
    if (!claimed) continue;
    try {
      const sos = await createSOSEvent({
        personId: claimed.userId,
        triggerMethod: "fallDetection",
        latitude: claimed.latitude,
        longitude: claimed.longitude,
        batteryLevel: claimed.batteryLevel,
        clientSOSId: claimed.clientSOSId,
      });
      await doc.ref.update({ sosEventId: sos.sosEventId });
      escalated++;
    } catch (error) {
      // Give it back so the next run tries again
      console.error("[Fall] server SOS failed:", error);
      await doc.ref.update({ outcome: "pending" }).catch(() => undefined);
    }
  }
  return escalated;
}

/** Falls in a window, oldest first (incident reports). */
export async function fallsBetween(uid: string, start: Date, end: Date) {
  const snap = await db().collection("safety_events")
    .where("userId", "==", uid)
    .where("detectedAt", ">=", admin.firestore.Timestamp.fromDate(start))
    .where("detectedAt", "<=", admin.firestore.Timestamp.fromDate(end))
    .orderBy("detectedAt", "asc")
    .get();
  return snap.docs.map((d) => d.data());
}
