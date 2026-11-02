/**
 * W2 behaviour through the FULL Express app (exact production mount order):
 * router auth bleed, rate-limit isolation, SOS trigger/resolve/acknowledge,
 * Twilio keypad acknowledgement, and the Home Safe push.
 */
jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);
jest.mock("@google-cloud/bigquery", () => ({
  BigQuery: jest.fn().mockImplementation(() => ({
    query: jest.fn(async () => [[]]),
    dataset: () => ({ table: () => ({ insert: jest.fn(async () => undefined) }) }),
  })),
}));
// Twilio webhook signatures are checked with the TWILIO_AUTH_TOKEN param.
process.env.TWILIO_AUTH_TOKEN = "twilio-secret";
afterAll(() => {
  delete process.env.TWILIO_AUTH_TOKEN;
});

import * as crypto from "crypto";
import request from "supertest";
import { resetFakeAdmin, seed, readDoc, sentMessages, tokenFor, ts, listDocs } from "./helpers/fakeAdmin";

const { app } = require("../app");
const auth = (uid: string) => ({ Authorization: `Bearer ${tokenFor(uid)}` });
const BASE = "https://us-central1-test.cloudfunctions.net/api";

function twilioSign(path: string, params: Record<string, string>) {
  const data = BASE + path + Object.keys(params).sort().map((k) => k + params[k]).join("");
  return crypto.createHmac("sha1", "twilio-secret").update(Buffer.from(data, "utf-8")).digest("base64");
}

function seedFamily() {
  seed("users/mom", { displayName: "Mom", role: "protected", timeZone: "Asia/Shanghai", cityName: "Chengdu", locale: "zh" });
  seed("users/sarah", { displayName: "Sarah", role: "guardian", locale: "en" });
  seed("users/kevin", { displayName: "Kevin", role: "guardian", locale: "zh" });
  for (const g of ["sarah", "kevin"]) {
    seed(`guardian_links/${g}_mom`, { guardianId: g, protectedPersonId: "mom", status: "active" });
    seed(`device_tokens/t_${g}`, { userId: g, token: `tok-${g}` });
  }
  seed("device_tokens/t_mom", { userId: "mom", token: "tok-mom" });
}

beforeEach(() => {
  resetFakeAdmin();
  delete process.env.FUNCTIONS_EMULATOR;
  process.env.PUBLIC_API_BASE_URL = BASE;
});

describe("no auth bleed from routers mounted at bare /v1", () => {
  const publicRoutes: [string, string][] = [
    ["post", "/v1/voice-callback"],
    ["post", "/v1/voice-replay"],
    ["post", "/v1/webhooks/twilio/call-status"],
    ["post", "/v1/webhooks/twilio/sms-status"],
    ["post", "/v1/webhooks/apple/subscription"],
    ["post", "/v1/payment/apple-webhook"],
    ["get", "/v1/evidence/share/abc"],
    ["get", "/v1/medical-card/share/abc"],
    ["get", "/health"],
  ];
  for (const [method, path] of publicRoutes) {
    it(`${method.toUpperCase()} ${path} is reachable without an app token`, async () => {
      const res = await (request(app) as any)[method](path).send({});
      expect(res.status).not.toBe(401);
      expect(res.status).not.toBe(429);
    });
  }

  it("protected routes still require auth", async () => {
    for (const [m, p] of [["post", "/v1/heartbeat"], ["post", "/v1/checkin"], ["post", "/v1/sos/trigger"],
      ["post", "/v1/voice-call"], ["get", "/v1/user/me"], ["post", "/v1/diagnostics/crash"]]) {
      const res = await (request(app) as any)[m](p).send({});
      expect([p, res.status]).toEqual([p, 401]);
    }
  });
});

describe("rate limits are isolated per limit", () => {
  it("heartbeats never make /v1/user/delete return 429", async () => {
    seed("users/mom", { displayName: "Mom" });
    for (let i = 0; i < 8; i++) {
      await request(app).post("/v1/heartbeat").set(auth("mom"))
        .send({ userId: "mom", timestamp: new Date().toISOString(), source: "test" });
    }
    const del = await request(app).post("/v1/user/delete").set(auth("mom")).send({});
    expect(del.status).not.toBe(429);
  });

  it("a second real SOS in the same hour is not rate limited", async () => {
    seedFamily();
    for (let i = 0; i < 5; i++) {
      const t = await request(app).post("/v1/sos/trigger").set(auth("mom")).send({ protectedPersonId: "mom" });
      expect(t.status).toBe(201);
      const r = await request(app).post("/v1/sos/resolve").set(auth("mom"))
        .send({ sosEventId: t.body.sosEventId, resolution: "protectedCancelled" });
      expect(r.status).toBe(200);
    }
  });

  it("buckets are namespaced by limit name", () => {
    const { rateLimitDocId, RATE_LIMITS } = require("../middleware/rateLimit");
    expect(rateLimitDocId(RATE_LIMITS.telemetry, "u1", 0)).not.toBe(rateLimitDocId(RATE_LIMITS.accountDelete, "u1", 0));
  });
});

describe("SOS trigger / resolve", () => {
  it("creates the escalation state machine fields and is idempotent while active", async () => {
    seedFamily();
    const a = await request(app).post("/v1/sos/trigger").set(auth("mom"))
      .send({ protectedPersonId: "mom", batteryLevel: 0.4, clientSOSId: "local-aaaa-1111" });
    expect(a.status).toBe(201);
    const doc = readDoc(`sos_events/${a.body.sosEventId}`)!;
    expect(doc).toMatchObject({ escalationNextStep: "hop1", escalationState: "initiated", clientSOSIds: ["local-aaaa-1111"] });

    const b = await request(app).post("/v1/sos/trigger").set(auth("mom"))
      .send({ protectedPersonId: "mom", clientSOSId: "local-bbbb-2222" });
    expect(b.body.sosEventId).toBe(a.body.sosEventId);
    expect(readDoc(`sos_events/${a.body.sosEventId}`)!.clientSOSIds).toEqual(["local-aaaa-1111", "local-bbbb-2222"]);
  });

  it("a stale offline resolve cannot close a newer, real SOS", async () => {
    seedFamily();
    // Old SOS (device id local-old-0001) already resolved
    seed("sos_events/old", { protectedPersonId: "mom", triggeredAt: ts("2026-10-29T10:00:00Z"), resolvedAt: ts("2026-10-29T10:05:00Z"), clientSOSIds: ["local-old-0001"] });
    const fresh = await request(app).post("/v1/sos/trigger").set(auth("mom")).send({ protectedPersonId: "mom", clientSOSId: "local-new-0002" });
    // The offline queue replays the old cancel
    const stale = await request(app).post("/v1/sos/resolve").set(auth("mom"))
      .send({ sosEventId: "local-old-0001", resolution: "protectedCancelled" });
    expect(stale.status).toBe(409);
    expect(readDoc(`sos_events/${fresh.body.sosEventId}`)!.resolvedAt).toBeNull();
    // An unknown local id doesn't fall back to "whatever is active"
    const unknown = await request(app).post("/v1/sos/resolve").set(auth("mom"))
      .send({ sosEventId: "local-zzz-9999", resolution: "protectedCancelled" });
    expect(unknown.status).toBe(404);
    expect(readDoc(`sos_events/${fresh.body.sosEventId}`)!.resolvedAt).toBeNull();
    // The matching local id does resolve it
    const ok = await request(app).post("/v1/sos/resolve").set(auth("mom"))
      .send({ sosEventId: "local-new-0002", resolution: "protectedCancelled" });
    expect(ok.body).toMatchObject({ success: true, sosEventId: fresh.body.sosEventId });
  });

  it("validates resolution and who may use it", async () => {
    seedFamily();
    const t = await request(app).post("/v1/sos/trigger").set(auth("mom")).send({ protectedPersonId: "mom" });
    const bad = await request(app).post("/v1/sos/resolve").set(auth("mom")).send({ sosEventId: t.body.sosEventId, resolution: "whatever" });
    expect(bad.status).toBe(400);
    const guardianCancel = await request(app).post("/v1/sos/resolve").set(auth("sarah"))
      .send({ sosEventId: t.body.sosEventId, resolution: "protectedCancelled" });
    expect(guardianCancel.status).toBe(400);
    const safe = await request(app).post("/v1/sos/resolve").set(auth("sarah"))
      .send({ sosEventId: t.body.sosEventId, resolution: "guardianConfirmedSafe" });
    expect(safe.status).toBe(200);
    expect(sentMessages.some((m) => m.tokens.includes("tok-mom") && m.data.action === "sos_resolved")).toBe(true);
  });

  it("GET /v1/sos/active reflects real escalation state for the person", async () => {
    seedFamily();
    expect((await request(app).get("/v1/sos/active").set(auth("mom"))).body).toEqual({ active: false, sos: null });
    await request(app).post("/v1/sos/trigger").set(auth("mom")).send({ protectedPersonId: "mom" });
    const r = await request(app).get("/v1/sos/active").set(auth("mom"));
    expect(r.body.active).toBe(true);
    expect(r.body.sos).toMatchObject({ escalationState: "initiated", nextStep: "hop1", noGuardians: false });
  });
});

describe("POST /v1/sos/acknowledge", () => {
  it("freezes and notifies; statuses for forbidden / resolved", async () => {
    seedFamily();
    const t = await request(app).post("/v1/sos/trigger").set(auth("mom")).send({ protectedPersonId: "mom" });
    const id = t.body.sosEventId;
    expect((await request(app).post("/v1/sos/acknowledge").set(auth("stranger")).send({ sosEventId: id })).status).toBe(403);
    const ok = await request(app).post("/v1/sos/acknowledge").set(auth("sarah")).send({ sosEventId: id });
    expect(ok.body).toMatchObject({ success: true, acknowledgedBy: "sarah", alreadyAcknowledged: false });
    expect(readDoc(`sos_events/${id}`)!.escalationState).toBe("frozen");
    expect(sentMessages.map((m) => m.tokens[0]).sort()).toEqual(["tok-kevin", "tok-mom"]);
    // "Mom is safe" is still the separate close action
    await request(app).post("/v1/sos/resolve").set(auth("sarah")).send({ sosEventId: id, resolution: "guardianConfirmedSafe" });
    expect((await request(app).post("/v1/sos/acknowledge").set(auth("kevin")).send({ sosEventId: id })).status).toBe(409);
  });
});

describe("Twilio keypad acknowledgement", () => {
  function seedCall() {
    seedFamily();
    seed("sos_events/s1", { protectedPersonId: "mom", triggeredAt: ts(new Date()), resolvedAt: null, acknowledgedBy: null,
      escalationState: "hop3_voiceCalling", escalationNextStep: "voice2", escalationNextAt: ts(new Date(Date.now() + 60_000)) });
    seed("voice_calls/CA123", { sosEventId: "s1", guardianId: "kevin", lang: "zh", personName: "Mom", isLastRound: false });
  }

  it("digit 1 with a valid signature acknowledges exactly the matched SOS as that guardian", async () => {
    seedCall();
    const params = { CallSid: "CA123", Digits: "1" };
    const res = await request(app).post("/v1/voice-callback")
      .set("x-twilio-signature", twilioSign("/v1/voice-callback", params))
      .type("form").send(params);
    expect(res.status).toBe(200);
    expect(res.text).toContain("<Say");
    expect(res.text).toContain("自动呼叫已停止");
    expect(readDoc("sos_events/s1")).toMatchObject({ escalationState: "frozen", acknowledgedBy: "kevin", acknowledgedVia: "voice" });
  });

  it("rejects a forged callback", async () => {
    seedCall();
    const res = await request(app).post("/v1/voice-callback")
      .set("x-twilio-signature", "forged").type("form").send({ CallSid: "CA123", Digits: "1" });
    expect(res.status).toBe(403);
    expect(readDoc("sos_events/s1")!.escalationState).toBe("hop3_voiceCalling");
  });

  it("digit 2 replays in the guardian's language; unknown CallSid does nothing", async () => {
    seedCall();
    const p2 = { CallSid: "CA123", Digits: "2" };
    const r2 = await request(app).post("/v1/voice-callback").set("x-twilio-signature", twilioSign("/v1/voice-callback", p2)).type("form").send(p2);
    expect(r2.text).toContain(`${BASE}/v1/voice-replay`);
    const pr = { CallSid: "CA123" };
    const replay = await request(app).post("/v1/voice-replay").set("x-twilio-signature", twilioSign("/v1/voice-replay", pr)).type("form").send(pr);
    expect(replay.text).toContain('language="cmn-CN"');
    expect(replay.text).toContain(`action="${BASE}/v1/voice-callback"`);
    const pu = { CallSid: "CAnope", Digits: "1" };
    await request(app).post("/v1/voice-callback").set("x-twilio-signature", twilioSign("/v1/voice-callback", pu)).type("form").send(pu);
    expect(readDoc("sos_events/s1")!.escalationState).toBe("hop3_voiceCalling");
  });
});

describe("Home Safe → guardians", () => {
  it("pushes every guardian with city and local time, deduped for 10 minutes", async () => {
    seedFamily();
    const res = await request(app).post("/v1/checkin").set(auth("mom")).send({ userId: "mom" });
    expect(res.status).toBe(200);
    expect(res.body.guardiansNotified).toBe(2);
    const toSarah = sentMessages.find((m) => m.tokens[0] === "tok-sarah")!;
    expect(toSarah.notification.title).toBe("Mom is home safe");
    expect(toSarah.notification.body).toMatch(/^Chengdu · \d{2}:\d{2}$/);
    expect(toSarah.data).toMatchObject({ action: "checkin_safe", person_id: "mom" });

    const again = await request(app).post("/v1/checkin").set(auth("mom")).send({ userId: "mom" });
    expect(again.body.guardiansNotified).toBe(0);
    expect(sentMessages).toHaveLength(2);
    expect(listDocs("checkins")).toHaveLength(2); // both check-ins still recorded
  });

  it("respects a guardian who turned check-in notifications off", async () => {
    seedFamily();
    seed("users/kevin", { displayName: "Kevin", notificationPrefs: { checkinReminder: false } });
    const res = await request(app).post("/v1/checkin").set(auth("mom")).send({ userId: "mom" });
    expect(res.body.guardiansNotified).toBe(1);
    expect(sentMessages.map((m) => m.tokens[0])).toEqual(["tok-sarah"]);
  });
});

describe("voice-call target validation", () => {
  it("only calls an active guardian of this SOS's person", async () => {
    seedFamily();
    seed("users/stranger", { displayName: "X", phone: "+10000000000" });
    const t = await request(app).post("/v1/sos/trigger").set(auth("mom")).send({ protectedPersonId: "mom" });
    const res = await request(app).post("/v1/voice-call").set(auth("mom"))
      .send({ guardianId: "stranger", sosEventId: t.body.sosEventId });
    expect(res.status).toBe(403);
  });
});

describe("user locale", () => {
  it("PUT /v1/user/me stores a normalised locale used for pushes / calls", async () => {
    seed("users/sarah", { displayName: "Sarah" });
    expect((await request(app).put("/v1/user/me").set(auth("sarah")).send({ locale: "fr-CA" })).status).toBe(200);
    expect(readDoc("users/sarah")!.locale).toBe("fr");
    expect((await request(app).put("/v1/user/me").set(auth("sarah")).send({ locale: "de" })).status).toBe(400);
    expect((await request(app).put("/v1/user/me").set(auth("sarah")).send({ timeZone: "Mars/Olympus" })).status).toBe(400);
  });
});

describe("PUT /v1/duty-schedule accepts 24 and overnight slots", () => {
  it("saves 23-24 and 22→6, rejects equal hours", async () => {
    seedFamily();
    seed("subscriptions/mom", { planId: "family", status: "active", currentPeriodEnd: ts(new Date(Date.now() + 86400000)) });
    const put = (slots: unknown) => request(app).put("/v1/duty-schedule").set(auth("mom")).send({ guardianId: "sarah", slots });
    const ok = await put([{ startHour: 23, endHour: 24, dayOfWeek: [1] }, { startHour: 22, endHour: 6, dayOfWeek: [2] }]);
    expect(ok.status).toBe(200);
    expect(listDocs("duty_schedules").map((d) => `${d.data.dayOfWeek}:${d.data.startHour}-${d.data.endHour}`).sort())
      .toEqual(["1:23-24", "2:22-6"]);
    expect((await put([{ startHour: 5, endHour: 5 }])).status).toBe(400);
    expect((await put([{ startHour: 5, endHour: 25 }])).status).toBe(400);
  });
});
