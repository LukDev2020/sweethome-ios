/**
 * Sign in with Alipay (支付宝登录), with no Alipay SDK in the app.
 *
 *  1. POST /v1/auth/alipay/start → a one-time `state` (+ a secret only this phone
 *     knows) and Alipay's authorization page (publicAppAuthorize, scope auth_user).
 *     The app opens it in the Alipay app (alipays://…appId=20000067) or, without
 *     Alipay installed, in a web sign-in sheet.
 *  2. The person agrees; Alipay sends them to our callback with a one-time
 *     auth_code. The server exchanges it (alipay.system.oauth.token, RSA2-signed,
 *     answer checked against Alipay's public key) and remembers who it was.
 *  3. Back in the app, POST /v1/auth/alipay/complete with state + secret → signed in,
 *     or a signup token if this Alipay account has no Lantern Care account yet.
 *
 * Off until ALIPAY_APP_ID, ALIPAY_PRIVATE_KEY and ALIPAY_PUBLIC_KEY are set
 * (GET /v1/auth/providers tells the app whether to show the button).
 */
import * as admin from "firebase-admin";
import { createHash, createPrivateKey, createPublicKey, createSign, createVerify, randomBytes, KeyObject } from "crypto";
import { Timestamp } from "firebase-admin/firestore";
import { alipayConfig, missingAlipayParams, reportMissingConfig } from "../config/params";

export const ALIPAY_LOGINS = "alipay_logins";
const GATEWAY = "https://openapi.alipay.com/gateway.do";
const AUTHORIZE_URL = "https://openauth.alipay.com/oauth2/publicAppAuthorize.htm";
const LOGIN_TTL_MS = 10 * 60 * 1000;

export class AlipayError extends Error {
  constructor(message: string, public readonly retryable = false) {
    super(message);
    this.name = "AlipayError";
  }
}

type HttpPost = (url: string, form: Record<string, string>) => Promise<string>;
let httpPost: HttpPost = async (url, form) => {
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded;charset=utf-8" },
    body: new URLSearchParams(form).toString(),
  });
  if (!res.ok) throw new AlipayError(`Alipay HTTP ${res.status}`, true);
  return res.text();
};

/** Tests: Alipay's gateway without the network. */
export function __setAlipayTransportForTests(post: HttpPost): void {
  httpPost = post;
}

export function alipayEnabled(): boolean {
  const missing = missingAlipayParams();
  reportMissingConfig("Sign in with Alipay", missing, "The Alipay button stays hidden.");
  return missing.length === 0;
}

// MARK: - Keys and signatures (RSA2 = SHA256withRSA)

function wrapPem(raw: string, label: string): string {
  const body = raw.replace(/-----[^-]+-----/g, "").replace(/\\n/g, "").replace(/\s+/g, "");
  return `-----BEGIN ${label}-----\n${body.match(/.{1,64}/g)?.join("\n") ?? ""}\n-----END ${label}-----\n`;
}

/** Alipay's key tool gives bare base64: PKCS#8 (Java) or PKCS#1 (other languages). */
export function parsePrivateKey(raw: string): KeyObject {
  if (raw.includes("-----BEGIN")) return createPrivateKey(raw.replace(/\\n/g, "\n"));
  try {
    return createPrivateKey(wrapPem(raw, "PRIVATE KEY"));
  } catch {
    return createPrivateKey(wrapPem(raw, "RSA PRIVATE KEY"));
  }
}

export function parsePublicKey(raw: string): KeyObject {
  return createPublicKey(raw.includes("-----BEGIN") ? raw.replace(/\\n/g, "\n") : wrapPem(raw, "PUBLIC KEY"));
}

/** Alipay's signing string: every non-empty parameter except sign, sorted, k=v joined by & */
export function signingString(params: Record<string, string>): string {
  return Object.keys(params)
    .filter((k) => k !== "sign" && params[k] !== undefined && params[k] !== "")
    .sort()
    .map((k) => `${k}=${params[k]}`)
    .join("&");
}

export function rsa2Sign(content: string, key: KeyObject): string {
  return createSign("RSA-SHA256").update(content, "utf8").sign(key, "base64");
}

export function rsa2Verify(content: string, signature: string, key: KeyObject): boolean {
  try {
    return createVerify("RSA-SHA256").update(content, "utf8").verify(key, signature, "base64");
  } catch {
    return false;
  }
}

/**
 * The exact JSON text of `node` in Alipay's answer: Alipay signs those bytes, so
 * they're cut out of the raw body rather than re-serialized.
 */
export function rawJsonNode(body: string, node: string): string | null {
  const at = body.indexOf(`"${node}"`);
  if (at < 0) return null;
  const start = body.indexOf("{", at + node.length + 2);
  if (start < 0) return null;
  let depth = 0;
  let inString = false;
  for (let i = start; i < body.length; i++) {
    const c = body[i];
    if (inString) {
      if (c === "\\") i++;
      else if (c === "\"") inString = false;
    } else if (c === "\"") inString = true;
    else if (c === "{") depth++;
    else if (c === "}" && --depth === 0) return body.slice(start, i + 1);
  }
  return null;
}

/** Beijing time, as Alipay's gateway wants it: yyyy-MM-dd HH:mm:ss */
export function alipayTimestamp(now = new Date()): string {
  const t = new Date(now.getTime() + 8 * 3600 * 1000).toISOString();
  return `${t.slice(0, 10)} ${t.slice(11, 19)}`;
}

/** One signed call to Alipay's gateway; returns the verified response node. */
async function callGateway(method: string, bizParams: Record<string, string>): Promise<Record<string, unknown>> {
  const cfg = alipayConfig();
  if (!cfg.appId || !cfg.privateKey || !cfg.alipayPublicKey) throw new AlipayError("Alipay not configured");
  const params: Record<string, string> = {
    app_id: cfg.appId,
    method,
    format: "JSON",
    charset: "utf-8",
    sign_type: "RSA2",
    timestamp: alipayTimestamp(),
    version: "1.0",
    ...bizParams,
  };
  params.sign = rsa2Sign(signingString(params), parsePrivateKey(cfg.privateKey));
  const body = await httpPost(GATEWAY, params);

  const nodeName = `${method.replace(/\./g, "_")}_response`;
  const parsed = JSON.parse(body) as Record<string, unknown>;
  const raw = rawJsonNode(body, nodeName) ?? rawJsonNode(body, "error_response");
  const sign = typeof parsed.sign === "string" ? parsed.sign : "";
  if (!raw || !sign || !rsa2Verify(raw, sign, parsePublicKey(cfg.alipayPublicKey))) {
    throw new AlipayError(`${method}: answer not signed by Alipay`);
  }
  const node = (parsed[nodeName] ?? parsed.error_response) as Record<string, unknown>;
  if (parsed.error_response || (node.code !== undefined && node.code !== "10000")) {
    throw new AlipayError(`${method}: ${node.sub_code ?? node.code} ${node.sub_msg ?? node.msg ?? ""}`.trim());
  }
  return node;
}

export interface AlipayUser {
  /** open_id (apps created since 2023) or user_id (2088…, older apps) */
  subject: string;
  nickName?: string;
}

/** auth_code → the Alipay account it belongs to (+ nickname when Alipay shares it) */
export async function exchangeAlipayAuthCode(authCode: string): Promise<AlipayUser> {
  const token = await callGateway("alipay.system.oauth.token", { grant_type: "authorization_code", code: authCode });
  const openId = typeof token.open_id === "string" ? token.open_id : undefined;
  const userId = typeof token.user_id === "string" ? token.user_id : undefined;
  const subject = openId ? `oid:${openId}` : userId ? `uid:${userId}` : undefined;
  if (!subject) throw new AlipayError("Alipay returned no user id");
  let nickName: string | undefined;
  if (typeof token.access_token === "string") {
    try {
      const info = await callGateway("alipay.user.info.share", { auth_token: token.access_token });
      if (typeof info.nick_name === "string" && info.nick_name.trim()) nickName = info.nick_name.trim().slice(0, 40);
    } catch (error) {
      console.warn("[Alipay] user info unavailable:", (error as Error).message);
    }
  }
  return { subject, nickName };
}

// MARK: - The sign-in round trip

const hash = (s: string) => createHash("sha256").update(s).digest("hex");

export interface AlipayStart {
  state: string;
  secret: string;
  /** Alipay's authorization page (web sign-in sheet) */
  authUrl: string;
  /** The same page inside the Alipay app */
  alipayAppUrl: string;
}

export async function startAlipayLogin(): Promise<AlipayStart> {
  const cfg = alipayConfig();
  if (!cfg.appId) throw new AlipayError("Alipay not configured");
  const state = randomBytes(16).toString("hex");
  const secret = randomBytes(24).toString("hex");
  const now = Date.now();
  await admin.firestore().collection(ALIPAY_LOGINS).doc(state).set({
    secretHash: hash(secret),
    status: "pending",
    createdAt: Timestamp.fromMillis(now),
    expiresAt: Timestamp.fromMillis(now + LOGIN_TTL_MS),
  });
  const authUrl = `${AUTHORIZE_URL}?app_id=${encodeURIComponent(cfg.appId)}&scope=auth_user` +
    `&redirect_uri=${encodeURIComponent(cfg.redirectUri)}&state=${state}`;
  return {
    state,
    secret,
    authUrl,
    alipayAppUrl: `alipays://platformapi/startapp?appId=20000067&url=${encodeURIComponent(authUrl)}`,
  };
}

export type CallbackOutcome = "done" | "expired" | "failed";

/** Alipay's redirect: exchange the code and remember the account for the app. */
export async function handleAlipayCallback(state: unknown, authCode: unknown): Promise<CallbackOutcome> {
  if (typeof state !== "string" || !/^[0-9a-f]{32}$/.test(state)) return "expired";
  const ref = admin.firestore().collection(ALIPAY_LOGINS).doc(state);
  const snap = await ref.get();
  const data = snap.data();
  if (!snap.exists || data?.status !== "pending" || (data.expiresAt as Timestamp).toMillis() < Date.now()) {
    return "expired";
  }
  if (typeof authCode !== "string" || !authCode) {
    // The person declined on Alipay's page
    await ref.update({ status: "failed", reason: "declined" });
    return "failed";
  }
  try {
    const user = await exchangeAlipayAuthCode(authCode);
    await ref.update({ status: "done", subject: user.subject, nickName: user.nickName ?? null });
    return "done";
  } catch (error) {
    console.error("[Alipay] code exchange failed:", (error as Error).message);
    await ref.update({ status: "failed", reason: "exchange" });
    return "failed";
  }
}

export type CompleteResult =
  | { status: "pending" }
  | { status: "failed"; reason: string }
  | { status: "done"; user: AlipayUser };

/** The app collects the result once (state + the secret only it knows). */
export async function completeAlipayLogin(state: unknown, secret: unknown): Promise<CompleteResult | null> {
  if (typeof state !== "string" || typeof secret !== "string" || !/^[0-9a-f]{32}$/.test(state)) return null;
  const db = admin.firestore();
  const ref = db.collection(ALIPAY_LOGINS).doc(state);
  return db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    const data = snap.data();
    if (!snap.exists || data?.secretHash !== hash(secret)) return null;
    if ((data.expiresAt as Timestamp).toMillis() < Date.now()) {
      t.delete(ref);
      return { status: "failed", reason: "expired" } as CompleteResult;
    }
    if (data.status === "pending") return { status: "pending" } as CompleteResult;
    t.delete(ref);
    if (data.status === "failed") return { status: "failed", reason: String(data.reason ?? "failed") } as CompleteResult;
    return { status: "done", user: { subject: data.subject, nickName: data.nickName ?? undefined } } as CompleteResult;
  });
}

/** The page Alipay shows after the callback: back to the app */
export function callbackPage(outcome: CallbackOutcome, state: string): string {
  const back = `shoudeng://auth/alipay?state=${encodeURIComponent(state)}`;
  const text = {
    done: ["已确认", "请返回守灯完成登录。", "Confirmed — return to Lantern Care to finish signing in."],
    failed: ["未完成", "支付宝没有确认此次登录，请返回守灯重试。", "Alipay didn't confirm this sign-in. Return to Lantern Care and try again."],
    expired: ["已过期", "此次登录已过期，请返回守灯重新开始。", "This sign-in has expired. Return to Lantern Care and start again."],
  }[outcome];
  return `<!doctype html><html lang="zh"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>守灯 Lantern Care</title>
<style>body{font-family:-apple-system,system-ui,sans-serif;background:#FBF8F1;color:#0E2B4A;text-align:center;padding:64px 24px}
h1{font-size:22px;color:#014581}p{font-size:15px;line-height:1.5;color:#0E2B4Acc}
a{display:inline-block;margin-top:24px;padding:14px 28px;border-radius:12px;background:#014581;color:#FCF2DA;text-decoration:none;font-size:16px}</style>
</head><body><h1>${text[0]}</h1><p>${text[1]}<br>${text[2]}</p>
<a href="${back}">返回守灯 · Back to Lantern Care</a>
<script>setTimeout(function(){location.href=${JSON.stringify(back)}},300)</script></body></html>`;
}
