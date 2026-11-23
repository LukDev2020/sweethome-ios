/**
 * Someone looked after who also looks after family ("both roles"): the account
 * keeps a flag for the home's switch, and nothing on the server depends on which
 * side the app is showing.
 */
jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);

import express from "express";
import request from "supertest";
import { resetFakeAdmin, seed, readDoc, tokenFor, FakeTimestamp } from "./helpers/fakeAdmin";

const app = express();
app.use(express.json());
app.use("/v1/user", require("../routes/user").default);
app.use("/v1/itinerary", require("../routes/itinerary").default);
const as = (uid: string) => ({
  get: (p: string) => request(app).get(p).set("Authorization", `Bearer ${tokenFor(uid)}`),
  put: (p: string, body: object) => request(app).put(p).set("Authorization", `Bearer ${tokenFor(uid)}`).send(body),
});

beforeEach(() => {
  resetFakeAdmin();
  const createdAt = FakeTimestamp.now();
  // Kai rides (looked after by his mum) and looks after his grandma
  seed("users/kai", { displayName: "Kai", role: "protected", timeZone: "UTC", countryCode: "CA", cityName: "", createdAt });
  seed("users/mum", { displayName: "Mum", role: "guardian", createdAt });
  seed("users/grandma", { displayName: "Grandma", role: "protected", createdAt });
  seed("guardian_links/mum_kai", { guardianId: "mum", protectedPersonId: "kai", status: "active" });
  seed("guardian_links/kai_grandma", { guardianId: "kai", protectedPersonId: "grandma", status: "active" });
});

it("stores and returns the both-roles flag; rejects anything but true/false", async () => {
  expect((await as("kai").get("/v1/user/me")).body.bothRoles).toBe(false);
  expect((await as("kai").put("/v1/user/me", { bothRoles: true })).status).toBe(200);
  expect(readDoc("users/kai")).toMatchObject({ bothRoles: true, role: "protected" });
  expect((await as("kai").get("/v1/user/me")).body.bothRoles).toBe(true);
  expect((await as("kai").put("/v1/user/me", { bothRoles: "yes" })).status).toBe(400);
});

it("switching the home side only changes the role field", async () => {
  await as("kai").put("/v1/user/me", { bothRoles: true });
  expect((await as("kai").put("/v1/user/me", { role: "guardian" })).status).toBe(200);
  expect(readDoc("users/kai")).toMatchObject({ role: "guardian", bothRoles: true });
  // The links — who looks after whom — are untouched
  expect(readDoc("guardian_links/mum_kai")).toMatchObject({ status: "active" });
  expect(readDoc("guardian_links/kai_grandma")).toMatchObject({ status: "active" });
});

it("itineraries: my own and grandma's, on either side", async () => {
  const soon = FakeTimestamp.fromDate(new Date(Date.now() + 3600_000));
  seed("itineraries/k1", { userId: "kai", type: "flight", departureTime: soon, status: "scheduled" });
  seed("itineraries/g1", { userId: "grandma", type: "flight", departureTime: soon, status: "scheduled" });
  seed("itineraries/m1", { userId: "mum", type: "flight", departureTime: soon, status: "scheduled" });
  for (const role of ["protected", "guardian"]) {
    seed("users/kai", { ...readDoc("users/kai"), role });
    const res = await as("kai").get("/v1/itinerary");
    expect(res.status).toBe(200);
    const owners = (res.body.itineraries ?? res.body).map((i: { userId: string }) => i.userId).sort();
    expect(owners).toEqual(["grandma", "kai"]); // never mum's: Kai doesn't look after her
  }
});

it("work role: null until set, then kept beside the home style; true/false only", async () => {
  expect((await as("kai").get("/v1/user/me")).body.workRole).toBeNull();
  expect((await as("kai").put("/v1/user/me", { workRole: true, useCase: "rider", homeStyle: "simple" })).status).toBe(200);
  expect(readDoc("users/kai")).toMatchObject({ workRole: true, useCase: "rider", homeStyle: "simple" });
  const me = (await as("kai").get("/v1/user/me")).body;
  expect(me).toMatchObject({ workRole: true, homeStyle: "simple", useCase: "rider" });
  expect(me.riderProfile).not.toBeNull(); // the rider setup and crew stay available
  expect((await as("kai").put("/v1/user/me", { workRole: false })).status).toBe(200);
  expect((await as("kai").get("/v1/user/me")).body.workRole).toBe(false);
  expect((await as("kai").put("/v1/user/me", { workRole: "on" })).status).toBe(400);
});
