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
exports.sendSOSSms = sendSOSSms;
exports.sendCheckinReminderSms = sendCheckinReminderSms;
exports.sendVerificationSms = sendVerificationSms;
exports.hasAppInstalled = hasAppInstalled;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
const db = admin.firestore();
// Per-locale SMS templates
const smsStrings = {
    zh: {
        sosBody: (name, url) => url
            ? `【守灯紧急通知】${name}正在求助！请立即查看详情：${url}`
            : `【守灯紧急通知】${name}正在求助！请立即打开守灯应用查看。`,
        checkinBody: (name) => `【守灯提醒】${name}今天尚未报平安，请关注。`,
        verifyBody: (code) => `【守灯】您的验证码是 ${code}，5 分钟内有效。`,
    },
    en: {
        sosBody: (name, url) => url
            ? `[Luma Emergency] ${name} is calling for help! View details: ${url}`
            : `[Luma Emergency] ${name} is calling for help! Open the Luma app now.`,
        checkinBody: (name) => `[Luma] ${name} hasn't checked in today. Please follow up.`,
        verifyBody: (code) => `[Luma] Your verification code is ${code}. Valid for 5 minutes.`,
    },
    fr: {
        sosBody: (name, url) => url
            ? `[Luma Urgence] ${name} demande de l'aide ! Voir les détails : ${url}`
            : `[Luma Urgence] ${name} demande de l'aide ! Ouvrez l'application Luma maintenant.`,
        checkinBody: (name) => `[Luma] ${name} n'a pas donné signe de vie aujourd'hui.`,
        verifyBody: (code) => `[Luma] Votre code de vérification est ${code}. Valide 5 minutes.`,
    },
};
function getSmsStrings(locale) {
    const lang = (locale || "zh").substring(0, 2);
    return smsStrings[lang] || smsStrings.zh;
}
async function getUserLocale(userId) {
    const userDoc = await db.collection("users").doc(userId).get();
    return userDoc.exists ? userDoc.data()?.locale || "zh" : "zh";
}
// Twilio client for SMS — initialized lazily
let twilioClient = null;
function createClient() {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const twilio = require("twilio");
    const accountSid = functions.config().twilio?.account_sid;
    const authToken = functions.config().twilio?.auth_token;
    if (!accountSid || !authToken) {
        console.warn("[SMS] Twilio not configured — SMS disabled");
        return null;
    }
    return twilio(accountSid, authToken);
}
function getClient() {
    if (!twilioClient) {
        twilioClient = createClient();
    }
    return twilioClient;
}
/**
 * Send an SMS to a guardian who may not have the app installed.
 * Used as a fallback in the SOS escalation chain.
 */
async function sendSOSSms(guardianId, protectedPersonName, sosEventId, shareUrl) {
    const client = getClient();
    if (!client)
        return false;
    const phone = await getUserPhone(guardianId);
    if (!phone) {
        console.warn(`[SMS] No phone for guardian ${guardianId}`);
        return false;
    }
    const fromNumber = functions.config().twilio?.sms_from || functions.config().twilio?.from_number;
    if (!fromNumber)
        return false;
    const locale = await getUserLocale(guardianId);
    const s = getSmsStrings(locale);
    const body = s.sosBody(protectedPersonName, shareUrl);
    try {
        const message = await client.messages.create({
            body,
            to: phone,
            from: fromNumber,
        });
        console.log(`[SMS] SOS SMS sent to ${guardianId}: ${message.sid}`);
        return true;
    }
    catch (error) {
        console.error(`[SMS] Failed to send to ${guardianId}:`, error);
        return false;
    }
}
/**
 * Send a check-in reminder SMS.
 */
async function sendCheckinReminderSms(guardianId, protectedPersonName) {
    const client = getClient();
    if (!client)
        return false;
    const phone = await getUserPhone(guardianId);
    if (!phone)
        return false;
    const fromNumber = functions.config().twilio?.sms_from || functions.config().twilio?.from_number;
    if (!fromNumber)
        return false;
    const locale = await getUserLocale(guardianId);
    const s = getSmsStrings(locale);
    try {
        await client.messages.create({
            body: s.checkinBody(protectedPersonName),
            to: phone,
            from: fromNumber,
        });
        return true;
    }
    catch (error) {
        console.error(`[SMS] Checkin reminder failed:`, error);
        return false;
    }
}
/**
 * Send a verification code SMS (for custom SMS provider flow).
 */
async function sendVerificationSms(phone, code) {
    const client = getClient();
    if (!client)
        return false;
    const fromNumber = functions.config().twilio?.sms_from || functions.config().twilio?.from_number;
    if (!fromNumber)
        return false;
    // Verification SMS uses phone's country to guess locale (no userId available)
    const locale = phone.startsWith("+33") ? "fr" : phone.startsWith("+1") || phone.startsWith("+44") || phone.startsWith("+61") ? "en" : "zh";
    const s = getSmsStrings(locale);
    try {
        await client.messages.create({
            body: s.verifyBody(code),
            to: phone,
            from: fromNumber,
        });
        return true;
    }
    catch (error) {
        console.error(`[SMS] Verification SMS failed:`, error);
        return false;
    }
}
/**
 * Check if a guardian has the app installed (has device tokens).
 * If not, SMS is the fallback notification channel.
 */
async function hasAppInstalled(userId) {
    const tokens = await db
        .collection("device_tokens")
        .where("userId", "==", userId)
        .limit(1)
        .get();
    return !tokens.empty;
}
/**
 * Get phone number for a user.
 */
async function getUserPhone(userId) {
    const userDoc = await db.collection("users").doc(userId).get();
    return userDoc.exists ? userDoc.data()?.phone ?? null : null;
}
//# sourceMappingURL=sms.js.map