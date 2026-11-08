/**
 * Sign in with Apple, checked on our server (no Firebase on the phone).
 *
 *  - verifyAppleIdentityToken: Apple's signed identity token (RS256, Apple's published
 *    keys), issued by Apple for this app, not expired, and carrying the nonce this
 *    sign-in started with (sha256 of the raw nonce the phone sends).
 *  - Account deletion must revoke the person's Apple sign-in (App Review 5.1.1(v)):
 *    at sign-in the one-time authorization code is exchanged for a refresh token
 *    (kept server-side in apple_tokens), which is revoked when the account is deleted.
 *    Both need the Sign in with Apple key (APPLE_SIWA_KEY_ID + APPLE_SIWA_PRIVATE_KEY);
 *    without it, sign-in still works and the missing key is logged once.
 */
import * as admin from "firebase-admin";
import { createHash, createPublicKey } from "crypto";
import { Timestamp } from "firebase-admin/firestore";
import jwt from "jsonwebtoken";
import { appleSignInConfig, reportMissingConfig } from "../config/params";
import { APPLE_BUNDLE_ID } from "./payment";
import { identityDocId } from "./identity";

const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys";
const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";
const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";
const KEYS_TTL_MS = 60 * 60 * 1000;
export const APPLE_TOKENS = "apple_tokens";

export class AppleSignInError extends Error {
  constructor(message: string, public readonly retryable = false) {
    super(message);
    this.name = "AppleSignInError";
  }
}

export interface AppleIdentity {
  sub: string;
  email?: string;
  emailVerified: boolean;
  /** A private relay address (…@privaterelay.appleid.com) */
  privateEmail: boolean;
}

type AppleJWK = { kty: string; kid?: string; alg?: string; n?: string; e?: string; use?: string };
type HttpPost = (url: string, form: Record<string, string>) => Promise<{ status: number; body: unknown }>;

let fetchKeys: () => Promise<AppleJWK[]> = async () => {
  const res = await fetch(APPLE_KEYS_URL);
  if (!res.ok) throw new AppleSignInError(`Apple keys HTTP ${res.status}`, true);
  const body = await res.json() as { keys?: AppleJWK[] };
  return body.keys ?? [];
};

let httpPost: HttpPost = async (url, form) => {
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(form).toString(),
  });
  const text = await res.text();
  let body: unknown = text;
  try { body = JSON.parse(text); } catch { /* revoke answers with an empty body */ }
  return { status: res.status, body };
};

let keyCache: { keys: AppleJWK[]; at: number } | null = null;

/** Tests: Apple's key set and HTTP calls without the network. */
export function __setAppleTransportForTests(keys: () => Promise<AppleJWK[]>, post?: HttpPost): void {
  fetchKeys = keys;
  if (post) httpPost = post;
  keyCache = null;
}

async function appleKey(kid: string): Promise<AppleJWK> {
  const fresh = keyCache && Date.now() - keyCache.at < KEYS_TTL_MS;
  let key = fresh ? keyCache!.keys.find((k) => k.kid === kid) : undefined;
  if (!key) {
    // Unknown kid: Apple may have rotated its keys, fetch once more
    try {
      keyCache = { keys: await fetchKeys(), at: Date.now() };
    } catch (error) {
      throw error instanceof AppleSignInError ? error : new AppleSignInError("Apple keys unavailable", true);
    }
    key = keyCache.keys.find((k) => k.kid === kid);
  }
  if (!key) throw new AppleSignInError("Unknown Apple signing key");
  return key;
}

export const sha256Hex = (s: string) => createHash("sha256").update(s).digest("hex");

export async function verifyAppleIdentityToken(identityToken: string, rawNonce: string): Promise<AppleIdentity> {
  const decoded = jwt.decode(identityToken, { complete: true });
  if (!decoded || typeof decoded === "string" || !decoded.header.kid) {
    throw new AppleSignInError("Malformed identity token");
  }
  const jwk = await appleKey(decoded.header.kid);
  let payload: jwt.JwtPayload;
  try {
    payload = jwt.verify(identityToken, createPublicKey({ key: jwk, format: "jwk" }), {
      algorithms: ["RS256"],
      issuer: APPLE_ISSUER,
      audience: APPLE_BUNDLE_ID,
    }) as jwt.JwtPayload;
  } catch (error) {
    throw new AppleSignInError(`Identity token rejected: ${(error as Error).message}`);
  }
  // The nonce ties the token to the sign-in this phone started (no replays)
  if (!rawNonce || payload.nonce !== sha256Hex(rawNonce)) {
    throw new AppleSignInError("Nonce mismatch");
  }
  if (typeof payload.sub !== "string" || !payload.sub) throw new AppleSignInError("No subject");
  const flag = (v: unknown) => v === true || v === "true";
  return {
    sub: payload.sub,
    email: typeof payload.email === "string" ? payload.email : undefined,
    emailVerified: flag(payload.email_verified),
    privateEmail: flag(payload.is_private_email),
  };
}

// MARK: - Token revocation (account deletion)

function clientSecret(): string | null {
  const cfg = appleSignInConfig();
  if (!cfg.keyId || !cfg.privateKey) {
    reportMissingConfig("Apple sign-in revocation",
      [cfg.keyId ? "" : "APPLE_SIWA_KEY_ID", cfg.privateKey ? "" : "APPLE_SIWA_PRIVATE_KEY"].filter(Boolean),
      "Deleting an account can't revoke its Sign in with Apple (App Review requires it).");
    return null;
  }
  const key = cfg.privateKey.replace(/\\n/g, "\n");
  return jwt.sign({}, key, {
    algorithm: "ES256",
    keyid: cfg.keyId,
    issuer: cfg.teamId,
    subject: APPLE_BUNDLE_ID,
    audience: APPLE_ISSUER,
    expiresIn: "5m",
  });
}

/**
 * The one-time authorization code from this sign-in → a refresh token kept for
 * revocation. Best effort: a failure here never blocks the sign-in.
 */
export async function keepAppleRefreshToken(sub: string, authorizationCode: unknown): Promise<boolean> {
  if (typeof authorizationCode !== "string" || !authorizationCode) return false;
  let secret: string | null;
  try {
    secret = clientSecret();
  } catch (error) {
    console.error("[Apple] client secret could not be signed (check APPLE_SIWA_PRIVATE_KEY):", (error as Error).message);
    return false;
  }
  if (!secret) return false;
  try {
    const { status, body } = await httpPost(APPLE_TOKEN_URL, {
      client_id: APPLE_BUNDLE_ID,
      client_secret: secret,
      code: authorizationCode,
      grant_type: "authorization_code",
    });
    const refreshToken = (body as { refresh_token?: unknown })?.refresh_token;
    if (status !== 200 || typeof refreshToken !== "string") {
      console.warn(`[Apple] code exchange failed: HTTP ${status}`);
      return false;
    }
    await admin.firestore().collection(APPLE_TOKENS).doc(identityDocId("apple", sub))
      .set({ refreshToken, updatedAt: Timestamp.now() });
    return true;
  } catch (error) {
    console.warn("[Apple] code exchange error:", (error as Error).message);
    return false;
  }
}

/** Account deletion: revoke the Apple sign-in and forget the token. */
export async function revokeAppleSignIn(sub: string): Promise<boolean> {
  const ref = admin.firestore().collection(APPLE_TOKENS).doc(identityDocId("apple", sub));
  const snap = await ref.get();
  const refreshToken = snap.exists ? snap.data()?.refreshToken : undefined;
  let revoked = false;
  if (typeof refreshToken === "string") {
    try {
      const secret = clientSecret();
      if (secret) {
        const { status } = await httpPost(APPLE_REVOKE_URL, {
          client_id: APPLE_BUNDLE_ID,
          client_secret: secret,
          token: refreshToken,
          token_type_hint: "refresh_token",
        });
        revoked = status === 200;
        if (!revoked) console.warn(`[Apple] revoke failed: HTTP ${status}`);
      }
    } catch (error) {
      console.warn("[Apple] revoke error:", (error as Error).message);
    }
  }
  await ref.delete();
  return revoked;
}
