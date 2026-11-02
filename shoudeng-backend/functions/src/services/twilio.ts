import * as admin from "firebase-admin";
import * as crypto from "crypto";
import { Lang, userLang } from "./locale";
import type { VoiceReservation } from "./fairUse";
import { twilioConfig, missingTwilioParams, reportMissingConfig } from "../config/params";

const db = admin.firestore();

// Twilio client — initialized lazily from the TWILIO_* params (config/params.ts)
let twilioClient: ReturnType<typeof createTwilioClient> | null = null;

function createTwilioClient() {
  const cfg = twilioConfig();
  const missing = missingTwilioParams("voice", cfg);
  if (missing.length > 0) {
    reportMissingConfig("SOS voice calls", missing, "Guardians get a push reminder instead of each call.");
    return null;
  }
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const twilio = require("twilio");
  return twilio(cfg.accountSid, cfg.authToken);
}

function getClient() {
  if (!twilioClient) {
    twilioClient = createTwilioClient();
  }
  return twilioClient;
}

/** Test hook. */
export function __setTwilioClientForTests(client: unknown) {
  twilioClient = client as ReturnType<typeof createTwilioClient>;
}

/**
 * Public base URL of the `api` HTTPS function, e.g.
 * https://us-central1-<project>.cloudfunctions.net/api — Twilio must call back
 * through the function name prefix and region, and signatures are computed over
 * this exact URL. Override with PUBLIC_API_BASE_URL (custom domain / hosting rewrite).
 */
export function publicApiBaseUrl(): string {
  if (process.env.PUBLIC_API_BASE_URL) return process.env.PUBLIC_API_BASE_URL.replace(/\/$/, "");
  const project = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || "sweethome-b4e82";
  const region = process.env.FUNCTION_REGION || "us-central1";
  return `https://${region}-${project}.cloudfunctions.net/api`;
}

/**
 * Verify X-Twilio-Signature: base64(HMAC-SHA1(authToken, url + sorted(key+value))).
 * `path` is the request path *inside* the api function (req.originalUrl).
 */
export function verifyTwilioSignature(
  signature: string | undefined,
  path: string,
  params: Record<string, unknown>,
  authToken = twilioConfig().authToken
): boolean {
  if (process.env.FUNCTIONS_EMULATOR === "true") return true;
  if (!authToken || !signature) return false;
  const url = publicApiBaseUrl() + path;
  const data = url + Object.keys(params).sort().map((k) => k + String(params[k] ?? "")).join("");
  const expected = crypto.createHmac("sha1", authToken).update(Buffer.from(data, "utf-8")).digest("base64");
  const a = Buffer.from(signature, "utf-8");
  const b = Buffer.from(expected, "utf-8");
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

/**
 * Get the phone number for a user from Firestore.
 */
async function getUserPhone(userId: string): Promise<string | null> {
  const userDoc = await db.collection("users").doc(userId).get();
  return userDoc.exists ? userDoc.data()?.phone ?? null : null;
}

/**
 * Get the emergency number based on country code.
 */
function getEmergencyNumber(countryCode: string): string {
  // Same table as the iOS app (RegionalEmergencyInfo): ambulance first.
  const map: Record<string, string> = {
    US: "911", CA: "911", HK: "999", MO: "999", TW: "119", SG: "995", AU: "000", NZ: "111",
    MY: "999", TH: "1669", PH: "911", JP: "119",
    CN: "120", GB: "999", FR: "15", DE: "112", KR: "119", UA: "112",
  };
  return map[countryCode.toUpperCase()] || "112"; // 112 works from most mobile phones
}

/**
 * Twilio <Say> language for the guardian's app language.
 */
function getTwimlLanguage(lang: Lang): string {
  return { en: "en-US", zh: "cmn-CN", "zh-Hant": "cmn-TW", fr: "fr-FR", ja: "ja-JP" }[lang];
}

/**
 * Escape a string for safe interpolation into XML/TwiML.
 */
export function escapeXml(str: string): string {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

const VOICE_COPY: Record<Lang, {
  intro: (name: string) => string;
  keys: string;
  prompt: string;
  /** What happens if nobody presses 1 — must match the escalation plan. */
  noAnswer: (isLastRound: boolean) => string;
  ack: string;
  invalid: string;
}> = {
  en: {
    intro: (n) => `Lantern Care emergency. ${n}, who you look after, is calling for help. Please open the Lantern Care app now.`,
    keys: "Press 1 if you are handling it. This stops the automatic calls and tells the rest of the family. Press 2 to hear this again.",
    prompt: "Please press a key.",
    noAnswer: (last) => last
      ? "No response received. Your family has also been sent a link with the latest location."
      : "No response received. We will call again in about two minutes until someone responds.",
    ack: "Thank you. The others have been told you are handling it, and the automatic calls have stopped. Please open the app to see the location.",
    invalid: "Invalid key.",
  },
  zh: {
    intro: (n) => `守灯紧急通知。您守护的${n}正在求助。请立即打开守灯应用查看详情。`,
    keys: "按 1 表示由您处理，系统将停止自动呼叫并通知其他家人。按 2 重听此消息。",
    prompt: "请按键。",
    noAnswer: (last) => last
      ? "未收到回应。家人已收到包含最新位置的链接短信。"
      : "未收到回应。约两分钟后系统将再次拨打，直到有人回应。",
    ack: "谢谢。已通知其他家人由您处理，自动呼叫已停止。请打开应用查看位置。",
    invalid: "无效按键。",
  },
  "zh-Hant": {
    intro: (n) => `守燈緊急通知。您守護的${n}正在求助。請立即開啟守燈應用檢視詳情。`,
    keys: "按 1 表示由您處理，系統將停止自動呼叫並通知其他家人。按 2 重聽此訊息。",
    prompt: "請按鍵。",
    noAnswer: (last) => last
      ? "未收到回應。家人已收到包含最新位置的連結簡訊。"
      : "未收到回應。約兩分鐘後系統將再次撥打，直到有人回應。",
    ack: "謝謝。已通知其他家人由您處理，自動呼叫已停止。請開啟應用檢視位置。",
    invalid: "無效按鍵。",
  },
  fr: {
    intro: (n) => `Urgence Lantern Care. ${n}, que vous protégez, demande de l'aide. Ouvrez l'application Lantern Care maintenant.`,
    keys: "Appuyez sur 1 si vous vous en occupez. Les appels automatiques s'arrêteront et le reste de la famille sera prévenu. Appuyez sur 2 pour réécouter.",
    prompt: "Veuillez appuyer sur une touche.",
    noAnswer: (last) => last
      ? "Aucune réponse. Votre famille a aussi reçu un lien avec la dernière position."
      : "Aucune réponse. Nous rappellerons dans environ deux minutes jusqu'à ce que quelqu'un réponde.",
    ack: "Merci. Les autres ont été prévenus que vous vous en occupez et les appels automatiques sont arrêtés. Ouvrez l'application pour voir la position.",
    invalid: "Touche invalide.",
  },
  ja: {
    intro: (n) => `Lantern Care緊急通知です。あなたが見守っている${n}さんが助けを求めています。今すぐLantern Careアプリを開いてください。`,
    keys: "対応できる場合は1を押してください。自動発信が停止し、ほかのご家族にお知らせします。もう一度聞く場合は2を押してください。",
    prompt: "番号を押してください。",
    noAnswer: (last) => last
      ? "応答がありませんでした。ご家族には最新の位置情報へのリンクも送信済みです。"
      : "応答がありませんでした。どなたかが応答するまで、約2分後に再度おかけします。",
    ack: "ありがとうございます。あなたが対応することをほかのご家族にお知らせし、自動発信を停止しました。アプリを開いて位置情報をご確認ください。",
    invalid: "無効な番号です。",
  },
};

export function buildVoiceTwiml(opts: {
  lang: Lang;
  personName: string;
  isLastRound: boolean;
  gatherUrl: string;
}): string {
  const c = VOICE_COPY[opts.lang];
  const l = escapeXml(getTwimlLanguage(opts.lang));
  return `<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Say language="${l}">${escapeXml(c.intro(opts.personName))}</Say>
  <Pause length="1"/>
  <Gather numDigits="1" action="${escapeXml(opts.gatherUrl)}" method="POST">
    <Say language="${l}">${escapeXml(c.keys)}</Say>
    <Say language="${l}">${escapeXml(c.prompt)}</Say>
  </Gather>
  <Say language="${l}">${escapeXml(c.noAnswer(opts.isLastRound))}</Say>
</Response>`;
}

export function voiceReplyTwiml(lang: Lang, kind: "ack" | "invalid"): string {
  const c = VOICE_COPY[lang];
  return `<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Say language="${escapeXml(getTwimlLanguage(lang))}">${escapeXml(kind === "ack" ? c.ack : c.invalid)}</Say>
</Response>`;
}

/**
 * Call a guardian as part of the SOS escalation. The call is recorded in
 * voice_calls/{CallSid} so the keypad callback can be matched to exactly this
 * SOS and guardian. Returns the CallSid, or null if the call could not be placed.
 */
export async function initiateVoiceCall(
  guardianId: string,
  sosEventId: string,
  protectedPersonName: string,
  opts: { round: number; isLastRound: boolean; fairUse?: VoiceReservation } = { round: 1, isLastRound: false }
): Promise<string | null> {
  const client = getClient();
  if (!client) return null; // not configured — reported once by createTwilioClient

  const [phone, guardianDoc] = await Promise.all([
    getUserPhone(guardianId),
    db.collection("users").doc(guardianId).get(),
  ]);
  if (!phone) {
    console.warn(`[Twilio] No phone number for guardian ${guardianId}`);
    return null;
  }
  const fromNumber = twilioConfig().voiceFrom;
  if (!fromNumber) return null;

  const lang = userLang(guardianDoc.data());
  const base = publicApiBaseUrl();
  const twiml = buildVoiceTwiml({
    lang,
    personName: protectedPersonName,
    isLastRound: opts.isLastRound,
    gatherUrl: `${base}/v1/voice-callback`,
  });

  try {
    const call = await client.calls.create({
      twiml,
      to: phone,
      from: fromNumber,
      statusCallback: `${base}/v1/webhooks/twilio/call-status`,
      statusCallbackEvent: ["ringing", "answered", "completed"],
    });
    await db.collection("voice_calls").doc(call.sid).set({
      sosEventId,
      guardianId,
      lang,
      personName: protectedPersonName,
      round: opts.round,
      isLastRound: opts.isLastRound,
      fairUse: opts.fairUse ?? null, // minute reserved by fair use; settled by the status callback
      createdAt: admin.firestore.Timestamp.now(),
      status: "queued",
    });
    console.log(`[Twilio] Call ${call.sid} placed to guardian ${guardianId} (round ${opts.round})`);
    return call.sid;
  } catch (error) {
    console.error(`[Twilio] Failed to call ${guardianId}:`, error);
    return null;
  }
}

export { getEmergencyNumber, getTwimlLanguage };
