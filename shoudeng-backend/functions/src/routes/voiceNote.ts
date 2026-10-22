import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import { authMiddleware } from "../middleware/auth";
import { createRateLimiter, RATE_LIMITS } from "../middleware/rateLimit";
import { v4 as uuidv4 } from "uuid";

const router = Router();
const db = admin.firestore();

router.use(authMiddleware);

/**
 * POST /v1/sos/:sosId/voice-notes
 * Submit a voice note transcript for an active SOS event.
 * Audio is transcribed on-device; only text + metadata are sent.
 */
router.post("/:sosId/voice-notes", createRateLimiter(RATE_LIMITS.general), async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { sosId } = req.params;
  const { transcript, duration, keywords, senderRole } = req.body;

  if (!sosId) {
    res.status(400).json({ error: "sosId is required" });
    return;
  }

  try {
    // Verify SOS event exists and caller is authorized
    const sosRef = db.collection("sos_events").doc(sosId);
    const sosDoc = await sosRef.get();

    if (!sosDoc.exists) {
      res.status(404).json({ error: "SOS event not found" });
      return;
    }

    const sosData = sosDoc.data()!;

    // Check authorization: must be the protected person or a linked guardian
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

    const noteId = uuidv4();
    const now = admin.firestore.Timestamp.now();

    // Store voice note as a subcollection of the SOS event
    await sosRef.collection("voice_notes").doc(noteId).set({
      senderId: uid,
      senderRole: senderRole || (isProtected ? "protected" : "guardian"),
      transcript: transcript || "",
      duration: duration || 0,
      keywords: keywords || [],
      createdAt: now,
    });

    // Add timeline entry
    const senderDoc = await db.collection("users").doc(uid).get();
    const senderName = senderDoc.exists ? senderDoc.data()!.displayName : "Unknown";

    await db.collection("timeline_entries").add({
      userId: sosData.protectedPersonId,
      timestamp: now,
      type: "voiceNote",
      description: `${senderName}发送了语音消息`,
      detail: transcript ? transcript.substring(0, 100) : null,
    });

    res.status(201).json({
      noteId,
      createdAt: now.toDate().toISOString(),
    });
  } catch (error) {
    console.error("[VoiceNote] create error:", error);
    res.status(500).json({ error: "Failed to save voice note" });
  }
});

/**
 * GET /v1/sos/:sosId/voice-notes
 * List voice notes for an SOS event.
 */
router.get("/:sosId/voice-notes", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { sosId } = req.params;

  try {
    // Verify authorization
    const sosRef = db.collection("sos_events").doc(sosId);
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

    const notesSnap = await sosRef
      .collection("voice_notes")
      .orderBy("createdAt", "asc")
      .limit(50)
      .get();

    const notes = notesSnap.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
      createdAt: doc.data().createdAt?.toDate().toISOString(),
    }));

    res.json({ notes });
  } catch (error) {
    console.error("[VoiceNote] list error:", error);
    res.status(500).json({ error: "Failed to fetch voice notes" });
  }
});

export default router;
