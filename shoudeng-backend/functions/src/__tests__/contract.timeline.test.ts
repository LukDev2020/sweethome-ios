jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);

import express from "express";
import request from "supertest";
import { resetFakeAdmin, seed, ts, tokenFor } from "./helpers/fakeAdmin";
import { expectMatchesFixture } from "./helpers/contractFixtures";

function buildApp() {
  const app = express();
  app.use(express.json());
  app.use("/v1/timeline", require("../routes/timeline").default);
  return app;
}

describe("contract: GET /v1/timeline", () => {
  beforeEach(() => {
    resetFakeAdmin();
    const types = ["checkIn", "sosTriggered", "sosResolved", "ble_separation",
      "silent_alarm_confirmed", "silent_alarm_missed", "silent_alarm_escalated", "voiceNote", "homeTimerSet"];
    types.forEach((type, i) =>
      seed(`timeline_entries/e${i}`, {
        userId: "mom", type, description: `entry ${i}`, detail: null,
        timestamp: ts(Date.UTC(2026, 9, 30, 12, 0 - i)),
      }));
    seed("timeline_entries/other", { userId: "dad", type: "checkIn", description: "x", timestamp: ts("2026-10-30T12:00:00Z") });
    seed("timeline_entries/broken", { userId: "mom", type: "checkIn", description: "no timestamp" });
  });

  it("returns hasMore + every backend entry type", async () => {
    const res = await request(buildApp()).get("/v1/timeline?limit=50")
      .set("Authorization", `Bearer ${tokenFor("mom")}`);
    expect(res.status).toBe(200);
    expect(res.body.hasMore).toBe(false);
    expect(res.body.entries).toHaveLength(9);
    expectMatchesFixture("timeline.json", res.body);
  });

  it("paginates with limit + before", async () => {
    const app = buildApp();
    const page1 = await request(app).get("/v1/timeline?limit=4").set("Authorization", `Bearer ${tokenFor("mom")}`);
    expect(page1.body.entries).toHaveLength(4);
    expect(page1.body.hasMore).toBe(true);
    const page2 = await request(app).get(`/v1/timeline?limit=4&before=${encodeURIComponent(page1.body.nextBefore)}`)
      .set("Authorization", `Bearer ${tokenFor("mom")}`);
    expect(page2.body.entries[0].id).toBe("e4");
    const page3 = await request(app).get(`/v1/timeline?limit=4&before=${encodeURIComponent(page2.body.nextBefore)}`)
      .set("Authorization", `Bearer ${tokenFor("mom")}`);
    expect(page3.body.entries.map((e: any) => e.id)).toEqual(["e8"]);
    expect(page3.body.hasMore).toBe(false);
  });

  describe("?personId= (guardian viewing someone they protect)", () => {
    const get = (uid: string, path: string) =>
      request(buildApp()).get(path).set("Authorization", `Bearer ${tokenFor(uid)}`);

    it("an active guardian sees only that person's entries", async () => {
      seed("guardian_links/sarah_dad", { guardianId: "sarah", protectedPersonId: "dad", status: "active" });
      const res = await get("sarah", "/v1/timeline?personId=dad");
      expect(res.status).toBe(200);
      expect(res.body.entries.map((e: { id: string }) => e.id)).toEqual(["other"]);
    });

    it("anyone else is refused", async () => {
      expect((await get("stranger", "/v1/timeline?personId=mom")).status).toBe(403);
      seed("guardian_links/sarah_mom", { guardianId: "sarah", protectedPersonId: "mom", status: "revoked" });
      expect((await get("sarah", "/v1/timeline?personId=mom")).status).toBe(403);
    });

    it("personId = yourself is the normal timeline", async () => {
      const res = await get("mom", "/v1/timeline?personId=mom&limit=50");
      expect(res.status).toBe(200);
      expect(res.body.entries).toHaveLength(9);
    });
  });
});
