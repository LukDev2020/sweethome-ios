/**
 * Family watch back (services/watchBack.ts):
 *  - the person cared for asks; the guardian accepts → a reverse link (watchBack)
 *  - or the guardian offers → active at once
 *  - only within the family; the guardian's SOS then reaches the person
 *  - watch-back links take no household seat (the carer's plan covers them)
 *  - either side stops it; removing the guardian ends it
 */
jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);
const mockPushes: { kind: string; to: string }[] = [];
jest.mock("../services/fcm", () => ({
  ...jest.requireActual("../services/fcm"),
  sendFamilyWatchRequest: jest.fn(async (to: string) => { mockPushes.push({ kind: "request", to }); }),
  sendFamilyWatchStarted: jest.fn(async (to: string) => { mockPushes.push({ kind: "started", to }); }),
}));

import express from "express";
import request from "supertest";
import { resetFakeAdmin, seed, readDoc, ts, tokenFor } from "./helpers/fakeAdmin";
import { activeGuardianIds } from "../services/sosTracking";
import { loadGraph, householdIn } from "../services/household";

const app = express();
app.use(express.json());
app.use("/v1/watch-back", require("../routes/watchBack").default);
app.use("/v1/protected", require("../routes/protected").default);
const as = (uid: string) => ({
  get: (p: string) => request(app).get(p).set("Authorization", `Bearer ${tokenFor(uid)}`),
  post: (p: string, body: object = {}) => request(app).post(p).set("Authorization", `Bearer ${tokenFor(uid)}`).send(body),
  del: (p: string) => request(app).delete(p).set("Authorization", `Bearer ${tokenFor(uid)}`),
});

beforeEach(() => {
  resetFakeAdmin();
  mockPushes.length = 0;
  seed("users/mom", { displayName: "Mom", role: "protected" });
  seed("users/sarah", { displayName: "Sarah", role: "guardian" });
  seed("users/kevin", { displayName: "Kevin", role: "guardian" });
  seed("users/stranger", { displayName: "X", role: "guardian" });
  seed("guardian_links/sarah_mom", { guardianId: "sarah", protectedPersonId: "mom", status: "active" });
  seed("guardian_links/kevin_mom", { guardianId: "kevin", protectedPersonId: "mom", status: "active" });
  seed("subscriptions/sarah", { planId: "family", status: "active", expiresAt: ts(Date.now() + 86400_000 * 30) });
});

it("Mom asks, Sarah accepts: Sarah's SOS now reaches Mom", async () => {
  const asked = await as("mom").post("/v1/watch-back/request", { guardianId: "sarah" });
  expect(asked.body.state).toBe("pending");
  expect(mockPushes).toEqual([{ kind: "request", to: "sarah" }]);
  expect(await activeGuardianIds("sarah")).toEqual([]);

  const sarahView = (await as("sarah").get("/v1/watch-back")).body;
  expect(sarahView.people).toEqual([{ id: "mom", name: "Mom", state: "pending" }]);

  const ok = await as("sarah").post("/v1/watch-back/respond", { personId: "mom", accept: true });
  expect(ok.body.state).toBe("active");
  expect(readDoc("guardian_links/mom_sarah")).toMatchObject({ guardianId: "mom", protectedPersonId: "sarah", watchBack: true, billedTo: "sarah" });
  expect(await activeGuardianIds("sarah")).toEqual(["mom"]);
  expect(mockPushes.at(-1)).toEqual({ kind: "started", to: "mom" });

  const momView = (await as("mom").get("/v1/watch-back")).body;
  expect(momView.guardians.find((g: { id: string }) => g.id === "sarah").state).toBe("active");
  expect(momView.guardians.find((g: { id: string }) => g.id === "kevin").state).toBe("none");
});

it("Sarah can offer it herself; declining a request removes it", async () => {
  expect((await as("sarah").post("/v1/watch-back/offer", { personId: "mom" })).body.state).toBe("active");
  await as("mom").post("/v1/watch-back/request", { guardianId: "kevin" });
  expect((await as("kevin").post("/v1/watch-back/respond", { personId: "mom", accept: false })).body.state).toBe("none");
  expect(readDoc("guardian_links/mom_kevin")).toBeUndefined();
});

it("only within the family", async () => {
  expect((await as("mom").post("/v1/watch-back/request", { guardianId: "stranger" })).status).toBe(403);
  expect((await as("stranger").post("/v1/watch-back/offer", { personId: "mom" })).status).toBe(403);
  expect((await as("sarah").post("/v1/watch-back/respond", { personId: "mom", accept: true })).status).toBe(404);
});

it("takes no household seat: the carer's plan covers it", async () => {
  const before = householdIn(await loadGraph(["sarah"]), "sarah")!;
  await as("sarah").post("/v1/watch-back/offer", { personId: "mom" });
  const after = householdIn(await loadGraph(["sarah", "mom"]), "sarah")!;
  expect([...after.protectedIds]).toEqual([...before.protectedIds]);
  expect([...after.guardianIds].sort()).toEqual([...before.guardianIds].sort());
  expect(after.protectedIds.has("sarah")).toBe(false);
});

it("either side stops it, and removing the guardian ends it", async () => {
  await as("sarah").post("/v1/watch-back/offer", { personId: "mom" });
  await as("mom").post("/v1/watch-back/stop", { otherId: "sarah" });
  expect(readDoc("guardian_links/mom_sarah")).toBeUndefined();

  await as("sarah").post("/v1/watch-back/offer", { personId: "mom" });
  expect((await as("mom").del("/v1/protected/guardians/sarah")).status).toBe(200);
  expect(readDoc("guardian_links/mom_sarah")).toBeUndefined();
});
