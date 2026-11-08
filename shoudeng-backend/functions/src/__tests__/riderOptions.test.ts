/**
 * Rider options (Settings → Rider) and crash reports:
 *  - crew SOS: on shift always; off shift only as chosen (none / nearby within N km / all)
 *  - approximate position for the crew, never during your own SOS
 *  - late-shift alert 15 / 30 / 60 min; caution spots 2 / 12 / 24 h
 *  - "Still OK?": asked inside the chosen hours, a check-in answers it, silence tells watchers
 *  - crash reports: not hurt → watchers / guardians (crew if chosen); hurt → recorded, the SOS alerts
 */
jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);
// Never reach real BigQuery from a test (the check-in route writes history)
jest.mock("../services/bigquery", () => ({
  ...jest.requireActual("../services/bigquery"),
  insertCheckin: jest.fn(async () => undefined),
  insertLocationReport: jest.fn(async () => undefined),
  insertHeartbeat: jest.fn(async () => undefined),
  insertConsentAudit: jest.fn(async () => undefined),
}));
const mockPushes: { kind: string; to: string }[] = [];
jest.mock("../services/fcm", () => ({
  ...jest.requireActual("../services/fcm"),
  sendCrewSOSAlert: jest.fn(async (to: string) => { mockPushes.push({ kind: "crewSOS", to }); }),
  sendShiftWatchRequest: jest.fn(async () => undefined),
  sendShiftStillOk: jest.fn(async (to: string) => { mockPushes.push({ kind: "stillOk", to }); }),
  sendShiftStillOkMissed: jest.fn(async (to: string) => { mockPushes.push({ kind: "stillOkMissed", to }); }),
  sendCrashReported: jest.fn(async (to: string) => { mockPushes.push({ kind: "crash", to }); }),
}));

import express from "express";
import request from "supertest";
import { resetFakeAdmin, seed, readDoc, listDocs, ts, tokenFor } from "./helpers/fakeAdmin";
import { alertCrewOfSOS, checkStillOk, checkOverdueShifts } from "../services/crew";

const app = express();
app.use(express.json());
app.use("/v1/crew", require("../routes/crew").default);
app.use("/v1/safety-events", require("../routes/safetyEvents").default);
app.use("/v1", require("../routes/telemetry").default);
const as = (uid: string) => ({
  get: (p: string) => request(app).get(p).set("Authorization", `Bearer ${tokenFor(uid)}`),
  post: (p: string, body: object = {}) => request(app).post(p).set("Authorization", `Bearer ${tokenFor(uid)}`).send(body),
  put: (p: string, body: object = {}) => request(app).put(p).set("Authorization", `Bearer ${tokenFor(uid)}`).send(body),
});

// Melbourne CBD; Wei 220 m away, Ahmed 2.4 km, Lina 8 km
const KAI = { latitude: -37.8122, longitude: 144.9687 };
const at = (dLat: number) => ({ latitude: KAI.latitude + dLat, longitude: KAI.longitude });

beforeEach(() => {
  resetFakeAdmin();
  mockPushes.length = 0;
  for (const [id, name] of [["kai", "Kai"], ["wei", "Wei"], ["ahmed", "Ahmed"], ["lina", "Lina"], ["mum", "Mum"]]) {
    seed(`users/${id}`, { displayName: name, role: id === "mum" ? "guardian" : "protected", crewId: id === "mum" ? undefined : "c1",
      timeZone: "Australia/Melbourne", avatarInitial: name[0] });
  }
  seed("crews/c1", { name: "CBD", ownerId: "kai", memberIds: ["kai", "wei", "ahmed", "lina"], inviteCode: "K7M2QX" });
  seed("guardian_links/mum_kai", { guardianId: "mum", protectedPersonId: "kai", status: "active" });
  seed("user_telemetry/kai", { ...KAI, locationTimestamp: ts(Date.now()) });
  seed("user_telemetry/wei", { ...at(0.002), locationTimestamp: ts(Date.now()) });
  seed("user_telemetry/ahmed", { ...at(0.022), locationTimestamp: ts(Date.now()) });
  seed("user_telemetry/lina", { ...at(0.072), locationTimestamp: ts(Date.now()) });
});

const sos = { protectedPersonId: "kai", ...KAI };
const alerted = () => mockPushes.filter((p) => p.kind === "crewSOS").map((p) => p.to).sort();

describe("crew SOS: who hears it", () => {
  it("default: only crew mates on shift", async () => {
    seed("users/ahmed", { ...readDoc("users/ahmed"), riderOnShift: true });
    await alertCrewOfSOS("s1", sos);
    expect(alerted()).toEqual(["ahmed"]);
  });

  it("off shift: nearby within my radius, or all; on shift always, whatever the setting", async () => {
    await as("wei").put("/v1/crew/prefs", { offShiftAlerts: "nearby", alertRadiusKm: 1 });
    await as("ahmed").put("/v1/crew/prefs", { offShiftAlerts: "nearby", alertRadiusKm: 1 });   // 2.4 km away
    await as("lina").put("/v1/crew/prefs", { offShiftAlerts: "all" });
    await alertCrewOfSOS("s1", sos);
    expect(alerted()).toEqual(["lina", "wei"]);
    expect(readDoc("sos_events/s1")!.crewNotified.sort()).toEqual(["lina", "wei"]);

    mockPushes.length = 0;
    seed("users/ahmed", { ...readDoc("users/ahmed"), riderOnShift: true, riderPrefs: { offShiftAlerts: "none" } });
    await alertCrewOfSOS("s2", sos);
    expect(alerted()).toEqual(["ahmed", "lina", "wei"]);
  });

  it("refuses values outside the choices", async () => {
    for (const body of [{ offShiftAlerts: "sometimes" }, { alertRadiusKm: 2 }, { crewPrecision: "fuzzy" }]) {
      expect((await as("wei").put("/v1/crew/prefs", body)).status).toBe(400);
    }
    expect((await as("wei").put("/v1/crew/prefs", { crewPrecision: "approx" })).body.prefs)
      .toEqual({ offShiftAlerts: "none", alertRadiusKm: 3, crewPrecision: "approx" });
  });
});

describe("what the crew sees", () => {
  it("approximate (~200 m) when chosen, exact to yourself and during your SOS", async () => {
    seed("users/wei", { ...readDoc("users/wei"), riderOnShift: true });
    await as("wei").put("/v1/crew/prefs", { crewPrecision: "approx" });
    const fromKai = (await as("kai").get("/v1/crew")).body.crew.members.find((m: { id: string }) => m.id === "wei");
    expect(fromKai.approximate).toBe(true);
    expect(fromKai.latitude).not.toBe(at(0.002).latitude);
    expect(Math.abs(fromKai.latitude - at(0.002).latitude)).toBeLessThan(0.0011);

    const self = (await as("wei").get("/v1/crew")).body.crew.members.find((m: { id: string }) => m.id === "wei");
    expect(self).toMatchObject({ approximate: false, latitude: at(0.002).latitude });

    seed("sos_events/w1", { protectedPersonId: "wei", resolvedAt: null, triggeredAt: ts(Date.now()) });
    const inSOS = (await as("kai").get("/v1/crew")).body.crew.members.find((m: { id: string }) => m.id === "wei");
    expect(inSOS).toMatchObject({ approximate: false, latitude: at(0.002).latitude });
    expect((await as("kai").get("/v1/crew")).body.crew.myPrefs).toEqual({ offShiftAlerts: "none", alertRadiusKm: 3, crewPrecision: "exact" });
  });
});

describe("shift options", () => {
  it("late-shift alert after the chosen minutes (default 30)", async () => {
    const end = new Date(Date.now() + 3600_000);
    await as("kai").post("/v1/crew/shift", { onShift: true, plannedEnd: end.toISOString(), graceMinutes: 15 });
    expect(readDoc("rider_shifts/kai")!.checkDueAt.toMillis()).toBe(end.getTime() + 15 * 60_000);
    await as("kai").post("/v1/crew/shift", { onShift: true, plannedEnd: end.toISOString(), graceMinutes: 5 });
    expect(readDoc("rider_shifts/kai")!.checkDueAt.toMillis()).toBe(end.getTime() + 30 * 60_000);
    expect(await checkOverdueShifts(new Date(end.getTime() + 31 * 60_000))).toBe(1);
  });

  it("caution spots last 2, 12 or 24 h", async () => {
    await as("kai").post("/v1/crew/caution", { ...KAI, note: "scooter thief", ttlHours: 2 });
    await as("kai").post("/v1/crew/caution", { ...KAI, note: "dog", ttlHours: 7 });
    const [a, b] = listDocs("crews/c1/cautions").map((d) => d.data).sort((x, y) => x.note.localeCompare(y.note));
    expect(a.expiresAt.toMillis() - a.createdAt.toMillis()).toBe(12 * 3600_000);   // "dog": 7 isn't a choice → 12
    expect(b.expiresAt.toMillis() - b.createdAt.toMillis()).toBe(2 * 3600_000);
  });
});

describe("\"Still OK?\" during a night shift", () => {
  const hourIn = (d: Date) => Number(new Intl.DateTimeFormat("en-US", { timeZone: "Australia/Melbourne", hour: "2-digit", hourCycle: "h23" }).format(d));

  it("asks inside the hours; a check-in answers it; silence tells the watchers", async () => {
    const now = new Date();
    const h = hourIn(now);
    await as("kai").post("/v1/crew/shift", { onShift: true, watcherIds: ["mum"], stillOkEveryMin: 60, stillOkFromHour: h, stillOkToHour: (h + 2) % 24 });
    expect(readDoc("rider_shifts/kai")!.stillOk).toMatchObject({ everyMin: 60, sentAt: null });

    const t1 = new Date(now.getTime() + 61 * 60_000);
    // Make the first check fall inside the window: run it "now"
    seed("rider_shifts/kai", { ...readDoc("rider_shifts/kai"), stillOk: { ...readDoc("rider_shifts/kai")!.stillOk, nextAt: ts(now) } });
    expect(await checkStillOk(now)).toBe(1);
    expect(mockPushes).toContainEqual({ kind: "stillOk", to: "kai" });

    // A check-in answers it
    await as("kai").post("/v1/checkin", { userId: "kai" });
    expect(readDoc("rider_shifts/kai")!.stillOk.sentAt).toBeNull();

    // Next time no answer: after 10 minutes the watchers are told
    seed("rider_shifts/kai", { ...readDoc("rider_shifts/kai"), stillOk: { ...readDoc("rider_shifts/kai")!.stillOk, nextAt: ts(now) } });
    await checkStillOk(now);
    expect(await checkStillOk(new Date(now.getTime() + 5 * 60_000))).toBe(0);
    expect(await checkStillOk(new Date(now.getTime() + 11 * 60_000))).toBe(1);
    expect(mockPushes).toContainEqual({ kind: "stillOkMissed", to: "mum" });
    expect(readDoc("rider_shifts/kai")!.stillOk.missedAt).toBeTruthy();
    void t1;
  });

  it("outside the hours it just waits for the next one", async () => {
    const now = new Date();
    const h = hourIn(now);
    await as("kai").post("/v1/crew/shift", { onShift: true, stillOkEveryMin: 120, stillOkFromHour: (h + 3) % 24, stillOkToHour: (h + 5) % 24 });
    seed("rider_shifts/kai", { ...readDoc("rider_shifts/kai"), stillOk: { ...readDoc("rider_shifts/kai")!.stillOk, nextAt: ts(now) } });
    expect(await checkStillOk(now)).toBe(0);
    expect(mockPushes).toEqual([]);
    expect(readDoc("rider_shifts/kai")!.stillOk.nextAt.toMillis()).toBe(now.getTime() + 120 * 60_000);
  });
});

describe("crash reports", () => {
  it("not hurt: watchers and guardians are told (crew on shift when chosen), kept with the place", async () => {
    seed("users/kai", { ...readDoc("users/kai"), riderWatchers: ["wei"] });
    seed("users/ahmed", { ...readDoc("users/ahmed"), riderOnShift: true });
    const r = await as("kai").post("/v1/safety-events/crash", { clientEventId: "crash-0001", hurt: false, ...KAI, note: "car door", vehicle: "ebike", notifyCrew: true });
    expect(r.status).toBe(201);
    expect(mockPushes.filter((p) => p.kind === "crash").map((p) => p.to).sort()).toEqual(["ahmed", "mum", "wei"]);
    expect(readDoc("safety_events/kai_crash-0001")).toMatchObject({ type: "crash", hurt: false, note: "car door", vehicle: "ebike", outcome: "reported" });
    expect(listDocs("timeline_entries").map((d) => d.data.type)).toEqual(["crashReported"]);
    // A retry doesn't notify twice
    await as("kai").post("/v1/safety-events/crash", { clientEventId: "crash-0001", hurt: false });
    expect(mockPushes.filter((p) => p.kind === "crash")).toHaveLength(3);
  });

  it("hurt: recorded, nobody pinged here (the SOS alerts)", async () => {
    const r = await as("kai").post("/v1/safety-events/crash", { clientEventId: "crash-0002", hurt: true, sosEventId: "s9" });
    expect(r.body.notified).toBe(0);
    expect(readDoc("safety_events/kai_crash-0002")).toMatchObject({ outcome: "sos", sosEventId: "s9" });
    expect(mockPushes).toEqual([]);
    expect((await as("kai").post("/v1/safety-events/crash", { clientEventId: "x" })).status).toBe(400);
  });
});
