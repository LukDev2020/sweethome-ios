import * as admin from "firebase-admin";
import * as crypto from "crypto";
import { v4 as uuidv4 } from "uuid";
import { queryLocations, queryHeartbeats } from "./bigquery";
import { distanceMeters } from "./sosTracking";
import { fallsBetween } from "./safetyEvents";
import { sendIncidentReportCreated } from "./fcm";
import { toIso } from "./time";

// ---------------------------------------------------------------------------
// Incident reports for police (docs/police-incident-report.md)
// ---------------------------------------------------------------------------
//
// The server gathers everything about one person in a window — positions from every
// place they are kept, activity, falls, SOS, check-ins, key events, gaps — as one
// canonical JSON string and hashes it before the phone sees it. The phone saves that
// string as data.json byte for byte, draws the PDF / maps / GPX / CSV from it, and
// seals their hashes here once. Police check a file with the verify code.
// Only the person, or a guardian who may see their location, can make one; the person
// is told whenever someone else does. The registry keeps hashes and metadata only.

export class IncidentReportError extends Error {
  constructor(public status: number, message: string) { super(message); }
}

export const MAX_WINDOW_MS = 7 * 24 * 3600_000;
export const MAX_POINTS = 20_000;
/** No position for this long is shown as a gap */
export const GAP_MS = 30 * 60_000;
export const PURPOSES = ["missing_person", "assault", "accident", "harassment", "other"] as const;
export type Purpose = (typeof PURPOSES)[number];
export const SECTIONS = ["locations", "activity", "falls", "sos", "checkins", "events", "device"] as const;
export type Section = (typeof SECTIONS)[number];
/** No 0/O, 1/I/L: read out over the phone */
const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
const FILE_NAME_RE = /^[A-Za-z0-9._-]{1,64}$/;
const SHA256_RE = /^[a-f0-9]{64}$/;

const db = () => admin.firestore();

export type ReporterRole = "self" | "guardian";

/** The person themselves, or an active guardian allowed to see their location. */
export async function authorizeReport(uid: string, personId: string): Promise<ReporterRole> {
  if (uid === personId) return "self";
  const link = (await db().collection("guardian_links").doc(`${uid}_${personId}`).get()).data();
  if (link?.status === "active" && link.permissions?.canSeeLocation !== false) return "guardian";
  throw new IncidentReportError(403, "Only the person or their guardian can make this report");
}

// MARK: - Data shapes (what data.json holds)

export type LocationSource = "history" | "trip" | "sos" | "checkin" | "fall";
export interface ReportPoint {
  at: string; latitude: number; longitude: number;
  accuracy: number | null; speed: number | null; altitude: number | null;
  activity: string | null; source: LocationSource;
}
export interface ActivitySegment { activity: string; start: string; end: string; distanceMeters: number; points: number }
export interface Gap { from: string; to: string; minutes: number }

const isCoord = (lat: unknown, lng: unknown) =>
  typeof lat === "number" && typeof lng === "number" && Number.isFinite(lat) && Number.isFinite(lng) &&
  Math.abs(lat) <= 90 && Math.abs(lng) <= 180 && !(lat === 0 && lng === 0);
const n = (v: unknown): number | null => (typeof v === "number" && Number.isFinite(v) ? v : null);

/** Source order when two sources hold the same moment and place */
const SOURCE_RANK: Record<LocationSource, number> = { history: 0, trip: 1, sos: 2, checkin: 3, fall: 4 };

/** Sorted, de-duplicated (same second, within 5 m), capped by thinning evenly. */
export function mergePoints(points: ReportPoint[]): { points: ReportPoint[]; thinned: boolean } {
  const sorted = points
    .filter((p) => isCoord(p.latitude, p.longitude) && Number.isFinite(Date.parse(p.at)))
    .sort((a, b) => Date.parse(a.at) - Date.parse(b.at) || SOURCE_RANK[a.source] - SOURCE_RANK[b.source]);
  const out: ReportPoint[] = [];
  for (const p of sorted) {
    const last = out[out.length - 1];
    if (last && Math.abs(Date.parse(p.at) - Date.parse(last.at)) < 1000 && distanceMeters(last, p) < 5) {
      // Keep the better source, but don't lose what it lacks
      last.activity = last.activity ?? p.activity;
      last.speed = last.speed ?? p.speed;
      continue;
    }
    out.push({ ...p });
  }
  if (out.length <= MAX_POINTS) return { points: out, thinned: false };
  // Keep event points (SOS / check-in / fall) and the ends; thin the rest evenly
  const keep = out.filter((p, i) => p.source !== "history" && p.source !== "trip" || i === 0 || i === out.length - 1);
  const rest = out.filter((p, i) => !(p.source !== "history" && p.source !== "trip" || i === 0 || i === out.length - 1));
  const room = Math.max(0, MAX_POINTS - keep.length);
  const step = rest.length / Math.max(room, 1);
  const thinned = room > 0 ? Array.from({ length: room }, (_, i) => rest[Math.floor(i * step)]) : [];
  return {
    points: [...keep, ...thinned].sort((a, b) => Date.parse(a.at) - Date.parse(b.at)),
    thinned: true,
  };
}

/** Activity from the phone's motion tag, else from speed (m/s). */
export function activityOf(p: ReportPoint): string {
  const tag = p.activity?.toLowerCase();
  if (tag && ["stationary", "walking", "running", "cycling", "driving", "automotive"].includes(tag)) {
    return tag === "automotive" ? "driving" : tag;
  }
  if (p.speed == null || p.speed < 0) return "unknown";
  if (p.speed < 0.5) return "stationary";
  if (p.speed < 2.2) return "walking";
  if (p.speed < 4.5) return "running";
  if (p.speed < 8) return "cycling";
  return "driving";
}

/** Consecutive points with the same activity, short blips folded into their neighbours. */
export function activitySegments(points: ReportPoint[]): ActivitySegment[] {
  const segs: ActivitySegment[] = [];
  let prev: ReportPoint | null = null;
  for (const p of points) {
    const act = activityOf(p);
    const last = segs[segs.length - 1];
    const step = prev ? distanceMeters(prev, p) : 0;
    const gapped = prev ? Date.parse(p.at) - Date.parse(prev.at) > GAP_MS : false;
    if (last && !gapped && (last.activity === act || act === "unknown")) {
      last.end = p.at;
      last.distanceMeters += step;
      last.points += 1;
    } else {
      // The way here was travelled in the previous activity
      if (last && !gapped) last.distanceMeters += step;
      segs.push({ activity: act, start: p.at, end: p.at, distanceMeters: 0, points: 1 });
    }
    prev = p;
  }
  // A one-point blip between two segments of the same kind joins them
  const folded: ActivitySegment[] = [];
  for (const s of segs) {
    const last = folded[folded.length - 1];
    if (last && s.points <= 1 && Date.parse(s.end) - Date.parse(s.start) < 120_000) {
      last.end = s.end;
      last.distanceMeters += s.distanceMeters;
      last.points += s.points;
      continue;
    }
    if (last && last.activity === s.activity) {
      last.end = s.end;
      last.distanceMeters += s.distanceMeters;
      last.points += s.points;
      continue;
    }
    folded.push(s);
  }
  return folded.map((s) => ({ ...s, distanceMeters: Math.round(s.distanceMeters) }));
}

/** Stretches without a position, including the window's ends. */
export function findGaps(points: ReportPoint[], start: Date, end: Date): Gap[] {
  const times = [start.getTime(), ...points.map((p) => Date.parse(p.at)), Math.min(end.getTime(), Date.now())];
  const gaps: Gap[] = [];
  for (let i = 1; i < times.length; i++) {
    const d = times[i] - times[i - 1];
    if (d > GAP_MS) {
      gaps.push({ from: new Date(times[i - 1]).toISOString(), to: new Date(times[i]).toISOString(), minutes: Math.round(d / 60_000) });
    }
  }
  return gaps;
}

/** Stable JSON: keys sorted at every level, so the same data always hashes the same. */
export function canonicalJSON(value: unknown): string {
  const norm = (v: unknown): unknown => {
    if (Array.isArray(v)) return v.map(norm);
    if (v && typeof v === "object") {
      const o = v as Record<string, unknown>;
      return Object.keys(o).sort().reduce<Record<string, unknown>>((acc, k) => {
        if (o[k] !== undefined) acc[k] = norm(o[k]);
        return acc;
      }, {});
    }
    return v;
  };
  return JSON.stringify(norm(value));
}

export const sha256 = (s: string | Buffer) => crypto.createHash("sha256").update(s).digest("hex");

function verifyCode(): string {
  const bytes = crypto.randomBytes(8);
  return Array.from(bytes, (b) => CODE_ALPHABET[b % CODE_ALPHABET.length]).join("");
}

// MARK: - Request validation

export interface ReportRequest {
  personId: string; start: Date; end: Date; purpose: Purpose; caseNumber: string | null; sections: Section[];
}

export function parseReportRequest(body: Record<string, unknown>, now = Date.now()): ReportRequest {
  const { personId, windowStart, windowEnd, purpose, caseNumber, sections } = body;
  if (typeof personId !== "string" || !personId) throw new IncidentReportError(400, "personId is required");
  const start = typeof windowStart === "string" ? new Date(windowStart) : null;
  const end = typeof windowEnd === "string" ? new Date(windowEnd) : null;
  if (!start || !end || isNaN(start.getTime()) || isNaN(end.getTime())) throw new IncidentReportError(400, "windowStart and windowEnd are required (ISO 8601)");
  if (end <= start) throw new IncidentReportError(400, "windowEnd must be after windowStart");
  if (end.getTime() > now + 5 * 60_000) throw new IncidentReportError(400, "windowEnd is in the future");
  if (end.getTime() - start.getTime() > MAX_WINDOW_MS) throw new IncidentReportError(400, "The window can be at most 7 days");
  const p = (PURPOSES as readonly string[]).includes(String(purpose)) ? (purpose as Purpose) : "other";
  const cn = typeof caseNumber === "string" && caseNumber.trim() ? caseNumber.trim().slice(0, 40) : null;
  const wanted = Array.isArray(sections)
    ? SECTIONS.filter((s) => (sections as unknown[]).includes(s))
    : [...SECTIONS];
  return { personId, start, end, purpose: p, caseNumber: cn, sections: wanted.length ? wanted : [...SECTIONS] };
}

// MARK: - Gathering

const tsRange = (q: FirebaseFirestore.Query, field: string, start: Date, end: Date) =>
  q.where(field, ">=", admin.firestore.Timestamp.fromDate(start))
    .where(field, "<=", admin.firestore.Timestamp.fromDate(end))
    .orderBy(field, "asc");

/** Interesting timeline types for the "key events" list (not every location update) */
const KEY_EVENT_TYPES = new Set([
  "checkIn", "sosTriggered", "sosResolved", "enteredSafeZone", "leftSafeZone", "missedCheckIn", "batteryLow",
  "phoneInactive", "fallDetected", "homeTimerSet", "homeTimerDismissed", "homeTimerExpired", "arrivalReport",
  "trackingPaused", "trackingResumed", "ble_separation", "silent_alarm_confirmed", "silent_alarm_missed",
  "silent_alarm_escalated",
]);

async function nameOf(uid: string | null | undefined): Promise<string | null> {
  if (!uid) return null;
  return ((await db().collection("users").doc(uid).get()).data()?.displayName as string) ?? null;
}

export async function gatherReportData(req: ReportRequest) {
  const { personId, start, end, sections } = req;
  const want = (s: Section) => sections.includes(s);
  const sources: Record<string, "ok" | "unavailable" | "skipped"> = {};
  const attempt = async <T>(name: string, on: boolean, work: () => Promise<T>, empty: T): Promise<T> => {
    if (!on) { sources[name] = "skipped"; return empty; }
    try { const r = await work(); sources[name] = "ok"; return r; } catch (error) {
      console.warn(`[IncidentReport] ${name} unavailable:`, error);
      sources[name] = "unavailable";
      return empty;
    }
  };
  const needPositions = want("locations") || want("activity");

  const [user, history, heartbeats, sosDocs, timeline, checkins, trips, falls] = await Promise.all([
    db().collection("users").doc(personId).get().then((d) => d.data() ?? {}),
    attempt("locationHistory", needPositions, () => queryLocations(personId, start.toISOString(), end.toISOString()), [] as Record<string, unknown>[]),
    attempt("heartbeats", want("device"), () => queryHeartbeats(personId, start.toISOString(), end.toISOString()), [] as Record<string, unknown>[]),
    attempt("sos", want("sos") || needPositions, async () =>
      (await tsRange(db().collection("sos_events").where("protectedPersonId", "==", personId), "triggeredAt", start, end).get()).docs,
    [] as FirebaseFirestore.QueryDocumentSnapshot[]),
    attempt("timeline", want("events"), async () =>
      (await tsRange(db().collection("timeline_entries").where("userId", "==", personId), "timestamp", start, end).get()).docs.map((d) => d.data()),
    [] as FirebaseFirestore.DocumentData[]),
    attempt("checkins", want("checkins") || needPositions, async () =>
      (await tsRange(db().collection("checkins").where("userId", "==", personId), "timestamp", start, end).get()).docs.map((d) => d.data()),
    [] as FirebaseFirestore.DocumentData[]),
    attempt("trips", needPositions, async () => {
      // Trips that started before the window's end; the points themselves are filtered by time
      const snap = await db().collection("trips").where("userId", "==", personId)
        .where("startTime", "<=", admin.firestore.Timestamp.fromDate(end)).orderBy("startTime", "desc").limit(30).get();
      const out: Record<string, unknown>[] = [];
      for (const t of snap.docs) {
        const endTime = t.data().endTime?.toDate?.() as Date | undefined;
        if (endTime && endTime < start) continue;
        const pts = await t.ref.collection("points").orderBy("timestamp", "asc").limit(5000).get();
        out.push(...pts.docs.map((p) => p.data()));
      }
      return out;
    }, [] as Record<string, unknown>[]),
    attempt("falls", want("falls") || needPositions, () => fallsBetween(personId, start, end), [] as FirebaseFirestore.DocumentData[]),
  ]);

  const inWindow = (iso: string | null) => !!iso && Date.parse(iso) >= start.getTime() && Date.parse(iso) <= end.getTime();

  // Positions from every place they are kept
  const raw: ReportPoint[] = [];
  for (const r of history) {
    raw.push({ at: String(r.timestamp), latitude: r.latitude as number, longitude: r.longitude as number,
      accuracy: n(r.accuracy), speed: n(r.speed), altitude: n(r.altitude),
      activity: typeof r.activity_type === "string" ? r.activity_type : null, source: "history" });
  }
  for (const r of trips) {
    const at = toIso(r.timestamp);
    if (!inWindow(at)) continue;
    raw.push({ at: at!, latitude: r.latitude as number, longitude: r.longitude as number,
      accuracy: n(r.accuracy), speed: n(r.speed), altitude: n(r.altitude),
      activity: typeof r.activityType === "string" ? r.activityType : null, source: "trip" });
  }
  for (const d of sosDocs) {
    const x = d.data();
    const at = toIso(x.triggeredAt);
    if (isCoord(x.latitude, x.longitude) && at) {
      raw.push({ at, latitude: x.latitude, longitude: x.longitude, accuracy: n(x.accuracy), speed: null, altitude: null, activity: null, source: "sos" });
    }
    for (const p of Array.isArray(x.trail) ? x.trail : []) {
      if (inWindow(p.at)) raw.push({ at: p.at, latitude: p.latitude, longitude: p.longitude, accuracy: null, speed: null, altitude: null, activity: null, source: "sos" });
    }
  }
  for (const c of checkins) {
    const at = toIso(c.timestamp);
    if (at && isCoord(c.latitude, c.longitude)) {
      raw.push({ at, latitude: c.latitude, longitude: c.longitude, accuracy: null, speed: null, altitude: null, activity: null, source: "checkin" });
    }
  }
  for (const f of falls) {
    const at = toIso(f.detectedAt);
    if (at && isCoord(f.latitude, f.longitude)) {
      raw.push({ at, latitude: f.latitude, longitude: f.longitude, accuracy: n(f.accuracy), speed: null, altitude: null, activity: null, source: "fall" });
    }
  }
  const merged = mergePoints(raw);
  const points = merged.points;

  const sos = want("sos") ? await Promise.all(sosDocs.map(async (d) => {
    const x = d.data();
    return {
      id: d.id,
      triggeredAt: toIso(x.triggeredAt),
      triggerMethod: x.triggerMethod ?? null,
      latitude: n(x.latitude), longitude: n(x.longitude),
      batteryLevel: n(x.batteryLevel),
      escalationState: x.escalationState ?? null,
      acknowledgedBy: await nameOf(x.acknowledgedBy),
      acknowledgedAt: toIso(x.acknowledgedAt),
      resolvedAt: toIso(x.resolvedAt),
      resolution: x.resolution ?? null,
      trail: (Array.isArray(x.trail) ? x.trail : []).map((p: Record<string, unknown>) => ({ latitude: p.latitude, longitude: p.longitude, at: p.at })),
    };
  })) : [];

  const fallList = want("falls") ? falls.map((f) => ({
    detectedAt: toIso(f.detectedAt),
    latitude: n(f.latitude), longitude: n(f.longitude), accuracy: n(f.accuracy),
    batteryLevel: n(f.batteryLevel),
    metrics: f.metrics ?? {},
    outcome: f.outcome,
    respondedAfterSec: n(f.respondedAfterSec),
    sosEventId: f.sosEventId ?? null,
  })) : [];

  const checkinList = want("checkins") ? checkins.map((c) => ({
    at: toIso(c.timestamp), latitude: n(c.latitude), longitude: n(c.longitude), note: typeof c.note === "string" ? c.note : null,
  })) : [];

  const events = want("events") ? timeline
    .filter((e) => KEY_EVENT_TYPES.has(String(e.type)))
    .map((e) => ({ at: toIso(e.timestamp), type: String(e.type), description: typeof e.description === "string" ? e.description : "" })) : [];

  const battery = heartbeats
    .map((h) => ({ at: String(h.timestamp), level: n(h.battery_level), state: (h.battery_state as string) ?? null }))
    .filter((h) => h.level != null)
    .sort((a, b) => Date.parse(a.at) - Date.parse(b.at));

  const last = points[points.length - 1] ?? null;
  return {
    person: {
      id: personId,
      name: (user.displayName as string) ?? null,
      phone: (user.phone as string) ?? null,
      timeZone: (user.timeZone as string) ?? null,
    },
    window: { start: start.toISOString(), end: end.toISOString() },
    sources,
    summary: {
      lastKnown: last,
      lastCheckIn: checkinList.length ? checkinList[checkinList.length - 1] : null,
      lastBattery: battery.length ? battery[battery.length - 1] : null,
      counts: { points: points.length, sos: sos.length, falls: fallList.length, checkins: checkinList.length },
      thinned: merged.thinned,
    },
    locations: want("locations") ? points : [],
    activity: want("activity") ? activitySegments(points) : [],
    gaps: needPositions ? findGaps(points, start, end) : [],
    falls: fallList,
    sos,
    checkins: checkinList,
    events,
    battery: want("device") ? battery : [],
  };
}

// MARK: - Create / seal / verify

export async function createIncidentReport(uid: string, body: Record<string, unknown>) {
  const req = parseReportRequest(body);
  const role = await authorizeReport(uid, req.personId);
  const reportId = `R-${uuidv4().slice(0, 8).toUpperCase()}`;
  const code = verifyCode();
  const now = admin.firestore.Timestamp.now();
  const reporterName = await nameOf(uid);

  const data = await gatherReportData(req);
  const report = {
    reportId,
    verifyCode: code,
    generatedAt: now.toDate().toISOString(),
    generator: "Lantern Care incident report v1",
    purpose: req.purpose,
    caseNumber: req.caseNumber,
    sections: req.sections,
    reporter: { id: uid, name: reporterName, role },
    ...data,
  };
  const canonical = canonicalJSON(report);
  const dataSha256 = sha256(canonical);

  await db().collection("incident_reports").doc(reportId).set({
    personId: req.personId,
    createdBy: uid,
    createdByRole: role,
    purpose: req.purpose,
    caseNumber: req.caseNumber,
    sections: req.sections,
    windowStart: admin.firestore.Timestamp.fromDate(req.start),
    windowEnd: admin.firestore.Timestamp.fromDate(req.end),
    verifyCode: code,
    dataSha256,
    sources: data.sources,
    counts: data.summary.counts,
    files: null,
    sealedAt: null,
    createdAt: now,
  });
  await audit(reportId, "create", uid);

  // The person always learns about a report someone else made
  if (role === "guardian") {
    await db().collection("timeline_entries").add({
      userId: req.personId,
      timestamp: now,
      type: "incidentReport",
      description: `${reporterName ?? ""} created a police report`.trim(),
      detail: `${req.start.toISOString()} – ${req.end.toISOString()}`,
    });
    await sendIncidentReportCreated(req.personId, reporterName ?? "").catch(() => undefined);
  }
  return { reportId, verifyCode: code, dataSha256, canonical };
}

export async function sealIncidentReport(uid: string, reportId: string, files: unknown) {
  if (!files || typeof files !== "object" || Array.isArray(files)) throw new IncidentReportError(400, "files is required");
  const entries = Object.entries(files as Record<string, unknown>);
  if (entries.length === 0 || entries.length > 16) throw new IncidentReportError(400, "1–16 files");
  for (const [name, hash] of entries) {
    if (!FILE_NAME_RE.test(name) || typeof hash !== "string" || !SHA256_RE.test(hash)) {
      throw new IncidentReportError(400, `bad file entry: ${name}`);
    }
  }
  const ref = db().collection("incident_reports").doc(reportId);
  await db().runTransaction(async (tx) => {
    const r = (await tx.get(ref)).data();
    if (!r || r.createdBy !== uid) throw new IncidentReportError(404, "No such report");
    if (r.files) throw new IncidentReportError(409, "Already sealed");
    tx.update(ref, { files: Object.fromEntries(entries), sealedAt: admin.firestore.Timestamp.now() });
  });
  await audit(reportId, "seal", uid);
}

/** Reports about me, or the ones I made about someone I look after. */
export async function listIncidentReports(uid: string, personId: string) {
  const role = await authorizeReport(uid, personId);
  let q: FirebaseFirestore.Query = db().collection("incident_reports").where("personId", "==", personId);
  if (role === "guardian") q = q.where("createdBy", "==", uid);
  const snap = await q.orderBy("createdAt", "desc").limit(50).get();
  return Promise.all(snap.docs.map(async (d) => {
    const r = d.data();
    return {
      reportId: d.id,
      createdAt: toIso(r.createdAt),
      createdBy: await nameOf(r.createdBy),
      createdBySelf: r.createdBy === uid,
      purpose: r.purpose,
      windowStart: toIso(r.windowStart),
      windowEnd: toIso(r.windowEnd),
      sealed: !!r.files,
    };
  }));
}

/**
 * Public. With only the code: what the report is (no names, no data). With a file's
 * SHA-256 as well: whether that exact file belongs to it.
 */
export async function verifyIncidentReport(code: unknown, hash: unknown, who: string) {
  if (typeof code !== "string" || !/^[A-Z2-9]{8}$/.test(code.toUpperCase())) throw new IncidentReportError(400, "code is required");
  const snap = await db().collection("incident_reports").where("verifyCode", "==", code.toUpperCase()).limit(1).get();
  if (snap.empty) return { valid: false as const };
  const doc = snap.docs[0];
  const r = doc.data();
  const files: Record<string, string> = { "data.json": r.dataSha256, ...(r.files ?? {}) };
  await audit(doc.id, "verify", who);
  const base = {
    valid: true as const,
    reportId: doc.id,
    createdAt: toIso(r.createdAt),
    windowStart: toIso(r.windowStart),
    windowEnd: toIso(r.windowEnd),
    purpose: r.purpose,
    caseNumber: r.caseNumber ?? null,
    sealed: !!r.files,
    files,
  };
  if (typeof hash === "string" && hash) {
    const h = hash.toLowerCase();
    const match = Object.entries(files).find(([, v]) => v === h);
    return { ...base, fileMatches: !!match, file: match?.[0] ?? null };
  }
  return base;
}

async function audit(reportId: string, action: "create" | "seal" | "verify", who: string) {
  await db().collection("incident_report_audit").add({
    reportId, action, who, at: admin.firestore.Timestamp.now(),
  }).catch((e) => console.warn("[IncidentReport] audit failed:", e));
}
