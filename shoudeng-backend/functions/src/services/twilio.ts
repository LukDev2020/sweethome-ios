import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

const db = admin.firestore();

// Twilio client — initialized lazily from Firebase config
let twilioClient: ReturnType<typeof createTwilioClient> | null = null;

function createTwilioClient() {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const twilio = require("twilio");
  const accountSid = functions.config().twilio?.account_sid;
  const authToken = functions.config().twilio?.auth_token;
  if (!accountSid || !authToken) {
    console.warn("[Twilio] Missing config — voice calls disabled");
    return null;
  }
  return twilio(accountSid, authToken);
}

function getClient() {
  if (!twilioClient) {
    twilioClient = createTwilioClient();
  }
  return twilioClient;
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
  const map: Record<string, string> = {
    CN: "110",
    US: "911",
    CA: "911",
    GB: "999",
    AU: "000",
    JP: "110",
    KR: "112",
  };
  return map[countryCode] || "112"; // 112 is international emergency
}

/**
 * Get the TwiML script language based on country code.
 */
function getTwimlLanguage(countryCode: string): string {
  const map: Record<string, string> = {
    CN: "zh-CN",
    US: "en-US",
    CA: "en-US",
    GB: "en-GB",
    AU: "en-AU",
    JP: "ja-JP",
    KR: "ko-KR",
  };
  return map[countryCode] || "zh-CN";
}

/**
 * Initiate a voice call to a guardian as part of the SOS escalation chain.
 */
export async function initiateVoiceCall(
  guardianId: string,
  sosEventId: string,
  protectedPersonName: string,
  callbackUrl: string
): Promise<string | null> {
  const client = getClient();
  if (!client) {
    console.warn("[Twilio] Client not configured — skipping voice call");
    return null;
  }

  const phone = await getUserPhone(guardianId);
  if (!phone) {
    console.warn(`[Twilio] No phone number for guardian ${guardianId}`);
    return null;
  }

  const fromNumber = functions.config().twilio?.from_number || "+10000000000";

  // Load protected person's country for language
  const sosDoc = await db.collection("sos_events").doc(sosEventId).get();
  const protectedId = sosDoc.data()?.protectedPersonId;
  const protectedUser = protectedId
    ? (await db.collection("users").doc(protectedId).get()).data()
    : null;
  const lang = getTwimlLanguage(protectedUser?.countryCode || "CN");

  const twiml = `<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Say language="${lang}" voice="alice">
    守灯紧急通知。您守护的${protectedPersonName}正在求助。请立即打开守灯应用查看详情。
  </Say>
  <Pause length="2"/>
  <Say language="${lang}" voice="alice">
    按 1 表示已接手处理。按 2 重听此消息。
  </Say>
  <Gather numDigits="1" action="${callbackUrl}" method="POST">
    <Say language="${lang}" voice="alice">请按键。</Say>
  </Gather>
  <Say language="${lang}" voice="alice">
    未收到回应。系统将在一分钟后再次拨打。
  </Say>
</Response>`;

  try {
    const call = await client.calls.create({
      twiml,
      to: phone,
      from: fromNumber,
      statusCallback: callbackUrl,
    });
    console.log(`[Twilio] Call initiated to ${guardianId}: ${call.sid}`);
    return call.sid;
  } catch (error) {
    console.error(`[Twilio] Failed to call ${guardianId}:`, error);
    return null;
  }
}

export { getEmergencyNumber, getTwimlLanguage };
