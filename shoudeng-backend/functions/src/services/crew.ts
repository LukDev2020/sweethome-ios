import * as admin from "firebase-admin";
import { markMilestone, noteShiftStarted } from "./riderProfile";
import { distanceMeters } from "./sosTracking";
import { activeGuardianIds } from "./sosTracking";
import {
  sendCrewSOSAlert, sendCrewResponseNotification, sendShiftOverdueNotification,
  sendShiftWatchRequest, sendWatchBackNotification, sendShiftStillOk, sendShiftStillOkMissed,
} from "./fcm";
import { activeSOSDoc } from "./escalation";
import { localTime } from "./localTime";

// ---------------------------------------------------------------------------
// Rider crews
// ---------------------------------------------------------------------------
//
// Riders (delivery / rideshare) look out for each other in a small invite-only crew.
// Unlike guardians, the relationship is mutual: every member is alerted when any
// member calls SOS, nearest first, and sees the others on the map — but only while
// they are on shift. Joining needs the crew's invite code (shown as a QR code).
//
//   crews/{crewId}                { name, ownerId, memberIds[], inviteCode, createdAt }
//   crews/{crewId}/cautions/{id}  { userId, latitude, longitude, note, createdAt, expiresAt }
//   rider_shifts/{uid}            active shifts only: { crewId, startedAt, plannedEnd, checkDueAt, overdueAlerted, watcherIds }
//   users/{uid}.crewId / .riderOnShift / .riderWatchers (who watches my shifts; the next shift starts with them)
//
// Watchers: each shift is watched by at least one crew colleague and one family member
// (guardian), chosen at shift start; more can be added. Watchers get the "shift not
// ended" alert. A crew mate who watches you can be watched back in one tap.
//   sos_events/{id}.crewNotified[] / .crewResponses{uid: {response, at, distanceM}}

export const CREW_MAX_MEMBERS = 12;
/** A shift with a planned end is checked this long after it */
export const SHIFT_GRACE_MS = 30 * 60 * 1000;
/** Caution spots fade after a night */
export const CAUTION_TTL_MS = 12 * 60 * 60 * 1000;

// ---------------------------------------------------------------------------
// Rider preferences (Settings → Rider)
// ---------------------------------------------------------------------------
//
// Kept on the user doc (riderPrefs). Guardrails are enforced here, not just in the app:
//  - while you're on shift, every crew SOS reaches you; the choice is only off shift
//  - an approximate position is never used during your own SOS
//  - the late-shift alert can be longer, never off; caution spots 2 / 12 / 24 h

export const OFF_SHIFT_ALERTS = ["none", "nearby", "all"] as const;
export const ALERT_RADII_KM = [1, 3, 5, 10] as const;
export const GRACE_MINUTES = [15, 30, 60] as const;
export const CAUTION_HOURS = [2, 12, 24] as const;
export const STILL_OK_EVERY_MIN = [60, 120] as const;
/** No answer to "Still OK?" within this long → the shift's watchers are told */
export const STILL_OK_ANSWER_MS = 10 * 60 * 1000;
/** ~200 m: coordinates rounded to 1/500 of a degree */
const APPROX_STEP = 500;

export interface RiderPrefs {
  offShiftAlerts: (typeof OFF_SHIFT_ALERTS)[number];
  alertRadiusKm: number;
  crewPrecision: "exact" | "approx";
}
export const DEFAULT_PREFS: RiderPrefs = { offShiftAlerts: "none", alertRadiusKm: 3, crewPrecision: "exact" };

export function prefsOf(user: FirebaseFirestore.DocumentData | undefined): RiderPrefs {
  const p = (user?.riderPrefs ?? {}) as Record<string, unknown>;
  return {
    offShiftAlerts: (OFF_SHIFT_ALERTS as readonly unknown[]).includes(p.offShiftAlerts) ? p.offShiftAlerts as RiderPrefs["offShiftAlerts"] : DEFAULT_PREFS.offShiftAlerts,
    alertRadiusKm: (ALERT_RADII_KM as readonly unknown[]).includes(p.alertRadiusKm) ? p.alertRadiusKm as number : DEFAULT_PREFS.alertRadiusKm,
    crewPrecision: p.crewPrecision === "approx" ? "approx" : "exact",
  };
}

export async function setPrefs(uid: string, body: Record<string, unknown>): Promise<RiderPrefs> {
  const updates: Record<string, unknown> = {};
  if (body.offShiftAlerts !== undefined) {
    if (!(OFF_SHIFT_ALERTS as readonly unknown[]).includes(body.offShiftAlerts)) throw new CrewError(400, "offShiftAlerts must be none, nearby or all");
    updates["riderPrefs.offShiftAlerts"] = body.offShiftAlerts;
  }
  if (body.alertRadiusKm !== undefined) {
    if (!(ALERT_RADII_KM as readonly unknown[]).includes(body.alertRadiusKm)) throw new CrewError(400, "alertRadiusKm must be 1, 3, 5 or 10");
    updates["riderPrefs.alertRadiusKm"] = body.alertRadiusKm;
  }
  if (body.crewPrecision !== undefined) {
    if (body.crewPrecision !== "exact" && body.crewPrecision !== "approx") throw new CrewError(400, "crewPrecision must be exact or approx");
    updates["riderPrefs.crewPrecision"] = body.crewPrecision;
  }
  const ref = db().collection("users").doc(uid);
  if (Object.keys(updates).length) await ref.update(updates);
  return prefsOf((await ref.get()).data());
}

/** Should this crew mate get the SOS? On shift: always. Off shift: their choice. */
export function wantsCrewAlert(user: FirebaseFirestore.DocumentData, distanceM: number | null): boolean {
  if (user.riderOnShift === true) return true;
  const p = prefsOf(user);
  if (p.offShiftAlerts === "all") return true;
  if (p.offShiftAlerts === "nearby") return distanceM != null && distanceM <= p.alertRadiusKm * 1000;
  return false;
}

const approx = (v: number) => Math.round(v * APPROX_STEP) / APPROX_STEP;
export const CREW_RESPONSES = ["going", "cant_help"] as const;
export type CrewResponse = typeof CREW_RESPONSES[number];

const db = () => admin.firestore();
const ts = (d: Date) => admin.firestore.Timestamp.fromDate(d);
const iso = (v: unknown): string | null =>
  v instanceof admin.firestore.Timestamp ? v.toDate().toISOString() : typeof v === "string" ? v : null;

export class CrewError extends Error {
  constructor(public status: number, message: string) { super(message); }
}

/** 6 characters, no look-alikes (0/O, 1/I) */
export function newInviteCode(random: () => number = Math.random): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  return Array.from({ length: 6 }, () => alphabet[Math.floor(random() * alphabet.length)]).join("");
}

export async function crewIdOf(uid: string): Promise<string | null> {
  const user = await db().collection("users").doc(uid).get();
  return (user.data()?.crewId as string | undefined) ?? null;
}

export async function createCrew(uid: string, rawName: unknown): Promise<string> {
  const name = typeof rawName === "string" ? rawName.trim().slice(0, 40) : "";
  if (!name) throw new CrewError(400, "name is required");
  if (await crewIdOf(uid)) throw new CrewError(409, "already in a crew");
  const ref = db().collection("crews").doc();
  await ref.set({ name, ownerId: uid, memberIds: [uid], inviteCode: newInviteCode(), createdAt: ts(new Date()) });
  await db().collection("users").doc(uid).set({ crewId: ref.id }, { merge: true });
  await markMilestone(uid, "crew");
  return ref.id;
}

export async function joinCrew(uid: string, rawCode: unknown): Promise<string> {
  const code = typeof rawCode === "string" ? rawCode.trim().toUpperCase() : "";
  if (!/^[A-Z0-9]{6}$/.test(code)) throw new CrewError(400, "invalid code");
  const current = await crewIdOf(uid);
  const snap = await db().collection("crews").where("inviteCode", "==", code).limit(1).get();
  if (snap.empty) throw new CrewError(404, "no crew with that code");
  const crew = snap.docs[0];
  if (current === crew.id) return crew.id;
  if (current) throw new CrewError(409, "already in a crew");
  await db().runTransaction(async (tx) => {
    const fresh = await tx.get(crew.ref);
    const members: string[] = fresh.data()?.memberIds ?? [];
    if (members.length >= CREW_MAX_MEMBERS) throw new CrewError(409, "crew is full");
    tx.update(crew.ref, { memberIds: [...members, uid] });
    tx.set(db().collection("users").doc(uid), { crewId: crew.id }, { merge: true });
  });
  await markMilestone(uid, "crew");
  return crew.id;
}

export async function leaveCrew(uid: string): Promise<void> {
  const crewId = await crewIdOf(uid);
  if (!crewId) return;
  const ref = db().collection("crews").doc(crewId);
  await db().runTransaction(async (tx) => {
    const fresh = await tx.get(ref);
    const members: string[] = (fresh.data()?.memberIds ?? []).filter((m: string) => m !== uid);
    if (members.length === 0) tx.delete(ref);
    else tx.update(ref, { memberIds: members, ...(fresh.data()?.ownerId === uid && { ownerId: members[0] }) });
    tx.set(db().collection("users").doc(uid), { crewId: admin.firestore.FieldValue.delete() }, { merge: true });
  });
}

interface Position { latitude: number; longitude: number; at: string | null }

async function positionOf(uid: string): Promise<Position | null> {
  const t = (await db().collection("user_telemetry").doc(uid).get()).data();
  if (typeof t?.latitude !== "number" || typeof t?.longitude !== "number") return null;
  return { latitude: t.latitude, longitude: t.longitude, at: iso(t.locationTimestamp) };
}

/** The caller's crew: members (location only while on shift), active cautions. */
export async function crewView(uid: string, now: Date = new Date()) {
  const crewId = await crewIdOf(uid);
  if (!crewId) return null;
  const crew = await db().collection("crews").doc(crewId).get();
  if (!crew.exists) return null;
  const c = crew.data()!;
  const me = await positionOf(uid);
  const myWatchers = await watchersOf(uid);
  const members = await Promise.all((c.memberIds as string[]).map(async (id) => {
    const user = (await db().collection("users").doc(id).get()).data() ?? {};
    const theirWatchers: string[] = Array.isArray(user.riderWatchers) ? user.riderWatchers : [];
    const onShift = user.riderOnShift === true;
    const exact = onShift || id === uid ? await positionOf(id) : null;
    // A mate who chose "approximate" shows ~200 m off — except to themselves and during their SOS
    const blur = !!exact && id !== uid && prefsOf(user).crewPrecision === "approx" && !(await activeSOSDoc(id));
    const pos = exact && blur ? { ...exact, latitude: approx(exact.latitude), longitude: approx(exact.longitude) } : exact;
    return {
      id,
      name: (user.displayName as string) ?? "",
      initial: (user.avatarInitial as string) ?? "",
      onShift,
      latitude: pos?.latitude ?? null,
      longitude: pos?.longitude ?? null,
      locationAt: pos?.at ?? null,
      distanceM: me && pos && id !== uid ? Math.round(distanceMeters(me, pos)) : null,
      /** watches my shifts */
      watchesMe: id !== uid && myWatchers.includes(id),
      /** I watch their shifts */
      iWatch: id !== uid && theirWatchers.includes(uid),
      approximate: blur,
    };
  }));
  const cautions = await crew.ref.collection("cautions").where("expiresAt", ">", ts(now)).get();
  return {
    id: crew.id,
    name: c.name as string,
    inviteCode: c.inviteCode as string,
    isOwner: c.ownerId === uid,
    members,
    myWatcherIds: myWatchers,
    myPrefs: prefsOf((await db().collection("users").doc(uid).get()).data()),
    cautions: cautions.docs.map((d) => ({
      id: d.id,
      latitude: d.data().latitude as number,
      longitude: d.data().longitude as number,
      note: (d.data().note as string) ?? "",
      createdAt: iso(d.data().createdAt),
    })),
  };
}

const isCoord = (lat: unknown, lng: unknown) =>
  typeof lat === "number" && typeof lng === "number" && Math.abs(lat) <= 90 && Math.abs(lng) <= 180;

/** Start / end a shift. A planned end is checked SHIFT_GRACE_MS later. */
export interface ShiftOptions {
  /** Late-shift alert after the planned end: 15, 30 (default) or 60 minutes */
  graceMinutes?: unknown;
  /** "Still OK?" every 60 / 120 minutes between these local hours (e.g. 22 → 6) */
  stillOkEveryMin?: unknown;
  stillOkFromHour?: unknown;
  stillOkToHour?: unknown;
}

const hourOrNull = (v: unknown) => (typeof v === "number" && Number.isInteger(v) && v >= 0 && v <= 23 ? v : null);

export async function setShift(
  uid: string, onShift: boolean, plannedEnd: unknown, now: Date = new Date(), rawWatchers?: unknown, options: ShiftOptions = {}
): Promise<void> {
  const shiftRef = db().collection("rider_shifts").doc(uid);
  if (!onShift) {
    await db().collection("users").doc(uid).set({ riderOnShift: false }, { merge: true });
    await shiftRef.delete();
    return;
  }
  // Watchers sent with the shift (else the ones from last time); must be crew mates or guardians
  const watcherIds = rawWatchers === undefined ? await watchersOf(uid) : await validWatchers(uid, rawWatchers);
  const end = typeof plannedEnd === "string" && !Number.isNaN(Date.parse(plannedEnd)) ? new Date(plannedEnd) : null;
  const previous = await watchersOf(uid);
  await db().collection("users").doc(uid).set({ riderOnShift: true, riderWatchers: watcherIds }, { merge: true });
  const grace = (GRACE_MINUTES as readonly unknown[]).includes(options.graceMinutes) ? (options.graceMinutes as number) * 60_000 : SHIFT_GRACE_MS;
  const every = (STILL_OK_EVERY_MIN as readonly unknown[]).includes(options.stillOkEveryMin) ? options.stillOkEveryMin as number : null;
  const from = hourOrNull(options.stillOkFromHour), to = hourOrNull(options.stillOkToHour);
  await shiftRef.set({
    crewId: await crewIdOf(uid),
    startedAt: ts(now),
    plannedEnd: end ? ts(end) : null,
    graceMinutes: grace / 60_000,
    checkDueAt: end ? ts(new Date(end.getTime() + grace)) : null,
    overdueAlerted: false,
    watcherIds,
    stillOk: every != null && from != null && to != null
      ? { everyMin: every, fromHour: from, toHour: to, nextAt: ts(new Date(now.getTime() + every * 60_000)), sentAt: null }
      : null,
  });
  await noteShiftStarted(uid);
  // Tell watchers who weren't watching before
  const name = ((await db().collection("users").doc(uid).get()).data()?.displayName as string) ?? "";
  await Promise.all(watcherIds.filter((w) => !previous.includes(w))
    .map((w) => sendShiftWatchRequest(w, name, uid).catch(() => undefined)));
}

/** Who watches the rider's shifts (saved with the last shift / watch-backs). */
export async function watchersOf(uid: string): Promise<string[]> {
  const w = (await db().collection("users").doc(uid).get()).data()?.riderWatchers;
  return Array.isArray(w) ? w.filter((x): x is string => typeof x === "string") : [];
}

/** Keeps only crew mates and active guardians (no strangers); 20 at most. */
async function validWatchers(uid: string, raw: unknown): Promise<string[]> {
  if (!Array.isArray(raw)) throw new CrewError(400, "watcherIds must be a list");
  const crewId = await crewIdOf(uid);
  const crewMates: string[] = crewId
    ? (((await db().collection("crews").doc(crewId).get()).data()?.memberIds ?? []) as string[]).filter((m) => m !== uid)
    : [];
  const guardians = await activeGuardianIds(uid);
  const allowed = new Set([...crewMates, ...guardians]);
  const ids = [...new Set(raw.filter((x): x is string => typeof x === "string"))];
  const bad = ids.filter((id) => !allowed.has(id));
  if (bad.length > 0) throw new CrewError(403, "watchers must be crew mates or guardians");
  return ids.slice(0, 20);
}

/**
 * "Watch back": a crew mate who watches my shifts asks to have me watch theirs.
 * Only allowed when they already watch me (so nobody adds themselves uninvited).
 */
export async function watchBack(uid: string, memberId: unknown): Promise<void> {
  if (typeof memberId !== "string" || !memberId || memberId === uid) throw new CrewError(400, "memberId is required");
  const crewId = await crewIdOf(uid);
  if (!crewId || crewId !== (await crewIdOf(memberId))) throw new CrewError(403, "not in your crew");
  if (!(await watchersOf(uid)).includes(memberId)) throw new CrewError(403, "they don't watch you");
  const theirs = await watchersOf(memberId);
  if (!theirs.includes(uid)) {
    await db().collection("users").doc(memberId).set({ riderWatchers: [...theirs, uid] }, { merge: true });
    const shift = db().collection("rider_shifts").doc(memberId);
    if ((await shift.get()).exists) await shift.set({ watcherIds: [...theirs, uid] }, { merge: true });
  }
  const name = ((await db().collection("users").doc(uid).get()).data()?.displayName as string) ?? "";
  await sendWatchBackNotification(memberId, name).catch(() => undefined);
}

export async function addCaution(uid: string, body: Record<string, unknown>, now: Date = new Date()): Promise<string> {
  const crewId = await crewIdOf(uid);
  if (!crewId) throw new CrewError(404, "not in a crew");
  if (!isCoord(body.latitude, body.longitude)) throw new CrewError(400, "latitude and longitude are required");
  const note = typeof body.note === "string" ? body.note.trim().slice(0, 140) : "";
  const ref = await db().collection("crews").doc(crewId).collection("cautions").add({
    userId: uid, latitude: body.latitude, longitude: body.longitude, note,
    createdAt: ts(now),
    expiresAt: ts(new Date(now.getTime() + ((CAUTION_HOURS as readonly unknown[]).includes(body.ttlHours) ? (body.ttlHours as number) * 3600_000 : CAUTION_TTL_MS))),
  });
  return ref.id;
}

// ---------------------------------------------------------------------------
// SOS → crew
// ---------------------------------------------------------------------------

/** Alerts every other member of the person's crew, nearest first. Never throws. */
export async function alertCrewOfSOS(sosId: string, sos: FirebaseFirestore.DocumentData): Promise<number> {
  try {
    const personId = sos.protectedPersonId as string;
    const crewId = await crewIdOf(personId);
    if (!crewId) return 0;
    const crew = (await db().collection("crews").doc(crewId).get()).data();
    const others = ((crew?.memberIds ?? []) as string[]).filter((m) => m !== personId);
    if (others.length === 0) return 0;
    const person = (await db().collection("users").doc(personId).get()).data() ?? {};
    const at = isCoord(sos.latitude, sos.longitude) ? { latitude: sos.latitude, longitude: sos.longitude } : null;
    const all = await Promise.all(others.map(async (id) => {
      const pos = await positionOf(id);
      const user = (await db().collection("users").doc(id).get()).data() ?? {};
      const distanceM = at && pos ? Math.round(distanceMeters(at, pos)) : null;
      return { id, distanceM, wants: wantsCrewAlert(user, distanceM) };
    }));
    // On shift: always. Off shift: only if they chose to hear about it (Settings → Rider)
    const withDistance = all.filter((m) => m.wants);
    withDistance.sort((a, b) => (a.distanceM ?? Infinity) - (b.distanceM ?? Infinity));
    await Promise.all(withDistance.map((m) => sendCrewSOSAlert(m.id, (person.displayName as string) ?? "", m.distanceM, {
      sosEventId: sosId, riderId: personId, latitude: at?.latitude, longitude: at?.longitude,
    })));
    await db().collection("sos_events").doc(sosId).set({ crewNotified: withDistance.map((m) => m.id) }, { merge: true });
    return withDistance.length;
  } catch (error) {
    console.error("[Crew] SOS alert failed:", error);
    return 0;
  }
}

/** A crew member answers "I'm going" / "Can't help"; the rider is told. */
export async function respondToCrewSOS(uid: string, sosEventId: unknown, response: unknown): Promise<void> {
  if (typeof sosEventId !== "string" || !sosEventId) throw new CrewError(400, "sosEventId is required");
  if (!(CREW_RESPONSES as readonly string[]).includes(response as string)) throw new CrewError(400, "response must be going or cant_help");
  const ref = db().collection("sos_events").doc(sosEventId);
  const sos = await ref.get();
  if (!sos.exists || sos.data()?.resolvedAt) throw new CrewError(404, "SOS not found or already ended");
  const personId = sos.data()!.protectedPersonId as string;
  const myCrew = await crewIdOf(uid);
  if (!myCrew || myCrew !== (await crewIdOf(personId)) || uid === personId) throw new CrewError(403, "not in this rider's crew");
  const me = await positionOf(uid);
  const s = sos.data()!;
  const distanceM = me && isCoord(s.latitude, s.longitude)
    ? Math.round(distanceMeters(me, { latitude: s.latitude, longitude: s.longitude })) : null;
  await ref.set({ crewResponses: { [uid]: { response, at: ts(new Date()), distanceM } } }, { merge: true });
  const name = ((await db().collection("users").doc(uid).get()).data()?.displayName as string) ?? "";
  await sendCrewResponseNotification(personId, name, response as CrewResponse, distanceM, sosEventId);
}

/** What the rider's own SOS screen shows about the crew. */
export async function crewResponsesFor(sos: FirebaseFirestore.DocumentData) {
  const responses = (sos.crewResponses ?? {}) as Record<string, { response: string; at: unknown; distanceM: number | null }>;
  return Promise.all(Object.entries(responses).map(async ([memberId, r]) => ({
    memberId,
    name: ((await db().collection("users").doc(memberId).get()).data()?.displayName as string) ?? "",
    response: r.response,
    at: iso(r.at),
    distanceM: r.distanceM ?? null,
  })));
}

/** Open SOS events of the caller's crew mates (for the crew alert screen). */
export async function crewAlerts(uid: string) {
  const crewId = await crewIdOf(uid);
  if (!crewId) return [];
  const crew = (await db().collection("crews").doc(crewId).get()).data();
  const others = ((crew?.memberIds ?? []) as string[]).filter((m) => m !== uid);
  const me = await positionOf(uid);
  const out = [];
  for (const id of others) {
    const snap = await db().collection("sos_events").where("protectedPersonId", "==", id).where("resolvedAt", "==", null).get();
    for (const doc of snap.docs) {
      const s = doc.data();
      const name = ((await db().collection("users").doc(id).get()).data()?.displayName as string) ?? "";
      const hasPos = isCoord(s.latitude, s.longitude);
      out.push({
        sosEventId: doc.id,
        riderId: id,
        riderName: name,
        triggeredAt: iso(s.triggeredAt),
        latitude: hasPos ? s.latitude : null,
        longitude: hasPos ? s.longitude : null,
        distanceM: me && hasPos ? Math.round(distanceMeters(me, { latitude: s.latitude, longitude: s.longitude })) : null,
        myResponse: (s.crewResponses?.[uid]?.response as string | undefined) ?? null,
        responses: await crewResponsesFor(s),
      });
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Shift not ended (scheduled)
// ---------------------------------------------------------------------------

/** Shifts past their planned end + grace: tell crew and guardians once. */
export async function checkOverdueShifts(now: Date = new Date()): Promise<number> {
  const due = await db().collection("rider_shifts").where("checkDueAt", "<=", ts(now)).get();
  let alerted = 0;
  for (const doc of due.docs) {
    const shift = doc.data();
    if (shift.overdueAlerted === true) continue;
    const uid = doc.id;
    const name = ((await db().collection("users").doc(uid).get()).data()?.displayName as string) ?? "";
    const planned = shift.plannedEnd instanceof admin.firestore.Timestamp ? shift.plannedEnd.toDate() : now;
    const minutes = Math.max(1, Math.round((now.getTime() - planned.getTime()) / 60000));
    // The shift's watchers; a shift without any falls back to the whole crew and all guardians
    const watchers: string[] = Array.isArray(shift.watcherIds) ? shift.watcherIds : [];
    const crew = shift.crewId ? (await db().collection("crews").doc(shift.crewId).get()).data() : null;
    const recipients = new Set<string>(watchers.length > 0 ? watchers : [
      ...((crew?.memberIds ?? []) as string[]).filter((m) => m !== uid),
      ...(await activeGuardianIds(uid)),
    ]);
    await Promise.all([...recipients].map((to) => sendShiftOverdueNotification(to, name, minutes, uid)));
    await doc.ref.update({ overdueAlerted: true });
    alerted++;
  }
  return alerted;
}


// ---------------------------------------------------------------------------
// "Still OK?" during a shift (Settings → Rider → night check)
// ---------------------------------------------------------------------------

function inHours(hour: number, from: number, to: number): boolean {
  return from === to ? true : from < to ? hour >= from && hour < to : hour >= from || hour < to;
}

/**
 * Every minute (checkHomeTimerExpiry): ask "Still OK?" when due inside the chosen
 * hours; no answer within 10 minutes → the shift's watchers are told, and the next
 * check is scheduled. Returns how many riders were asked or reported.
 */
export async function checkStillOk(now: Date = new Date()): Promise<number> {
  const due = await db().collection("rider_shifts").where("stillOk.nextAt", "<=", ts(now)).get();
  let acted = 0;
  for (const doc of due.docs) {
    const shift = doc.data();
    const cfg = shift.stillOk;
    if (!cfg) continue;
    const uid = doc.id;
    const user = (await db().collection("users").doc(uid).get()).data() ?? {};
    const next = ts(new Date(now.getTime() + cfg.everyMin * 60_000));
    if (cfg.sentAt) {
      if (now.getTime() - cfg.sentAt.toMillis() < STILL_OK_ANSWER_MS) continue;
      // No answer
      const watchers: string[] = Array.isArray(shift.watcherIds) && shift.watcherIds.length
        ? shift.watcherIds : await activeGuardianIds(uid);
      await Promise.all(watchers.map((w) => sendShiftStillOkMissed(w, (user.displayName as string) ?? "", uid).catch(() => undefined)));
      await doc.ref.update({ "stillOk.sentAt": null, "stillOk.nextAt": next, "stillOk.missedAt": ts(now) });
      acted++;
      continue;
    }
    if (!inHours(localTime(now, user.timeZone).hour, cfg.fromHour, cfg.toHour)) {
      await doc.ref.update({ "stillOk.nextAt": next });
      continue;
    }
    await sendShiftStillOk(uid).catch(() => undefined);
    // Answer window: checked again once it has passed
    await doc.ref.update({ "stillOk.sentAt": ts(now), "stillOk.nextAt": ts(new Date(now.getTime() + STILL_OK_ANSWER_MS)) });
    acted++;
  }
  return acted;
}

/** The rider answered (the "Still OK?" button, or any check-in). */
export async function confirmStillOk(uid: string, now: Date = new Date()): Promise<boolean> {
  const ref = db().collection("rider_shifts").doc(uid);
  const shift = (await ref.get()).data();
  if (!shift?.stillOk?.sentAt) return false;
  await ref.update({
    "stillOk.sentAt": null,
    "stillOk.nextAt": ts(new Date(now.getTime() + shift.stillOk.everyMin * 60_000)),
  });
  return true;
}
