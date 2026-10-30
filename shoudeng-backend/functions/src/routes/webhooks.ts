import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import { verifyTwilioSignature } from "../services/twilio";

const router = Router();
const db = admin.firestore();

// --- Twilio Signature Verification ---
// Computed over the public URL (region + /api function prefix), which
// req.headers.host + req.originalUrl does not reproduce inside Cloud Functions.
function verifyTwilio(req: Request): boolean {
  return verifyTwilioSignature(
    req.headers["x-twilio-signature"] as string | undefined,
    req.originalUrl,
    (req.body ?? {}) as Record<string, unknown>
  );
}

/**
 * POST /v1/webhooks/twilio/call-status
 * Twilio call status callback — tracks voice call delivery and duration.
 * Called by Twilio when a call's status changes.
 * Verified via X-Twilio-Signature.
 */
router.post("/twilio/call-status", async (req: Request, res: Response) => {
  if (!verifyTwilio(req)) {
    console.error("[Webhook] Invalid Twilio signature for call-status");
    res.status(403).json({ error: "Invalid signature" });
    return;
  }

  const {
    CallSid,
    CallStatus,    // "queued" | "ringing" | "in-progress" | "completed" | "busy" | "failed" | "no-answer"
    CallDuration,
    To,
    From,
  } = req.body;

  console.log(`[Webhook] Twilio call status: ${CallSid} → ${CallStatus}`);

  try {
    const callRef = db.collection("voice_calls").doc(String(CallSid));
    const call = await callRef.get();
    if (!call.exists) {
      res.status(204).send();
      return;
    }
    await callRef.update({ status: CallStatus, duration: CallDuration ?? null, to: To ?? null, from: From ?? null });

    // Mirror onto the SOS escalation log entry for this call
    const sosRef = db.collection("sos_events").doc(call.data()!.sosEventId);
    await db.runTransaction(async (tx) => {
      const sos = await tx.get(sosRef);
      if (!sos.exists) return;
      const log = [...(sos.data()!.escalationLog || [])];
      const idx = log.findIndex((e: { callSid?: string }) => e.callSid === CallSid);
      if (idx < 0) return;
      const now = admin.firestore.Timestamp.now();
      const entry = { ...log[idx] };
      switch (CallStatus) {
        case "ringing": entry.deliveredAt = now; break;
        case "in-progress": entry.readAt = now; break;
        case "completed": entry.respondedAt = now; entry.response = `completed_${CallDuration}s`; break;
        case "busy": case "failed": case "no-answer": entry.response = CallStatus; break;
      }
      log[idx] = entry;
      // Escalation state is owned by services/escalation.ts — only the log changes here
      tx.update(sosRef, { escalationLog: log });
    });

    res.status(204).send();
  } catch (error) {
    console.error("[Webhook] Twilio call status error:", error);
    res.status(500).json({ error: "Failed to process callback" });
  }
});

/**
 * POST /v1/webhooks/twilio/sms-status
 * Twilio SMS delivery status callback.
 * Verified via X-Twilio-Signature.
 */
router.post("/twilio/sms-status", async (req: Request, res: Response) => {
  if (!verifyTwilio(req)) {
    console.error("[Webhook] Invalid Twilio signature for sms-status");
    res.status(403).json({ error: "Invalid signature" });
    return;
  }

  const { MessageSid, MessageStatus, To, ErrorCode } = req.body;

  console.log(`[Webhook] Twilio SMS status: ${MessageSid} → ${MessageStatus}`);

  if (ErrorCode) {
    console.error(`[Webhook] SMS error ${ErrorCode} for ${To}`);
  }

  // Log SMS delivery for monitoring
  try {
    await db.collection("sms_delivery_log").add({
      messageSid: MessageSid,
      status: MessageStatus,
      to: To,
      errorCode: ErrorCode || null,
      timestamp: admin.firestore.Timestamp.now(),
    });
  } catch (error) {
    console.error("[Webhook] Failed to log SMS status:", error);
  }

  res.status(204).send();
});

/**
 * POST /v1/webhooks/apple/subscription
 * Apple App Store Server Notification v2 — alternative webhook endpoint.
 * Delegates to the payment service handler.
 */
router.post("/apple/subscription", async (req: Request, res: Response) => {
  const { signedPayload } = req.body;

  if (!signedPayload) {
    res.status(400).json({ error: "signedPayload is required" });
    return;
  }

  try {
    const { handleAppleNotification } = await import("../services/payment");
    await handleAppleNotification(signedPayload);
    res.json({ success: true });
  } catch (error) {
    console.error("[Webhook] Apple subscription error:", error);
    res.status(500).json({ error: "Webhook processing failed" });
  }
});

export default router;
