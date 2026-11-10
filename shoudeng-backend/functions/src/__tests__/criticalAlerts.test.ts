/**
 * Verifies the Critical Alerts behaviour described in the entitlement request:
 * - SOS pushes are Critical Alerts only for guardians who opted in, otherwise
 *   Time Sensitive.
 * - Critical SOS pushes use the APNs critical sound dictionary.
 * - Guardians can change the setting; saving preferences never wipes it.
 */
import express from "express";
import request from "supertest";

import * as crypto from "crypto";
import { __setApnsTransportForTests, __resetApnsForTests, ApnsTransportRequest } from "../services/apns";

const mockUsers: Record<string, any> = {};
const mockUpdate = jest.fn();
/** APNs requests, as sent to Apple */
const sent: ApnsTransportRequest[] = [];

jest.mock("firebase-admin", () => {
  const collection = jest.fn((name: string) => ({
    doc: jest.fn((id: string) => ({
      get: jest.fn(async () => ({
        exists: name === "users" && !!mockUsers[id],
        data: () => mockUsers[id],
      })),
      update: mockUpdate,
    })),
    where: jest.fn(() => ({
      get: jest.fn(async () => ({
        docs: name === "device_tokens" ? [{ ref: {}, data: () => ({ token: "a1b2c3d4", environment: "production" }) }] : [],
      })),
      limit: jest.fn(() => ({ get: jest.fn(async () => ({ docs: [] })) })),
    })),
  }));
  const firestore = Object.assign(jest.fn(() => ({ collection, batch: jest.fn() })), {
    Timestamp: { now: jest.fn(() => ({ seconds: 1, nanoseconds: 0 })) },
  });
  return {
    firestore,
    initializeApp: jest.fn(),
  };
});

jest.mock("../middleware/auth", () => ({
  authMiddleware: (req: any, _res: any, next: any) => { req.uid = "guardian-1"; next(); },
}));
jest.mock("../middleware/rateLimit", () => ({
  createRateLimiter: () => (_req: any, _res: any, next: any) => next(),
  RATE_LIMITS: {},
}));

import { sendSOSAlert } from "../services/fcm";

function lastAps() {
  return JSON.parse(sent[sent.length - 1].body).aps;
}

beforeAll(() => {
  process.env.APNS_AUTH_KEY = crypto.generateKeyPairSync("ec", { namedCurve: "P-256" })
    .privateKey.export({ type: "pkcs8", format: "pem" }).toString();
  process.env.APNS_KEY_ID = "TESTKEY123";
  __resetApnsForTests();
  __setApnsTransportForTests(async (req) => {
    sent.push(req);
    return { status: 200, headers: {}, body: "" };
  });
});
afterAll(() => {
  __setApnsTransportForTests(null);
  delete process.env.APNS_AUTH_KEY;
  delete process.env.APNS_KEY_ID;
});

describe("SOS push: Critical Alerts only with guardian consent", () => {
  // Critical alerts also need Apple's entitlement, switched on server-side.
  beforeAll(() => { process.env.CRITICAL_ALERTS_ENABLED = "true"; });
  afterAll(() => { delete process.env.CRITICAL_ALERTS_ENABLED; });

  it("stays Time Sensitive for an opted-in guardian until the entitlement flag is on", async () => {
    delete process.env.CRITICAL_ALERTS_ENABLED;
    mockUsers["g-on"] = { locale: "en", notificationPrefs: { sosCriticalAlerts: true } };
    await sendSOSAlert("g-on", "Ann", "sos-0");
    expect(lastAps()["interruption-level"]).toBe("time-sensitive");
    process.env.CRITICAL_ALERTS_ENABLED = "true";
  });

  beforeEach(() => {
    for (const k of Object.keys(mockUsers)) delete mockUsers[k];
    sent.length = 0;
  });

  it("sends a critical alert with the critical sound dictionary when the guardian opted in", async () => {
    mockUsers["g-on"] = { locale: "en", notificationPrefs: { sosCriticalAlerts: true } };
    await sendSOSAlert("g-on", "Ann", "sos-1");
    const aps = lastAps();
    expect(aps["interruption-level"]).toBe("critical");
    // APNs wants the integer 1 (firebase-admin used to convert true)
    expect(aps.sound).toEqual({ critical: 1, name: "sos_alert.caf", volume: 1.0 });
    expect(sent[0].headers).toMatchObject({ "apns-priority": "10", "apns-push-type": "alert" });
  });

  it("treats guardians without a stored choice (linked before the setting existed) as opted in", async () => {
    mockUsers["g-legacy"] = { locale: "en" };
    await sendSOSAlert("g-legacy", "Ann", "sos-2");
    expect(lastAps()["interruption-level"]).toBe("critical");
  });

  it("falls back to Time Sensitive with a normal sound when the guardian turned it off", async () => {
    mockUsers["g-off"] = { locale: "en", notificationPrefs: { sosCriticalAlerts: false } };
    await sendSOSAlert("g-off", "Ann", "sos-3");
    const aps = lastAps();
    expect(aps["interruption-level"]).toBe("time-sensitive");
    expect(aps.sound).toBe("sos_alert.caf");
  });
});

describe("PUT /notification-preferences", () => {
  const app = express();
  app.use(express.json());
  app.use("/v1/user", require("../routes/user").default);

  beforeEach(() => mockUpdate.mockResolvedValue(undefined));

  it("saves the guardian's SOS critical alert choice", async () => {
    const res = await request(app).put("/v1/user/notification-preferences").send({ sosCriticalAlerts: false });
    expect(res.status).toBe(200);
    expect(mockUpdate.mock.calls[0][0]).toMatchObject({ "notificationPrefs.sosCriticalAlerts": false });
  });

  it("only updates the fields that were sent, so older clients can't wipe the choice", async () => {
    await request(app).put("/v1/user/notification-preferences").send({ sosAlerts: true, familyFeed: false });
    const update = mockUpdate.mock.calls[0][0];
    expect(update).toMatchObject({ "notificationPrefs.sosAlerts": true, "notificationPrefs.familyFeed": false });
    expect(update).not.toHaveProperty("notificationPrefs");
    expect(update).not.toHaveProperty("notificationPrefs.sosCriticalAlerts");
  });

  it("ignores non-boolean values", async () => {
    await request(app).put("/v1/user/notification-preferences").send({ sosCriticalAlerts: "yes" });
    expect(mockUpdate.mock.calls[0][0]).not.toHaveProperty("notificationPrefs.sosCriticalAlerts");
  });
});
