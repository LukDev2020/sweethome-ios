/**
 * Apple Push Notification service, HTTP/2 provider API with token (JWT) auth.
 *
 * The iOS app registers its raw APNs device token (hex) with POST /v1/device/token;
 * it does not use Firebase Messaging, so FCM can't deliver to it. We talk to Apple
 * directly. APNs is reachable from mainland China, FCM isn't.
 *
 * Config (docs/ops/SECRETS.md): APNS_AUTH_KEY secret (.p8), APNS_KEY_ID, APPLE_TEAM_ID.
 * Apple's reference: "Sending notification requests to APNs" and
 * "Establishing a token-based connection to APNs".
 *
 * Pure transport: no Firestore here. services/push.ts looks up device tokens,
 * builds payloads and deletes tokens Apple reports as dead.
 */
import * as http2 from "http2";
import * as jwt from "jsonwebtoken";
import { apnsConfig, missingApnsParams, reportMissingConfig, ApnsConfig } from "../config/params";

export type ApnsEnvironment = "production" | "sandbox";

export const APNS_HOSTS: Readonly<Record<ApnsEnvironment, string>> = {
  production: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com",
};

/**
 * The app stores "development" (Xcode debug builds) or "production" (TestFlight,
 * App Store). Anything else, including no value, is production.
 */
export function apnsEnvironment(stored: unknown): ApnsEnvironment {
  return stored === "development" || stored === "sandbox" ? "sandbox" : "production";
}

export interface ApnsNotification {
  /** `{ aps: {...}, ...custom keys }`, sent as the JSON body */
  payload: Record<string, unknown>;
  pushType: "alert" | "background";
  priority: 10 | 5;
  /** Unix seconds until which APNs keeps retrying an offline device; 0 = try once */
  expiration: number;
}

export interface ApnsResult {
  ok: boolean;
  /** HTTP status from Apple; 0 = not sent (not configured, bad token, network error) */
  status: number;
  /** Apple's `reason` (e.g. "BadDeviceToken", "Unregistered") or a local reason */
  reason?: string;
  apnsId?: string;
  /** The environment that gave this answer (may differ from the stored one) */
  environment: ApnsEnvironment;
  /** Apple says this token will never work again: the caller should delete it */
  unregistered: boolean;
}

// ---------------------------------------------------------------------------
// Transport (HTTP/2, one long-lived connection per host, as Apple asks)
// ---------------------------------------------------------------------------

export interface ApnsTransportRequest {
  origin: string;
  path: string;
  headers: Record<string, string>;
  body: string;
}

export interface ApnsTransportResponse {
  status: number;
  headers: Record<string, string | undefined>;
  body: string;
}

export type ApnsTransport = (req: ApnsTransportRequest) => Promise<ApnsTransportResponse>;

const REQUEST_TIMEOUT_MS = 10_000;
const sessions = new Map<string, http2.ClientHttp2Session>();
let inFlight = 0;

function getSession(origin: string): http2.ClientHttp2Session {
  const existing = sessions.get(origin);
  if (existing && !existing.closed && !existing.destroyed) return existing;
  const session = http2.connect(origin);
  const forget = () => { if (sessions.get(origin) === session) sessions.delete(origin); };
  // Without an error listener a dropped connection would crash the instance.
  session.on("error", (err) => { console.warn(`[APNs] connection to ${origin} failed:`, err.message); forget(); });
  session.on("goaway", forget);
  session.on("close", forget);
  // Apple closes idle connections itself; an idle one must not keep the process alive.
  session.unref();
  sessions.set(origin, session);
  return session;
}

const http2Transport: ApnsTransport = (req) => new Promise((resolve, reject) => {
  let session: http2.ClientHttp2Session;
  try {
    session = getSession(req.origin);
  } catch (err) {
    reject(err);
    return;
  }
  inFlight++;
  session.ref();
  const done = () => {
    inFlight--;
    if (inFlight === 0) for (const s of sessions.values()) s.unref();
  };
  const stream = session.request({
    ":method": "POST",
    ":path": req.path,
    "content-type": "application/json",
    ...req.headers,
  });
  let status = 0;
  let headers: Record<string, string | undefined> = {};
  let body = "";
  let settled = false;
  const finish = (fn: () => void) => { if (!settled) { settled = true; done(); fn(); } };
  stream.setEncoding("utf8");
  stream.on("response", (h) => {
    status = Number(h[":status"]);
    headers = Object.fromEntries(Object.entries(h).map(([k, v]) => [k, Array.isArray(v) ? v.join(",") : v?.toString()]));
  });
  stream.on("data", (chunk: string) => { body += chunk; });
  stream.on("end", () => finish(() => resolve({ status, headers, body })));
  stream.on("error", (err) => finish(() => reject(err)));
  stream.setTimeout(REQUEST_TIMEOUT_MS, () => {
    stream.close(http2.constants.NGHTTP2_CANCEL);
    finish(() => reject(new Error(`APNs request timed out after ${REQUEST_TIMEOUT_MS} ms`)));
  });
  stream.end(req.body);
});

let transport: ApnsTransport = http2Transport;
let hosts: Record<ApnsEnvironment, string> = { ...APNS_HOSTS };

// ---------------------------------------------------------------------------
// Provider token (JWT, ES256). Apple: reuse for 20–60 minutes; refreshing more
// often than every 20 minutes gets TooManyProviderTokenUpdates.
// ---------------------------------------------------------------------------

const JWT_REUSE_SECONDS = 40 * 60;
let cachedJwt: { token: string; keyId: string; teamId: string; issuedAt: number } | null = null;

/** Accepts the .p8 file as-is, with literal "\n"s, or as the bare base64 body. */
export function normalizeP8(key: string): string {
  const k = key.replace(/\\n/g, "\n").trim();
  if (k.includes("-----BEGIN")) return k;
  const body = k.replace(/\s+/g, "");
  return `-----BEGIN PRIVATE KEY-----\n${body.match(/.{1,64}/g)?.join("\n") ?? body}\n-----END PRIVATE KEY-----`;
}

function providerToken(cfg: Required<Pick<ApnsConfig, "teamId" | "keyId" | "privateKey">>, force = false): string {
  const now = Math.floor(Date.now() / 1000);
  if (!force && cachedJwt && cachedJwt.keyId === cfg.keyId && cachedJwt.teamId === cfg.teamId &&
      now - cachedJwt.issuedAt < JWT_REUSE_SECONDS) {
    return cachedJwt.token;
  }
  // Apple needs iss + iat. (Don't pass noTimestamp: jsonwebtoken would drop our iat.)
  const token = jwt.sign({ iss: cfg.teamId, iat: now }, normalizeP8(cfg.privateKey), {
    algorithm: "ES256",
    keyid: cfg.keyId,
  });
  cachedJwt = { token, keyId: cfg.keyId, teamId: cfg.teamId, issuedAt: now };
  return token;
}

// ---------------------------------------------------------------------------
// Sending
// ---------------------------------------------------------------------------

/**
 * APNs device tokens are hex. Only path-safe characters may go into `:path`; a value
 * with anything else (an FCM token has ":") can never be delivered.
 */
const DEVICE_TOKEN = /^[0-9A-Za-z_-]{1,512}$/;

export function isSendableDeviceToken(token: unknown): token is string {
  return typeof token === "string" && DEVICE_TOKEN.test(token);
}

/** Apple's limit for alert and background pushes. */
export const APNS_MAX_PAYLOAD_BYTES = 4096;

async function attempt(
  cfg: Required<Pick<ApnsConfig, "teamId" | "keyId" | "privateKey" | "topic">>,
  deviceToken: string,
  environment: ApnsEnvironment,
  n: ApnsNotification,
  freshJwt = false
): Promise<ApnsResult> {
  const base: Pick<ApnsResult, "environment" | "unregistered"> = { environment, unregistered: false };
  let authorization: string;
  try {
    authorization = `bearer ${providerToken(cfg, freshJwt)}`;
  } catch (err) {
    // A malformed key: nothing will send until it's fixed.
    console.error("[APNs] could not sign the provider token (check APNS_AUTH_KEY / APNS_KEY_ID):", (err as Error).message);
    return { ...base, ok: false, status: 0, reason: "InvalidAuthKey" };
  }
  try {
    const res = await transport({
      origin: hosts[environment],
      path: `/3/device/${deviceToken}`,
      headers: {
        authorization,
        "apns-topic": cfg.topic,
        "apns-push-type": n.pushType,
        "apns-priority": String(n.priority),
        "apns-expiration": String(n.expiration),
      },
      body: JSON.stringify(n.payload),
    });
    let reason: string | undefined;
    if (res.status !== 200 && res.body) {
      try { reason = JSON.parse(res.body).reason; } catch { reason = res.body.slice(0, 200); }
    }
    return {
      ...base,
      ok: res.status === 200,
      status: res.status,
      reason,
      apnsId: res.headers["apns-id"],
      unregistered: res.status === 410 || reason === "Unregistered",
    };
  } catch (err) {
    return { ...base, ok: false, status: 0, reason: `NetworkError: ${(err as Error).message}` };
  }
}

const isTransient = (r: ApnsResult) =>
  (r.status === 0 && !!r.reason?.startsWith("NetworkError")) || r.status === 429 || r.status >= 500;

/**
 * Send one notification to one device. Never throws.
 *
 * - Expired provider token (403 ExpiredProviderToken): re-signs and retries once.
 * - Network error / 429 / 5xx: retries once.
 * - 400 BadDeviceToken: the token may belong to the other environment (a debug build
 *   marked production or the reverse), so the other host is tried once. The result
 *   says which environment answered, so the caller can correct the stored value.
 * - `unregistered` is true for 410 / Unregistered, and for BadDeviceToken from both hosts.
 */
export async function sendApns(
  deviceToken: string,
  environment: ApnsEnvironment,
  n: ApnsNotification
): Promise<ApnsResult> {
  const cfg = apnsConfig();
  const missing = missingApnsParams(cfg);
  if (missing.length > 0 || !cfg.keyId || !cfg.privateKey) {
    reportMissingConfig("Push notifications (APNs)", missing,
      "No push is sent; SOS reaches guardians by SMS and calls only.");
    return { ok: false, status: 0, reason: "NotConfigured", environment, unregistered: false };
  }
  if (!isSendableDeviceToken(deviceToken)) {
    return { ok: false, status: 0, reason: "BadDeviceToken", environment, unregistered: true };
  }
  const full = { teamId: cfg.teamId, keyId: cfg.keyId, privateKey: cfg.privateKey, topic: cfg.topic };

  let r = await attempt(full, deviceToken, environment, n);
  if (r.status === 403 && r.reason === "ExpiredProviderToken") {
    r = await attempt(full, deviceToken, environment, n, true);
  }
  if (isTransient(r)) {
    r = await attempt(full, deviceToken, environment, n);
  }
  if (r.status === 400 && r.reason === "BadDeviceToken") {
    const other: ApnsEnvironment = environment === "production" ? "sandbox" : "production";
    const alt = await attempt(full, deviceToken, other, n);
    if (alt.ok) return alt;
    const deadThere = alt.unregistered || (alt.status === 400 && alt.reason === "BadDeviceToken");
    return { ...r, unregistered: deadThere };
  }
  return r;
}

// ---------------------------------------------------------------------------
// Tests only
// ---------------------------------------------------------------------------

export function __setApnsTransportForTests(t: ApnsTransport | null): void {
  transport = t ?? http2Transport;
}

export function __setApnsHostsForTests(h: Partial<Record<ApnsEnvironment, string>> | null): void {
  hosts = { ...APNS_HOSTS, ...(h ?? {}) };
}

export function __resetApnsForTests(): void {
  cachedJwt = null;
  closeApnsSessions();
}

/** Close the HTTP/2 connections (tests; graceful shutdown). */
export function closeApnsSessions(): void {
  for (const s of sessions.values()) s.close();
  sessions.clear();
}
