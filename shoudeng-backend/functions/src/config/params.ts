/**
 * Runtime configuration (firebase-functions params). Replaces functions.config(),
 * which Google shuts down in March 2027. Owner setup: docs/ops/SECRETS.md.
 *
 * Secrets live in Cloud Secret Manager and are only visible to functions that list
 * them in runWith({ secrets }). Plain values come from functions/.env.
 *
 * Unset (or the value "disabled") never throws: SMS / voice calls / geocoding are
 * skipped, one clear error is logged per instance, and SOS still goes out by push.
 */
import { defineSecret, defineString } from "firebase-functions/params";

export const TWILIO_ACCOUNT_SID = defineSecret("TWILIO_ACCOUNT_SID");
export const TWILIO_AUTH_TOKEN = defineSecret("TWILIO_AUTH_TOKEN");
export const GOOGLE_MAPS_API_KEY = defineSecret("GOOGLE_MAPS_API_KEY");

/** Twilio number (E.164) for SOS voice calls, and for SMS unless TWILIO_SMS_FROM is set. */
export const TWILIO_FROM_NUMBER = defineString("TWILIO_FROM_NUMBER", {
  description: "Twilio phone number in E.164 used for SOS voice calls (and SMS unless TWILIO_SMS_FROM is set)",
});
/** Optional SMS sender (number or alphanumeric sender ID); empty = TWILIO_FROM_NUMBER. */
export const TWILIO_SMS_FROM = defineString("TWILIO_SMS_FROM", {
  description: "Optional SMS sender; leave empty to use TWILIO_FROM_NUMBER",
});

/** Bind to every function that sends SMS / places calls / verifies Twilio webhooks. */
export const TWILIO_SECRETS = [TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN];
/** The `api` function also reverse-geocodes. */
export const API_SECRETS = [...TWILIO_SECRETS, GOOGLE_MAPS_API_KEY];

type Param = { name: string; value(): string };

/** Trimmed value, or undefined when unset, empty or "disabled". */
function read(param: Param): string | undefined {
  // An unbound/unset secret makes value() warn on every call; we log once ourselves.
  if (process.env[param.name] === undefined) return undefined;
  const v = param.value().trim();
  return v === "" || v.toLowerCase() === "disabled" ? undefined : v;
}

export interface TwilioConfig {
  accountSid?: string;
  authToken?: string;
  /** Caller ID for voice calls. */
  voiceFrom?: string;
  /** Sender for SMS (TWILIO_SMS_FROM, else TWILIO_FROM_NUMBER). */
  smsFrom?: string;
}

export function twilioConfig(): TwilioConfig {
  const voiceFrom = read(TWILIO_FROM_NUMBER);
  return {
    accountSid: read(TWILIO_ACCOUNT_SID),
    authToken: read(TWILIO_AUTH_TOKEN),
    voiceFrom,
    smsFrom: read(TWILIO_SMS_FROM) ?? voiceFrom,
  };
}

/** Names of the params a channel still needs ([] = ready). */
export function missingTwilioParams(channel: "sms" | "voice", cfg = twilioConfig()): string[] {
  const missing: string[] = [];
  if (!cfg.accountSid) missing.push(TWILIO_ACCOUNT_SID.name);
  if (!cfg.authToken) missing.push(TWILIO_AUTH_TOKEN.name);
  if (!(channel === "sms" ? cfg.smsFrom : cfg.voiceFrom)) {
    missing.push(channel === "sms" ? `${TWILIO_SMS_FROM.name} or ${TWILIO_FROM_NUMBER.name}` : TWILIO_FROM_NUMBER.name);
  }
  return missing;
}

export function googleMapsApiKey(): string | undefined {
  return read(GOOGLE_MAPS_API_KEY);
}

const reported = new Set<string>();

/** Log a feature's missing configuration once per instance (not on every SOS). */
export function reportMissingConfig(feature: string, missing: string[], consequence: string): void {
  if (missing.length === 0 || reported.has(feature)) return;
  reported.add(feature);
  console.error(
    `[Config] ${feature} disabled — not configured: ${missing.join(", ")}. ${consequence} ` +
    "Setup: docs/ops/SECRETS.md"
  );
}

/** Tests only. */
export function __resetConfigReportsForTests(): void {
  reported.clear();
}
