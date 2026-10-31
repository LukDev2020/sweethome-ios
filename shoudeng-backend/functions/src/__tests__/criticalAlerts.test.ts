/**
 * Verifies the Critical Alerts behaviour described in the entitlement request:
 * - SOS pushes are Critical Alerts only for guardians who opted in, otherwise
 *   Time Sensitive.
 * - Critical SOS pushes use the APNs critical sound dictionary.
 * - Guardians can change the setting; saving preferences never wipes it.
 */
import express from "express";
import request from "supertest";

const mockUsers: Record<string, any> = {};
const mockSend = jest.fn();
const mockUpdate = jest.fn();

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
        docs: name === "device_tokens" ? [{ data: () => ({ token: "tok-1" }) }] : [],
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
    messaging: jest.fn(() => ({ sendEachForMulticast: mockSend })),
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
  const message = mockSend.mock.calls[mockSend.mock.calls.length - 1][0];
  return message.apns.payload.aps;
}

describe("SOS push: Critical Alerts only with guardian consent", () => {
  beforeEach(() => {
    for (const k of Object.keys(mockUsers)) delete mockUsers[k];
    mockSend.mockResolvedValue({ successCount: 1, failureCount: 0, responses: [{}] });
  });

  it("sends a critical alert with the critical sound dictionary when the guardian opted in", async () => {
    mockUsers["g-on"] = { locale: "en", notificationPrefs: { sosCriticalAlerts: true } };
    await sendSOSAlert("g-on", "Ann", "sos-1");
    const aps = lastAps();
    expect(aps["interruption-level"]).toBe("critical");
    expect(aps.sound).toEqual({ critical: true, name: "sos_alert.caf", volume: 1.0 });
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
