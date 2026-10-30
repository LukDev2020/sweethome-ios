import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import { acknowledgeSOS } from "../services/escalation";
import { buildVoiceTwiml, publicApiBaseUrl, verifyTwilioSignature, voiceReplyTwiml } from "../services/twilio";
import { normalizeLocale, Lang } from "../services/locale";
import { createRateLimiter, RATE_LIMITS } from "../middleware/rateLimit";

/**
 * Public Twilio voice endpoints (no app auth — Twilio signs every request).
 *   POST /v1/voice-callback  keypad result from the escalation call's <Gather>
 *   POST /v1/voice-replay    replays the message (digit 2)
 * The call is matched by CallSid to voice_calls/{CallSid}, written when the
 * escalation placed it, so "1" acknowledges exactly that SOS for that guardian.
 */
const router = Router();
const db = admin.firestore();
// Per route (never router.use): this router is mounted at bare /v1
const limit = createRateLimiter(RATE_LIMITS.webhook, (req) => `ip:${req.ip}`);

function twiml(res: Response, xml: string) {
  res.set("Content-Type", "text/xml");
  res.send(xml);
}

function signed(req: Request): boolean {
  return verifyTwilioSignature(
    req.headers["x-twilio-signature"] as string | undefined,
    req.originalUrl,
    (req.body ?? {}) as Record<string, unknown>
  );
}

router.post("/voice-callback", limit, async (req: Request, res: Response) => {
  if (!signed(req)) {
    console.warn("[VoiceCallback] Rejected request with invalid Twilio signature");
    res.status(403).send("Forbidden");
    return;
  }
  const { Digits, CallSid } = req.body ?? {};
  const callDoc = typeof CallSid === "string" && CallSid
    ? await db.collection("voice_calls").doc(CallSid).get()
    : null;
  const call = callDoc?.exists ? callDoc.data()! : null;
  const lang: Lang = normalizeLocale(call?.lang) ?? normalizeLocale(req.query.lang) ?? "zh";

  if (!call) {
    console.warn(`[VoiceCallback] Unknown CallSid ${CallSid}`);
    twiml(res, voiceReplyTwiml(lang, "invalid"));
    return;
  }

  if (Digits === "1") {
    try {
      const r = await acknowledgeSOS(call.sosEventId, call.guardianId, "voice");
      await callDoc!.ref.update({ acknowledged: r.status === "acknowledged", digits: "1" });
      console.log(`[VoiceCallback] ${CallSid}: guardian ${call.guardianId} → ${r.status}`);
    } catch (err) {
      console.error("[VoiceCallback] acknowledge failed:", err);
    }
    twiml(res, voiceReplyTwiml(lang, "ack"));
    return;
  }

  if (Digits === "2") {
    twiml(res, `<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Redirect method="POST">${publicApiBaseUrl()}/v1/voice-replay</Redirect>
</Response>`);
    return;
  }

  twiml(res, voiceReplyTwiml(lang, "invalid"));
});

router.post("/voice-replay", limit, async (req: Request, res: Response) => {
  if (!signed(req)) {
    res.status(403).send("Forbidden");
    return;
  }
  const { CallSid } = req.body ?? {};
  const callDoc = typeof CallSid === "string" && CallSid
    ? await db.collection("voice_calls").doc(CallSid).get()
    : null;
  const call = callDoc?.exists ? callDoc.data()! : null;
  if (!call) {
    twiml(res, voiceReplyTwiml("zh", "invalid"));
    return;
  }
  twiml(res, buildVoiceTwiml({
    lang: normalizeLocale(call.lang) ?? "zh",
    personName: call.personName ?? "",
    isLastRound: call.isLastRound === true,
    gatherUrl: `${publicApiBaseUrl()}/v1/voice-callback`,
  }));
});

export default router;
