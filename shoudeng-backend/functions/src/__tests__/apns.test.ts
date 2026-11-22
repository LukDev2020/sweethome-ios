/**
 * Push goes straight to Apple over HTTP/2 (services/apns.ts + services/push.ts).
 *
 * Two local HTTP/2 servers stand in for api.push.apple.com and
 * api.sandbox.push.apple.com; the REAL transport, JWT signing and payload building
 * run end to end from sendSOSAlert() etc., over the in-memory Firestore.
 */
jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);
jest.mock("@google-cloud/bigquery", () => ({
  BigQuery: jest.fn().mockImplementation(() => ({
    query: jest.fn(async () => [[]]),
    dataset: () => ({ table: () => ({ insert: jest.fn(async () => undefined) }) }),
  })),
}));

import * as http2 from "http2";
import * as crypto from "crypto";
import { AddressInfo } from "net";
import * as jwt from "jsonwebtoken";
import request from "supertest";
import { resetFakeAdmin, seed, readDoc, tokenFor } from "./helpers/fakeAdmin";
import {
  __setApnsTransportForTests,
  __setApnsHostsForTests,
  __resetApnsForTests,
  closeApnsSessions,
  normalizeP8,
  sendApns,
} from "../services/apns";
import { buildApnsNotification } from "../services/push";
import { sendSOSAlert, sendSilentPush, sendCheckinReminder } from "../services/fcm";
import { __resetConfigReportsForTests } from "../config/params";

// ---------------------------------------------------------------------------
// Fake APNs
// ---------------------------------------------------------------------------

interface Received {
  host: "production" | "sandbox";
  headers: http2.IncomingHttpHeaders;
  token: string;
  body: any;
}

type Reply = { status: number; reason?: string };
/** Decide the answer for a request; default 200. */
let answer: (r: Received) => Reply = () => ({ status: 200 });
const received: Received[] = [];
const sessionsOpened = { production: 0, sandbox: 0 };

function fakeApns(host: "production" | "sandbox"): Promise<http2.Http2Server> {
  const server = http2.createServer();
  server.on("session", () => { sessionsOpened[host]++; });
  server.on("stream", (stream: http2.ServerHttp2Stream, headers) => {
    let raw = "";
    stream.setEncoding("utf8");
    stream.on("data", (c: string) => { raw += c; });
    stream.on("end", () => {
      const r: Received = {
        host,
        headers,
        token: String(headers[":path"]).replace("/3/device/", ""),
        body: JSON.parse(raw),
      };
      received.push(r);
      const reply = answer(r);
      stream.respond({ ":status": reply.status, "apns-id": `id-${received.length}` });
      stream.end(reply.status === 200 ? "" : JSON.stringify({ reason: reply.reason }));
    });
  });
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve(server)));
}

const { publicKey, privateKey } = crypto.generateKeyPairSync("ec", { namedCurve: "P-256" });
const P8 = privateKey.export({ type: "pkcs8", format: "pem" }).toString();
const TOKEN_PROD = "a".repeat(64);
const TOKEN_SANDBOX = "b".repeat(64);

let prodServer: http2.Http2Server;
let sandboxServer: http2.Http2Server;

beforeAll(async () => {
  prodServer = await fakeApns("production");
  sandboxServer = await fakeApns("sandbox");
});

afterAll(async () => {
  closeApnsSessions();
  await new Promise((r) => prodServer.close(r));
  await new Promise((r) => sandboxServer.close(r));
  __setApnsHostsForTests(null);
  delete process.env.CRITICAL_ALERTS_ENABLED;
});

beforeEach(() => {
  resetFakeAdmin(); // installs a recording fake transport; use the real one here
  __setApnsTransportForTests(null);
  __resetApnsForTests();
  __resetConfigReportsForTests();
  __setApnsHostsForTests({
    production: `http://127.0.0.1:${(prodServer.address() as AddressInfo).port}`,
    sandbox: `http://127.0.0.1:${(sandboxServer.address() as AddressInfo).port}`,
  });
  process.env.APNS_AUTH_KEY = P8;
  process.env.APNS_KEY_ID = "KEY1234567";
  delete process.env.APPLE_TEAM_ID;
  delete process.env.CRITICAL_ALERTS_ENABLED;
  received.length = 0;
  sessionsOpened.production = 0;
  sessionsOpened.sandbox = 0;
  answer = () => ({ status: 200 });
  jest.spyOn(console, "log").mockImplementation(() => undefined);
  jest.spyOn(console, "warn").mockImplementation(() => undefined);
  jest.spyOn(console, "error").mockImplementation(() => undefined);

  seed("users/sarah", { displayName: "Sarah", locale: "en", notificationPrefs: { sosCriticalAlerts: true } });
  seed("device_tokens/sarah_ios", { userId: "sarah", token: TOKEN_PROD, platform: "ios", environment: "production" });
});

afterEach(() => jest.restoreAllMocks());

// ---------------------------------------------------------------------------

describe("request to Apple", () => {
  it("SOS: provider JWT, APNs headers and the payload FCM used to build", async () => {
    process.env.CRITICAL_ALERTS_ENABLED = "true";
    const before = Math.floor(Date.now() / 1000);
    const r = await sendSOSAlert("sarah", "Mom", "sos1", {
      protectedPersonId: "mom", locationDescription: "Chengdu", batteryLevel: 0.23, latitude: 30.5, longitude: 104.1,
    });
    expect(r).toEqual({ successCount: 1, failureCount: 0, allFailed: false });
    expect(received).toHaveLength(1);
    const { host, headers, token, body } = received[0];
    expect(host).toBe("production");
    expect(token).toBe(TOKEN_PROD);

    // JWT: ES256 with the key id, issued by the team, signed by the .p8
    const auth = String(headers.authorization);
    expect(auth).toMatch(/^bearer /);
    const decoded = jwt.decode(auth.slice(7), { complete: true })!;
    expect(decoded.header).toMatchObject({ alg: "ES256", kid: "KEY1234567" });
    const claims = jwt.verify(auth.slice(7), publicKey.export({ type: "spki", format: "pem" }), {
      algorithms: ["ES256"],
    }) as jwt.JwtPayload;
    expect(claims.iss).toBe("B98QT5LTWZ");
    expect(claims.iat).toBeGreaterThanOrEqual(before);
    expect(claims.iat).toBeLessThanOrEqual(before + 5);

    expect(headers[":method"]).toBe("POST");
    expect(headers["apns-topic"]).toBe("com.shoudeng.app");
    expect(headers["apns-push-type"]).toBe("alert");
    expect(headers["apns-priority"]).toBe("10");
    expect(Number(headers["apns-expiration"])).toBeGreaterThanOrEqual(before + 86400);
    expect(headers["content-type"]).toBe("application/json");

    expect(body.aps).toEqual({
      alert: { title: expect.any(String), body: expect.stringContaining("23%") },
      sound: { critical: 1, name: "sos_alert.caf", volume: 1.0 },
      "interruption-level": "critical",
      "relevance-score": 1.0,
      category: "SOS_ALERT",
      // wakes the guardian's app to put the SOS on its lock-screen card
      "content-available": 1,
    });
    expect(body).toMatchObject({
      action: "sos_alert", sos_id: "sos1", person_id: "mom", protected_person_name: "Mom",
      battery: "0.23", lat: "30.5", lng: "104.1",
    });
  });

  it("SOS is Time Sensitive with a plain sound until CRITICAL_ALERTS_ENABLED", async () => {
    await sendSOSAlert("sarah", "Mom", "sos1");
    expect(received[0].body.aps["interruption-level"]).toBe("time-sensitive");
    expect(received[0].body.aps.sound).toBe("sos_alert.caf");
  });

  it("notification-only messages get aps.alert from the notification, plus category", async () => {
    await sendCheckinReminder("sarah", "Mom");
    expect(received[0].body.aps).toMatchObject({
      alert: { title: expect.any(String), body: expect.stringContaining("Mom") },
      sound: "default",
      category: "CHECKIN_REMINDER",
    });
    expect(received[0].body.action).toBe("checkin_reminder");
  });

  it("silent push: background type, priority 5, content-available, no alert", async () => {
    await sendSilentPush("sarah");
    const { headers, body } = received[0];
    expect(headers["apns-push-type"]).toBe("background");
    expect(headers["apns-priority"]).toBe("5");
    expect(body).toEqual({ action: "heartbeat_wake", aps: { "content-available": 1 } });
  });

  it("reuses one HTTP/2 connection and one provider token across sends", async () => {
    await sendSOSAlert("sarah", "Mom", "sos1");
    await sendSOSAlert("sarah", "Mom", "sos2");
    await sendSilentPush("sarah");
    expect(received).toHaveLength(3);
    expect(sessionsOpened.production).toBe(1);
    expect(new Set(received.map((r) => r.headers.authorization)).size).toBe(1);
  });

  it("every device of the user gets it", async () => {
    seed("device_tokens/sarah_ipad", { userId: "sarah", token: "c".repeat(64), environment: "production" });
    const r = await sendSOSAlert("sarah", "Mom", "sos1");
    expect(r.successCount).toBe(2);
    expect(received.map((x) => x.token).sort()).toEqual([TOKEN_PROD, "c".repeat(64)]);
  });
});

describe("environments", () => {
  it("a token from an Xcode debug build (environment: development) goes to the sandbox host", async () => {
    seed("device_tokens/sarah_ios", { userId: "sarah", token: TOKEN_SANDBOX, platform: "ios", environment: "development" });
    const r = await sendSOSAlert("sarah", "Mom", "sos1");
    expect(r.allFailed).toBe(false);
    expect(received.map((x) => x.host)).toEqual(["sandbox"]);
    expect(sessionsOpened.production).toBe(0);
  });

  it("no stored environment = production", async () => {
    seed("device_tokens/sarah_ios", { userId: "sarah", token: TOKEN_PROD, platform: "ios" });
    await sendSOSAlert("sarah", "Mom", "sos1");
    expect(received.map((x) => x.host)).toEqual(["production"]);
  });

  it("BadDeviceToken on production → tries sandbox once, delivers, and corrects the stored environment", async () => {
    seed("device_tokens/sarah_ios", { userId: "sarah", token: TOKEN_SANDBOX, platform: "ios", environment: "production" });
    answer = (r) => (r.host === "production" ? { status: 400, reason: "BadDeviceToken" } : { status: 200 });
    const res = await sendSOSAlert("sarah", "Mom", "sos1");
    expect(res).toEqual({ successCount: 1, failureCount: 0, allFailed: false });
    expect(received.map((x) => x.host)).toEqual(["production", "sandbox"]);
    expect(readDoc("device_tokens/sarah_ios")).toMatchObject({ token: TOKEN_SANDBOX, environment: "development" });
  });
});

describe("dead tokens", () => {
  it("410 Unregistered removes the token", async () => {
    answer = () => ({ status: 410, reason: "Unregistered" });
    const r = await sendSOSAlert("sarah", "Mom", "sos1");
    expect(r).toEqual({ successCount: 0, failureCount: 1, allFailed: true });
    expect(readDoc("device_tokens/sarah_ios")).toBeUndefined();
  });

  it("BadDeviceToken from both hosts removes the token", async () => {
    answer = () => ({ status: 400, reason: "BadDeviceToken" });
    const r = await sendSOSAlert("sarah", "Mom", "sos1");
    expect(r.allFailed).toBe(true);
    expect(received.map((x) => x.host)).toEqual(["production", "sandbox"]);
    expect(readDoc("device_tokens/sarah_ios")).toBeUndefined();
  });

  it("a token that isn't an APNs token (e.g. an FCM token) is removed without calling Apple", async () => {
    seed("device_tokens/sarah_ios", { userId: "sarah", token: "fcm:APA91b-xyz", environment: "production" });
    const r = await sendSOSAlert("sarah", "Mom", "sos1");
    expect(r.allFailed).toBe(true);
    expect(received).toHaveLength(0);
    expect(readDoc("device_tokens/sarah_ios")).toBeUndefined();
  });

  it("a token the phone replaced in the meantime is kept", async () => {
    answer = () => {
      // The app re-registers (same doc id) while Apple answers for the old token.
      seed("device_tokens/sarah_ios", { userId: "sarah", token: "d".repeat(64), environment: "production" });
      return { status: 410, reason: "Unregistered" };
    };
    await sendSOSAlert("sarah", "Mom", "sos1");
    expect(readDoc("device_tokens/sarah_ios")).toMatchObject({ token: "d".repeat(64) });
  });

  it("other errors keep the token (e.g. our topic or key is wrong, Apple is down)", async () => {
    for (const reply of [
      { status: 400, reason: "DeviceTokenNotForTopic" },
      { status: 403, reason: "InvalidProviderToken" },
      { status: 503, reason: "ServiceUnavailable" },
    ]) {
      answer = () => reply;
      const r = await sendSOSAlert("sarah", "Mom", "sos1");
      expect(r.allFailed).toBe(true);
      expect(readDoc("device_tokens/sarah_ios")).toBeDefined();
    }
  });
});

describe("retries", () => {
  it("ExpiredProviderToken → signs a new JWT and retries once", async () => {
    let calls = 0;
    answer = () => (++calls === 1 ? { status: 403, reason: "ExpiredProviderToken" } : { status: 200 });
    const nowSpy = jest.spyOn(Date, "now");
    nowSpy.mockReturnValueOnce(Date.now() - 2 * 3600 * 1000); // first JWT "issued" 2 h ago
    const r = await sendSOSAlert("sarah", "Mom", "sos1");
    nowSpy.mockRestore();
    expect(r.allFailed).toBe(false);
    expect(received).toHaveLength(2);
    expect(received[0].headers.authorization).not.toBe(received[1].headers.authorization);
  });

  it("5xx → retries once", async () => {
    let calls = 0;
    answer = () => (++calls === 1 ? { status: 500, reason: "InternalServerError" } : { status: 200 });
    const r = await sendSOSAlert("sarah", "Mom", "sos1");
    expect(r.allFailed).toBe(false);
    expect(received).toHaveLength(2);
  });

  it("network error → retries once, then reports failure without throwing", async () => {
    __setApnsHostsForTests({ production: "http://127.0.0.1:1" });
    const r = await sendApns(TOKEN_PROD, "production", buildApnsNotification({ notification: { title: "t", body: "b" } }));
    expect(r).toMatchObject({ ok: false, status: 0, unregistered: false });
    expect(r.reason).toMatch(/^NetworkError/);
  });
});

describe("configuration", () => {
  it("no key yet (\"disabled\"): nothing is sent, SOS reports allFailed so SMS takes over, one [Config] error", async () => {
    process.env.APNS_AUTH_KEY = "disabled";
    const r1 = await sendSOSAlert("sarah", "Mom", "sos1");
    const r2 = await sendSOSAlert("sarah", "Mom", "sos2");
    expect(r1.allFailed && r2.allFailed).toBe(true);
    expect(received).toHaveLength(0);
    expect(readDoc("device_tokens/sarah_ios")).toBeDefined();
    const configErrors = (console.error as jest.Mock).mock.calls.filter((c) => String(c[0]).includes("[Config]"));
    expect(configErrors).toHaveLength(1);
    expect(configErrors[0][0]).toContain("APNS_AUTH_KEY");
  });

  it("APPLE_TEAM_ID overrides the team in the JWT", async () => {
    process.env.APPLE_TEAM_ID = "TEAM999999";
    await sendSilentPush("sarah");
    const claims = jwt.decode(String(received[0].headers.authorization).slice(7)) as jwt.JwtPayload;
    expect(claims.iss).toBe("TEAM999999");
  });

  it("accepts the .p8 with literal \\n or as bare base64", () => {
    const body = P8.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
    expect(normalizeP8(P8.replace(/\n/g, "\\n"))).toBe(P8.trim());
    expect(crypto.createPrivateKey(normalizeP8(body)).asymmetricKeyDetails?.namedCurve).toBe("prime256v1");
  });
});

describe("payload", () => {
  it("shortens a long alert body to fit Apple's 4 KB limit", () => {
    const n = buildApnsNotification({ notification: { title: "t", body: "路".repeat(3000) }, data: { action: "x" } });
    const size = Buffer.byteLength(JSON.stringify(n.payload), "utf8");
    expect(size).toBeLessThanOrEqual(4096);
    expect((n.payload.aps as any).alert.body.endsWith("…")).toBe(true);
  });
});

describe("POST /v1/device/token", () => {
  const { app } = require("../app");
  const auth = { Authorization: `Bearer ${tokenFor("sarah")}` };

  it("stores the APNs token with its environment", async () => {
    const res = await request(app).post("/v1/device/token").set(auth)
      .send({ token: TOKEN_SANDBOX, platform: "ios", environment: "development" });
    expect(res.status).toBe(200);
    expect(readDoc("device_tokens/sarah_ios")).toMatchObject({ token: TOKEN_SANDBOX, environment: "development" });
  });

  it("anything but \"development\" is production", async () => {
    await request(app).post("/v1/device/token").set(auth).send({ token: TOKEN_PROD, platform: "ios" });
    expect(readDoc("device_tokens/sarah_ios")).toMatchObject({ environment: "production" });
  });

  it("refuses a value that can't be an APNs token", async () => {
    const res = await request(app).post("/v1/device/token").set(auth)
      .send({ token: "abc/../../3/device/x", platform: "ios" });
    expect(res.status).toBe(400);
  });
});
