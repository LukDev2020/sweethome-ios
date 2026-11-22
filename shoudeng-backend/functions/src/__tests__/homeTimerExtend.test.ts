/**
 * POST /v1/home-timer/extend — "+15 min" on the lock-screen card moves the
 * deadline and keeps the destination and notes the person set.
 */
jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);

import express from "express";
import request from "supertest";
import { resetFakeAdmin, seed, readDoc, tokenFor, FakeTimestamp } from "./helpers/fakeAdmin";

const app = express();
app.use(express.json());
app.use("/v1/home-timer", require("../routes/homeTimer").default);
const extend = (uid: string, body: object) =>
  request(app).post("/v1/home-timer/extend").set("Authorization", `Bearer ${tokenFor(uid)}`).send(body);
const minutesFromNow = (m: number) => new Date(Date.now() + m * 60_000);
const deadlineOf = () => {
  const d = readDoc("home_timers/mom")!.deadline;
  return (typeof d.toDate === "function" ? d.toDate() : new Date(d)).getTime();
};

beforeEach(() => {
  resetFakeAdmin();
  seed("users/mom", { displayName: "Mom", role: "protected" });
});

const seedTimer = (deadline: Date, status = "active") => seed("home_timers/mom", {
  userId: "mom", deadline: FakeTimestamp.fromDate(deadline), label: "Home", destination: "Home", routeNotes: "Bus 24", status,
});

it("adds the minutes to the deadline and keeps destination and notes", async () => {
  const before = minutesFromNow(10);
  seedTimer(before);
  const res = await extend("mom", { minutes: 15 });
  expect(res.status).toBe(200);
  expect(new Date(res.body.deadline).getTime()).toBe(before.getTime() + 15 * 60_000);
  expect(deadlineOf()).toBe(before.getTime() + 15 * 60_000);
  expect(readDoc("home_timers/mom")).toMatchObject({ destination: "Home", routeNotes: "Bus 24", status: "active" });
});

it("a deadline already passed is extended from now", async () => {
  seedTimer(minutesFromNow(-5));
  const res = await extend("mom", { minutes: 15 });
  expect(res.status).toBe(200);
  expect(Math.abs(deadlineOf() - minutesFromNow(15).getTime())).toBeLessThan(5_000);
});

it("no active timer → 404; bad minutes → 400; no auth → 401", async () => {
  expect((await extend("mom", { minutes: 15 })).status).toBe(404);
  seedTimer(minutesFromNow(10), "dismissed");
  expect((await extend("mom", { minutes: 15 })).status).toBe(404);
  seedTimer(minutesFromNow(10));
  for (const minutes of [0, -5, 121, 2.5, "15x"]) {
    expect((await extend("mom", { minutes })).status).toBe(400);
  }
  expect((await request(app).post("/v1/home-timer/extend").send({ minutes: 15 })).status).toBe(401);
});
