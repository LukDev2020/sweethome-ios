/**
 * Safety timer on the server (services/safetyTimer.ts): the phone keeps its
 * deadline here so a killed app or dead battery still raises the SOS.
 */
jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);

import express from "express";
import request from "supertest";
import { resetFakeAdmin, seed, readDoc, listDocs, tokenFor } from "./helpers/fakeAdmin";
import { escalateExpiredSafetyTimers, SAFETY_TIMER_GRACE_MS } from "../services/safetyTimer";

const app = express();
app.use(express.json());
app.use("/v1/safety-timer", require("../routes/safetyTimer").default);
app.use("/v1/sos", require("../routes/sos").default);
const as = (uid: string) => ({
  put: (body: object) => request(app).post("/v1/safety-timer").set("Authorization", `Bearer ${tokenFor(uid)}`).send(body),
  post: (p: string, body: object) => request(app).post(p).set("Authorization", `Bearer ${tokenFor(uid)}`).send(body),
});
const inMin = (m: number) => new Date(Date.now() + m * 60_000).toISOString();
const later = (ms: number) => Date.now() + ms;
const sosEvents = () => listDocs("sos_events");
const timer = () => readDoc("safety_timers/mom")!;

beforeEach(() => {
  resetFakeAdmin();
  seed("users/mom", { displayName: "Mom", role: "protected" });
  seed("users/sarah", { displayName: "Sarah", role: "guardian" });
  seed("guardian_links/sarah_mom", { guardianId: "sarah", protectedPersonId: "mom", status: "active" });
});

const start = (extra: object = {}) => as("mom").put({
  deadline: inMin(30), clientSOSId: "sos-dms-0001", latitude: 43.65, longitude: -79.38, batteryLevel: 0.2, ...extra,
});

it("the phone never checks in: the server raises one SOS after deadline + grace", async () => {
  expect((await start()).body.active).toBe(true);
  expect(timer()).toMatchObject({ status: "active", clientSOSId: "sos-dms-0001", latitude: 43.65 });

  expect(await escalateExpiredSafetyTimers(later(29 * 60_000))).toBe(0);
  expect(await escalateExpiredSafetyTimers(later(30 * 60_000 + SAFETY_TIMER_GRACE_MS - 5_000))).toBe(0);
  expect(sosEvents()).toHaveLength(0);

  expect(await escalateExpiredSafetyTimers(later(30 * 60_000 + SAFETY_TIMER_GRACE_MS + 5_000))).toBe(1);
  const [sos] = sosEvents();
  expect(sos.data).toMatchObject({
    protectedPersonId: "mom", triggerMethod: "deadManSwitch", latitude: 43.65, batteryLevel: 0.2,
    clientSOSIds: ["sos-dms-0001"],
  });
  expect(timer()).toMatchObject({ status: "fired", sosEventId: sos.id });

  // Runs again: nothing more
  expect(await escalateExpiredSafetyTimers(later(60 * 60_000))).toBe(0);
  expect(sosEvents()).toHaveLength(1);
});

it("checking in (deadline null) stops the server from raising anything", async () => {
  await start();
  expect((await as("mom").put({ deadline: null })).body.active).toBe(false);
  expect(timer().status).toBe("cancelled");
  expect(await escalateExpiredSafetyTimers(later(2 * 60 * 60_000))).toBe(0);
  expect(sosEvents()).toHaveLength(0);
});

it("extending moves the server deadline", async () => {
  await start();
  await start({ deadline: inMin(90) });
  expect(await escalateExpiredSafetyTimers(later(31 * 60_000 + SAFETY_TIMER_GRACE_MS))).toBe(0);
  expect(await escalateExpiredSafetyTimers(later(91 * 60_000 + SAFETY_TIMER_GRACE_MS))).toBe(1);
});

it("the phone's own SOS and the server's join into one", async () => {
  await start();
  await as("mom").post("/v1/sos/trigger", { protectedPersonId: "mom", triggerMethod: "deadManSwitch", clientSOSId: "sos-dms-0001" });
  expect(sosEvents()).toHaveLength(1);
  await escalateExpiredSafetyTimers(later(40 * 60_000));
  expect(sosEvents()).toHaveLength(1);
});

it("refuses bad deadlines", async () => {
  expect((await as("mom").put({ deadline: "soon" })).status).toBe(400);
  expect((await as("mom").put({ deadline: inMin(-1) })).status).toBe(400);
  expect((await as("mom").put({ deadline: inMin(25 * 60) })).status).toBe(400);
  expect((await request(app).put("/v1/safety-timer").send({ deadline: inMin(5) })).status).toBe(401);
});

it("a cancel after the server already fired leaves it fired", async () => {
  await start();
  await escalateExpiredSafetyTimers(later(40 * 60_000));
  await as("mom").put({ deadline: null });
  expect(timer().status).toBe("fired");
});
