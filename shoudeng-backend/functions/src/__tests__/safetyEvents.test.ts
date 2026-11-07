/**
 * Detected falls (services/safetyEvents.ts):
 *  - the phone reports "pending" at once; the server's clock sets when it steps in
 *  - "I'm OK" → dismissed (timeline + a quiet push to guardians), never an SOS
 *  - the phone's own SOS → escalated, the server leaves it alone
 *  - the phone never answers → the every-minute job sends exactly one SOS
 *  - phone and server firing for the same fall join one SOS
 */
jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);
const mockPushes: { kind: string; to: string }[] = [];
jest.mock("../services/fcm", () => ({
  ...jest.requireActual("../services/fcm"),
  sendFallDismissed: jest.fn(async (to: string) => { mockPushes.push({ kind: "fallDismissed", to }); }),
}));

import express from "express";
import request from "supertest";
import { resetFakeAdmin, seed, readDoc, listDocs, tokenFor } from "./helpers/fakeAdmin";
import { escalateUnansweredFalls, SERVER_GRACE_MS } from "../services/safetyEvents";

const app = express();
app.use(express.json());
app.use("/v1/safety-events", require("../routes/safetyEvents").default);
app.use("/v1/sos", require("../routes/sos").default);
const as = (uid: string) => ({
  post: (p: string, body: object = {}) => request(app).post(p).set("Authorization", `Bearer ${tokenFor(uid)}`).send(body),
});

const fall = (extra: object = {}) => ({
  clientEventId: "fall-0001-abcd",
  clientSOSId: "sos-0001-abcd",
  outcome: "pending",
  detectedAt: new Date().toISOString(),
  countdownSec: 60,
  latitude: 43.65, longitude: -79.38, accuracy: 12, batteryLevel: 0.41,
  metrics: { peakImpactG: 3.6, freeFallMs: 440, orientationChangeDeg: 88, stillnessVariance: 0.001, detector: "threshold-v2" },
  ...extra,
});
const sosEvents = () => listDocs("sos_events");
const later = (ms: number) => Date.now() + ms;

beforeEach(() => {
  resetFakeAdmin();
  mockPushes.length = 0;
  seed("users/mom", { displayName: "Mom", role: "protected" });
  seed("users/sarah", { displayName: "Sarah", role: "guardian" });
  seed("guardian_links/sarah_mom", { guardianId: "sarah", protectedPersonId: "mom", status: "active" });
});

it("records a pending fall with the server's deadline and the sensor numbers", async () => {
  const r = await as("mom").post("/v1/safety-events/fall", fall());
  expect(r.status).toBe(200);
  expect(r.body).toEqual({ outcome: "pending", sosEventId: null });
  const doc = readDoc("safety_events/mom_fall-0001-abcd")!;
  expect(doc).toMatchObject({ userId: "mom", type: "fall", outcome: "pending", clientSOSId: "sos-0001-abcd", latitude: 43.65 });
  expect(doc.metrics).toEqual({ peakImpactG: 3.6, freeFallMs: 440, orientationChangeDeg: 88, stillnessVariance: 0.001, detector: "threshold-v2" });
  expect(doc.escalateAt.toMillis() - doc.receivedAt.toMillis()).toBe(60_000);
});

it("I'm OK: dismissed, a timeline note and a quiet push to guardians — never an SOS", async () => {
  await as("mom").post("/v1/safety-events/fall", fall());
  const r = await as("mom").post("/v1/safety-events/fall", fall({ outcome: "dismissed", respondedAfterSec: 12 }));
  expect(r.body.outcome).toBe("dismissed");
  expect(readDoc("safety_events/mom_fall-0001-abcd")).toMatchObject({ outcome: "dismissed", respondedAfterSec: 12 });
  expect(mockPushes).toEqual([{ kind: "fallDismissed", to: "sarah" }]);
  expect(listDocs("timeline_entries").map((d) => d.data.type)).toEqual(["fallDetected"]);

  expect(await escalateUnansweredFalls(later(10 * 60_000))).toBe(0);
  expect(sosEvents()).toHaveLength(0);
});

it("the phone never answers: the server sends one SOS after the countdown + grace", async () => {
  await as("mom").post("/v1/safety-events/fall", fall());
  // Not yet: inside the countdown, and inside the grace after it
  expect(await escalateUnansweredFalls(later(30_000))).toBe(0);
  expect(await escalateUnansweredFalls(later(60_000 + SERVER_GRACE_MS - 2_000))).toBe(0);
  expect(sosEvents()).toHaveLength(0);

  expect(await escalateUnansweredFalls(later(60_000 + SERVER_GRACE_MS + 1_000))).toBe(1);
  const [sos] = sosEvents();
  expect(sos.data).toMatchObject({ protectedPersonId: "mom", triggerMethod: "fallDetection", latitude: 43.65, clientSOSIds: ["sos-0001-abcd"] });
  expect(readDoc("safety_events/mom_fall-0001-abcd")).toMatchObject({ outcome: "escalated_by_server", sosEventId: sos.id });

  // Runs again: nothing more
  expect(await escalateUnansweredFalls(later(5 * 60_000))).toBe(0);
  expect(sosEvents()).toHaveLength(1);
});

it("the phone's late SOS joins the server's (one SOS), and a late I'm OK is told it's already out", async () => {
  await as("mom").post("/v1/safety-events/fall", fall());
  await escalateUnansweredFalls(later(2 * 60_000));
  const trig = await as("mom").post("/v1/sos/trigger", { protectedPersonId: "mom", triggerMethod: "fallDetection", clientSOSId: "sos-0001-abcd" });
  expect(trig.body.message).toBe("SOS already active");
  expect(sosEvents()).toHaveLength(1);

  const late = await as("mom").post("/v1/safety-events/fall", fall({ outcome: "dismissed", respondedAfterSec: 140 }));
  expect(late.body.outcome).toBe("escalated_by_server");
  expect(late.body.sosEventId).toBe(sosEvents()[0].id);
  expect(readDoc("safety_events/mom_fall-0001-abcd")).toMatchObject({ outcome: "escalated_by_server", dismissedAfterServerSOS: true });
  expect(mockPushes).toEqual([]);
});

it("the phone sent the SOS itself: the server leaves it alone", async () => {
  await as("mom").post("/v1/safety-events/fall", fall());
  await as("mom").post("/v1/safety-events/fall", fall({ outcome: "escalated", sosEventId: "srv-sos-1", respondedAfterSec: 60 }));
  expect(await escalateUnansweredFalls(later(10 * 60_000))).toBe(0);
  expect(readDoc("safety_events/mom_fall-0001-abcd")).toMatchObject({ outcome: "escalated", sosEventId: "srv-sos-1" });
});

it("\"I need help\" is recorded as such, not as no answer", async () => {
  await as("mom").post("/v1/safety-events/fall", fall());
  const r = await as("mom").post("/v1/safety-events/fall", fall({ outcome: "help_requested", respondedAfterSec: 9 }));
  expect(r.body.outcome).toBe("help_requested");
  expect(await escalateUnansweredFalls(later(10 * 60_000))).toBe(0);
  expect(readDoc("safety_events/mom_fall-0001-abcd")).toMatchObject({ outcome: "help_requested", respondedAfterSec: 9 });
});

it("a phone clock far off doesn't move the deadline; bad input is refused", async () => {
  await as("mom").post("/v1/safety-events/fall", fall({ detectedAt: "2001-01-01T00:00:00Z", countdownSec: 99999 }));
  const doc = readDoc("safety_events/mom_fall-0001-abcd")!;
  expect(Math.abs(doc.detectedAt.toMillis() - Date.now())).toBeLessThan(5_000);
  expect(doc.escalateAt.toMillis() - doc.receivedAt.toMillis()).toBe(60_000);

  expect((await as("mom").post("/v1/safety-events/fall", fall({ clientEventId: "x" }))).status).toBe(400);
  expect((await as("mom").post("/v1/safety-events/fall", fall({ outcome: "escalated_by_server" }))).status).toBe(400);
  expect((await request(app).post("/v1/safety-events/fall").send(fall())).status).toBe(401);
});

it("each person's falls are their own", async () => {
  await as("mom").post("/v1/safety-events/fall", fall());
  await as("sarah").post("/v1/safety-events/fall", fall({ outcome: "dismissed" }));
  expect(readDoc("safety_events/mom_fall-0001-abcd")!.outcome).toBe("pending");
  expect(readDoc("safety_events/sarah_fall-0001-abcd")!.outcome).toBe("dismissed");
});
