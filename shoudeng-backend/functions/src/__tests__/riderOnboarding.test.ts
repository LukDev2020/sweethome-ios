/**
 * Rider onboarding (docs/rider-onboarding-plan.md):
 *  - PUT /v1/user/me takes useCase, homeStyle and riderProfile (validated, partial)
 *  - GET /v1/user/me gives them back (Rider mode survives a new phone)
 *  - milestones: crew (create / join), first and last shift, lock card / setup (phone)
 *  - partner organisations: code, preview, join (with or without being counted),
 *    totals only for the admin
 *  - the funnel counts
 */
jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);
jest.mock("../services/fcm", () => ({
  ...jest.requireActual("../services/fcm"),
  sendShiftWatchRequest: jest.fn(async () => undefined),
}));

import express from "express";
import request from "supertest";
import { resetFakeAdmin, seed, readDoc, ts, tokenFor } from "./helpers/fakeAdmin";
import { riderFunnel, riderProfileView } from "../services/riderProfile";

const app = express();
app.use(express.json());
app.use("/v1/user", require("../routes/user").default);
app.use("/v1/crew", require("../routes/crew").default);
app.use("/v1/org", require("../routes/organization").default);
const as = (uid: string) => ({
  get: (p: string) => request(app).get(p).set("Authorization", `Bearer ${tokenFor(uid)}`),
  post: (p: string, body: object = {}) => request(app).post(p).set("Authorization", `Bearer ${tokenFor(uid)}`).send(body),
  put: (p: string, body: object = {}) => request(app).put(p).set("Authorization", `Bearer ${tokenFor(uid)}`).send(body),
});

beforeEach(() => {
  resetFakeAdmin();
  for (const [id, name] of [["kai", "Kai"], ["wei", "Wei"], ["mum", "Mum"], ["boss", "Boss"]]) {
    seed(`users/${id}`, { displayName: name, role: id === "mum" ? "guardian" : "protected", timeZone: "Australia/Melbourne",
      countryCode: "AU", cityName: "Melbourne", avatarInitial: name[0], createdAt: ts(Date.now() - 86400_000) });
  }
});

describe("profile fields", () => {
  it("a rider's choice is saved and comes back on a new phone", async () => {
    const r = await as("kai").put("/v1/user/me", {
      useCase: "rider", homeStyle: "rider",
      riderProfile: { city: "Melbourne", platforms: ["ubereats", "doordash", "ubereats"] },
    });
    expect(r.status).toBe(200);
    const me = (await as("kai").get("/v1/user/me")).body;
    expect(me).toMatchObject({ useCase: "rider", homeStyle: "rider" });
    expect(me.riderProfile).toMatchObject({ city: "Melbourne", platforms: ["ubereats", "doordash"], partnerOrg: null });
    expect(me.riderProfile.onboardedAt).toBeTruthy();
    expect(me.riderProfile.riderFree).toMatchObject({ active: true });
    expect(me.riderProfile.riderFree.included).toContain("crew_sos");
  });

  it("partial updates keep the rest; the first setup date stays", async () => {
    await as("kai").put("/v1/user/me", { useCase: "rider", riderProfile: { city: "Melbourne", platforms: ["uber"] } });
    const first = readDoc("users/kai")!.riderProfile.onboardedAt.toMillis();
    await new Promise((r) => setTimeout(r, 5));
    await as("kai").put("/v1/user/me", { homeStyle: "rider", riderProfile: { platforms: ["didi"] } });
    const doc = readDoc("users/kai")!;
    expect(doc.riderProfile).toMatchObject({ city: "Melbourne", platforms: ["didi"] });
    expect(doc.riderProfile.onboardedAt.toMillis()).toBe(first);
  });

  it("refuses bad values", async () => {
    for (const body of [
      { useCase: "courier" }, { homeStyle: "fancy" }, { riderProfile: "x" },
      { riderProfile: { platforms: ["myspace"] } }, { riderProfile: { city: "x".repeat(101) } },
      { riderProfile: { milestones: { crew: true } } },        // only the server sets this one
      { riderProfile: { milestones: { lockCard: "yes" } } },
    ]) {
      expect((await as("kai").put("/v1/user/me", body)).status).toBe(400);
    }
  });

  it("a non-rider has no rider profile", async () => {
    const me = (await as("wei").get("/v1/user/me")).body;
    expect(me.riderProfile).toBeNull();
    expect(me.useCase).toBeNull();
  });
});

describe("milestones", () => {
  it("crew, first shift (once), last shift, lock card and setup", async () => {
    await as("kai").put("/v1/user/me", { useCase: "rider" });
    const crew = await as("kai").post("/v1/crew", { name: "Little Bourke riders" });
    expect(crew.status).toBeLessThan(300);
    const code = crew.body.crew.inviteCode;
    expect((await as("wei").post("/v1/crew/join", { code })).status).toBeLessThan(300);
    expect(readDoc("users/wei")!.riderProfile.milestones.crewAt).toBeTruthy();

    await as("kai").post("/v1/crew/shift", { onShift: true });
    const firstShift = readDoc("users/kai")!.riderProfile.milestones.firstShiftAt.toMillis();
    await as("kai").post("/v1/crew/shift", { onShift: false });
    await new Promise((r) => setTimeout(r, 5));
    await as("kai").post("/v1/crew/shift", { onShift: true });
    const doc = readDoc("users/kai")!;
    expect(doc.riderProfile.milestones.firstShiftAt.toMillis()).toBe(firstShift);
    expect(doc.riderProfile.lastShiftAt.toMillis()).toBeGreaterThan(firstShift);

    await as("kai").put("/v1/user/me", { riderProfile: { milestones: { lockCard: true, setupDone: true } } });
    const m = (await as("kai").get("/v1/user/me")).body.riderProfile.milestones;
    expect(m.crewAt && m.firstShiftAt && m.lockCardAt && m.setupDoneAt).toBeTruthy();
  });

  it("a rider with no shift for 30 days is no longer active", () => {
    const view = riderProfileView({
      useCase: "rider",
      riderProfile: { onboardedAt: ts(Date.now() - 90 * 86400_000), lastShiftAt: ts(Date.now() - 31 * 86400_000) },
    });
    expect(view.riderProfile!.riderFree.active).toBe(false);
  });
});

describe("partner organisations", () => {
  beforeEach(() => {
    seed("organizations/union", { name: "Riders Union", type: "union", adminIds: ["boss"], memberCount: 0 });
  });

  it("code → preview → join; the admin sees totals of riders who agreed only", async () => {
    const pc = await as("boss").post("/v1/org/partner-code");
    expect(pc.body.code).toMatch(/^[A-HJ-NP-Z2-9]{6}$/);
    expect(pc.body.link).toBe(`https://shoudeng.app/start?for=rider&org=${pc.body.code}`);
    // Asking again gives the same code
    expect((await as("boss").post("/v1/org/partner-code")).body.code).toBe(pc.body.code);

    expect((await as("kai").get(`/v1/org/partner/${pc.body.code.toLowerCase()}`)).body).toEqual({ name: "Riders Union" });
    expect((await as("kai").post(`/v1/org/partner/${pc.body.code}/join`, { shareStats: true })).body)
      .toEqual({ name: "Riders Union", shareStats: true });
    await as("wei").post(`/v1/org/partner/${pc.body.code}/join`, { shareStats: false });
    // Joining again only changes the choice (not counted twice)
    await as("kai").post(`/v1/org/partner/${pc.body.code}/join`, { shareStats: true });
    expect(readDoc("organizations/union")!.memberCount).toBe(2);
    expect((await as("kai").get("/v1/user/me")).body.riderProfile).toMatchObject({ partnerOrg: "Riders Union" });

    await as("kai").post("/v1/crew/shift", { onShift: true });
    seed("sos_events/s1", { protectedPersonId: "kai", triggeredAt: ts(Date.now() - 86400_000), resolvedAt: ts(Date.now()) });
    seed("sos_events/s2", { protectedPersonId: "wei", triggeredAt: ts(Date.now() - 86400_000), resolvedAt: ts(Date.now()) });
    const stats = (await as("boss").get("/v1/org/riders")).body;
    expect(stats).toEqual({
      orgName: "Riders Union", partnerCode: pc.body.code,
      riders: 1, notCounted: 1, activeLast7d: 1, onShiftNow: 1, sosLast30d: 1,
    });
    expect(JSON.stringify(stats)).not.toMatch(/Kai|latitude/);
  });

  it("only an admin gets a code or totals; bad codes are refused", async () => {
    expect((await as("kai").post("/v1/org/partner-code")).status).toBe(404);
    expect((await as("kai").get("/v1/org/riders")).status).toBe(404);
    expect((await as("kai").get("/v1/org/partner/abc")).status).toBe(400);
    expect((await as("kai").get("/v1/org/partner/ZZZZZZ")).status).toBe(404);
    expect((await as("kai").post("/v1/org/partner/ZZZZZZ/join", { shareStats: true })).status).toBe(404);
  });
});

it("the funnel counts each step", async () => {
  await as("kai").put("/v1/user/me", { useCase: "rider" });
  await as("wei").put("/v1/user/me", { useCase: "rider" });
  await as("kai").post("/v1/crew", { name: "Crew" });
  seed("guardian_links/mum_kai", { guardianId: "mum", protectedPersonId: "kai", status: "active" });
  await as("kai").post("/v1/crew/shift", { onShift: true });
  await as("kai").put("/v1/user/me", { riderProfile: { milestones: { lockCard: true, setupDone: true } } });
  const c = await riderFunnel(new Date(Date.now() - 86400_000));
  expect(c).toEqual({ started: 2, crew: 1, watcher: 1, lockCard: 1, setupDone: 1, firstShift: 1, firstShiftWithin7dFullyWatched: 1 });
});
