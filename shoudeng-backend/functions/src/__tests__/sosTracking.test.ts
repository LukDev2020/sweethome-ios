/**
 * Live SOS location (services/sosTracking.ts):
 *  - location reports move an open SOS and build a thinned trail
 *  - the guardian's SOS status carries trail and shared route
 *  - POST /v1/sos/route stores the route and tells the guardians
 *  - the person ending their own SOS tells the guardians they are safe
 */
jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);

const mockPushes: { kind: string; to: string; args: unknown[] }[] = [];
jest.mock("../services/fcm", () => ({
  sendSOSResolvedNotification: jest.fn(async () => undefined),
  sendSOSEndedByPersonNotification: jest.fn(async (to: string, ...args: unknown[]) => { mockPushes.push({ kind: "safe", to, args }); }),
  sendSOSRouteNotification: jest.fn(async (to: string, ...args: unknown[]) => { mockPushes.push({ kind: "route", to, args }); }),
}));
jest.mock("../services/bigquery", () => ({
  ...jest.requireActual("../services/bigquery"),
  insertLocationReport: jest.fn(async () => undefined),
  insertCheckin: jest.fn(async () => undefined),
  insertHeartbeat: jest.fn(async () => undefined),
  insertConsentAudit: jest.fn(async () => undefined),
}));

import express from "express";
import request from "supertest";
import { resetFakeAdmin, seed, readDoc, ts, tokenFor } from "./helpers/fakeAdmin";
import { recordSOSLocation, shouldAppend, parseRoute, TRAIL_MAX_POINTS } from "../services/sosTracking";
import { sosStatus, activeSOSDoc } from "../services/escalation";

const app = express();
app.use(express.json());
app.use("/v1/sos", require("../routes/sos").default);
app.use("/v1", require("../routes/telemetry").default);
const as = (uid: string) => ({
  post: (path: string, body: object) => request(app).post(path).set("Authorization", `Bearer ${tokenFor(uid)}`).send(body),
});

beforeEach(() => {
  resetFakeAdmin();
  mockPushes.length = 0;
  seed("users/mom", { displayName: "秀兰", avatarInitial: "秀", role: "protected" });
  seed("guardian_links/sarah_mom", { guardianId: "sarah", protectedPersonId: "mom", status: "active" });
  seed("guardian_links/kevin_mom", { guardianId: "kevin", protectedPersonId: "mom", status: "active" });
});

const openSOS = () => seed("sos_events/s1", {
  protectedPersonId: "mom", triggeredAt: ts(Date.now() - 60_000), resolvedAt: null,
  latitude: 30.6586, longitude: 104.0647, escalationState: "initiated", escalationLog: [], clientSOSIds: [],
});

describe("trail thinning", () => {
  const p = (lat: number, at: number) => ({ latitude: lat, longitude: 104, at: new Date(at).toISOString() });
  it("keeps the first point, then one every 15 s or 15 m", () => {
    expect(shouldAppend(undefined, p(30, 0))).toBe(true);
    expect(shouldAppend(p(30, 0), p(30.00001, 5_000))).toBe(false);   // ~1 m, 5 s
    expect(shouldAppend(p(30, 0), p(30.0002, 5_000))).toBe(true);     // ~22 m
    expect(shouldAppend(p(30, 0), p(30, 16_000))).toBe(true);         // 16 s
  });
});

describe("recordSOSLocation", () => {
  it("does nothing without an open SOS", async () => {
    expect(await recordSOSLocation("mom", 30.66, 104.07)).toBe(false);
  });

  it("moves the SOS and appends to its trail", async () => {
    openSOS();
    await recordSOSLocation("mom", 30.6600, 104.0700, new Date(1_000_000));
    await recordSOSLocation("mom", 30.6601, 104.0700, new Date(1_005_000)); // too close, too soon
    await recordSOSLocation("mom", 30.6620, 104.0700, new Date(1_010_000));
    const d = readDoc("sos_events/s1")!;
    expect(d.latitude).toBe(30.662);
    expect(d.trail).toHaveLength(2);
  });

  it("caps the trail", async () => {
    openSOS();
    for (let i = 0; i < TRAIL_MAX_POINTS + 5; i++) {
      await recordSOSLocation("mom", 30 + i * 0.001, 104, new Date(1_000_000 + i * 20_000));
    }
    expect(readDoc("sos_events/s1")!.trail).toHaveLength(TRAIL_MAX_POINTS);
  });

  it("ignores bad coordinates", async () => {
    openSOS();
    expect(await recordSOSLocation("mom", "x", 104)).toBe(false);
    expect(await recordSOSLocation("mom", 120, 104)).toBe(false);
  });
});

describe("location report → SOS", () => {
  it("a report during an SOS moves the guardians' map", async () => {
    openSOS();
    const res = await as("mom").post("/v1/location/report", { userId: "mom", latitude: 30.67, longitude: 104.08 });
    expect(res.status).toBe(200);
    const status = await sosStatus((await activeSOSDoc("mom"))!);
    expect(status.latitude).toBe(30.67);
    expect(status.trail.length).toBe(1);
    expect(status.locationUpdatedAt).not.toBeNull();
  });
});

describe("POST /v1/sos/route", () => {
  it("rejects a route without a place", async () => {
    openSOS();
    expect((await as("mom").post("/v1/sos/route", { latitude: 30.6 })).status).toBe(400);
  });

  it("needs an open SOS", async () => {
    expect((await as("mom").post("/v1/sos/route", { name: "医院", latitude: 30.6, longitude: 104 })).status).toBe(404);
  });

  it("stores the route and tells every guardian", async () => {
    openSOS();
    const res = await as("mom").post("/v1/sos/route", { name: "第二人民医院", latitude: 30.66, longitude: 104.06, mode: "walking" });
    expect(res.status).toBe(200);
    expect(readDoc("sos_events/s1")!.route).toMatchObject({ name: "第二人民医院", mode: "walking" });
    expect(mockPushes.filter((p) => p.kind === "route").map((p) => p.to).sort()).toEqual(["kevin", "sarah"]);
    expect(parseRoute({ name: "x", latitude: 1, longitude: 2, mode: "boat" })!.mode).toBe("walking");
  });
});

describe("person ends their own SOS", () => {
  it("guardians are told she is safe", async () => {
    openSOS();
    const res = await as("mom").post("/v1/sos/resolve", { sosEventId: "s1", resolution: "protectedCancelled" });
    expect(res.status).toBe(200);
    expect(mockPushes.filter((p) => p.kind === "safe").map((p) => p.to).sort()).toEqual(["kevin", "sarah"]);
  });
});
