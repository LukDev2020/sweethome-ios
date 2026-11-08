/**
 * App session tokens (our own JWTs, not Firebase's). Every sign-in method — phone,
 * Apple, Alipay — ends here, so after sign-in nothing on the phone depends on Google.
 */
import jwt from "jsonwebtoken";

export function getJwtSecret(): string {
  const secret = process.env.JWT_SECRET;
  if (secret) return secret;
  const isDev = process.env.FUNCTIONS_EMULATOR === "true" || !!process.env.JEST_WORKER_ID;
  if (!isDev) {
    throw new Error("JWT_SECRET environment variable is required in production");
  }
  return "shoudeng-dev-jwt-secret-do-not-use-in-prod";
}

const ACCESS_TOKEN_EXPIRY = "1h";
const REFRESH_TOKEN_EXPIRY = "30d";
/** A verified Apple / Alipay identity with no account yet: time to fill in the profile */
const SIGNUP_TOKEN_EXPIRY = "30m";

export function generateTokens(uid: string): { accessToken: string; refreshToken: string } {
  const accessToken = jwt.sign({ uid, type: "access" }, getJwtSecret(), { expiresIn: ACCESS_TOKEN_EXPIRY });
  const refreshToken = jwt.sign({ uid, type: "refresh" }, getJwtSecret(), { expiresIn: REFRESH_TOKEN_EXPIRY });
  return { accessToken, refreshToken };
}

export type IdentityProvider = "apple" | "alipay";

/** What a signup token vouches for: this provider verified this subject. */
export interface VerifiedIdentity {
  provider: IdentityProvider;
  subject: string;
  email?: string;
  /** Name the provider gave (Apple: first sign-in only; Alipay: nickname) */
  name?: string;
}

/**
 * Signed proof that the server verified an identity. The phone holds it while the
 * person fills in the profile (signup), or signs in with their phone to connect it.
 */
export function signupTokenFor(identity: VerifiedIdentity): string {
  return jwt.sign({ type: "signup", ...identity }, getJwtSecret(), { expiresIn: SIGNUP_TOKEN_EXPIRY });
}

export function readSignupToken(token: unknown): VerifiedIdentity | null {
  if (typeof token !== "string" || token.length === 0) return null;
  try {
    const p = jwt.verify(token, getJwtSecret()) as Record<string, unknown>;
    if (p.type !== "signup" || (p.provider !== "apple" && p.provider !== "alipay") ||
        typeof p.subject !== "string" || !p.subject) return null;
    return {
      provider: p.provider,
      subject: p.subject,
      email: typeof p.email === "string" ? p.email : undefined,
      name: typeof p.name === "string" ? p.name : undefined,
    };
  } catch {
    return null;
  }
}
