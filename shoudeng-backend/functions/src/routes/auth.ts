import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import jwt from "jsonwebtoken";

const router = Router();
const db = admin.firestore();

const JWT_SECRET =
  process.env.JWT_SECRET || "shoudeng-dev-jwt-secret-do-not-use-in-prod";
const ACCESS_TOKEN_EXPIRY = "1h";
const REFRESH_TOKEN_EXPIRY = "30d";

/**
 * Generate JWT access and refresh tokens for a user.
 */
function generateTokens(uid: string): {
  accessToken: string;
  refreshToken: string;
} {
  const accessToken = jwt.sign({ uid, type: "access" }, JWT_SECRET, {
    expiresIn: ACCESS_TOKEN_EXPIRY,
  });
  const refreshToken = jwt.sign({ uid, type: "refresh" }, JWT_SECRET, {
    expiresIn: REFRESH_TOKEN_EXPIRY,
  });
  return { accessToken, refreshToken };
}

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
 * Verify Firebase ID token and return session JWT tokens.
 */
router.post("/login", async (req: Request, res: Response) => {
  const { idToken } = req.body;

  if (!idToken) {
    res.status(400).json({ error: "ID token is required" });
    return;
  }

  try {
    const { uid } = await decodeIdToken(idToken);

    // Check if user exists in Firestore
    const userDoc = await db.collection("users").doc(uid).get();
    if (!userDoc.exists) {
      res.status(404).json({ error: "User not found. Please sign up first." });
      return;
    }

    const userData = userDoc.data()!;
    const tokens = generateTokens(uid);

    res.json({
      ...tokens,
      userId: uid,
      displayName: userData.displayName,
      role: userData.role,
    });
  } catch (error) {
    console.error("[Auth] login error:", error);
    res.status(401).json({ error: "Invalid credentials" });
  }
});

/**
 * POST /v1/auth/signup
 * Create a new user account after phone verification.
 * Accepts optional countryCode from client for accurate geo assignment.
 */
router.post("/signup", async (req: Request, res: Response) => {
  const { idToken, displayName, role, countryCode: clientCountryCode } =
    req.body;

  if (!idToken || !displayName || !role) {
    res
      .status(400)
      .json({ error: "idToken, displayName, and role are required" });
    return;
  }

  if (!["protected", "guardian"].includes(role)) {
    res.status(400).json({ error: "Role must be 'protected' or 'guardian'" });
    return;
  }

  try {
    const { uid, phone } = await decodeIdToken(idToken);

    // Check if user already exists
    const existing = await db.collection("users").doc(uid).get();
    if (existing.exists) {
      res.status(409).json({ error: "User already exists" });
      return;
    }

    const now = Timestamp.now();
    const avatarInitial = displayName.charAt(0);
    const detectedCountry = clientCountryCode || countryFromPhone(phone);
    const detectedTimezone = timezoneFromCountry(detectedCountry);

    const userDoc = {
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

    await db.collection("users").doc(uid).set(userDoc);

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
    const payload = jwt.verify(refreshToken, JWT_SECRET) as {
      uid: string;
      type: string;
    };
    if (payload.type !== "refresh") {
      res.status(401).json({ error: "Invalid refresh token" });
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
