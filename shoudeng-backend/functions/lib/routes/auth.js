"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-admin/firestore");
const router = (0, express_1.Router)();
const db = admin.firestore();
/**
 * Decode Firebase idToken. In emulator mode, decodes JWT payload directly
 * to accept tokens from any Firebase project (e.g. production iOS tokens).
 * In production, uses Firebase Admin SDK's full verification.
 */
async function decodeIdToken(idToken) {
    if (process.env.FUNCTIONS_EMULATOR === "true") {
        // Emulator: decode JWT payload without signature verification
        // so we can accept production tokens from any Firebase project
        try {
            const payload = JSON.parse(Buffer.from(idToken.split(".")[1], "base64").toString());
            return {
                uid: payload.user_id || payload.sub || payload.uid,
                phone: payload.phone_number || "",
            };
        }
        catch {
            throw new Error("Invalid token format");
        }
    }
    // Production: full verification
    const decoded = await admin.auth().verifyIdToken(idToken);
    return { uid: decoded.uid, phone: decoded.phone_number || "" };
}
/**
 * Derive ISO country code from E.164 phone number prefix.
 */
function countryFromPhone(phone) {
    const prefixes = {
        "+1": "US", "+7": "RU", "+20": "EG", "+27": "ZA", "+30": "GR",
        "+31": "NL", "+32": "BE", "+33": "FR", "+34": "ES", "+36": "HU",
        "+39": "IT", "+40": "RO", "+41": "CH", "+43": "AT", "+44": "GB",
        "+45": "DK", "+46": "SE", "+47": "NO", "+48": "PL", "+49": "DE",
        "+51": "PE", "+52": "MX", "+53": "CU", "+54": "AR", "+55": "BR",
        "+56": "CL", "+57": "CO", "+58": "VE", "+60": "MY", "+61": "AU",
        "+62": "ID", "+63": "PH", "+64": "NZ", "+65": "SG", "+66": "TH",
        "+81": "JP", "+82": "KR", "+84": "VN", "+86": "CN", "+90": "TR",
        "+91": "IN", "+92": "PK", "+93": "AF", "+94": "LK", "+95": "MM",
        "+98": "IR", "+212": "MA", "+213": "DZ", "+216": "TN", "+234": "NG",
        "+251": "ET", "+254": "KE", "+255": "TZ", "+351": "PT", "+352": "LU",
        "+353": "IE", "+354": "IS", "+358": "FI", "+359": "BG", "+370": "LT",
        "+371": "LV", "+372": "EE", "+380": "UA", "+381": "RS", "+385": "HR",
        "+386": "SI", "+420": "CZ", "+421": "SK", "+593": "EC", "+673": "BN",
        "+679": "FJ", "+852": "HK", "+853": "MO", "+855": "KH", "+856": "LA",
        "+880": "BD", "+886": "TW", "+961": "LB", "+962": "JO", "+964": "IQ",
        "+965": "KW", "+966": "SA", "+968": "OM", "+971": "AE", "+972": "IL",
        "+973": "BH", "+974": "QA", "+976": "MN", "+977": "NP",
    };
    // Try longest prefix first (4 digits, then 3, then 2, then 1)
    for (let len = 4; len >= 1; len--) {
        const prefix = phone.substring(0, len + 1); // +1 for the '+' sign
        if (prefixes[prefix])
            return prefixes[prefix];
    }
    return "CN"; // fallback
}
/**
 * Map country code to a default timezone.
 */
function timezoneFromCountry(country) {
    const map = {
        CN: "Asia/Shanghai", US: "America/New_York", GB: "Europe/London",
        JP: "Asia/Tokyo", KR: "Asia/Seoul", CA: "America/Toronto",
        AU: "Australia/Sydney", DE: "Europe/Berlin", FR: "Europe/Paris",
        IN: "Asia/Kolkata", SG: "Asia/Singapore", HK: "Asia/Hong_Kong",
        TW: "Asia/Taipei", MY: "Asia/Kuala_Lumpur", TH: "Asia/Bangkok",
        VN: "Asia/Ho_Chi_Minh", PH: "Asia/Manila", ID: "Asia/Jakarta",
        NZ: "Pacific/Auckland", IT: "Europe/Rome", ES: "Europe/Madrid",
        NL: "Europe/Amsterdam", SE: "Europe/Stockholm", CH: "Europe/Zurich",
        RU: "Europe/Moscow", BR: "America/Sao_Paulo", MX: "America/Mexico_City",
        AR: "America/Argentina/Buenos_Aires", ZA: "Africa/Johannesburg",
        NG: "Africa/Lagos", EG: "Africa/Cairo", KE: "Africa/Nairobi",
        TR: "Europe/Istanbul", SA: "Asia/Riyadh", AE: "Asia/Dubai",
        IL: "Asia/Jerusalem", PK: "Asia/Karachi", BD: "Asia/Dhaka",
    };
    return map[country] || "UTC";
}
/**
 * POST /v1/auth/send-code
 * Send verification code to phone number via Firebase Auth.
 * In production, Firebase Auth handles SMS delivery automatically.
 * This endpoint exists for the iOS client's flow compatibility.
 */
router.post("/send-code", async (req, res) => {
    const { phone } = req.body;
    if (!phone) {
        res.status(400).json({ error: "Phone number is required" });
        return;
    }
    try {
        // Firebase Auth handles phone verification on the client side.
        // This endpoint is a placeholder for server-initiated flows
        // (e.g., re-send code, rate limiting, or custom SMS providers).
        // The actual verification is done via Firebase Auth SDK on iOS.
        res.json({ success: true, message: "Verification code sent" });
    }
    catch (error) {
        console.error("[Auth] send-code error:", error);
        res.status(500).json({ error: "Failed to send verification code" });
    }
});
/**
 * POST /v1/auth/login
 * Verify phone + code and return tokens.
 * With Firebase Auth, the client verifies directly and sends the ID token.
 * This endpoint validates the token and returns user data.
 */
router.post("/login", async (req, res) => {
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
        const userData = userDoc.data();
        // Generate custom token for session management
        const customToken = await admin.auth().createCustomToken(uid);
        res.json({
            accessToken: customToken,
            refreshToken: customToken, // Firebase handles refresh internally
            userId: uid,
            displayName: userData.displayName,
            role: userData.role,
        });
    }
    catch (error) {
        console.error("[Auth] login error:", error);
        res.status(401).json({ error: "Invalid credentials" });
    }
});
/**
 * POST /v1/auth/signup
 * Create a new user account after phone verification.
 */
router.post("/signup", async (req, res) => {
    const { idToken, displayName, role } = req.body;
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
        const now = firestore_1.Timestamp.now();
        const avatarInitial = displayName.charAt(0);
        const detectedCountry = countryFromPhone(phone);
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
        const customToken = await admin.auth().createCustomToken(uid);
        res.status(201).json({
            accessToken: customToken,
            refreshToken: customToken,
            userId: uid,
            displayName,
            role,
        });
    }
    catch (error) {
        console.error("[Auth] signup error:", error);
        res.status(500).json({ error: "Failed to create account" });
    }
});
/**
 * POST /v1/auth/refresh
 * Refresh an expired token.
 * With Firebase Auth, token refresh is handled client-side.
 * This endpoint exists for compatibility with the iOS AuthManager.
 */
router.post("/refresh", async (req, res) => {
    const { refreshToken } = req.body;
    if (!refreshToken) {
        res.status(400).json({ error: "Refresh token is required" });
        return;
    }
    try {
        // Verify the existing token and issue a new one
        const decoded = await admin.auth().verifyIdToken(refreshToken, true);
        const newToken = await admin.auth().createCustomToken(decoded.uid);
        res.json({
            accessToken: newToken,
            refreshToken: newToken,
        });
    }
    catch (error) {
        console.error("[Auth] refresh error:", error);
        res.status(401).json({ error: "Invalid refresh token" });
    }
});
exports.default = router;
//# sourceMappingURL=auth.js.map