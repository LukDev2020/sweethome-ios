import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";

const router = Router();
const db = admin.firestore();

/**
 * POST /v1/webhooks/twilio/call-status
 * Twilio call status callback — tracks voice call delivery and duration.
 * Called by Twilio when a call's status changes.
 * NO auth — Twilio signs requests, verify via X-Twilio-Signature in production.
 */
router.post("/twilio/call-status", async (req: Request, res: Response) => {
  const {
    CallSid,
    CallStatus,    // "queued" | "ringing" | "in-progress" | "completed" | "busy" | "failed" | "no-answer"
    CallDuration,
    To,
    From,
  } = req.body;

  console.log(`[Webhook] Twilio call status: ${CallSid} → ${CallStatus}`);

  try {
    // Find SOS event with this call SID in escalation log
    const sosSnapshot = await db
      .collection("sos_events")
      .where("resolvedAt", "==", null)
      .get();

    for (const doc of sosSnapshot.docs) {
      const data = doc.data();
      const log = data.escalationLog || [];

      const matchIdx = log.findIndex(
        (entry: { callSid?: string }) => entry.callSid === CallSid
      );

      if (matchIdx >= 0) {
        // Update the escalation log entry
        const updatedLog = [...log];
        const now = admin.firestore.Timestamp.now();

        switch (CallStatus) {
          case "ringing":
            updatedLog[matchIdx].deliveredAt = now;
            break;
          case "in-progress":
            updatedLog[matchIdx].readAt = now;
            break;
          case "completed":
            updatedLog[matchIdx].respondedAt = now;
            updatedLog[matchIdx].response = `completed_${CallDuration}s`;
            break;
          case "busy":
          case "failed":
          case "no-answer":
            updatedLog[matchIdx].response = CallStatus;
            break;
        }

        await doc.ref.update({ escalationLog: updatedLog });

        // If call was not answered, update escalation state
        if (["busy", "failed", "no-answer"].includes(CallStatus)) {
          // Check if all voice calls have been exhausted
          const allExhausted = updatedLog
            .filter((e: { hop: number }) => e.hop === 3)
            .every(
              (e: { response: string | null }) =>
                e.response && ["busy", "failed", "no-answer"].includes(e.response)
            );

          if (allExhausted) {
            await doc.ref.update({ escalationState: "hop3_exhausted" });
          }
        }

        break;
      }
    }

    res.status(204).send();
  } catch (error) {
    console.error("[Webhook] Twilio call status error:", error);
    res.status(500).json({ error: "Failed to process callback" });
  }
});

/**
 * POST /v1/webhooks/twilio/sms-status
 * Twilio SMS delivery status callback.
 */
router.post("/twilio/sms-status", async (req: Request, res: Response) => {
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
