import { Router, Request, Response } from "express";
import { recordDataTransferConsent } from "../services/consent";
import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import jwt from "jsonwebtoken";
import { authMiddleware } from "../middleware/auth";
import { generateTokens, getJwtSecret, readSignupToken, signupTokenFor, VerifiedIdentity } from "../services/session";
import { identitiesOf, linkIdentity, LinkResult, userForIdentity, userForPhoneSignIn } from "../services/identity";
import { AppleSignInError, keepAppleRefreshToken, verifyAppleIdentityToken } from "../services/appleSignIn";
import {
  alipayEnabled, callbackPage, completeAlipayLogin, handleAlipayCallback, startAlipayLogin,
} from "../services/alipayAuth";

const router = Router();
const db = admin.firestore();

/**
 * Decode Firebase idToken. In emulator mode, decodes JWT payload directly
 * to accept tokens from any Firebase project (e.g. production iOS tokens).
 * In production, uses Firebase Admin SDK's full verification.
 */
async function decodeIdToken(
  idToken: string
): Promise<{ uid: string; phone: string }> {
  if (process.env.FUNCTIONS_EMULATOR === "true") {
    try {
      const payload = JSON.parse(
        Buffer.from(idToken.split(".")[1], "base64").toString()
      );
      return {
        uid: payload.user_id || payload.sub || payload.uid,
        phone: payload.phone_number || "",
      };
    } catch {
      throw new Error("Invalid token format");
    }
  }
  const decoded = await admin.auth().verifyIdToken(idToken);
  return { uid: decoded.uid, phone: decoded.phone_number || "" };
}

/**
 * Derive ISO country code from E.164 phone number prefix.
 */
function countryFromPhone(phone: string): string {
  const prefixes: Record<string, string> = {
    "+1": "US",
    "+7": "RU",
    "+20": "EG",
    "+27": "ZA",
    "+30": "GR",
    "+31": "NL",
    "+32": "BE",
    "+33": "FR",
    "+34": "ES",
    "+36": "HU",
    "+39": "IT",
    "+40": "RO",
    "+41": "CH",
    "+43": "AT",
    "+44": "GB",
    "+45": "DK",
    "+46": "SE",
    "+47": "NO",
    "+48": "PL",
    "+49": "DE",
    "+51": "PE",
    "+52": "MX",
    "+53": "CU",
    "+54": "AR",
    "+55": "BR",
    "+56": "CL",
    "+57": "CO",
    "+58": "VE",
    "+60": "MY",
    "+61": "AU",
    "+62": "ID",
    "+63": "PH",
    "+64": "NZ",
    "+65": "SG",
    "+66": "TH",
    "+81": "JP",
    "+82": "KR",
    "+84": "VN",
    "+86": "CN",
    "+90": "TR",
    "+91": "IN",
    "+92": "PK",
    "+93": "AF",
    "+94": "LK",
    "+95": "MM",
    "+98": "IR",
    "+212": "MA",
    "+213": "DZ",
    "+216": "TN",
    "+234": "NG",
    "+251": "ET",
    "+254": "KE",
    "+255": "TZ",
    "+351": "PT",
    "+352": "LU",
    "+353": "IE",
    "+354": "IS",
    "+358": "FI",
    "+359": "BG",
    "+370": "LT",
    "+371": "LV",
    "+372": "EE",
    "+380": "UA",
    "+381": "RS",
    "+385": "HR",
    "+386": "SI",
    "+420": "CZ",
    "+421": "SK",
    "+593": "EC",
    "+673": "BN",
    "+679": "FJ",
    "+852": "HK",
    "+853": "MO",
    "+855": "KH",
    "+856": "LA",
    "+880": "BD",
    "+886": "TW",
    "+961": "LB",
    "+962": "JO",
    "+964": "IQ",
    "+965": "KW",
    "+966": "SA",
    "+968": "OM",
    "+971": "AE",
    "+972": "IL",
    "+973": "BH",
    "+974": "QA",
    "+976": "MN",
    "+977": "NP",
  };

  // Try longest prefix first (4 digits, then 3, then 2, then 1)
  for (let len = 4; len >= 1; len--) {
    const prefix = phone.substring(0, len + 1); // +1 for the '+' sign
    if (prefixes[prefix]) return prefixes[prefix];
  }
  return "CN"; // fallback
}

/**
 * Map country code to a default timezone.
 */
function timezoneFromCountry(country: string): string {
  const map: Record<string, string> = {
    CN: "Asia/Shanghai",
    US: "America/New_York",
    GB: "Europe/London",
    JP: "Asia/Tokyo",
    KR: "Asia/Seoul",
    CA: "America/Toronto",
    AU: "Australia/Sydney",
    DE: "Europe/Berlin",
    FR: "Europe/Paris",
    IN: "Asia/Kolkata",
    SG: "Asia/Singapore",
    HK: "Asia/Hong_Kong",
    TW: "Asia/Taipei",
    MY: "Asia/Kuala_Lumpur",
    TH: "Asia/Bangkok",
    VN: "Asia/Ho_Chi_Minh",
    PH: "Asia/Manila",
    ID: "Asia/Jakarta",
    NZ: "Pacific/Auckland",
    IT: "Europe/Rome",
    ES: "Europe/Madrid",
    NL: "Europe/Amsterdam",
    SE: "Europe/Stockholm",
    CH: "Europe/Zurich",
    RU: "Europe/Moscow",
    BR: "America/Sao_Paulo",
    MX: "America/Mexico_City",
    AR: "America/Argentina/Buenos_Aires",
    ZA: "Africa/Johannesburg",
    NG: "Africa/Lagos",
    EG: "Africa/Cairo",
    KE: "Africa/Nairobi",
    TR: "Europe/Istanbul",
    SA: "Asia/Riyadh",
    AE: "Asia/Dubai",
    IL: "Asia/Jerusalem",
    PK: "Asia/Karachi",
    BD: "Asia/Dhaka",
  };
  return map[country] || "UTC";
}

/**
 * POST /v1/auth/send-code
 * Send verification code to phone number via Firebase Auth.
 * In production, Firebase Auth handles SMS delivery automatically.
 * This endpoint exists for the iOS client's flow compatibility.
 */
router.post("/send-code", async (req: Request, res: Response) => {
  const { phone } = req.body;

  if (!phone) {
    res.status(400).json({ error: "Phone number is required" });
    return;
  }

  try {
    res.json({ success: true, message: "Verification code sent" });
  } catch (error) {
    console.error("[Auth] send-code error:", error);
    res.status(500).json({ error: "Failed to send verification code" });
  }
});

/**
 * POST /v1/auth/login
 * Verify a Firebase phone ID token and return session JWT tokens.
 * `linkToken` (optional): an Apple / Alipay sign-in that found no account — the
 * person signed in with their phone instead, so connect it to this account.
 */
router.post("/login", async (req: Request, res: Response) => {
  const { idToken, linkToken } = req.body;

  if (!idToken) {
    res.status(400).json({ error: "ID token is required" });
    return;
  }

  try {
    const { uid: phoneUid } = await decodeIdToken(idToken);

    // An account created by phone, or an Apple / Alipay account this number was added to
    const uid = await userForPhoneSignIn(phoneUid);
    if (!uid) {
      res.status(404).json({ error: "User not found. Please sign up first." });
      return;
    }

    let linked: string | undefined;
    if (linkToken !== undefined) {
      const identity = readSignupToken(linkToken);
      if (!identity) {
        res.status(400).json({ error: "Sign-in to connect has expired. Try again.", code: "LINK_EXPIRED" });
        return;
      }
      const result = await linkVerifiedIdentity(uid, identity);
      if (result === "linkedElsewhere") {
        res.status(409).json(LINKED_ELSEWHERE);
        return;
      }
      linked = identity.provider;
    }

    const userData = (await db.collection("users").doc(uid).get()).data()!;
    const tokens = generateTokens(uid);

    res.json({
      ...tokens,
      userId: uid,
      displayName: userData.displayName,
      role: userData.role,
      ...(linked ? { linked } : {}),
    });
  } catch (error) {
    console.error("[Auth] login error:", error);
    res.status(401).json({ error: "Invalid credentials" });
  }
});

const LINKED_ELSEWHERE = {
  error: "This sign-in is already connected to another Beaconify account.",
  code: "IDENTITY_LINKED_ELSEWHERE",
};

async function linkVerifiedIdentity(uid: string, identity: VerifiedIdentity): Promise<LinkResult> {
  const result = await linkIdentity(uid, identity.provider, identity.subject,
    identity.email ? { email: identity.email } : {});
  if (result === "linked") {
    await db.collection("users").doc(uid).set({
      authProviders: admin.firestore.FieldValue.arrayUnion(identity.provider),
      updatedAt: Timestamp.now(),
    }, { merge: true });
  }
  return result;
}

/** An Apple / Alipay identity was verified: sign in, or hand back a signup token. */
async function signInWithIdentity(res: Response, identity: VerifiedIdentity): Promise<void> {
  const uid = await userForIdentity(identity.provider, identity.subject);
  const user = uid ? await db.collection("users").doc(uid).get() : null;
  if (uid && user?.exists) {
    const data = user.data()!;
    res.json({
      status: "signedIn",
      ...generateTokens(uid),
      userId: uid,
      displayName: data.displayName,
      role: data.role,
    });
    return;
  }
  res.json({
    status: "signupRequired",
    signupToken: signupTokenFor(identity),
    displayName: identity.name ?? null,
    email: identity.email ?? null,
  });
}

/**
 * GET /v1/auth/providers — which sign-in buttons the app shows.
 */
router.get("/providers", (_req: Request, res: Response) => {
  res.json({ phone: true, apple: true, alipay: alipayEnabled() });
});

/**
 * POST /v1/auth/apple
 * { identityToken, rawNonce, authorizationCode?, fullName? } from Sign in with Apple.
 */
router.post("/apple", async (req: Request, res: Response) => {
  const { identityToken, rawNonce, authorizationCode, fullName } = req.body;
  if (typeof identityToken !== "string" || typeof rawNonce !== "string") {
    res.status(400).json({ error: "identityToken and rawNonce are required" });
    return;
  }
  try {
    const apple = await verifyAppleIdentityToken(identityToken, rawNonce);
    // Kept for revoking this sign-in if the account is deleted (never blocks sign-in)
    await keepAppleRefreshToken(apple.sub, authorizationCode);
    const name = typeof fullName === "string" && fullName.trim() ? fullName.trim().slice(0, 40) : undefined;
    await signInWithIdentity(res, { provider: "apple", subject: apple.sub, email: apple.email, name });
  } catch (error) {
    if (error instanceof AppleSignInError) {
      console.warn("[Auth] Apple sign-in rejected:", error.message);
      res.status(error.retryable ? 503 : 401).json({ error: "Apple sign-in could not be verified", code: "APPLE_INVALID" });
      return;
    }
    console.error("[Auth] Apple sign-in error:", error);
    res.status(500).json({ error: "Apple sign-in failed" });
  }
});

/**
 * POST /v1/auth/alipay/start → { state, secret, authUrl, alipayAppUrl }
 */
router.post("/alipay/start", async (_req: Request, res: Response) => {
  if (!alipayEnabled()) {
    res.status(503).json({ error: "Alipay sign-in is not available", code: "ALIPAY_UNAVAILABLE" });
    return;
  }
  try {
    res.json(await startAlipayLogin());
  } catch (error) {
    console.error("[Auth] Alipay start error:", error);
    res.status(500).json({ error: "Alipay sign-in failed" });
  }
});

/**
 * GET /v1/auth/alipay/callback?auth_code&state — Alipay sends the person here.
 */
router.get("/alipay/callback", async (req: Request, res: Response) => {
  const state = typeof req.query.state === "string" ? req.query.state : "";
  let outcome: "done" | "expired" | "failed" = "failed";
  try {
    outcome = await handleAlipayCallback(state, req.query.auth_code);
  } catch (error) {
    console.error("[Auth] Alipay callback error:", error);
  }
  res.status(200).type("html").send(callbackPage(outcome, state));
});

/**
 * POST /v1/auth/alipay/complete { state, secret }
 * 202 while Alipay hasn't answered yet; then signed in or a signup token.
 */
router.post("/alipay/complete", async (req: Request, res: Response) => {
  try {
    const result = await completeAlipayLogin(req.body?.state, req.body?.secret);
    if (!result) {
      res.status(404).json({ error: "Unknown sign-in", code: "ALIPAY_UNKNOWN" });
      return;
    }
    if (result.status === "pending") {
      res.status(202).json({ status: "pending" });
      return;
    }
    if (result.status === "failed") {
      res.status(400).json({ error: "Alipay didn't confirm the sign-in", code: "ALIPAY_DENIED", reason: result.reason });
      return;
    }
    await signInWithIdentity(res, { provider: "alipay", subject: result.user.subject, name: result.user.nickName });
  } catch (error) {
    console.error("[Auth] Alipay complete error:", error);
    res.status(500).json({ error: "Alipay sign-in failed" });
  }
});

/**
 * GET /v1/auth/methods — this account's sign-in methods (Settings).
 */
router.get("/methods", authMiddleware, async (req: Request, res: Response) => {
  try {
    const uid = req.uid!;
    const [user, identities] = await Promise.all([db.collection("users").doc(uid).get(), identitiesOf(uid)]);
    const providers = new Set(identities.map((i) => i.provider));
    const phone = user.data()?.phone || null;
    res.json({ phone, apple: providers.has("apple"), alipay: providers.has("alipay") });
  } catch (error) {
    console.error("[Auth] methods error:", error);
    res.status(500).json({ error: "Failed to load sign-in methods" });
  }
});

/**
 * POST /v1/auth/link { signupToken } — connect Apple / Alipay to the signed-in account.
 */
router.post("/link", authMiddleware, async (req: Request, res: Response) => {
  const identity = readSignupToken(req.body?.signupToken);
  if (!identity) {
    res.status(400).json({ error: "Sign-in to connect has expired. Try again.", code: "LINK_EXPIRED" });
    return;
  }
  try {
    const result = await linkVerifiedIdentity(req.uid!, identity);
    if (result === "linkedElsewhere") {
      res.status(409).json(LINKED_ELSEWHERE);
      return;
    }
    res.json({ success: true, provider: identity.provider });
  } catch (error) {
    console.error("[Auth] link error:", error);
    res.status(500).json({ error: "Failed to connect sign-in" });
  }
});

/**
 * POST /v1/auth/link-phone { idToken } — add a verified phone number to an Apple /
 * Alipay account, so texts and calls reach this person and they can sign in by phone.
 */
router.post("/link-phone", authMiddleware, async (req: Request, res: Response) => {
  const { idToken } = req.body;
  if (!idToken) {
    res.status(400).json({ error: "ID token is required" });
    return;
  }
  const uid = req.uid!;
  try {
    const { uid: phoneUid, phone } = await decodeIdToken(idToken);
    if (!phone) {
      res.status(400).json({ error: "Not a phone sign-in" });
      return;
    }
    const owner = await userForPhoneSignIn(phoneUid);
    if (owner && owner !== uid) {
      res.status(409).json({
        error: "This number already has its own Beaconify account.",
        code: "PHONE_HAS_ACCOUNT",
      });
      return;
    }
    if (owner !== uid) {
      const result = await linkIdentity(uid, "phone", phoneUid, { phone });
      if (result === "linkedElsewhere") {
        res.status(409).json({ error: "This number is connected to another account.", code: "PHONE_HAS_ACCOUNT" });
        return;
      }
    }
    await db.collection("users").doc(uid).set({
      phone,
      authProviders: admin.firestore.FieldValue.arrayUnion("phone"),
      updatedAt: Timestamp.now(),
    }, { merge: true });
    res.json({ success: true, phone });
  } catch (error) {
    console.error("[Auth] link-phone error:", error);
    res.status(401).json({ error: "Invalid credentials" });
  }
});

/**
 * POST /v1/auth/signup
 * Create a new user account after phone verification.
 * Accepts optional countryCode from client for accurate geo assignment.
 */
router.post("/signup", async (req: Request, res: Response) => {
  const { idToken, signupToken, displayName, role, countryCode: clientCountryCode, email, dataTransferConsent } =
    req.body;

  if ((!idToken && !signupToken) || !displayName || !role) {
    res
      .status(400)
      .json({ error: "idToken (or signupToken), displayName, and role are required" });
    return;
  }

  if (!["protected", "guardian"].includes(role)) {
    res.status(400).json({ error: "Role must be 'protected' or 'guardian'" });
    return;
  }

  try {
    // Phone: the account id is the phone sign-in's Firebase uid (as before).
    // Apple / Alipay: a new id, and the verified identity is linked to it.
    let uid: string;
    let phone = "";
    let identity: VerifiedIdentity | null = null;
    if (signupToken) {
      identity = readSignupToken(signupToken);
      if (!identity) {
        res.status(400).json({ error: "Sign-in expired. Please start again.", code: "SIGNUP_EXPIRED" });
        return;
      }
      if (await userForIdentity(identity.provider, identity.subject)) {
        res.status(409).json({ error: "User already exists" });
        return;
      }
      uid = db.collection("users").doc().id;
    } else {
      const decoded = await decodeIdToken(idToken);
      uid = decoded.uid;
      phone = decoded.phone;
      // An account of its own, or a number already added to an Apple / Alipay account
      if (await userForPhoneSignIn(uid)) {
        res.status(409).json({ error: "User already exists" });
        return;
      }
    }

    const now = Timestamp.now();
    const avatarInitial = displayName.charAt(0);
    const detectedCountry = clientCountryCode || (phone ? countryFromPhone(phone) : "US");
    const detectedTimezone = timezoneFromCountry(detectedCountry);

    const userDoc: Record<string, unknown> = {
      displayName,
      phone,
      role,
      avatarInitial,
      timeZone: detectedTimezone,
      countryCode: detectedCountry,
      cityName: "",
      createdAt: now,
      updatedAt: now,
    };
    if (email && typeof email === "string" && email.includes("@")) {
      userDoc.email = email;
    } else if (identity?.email) {
      userDoc.email = identity.email;
    }
    userDoc.authProviders = [identity ? identity.provider : "phone"];
    // Explicit consent to storage and processing in the United States (shown at sign-up)
    const consentVersion = typeof dataTransferConsent === "string" ? dataTransferConsent.slice(0, 20) : null;
    if (consentVersion) {
      userDoc.dataTransferConsentVersion = consentVersion;
      userDoc.dataTransferConsentAt = now;
    }

    await db.collection("users").doc(uid).set(userDoc);
    if (identity) {
      const linked = await linkIdentity(uid, identity.provider, identity.subject,
        identity.email ? { email: identity.email } : {});
      if (linked === "linkedElsewhere") {
        // Two sign-ups raced with the same Apple / Alipay account: keep the first
        await db.collection("users").doc(uid).delete();
        res.status(409).json({ error: "User already exists" });
        return;
      }
    }

    if (consentVersion) {
      await recordDataTransferConsent(uid, consentVersion, "signup");
    }

    const tokens = generateTokens(uid);

    res.status(201).json({
      ...tokens,
      userId: uid,
      displayName,
      role,
    });
  } catch (error) {
    console.error("[Auth] signup error:", error);
    res.status(500).json({ error: "Failed to create account" });
  }
});

/**
 * POST /v1/auth/refresh
 * Verify refresh JWT and issue new access + refresh tokens.
 */
router.post("/refresh", async (req: Request, res: Response) => {
  const { refreshToken } = req.body;

  if (!refreshToken) {
    res.status(400).json({ error: "Refresh token is required" });
    return;
  }

  try {
    const payload = jwt.verify(refreshToken, getJwtSecret()) as {
      uid: string;
      type: string;
    };
    if (payload.type !== "refresh") {
      res.status(401).json({ error: "Invalid refresh token" });
      return;
    }
    // A deleted account's refresh token must not keep minting sessions
    const user = await db.collection("users").doc(payload.uid).get();
    if (!user.exists) {
      res.status(401).json({ error: "Account no longer exists" });
      return;
    }

    const tokens = generateTokens(payload.uid);
    res.json({
      ...tokens,
      userId: payload.uid,
    });
  } catch (error) {
    console.error("[Auth] refresh error:", error);
    res.status(401).json({ error: "Invalid or expired refresh token" });
  }
});

export default router;
