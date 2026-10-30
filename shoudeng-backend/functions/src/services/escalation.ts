import * as admin from "firebase-admin";
import {
  sendSOSAlert,
  sendSOSAcknowledgedToGuardian,
  sendSOSAcknowledgedToProtected,
} from "./fcm";
import { sendSOSSms, sendEmergencyContactSms, hasAppInstalled } from "./sms";
import { initiateVoiceCall, publicApiBaseUrl } from "./twilio";
import { createShareToken } from "./evidence";
import { localTime, onDutyAt } from "./localTime";
import { userLang } from "./locale";
import { toIso } from "./time";

const db = admin.firestore();

/**
 * SOS escalation as a durable state machine on the sos_events document.
 *
 *   hop1   +0s    push the on-duty guardian(s) (SMS if push fails)
 *   hop2   +30s   push every guardian (SMS if no app / push fails)
 *   voice1 +90s   phone call to every guardian ("press 1 = I'm handling it")
 *   share  +120s  SMS every guardian a 48 h emergency link (location, battery)
 *   voice2 +210s  call again
 *   voice3 +330s  call again (last round) → "exhausted"
 *
 * The next step and its due time live on the document
 * (escalationNextStep / escalationNextAt). onSOSCreated drives the steps inline
 * while its instance is alive; the advanceEscalations scheduler (every minute)
 * picks up anything due — so a crashed or timed-out instance never loses the
 * escalation. Each step is claimed with a lease in a transaction, and each
 * (step, target) send is recorded, so a re-delivered trigger or a concurrent
 * scheduler run never double-calls anyone.
 *
 * Acknowledging (app button or keypad 1) freezes the machine.
 */

export type EscalationStep = "hop1" | "hop2" | "voice1" | "share" | "voice2" | "voice3";

export const ESCALATION_PLAN: { step: EscalationStep; offsetMs: number; state: string }[] = [
  { step: "hop1", offsetMs: 0, state: "hop1_notified" },
  { step: "hop2", offsetMs: 30_000, state: "hop2_allNotified" },
  { step: "voice1", offsetMs: 90_000, state: "hop3_voiceCalling" },
  { step: "share", offsetMs: 120_000, state: "hop4_shareSent" },
  { step: "voice2", offsetMs: 210_000, state: "hop3_voiceCalling" },
  { step: "voice3", offsetMs: 330_000, state: "hop3_voiceCalling" },
];
export const VOICE_ROUNDS = 3;
const LEASE_MS = 90_000;

export const RESOLUTIONS = [
  "guardianConfirmedSafe",
  "protectedCancelled",
  "responderHandled",
  "falseAlarm",
  "timeout",
] as const;
export type Resolution = typeof RESOLUTIONS[number];

function planIndex(step: string | null | undefined): number {
  return ESCALATION_PLAN.findIndex((p) => p.step === step);
}

/** Fields written on a new SOS so the scheduler can drive it even if onCreate never fires. */
export function initialEscalationFields(now: admin.firestore.Timestamp) {
  return {
    escalationState: "initiated",
    escalationNextStep: "hop1" as EscalationStep,
    escalationNextAt: now,
    escalationLeaseUntil: null,
    escalationSent: {} as Record<string, boolean>,
    escalationLog: [],
  };
}

function ts(ms: number) {
  return admin.firestore.Timestamp.fromMillis(ms);
}

function millis(v: unknown): number | null {
  const t = v as { toMillis?: () => number } | null;
  return t && typeof t.toMillis === "function" ? t.toMillis() : null;
}

interface SOSDoc {
  protectedPersonId: string;
  triggeredAt: admin.firestore.Timestamp;
  resolvedAt: admin.firestore.Timestamp | null;
  escalationState: string;
  escalationNextStep: EscalationStep | null;
  escalationNextAt: admin.firestore.Timestamp | null;
  escalationLeaseUntil: admin.firestore.Timestamp | null;
  escalationSent?: Record<string, boolean>;
  latitude?: number | null;
  longitude?: number | null;
  batteryLevel?: number | null;
  acknowledgedBy?: string | null;
}

export interface AdvanceResult {
  ran: EscalationStep | null;
  /** When the next step is due (ms epoch), or null when the machine has stopped. */
  nextAt: number | null;
}

/**
 * Run the due step of one SOS, if any. Safe to call concurrently and repeatedly.
 */
export async function advanceEscalation(sosId: string, now: Date = new Date()): Promise<AdvanceResult> {
  const ref = db.collection("sos_events").doc(sosId);
  const nowMs = now.getTime();

  // 1. Claim the due step
  const claim = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return { kind: "stop" as const };
    const d = snap.data() as SOSDoc;
    if (d.resolvedAt || d.escalationState === "frozen" || !d.escalationNextStep) {
      return { kind: "stop" as const };
    }
    const dueAt = millis(d.escalationNextAt) ?? nowMs;
    if (dueAt > nowMs) return { kind: "wait" as const, nextAt: dueAt };
    const leaseUntil = millis(d.escalationLeaseUntil);
    if (leaseUntil && leaseUntil > nowMs) return { kind: "wait" as const, nextAt: leaseUntil };
    tx.update(ref, { escalationLeaseUntil: ts(nowMs + LEASE_MS) });
    return { kind: "run" as const, step: d.escalationNextStep, data: d };
  });

  if (claim.kind === "stop") return { ran: null, nextAt: null };
  if (claim.kind === "wait") return { ran: null, nextAt: claim.nextAt };

  const { step, data } = claim;
  let stop = false;
  let stateOverride: string | null = null;
  try {
    const outcome = await runStep(sosId, step, data, now);
    stop = outcome.stop;
    stateOverride = outcome.state ?? null;
  } catch (err) {
    // Leave the lease to expire: the scheduler retries this step; per-target
    // markers prevent repeating sends that already went out.
    console.error(`[Escalation] ${sosId} step ${step} failed:`, err);
    return { ran: null, nextAt: nowMs + LEASE_MS };
  }

  // 2. Commit progress
  const idx = planIndex(step);
  const next = stop ? undefined : ESCALATION_PLAN[idx + 1];
  const triggeredMs = millis(data.triggeredAt) ?? nowMs;
  const nextAtMs = next ? Math.max(triggeredMs + next.offsetMs, nowMs + 5_000) : null;

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const d = snap.data() as SOSDoc | undefined;
    const halted = !d || d.resolvedAt || d.escalationState === "frozen";
    const update: Record<string, unknown> = {
      escalationLeaseUntil: null,
      escalationNextStep: halted || !next ? null : next.step,
      escalationNextAt: halted || nextAtMs === null ? null : ts(nextAtMs),
    };
    if (!halted) {
      update.escalationState = stateOverride ?? (next ? ESCALATION_PLAN[idx].state : "exhausted");
    }
    tx.update(ref, update);
    return { ran: step, nextAt: halted ? null : nextAtMs };
  });
}

// ---------------------------------------------------------------------------
// Steps
// ---------------------------------------------------------------------------

interface StepOutcome { stop: boolean; state?: string }

async function activeGuardianIds(personId: string): Promise<string[]> {
  const links = await db
    .collection("guardian_links")
    .where("protectedPersonId", "==", personId)
    .where("status", "==", "active")
    .get();
  return links.docs.map((d) => d.data().guardianId as string);
}

/** Guardians on duty right now in the protected person's local time. */
export async function onDutyGuardians(
  personId: string,
  guardianIds: string[],
  personTimeZone: string | null | undefined,
  now: Date
): Promise<string[]> {
  const t = localTime(now, personTimeZone);
  const result: string[] = [];
  for (const gid of guardianIds) {
    const schedules = await db
      .collection("duty_schedules")
      .where("guardianId", "==", gid)
      .where("protectedPersonId", "==", personId)
      .where("isActive", "==", true)
      .get();
    const slots = schedules.docs.map((d) => d.data() as { startHour: number; endHour: number; dayOfWeek: number });
    // No schedule = always on duty
    if (slots.length === 0 || onDutyAt(slots, t)) result.push(gid);
  }
  return result;
}

async function logEntry(sosId: string, entry: Record<string, unknown>, sentKey?: string) {
  const update: Record<string, unknown> = {
    escalationLog: admin.firestore.FieldValue.arrayUnion({
      sentAt: admin.firestore.Timestamp.now(),
      deliveredAt: null,
      readAt: null,
      respondedAt: null,
      response: null,
      ...entry,
    }),
  };
  if (sentKey) update[`escalationSent.${sentKey}`] = true;
  await db.collection("sos_events").doc(sosId).update(update);
}

async function stillActive(sosId: string): Promise<boolean> {
  const d = (await db.collection("sos_events").doc(sosId).get()).data();
  return !!d && !d.resolvedAt && d.escalationState !== "frozen";
}

async function runStep(sosId: string, step: EscalationStep, sos: SOSDoc, now: Date): Promise<StepOutcome> {
  const personId = sos.protectedPersonId;
  const userDoc = await db.collection("users").doc(personId).get();
  const user = userDoc.data() ?? {};
  const personName: string = user.displayName || "Protected Person";
  const sent = sos.escalationSent ?? {};
  const guardianIds = await activeGuardianIds(personId);
  const alertDetails = {
    protectedPersonId: personId,
    batteryLevel: sos.batteryLevel ?? null,
    latitude: sos.latitude ?? null,
    longitude: sos.longitude ?? null,
  };

  if (guardianIds.length === 0) {
    if (step !== "hop1") return { stop: true };
    return notifyWithoutGuardians(sosId, personId, personName, user, sent);
  }

  switch (step) {
    case "hop1": {
      const onDuty = await onDutyGuardians(personId, guardianIds, user.timeZone, now);
      const targets = onDuty.length > 0 ? onDuty : guardianIds;
      for (const gid of targets) {
        const key = `hop1:${gid}`;
        if (sent[key]) continue;
        const push = await sendSOSAlert(gid, personName, sosId, alertDetails);
        let channel = "push";
        if (push.allFailed) {
          channel = (await sendSOSSms(gid, personName, sosId)) ? "sms_fallback" : "failed";
        }
        await logEntry(sosId, { hop: 1, targetId: gid, channel }, key);
      }
      return { stop: false };
    }
    case "hop2": {
      for (const gid of guardianIds) {
        const key = `hop2:${gid}`;
        if (sent[key]) continue;
        const push = await sendSOSAlert(gid, personName, sosId, alertDetails);
        let channel = "push";
        const hasApp = await hasAppInstalled(gid);
        if (!hasApp || push.allFailed) {
          const ok = await sendSOSSms(gid, personName, sosId);
          channel = ok ? "sms_fallback" : hasApp ? "push_failed" : "sms_failed";
        }
        await logEntry(sosId, { hop: 2, targetId: gid, channel }, key);
      }
      return { stop: false };
    }
    case "voice1":
    case "voice2":
    case "voice3": {
      const round = Number(step.slice(5));
      for (const gid of guardianIds) {
        const key = `${step}:${gid}`;
        if (sent[key]) continue;
        // Stop ringing phones the moment someone acknowledges
        if (!(await stillActive(sosId))) return { stop: true };
        const callSid = await initiateVoiceCall(gid, sosId, personName, {
          round,
          isLastRound: round === VOICE_ROUNDS,
        });
        await logEntry(sosId, {
          hop: 3,
          round,
          targetId: gid,
          channel: callSid ? "voice" : "voice_unavailable",
          callSid: callSid ?? null,
        }, key);
      }
      return { stop: false };
    }
    case "share": {
      if (sent["share:link"]) return { stop: false };
      const url = await createEmergencyShareUrl(personId);
      for (const gid of guardianIds) {
        const key = `share:${gid}`;
        if (sent[key]) continue;
        const ok = await sendSOSSms(gid, personName, sosId, url);
        await logEntry(sosId, { hop: 4, targetId: gid, channel: ok ? "sms_link" : "sms_failed" }, key);
      }
      await db.collection("sos_events").doc(sosId).update({
        shareLinkSentAt: admin.firestore.Timestamp.now(),
        "escalationSent.share:link": true,
      });
      return { stop: false };
    }
  }
}

/** Public 48 h emergency link. The token itself is never logged. */
async function createEmergencyShareUrl(personId: string): Promise<string> {
  const token = await createShareToken({
    protectedPersonId: personId,
    createdBy: "system_escalation",
    expiresInHours: 48,
  });
  return `${publicApiBaseUrl()}/v1/evidence/share/${token}`;
}

/**
 * Nobody to escalate to: text the user's personal emergency contacts (with the
 * emergency link) and mark the SOS so the app tells the user to call the local
 * emergency number instead of claiming "family notified".
 */
async function notifyWithoutGuardians(
  sosId: string,
  personId: string,
  personName: string,
  user: admin.firestore.DocumentData,
  sent: Record<string, boolean>
): Promise<StepOutcome> {
  const contactsDoc = await db.collection("emergency_contacts").doc(personId).get();
  const contacts: { id: string; phone: string }[] = contactsDoc.exists ? contactsDoc.data()?.contacts ?? [] : [];
  let texted = 0;
  if (contacts.length > 0) {
    const url = await createEmergencyShareUrl(personId);
    for (const c of contacts) {
      const key = `contact:${c.id}`;
      if (sent[key]) { texted++; continue; }
      const ok = await sendEmergencyContactSms(c.phone, personName, userLang(user), url);
      if (ok) texted++;
      await logEntry(sosId, { hop: 1, targetId: `contact:${c.id}`, channel: ok ? "sms_contact" : "sms_failed" }, key);
    }
  }
  await db.collection("sos_events").doc(sosId).update({
    noGuardians: true,
    emergencyContactsNotified: texted,
  });
  console.warn(`[Escalation] SOS ${sosId}: no guardians; texted ${texted} emergency contact(s)`);
  return { stop: true, state: "no_guardians" };
}

// ---------------------------------------------------------------------------
// Acknowledge ("I've got it" / keypad 1)
// ---------------------------------------------------------------------------

export type AckResult =
  | { status: "acknowledged"; acknowledgedBy: string; alreadyAcknowledged: boolean }
  | { status: "not_found" | "resolved" | "forbidden" };

export async function acknowledgeSOS(
  sosId: string,
  guardianId: string,
  via: "app" | "voice" | "push_action"
): Promise<AckResult> {
  const ref = db.collection("sos_events").doc(sosId);

  const result = await db.runTransaction(async (tx): Promise<AckResult & { personId?: string }> => {
    const snap = await tx.get(ref);
    if (!snap.exists) return { status: "not_found" };
    const d = snap.data()!;
    if (d.resolvedAt) return { status: "resolved" };
    const link = await tx.get(db.collection("guardian_links").doc(`${guardianId}_${d.protectedPersonId}`));
    if (!link.exists || link.data()?.status !== "active") return { status: "forbidden" };
    if (d.acknowledgedBy) {
      return { status: "acknowledged", acknowledgedBy: d.acknowledgedBy, alreadyAcknowledged: true };
    }
    const now = admin.firestore.Timestamp.now();
    tx.update(ref, {
      escalationState: "frozen",
      acknowledgedBy: guardianId,
      acknowledgedAt: now,
      acknowledgedVia: via,
      escalationNextStep: null,
      escalationNextAt: null,
      escalationLeaseUntil: null,
      escalationLog: admin.firestore.FieldValue.arrayUnion({
        hop: "ack",
        targetId: guardianId,
        sentAt: now,
        respondedAt: now,
        response: `acknowledged_${via}`,
      }),
    });
    return { status: "acknowledged", acknowledgedBy: guardianId, alreadyAcknowledged: false, personId: d.protectedPersonId };
  });

  if (result.status === "acknowledged" && !result.alreadyAcknowledged && result.personId) {
    const personId = result.personId;
    try {
      const [guardianDoc, personDoc] = await Promise.all([
        db.collection("users").doc(guardianId).get(),
        db.collection("users").doc(personId).get(),
      ]);
      const guardianName = guardianDoc.data()?.displayName || "Guardian";
      const personName = personDoc.data()?.displayName || "";
      await db.collection("timeline_entries").add({
        userId: personId,
        timestamp: admin.firestore.Timestamp.now(),
        type: "guardianAlert",
        description: `${guardianName} is handling the SOS`,
        detail: via,
      });
      const others = (await activeGuardianIds(personId)).filter((g) => g !== guardianId);
      await Promise.all([
        ...others.map((g) => sendSOSAcknowledgedToGuardian(g, guardianName, personName, sosId, personId)),
        sendSOSAcknowledgedToProtected(personId, guardianName, sosId),
      ]);
    } catch (err) {
      console.error(`[Escalation] ack notifications for ${sosId} failed:`, err);
    }
  }
  if (result.status === "acknowledged") {
    return { status: "acknowledged", acknowledgedBy: result.acknowledgedBy, alreadyAcknowledged: result.alreadyAcknowledged };
  }
  return { status: result.status };
}

// ---------------------------------------------------------------------------
// Read model shared by the guardian + protected views
// ---------------------------------------------------------------------------

export interface SOSStatus {
  sosEventId: string;
  protectedPersonId: string;
  personName: string;
  triggeredAt: string | null;
  triggerMethod: string | null;
  latitude: number | null;
  longitude: number | null;
  batteryLevel: number | null;
  escalationState: string;
  nextStep: string | null;
  nextStepAt: string | null;
  guardiansNotified: number;
  callsPlaced: number;
  shareLinkSent: boolean;
  noGuardians: boolean;
  emergencyContactsNotified: number;
  acknowledgedBy: string | null;
  acknowledgedByName: string | null;
  acknowledgedAt: string | null;
  elapsedSeconds: number;
}

export async function sosStatus(
  doc: admin.firestore.DocumentSnapshot,
  now: Date = new Date()
): Promise<SOSStatus> {
  const d = doc.data()!;
  const log: { hop?: unknown; targetId?: string; channel?: string }[] = d.escalationLog ?? [];
  const notified = new Set(
    log.filter((e) => (e.hop === 1 || e.hop === 2) && e.channel && !String(e.channel).includes("failed"))
      .map((e) => e.targetId)
  );
  const [personDoc, ackDoc] = await Promise.all([
    db.collection("users").doc(d.protectedPersonId).get(),
    d.acknowledgedBy ? db.collection("users").doc(d.acknowledgedBy).get() : Promise.resolve(null),
  ]);
  const triggered = millis(d.triggeredAt);
  return {
    sosEventId: doc.id,
    protectedPersonId: d.protectedPersonId,
    personName: personDoc.data()?.displayName ?? "",
    triggeredAt: toIso(d.triggeredAt),
    triggerMethod: d.triggerMethod ?? null,
    latitude: typeof d.latitude === "number" ? d.latitude : null,
    longitude: typeof d.longitude === "number" ? d.longitude : null,
    batteryLevel: typeof d.batteryLevel === "number" ? d.batteryLevel : null,
    escalationState: d.escalationState ?? "initiated",
    nextStep: d.escalationNextStep ?? null,
    nextStepAt: toIso(d.escalationNextAt),
    guardiansNotified: [...notified].filter((t) => t && !String(t).startsWith("contact:")).length,
    callsPlaced: log.filter((e) => e.hop === 3 && e.channel === "voice").length,
    shareLinkSent: !!d.shareLinkSentAt,
    noGuardians: d.noGuardians === true,
    emergencyContactsNotified: d.emergencyContactsNotified ?? 0,
    acknowledgedBy: d.acknowledgedBy ?? null,
    acknowledgedByName: ackDoc?.data()?.displayName ?? null,
    acknowledgedAt: toIso(d.acknowledgedAt),
    elapsedSeconds: triggered ? Math.max(0, Math.round((now.getTime() - triggered) / 1000)) : 0,
  };
}

/** The person's unresolved SOS, newest first (there should be at most one). */
export async function activeSOSDoc(personId: string): Promise<admin.firestore.DocumentSnapshot | null> {
  const snap = await db
    .collection("sos_events")
    .where("protectedPersonId", "==", personId)
    .where("resolvedAt", "==", null)
    .get();
  if (snap.empty) return null;
  return [...snap.docs].sort((a, b) => (millis(b.data().triggeredAt) ?? 0) - (millis(a.data().triggeredAt) ?? 0))[0];
}

/**
 * Drive steps inline while this function instance is alive (precise timing on
 * the happy path). The scheduler covers anything this misses.
 */
export async function runEscalationInline(
  sosId: string,
  budgetMs: number,
  sleep: (ms: number) => Promise<void> = (ms) => new Promise((r) => setTimeout(r, ms))
): Promise<void> {
  const deadline = Date.now() + budgetMs;
  for (;;) {
    const r = await advanceEscalation(sosId, new Date());
    if (r.nextAt === null) return;
    const wait = r.nextAt - Date.now();
    if (Date.now() + Math.max(wait, 0) > deadline) return; // hand over to the scheduler
    if (wait > 0) await sleep(wait);
  }
}

/** Scheduler body: advance every unresolved SOS whose next step is due. */
export async function advanceDueEscalations(now: Date = new Date()): Promise<number> {
  const due = await db
    .collection("sos_events")
    .where("resolvedAt", "==", null)
    .where("escalationNextAt", "<=", admin.firestore.Timestamp.fromDate(now))
    .limit(50)
    .get();
  let ran = 0;
  for (const doc of due.docs) {
    try {
      // A single scheduler tick may need to catch up several overdue steps
      for (let i = 0; i < ESCALATION_PLAN.length; i++) {
        const r = await advanceEscalation(doc.id, now);
        if (r.ran) ran++;
        if (!r.ran || r.nextAt === null || r.nextAt > now.getTime()) break;
      }
    } catch (err) {
      console.error(`[Escalation] scheduler failed for ${doc.id}:`, err);
    }
  }
  return ran;
}
