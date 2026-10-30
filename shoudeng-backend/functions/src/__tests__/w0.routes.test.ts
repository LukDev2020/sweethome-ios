jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);
jest.mock("@google-cloud/bigquery", () => ({
  BigQuery: jest.fn().mockImplementation(() => ({
    query: jest.fn(async () => [[]]),
    dataset: () => ({ table: () => ({ insert: jest.fn(async () => undefined) }) }),
  })),
}));

import request from "supertest";
import { resetFakeAdmin, tokenFor, readDoc, listDocs } from "./helpers/fakeAdmin";

const { app } = require("../app");
const auth = (uid: string) => ({ Authorization: `Bearer ${tokenFor(uid)}` });

describe("/v1/emergency-contacts", () => {
  beforeEach(() => resetFakeAdmin());
  const contact = { id: "c1", name: "Aunt Mei", relationship: "aunt", phone: "+86 138 0000 0000", email: "", address: "", countryCode: "CN" };

  it("round-trips the user's own contacts", async () => {
    const put = await request(app).put("/v1/emergency-contacts").set(auth("mom")).send([contact]);
    expect(put.status).toBe(200);
    expect(put.body).toEqual({ success: true });
    const get = await request(app).get("/v1/emergency-contacts").set(auth("mom"));
    expect(get.body).toEqual([contact]);
    const other = await request(app).get("/v1/emergency-contacts").set(auth("dad"));
    expect(other.body).toEqual([]);
  });

  it("rejects malformed or oversized lists", async () => {
    expect((await request(app).put("/v1/emergency-contacts").set(auth("mom")).send({ not: "array" })).status).toBe(400);
    expect((await request(app).put("/v1/emergency-contacts").set(auth("mom")).send([{ ...contact, phone: "call me" }])).status).toBe(400);
    const many = Array.from({ length: 11 }, (_, i) => ({ ...contact, id: `c${i}` }));
    expect((await request(app).put("/v1/emergency-contacts").set(auth("mom")).send(many)).status).toBe(400);
  });

  it("requires auth", async () => {
    expect((await request(app).get("/v1/emergency-contacts")).status).toBe(401);
  });
});

describe("POST /v1/location/pause", () => {
  beforeEach(() => resetFakeAdmin());

  it("stores the pause capped at 4 hours and writes a timeline entry", async () => {
    const farFuture = new Date(Date.now() + 24 * 3600 * 1000).toISOString();
    const res = await request(app).post("/v1/location/pause").set(auth("mom"))
      .send({ userId: "mom", paused: true, expiresAt: farFuture });
    expect(res.status).toBe(200);
    const until = new Date(res.body.pausedUntil).getTime();
    expect(until - Date.now()).toBeLessThanOrEqual(4 * 3600 * 1000 + 1000);
    expect(readDoc("user_telemetry/mom")!.trackingPaused).toBe(true);
    expect(listDocs("timeline_entries").map((d) => d.data.type)).toEqual(["trackingPaused"]);

    const resume = await request(app).post("/v1/location/pause").set(auth("mom")).send({ userId: "mom", paused: false });
    expect(resume.body.pausedUntil).toBeNull();
    expect(readDoc("user_telemetry/mom")!.trackingPaused).toBe(false);
  });

  it("cannot pause someone else", async () => {
    const res = await request(app).post("/v1/location/pause").set(auth("sarah")).send({ userId: "mom", paused: true });
    expect(res.status).toBe(403);
  });
});

describe("heartbeat writes real-time telemetry even when BigQuery fails", () => {
  beforeEach(() => resetFakeAdmin());
  it("updates user_telemetry", async () => {
    const res = await request(app).post("/v1/heartbeat").set(auth("mom")).send({
      userId: "mom", timestamp: new Date().toISOString(), source: "appForeground",
      batteryLevel: 0.5, batteryState: "unplugged", latitude: 30.6, longitude: 104.0, accuracy: 10,
    });
    expect(res.status).toBe(200);
    const tel = readDoc("user_telemetry/mom")!;
    expect(tel.batteryLevel).toBe(0.5);
    expect(tel.latitude).toBe(30.6);
    expect(tel.lastHeartbeat).toBeDefined();
  });
});
