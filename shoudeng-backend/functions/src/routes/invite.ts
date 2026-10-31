import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import * as crypto from "crypto";
import { authMiddleware } from "../middleware/auth";
import { createRateLimiter, RATE_LIMITS } from "../middleware/rateLimit";
import { insertConsentAudit } from "../services/bigquery";
import { getSubscription, PLANS, PlanId } from "../services/payment";

const router = Router();
const db = admin.firestore();

router.use(authMiddleware);

/**
 * What the person who created the invite will become once it is accepted:
 *  - "protected": the inviter wants to be protected; the acceptor becomes their guardian.
 *  - "guardian":  the inviter wants to guard the acceptor; the acceptor becomes protected.
 * The account roles of the two people no longer matter — the invite carries the direction.
 */
export type InviterRole = "protected" | "guardian";

function isInviterRole(v: unknown): v is InviterRole {
  return v === "protected" || v === "guardian";
}

/** Machine-readable error codes the app maps to specific messages. */
export type InviteErrorCode =
  | "NOT_FOUND"
  | "INVITE_EXPIRED"
  | "INVITE_USED"
  | "SELF_ACCEPT"
  | "PLAN_LIMIT"
  | "USER_NOT_FOUND";

const INVITE_ERRORS: Record<InviteErrorCode, { status: number; error: string }> = {
  NOT_FOUND: { status: 404, error: "Invalid or expired invite code" },
  INVITE_EXPIRED: { status: 410, error: "Invite has expired" },
  INVITE_USED: { status: 409, error: "Invite already used" },
  SELF_ACCEPT: { status: 400, error: "Cannot accept your own invite" },
  PLAN_LIMIT: { status: 403, error: "Guardian's plan limit reached. Upgrade to add more protected persons." },
  USER_NOT_FOUND: { status: 404, error: "User not found" },
};

class InviteError extends Error {
  constructor(public readonly code: InviteErrorCode, public readonly extra: Record<string, unknown> = {}) {
    super(code);
  }
}

function sendInviteError(res: Response, err: InviteError) {
  const { status, error } = INVITE_ERRORS[err.code];
  res.status(status).json({ error, code: err.code, ...err.extra });
}

function normalizeCode(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const code = raw.trim().toUpperCase();
  return /^[A-Z0-9]{4,12}$/.test(code) ? code : null;
}

/**
 * Codes are short and random, so an old (accepted / expired) invite can share a
 * code with a live one. Prefer the pending invite, then the newest.
 */
async function findInviteByCode(code: string): Promise<FirebaseFirestore.QueryDocumentSnapshot | null> {
  const snapshot = await db.collection("invites").where("code", "==", code).get();
  if (snapshot.empty) return null;
  const millis = (d: FirebaseFirestore.QueryDocumentSnapshot) => d.get("createdAt")?.toMillis?.() ?? 0;
  const docs = [...snapshot.docs].sort((a, b) => {
    const pa = a.get("status") === "pending" ? 0 : 1;
    const pb = b.get("status") === "pending" ? 0 : 1;
    return pa - pb || millis(b) - millis(a);
  });
  return docs[0];
}

/** "pending" | "accepted" | "expired", taking the expiry time into account. */
function effectiveStatus(invite: FirebaseFirestore.DocumentData): "pending" | "accepted" | "expired" {
  if (invite.status === "accepted") return "accepted";
  if (invite.status === "expired") return "expired";
  if (invite.expiresAt?.toDate && invite.expiresAt.toDate() < new Date()) return "expired";
  return "pending";
}

/** Direction of an invite. Invites made before the field existed use the creator's current role. */
function inviterRoleOf(invite: FirebaseFirestore.DocumentData, creator: FirebaseFirestore.DocumentData | undefined): InviterRole {
  if (isInviterRole(invite.inviterRole)) return invite.inviterRole;
  if (isInviterRole(creator?.role)) return creator!.role;
  return "guardian";
}

async function hasActiveLinks(uid: string): Promise<boolean> {
  const [asGuardian, asProtected] = await Promise.all([
    db.collection("guardian_links").where("guardianId", "==", uid).where("status", "==", "active").limit(1).get(),
    db.collection("guardian_links").where("protectedPersonId", "==", uid).where("status", "==", "active").limit(1).get(),
  ]);
  return !asGuardian.empty || !asProtected.empty;
}

/**
 * POST /v1/invite/create
 * Create an invite code for linking guardian ↔ protected person.
 * Body: { inviterRole?: "protected" | "guardian" } — what the inviter will become.
 * Older apps don't send it; then the creator's current account role decides.
 */
router.post("/create", async (req: Request, res: Response) => {
  const uid = req.uid!;

  try {
    let inviterRole: InviterRole;
    if (isInviterRole(req.body?.inviterRole)) {
      inviterRole = req.body.inviterRole;
    } else {
      const creator = await db.collection("users").doc(uid).get();
      const accountRole = creator.exists ? creator.data()!.role : undefined;
      inviterRole = isInviterRole(accountRole) ? accountRole
        : isInviterRole(req.body?.role) ? req.body.role : "guardian";
    }

    // Generate 6-char alphanumeric code
    const code = crypto.randomBytes(3).toString("hex").toUpperCase();

    const now = admin.firestore.Timestamp.now();
    const expiresAt = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() + 24 * 60 * 60 * 1000) // 24 hours
    );

    const inviteDoc = {
      code,
      createdBy: uid,
      inviterRole,
      // Legacy field, kept for anything still reading it
      role: inviterRole,
      acceptedBy: null,
      status: "pending" as const,
      createdAt: now,
      expiresAt,
    };

    const ref = await db.collection("invites").add(inviteDoc);

    res.status(201).json({
      inviteId: ref.id,
      code,
      inviterRole,
      expiresAt: expiresAt.toDate().toISOString(),
      status: "pending",
    });
  } catch (error) {
    console.error("[Invite] create error:", error);
    res.status(500).json({ error: "Failed to create invite" });
  }
});

/**
 * GET /v1/invite/preview?code=XXXXXX
 * Read-only: who sent the invite and what accepting it means, for the
 * confirmation screen. Never changes any state.
 */
router.get("/preview", createRateLimiter(RATE_LIMITS.invite), async (req: Request, res: Response) => {
  const uid = req.uid!;
  const code = normalizeCode(req.query.code);

  try {
    if (!code) throw new InviteError("NOT_FOUND");
    const inviteDoc = await findInviteByCode(code);
    if (!inviteDoc) throw new InviteError("NOT_FOUND");
    const invite = inviteDoc.data();

    const creatorDoc = await db.collection("users").doc(invite.createdBy).get();
    if (!creatorDoc.exists) throw new InviteError("NOT_FOUND");
    const creator = creatorDoc.data()!;

    const status = effectiveStatus(invite);
    // The inviter's name is only shown for an invite that can still be accepted
    const showInviter = status === "pending";
    const displayName: string = creator.displayName ?? "";

    res.json({
      code,
      inviterName: showInviter ? displayName : null,
      avatarInitial: showInviter ? (creator.avatarInitial ?? displayName.charAt(0)) : null,
      inviterRole: inviterRoleOf(invite, creator),
      expiresAt: invite.expiresAt?.toDate ? invite.expiresAt.toDate().toISOString() : null,
      status,
      isOwnInvite: invite.createdBy === uid,
    });
  } catch (error: any) {
    if (error instanceof InviteError) {
      sendInviteError(res, error);
    } else {
      console.error("[Invite] preview error:", error);
      res.status(500).json({ error: "Failed to load invite" });
    }
  }
});

/**
 * POST /v1/invite/accept
 * Accept an invite code to establish guardian ↔ protected relationship.
 * The invite's direction decides who guards whom; account roles don't matter.
 */
router.post("/accept", createRateLimiter(RATE_LIMITS.invite), async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { inviteId, publicKey } = req.body;
  // The guardian app shows an explicit consent screen for SOS critical
  // alerts before accepting; record that choice.
  const criticalAlertConsent = req.body?.criticalAlertConsent === true;

  try {
    // Find invite by ID or code (outside transaction for query support)
    let inviteRef: FirebaseFirestore.DocumentReference;

    if (inviteId) {
      inviteRef = db.collection("invites").doc(String(inviteId));
    } else if (req.body?.code !== undefined) {
      const code = normalizeCode(req.body.code);
      const found = code ? await findInviteByCode(code) : null;
      if (!found) throw new InviteError("NOT_FOUND");
      inviteRef = found.ref;
    } else {
      res.status(400).json({ error: "inviteId or code is required" });
      return;
    }

    // Run accept logic inside a transaction to prevent race conditions
    const result = await db.runTransaction(async (transaction) => {
      const inviteDoc = await transaction.get(inviteRef);
      if (!inviteDoc.exists) {
        throw new InviteError("NOT_FOUND");
      }
      const inviteData = inviteDoc.data()!;

      const status = effectiveStatus(inviteData);
      if (status === "accepted") throw new InviteError("INVITE_USED");
      if (status === "expired") throw new InviteError("INVITE_EXPIRED");

      // Cannot accept your own invite
      if (inviteData.createdBy === uid) {
        throw new InviteError("SELF_ACCEPT");
      }

      const creatorRef = db.collection("users").doc(inviteData.createdBy);
      const acceptorRef = db.collection("users").doc(uid);
      const [creatorDoc, acceptorDoc] = await Promise.all([
        transaction.get(creatorRef),
        transaction.get(acceptorRef),
      ]);

      if (!creatorDoc.exists) throw new InviteError("NOT_FOUND");
      if (!acceptorDoc.exists) throw new InviteError("USER_NOT_FOUND");

      // The invite says who guards whom
      const inviterRole = inviterRoleOf(inviteData, creatorDoc.data());
      const guardianId = inviterRole === "protected" ? uid : inviteData.createdBy;
      const protectedPersonId = inviterRole === "protected" ? inviteData.createdBy : uid;
      const acceptorRole: InviterRole = uid === guardianId ? "guardian" : "protected";

      const now = admin.firestore.Timestamp.now();
      const linkId = `${guardianId}_${protectedPersonId}`;
      const linkRef = db.collection("guardian_links").doc(linkId);

      // Check guardian's plan capacity (protected person limit). Re-linking the
      // same pair doesn't take another seat.
      const guardianSub = await getSubscription(guardianId);
      const guardianPlan = PLANS[guardianSub.planId as PlanId] || PLANS.free;
      const maxProtected = (guardianPlan as any).maxProtected ?? 1;

      if (maxProtected >= 0) {
        const existingLinks = await db
          .collection("guardian_links")
          .where("guardianId", "==", guardianId)
          .where("status", "==", "active")
          .get();
        const used = existingLinks.docs.filter((d) => d.id !== linkId).length;
        if (used >= maxProtected) {
          throw new InviteError("PLAN_LIMIT", {
            upgrade: true,
            maxProtected,
            guardianIsYou: guardianId === uid,
          });
        }
      }

      // Someone joining their first family opens the app on their side of the
      // link. Anyone who already has links keeps their home view.
      const acceptorUpdates: Record<string, unknown> = {};
      const setsHomeRole = !(await hasActiveLinks(uid)) && acceptorDoc.data()!.role !== acceptorRole;
      if (setsHomeRole) acceptorUpdates.role = acceptorRole;
      // Store E2E public key on user doc if provided
      if (publicKey) acceptorUpdates.publicKey = publicKey;
      if (Object.keys(acceptorUpdates).length) {
        transaction.update(acceptorRef, acceptorUpdates);
      }

      // Atomically create link + mark invite as accepted
      transaction.set(linkRef, {
        guardianId,
        protectedPersonId,
        status: "active",
        createdAt: now,
        acceptedAt: now,
        revokedAt: null,
        protectionLayers: ["location", "heartbeat", "sos"],
        ...(publicKey && { acceptorPublicKey: publicKey }),
      });

      transaction.update(inviteRef, {
        status: "accepted",
        acceptedBy: uid,
      });

      return { guardianId, protectedPersonId, linkId, acceptorRole };
    });

    // Log consent (outside transaction — non-critical)
    await insertConsentAudit({
      userId: result.protectedPersonId,
      consentType: "guardian_link",
      action: "granted",
      grantedTo: result.guardianId,
      detail: `Guardian link established via invite ${inviteRef.id}`,
    });

    // The guardian's own opt-in to receive SOS alerts as iOS Critical Alerts.
    if (uid === result.guardianId) {
      await db.collection("users").doc(uid).set(
        { notificationPrefs: { sosCriticalAlerts: criticalAlertConsent } },
        { merge: true }
      );
      await insertConsentAudit({
        userId: uid,
        consentType: "sos_critical_alerts",
        action: criticalAlertConsent ? "granted" : "declined",
        grantedTo: result.protectedPersonId,
        detail: `SOS critical alert consent at guardian link ${result.linkId}`,
      });
    }

    res.json({
      success: true,
      ...result,
    });
  } catch (error: any) {
    if (error instanceof InviteError) {
      sendInviteError(res, error);
    } else {
      console.error("[Invite] accept error:", error);
      res.status(500).json({ error: "Failed to accept invite" });
    }
  }
});

export default router;
