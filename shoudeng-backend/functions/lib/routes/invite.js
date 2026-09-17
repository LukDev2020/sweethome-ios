"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const admin = __importStar(require("firebase-admin"));
const crypto = __importStar(require("crypto"));
const auth_1 = require("../middleware/auth");
const bigquery_1 = require("../services/bigquery");
const router = (0, express_1.Router)();
const db = admin.firestore();
router.use(auth_1.authMiddleware);
/**
 * POST /v1/invite/create
 * Create an invite code for linking guardian ↔ protected person.
 */
router.post("/create", async (req, res) => {
    const uid = req.uid;
    const { role } = req.body;
    try {
        // Generate 6-char alphanumeric code
        const code = crypto.randomBytes(3).toString("hex").toUpperCase();
        const now = admin.firestore.Timestamp.now();
        const expiresAt = admin.firestore.Timestamp.fromDate(new Date(Date.now() + 24 * 60 * 60 * 1000) // 24 hours
        );
        const inviteDoc = {
            code,
            createdBy: uid,
            role: role || "guardian",
            acceptedBy: null,
            status: "pending",
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
    }
    catch (error) {
        console.error("[Invite] create error:", error);
        res.status(500).json({ error: "Failed to create invite" });
    }
});
/**
 * POST /v1/invite/accept
 * Accept an invite code to establish guardian ↔ protected relationship.
 */
router.post("/accept", async (req, res) => {
    const uid = req.uid;
    const { inviteId, code } = req.body;
    try {
        // Find invite by ID or code (outside transaction for query support)
        let inviteRef;
        if (inviteId) {
            inviteRef = db.collection("invites").doc(inviteId);
        }
        else if (code) {
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
        }
        else {
            res.status(400).json({ error: "inviteId or code is required" });
            return;
        }
        // Run accept logic inside a transaction to prevent race conditions
        const result = await db.runTransaction(async (transaction) => {
            const inviteDoc = await transaction.get(inviteRef);
            if (!inviteDoc.exists) {
                throw new Error("NOT_FOUND");
            }
            const inviteData = inviteDoc.data();
            // Check expiry
            if (inviteData.expiresAt.toDate() < new Date()) {
                transaction.update(inviteRef, { status: "expired" });
                throw new Error("EXPIRED");
            }
            if (inviteData.status !== "pending") {
                throw new Error("ALREADY_USED");
            }
            // Cannot accept your own invite
            if (inviteData.createdBy === uid) {
                throw new Error("SELF_ACCEPT");
            }
            // Determine who is guardian and who is protected
            const creatorRef = db.collection("users").doc(inviteData.createdBy);
            const acceptorRef = db.collection("users").doc(uid);
            const [creatorDoc, acceptorDoc] = await Promise.all([
                transaction.get(creatorRef),
                transaction.get(acceptorRef),
            ]);
            if (!creatorDoc.exists || !acceptorDoc.exists) {
                throw new Error("USER_NOT_FOUND");
            }
            const creatorRole = creatorDoc.data().role;
            let guardianId;
            let protectedPersonId;
            if (creatorRole === "protected") {
                protectedPersonId = inviteData.createdBy;
                guardianId = uid;
            }
            else {
                guardianId = inviteData.createdBy;
                protectedPersonId = uid;
            }
            const now = admin.firestore.Timestamp.now();
            const linkId = `${guardianId}_${protectedPersonId}`;
            const linkRef = db.collection("guardian_links").doc(linkId);
            // Atomically create link + mark invite as accepted
            transaction.set(linkRef, {
                guardianId,
                protectedPersonId,
                status: "active",
                createdAt: now,
                acceptedAt: now,
                revokedAt: null,
                protectionLayers: ["location", "heartbeat", "sos"],
            });
            transaction.update(inviteRef, {
                status: "accepted",
                acceptedBy: uid,
            });
            return { guardianId, protectedPersonId, linkId };
        });
        // Log consent (outside transaction — non-critical)
        await (0, bigquery_1.insertConsentAudit)({
            userId: result.protectedPersonId,
            consentType: "guardian_link",
            action: "granted",
            grantedTo: result.guardianId,
            detail: `Guardian link established via invite ${inviteRef.id}`,
        });
        res.json({
            success: true,
            ...result,
        });
    }
    catch (error) {
        if (error.message === "NOT_FOUND") {
            res.status(404).json({ error: "Invite not found" });
        }
        else if (error.message === "EXPIRED") {
            res.status(410).json({ error: "Invite has expired" });
        }
        else if (error.message === "ALREADY_USED") {
            res.status(409).json({ error: "Invite already used" });
        }
        else if (error.message === "SELF_ACCEPT") {
            res.status(400).json({ error: "Cannot accept your own invite" });
        }
        else if (error.message === "USER_NOT_FOUND") {
            res.status(404).json({ error: "User not found" });
        }
        else {
            console.error("[Invite] accept error:", error);
            res.status(500).json({ error: "Failed to accept invite" });
        }
    }
});
exports.default = router;
//# sourceMappingURL=invite.js.map