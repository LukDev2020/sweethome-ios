/**
 * Rider crews (services/crew.ts, routes/crew.ts):
 *  - create / join by invite code / leave; one crew per rider, 12 members max
 *  - locations only while on shift
 *  - an SOS alerts every other crew member, nearest first, and records it
 *  - "I'm going" is stored on the SOS, shown in its status and pushed to the rider
 *  - a shift past its planned end + 30 min alerts crew and guardians once
 */
jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);
const mockPushes: { kind: string; to: string; args: unknown[] }[] = [];
jest.mock("../services/fcm", () => ({
  ...jest.requireActual("../services/fcm"),
  sendCrewSOSAlert: jest.fn(async (to: string, ...args: unknown[]) => { mockPushes.push({ kind: "sos", to, args }); return { successCount: 1, failureCount: 0, allFailed: false }; }),
  sendCrewResponseNotification: jest.fn(async (to: string, ...args: unknown[]) => { mockPushes.push({ kind: "response", to, args }); }),
  sendShiftOverdueNotification: jest.fn(async (to: string, ...args: unknown[]) => { mockPushes.push({ kind: "overdue", to, args }); }),
}));

import express from "express";
import request from "supertest";
import { resetFakeAdmin, seed, readDoc, ts, tokenFor } from "./helpers/fakeAdmin";
import { alertCrewOfSOS, checkOverdueShifts, newInviteCode, CREW_MAX_MEMBERS } from "../services/crew";
import { sosStatus } from "../services/escalation";
import * as admin from "firebase-admin";

const app = express();
app.use(express.json());
app.use("/v1/crew", require("../routes/crew").default);
const as = (uid: string) => ({
  get: (p: string) => request(app).get(p).set("Authorization", `Bearer ${tokenFor(uid)}`),
  post: (p: string, body: object = {}) => request(app).post(p).set("Authorization", `Bearer ${tokenFor(uid)}`).send(body),
});

// Melbourne CBD: Kai at Little Bourke St, Wei 220 m, Ahmed ~1 km
const at = (uid: string, lat: number, lng: number) =>
  seed(`user_telemetry/${uid}`, { latitude: lat, longitude: lng, locationTimestamp: ts(Date.now()) });

beforeEach(() => {
  resetFakeAdmin();
  mockPushes.length = 0;
  for (const [id, name] of [["kai", "Kai"], ["wei", "Wei"], ["ahmed", "Ahmed"], ["mei", "Mei"]]) {
    seed(`users/${id}`, { displayName: name, avatarInitial: name[0], role: "protected" });
  }
  at("kai", -37.8125, 144.9685);
  at("wei", -37.8135, 144.9705);
  at("ahmed", -37.8040, 144.9620);
  seed("guardian_links/mei_kai", { guardianId: "mei", protectedPersonId: "kai", status: "active" });
});

async function crewOfThree() {
  const created = await as("kai").post("/v1/crew", { name: "CBD night crew" });
  const code = created.body.crew.inviteCode as string;
  await as("wei").post("/v1/crew/join", { code: code.toLowerCase() });
  await as("ahmed").post("/v1/crew/join", { code });
  return { crewId: created.body.crew.id as string, code };
}

describe("crew membership", () => {
  it("creates with an invite code others join", async () => {
    const { code } = await crewOfThree();
    expect(code).toMatch(/^[A-HJ-NP-Z2-9]{6}$/);
    const view = await as("wei").get("/v1/crew");
    expect(view.body.crew.members.map((m: { name: string }) => m.name)).toEqual(["Kai", "Wei", "Ahmed"]);
    expect(view.body.crew.isOwner).toBe(false);
  });

  it("refuses a second crew, a bad code and a full crew", async () => {
    const { code } = await crewOfThree();
    expect((await as("wei").post("/v1/crew", { name: "Other" })).status).toBe(409);
    expect((await as("mei").post("/v1/crew/join", { code: "ZZZZZZ" })).status).toBe(404);
    expect((await as("mei").post("/v1/crew/join", { code: "bad" })).status).toBe(400);
    const crewId = readDoc("users/kai")!.crewId as string;
    seed(`crews/${crewId}`, { ...readDoc(`crews/${crewId}`)!, memberIds: Array.from({ length: CREW_MAX_MEMBERS }, (_, i) => `m${i}`) });
    expect((await as("mei").post("/v1/crew/join", { code })).status).toBe(409);
  });

  it("leaving hands the crew on, and the last one out removes it", async () => {
    const { crewId } = await crewOfThree();
    await as("kai").post("/v1/crew/leave");
    expect(readDoc(`crews/${crewId}`)!.ownerId).toBe("wei");
    await as("wei").post("/v1/crew/leave");
    await as("ahmed").post("/v1/crew/leave");
    expect(readDoc(`crews/${crewId}`)).toBeUndefined();
  });

  it("invite codes avoid look-alike characters", () => {
    expect(newInviteCode(() => 0)).toBe("AAAAAA");
    expect(newInviteCode(() => 0.999)).toBe("999999");
  });
});

describe("shift and map", () => {
  it("shows a crew mate's location only while on shift", async () => {
    await crewOfThree();
    let wei = (await as("kai").get("/v1/crew")).body.crew.members.find((m: { id: string }) => m.id === "wei");
    expect(wei.latitude).toBeNull();
    await as("wei").post("/v1/crew/shift", { onShift: true, plannedEnd: new Date(Date.now() + 3600_000).toISOString() });
    wei = (await as("kai").get("/v1/crew")).body.crew.members.find((m: { id: string }) => m.id === "wei");
    expect(wei.onShift).toBe(true);
    expect(wei.latitude).toBeCloseTo(-37.8135);
    expect(wei.distanceM).toBeGreaterThan(150);
    expect(wei.distanceM).toBeLessThan(300);
    await as("wei").post("/v1/crew/shift", { onShift: false });
    expect(readDoc("rider_shifts/wei")).toBeUndefined();
  });

  it("caution spots are shared with the crew", async () => {
    await crewOfThree();
    expect((await as("kai").post("/v1/crew/caution", { latitude: -37.81, longitude: 144.96, note: "bike tampered" })).status).toBe(201);
    const cautions = (await as("wei").get("/v1/crew")).body.crew.cautions;
    expect(cautions).toHaveLength(1);
    expect(cautions[0].note).toBe("bike tampered");
  });
});

describe("SOS → crew", () => {
  it("alerts the other members nearest first and records who answered", async () => {
    await crewOfThree();
    seed("sos_events/s1", { protectedPersonId: "kai", triggeredAt: ts(Date.now()), resolvedAt: null,
      latitude: -37.8125, longitude: 144.9685, escalationState: "initiated", escalationLog: [] });
    const count = await alertCrewOfSOS("s1", readDoc("sos_events/s1")!);
    expect(count).toBe(2);
    expect(mockPushes.filter((p) => p.kind === "sos").map((p) => p.to)).toEqual(["wei", "ahmed"]);
    expect(readDoc("sos_events/s1")!.crewNotified).toEqual(["wei", "ahmed"]);

    const alerts = (await as("wei").get("/v1/crew/alerts")).body.alerts;
    expect(alerts).toHaveLength(1);
    expect(alerts[0]).toMatchObject({ sosEventId: "s1", riderName: "Kai", myResponse: null });

    expect((await as("wei").post("/v1/crew/respond", { sosEventId: "s1", response: "going" })).status).toBe(200);
    expect(mockPushes.find((p) => p.kind === "response")!.to).toBe("kai");
    const status = await sosStatus(await admin.firestore().collection("sos_events").doc("s1").get());
    expect(status.crewNotified).toBe(2);
    expect(status.crewResponses).toEqual([expect.objectContaining({ memberId: "wei", name: "Wei", response: "going" })]);
  });

  it("only crew mates may answer, and only an open SOS", async () => {
    await crewOfThree();
    seed("sos_events/s1", { protectedPersonId: "kai", triggeredAt: ts(Date.now()), resolvedAt: null, latitude: -37.81, longitude: 144.96 });
    expect((await as("mei").post("/v1/crew/respond", { sosEventId: "s1", response: "going" })).status).toBe(403);
    expect((await as("wei").post("/v1/crew/respond", { sosEventId: "s1", response: "maybe" })).status).toBe(400);
    seed("sos_events/s2", { protectedPersonId: "kai", triggeredAt: ts(Date.now()), resolvedAt: ts(Date.now()) });
    expect((await as("wei").post("/v1/crew/respond", { sosEventId: "s2", response: "going" })).status).toBe(404);
  });

  it("a rider without a crew alerts nobody extra", async () => {
    seed("sos_events/s1", { protectedPersonId: "kai", triggeredAt: ts(Date.now()), resolvedAt: null });
    expect(await alertCrewOfSOS("s1", readDoc("sos_events/s1")!)).toBe(0);
  });
});

describe("shift not ended", () => {
  it("alerts crew and guardians once, 30 min after the planned end", async () => {
    await crewOfThree();
    const plannedEnd = new Date(Date.now() - 31 * 60_000);
    await as("kai").post("/v1/crew/shift", { onShift: true, plannedEnd: plannedEnd.toISOString() });
    expect(await checkOverdueShifts()).toBe(1);
    expect(mockPushes.filter((p) => p.kind === "overdue").map((p) => p.to).sort()).toEqual(["ahmed", "mei", "wei"]);
    expect(await checkOverdueShifts()).toBe(0);
  });

  it("ending the shift in time means no alert", async () => {
    await crewOfThree();
    await as("kai").post("/v1/crew/shift", { onShift: true, plannedEnd: new Date(Date.now() - 31 * 60_000).toISOString() });
    await as("kai").post("/v1/crew/shift", { onShift: false });
    expect(await checkOverdueShifts()).toBe(0);
  });
});
