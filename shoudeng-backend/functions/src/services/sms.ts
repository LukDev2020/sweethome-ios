import { localeFromPhone, normalizeLocale } from "./locale";
import * as admin from "firebase-admin";
import { twilioConfig, missingTwilioParams, reportMissingConfig } from "../config/params";

const db = admin.firestore();

// Per-locale SMS templates
const smsStrings: Record<string, {
  sosBody: (name: string, url?: string) => string;
  /** To an emergency contact who is not an app user (no guardians set up). */
  contactSosBody: (name: string, url?: string) => string;
  checkinBody: (name: string) => string;
  verifyBody: (code: string) => string;
}> = {
  zh: {
    sosBody: (name, url) => url
      ? `【守灯紧急通知】${name}正在求助！请立即查看详情：${url}`
      : `【守灯紧急通知】${name}正在求助！请立即打开守灯应用查看。`,
    contactSosBody: (name, url) => `【守灯紧急通知】${name}将您设为紧急联系人，现在正在求助。${url ? "最新位置：" + url + "。" : ""}如无法联系上本人，请拨打当地紧急电话。`,
    checkinBody: (name) => `【守灯提醒】${name}今天尚未报平安，请关注。`,
    verifyBody: (code) => `【守灯】您的验证码是 ${code}，5 分钟内有效。`,
  },
  "zh-Hant": {
    sosBody: (name, url) => url
      ? `【守燈緊急通知】${name}正在求助！請立即檢視詳情：${url}`
      : `【守燈緊急通知】${name}正在求助！請立即開啟守燈應用檢視。`,
    contactSosBody: (name, url) => `【守燈緊急通知】${name}將您設為緊急聯絡人，現在正在求助。${url ? "最新位置：" + url + "。" : ""}如無法聯絡上本人，請撥打當地緊急電話。`,
    checkinBody: (name) => `【守燈提醒】${name}今天尚未報平安，請關注。`,
    verifyBody: (code) => `【守燈】您的驗證碼是 ${code}，5 分鐘內有效。`,
  },
  en: {
    sosBody: (name, url) => url
      ? `[Lantern Care Emergency] ${name} is calling for help! View details: ${url}`
      : `[Lantern Care Emergency] ${name} is calling for help! Open the Lantern Care app now.`,
    contactSosBody: (name, url) => `[Lantern Care Emergency] ${name} listed you as an emergency contact and is calling for help now.${url ? " Latest location: " + url + "." : ""} If you can't reach them, call local emergency services.`,
    checkinBody: (name) => `[Lantern Care] ${name} hasn't checked in today. Please follow up.`,
    verifyBody: (code) => `[Lantern Care] Your verification code is ${code}. Valid for 5 minutes.`,
  },
  fr: {
    sosBody: (name, url) => url
      ? `[Lantern Care Urgence] ${name} demande de l'aide ! Voir les détails : ${url}`
      : `[Lantern Care Urgence] ${name} demande de l'aide ! Ouvrez l'application Lantern Care maintenant.`,
    contactSosBody: (name, url) => `[Lantern Care Urgence] ${name} vous a désigné(e) comme contact d'urgence et demande de l'aide.${url ? " Dernière position : " + url + "." : ""} Si vous ne pouvez pas le/la joindre, appelez les secours.`,
    checkinBody: (name) => `[Lantern Care] ${name} n'a pas donné signe de vie aujourd'hui.`,
    verifyBody: (code) => `[Lantern Care] Votre code de vérification est ${code}. Valide 5 minutes.`,
  },
  ja: {
    sosBody: (name, url) => url
      ? `【Lantern Care 緊急通知】${name}さんが助けを求めています。詳細をすぐにご確認ください：${url}`
      : `【Lantern Care 緊急通知】${name}さんが助けを求めています。今すぐLantern Careアプリを開いてご確認ください。`,
    contactSosBody: (name, url) => `【Lantern Care 緊急通知】${name}さんがあなたを緊急連絡先に登録しており、現在助けを求めています。${url ? "最新の位置情報：" + url + " " : ""}ご本人と連絡が取れない場合は、現地の緊急通報番号（日本国内は救急119・警察110）に連絡してください。`,
    checkinBody: (name) => `【Lantern Care】${name}さんから今日の無事報告がまだありません。ご確認をお願いします。`,
    verifyBody: (code) => `【Lantern Care】認証コードは ${code} です。有効期限は5分間です。`,
  },
};

function getSmsStrings(locale: string) {
  // normalizeLocale keeps "zh-Hant" (Hong Kong, Macao, Taiwan) apart from "zh".
  const lang = normalizeLocale(locale) ?? "zh";
  return smsStrings[lang] || smsStrings.zh;
}

async function getUserLocale(userId: string): Promise<string> {
  const userDoc = await db.collection("users").doc(userId).get();
  return userDoc.exists ? userDoc.data()?.locale || "zh" : "zh";
}

// Twilio client for SMS — initialized lazily from the TWILIO_* params (config/params.ts)
let twilioClient: ReturnType<typeof createClient> | null = null;

function createClient() {
  const cfg = twilioConfig();
  const missing = missingTwilioParams("sms", cfg);
  if (missing.length > 0) {
    reportMissingConfig("SMS", missing, "SOS reaches guardians by push only; emergency contacts get no text.");
    return null;
  }
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const twilio = require("twilio");
  return twilio(cfg.accountSid, cfg.authToken);
}

/** Tests only. */
export function __setSmsClientForTests(client: unknown) {
  twilioClient = client as ReturnType<typeof createClient>;
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
export async function sendSOSSms(
  guardianId: string,
  protectedPersonName: string,
  sosEventId: string,
  shareUrl?: string
): Promise<boolean> {
  const client = getClient();
  if (!client) return false;

  const phone = await getUserPhone(guardianId);
  if (!phone) {
    console.warn(`[SMS] No phone for guardian ${guardianId}`);
    return false;
  }

  const fromNumber = twilioConfig().smsFrom;
  if (!fromNumber) return false;

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
  } catch (error) {
    console.error(`[SMS] Failed to send to ${guardianId}:`, error);
    return false;
  }
}

/**
 * SOS text to an emergency contact (a phone number, not an app user), in the
 * protected person's language.
 */
export async function sendEmergencyContactSms(
  phone: string,
  protectedPersonName: string,
  locale: string,
  shareUrl?: string
): Promise<boolean> {
  const client = getClient();
  if (!client) return false;
  const fromNumber = twilioConfig().smsFrom;
  if (!fromNumber) return false;
  try {
    await client.messages.create({
      body: getSmsStrings(locale).contactSosBody(protectedPersonName, shareUrl),
      to: phone,
      from: fromNumber,
    });
    return true;
  } catch (error) {
    console.error("[SMS] Emergency contact SMS failed:", error);
    return false;
  }
}

/**
 * Send a check-in reminder SMS.
 */
export async function sendCheckinReminderSms(
  guardianId: string,
  protectedPersonName: string
): Promise<boolean> {
  const client = getClient();
  if (!client) return false;

  const phone = await getUserPhone(guardianId);
  if (!phone) return false;

  const fromNumber = twilioConfig().smsFrom;
  if (!fromNumber) return false;

  const locale = await getUserLocale(guardianId);
  const s = getSmsStrings(locale);

  try {
    await client.messages.create({
      body: s.checkinBody(protectedPersonName),
      to: phone,
      from: fromNumber,
    });
    return true;
  } catch (error) {
    console.error(`[SMS] Checkin reminder failed:`, error);
    return false;
  }
}

/**
 * Send a verification code SMS (for custom SMS provider flow).
 */
export async function sendVerificationSms(
  phone: string,
  code: string
): Promise<boolean> {
  const client = getClient();
  if (!client) return false;

  const fromNumber = twilioConfig().smsFrom;
  if (!fromNumber) return false;

  // Verification SMS uses phone's country to guess locale (no userId available)
  const locale = localeFromPhone(phone);
  const s = getSmsStrings(locale);

  try {
    await client.messages.create({
      body: s.verifyBody(code),
      to: phone,
      from: fromNumber,
    });
    return true;
  } catch (error) {
    console.error(`[SMS] Verification SMS failed:`, error);
    return false;
  }
}

/**
 * Check if a guardian has the app installed (has device tokens).
 * If not, SMS is the fallback notification channel.
 */
export async function hasAppInstalled(userId: string): Promise<boolean> {
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
async function getUserPhone(userId: string): Promise<string | null> {
  const userDoc = await db.collection("users").doc(userId).get();
  return userDoc.exists ? userDoc.data()?.phone ?? null : null;
}
