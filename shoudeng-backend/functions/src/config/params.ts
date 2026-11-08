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
/** Sign in with Apple key (.p8 contents): revokes a person's Apple sign-in when they delete their account */
export const APPLE_SIWA_PRIVATE_KEY = defineSecret("APPLE_SIWA_PRIVATE_KEY");
/** Alipay app private key (RSA2): signs calls to Alipay for "Sign in with Alipay" */
export const ALIPAY_PRIVATE_KEY = defineSecret("ALIPAY_PRIVATE_KEY");

/** Twilio number (E.164) for SOS voice calls, and for SMS unless TWILIO_SMS_FROM is set. */
export const TWILIO_FROM_NUMBER = defineString("TWILIO_FROM_NUMBER", {
  description: "Twilio phone number in E.164 used for SOS voice calls (and SMS unless TWILIO_SMS_FROM is set)",
});
/** Optional SMS sender (number or alphanumeric sender ID); empty = TWILIO_FROM_NUMBER. */
export const TWILIO_SMS_FROM = defineString("TWILIO_SMS_FROM", {
  description: "Optional SMS sender; leave empty to use TWILIO_FROM_NUMBER",
});

/** Key ID of APPLE_SIWA_PRIVATE_KEY (Apple Developer → Keys) */
export const APPLE_SIWA_KEY_ID = defineString("APPLE_SIWA_KEY_ID", {
  description: "Key ID of the Sign in with Apple key (Apple Developer → Certificates, IDs & Profiles → Keys)",
});
/** Apple Developer team that owns the app (default: the current team) */
export const APPLE_TEAM_ID = defineString("APPLE_TEAM_ID", {
  description: "Apple Developer Team ID; empty = B98QT5LTWZ",
});
/** Alipay Open Platform app id (支付宝开放平台 → 应用 → APPID) */
export const ALIPAY_APP_ID = defineString("ALIPAY_APP_ID", {
  description: "Alipay Open Platform APPID for Sign in with Alipay; empty = Alipay sign-in off",
});
/** Alipay's public key (支付宝公钥, RSA2) for checking Alipay's answers */
export const ALIPAY_PUBLIC_KEY = defineString("ALIPAY_PUBLIC_KEY", {
  description: "Alipay public key (支付宝公钥), base64 or PEM",
});
/** Where Alipay sends people back after they agree (registered as 授权回调地址); empty = this API's callback */
export const ALIPAY_REDIRECT_URI = defineString("ALIPAY_REDIRECT_URI", {
  description: "Alipay authorization callback URL; empty = https://us-central1-sweethome-b4e82.cloudfunctions.net/api/v1/auth/alipay/callback",
});

/** Bind to every function that sends SMS / places calls / verifies Twilio webhooks. */
export const TWILIO_SECRETS = [TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN];
/** The `api` function also reverse-geocodes and signs people in with Apple and Alipay. */
export const API_SECRETS = [...TWILIO_SECRETS, GOOGLE_MAPS_API_KEY, APPLE_SIWA_PRIVATE_KEY, ALIPAY_PRIVATE_KEY];

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

export interface AppleSignInConfig {
  teamId: string;
  keyId?: string;
  privateKey?: string;
}

export function appleSignInConfig(): AppleSignInConfig {
  return {
    teamId: read(APPLE_TEAM_ID) ?? "B98QT5LTWZ",
    keyId: read(APPLE_SIWA_KEY_ID),
    privateKey: read(APPLE_SIWA_PRIVATE_KEY),
  };
}

export interface AlipayConfig {
  appId?: string;
  privateKey?: string;
  alipayPublicKey?: string;
  redirectUri: string;
}

export const DEFAULT_ALIPAY_REDIRECT_URI =
  "https://us-central1-sweethome-b4e82.cloudfunctions.net/api/v1/auth/alipay/callback";

export function alipayConfig(): AlipayConfig {
  return {
    appId: read(ALIPAY_APP_ID),
    privateKey: read(ALIPAY_PRIVATE_KEY),
    alipayPublicKey: read(ALIPAY_PUBLIC_KEY),
    redirectUri: read(ALIPAY_REDIRECT_URI) ?? DEFAULT_ALIPAY_REDIRECT_URI,
  };
}

/** Names of the Alipay params still missing ([] = Sign in with Alipay is on). */
export function missingAlipayParams(cfg = alipayConfig()): string[] {
  const missing: string[] = [];
  if (!cfg.appId) missing.push(ALIPAY_APP_ID.name);
  if (!cfg.privateKey) missing.push(ALIPAY_PRIVATE_KEY.name);
  if (!cfg.alipayPublicKey) missing.push(ALIPAY_PUBLIC_KEY.name);
  return missing;
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
