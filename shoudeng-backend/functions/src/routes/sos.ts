import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import { authMiddleware } from "../middleware/auth";
import { createRateLimiter, RATE_LIMITS } from "../middleware/rateLimit";
import { sendSOSResolvedNotification, sendSOSEndedByPersonNotification, sendSOSRouteNotification } from "../services/fcm";
import { parseRoute, activeGuardianIds } from "../services/sosTracking";
import {
  acknowledgeSOS,
  activeSOSDoc,
  RESOLUTIONS,
  Resolution,
  sosStatus,
} from "../services/escalation";
import { createSOSEvent } from "../services/sosTrigger";

/**
 * SOS routes. This router is mounted at both /v1/sos and /v1 (for the legacy
 * /v1/voice-call path), so auth is applied PER ROUTE — a router-level
 * `router.use(authMiddleware)` would run for every later /v1 route (Twilio
 * callbacks, public share links) and answer them 401.
 *
 * SOS trigger / resolve / acknowledge never share a rate-limit bucket with
 * anything else.
 */
const router = Router();
const db = admin.firestore();

/**
 * POST /v1/sos/trigger
 * Trigger an SOS event from the protected person's device.
 * Creates a Firestore document which triggers the escalation state machine.
 * Body: { protectedPersonId, triggerMethod?, latitude?, longitude?, batteryLevel?,
 *         clientSOSId?, clientTriggeredAt? }
 */
router.post("/trigger", authMiddleware, createRateLimiter(RATE_LIMITS.sosTrigger), async (req: Request, res: Response) => {
  const {
    protectedPersonId,
    triggerMethod,
    latitude,
    longitude,
    batteryLevel,
    clientSOSId,
    clientTriggeredAt,
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

  try {
    const result = await createSOSEvent({
      personId: protectedPersonId,
      triggerMethod, latitude, longitude, batteryLevel, clientSOSId, clientTriggeredAt,
    });
    if (!result.created) {
      res.json({ sosEventId: result.sosEventId, escalationState: result.escalationState, message: "SOS already active" });
      return;
    }
    res.status(201).json({ sosEventId: result.sosEventId, escalationState: "initiated" });
  } catch (error) {
    console.error("[SOS] trigger error:", error);
    res.status(500).json({ error: "Failed to trigger SOS" });
  }
});

/**
 * GET /v1/sos/active
 * The caller's own unresolved SOS with real delivery / escalation state
 * (drives SOSActiveView), or { active: false }.
 */
router.get("/active", authMiddleware, async (req: Request, res: Response) => {
  try {
    const doc = await activeSOSDoc(req.uid!);
    if (!doc) {
      res.json({ active: false, sos: null });
      return;
    }
    res.json({ active: true, sos: await sosStatus(doc) });
  } catch (error) {
    console.error("[SOS] active error:", error);
    res.status(500).json({ error: "Failed to load SOS" });
  }
});

/**
 * POST /v1/sos/acknowledge  { sosEventId }
 * A guardian says "I've got it": freezes the escalation (no more pushes, SMS or
 * calls), tells the other guardians and the protected person. Idempotent.
 * Closing the SOS ("Mom is safe") is the separate /resolve.
 */
router.post("/acknowledge", authMiddleware, async (req: Request, res: Response) => {
  const { sosEventId } = req.body;
  if (typeof sosEventId !== "string" || !sosEventId) {
    res.status(400).json({ error: "sosEventId is required" });
    return;
  }
  try {
    const r = await acknowledgeSOS(sosEventId, req.uid!, "app");
    switch (r.status) {
      case "acknowledged":
        res.json({ success: true, acknowledgedBy: r.acknowledgedBy, alreadyAcknowledged: r.alreadyAcknowledged });
        return;
      case "not_found":
        res.status(404).json({ error: "SOS event not found" });
        return;
      case "resolved":
        res.status(409).json({ error: "SOS already resolved" });
        return;
      case "forbidden":
        res.status(403).json({ error: "Only an active guardian can acknowledge this SOS" });
        return;
    }
  } catch (error) {
    console.error("[SOS] acknowledge error:", error);
    res.status(500).json({ error: "Failed to acknowledge SOS" });
  }
});

/**
 * POST /v1/sos/resolve
 * Close an active SOS ("Mom is safe" by a guardian, or the person cancelling).
 * Body: { sosEventId, resolution, clientTriggeredAt? }
 *
 * `sosEventId` may be the device-local id of an SOS created while offline. It
 * only maps to a server SOS that recorded that same client id — never to
 * "whatever SOS is active now", so a stale resolve replayed from the offline
 * queue cannot close a newer, real emergency.
 */
router.post("/resolve", authMiddleware, async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { sosEventId, resolution } = req.body;

  if (typeof sosEventId !== "string" || !sosEventId || typeof resolution !== "string") {
    res.status(400).json({ error: "sosEventId and resolution are required" });
    return;
  }
  if (!RESOLUTIONS.includes(resolution as Resolution)) {
    res.status(400).json({ error: `resolution must be one of ${RESOLUTIONS.join(", ")}` });
    return;
  }

  try {
    let sosRef = db.collection("sos_events").doc(sosEventId);
    let sosDoc = await sosRef.get();

    if (!sosDoc.exists) {
      const byClientId = await db
        .collection("sos_events")
        .where("protectedPersonId", "==", uid)
        .where("clientSOSIds", "array-contains", sosEventId)
        .limit(1)
        .get();
      if (byClientId.empty) {
        res.status(404).json({ error: "SOS event not found" });
        return;
      }
      sosRef = byClientId.docs[0].ref;
      sosDoc = byClientId.docs[0];
    }

    const sosData = sosDoc.data()!;
    if (sosData.resolvedAt) {
      res.status(409).json({ error: "SOS already resolved" });
      return;
    }

    // Caller must be the protected person or an active guardian
    const isProtected = sosData.protectedPersonId === uid;
    let isGuardian = false;
    if (!isProtected) {
      const linkDoc = await db.collection("guardian_links").doc(`${uid}_${sosData.protectedPersonId}`).get();
      isGuardian = linkDoc.exists && linkDoc.data()?.status === "active";
    }
    if (!isProtected && !isGuardian) {
      res.status(403).json({ error: "Not authorized to resolve this SOS event" });
      return;
    }
    if (resolution === "protectedCancelled" && !isProtected) {
      res.status(400).json({ error: "Only the protected person can cancel their SOS" });
      return;
    }

    const now = admin.firestore.Timestamp.now();
    await sosRef.update({
      escalationState: "resolved",
      escalationNextStep: null,
      escalationNextAt: null,
      resolvedAt: now,
      resolvedBy: uid,
      resolution,
    });

    await db.collection("timeline_entries").add({
      userId: sosData.protectedPersonId,
      timestamp: now,
      type: "sosResolved",
      description: `SOS resolved (${resolution})`,
      detail: null,
    });

    // The person ended it themselves: tell the family she is safe
    if (isProtected) {
      const name = (await db.collection("users").doc(uid).get()).data()?.displayName ?? "";
      const guardians = await activeGuardianIds(uid);
      await Promise.all(guardians.map((g) =>
        sendSOSEndedByPersonNotification(g, name, sosRef.id, uid).catch((e) => console.warn("[SOS] safe notice failed:", e))));
    }

    // Tell the protected person a guardian closed it
    if (!isProtected) {
      const resolverDoc = await db.collection("users").doc(uid).get();
      await sendSOSResolvedNotification(
        sosData.protectedPersonId,
        resolverDoc.exists ? resolverDoc.data()!.displayName : "Guardian"
      );
    }

    res.json({ success: true, sosEventId: sosRef.id });
  } catch (error) {
    console.error("[SOS] resolve error:", error);
    res.status(500).json({ error: "Failed to resolve SOS" });
  }
});

/**
 * POST /v1/sos/route
 * The person shares where they are heading during their SOS ("hospital, on foot").
 * Body: { name, latitude, longitude, mode: walking | driving | transit }
 * Stored on the open SOS (guardians see it on the map) and pushed to the guardians.
 */
router.post("/route", authMiddleware, async (req: Request, res: Response) => {
  const uid = req.uid!;
  const route = parseRoute(req.body ?? {});
  if (!route) {
    res.status(400).json({ error: "name, latitude and longitude are required" });
    return;
  }
  try {
    const doc = await activeSOSDoc(uid);
    if (!doc) {
      res.status(404).json({ error: "No active SOS" });
      return;
    }
    await doc.ref.update({ route });
    const name = (await db.collection("users").doc(uid).get()).data()?.displayName ?? "";
    const guardians = await activeGuardianIds(uid);
    await Promise.all(guardians.map((g) =>
      sendSOSRouteNotification(g, name, route.name, route.mode, doc.id, uid).catch((e) => console.warn("[SOS] route notice failed:", e))));
    res.json({ success: true, sosEventId: doc.id, route });
  } catch (error) {
    console.error("[SOS] route error:", error);
    res.status(500).json({ error: "Failed to share route" });
  }
});

/**
 * POST /v1/voice-call
 * Ask the server to call one of this SOS's guardians now.
 */
router.post("/voice-call", authMiddleware, createRateLimiter(RATE_LIMITS.voiceCall), async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { guardianId, sosEventId } = req.body;

  if (!guardianId || !sosEventId) {
    res.status(400).json({ error: "guardianId and sosEventId are required" });
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
    const personId = sosData.protectedPersonId;

    // Caller: the protected person or one of their active guardians
    const isProtected = personId === uid;
    if (!isProtected) {
      const callerLink = await db.collection("guardian_links").doc(`${uid}_${personId}`).get();
      if (!callerLink.exists || callerLink.data()?.status !== "active") {
        res.status(403).json({ error: "Not authorized for this SOS event" });
        return;
      }
    }
    // Callee: must be an active guardian of THIS SOS's person — never an arbitrary user
    const targetLink = await db.collection("guardian_links").doc(`${guardianId}_${personId}`).get();
    if (!targetLink.exists || targetLink.data()?.status !== "active") {
      res.status(403).json({ error: "guardianId is not an active guardian of this person" });
      return;
    }

    // Fair use: calls count against the person's monthly minutes
    const { reserveVoiceMinute, releaseVoiceMinute, FAIR_USE } = await import("../services/fairUse");
    const reservation = await reserveVoiceMinute(personId);
    if (!reservation) {
      res.status(429).json({
        error: "This month's SOS call minutes are used up; guardians are still notified by push",
        code: "FAIR_USE_LIMIT",
        voiceMinutesPerMonth: FAIR_USE.voiceMinutesPerMonth,
      });
      return;
    }

    const { initiateVoiceCall } = await import("../services/twilio");
    const personDoc = await db.collection("users").doc(personId).get();
    const callSid = await initiateVoiceCall(guardianId, sosEventId, personDoc.data()?.displayName || "", {
      round: 0,
      isLastRound: false,
      fairUse: reservation,
    });
    if (!callSid) await releaseVoiceMinute(reservation);

    if (callSid) {
      await sosRef.update({
        escalationLog: admin.firestore.FieldValue.arrayUnion({
          hop: 3,
          round: 0,
          targetId: guardianId,
          channel: "voice",
          sentAt: admin.firestore.Timestamp.now(),
          deliveredAt: null,
          readAt: null,
          respondedAt: null,
          response: null,
          callSid,
          requestedBy: uid,
        }),
      });
    }

    res.json({ success: !!callSid, callSid });
  } catch (error) {
    console.error("[SOS] voice-call error:", error);
    res.status(500).json({ error: "Failed to initiate voice call" });
  }
});

export default router;
