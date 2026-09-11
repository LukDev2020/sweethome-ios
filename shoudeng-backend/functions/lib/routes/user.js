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
// All user routes require authentication
router.use(auth_1.authMiddleware);
/**
 * GET /v1/user/me
 * Get current user's profile.
 */
router.get("/me", async (req, res) => {
    const uid = req.uid;
    try {
        const userDoc = await db.collection("users").doc(uid).get();
        if (!userDoc.exists) {
            res.status(404).json({ error: "User not found" });
            return;
        }
        const data = userDoc.data();
        res.json({
            id: uid,
            displayName: data.displayName,
            role: data.role,
            avatarInitial: data.avatarInitial,
            timeZone: data.timeZone,
            countryCode: data.countryCode,
            cityName: data.cityName,
            createdAt: data.createdAt.toDate().toISOString(),
        });
    }
    catch (error) {
        console.error("[User] get profile error:", error);
        res.status(500).json({ error: "Failed to fetch profile" });
    }
});
/**
 * PUT /v1/user/me
 * Update current user's profile.
 */
router.put("/me", async (req, res) => {
    const uid = req.uid;
    const { displayName, timeZone, cityName, countryCode } = req.body;
    const updates = {
        updatedAt: admin.firestore.Timestamp.now(),
    };
    if (displayName !== undefined) {
        updates.displayName = displayName;
        updates.avatarInitial = displayName.charAt(0);
    }
    if (timeZone !== undefined)
        updates.timeZone = timeZone;
    if (cityName !== undefined)
        updates.cityName = cityName;
    if (countryCode !== undefined)
        updates.countryCode = countryCode;
    try {
        await db.collection("users").doc(uid).update(updates);
        res.json({ success: true });
    }
    catch (error) {
        console.error("[User] update profile error:", error);
        res.status(500).json({ error: "Failed to update profile" });
    }
});
/**
 * POST /v1/user/delete
 * Delete user account and all associated data (GDPR right to erasure).
 * This is irreversible.
 */
router.post("/delete", async (req, res) => {
    const uid = req.uid;
    try {
        const batch = db.batch();
        // Delete user profile
        batch.delete(db.collection("users").doc(uid));
        // Delete subscriptions
        batch.delete(db.collection("subscriptions").doc(uid));
        // Delete device tokens
        const tokens = await db
            .collection("device_tokens")
            .where("userId", "==", uid)
            .get();
        tokens.docs.forEach((doc) => batch.delete(doc.ref));
        // Delete guardian links (both as guardian and protected)
        const linksAsGuardian = await db
            .collection("guardian_links")
            .where("guardianId", "==", uid)
            .get();
        linksAsGuardian.docs.forEach((doc) => batch.delete(doc.ref));
        const linksAsProtected = await db
            .collection("guardian_links")
            .where("protectedPersonId", "==", uid)
            .get();
        linksAsProtected.docs.forEach((doc) => batch.delete(doc.ref));
        // Delete duty schedules
        const schedules = await db
            .collection("duty_schedules")
            .where("guardianId", "==", uid)
            .get();
        schedules.docs.forEach((doc) => batch.delete(doc.ref));
        // Delete checkins
        const checkins = await db
            .collection("checkins")
            .where("userId", "==", uid)
            .get();
        checkins.docs.forEach((doc) => batch.delete(doc.ref));
        // Delete timeline entries
        const timeline = await db
            .collection("timeline_entries")
            .where("userId", "==", uid)
            .get();
        timeline.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
        // Delete Firebase Auth account
        try {
            await admin.auth().deleteUser(uid);
        }
        catch (authError) {
            console.warn(`[User] Failed to delete auth account for ${uid}:`, authError);
        }
        console.log(`[User] Account deleted: ${uid}`);
        res.json({ success: true });
    }
    catch (error) {
        console.error("[User] delete account error:", error);
        res.status(500).json({ error: "Failed to delete account" });
    }
});
/**
 * POST /v1/user/export
 * Request a full data export (GDPR data portability).
 * Returns all user data as JSON.
 */
router.post("/export", async (req, res) => {
    const uid = req.uid;
    try {
        const userDoc = await db.collection("users").doc(uid).get();
        const userData = userDoc.exists ? userDoc.data() : null;
        const [linksSnap, schedulesSnap, checkinsSnap, timelineSnap, tokensSnap] = await Promise.all([
            db.collection("guardian_links").where("guardianId", "==", uid).get(),
            db.collection("duty_schedules").where("guardianId", "==", uid).get(),
            db.collection("checkins").where("userId", "==", uid).get(),
            db
                .collection("timeline_entries")
                .where("userId", "==", uid)
                .orderBy("timestamp", "desc")
                .limit(1000)
                .get(),
            db.collection("device_tokens").where("userId", "==", uid).get(),
        ]);
        const exportData = {
            exportedAt: new Date().toISOString(),
            userId: uid,
            profile: userData,
            guardianLinks: linksSnap.docs.map((d) => ({ id: d.id, ...d.data() })),
            dutySchedules: schedulesSnap.docs.map((d) => ({
                id: d.id,
                ...d.data(),
            })),
            checkins: checkinsSnap.docs.map((d) => ({ id: d.id, ...d.data() })),
            timeline: timelineSnap.docs.map((d) => ({ id: d.id, ...d.data() })),
            deviceTokenCount: tokensSnap.size,
        };
        res.json(exportData);
    }
    catch (error) {
        console.error("[User] export error:", error);
        res.status(500).json({ error: "Failed to export data" });
    }
});
/**
 * POST /v1/diagnostics/crash
 * Receive crash reports from iOS client.
 */
router.post("/diagnostics/crash", async (req, res) => {
    try {
        await db.collection("crash_reports").add({
            ...req.body,
            userId: req.uid,
            receivedAt: admin.firestore.Timestamp.now(),
        });
        res.json({ success: true });
    }
    catch (error) {
        console.error("[Diagnostics] crash report error:", error);
        res.status(500).json({ error: "Failed to store crash report" });
    }
});
exports.default = router;
//# sourceMappingURL=user.js.map