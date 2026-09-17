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
const auth_1 = require("../middleware/auth");
const router = (0, express_1.Router)();
const db = admin.firestore();
/**
 * PUT /v1/medical-card
 * Save medical card info (blood type, allergies, meds, conditions, insurance, emergency contacts).
 * This is the user's emergency medical profile visible on lock screen.
 */
router.put("/", auth_1.authMiddleware, async (req, res) => {
    const uid = req.uid;
    const { bloodType, allergies, medications, conditions, insuranceProvider, insurancePolicyNumber, emergencyNote, organDonor, weight, height, } = req.body;
    try {
        await db
            .collection("medical_cards")
            .doc(uid)
            .set({
            userId: uid,
            bloodType: bloodType || null,
            allergies: allergies || [],
            medications: medications || [],
            conditions: conditions || [],
            insuranceProvider: insuranceProvider || null,
            insurancePolicyNumber: insurancePolicyNumber || null,
            emergencyNote: emergencyNote || null,
            organDonor: organDonor ?? false,
            weight: weight || null,
            height: height || null,
            updatedAt: admin.firestore.Timestamp.now(),
        }, { merge: true });
        res.json({ success: true });
    }
    catch (error) {
        console.error("[MedicalCard] save error:", error);
        res.status(500).json({ error: "Failed to save medical card" });
    }
});
/**
 * GET /v1/medical-card
 * Get own medical card.
 */
router.get("/", auth_1.authMiddleware, async (req, res) => {
    const uid = req.uid;
    try {
        const doc = await db.collection("medical_cards").doc(uid).get();
        if (!doc.exists) {
            res.json(null);
            return;
        }
        const data = doc.data();
        res.json({
            bloodType: data.bloodType,
            allergies: data.allergies,
            medications: data.medications,
            conditions: data.conditions,
            insuranceProvider: data.insuranceProvider,
            insurancePolicyNumber: data.insurancePolicyNumber,
            emergencyNote: data.emergencyNote,
            organDonor: data.organDonor,
            weight: data.weight,
            height: data.height,
        });
    }
    catch (error) {
        console.error("[MedicalCard] get error:", error);
        res.status(500).json({ error: "Failed to get medical card" });
    }
});
/**
 * GET /v1/medical-card/share/:token
 * Public endpoint: access medical card via share token (no auth).
 * For first responders to see critical info without unlocking the phone.
 */
router.get("/share/:token", async (req, res) => {
    const { token } = req.params;
    try {
        const shareDoc = await db
            .collection("medical_card_shares")
            .doc(token)
            .get();
        if (!shareDoc.exists) {
            res.status(404).json({ error: "Share link not found" });
            return;
        }
        const shareData = shareDoc.data();
        if (shareData.expiresAt.toDate() < new Date()) {
            res.status(410).json({ error: "Share link expired" });
            return;
        }
        const userId = shareData.userId;
        const [cardDoc, userDoc] = await Promise.all([
            db.collection("medical_cards").doc(userId).get(),
            db.collection("users").doc(userId).get(),
        ]);
        if (!cardDoc.exists) {
            res.status(404).json({ error: "Medical card not found" });
            return;
        }
        const card = cardDoc.data();
        const user = userDoc.exists ? userDoc.data() : {};
        // Get emergency contacts
        const contactsDoc = await db
            .collection("emergency_contacts")
            .doc(userId)
            .get();
        const contacts = contactsDoc.exists
            ? contactsDoc.data().contacts || []
            : [];
        res.json({
            name: user.displayName || "Unknown",
            bloodType: card.bloodType,
            allergies: card.allergies,
            medications: card.medications,
            conditions: card.conditions,
            insuranceProvider: card.insuranceProvider,
            insurancePolicyNumber: card.insurancePolicyNumber,
            emergencyNote: card.emergencyNote,
            organDonor: card.organDonor,
            emergencyContacts: contacts.map((c) => ({
                name: c.name,
                phone: c.phone,
                relationship: c.relationship,
            })),
        });
    }
    catch (error) {
        console.error("[MedicalCard] share access error:", error);
        res.status(500).json({ error: "Failed to access shared medical card" });
    }
});
/**
 * POST /v1/medical-card/share
 * Create a share token for the medical card.
 */
router.post("/share", auth_1.authMiddleware, async (req, res) => {
    const uid = req.uid;
    try {
        const token = Math.random().toString(36).substring(2) +
            Math.random().toString(36).substring(2);
        const expiresAt = new Date(Date.now() + 365 * 24 * 60 * 60 * 1000); // 1 year
        await db.collection("medical_card_shares").doc(token).set({
            userId: uid,
            createdAt: admin.firestore.Timestamp.now(),
            expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
        });
        res.json({ token, expiresAt: expiresAt.toISOString() });
    }
    catch (error) {
        console.error("[MedicalCard] share create error:", error);
        res.status(500).json({ error: "Failed to create share link" });
    }
});
exports.default = router;
//# sourceMappingURL=medicalCard.js.map