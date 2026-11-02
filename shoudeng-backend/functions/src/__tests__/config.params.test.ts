/**
 * Runtime configuration (config/params.ts): Twilio + Google Maps come from
 * firebase-functions params (Secret Manager / functions/.env), not the retired
 * functions.config(). Unset config must never throw — SMS / calls / geocoding are
 * skipped with one clear error, and the functions that need secrets bind them.
 */
jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);
jest.mock("@google-cloud/bigquery", () => ({
  BigQuery: jest.fn().mockImplementation(() => ({
    query: jest.fn(async () => [[]]),
    dataset: () => ({ table: () => ({ insert: jest.fn(async () => undefined) }) }),
  })),
}));

import * as fs from "fs";
import * as path from "path";
import * as crypto from "crypto";
import { resetFakeAdmin, seed } from "./helpers/fakeAdmin";
import {
  twilioConfig,
  missingTwilioParams,
  googleMapsApiKey,
  reportMissingConfig,
  __resetConfigReportsForTests,
  TWILIO_SECRETS,
  API_SECRETS,
} from "../config/params";
import { sendSOSSms, sendEmergencyContactSms, __setSmsClientForTests } from "../services/sms";
import { initiateVoiceCall, verifyTwilioSignature, __setTwilioClientForTests } from "../services/twilio";
import { reverseGeocode } from "../services/geocoding";

const KEYS = ["TWILIO_ACCOUNT_SID", "TWILIO_AUTH_TOKEN", "TWILIO_FROM_NUMBER", "TWILIO_SMS_FROM", "GOOGLE_MAPS_API_KEY"];
const configured = {
  TWILIO_ACCOUNT_SID: "AC-test",
  TWILIO_AUTH_TOKEN: "token-test",
  TWILIO_FROM_NUMBER: "+15550001111",
};

function setEnv(values: Record<string, string>) {
  for (const k of KEYS) delete process.env[k];
  Object.assign(process.env, values);
}

let errorSpy: jest.SpyInstance;

beforeEach(() => {
  setEnv({});
  resetFakeAdmin();
  __resetConfigReportsForTests();
  __setSmsClientForTests(null);
  __setTwilioClientForTests(null);
  errorSpy = jest.spyOn(console, "error").mockImplementation(() => undefined);
  jest.spyOn(console, "warn").mockImplementation(() => undefined);
  seed("users/g1", { displayName: "Sarah", phone: "+14165550101", locale: "en" });
});

afterEach(() => jest.restoreAllMocks());
afterAll(() => setEnv({}));

describe("twilioConfig()", () => {
  it("reads the TWILIO_* params, trimmed", () => {
    setEnv({ ...configured, TWILIO_ACCOUNT_SID: "  AC-test \n" });
    expect(twilioConfig()).toEqual({
      accountSid: "AC-test",
      authToken: "token-test",
      voiceFrom: "+15550001111",
      smsFrom: "+15550001111",
    });
  });

  it("TWILIO_SMS_FROM overrides the SMS sender only", () => {
    setEnv({ ...configured, TWILIO_SMS_FROM: "Lantern" });
    expect(twilioConfig()).toMatchObject({ voiceFrom: "+15550001111", smsFrom: "Lantern" });
  });

  it("treats unset, empty and \"disabled\" as not configured", () => {
    setEnv({ TWILIO_ACCOUNT_SID: "disabled", TWILIO_AUTH_TOKEN: "", TWILIO_SMS_FROM: "  " });
    expect(twilioConfig()).toEqual({});
    expect(missingTwilioParams("voice")).toEqual(["TWILIO_ACCOUNT_SID", "TWILIO_AUTH_TOKEN", "TWILIO_FROM_NUMBER"]);
    expect(missingTwilioParams("sms")).toEqual([
      "TWILIO_ACCOUNT_SID", "TWILIO_AUTH_TOKEN", "TWILIO_SMS_FROM or TWILIO_FROM_NUMBER",
    ]);
  });

  it("an SMS-only sender is enough for SMS but not for calls", () => {
    setEnv({ ...configured, TWILIO_FROM_NUMBER: "", TWILIO_SMS_FROM: "+15550002222" });
    expect(missingTwilioParams("sms")).toEqual([]);
    expect(missingTwilioParams("voice")).toEqual(["TWILIO_FROM_NUMBER"]);
  });

  it("GOOGLE_MAPS_API_KEY", () => {
    expect(googleMapsApiKey()).toBeUndefined();
    setEnv({ GOOGLE_MAPS_API_KEY: "maps-key" });
    expect(googleMapsApiKey()).toBe("maps-key");
    setEnv({ GOOGLE_MAPS_API_KEY: "DISABLED" });
    expect(googleMapsApiKey()).toBeUndefined();
  });
});

describe("missing configuration is reported once", () => {
  it("reportMissingConfig logs one error per feature", () => {
    reportMissingConfig("SMS", ["TWILIO_AUTH_TOKEN"], "Push only.");
    reportMissingConfig("SMS", ["TWILIO_AUTH_TOKEN"], "Push only.");
    reportMissingConfig("Nothing missing", [], "");
    expect(errorSpy).toHaveBeenCalledTimes(1);
    expect(errorSpy.mock.calls[0][0]).toContain("TWILIO_AUTH_TOKEN");
    expect(errorSpy.mock.calls[0][0]).toContain("docs/ops/SECRETS.md");
  });

  it("SMS: returns false (caller falls back to push) and logs once across sends", async () => {
    expect(await sendSOSSms("g1", "Mom", "sos1")).toBe(false);
    expect(await sendEmergencyContactSms("+8613800000009", "Mom", "zh")).toBe(false);
    const smsErrors = errorSpy.mock.calls.filter((c) => String(c[0]).includes("SMS disabled"));
    expect(smsErrors).toHaveLength(1);
    expect(smsErrors[0][0]).toContain("TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_SMS_FROM or TWILIO_FROM_NUMBER");
  });

  it("voice: returns null and logs once across calls", async () => {
    expect(await initiateVoiceCall("g1", "sos1", "Mom")).toBeNull();
    expect(await initiateVoiceCall("g1", "sos1", "Mom")).toBeNull();
    const voiceErrors = errorSpy.mock.calls.filter((c) => String(c[0]).includes("voice calls disabled"));
    expect(voiceErrors).toHaveLength(1);
  });

  it("geocoding: returns null and logs once", async () => {
    expect(await reverseGeocode(30.6, 104.0)).toBeNull();
    expect(await reverseGeocode(30.6, 104.0)).toBeNull();
    const geoErrors = errorSpy.mock.calls.filter((c) => String(c[0]).includes("GOOGLE_MAPS_API_KEY"));
    expect(geoErrors).toHaveLength(1);
  });
});

describe("configured values reach Twilio", () => {
  it("SMS is sent from TWILIO_SMS_FROM (else TWILIO_FROM_NUMBER)", async () => {
    setEnv({ ...configured, TWILIO_SMS_FROM: "+15550002222" });
    const create = jest.fn(async () => ({ sid: "SM1" }));
    __setSmsClientForTests({ messages: { create } });
    expect(await sendSOSSms("g1", "Mom", "sos1")).toBe(true);
    expect(create).toHaveBeenCalledWith(expect.objectContaining({ from: "+15550002222", to: "+14165550101" }));
  });

  it("calls are placed from TWILIO_FROM_NUMBER", async () => {
    setEnv({ ...configured, TWILIO_SMS_FROM: "+15550002222" });
    const create = jest.fn(async () => ({ sid: "CA1" }));
    __setTwilioClientForTests({ calls: { create } });
    expect(await initiateVoiceCall("g1", "sos1", "Mom")).toBe("CA1");
    expect(create).toHaveBeenCalledWith(expect.objectContaining({ from: "+15550001111", to: "+14165550101" }));
  });

  it("webhook signatures are checked with TWILIO_AUTH_TOKEN", () => {
    setEnv(configured);
    process.env.PUBLIC_API_BASE_URL = "https://example.test/api";
    const params = { Digits: "1", CallSid: "CA1" };
    const data = "https://example.test/api/v1/voice-callback" + "CallSidCA1" + "Digits1";
    const sig = crypto.createHmac("sha1", "token-test").update(Buffer.from(data, "utf-8")).digest("base64");
    const prevEmulator = process.env.FUNCTIONS_EMULATOR;
    delete process.env.FUNCTIONS_EMULATOR;
    try {
      expect(verifyTwilioSignature(sig, "/v1/voice-callback", params)).toBe(true);
      setEnv({});
      expect(verifyTwilioSignature(sig, "/v1/voice-callback", params)).toBe(false);
    } finally {
      if (prevEmulator !== undefined) process.env.FUNCTIONS_EMULATOR = prevEmulator;
      delete process.env.PUBLIC_API_BASE_URL;
    }
  });
});

describe("secrets are bound to the functions that use them", () => {
  const secretNames = (fn: unknown) =>
    ((fn as { __endpoint?: { secretEnvironmentVariables?: { key: string }[] } }).__endpoint
      ?.secretEnvironmentVariables ?? []).map((s) => s.key).sort();

  it("onSOSCreated and advanceEscalations get the Twilio secrets", () => {
    const prev = process.env.GCLOUD_PROJECT;
    process.env.GCLOUD_PROJECT = "demo-test"; // firestore triggers resolve the database path
    try {
      const twilio = TWILIO_SECRETS.map((s) => s.name).sort();
      expect(secretNames(require("../triggers/onSOSCreated").onSOSCreated)).toEqual(twilio);
      expect(secretNames(require("../scheduled/escalationCheck").advanceEscalations)).toEqual(twilio);
    } finally {
      if (prev === undefined) delete process.env.GCLOUD_PROJECT;
      else process.env.GCLOUD_PROJECT = prev;
    }
  });

  it("api gets Twilio + Google Maps", () => {
    expect(secretNames(require("../index").api)).toEqual(API_SECRETS.map((s) => s.name).sort());
  });

  it("no source file reads functions.config() (Runtime Config shuts down March 2027)", () => {
    const offenders: string[] = [];
    const walk = (dir: string) => {
      for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        const p = path.join(dir, e.name);
        if (e.isDirectory()) {
          if (e.name !== "__tests__") walk(p);
        } else if (p.endsWith(".ts") && /functions\.config\(\)\./.test(fs.readFileSync(p, "utf8"))) {
          offenders.push(path.relative(path.join(__dirname, ".."), p));
        }
      }
    };
    walk(path.join(__dirname, ".."));
    expect(offenders).toEqual([]);
  });

  it("every module that can send SMS / place calls is only reachable from secret-bound functions", () => {
    // Scheduled functions without secrets must not import the Twilio services.
    const bound = new Set(["escalationCheck.ts"]);
    const dir = path.join(__dirname, "..", "scheduled");
    for (const f of fs.readdirSync(dir).filter((n) => n.endsWith(".ts") && !bound.has(n))) {
      const src = fs.readFileSync(path.join(dir, f), "utf8");
      expect({ f, usesTwilio: /services\/(sms|twilio|escalation|geocoding)"/.test(src) }).toEqual({ f, usesTwilio: false });
    }
  });
});
