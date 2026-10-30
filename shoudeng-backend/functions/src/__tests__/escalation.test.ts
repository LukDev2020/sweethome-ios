/**
 * SOS escalation state machine (services/escalation.ts), run against the
 * in-memory Firestore with real FCM payloads and mocked SMS / Twilio.
 *
 * Replaces the old regex-on-source checks of onSOSCreated, which would have
 * passed with the logic broken.
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
  hasAppInstalled: jest.fn(async (id: string) => id !== "lucy"),
};
jest.mock("../services/sms", () => ({
  sendSOSSms: (...a: unknown[]) => mockSms.sendSOSSms(...a),
  sendEmergencyContactSms: (...a: unknown[]) => mockSms.sendEmergencyContactSms(...a),
  hasAppInstalled: (id: string) => mockSms.hasAppInstalled(id),
}));

let mockCallCounter = 0;
const mockCalls: { guardianId: string; sosId: string; round: number; isLastRound: boolean }[] = [];
jest.mock("../services/twilio", () => ({
  ...jest.requireActual("../services/twilio"),
  initiateVoiceCall: jest.fn(async (guardianId: string, sosId: string, _name: string, opts: { round: number; isLastRound: boolean }) => {
    mockCalls.push({ guardianId, sosId, ...opts });
    return `CA${++mockCallCounter}`;
  }),
}));

import { resetFakeAdmin, seed, readDoc, sentMessages, ts, listDocs } from "./helpers/fakeAdmin";
import {
  advanceEscalation,
  advanceDueEscalations,
  acknowledgeSOS,
  initialEscalationFields,
  ESCALATION_PLAN,
} from "../services/escalation";

// 2026-10-30 03:00 UTC = 11:00 in Chengdu (Asia/Shanghai)
const T0 = new Date("2026-10-30T03:00:00Z");
const at = (sec: number) => new Date(T0.getTime() + sec * 1000);

function seedFamily(opts: { guardians?: boolean } = {}) {
  seed("users/mom", { displayName: "Mom", role: "protected", timeZone: "Asia/Shanghai", locale: "zh", phone: "+8613800000001" });
  seed("users/sarah", { displayName: "Sarah", role: "guardian", locale: "en", phone: "+14165550101" });
  seed("users/kevin", { displayName: "Kevin", role: "guardian", locale: "zh", phone: "+8613900000003" });
  seed("users/lucy", { displayName: "Lucy", role: "guardian", locale: "fr", phone: "+33600000004" });
  if (opts.guardians !== false) {
    for (const g of ["sarah", "kevin", "lucy"]) {
      seed(`guardian_links/${g}_mom`, { guardianId: g, protectedPersonId: "mom", status: "active" });
    }
    seed("device_tokens/t_sarah", { userId: "sarah", token: "tok-sarah" });
    seed("device_tokens/t_kevin", { userId: "kevin", token: "tok-kevin" });
    // Duty in Chengdu local time: Kevin 08-20, Sarah overnight 20→08, Lucy 15-23
    for (let day = 1; day <= 7; day++) {
      seed(`duty_schedules/k${day}`, { guardianId: "kevin", protectedPersonId: "mom", dayOfWeek: day, startHour: 8, endHour: 20, isActive: true });
      seed(`duty_schedules/s${day}`, { guardianId: "sarah", protectedPersonId: "mom", dayOfWeek: day, startHour: 20, endHour: 8, isActive: true });
      seed(`duty_schedules/l${day}`, { guardianId: "lucy", protectedPersonId: "mom", dayOfWeek: day, startHour: 15, endHour: 23, isActive: true });
    }
  }
  seed("sos_events/sos1", {
    protectedPersonId: "mom",
    triggeredAt: ts(T0),
    resolvedAt: null,
    acknowledgedBy: null,
    batteryLevel: 0.23,
    latitude: 30.6586,
    longitude: 104.0647,
    ...initialEscalationFields(ts(T0) as any),
  });
}

const pushTargets = () => sentMessages.map((m) => m.tokens).flat();
const sos = () => readDoc("sos_events/sos1")!;

beforeEach(() => {
  resetFakeAdmin();
  jest.clearAllMocks();
  mockCalls.length = 0;
  mockCallCounter = 0;
  process.env.PUBLIC_API_BASE_URL = "https://us-central1-test.cloudfunctions.net/api";
  delete process.env.CRITICAL_ALERTS_ENABLED;
});

describe("hop 1 — on-duty guardian in the PROTECTED PERSON's time zone", () => {
  it("pushes only the guardian on duty at 11:00 Chengdu time, with battery in the alert", async () => {
    seedFamily();
    const r = await advanceEscalation("sos1", at(0));
    expect(r.ran).toBe("hop1");
    expect(pushTargets()).toEqual(["tok-kevin"]);
    expect(sentMessages[0].notification.body).toContain("23%");
    expect(sentMessages[0].data).toMatchObject({ action: "sos_alert", sos_id: "sos1", person_id: "mom" });
    expect(sos().escalationState).toBe("hop1_notified");
    expect(sos().escalationNextStep).toBe("hop2");
    expect(sos().escalationNextAt.toMillis()).toBe(at(30).getTime());
  });

  it("at 23:00 Chengdu the overnight guardian (Sarah, 20→08) is on duty", async () => {
    seedFamily();
    const lateNight = new Date("2026-10-30T15:00:00Z"); // 23:00 Asia/Shanghai
    seed("sos_events/sos1", { ...readDoc("sos_events/sos1"), triggeredAt: ts(lateNight), escalationNextAt: ts(lateNight) });
    await advanceEscalation("sos1", lateNight);
    expect(pushTargets()).toEqual(["tok-sarah"]);
  });

  it("time-sensitive by default; critical only when the entitlement flag is on", async () => {
    seedFamily();
    await advanceEscalation("sos1", at(0));
    expect(sentMessages[0].apns.payload.aps["interruption-level"]).toBe("time-sensitive");
    process.env.CRITICAL_ALERTS_ENABLED = "true";
    resetFakeAdmin();
    seedFamily();
    await advanceEscalation("sos1", at(0));
    expect(sentMessages[0].apns.payload.aps["interruption-level"]).toBe("critical");
    expect(sentMessages[0].apns.payload.aps.sound).toMatchObject({ critical: 1, name: "sos_alert.caf" });
  });
});

describe("full chain until someone responds", () => {
  it("runs hop2 → voice1 → share → voice2 → voice3 → exhausted on schedule", async () => {
    seedFamily();
    const logSpy = jest.spyOn(console, "log");
    const steps: (string | null)[] = [];
    for (const p of ESCALATION_PLAN) {
      // Not due yet → nothing happens
      if (p.offsetMs > 0) {
        const early = await advanceEscalation("sos1", new Date(T0.getTime() + p.offsetMs - 1000));
        expect(early.ran).toBeNull();
      }
      steps.push((await advanceEscalation("sos1", new Date(T0.getTime() + p.offsetMs))).ran);
    }
    expect(steps).toEqual(["hop1", "hop2", "voice1", "share", "voice2", "voice3"]);
    expect(sos().escalationState).toBe("exhausted");
    expect(sos().escalationNextStep).toBeNull();

    // hop2: every guardian pushed; Lucy has no app → SMS
    expect(mockSms.sendSOSSms.mock.calls.filter((c) => c[3] === undefined).map((c) => c[0])).toEqual(["lucy"]);
    // 3 voice rounds × 3 guardians, last round flagged
    expect(mockCalls.map((c) => `${c.round}:${c.guardianId}`)).toEqual([
      "1:sarah", "1:kevin", "1:lucy", "2:sarah", "2:kevin", "2:lucy", "3:sarah", "3:kevin", "3:lucy",
    ]);
    expect(mockCalls.filter((c) => c.isLastRound).length).toBe(3);
    // hop 4 actually SENDS the emergency link by SMS to every guardian
    const linkTexts = mockSms.sendSOSSms.mock.calls.filter((c) => typeof c[3] === "string");
    expect(linkTexts.map((c) => c[0])).toEqual(["sarah", "kevin", "lucy"]);
    expect(String(linkTexts[0][3])).toMatch(/^https:\/\/us-central1-test\.cloudfunctions\.net\/api\/v1\/evidence\/share\/[0-9a-f]{64}$/);
    // …and the token never reaches the logs
    const token = String(linkTexts[0][3]).split("/").pop()!;
    expect(JSON.stringify(logSpy.mock.calls)).not.toContain(token);
    expect(JSON.stringify(sos().escalationLog)).not.toContain(token);
    expect(sos().shareLinkSentAt).toBeDefined();
    logSpy.mockRestore();
  });

  it("the scheduler picks up a due step after the inline runner died", async () => {
    seedFamily();
    await advanceEscalation("sos1", at(0));
    // Instance crashed: nothing ran hop2. One minute later the scheduler does.
    const ran = await advanceDueEscalations(at(60));
    expect(ran).toBe(1);
    expect(sos().escalationState).toBe("hop2_allNotified");
  });
});

describe("idempotency", () => {
  it("re-running the same due step (re-delivered trigger) does not notify twice", async () => {
    seedFamily();
    await advanceEscalation("sos1", at(0));
    const again = await advanceEscalation("sos1", at(0));
    expect(again.ran).toBeNull();
    expect(sentMessages).toHaveLength(1);
  });

  it("a held lease blocks a concurrent runner", async () => {
    seedFamily();
    seed("sos_events/sos1", { ...sos(), escalationLeaseUntil: ts(at(60)) });
    const r = await advanceEscalation("sos1", at(0));
    expect(r.ran).toBeNull();
    expect(sentMessages).toHaveLength(0);
  });

  it("a retried step skips targets already sent before a crash", async () => {
    seedFamily();
    await advanceEscalation("sos1", at(0));
    await advanceEscalation("sos1", at(30)); // hop2
    // Simulate a crash mid-voice1: Sarah was called, then the lease expired
    seed("sos_events/sos1", {
      ...sos(),
      escalationNextStep: "voice1",
      escalationNextAt: ts(at(90)),
      "escalationSent": { ...sos().escalationSent, "voice1:sarah": true },
    });
    await advanceEscalation("sos1", at(90));
    expect(mockCalls.map((c) => c.guardianId)).toEqual(["kevin", "lucy"]);
  });
});

describe("acknowledge (\"I've got it\")", () => {
  it("freezes escalation, tells the other guardians and the protected person", async () => {
    seedFamily();
    seed("device_tokens/t_mom", { userId: "mom", token: "tok-mom" });
    seed("device_tokens/t_lucy", { userId: "lucy", token: "tok-lucy" });
    await advanceEscalation("sos1", at(0));
    sentMessages.length = 0;

    const r = await acknowledgeSOS("sos1", "sarah", "app");
    expect(r).toEqual({ status: "acknowledged", acknowledgedBy: "sarah", alreadyAcknowledged: false });
    expect(sos().escalationState).toBe("frozen");
    expect(sos().escalationNextStep).toBeNull();
    const byToken = Object.fromEntries(sentMessages.map((m) => [m.tokens[0], m]));
    expect(Object.keys(byToken).sort()).toEqual(["tok-kevin", "tok-lucy", "tok-mom"]);
    expect(byToken["tok-kevin"].notification.body).toContain("Sarah"); // zh copy names Sarah
    expect(byToken["tok-lucy"].notification.body).toMatch(/Sarah gère le SOS de Mom/);
    expect(byToken["tok-mom"].data.action).toBe("sos_acknowledged");

    // Nothing else is sent afterwards
    sentMessages.length = 0;
    expect((await advanceEscalation("sos1", at(600))).ran).toBeNull();
    expect(sentMessages).toHaveLength(0);
    expect(mockCalls).toHaveLength(0);
  });

  it("is idempotent and keeps the first responder", async () => {
    seedFamily();
    await acknowledgeSOS("sos1", "kevin", "voice");
    const second = await acknowledgeSOS("sos1", "sarah", "app");
    expect(second).toEqual({ status: "acknowledged", acknowledgedBy: "kevin", alreadyAcknowledged: true });
  });

  it("rejects non-guardians and resolved SOS", async () => {
    seedFamily();
    expect((await acknowledgeSOS("sos1", "stranger", "app")).status).toBe("forbidden");
    seed("sos_events/sos1", { ...sos(), resolvedAt: ts(at(10)) });
    expect((await acknowledgeSOS("sos1", "sarah", "app")).status).toBe("resolved");
    expect((await acknowledgeSOS("nope", "sarah", "app")).status).toBe("not_found");
  });

  it("stops voice calls that have not been placed yet in the current round", async () => {
    seedFamily();
    for (const sec of [0, 30]) await advanceEscalation("sos1", at(sec));
    const twilio = require("../services/twilio");
    twilio.initiateVoiceCall.mockImplementationOnce(async (g: string) => {
      mockCalls.push({ guardianId: g, sosId: "sos1", round: 1, isLastRound: false });
      await acknowledgeSOS("sos1", "sarah", "voice"); // Sarah presses 1 during her call
      return "CA-sarah";
    });
    await advanceEscalation("sos1", at(90));
    expect(mockCalls.map((c) => c.guardianId)).toEqual(["sarah"]);
  });
});

describe("no guardians", () => {
  it("texts the personal emergency contacts with the link and flags the SOS", async () => {
    seedFamily({ guardians: false });
    seed("emergency_contacts/mom", {
      contacts: [
        { id: "c1", name: "Aunt Mei", phone: "+8613800000009" },
        { id: "c2", name: "Neighbor", phone: "+8613800000010" },
      ],
    });
    const r = await advanceEscalation("sos1", at(0));
    expect(r.nextAt).toBeNull();
    expect(mockSms.sendEmergencyContactSms.mock.calls.map((c) => c[0])).toEqual(["+8613800000009", "+8613800000010"]);
    expect(String(mockSms.sendEmergencyContactSms.mock.calls[0][3])).toContain("/v1/evidence/share/");
    expect(sos()).toMatchObject({ noGuardians: true, emergencyContactsNotified: 2, escalationState: "no_guardians" });
  });

  it("still marks the SOS when there are no contacts either (app tells the user to call emergency services)", async () => {
    seedFamily({ guardians: false });
    await advanceEscalation("sos1", at(0));
    expect(sos()).toMatchObject({ noGuardians: true, emergencyContactsNotified: 0, escalationState: "no_guardians" });
    expect(listDocs("evidence_shares")).toHaveLength(0);
  });
});
