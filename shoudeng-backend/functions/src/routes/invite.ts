import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import * as crypto from "crypto";
import { authMiddleware } from "../middleware/auth";
import { insertConsentAudit } from "../services/bigquery";

const router = Router();
const db = admin.firestore();

router.use(authMiddleware);

/**
 * POST /v1/invite/create
 * Create an invite code for linking guardian ↔ protected person.
 */
router.post("/create", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { role } = req.body;

  try {
    // Generate 6-char alphanumeric code
    const code = crypto.randomBytes(3).toString("hex").toUpperCase();

    const now = admin.firestore.Timestamp.now();
    const expiresAt = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() + 24 * 60 * 60 * 1000) // 24 hours
    );

    const inviteDoc = {
      code,
      createdBy: uid,
      role: role || "guardian",
      acceptedBy: null,
      status: "pending" as const,
      createdAt: now,
      expiresAt,
    };

    const ref = await db.collection("invites").add(inviteDoc);

    res.status(201).json({
      inviteId: ref.id,
      code,
      expiresAt: expiresAt.toDate().toISOString(),
      status: "pending",
    });
  } catch (error) {
    console.error("[Invite] create error:", error);
    res.status(500).json({ error: "Failed to create invite" });
  }
});

/**
 * POST /v1/invite/accept
 * Accept an invite code to establish guardian ↔ protected relationship.
 */
router.post("/accept", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { inviteId, code } = req.body;

  try {
    // Find invite by ID or code
    let inviteRef: FirebaseFirestore.DocumentReference;
    let inviteData: FirebaseFirestore.DocumentData;

    if (inviteId) {
      inviteRef = db.collection("invites").doc(inviteId);
      const doc = await inviteRef.get();
      if (!doc.exists) {
        res.status(404).json({ error: "Invite not found" });
        return;
      }
      inviteData = doc.data()!;
    } else if (code) {
      const snapshot = await db
        .collection("invites")
        .where("code", "==", code.toUpperCase())
        .where("status", "==", "pending")
        .limit(1)
        .get();
      if (snapshot.empty) {
        res.status(404).json({ error: "Invalid or expired invite code" });
        return;
      }
      inviteRef = snapshot.docs[0].ref;
      inviteData = snapshot.docs[0].data();
    } else {
      res.status(400).json({ error: "inviteId or code is required" });
      return;
    }

    // Check expiry
    if (inviteData.expiresAt.toDate() < new Date()) {
      await inviteRef.update({ status: "expired" });
      res.status(410).json({ error: "Invite has expired" });
      return;
    }

    if (inviteData.status !== "pending") {
      res.status(409).json({ error: "Invite already used" });
      return;
    }

    // Cannot accept your own invite
    if (inviteData.createdBy === uid) {
      res.status(400).json({ error: "Cannot accept your own invite" });
      return;
    }

    // Determine who is guardian and who is protected
    const creatorDoc = await db
      .collection("users")
      .doc(inviteData.createdBy)
      .get();
    const acceptorDoc = await db.collection("users").doc(uid).get();

    if (!creatorDoc.exists || !acceptorDoc.exists) {
      res.status(404).json({ error: "User not found" });
      return;
    }

    const creatorRole = creatorDoc.data()!.role;
    let guardianId: string;
    let protectedPersonId: string;

    if (creatorRole === "protected") {
      protectedPersonId = inviteData.createdBy;
      guardianId = uid;
    } else {
      guardianId = inviteData.createdBy;
      protectedPersonId = uid;
    }

    const now = admin.firestore.Timestamp.now();

    // Create guardian link
    const linkId = `${guardianId}_${protectedPersonId}`;
    await db
      .collection("guardian_links")
      .doc(linkId)
      .set({
        guardianId,
        protectedPersonId,
        status: "active",
        createdAt: now,
        acceptedAt: now,
        revokedAt: null,
        protectionLayers: ["location", "heartbeat", "sos"],
      });

    // Update invite
    await inviteRef.update({
      status: "accepted",
      acceptedBy: uid,
    });

    // Log consent
    await insertConsentAudit({
      userId: protectedPersonId,
      consentType: "guardian_link",
      action: "granted",
      grantedTo: guardianId,
      detail: `Guardian link established via invite ${inviteRef.id}`,
    });

    res.json({
      success: true,
      guardianId,
      protectedPersonId,
      linkId,
    });
  } catch (error) {
    console.error("[Invite] accept error:", error);
    res.status(500).json({ error: "Failed to accept invite" });
  }
});

export default router;
