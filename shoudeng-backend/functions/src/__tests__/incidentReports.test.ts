/**
 * Incident reports for police (services/incidentReport.ts):
 *  - who may make one: the person, or a guardian who may see their location
 *  - positions merged from history, trips, SOS trails, check-ins and falls (and still
 *    a trail when BigQuery is down), with activity segments and gaps
 *  - data.json is hashed on the server: the canonical string hashes to dataSha256
 *  - the person is told when a guardian makes one
 *  - seal once; verify by code (no names), and by a file's SHA-256
 */
jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);
let mockHistory: Record<string, unknown>[] | Error = [];
jest.mock("../services/bigquery", () => ({
  ...jest.requireActual("../services/bigquery"),
  queryLocations: jest.fn(async () => { if (mockHistory instanceof Error) throw mockHistory; return mockHistory; }),
  queryHeartbeats: jest.fn(async () => [{ timestamp: "2026-11-06T20:00:00.000Z", battery_level: 0.32, battery_state: "unplugged" }]),
}));
const mockPushes: { kind: string; to: string }[] = [];
jest.mock("../services/fcm", () => ({
  ...jest.requireActual("../services/fcm"),
  sendIncidentReportCreated: jest.fn(async (to: string) => { mockPushes.push({ kind: "report", to }); }),
}));

import express from "express";
import request from "supertest";
import * as crypto from "crypto";
import { resetFakeAdmin, seed, readDoc, listDocs, ts, tokenFor } from "./helpers/fakeAdmin";
import { activitySegments, findGaps, mergePoints, canonicalJSON, ReportPoint, MAX_POINTS } from "../services/incidentReport";

const app = express();
app.use(express.json());
app.set("trust proxy", 1);
app.use("/v1/incident-reports", require("../routes/incidentReports").default);
const as = (uid: string) => ({
  get: (p: string) => request(app).get(p).set("Authorization", `Bearer ${tokenFor(uid)}`),
  post: (p: string, body: object = {}) => request(app).post(p).set("Authorization", `Bearer ${tokenFor(uid)}`).send(body),
});
const sha = (s: string) => crypto.createHash("sha256").update(s).digest("hex");

const START = "2026-11-06T18:00:00.000Z";
const END = "2026-11-06T22:00:00.000Z";
const body = (extra: object = {}) => ({ personId: "mom", windowStart: START, windowEnd: END, purpose: "missing_person", caseNumber: "TPS-2026-1188", ...extra });
const at = (min: number) => new Date(Date.parse(START) + min * 60_000).toISOString();

beforeEach(() => {
  resetFakeAdmin();
  mockPushes.length = 0;
  mockHistory = [
    { timestamp: at(0), latitude: 43.6500, longitude: -79.3800, accuracy: 8, speed: 0, altitude: 90 },
    { timestamp: at(5), latitude: 43.6510, longitude: -79.3790, accuracy: 10, speed: 1.3, altitude: 90 },
    { timestamp: at(10), latitude: 43.6530, longitude: -79.3770, accuracy: 9, speed: 1.4, altitude: 90 },
    { timestamp: at(15), latitude: 43.6700, longitude: -79.3600, accuracy: 15, speed: 13, altitude: 92 },
    { timestamp: at(20), latitude: 43.6900, longitude: -79.3400, accuracy: 15, speed: 14, altitude: 95 },
    // 90-minute silence, then the SOS
  ];
  seed("users/mom", { displayName: "Mom", role: "protected", phone: "+14165550101", timeZone: "America/Toronto" });
  seed("users/sarah", { displayName: "Sarah", role: "guardian" });
  seed("users/kevin", { displayName: "Kevin", role: "guardian" });
  seed("users/crewmate", { displayName: "Kai", role: "protected" });
  seed("guardian_links/sarah_mom", { guardianId: "sarah", protectedPersonId: "mom", status: "active" });
  seed("guardian_links/kevin_mom", { guardianId: "kevin", protectedPersonId: "mom", status: "active", permissions: { canSeeLocation: false } });
  seed("sos_events/sos1", {
    protectedPersonId: "mom", triggeredAt: ts(at(110)), triggerMethod: "fallDetection", latitude: 43.7000, longitude: -79.3300,
    batteryLevel: 0.3, acknowledgedBy: "sarah", acknowledgedAt: ts(at(112)), resolvedAt: null, escalationState: "frozen",
    trail: [{ latitude: 43.7001, longitude: -79.3301, at: at(115) }],
  });
  seed("safety_events/mom_f1", {
    userId: "mom", type: "fall", detectedAt: ts(at(109)), latitude: 43.7000, longitude: -79.3300, accuracy: 20,
    metrics: { peakImpactG: 3.6, freeFallMs: 440, orientationChangeDeg: 88, stillnessVariance: 0.001, detector: "threshold-v2" },
    outcome: "escalated", respondedAfterSec: 60, sosEventId: "sos1",
  });
  seed("checkins/c1", { userId: "mom", timestamp: ts(at(2)), latitude: 43.6502, longitude: -79.3799, note: "Leaving the library" });
  seed("timeline_entries/t1", { userId: "mom", timestamp: ts(at(2)), type: "checkIn", description: "Checked in" });
  seed("timeline_entries/t2", { userId: "mom", timestamp: ts(at(3)), type: "locationUpdate", description: "noise" });
  seed("trips/trip1", { userId: "mom", status: "completed", startTime: ts(at(14)), endTime: ts(at(21)) });
  seed("trips/trip1/points/p1", { latitude: 43.6800, longitude: -79.3500, accuracy: 6, speed: 13.5, timestamp: at(17), activityType: "automotive" });
});

it("a guardian makes a report: merged trail, activity, falls, SOS, gaps — and Mom is told", async () => {
  const r = await as("sarah").post("/v1/incident-reports", body());
  expect(r.status).toBe(201);
  expect(r.body.reportId).toMatch(/^R-[0-9A-F]{8}$/);
  expect(r.body.verifyCode).toMatch(/^[A-HJ-NP-Z2-9]{8}$/);
  expect(r.body.verifyUrl).toContain(`/v1/incident-reports/verify?code=${r.body.verifyCode}`);

  // data.json is the canonical string, and its hash is what the registry holds
  expect(sha(r.body.canonical)).toBe(r.body.dataSha256);
  const data = JSON.parse(r.body.canonical);
  expect(canonicalJSON(data)).toBe(r.body.canonical);
  expect(readDoc(`incident_reports/${r.body.reportId}`)).toMatchObject({
    personId: "mom", createdBy: "sarah", createdByRole: "guardian", dataSha256: r.body.dataSha256, files: null, caseNumber: "TPS-2026-1188",
  });

  expect(data.person).toEqual({ id: "mom", name: "Mom", phone: "+14165550101", timeZone: "America/Toronto" });
  expect(data.reporter).toEqual({ id: "sarah", name: "Sarah", role: "guardian" });
  // history 5 + trip 1 + SOS 1 + SOS trail 1 + check-in 1 + fall 1 (the fall and the SOS share a place but not a second)
  expect(data.locations.map((p: ReportPoint) => p.source)).toEqual(["history", "checkin", "history", "history", "history", "trip", "history", "fall", "sos", "sos"]);
  expect(data.summary.lastKnown).toMatchObject({ latitude: 43.7001, source: "sos" });
  expect(data.summary.counts).toEqual({ points: 10, sos: 1, falls: 1, checkins: 1 });
  expect(data.activity.map((s: { activity: string }) => s.activity)).toEqual(["stationary", "walking", "driving", "unknown"]);
  expect(data.gaps).toEqual([{ from: at(20), to: at(109), minutes: 89 }, { from: at(115), to: END, minutes: 125 }]);
  expect(data.falls[0]).toMatchObject({ outcome: "escalated", metrics: { peakImpactG: 3.6 }, sosEventId: "sos1" });
  expect(data.sos[0]).toMatchObject({ triggerMethod: "fallDetection", acknowledgedBy: "Sarah", trail: [{ latitude: 43.7001 }] });
  expect(data.events.map((e: { type: string }) => e.type)).toEqual(["checkIn"]);
  expect(data.battery).toEqual([{ at: "2026-11-06T20:00:00.000Z", level: 0.32, state: "unplugged" }]);
  expect(data.sources).toMatchObject({ locationHistory: "ok", trips: "ok", sos: "ok", falls: "ok" });

  // Transparency
  expect(mockPushes).toEqual([{ kind: "report", to: "mom" }]);
  expect(listDocs("timeline_entries").find((d) => d.data.type === "incidentReport")?.data.userId).toBe("mom");
});

it("still has a trail when BigQuery is down, and says so", async () => {
  mockHistory = new Error("Not found: Dataset sweethome-b4e82:shoudeng");
  const r = await as("mom").post("/v1/incident-reports", body());
  expect(r.status).toBe(201);
  const data = JSON.parse(r.body.canonical);
  expect(data.sources.locationHistory).toBe("unavailable");
  expect(data.locations.map((p: ReportPoint) => p.source)).toEqual(["checkin", "trip", "fall", "sos", "sos"]);
  // Her own report: nobody is "told"
  expect(mockPushes).toEqual([]);
  expect(data.reporter.role).toBe("self");
});

it("only the person, or a guardian who may see the location", async () => {
  expect((await as("kevin").post("/v1/incident-reports", body())).status).toBe(403);   // canSeeLocation off
  expect((await as("crewmate").post("/v1/incident-reports", body())).status).toBe(403);
  expect((await request(app).post("/v1/incident-reports").send(body())).status).toBe(401);
});

it("window limits: ≤ 7 days, not in the future, start before end", async () => {
  const day = 86400_000;
  const now = Date.now();
  expect((await as("sarah").post("/v1/incident-reports", body({ windowStart: new Date(now - 8 * day).toISOString(), windowEnd: new Date(now).toISOString() }))).status).toBe(400);
  expect((await as("sarah").post("/v1/incident-reports", body({ windowEnd: new Date(now + day).toISOString() }))).status).toBe(400);
  expect((await as("sarah").post("/v1/incident-reports", body({ windowStart: END, windowEnd: START }))).status).toBe(400);
  expect((await as("sarah").post("/v1/incident-reports", body({ windowStart: "yesterday" }))).status).toBe(400);
});

it("sections switched off are not fetched at all", async () => {
  const r = await as("sarah").post("/v1/incident-reports", body({ sections: ["sos", "falls"] }));
  const data = JSON.parse(r.body.canonical);
  expect(data.locations).toEqual([]);
  expect(data.activity).toEqual([]);
  expect(data.checkins).toEqual([]);
  expect(data.sources).toMatchObject({ locationHistory: "skipped", trips: "skipped", checkins: "skipped" });
  expect(data.sos).toHaveLength(1);
});

it("seal once; police verify by code (no names) and by a file's SHA-256", async () => {
  const r = await as("sarah").post("/v1/incident-reports", body());
  const { reportId, verifyCode, dataSha256 } = r.body;
  const pdf = sha("the pdf bytes");
  expect((await as("mom").post(`/v1/incident-reports/${reportId}/seal`, { files: { "report.pdf": pdf } })).status).toBe(404);
  expect((await as("sarah").post(`/v1/incident-reports/${reportId}/seal`, { files: { "../x": pdf } })).status).toBe(400);
  expect((await as("sarah").post(`/v1/incident-reports/${reportId}/seal`, { files: { "report.pdf": pdf, "track.gpx": sha("gpx") } })).status).toBe(200);
  expect((await as("sarah").post(`/v1/incident-reports/${reportId}/seal`, { files: { "report.pdf": sha("other") } })).status).toBe(409);

  const v = await request(app).get(`/v1/incident-reports/verify?code=${verifyCode.toLowerCase()}`).set("Accept", "application/json");
  expect(v.status).toBe(200);
  expect(v.body).toMatchObject({ valid: true, reportId, sealed: true, caseNumber: "TPS-2026-1188", files: { "data.json": dataSha256, "report.pdf": pdf } });
  expect(JSON.stringify(v.body)).not.toContain("Mom");

  const good = await request(app).get(`/v1/incident-reports/verify?code=${verifyCode}&sha256=${pdf}`).set("Accept", "application/json");
  expect(good.body).toMatchObject({ fileMatches: true, file: "report.pdf" });
  const bad = await request(app).get(`/v1/incident-reports/verify?code=${verifyCode}&sha256=${sha("edited")}`).set("Accept", "application/json");
  expect(bad.body).toMatchObject({ valid: true, fileMatches: false, file: null });

  const none = await request(app).get("/v1/incident-reports/verify?code=ZZZZZZZZ").set("Accept", "application/json");
  expect(none.status).toBe(404);
  const html = await request(app).get(`/v1/incident-reports/verify?code=${verifyCode}&sha256=${pdf}`).set("Accept", "text/html");
  expect(html.text).toContain("unchanged");
  expect(html.text).not.toContain("Mom");
  expect(listDocs("incident_report_audit").map((d) => d.data.action).sort()).toEqual(["create", "seal", "verify", "verify", "verify", "verify"]);
});

it("Mom sees every report about her; Sarah only the ones she made", async () => {
  await as("sarah").post("/v1/incident-reports", body());
  await as("mom").post("/v1/incident-reports", body({ purpose: "harassment" }));
  const mine = (await as("mom").get("/v1/incident-reports")).body.reports;
  expect(mine.map((r: { createdBy: string }) => r.createdBy).sort()).toEqual(["Mom", "Sarah"]);
  const sarahs = (await as("sarah").get("/v1/incident-reports?personId=mom")).body.reports;
  expect(sarahs).toHaveLength(1);
  expect(sarahs[0]).toMatchObject({ createdBySelf: true, purpose: "missing_person", sealed: false });
  expect((await as("kevin").get("/v1/incident-reports?personId=mom")).status).toBe(403);
});

describe("building blocks", () => {
  const p = (min: number, lat: number, extra: Partial<ReportPoint> = {}): ReportPoint =>
    ({ at: at(min), latitude: lat, longitude: -79.38, accuracy: null, speed: null, altitude: null, activity: null, source: "history", ...extra });

  it("dedupes the same moment and place, keeping the better source", () => {
    const { points } = mergePoints([p(1, 43.65, { source: "sos" }), p(1, 43.65000001, { speed: 1.2 }), p(2, 43.66)]);
    expect(points).toHaveLength(2);
    expect(points[0]).toMatchObject({ source: "history", speed: 1.2 });
  });

  it("drops null island and nonsense", () => {
    expect(mergePoints([p(1, 0, { longitude: 0 }), p(2, 95), p(3, 43.6)]).points).toHaveLength(1);
  });

  it(`thins evenly above ${MAX_POINTS} points but keeps every event point`, () => {
    const many = Array.from({ length: MAX_POINTS + 5000 }, (_, i) => ({ ...p(0, 43.6 + i * 1e-5), at: new Date(Date.parse(START) + i * 2000).toISOString() }));
    many[777] = { ...many[777], source: "sos" };
    const { points, thinned } = mergePoints(many);
    expect(thinned).toBe(true);
    expect(points.length).toBe(MAX_POINTS);
    expect(points.some((x) => x.source === "sos")).toBe(true);
  });

  it("activity from the motion tag first, then speed; blips fold in", () => {
    const segs = activitySegments([
      p(0, 43.650, { speed: 1.3 }), p(1, 43.651, { speed: 1.4 }), p(2, 43.652, { speed: 0.2 }), p(3, 43.653, { speed: 1.2 }),
      p(4, 43.660, { activity: "automotive" }), p(6, 43.680, { speed: 15 }),
    ]);
    expect(segs.map((s) => s.activity)).toEqual(["walking", "driving"]);
    expect(segs[0].distanceMeters).toBeGreaterThan(300);
  });

  it("gaps include the window's ends", () => {
    const gaps = findGaps([p(40, 43.6), p(50, 43.6)], new Date(START), new Date(END));
    expect(gaps).toEqual([{ from: START, to: at(40), minutes: 40 }, { from: at(50), to: END, minutes: 190 }]);
  });

  it("canonical JSON sorts keys at every level", () => {
    expect(canonicalJSON({ b: 1, a: { d: [{ z: 1, y: 2 }], c: null } })).toBe('{"a":{"c":null,"d":[{"y":2,"z":1}]},"b":1}');
  });
});
