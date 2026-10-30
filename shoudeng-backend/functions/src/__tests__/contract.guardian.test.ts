/**
 * Contract test: the REAL /v1/guardian/protected-persons route output, with BigQuery
 * returning its native timestamp wrapper objects, must be decodable by iOS
 * `ProtectedPersonStatusResponse` (strict ISO-8601 dates).
 *
 * The output is snapshotted to ShouDengTests/ContractFixtures/*.json, which the iOS
 * ContractFixtureTests decode with the app's own models. Regenerate with
 *   UPDATE_CONTRACT_FIXTURES=1 npx jest contract
 */
jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);
jest.mock("../services/geocoding", () => ({
  reverseGeocode: jest.fn(async () => "Jinjiang District, Chengdu"),
}));

const mockBigQueryRows: Record<string, unknown>[] = [];
jest.mock("@google-cloud/bigquery", () => ({
  BigQuery: jest.fn().mockImplementation(() => ({
    query: jest.fn(async () => [mockBigQueryRows]),
    dataset: () => ({ table: () => ({ insert: jest.fn(async () => undefined) }) }),
  })),
}));

import express from "express";
import request from "supertest";
import { resetFakeAdmin, seed, ts, tokenFor } from "./helpers/fakeAdmin";
import { writeContractFixture, expectMatchesFixture } from "./helpers/contractFixtures";

const NOW = new Date("2026-10-30T12:00:00.000Z");

/** Mimics @google-cloud/bigquery's BigQueryTimestamp. */
class BigQueryTimestamp {
  constructor(public value: string) {}
}

function buildApp() {
  const app = express();
  app.use(express.json());
  app.use("/v1/guardian", require("../routes/guardian").default);
  return app;
}

const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/;

describe("contract: GET /v1/guardian/protected-persons", () => {
  beforeEach(() => {
    resetFakeAdmin();
    mockBigQueryRows.length = 0;
    jest.useFakeTimers({ now: NOW, doNotFake: ["nextTick", "setImmediate", "setTimeout", "setInterval", "queueMicrotask"] });

    seed("users/mom", { displayName: "Mom", role: "protected", timeZone: "Asia/Shanghai", countryCode: "CN", cityName: "Chengdu" });
    seed("users/dad", { displayName: "Dad", role: "protected", timeZone: "America/Toronto", countryCode: "CA", cityName: "Toronto" });
    seed("guardian_links/sarah_mom", { guardianId: "sarah", protectedPersonId: "mom", status: "active", permissions: { canSeeLocation: true } });
    seed("guardian_links/kevin_mom", { guardianId: "kevin", protectedPersonId: "mom", status: "active" });
    seed("guardian_links/sarah_dad", { guardianId: "sarah", protectedPersonId: "dad", status: "active", permissions: { canSeeLocation: false } });
    seed("checkins/c1", { userId: "mom", timestamp: ts("2026-10-30T10:58:00Z") });
  });

  afterEach(() => jest.useRealTimers());

  it("normalises BigQuery timestamp objects to ISO-8601 (BigQuery fallback path)", async () => {
    mockBigQueryRows.push({
      user_id: "mom",
      timestamp: new BigQueryTimestamp("2026-10-30T11:55:00.000Z"),
      latitude: 30.657, longitude: 104.066, accuracy: 12,
      battery_level: 0.62, battery_state: "unplugged",
    });

    const res = await request(buildApp())
      .get("/v1/guardian/protected-persons")
      .set("Authorization", `Bearer ${tokenFor("sarah")}`);

    expect(res.status).toBe(200);
    expect(res.body).toHaveLength(2);
    const mom = res.body.find((p: any) => p.personId === "mom");
    expect(mom.locationTimestamp).toBe("2026-10-30T11:55:00.000Z");
    expect(mom.lastPhoneActivity).toBe("2026-10-30T11:55:00.000Z");
    expect(mom.lastCheckIn).toBe("2026-10-30T10:58:00.000Z");
    expect(mom.status).toBe("normal");
    expect(mom.protectionLayers).toBe(2);
    expect(JSON.stringify(res.body)).not.toContain("[object Object]");
    expect(JSON.stringify(res.body)).not.toContain('"value"');
    for (const p of res.body) {
      for (const k of ["locationTimestamp", "lastCheckIn", "lastPhoneActivity"]) {
        if (p[k] !== null) expect(p[k]).toMatch(ISO);
      }
    }
    // Dad hid his location from Sarah
    const dad = res.body.find((p: any) => p.personId === "dad");
    expect(dad.latitude).toBeNull();
    expect(dad.locationTimestamp).toBeNull();

    expectMatchesFixture("guardian_protected_persons.json", res.body);
  });

  it("prefers Firestore real-time telemetry and does not need BigQuery", async () => {
    seed("user_telemetry/mom", {
      lastHeartbeat: ts("2026-10-30T11:59:00Z"),
      latitude: 30.66, longitude: 104.07, accuracy: 8,
      locationTimestamp: ts("2026-10-30T11:58:30Z"),
      batteryLevel: 0.41, batteryState: "charging",
    });
    const res = await request(buildApp())
      .get("/v1/guardian/protected-persons")
      .set("Authorization", `Bearer ${tokenFor("sarah")}`);
    const mom = res.body.find((p: any) => p.personId === "mom");
    expect(mom.lastPhoneActivity).toBe("2026-10-30T11:59:00.000Z");
    expect(mom.locationTimestamp).toBe("2026-10-30T11:58:30.000Z");
    expect(mom.batteryLevel).toBe(0.41);
    writeContractFixture("guardian_protected_persons_realtime.json", res.body);
  });

  it("one person with corrupt data does not blank the dashboard", async () => {
    seed("checkins/bad", { userId: "dad", timestamp: "not-a-date" });
    const res = await request(buildApp())
      .get("/v1/guardian/protected-persons")
      .set("Authorization", `Bearer ${tokenFor("sarah")}`);
    expect(res.status).toBe(200);
    expect(res.body.map((p: any) => p.personId).sort()).toEqual(["dad", "mom"]);
    const dad = res.body.find((p: any) => p.personId === "dad");
    expect(dad.lastCheckIn).toBeNull();
  });

  it("requires auth", async () => {
    const res = await request(buildApp()).get("/v1/guardian/protected-persons");
    expect(res.status).toBe(401);
  });
});

describe("heartbeat-missing check parses BigQuery timestamps", () => {
  beforeEach(() => {
    resetFakeAdmin();
    mockBigQueryRows.length = 0;
  });

  it("alerts guardians once per silent period", async () => {
    const { checkUser } = require("../scheduled/heartbeatCheck");
    const now = new Date("2026-10-30T12:00:00Z");
    mockBigQueryRows.push({ user_id: "mom", timestamp: new BigQueryTimestamp("2026-10-30T11:00:00.000Z") });
    seed("users/sarah", { locale: "en" });
    seed("device_tokens/t1", { userId: "sarah", token: "tok-sarah" });
    seed("guardian_links/sarah_mom", { guardianId: "sarah", protectedPersonId: "mom", status: "active" });

    const { sentMessages } = require("./helpers/fakeAdmin");
    expect(await checkUser("mom", "Mom", now)).toBe(true);
    expect(sentMessages).toHaveLength(1);
    expect(sentMessages[0].notification.body).toContain("60 minutes");
    // Second run for the same silence → no duplicate alert
    expect(await checkUser("mom", "Mom", now)).toBe(false);
    expect(sentMessages).toHaveLength(1);
  });
});
