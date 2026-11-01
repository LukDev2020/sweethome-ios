/**
 * Fair use of SOS SMS / voice calls (docs/pricing/PRICING.md): every plan gets SMS
 * fallback and voice escalation, up to 50 SMS and 30 call minutes per protected person
 * per calendar month. Beyond that escalation goes on by push only — the SOS is never blocked.
 */
jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);
jest.mock("@google-cloud/bigquery", () => ({
  BigQuery: jest.fn().mockImplementation(() => ({
    query: jest.fn(async () => [[]]),
    dataset: () => ({ table: () => ({ insert: jest.fn(async () => undefined) }) }),
  })),
}));

const mockSms = {
  sendSOSSms: jest.fn(async (..._a: unknown[]) => true),
  sendEmergencyContactSms: jest.fn(async (..._a: unknown[]) => true),
  hasAppInstalled: jest.fn(async (_id: string) => false), // nobody has the app → SMS every hop
};
jest.mock("../services/sms", () => ({
  sendSOSSms: (...a: unknown[]) => mockSms.sendSOSSms(...a),
  sendEmergencyContactSms: (...a: unknown[]) => mockSms.sendEmergencyContactSms(...a),
  hasAppInstalled: (id: string) => mockSms.hasAppInstalled(id),
}));

const mockCalls: { guardianId: string; fairUse?: unknown }[] = [];
let mockCallResult: string | null = "CA1";
jest.mock("../services/twilio", () => ({
  ...jest.requireActual("../services/twilio"),
  initiateVoiceCall: jest.fn(async (guardianId: string, _sos: string, _n: string, opts: { fairUse?: unknown }) => {
    mockCalls.push({ guardianId, fairUse: opts.fairUse });
    return mockCallResult;
  }),
}));

import { resetFakeAdmin, seed, readDoc, sentMessages, ts } from "./helpers/fakeAdmin";
import {
  FAIR_USE, usageMonth, reserveSms, recordSms, reserveVoiceMinute, releaseVoiceMinute,
  billedMinutes, settleVoiceCall,
} from "../services/fairUse";
import { advanceEscalation, initialEscalationFields, ESCALATION_PLAN } from "../services/escalation";
import { PLANS } from "../services/payment";

const T0 = new Date("2026-10-30T03:00:00Z");
const usage = (person = "mom", month = "2026-10") => readDoc(`sos_usage/${person}_${month}`);

beforeEach(() => {
  resetFakeAdmin();
  jest.clearAllMocks();
  mockCalls.length = 0;
  mockCallResult = "CA1";
  process.env.PUBLIC_API_BASE_URL = "https://us-central1-test.cloudfunctions.net/api";
});

describe("safety floor is free", () => {
  test("SMS fallback and voice escalation are in every plan, including free", () => {
    for (const plan of Object.values(PLANS)) {
      expect(plan.features).toContain("sms_fallback");
      expect(plan.features).toContain("voice_call_escalation");
      expect(plan.features).toContain("basic_sos");
    }
  });
});

describe("allowance", () => {
  test("50 SMS per person per month, then refused; next month starts again", async () => {
    for (let i = 0; i < FAIR_USE.smsPerMonth; i++) expect(await reserveSms("mom", 1, T0)).toBe(true);
    expect(await reserveSms("mom", 1, T0)).toBe(false);
    expect(usage()?.smsCount).toBe(50);
    expect(await reserveSms("dad", 1, T0)).toBe(true); // per person
    expect(await reserveSms("mom", 1, new Date("2026-11-01T00:00:00Z"))).toBe(true);
    expect(usageMonth(new Date("2026-11-30T23:59:59Z"))).toBe("2026-11");
  });

  test("uncapped SMS (emergency contacts) are still counted", async () => {
    for (let i = 0; i < 50; i++) await reserveSms("mom", 1, T0);
    await recordSms("mom", 1, T0);
    expect(usage()?.smsCount).toBe(51);
  });

  test("30 call minutes: each call reserves one, settled to the billed minutes", async () => {
    const r = await reserveVoiceMinute("mom", T0);
    expect(r).toEqual({ personId: "mom", month: "2026-10" });
    seed("voice_calls/CA1", { fairUse: r });
    await settleVoiceCall("CA1", "ringing", 0);   // not final: nothing yet
    expect(usage()?.voiceMinutes).toBe(1);
    await settleVoiceCall("CA1", "completed", 125); // 2m05s → 3 minutes
    expect(usage()?.voiceMinutes).toBe(3);
    await settleVoiceCall("CA1", "completed", 125); // settled once
    expect(usage()?.voiceMinutes).toBe(3);

    const r2 = await reserveVoiceMinute("mom", T0);
    seed("voice_calls/CA2", { fairUse: r2 });
    await settleVoiceCall("CA2", "no-answer", 0);   // unanswered calls are free
    expect(usage()?.voiceMinutes).toBe(3);
  });

  test("no minute is reserved past 30; a call that was never placed gives it back", async () => {
    seed("sos_usage/mom_2026-10", { voiceMinutes: 29 });
    const r = await reserveVoiceMinute("mom", T0);
    expect(r).not.toBeNull();
    expect(await reserveVoiceMinute("mom", T0)).toBeNull();
    await releaseVoiceMinute(r!);
    expect(usage()?.voiceMinutes).toBe(29);
  });

  test("billedMinutes rounds answered calls up", () => {
    expect(billedMinutes("completed", 1)).toBe(1);
    expect(billedMinutes("completed", 60)).toBe(1);
    expect(billedMinutes("completed", 61)).toBe(2);
    expect(billedMinutes("busy", 30)).toBe(0);
    expect(billedMinutes("completed", 0)).toBe(0);
  });
});

describe("escalation over the allowance falls back to push, never blocks the SOS", () => {
  function seedFamily() {
    seed("users/mom", { displayName: "Mom", role: "protected", timeZone: "Asia/Shanghai", phone: "+8613800000001" });
    for (const g of ["sarah", "kevin"]) {
      seed(`users/${g}`, { displayName: g, role: "guardian", phone: "+14165550101" });
      seed(`guardian_links/${g}_mom`, { guardianId: g, protectedPersonId: "mom", status: "active" });
      seed(`device_tokens/t_${g}`, { userId: g, token: `tok-${g}` });
    }
    seed("sos_events/sos1", {
      protectedPersonId: "mom", triggeredAt: ts(T0), resolvedAt: null, acknowledgedBy: null,
      ...initialEscalationFields(ts(T0) as any),
    });
  }
  const sos = () => readDoc("sos_events/sos1")!;
  const runAll = async () => {
    for (const p of ESCALATION_PLAN) await advanceEscalation("sos1", new Date(T0.getTime() + p.offsetMs));
  };
  const channels = () => (sos().escalationLog as { channel: string }[]).map((e) => e.channel);

  test("within the allowance: SMS and calls go out and are counted", async () => {
    seedFamily();
    await runAll();
    expect(sos().escalationState).toBe("exhausted");
    // hop2 SMS × 2 + share link SMS × 2
    expect(mockSms.sendSOSSms).toHaveBeenCalledTimes(4);
    expect(usage()?.smsCount).toBe(4);
    // 3 rounds × 2 guardians, each with a reservation
    expect(mockCalls).toHaveLength(6);
    expect(mockCalls.every((c) => (c.fairUse as { personId: string }).personId === "mom")).toBe(true);
    expect(usage()?.voiceMinutes).toBe(6);
    expect(sos().fairUseLimited).toBeUndefined();
  });

  test("SMS allowance used up: no SMS, pushes still sent, SOS runs to the end", async () => {
    seedFamily();
    seed("sos_usage/mom_2026-10", { smsCount: 50 });
    await runAll();
    expect(mockSms.sendSOSSms).not.toHaveBeenCalled();
    expect(channels().filter((c) => c === "sms_fair_use_limit")).toHaveLength(4);
    expect(sentMessages.length).toBeGreaterThan(0);
    expect(mockCalls).toHaveLength(6); // calls are a separate allowance
    expect(sos().fairUseLimited).toBe(true);
    expect(sos().escalationState).toBe("exhausted");
  });

  test("call minutes used up: guardians get a push instead of a call", async () => {
    seedFamily();
    seed("sos_usage/mom_2026-10", { voiceMinutes: 30 });
    await runAll();
    expect(mockCalls).toHaveLength(0);
    expect(channels().filter((c) => c === "push_fair_use_limit")).toHaveLength(6);
    const pushes = sentMessages.filter((m) => m.data?.action === "sos_alert").length;
    expect(pushes).toBeGreaterThanOrEqual(6 + 2); // hop1/hop2 pushes + one per skipped call
    expect(sos().fairUseLimited).toBe(true);
    expect(sos().escalationState).toBe("exhausted");
  });

  test("a call that could not be placed does not use the allowance", async () => {
    seedFamily();
    mockCallResult = null;
    await runAll();
    expect(usage()?.voiceMinutes ?? 0).toBe(0);
  });

  test("a failed SMS gives its allowance back", async () => {
    seedFamily();
    mockSms.sendSOSSms.mockResolvedValue(false);
    await runAll();
    expect(usage()?.smsCount ?? 0).toBe(0);
    mockSms.sendSOSSms.mockResolvedValue(true);
  });

  test("no guardians: emergency contacts are texted even over the allowance", async () => {
    seed("users/mom", { displayName: "Mom", role: "protected", locale: "en" });
    seed("emergency_contacts/mom", { contacts: [{ id: "c1", phone: "+14165550199" }] });
    seed("sos_usage/mom_2026-10", { smsCount: 50 });
    seed("sos_events/sos1", {
      protectedPersonId: "mom", triggeredAt: ts(T0), resolvedAt: null, acknowledgedBy: null,
      ...initialEscalationFields(ts(T0) as any),
    });
    await advanceEscalation("sos1", T0);
    expect(mockSms.sendEmergencyContactSms).toHaveBeenCalledTimes(1);
    expect(usage()?.smsCount).toBe(51);
  });
});

describe("manual call (POST /v1/voice-call) and the Twilio status callback", () => {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const request = require("supertest");
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { tokenFor } = require("./helpers/fakeAdmin");
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { app } = require("../app");

  function seedSOS() {
    seed("users/mom", { displayName: "Mom", role: "protected" });
    seed("users/sarah", { displayName: "Sarah", role: "guardian", phone: "+14165550101" });
    seed("guardian_links/sarah_mom", { guardianId: "sarah", protectedPersonId: "mom", status: "active" });
    seed("sos_events/sos1", { protectedPersonId: "mom", triggeredAt: ts(new Date()), resolvedAt: null });
  }

  test("refused with FAIR_USE_LIMIT once the month's minutes are used up", async () => {
    seedSOS();
    seed(`sos_usage/mom_${usageMonth()}`, { voiceMinutes: 30 });
    const res = await request(app).post("/v1/voice-call").set("Authorization", `Bearer ${tokenFor("sarah")}`)
      .send({ guardianId: "sarah", sosEventId: "sos1" });
    expect(res.status).toBe(429);
    expect(res.body.code).toBe("FAIR_USE_LIMIT");
    expect(mockCalls).toHaveLength(0);
  });

  test("within the allowance the call is placed with a reservation", async () => {
    seedSOS();
    const res = await request(app).post("/v1/voice-call").set("Authorization", `Bearer ${tokenFor("sarah")}`)
      .send({ guardianId: "sarah", sosEventId: "sos1" });
    expect(res.status).toBe(200);
    expect(mockCalls).toHaveLength(1);
    expect(readDoc(`sos_usage/mom_${usageMonth()}`)?.voiceMinutes).toBe(1);
  });
});
