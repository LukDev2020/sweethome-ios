import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import { v4 as uuidv4 } from "uuid";
import { authMiddleware } from "../middleware/auth";
import { createRateLimiter, RATE_LIMITS } from "../middleware/rateLimit";
import { sendSOSResolvedNotification } from "../services/fcm";

const router = Router();
const db = admin.firestore();

router.use(authMiddleware);

/**
 * POST /v1/sos/trigger
 * Trigger an SOS event from the protected person's device.
 * Creates a Firestore document which triggers the onSOSCreated escalation chain.
 */
router.post("/trigger", async (req: Request, res: Response) => {
  const {
    protectedPersonId,
    triggerMethod,
    latitude,
    longitude,
    batteryLevel,
  } = req.body;

  if (!protectedPersonId) {
    res.status(400).json({ error: "protectedPersonId is required" });
    return;
  }

  // Only the protected person themselves can trigger their own SOS
  if (protectedPersonId !== req.uid) {
    res.status(403).json({ error: "Cannot trigger SOS for another user" });
    return;
  }

  const sosId = uuidv4();
  const now = admin.firestore.Timestamp.now();

  try {
    // Use transaction to prevent duplicate SOS events
    const existingEvent = await db.runTransaction(async (transaction) => {
      // Check for existing active SOS inside transaction
      const activeSnapshot = await db
        .collection("sos_events")
        .where("protectedPersonId", "==", protectedPersonId)
        .where("resolvedAt", "==", null)
        .limit(1)
        .get();

      if (!activeSnapshot.empty) {
        return {
          sosEventId: activeSnapshot.docs[0].id,
          escalationState: activeSnapshot.docs[0].data().escalationState,
        };
      }

      const sosDoc = {
        protectedPersonId,
        triggeredAt: now,
        triggerMethod: triggerMethod || "longPress",
        latitude: latitude || null,
        longitude: longitude || null,
        accuracy: null,
        batteryLevel: batteryLevel || null,
        escalationState: "initiated",
        resolvedAt: null,
        resolvedBy: null,
        resolution: null,
        escalationLog: [],
      };

      transaction.set(db.collection("sos_events").doc(sosId), sosDoc);
      return null;
    });

    if (existingEvent) {
      res.json({
        ...existingEvent,
        message: "SOS already active",
      });
      return;
    }

    // Add timeline entry
    const triggerLabels: Record<string, string> = {
      longPress: "长按",
      fallDetection: "摔倒检测",
      watchQuickAction: "手表快捷操作",
      bluetoothButton: "蓝牙按钮",
      duressPassword: "胁迫密码",
      voiceWakeWord: "语音唤醒",
    };
    const triggerLabel =
      triggerLabels[triggerMethod || "longPress"] || triggerMethod;

    await db.collection("timeline_entries").add({
      userId: protectedPersonId,
      timestamp: now,
      type: "sosTriggered",
      description: `触发紧急求助（${triggerLabel}）`,
      detail: null,
    });

    res.status(201).json({
      sosEventId: sosId,
      escalationState: "initiated",
    });
  } catch (error) {
    console.error("[SOS] trigger error:", error);
    res.status(500).json({ error: "Failed to trigger SOS" });
  }
});

/**
 * POST /v1/sos/resolve
 * Resolve an active SOS event (guardian "I've taken over" or protected person cancel).
 */
router.post("/resolve", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { sosEventId, resolution } = req.body;

  if (!sosEventId || !resolution) {
    res
      .status(400)
      .json({ error: "sosEventId and resolution are required" });
    return;
  }

  try {
    const sosRef = db.collection("sos_events").doc(sosEventId);
    const sosDoc = await sosRef.get();

    if (!sosDoc.exists) {
      res.status(404).json({ error: "SOS event not found" });
      return;
    }

    const sosData = sosDoc.data()!;
    if (sosData.resolvedAt) {
      res.status(409).json({ error: "SOS already resolved" });
      return;
    }

    // C2 fix: verify caller is the protected person or a linked guardian
    const isProtected = sosData.protectedPersonId === uid;
    let isGuardian = false;
    if (!isProtected) {
      const linkId = `${uid}_${sosData.protectedPersonId}`;
      const linkDoc = await db.collection("guardian_links").doc(linkId).get();
      isGuardian = linkDoc.exists && linkDoc.data()?.status === "active";
    }
    if (!isProtected && !isGuardian) {
      res.status(403).json({ error: "Not authorized to resolve this SOS event" });
      return;
    }

    const now = admin.firestore.Timestamp.now();

    await sosRef.update({
      escalationState: "resolved",
      resolvedAt: now,
      resolvedBy: uid,
      resolution,
    });

    // Add timeline entry
    const resolutionLabels: Record<string, string> = {
      guardianConfirmedSafe: "守护者确认安全",
      protectedCancelled: "取消了紧急求助",
      responderHandled: "专员已处理",
      falseAlarm: "误触",
      timeout: "超时自动解除",
    };
    const resolutionLabel = resolutionLabels[resolution] || resolution;

    await db.collection("timeline_entries").add({
      userId: sosData.protectedPersonId,
      timestamp: now,
      type: "sosResolved",
      description: resolutionLabel,
      detail: null,
    });

    // Notify the protected person that a guardian has taken over
    if (resolution === "guardianConfirmedSafe") {
      const resolverDoc = await db.collection("users").doc(uid).get();
      const resolverName = resolverDoc.exists
        ? resolverDoc.data()!.displayName
        : "守护者";
      await sendSOSResolvedNotification(
        sosData.protectedPersonId,
        resolverName
      );
    }

    res.json({ success: true });
  } catch (error) {
    console.error("[SOS] resolve error:", error);
    res.status(500).json({ error: "Failed to resolve SOS" });
  }
});

/**
 * POST /v1/voice-call
 * Request a voice call to a guardian as part of escalation.
 * Delegates to Twilio service.
 */
router.post("/voice-call", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { guardianId, sosEventId, protectedPersonName } = req.body;

  if (!guardianId || !sosEventId) {
    res
      .status(400)
      .json({ error: "guardianId and sosEventId are required" });
    return;
  }

  try {
    // C1 fix: verify caller is the SOS's protected person or a linked guardian
    const sosRef = db.collection("sos_events").doc(sosEventId);
    const sosDoc = await sosRef.get();
    if (!sosDoc.exists) {
      res.status(404).json({ error: "SOS event not found" });
      return;
    }
    const sosData = sosDoc.data()!;
    const isProtected = sosData.protectedPersonId === uid;
    let isGuardian = false;
    if (!isProtected) {
      const linkId = `${uid}_${sosData.protectedPersonId}`;
      const linkDoc = await db.collection("guardian_links").doc(linkId).get();
      isGuardian = linkDoc.exists && linkDoc.data()?.status === "active";
    }
    if (!isProtected && !isGuardian) {
      res.status(403).json({ error: "Not authorized for this SOS event" });
      return;
    }
    // Import dynamically to avoid initialization issues
    const { initiateVoiceCall } = await import("../services/twilio");

    const callbackUrl = `${req.protocol}://${req.get("host")}/v1/voice-callback`;

    const callSid = await initiateVoiceCall(
      guardianId,
      sosEventId,
      protectedPersonName || "被守护者",
      callbackUrl
    );

    // Update escalation log
    if (callSid) {
      const sosRef = db.collection("sos_events").doc(sosEventId);
      await sosRef.update({
        escalationState: "hop3_voiceCalling",
        escalationLog: admin.firestore.FieldValue.arrayUnion({
          hop: 3,
          targetId: guardianId,
          sentAt: admin.firestore.Timestamp.now(),
          deliveredAt: null,
          readAt: null,
          respondedAt: null,
          response: null,
          callSid,
        }),
      });
    }

    res.json({ success: true, callSid });
  } catch (error) {
    console.error("[SOS] voice-call error:", error);
    res.status(500).json({ error: "Failed to initiate voice call" });
  }
});

export default router;
