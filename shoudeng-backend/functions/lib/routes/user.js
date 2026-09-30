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
        if (typeof displayName !== "string" || displayName.length > 100) {
            res.status(400).json({ error: "displayName must be a string of 100 characters or less" });
            return;
        }
        updates.displayName = displayName;
        updates.avatarInitial = displayName.charAt(0);
    }
    if (timeZone !== undefined)
        updates.timeZone = timeZone;
    if (cityName !== undefined) {
        if (typeof cityName !== "string" || cityName.length > 100) {
            res.status(400).json({ error: "cityName must be a string of 100 characters or less" });
            return;
        }
        updates.cityName = cityName;
    }
    if (countryCode !== undefined) {
        if (typeof countryCode !== "string" || countryCode.length > 10) {
            res.status(400).json({ error: "countryCode must be a string of 10 characters or less" });
            return;
        }
        updates.countryCode = countryCode;
    }
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
 * PUT /v1/user/notification-preferences
 * Save notification preferences to server (for push filtering).
 */
router.put("/notification-preferences", async (req, res) => {
    const uid = req.uid;
    const { sosAlerts, checkinReminder, checkinOverdue, familyFeed } = req.body;
    const prefs = {};
    if (sosAlerts !== undefined)
        prefs.sosAlerts = sosAlerts;
    if (checkinReminder !== undefined)
        prefs.checkinReminder = checkinReminder;
    if (checkinOverdue !== undefined)
        prefs.checkinOverdue = checkinOverdue;
    if (familyFeed !== undefined)
        prefs.familyFeed = familyFeed;
    try {
        await db.collection("users").doc(uid).update({
            notificationPrefs: prefs,
            updatedAt: admin.firestore.Timestamp.now(),
        });
        res.json({ success: true });
    }
    catch (error) {
        console.error("[User] update notification prefs error:", error);
        res.status(500).json({ error: "Failed to update notification preferences" });
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
        // Helper: delete all docs from a query, respecting Firestore batch limit (500)
        async function deleteQueryResults(query) {
            const snap = await query.get();
            if (snap.empty)
                return 0;
            const chunks = [];
            for (let i = 0; i < snap.docs.length; i += 450) {
                chunks.push(snap.docs.slice(i, i + 450));
            }
            for (const chunk of chunks) {
                const batch = db.batch();
                chunk.forEach((doc) => batch.delete(doc.ref));
                await batch.commit();
            }
            return snap.size;
        }
        // Helper: delete subcollections of matching docs (e.g. family_posts/{id}/comments)
        async function deleteDocsWithSubcollection(query, subcollectionName) {
            const snap = await query.get();
            if (snap.empty)
                return 0;
            for (const doc of snap.docs) {
                const subSnap = await doc.ref.collection(subcollectionName).get();
                if (!subSnap.empty) {
                    const batch = db.batch();
                    subSnap.docs.forEach((sub) => batch.delete(sub.ref));
                    await batch.commit();
                }
            }
            const batch = db.batch();
            snap.docs.forEach((doc) => batch.delete(doc.ref));
            await batch.commit();
            return snap.size;
        }
        // Delete documents by uid-keyed ID (no query needed)
        const directDeleteBatch = db.batch();
        directDeleteBatch.delete(db.collection("users").doc(uid));
        directDeleteBatch.delete(db.collection("subscriptions").doc(uid));
        directDeleteBatch.delete(db.collection("home_timers").doc(uid));
        directDeleteBatch.delete(db.collection("medical_cards").doc(uid));
        directDeleteBatch.delete(db.collection("selected_hotlines").doc(uid));
        await directDeleteBatch.commit();
        // Delete query-based collections in parallel where possible
        await Promise.all([
            deleteQueryResults(db.collection("device_tokens").where("userId", "==", uid)),
            deleteQueryResults(db.collection("guardian_links").where("guardianId", "==", uid)),
            deleteQueryResults(db.collection("guardian_links").where("protectedPersonId", "==", uid)),
            deleteQueryResults(db.collection("duty_schedules").where("guardianId", "==", uid)),
            deleteQueryResults(db.collection("duty_schedules").where("protectedPersonId", "==", uid)),
            deleteQueryResults(db.collection("checkins").where("userId", "==", uid)),
            deleteQueryResults(db.collection("timeline_entries").where("userId", "==", uid)),
            deleteQueryResults(db.collection("safe_zones").where("userId", "==", uid)),
            deleteQueryResults(db.collection("arrival_reports").where("userId", "==", uid)),
            deleteQueryResults(db.collection("itineraries").where("userId", "==", uid)),
            deleteQueryResults(db.collection("invites").where("createdBy", "==", uid)),
            deleteQueryResults(db.collection("crash_reports").where("userId", "==", uid)),
            deleteQueryResults(db.collection("evidence_shares").where("createdBy", "==", uid)),
            deleteQueryResults(db.collection("medical_card_shares").where("userId", "==", uid)),
            deleteQueryResults(db.collection("sos_events").where("protectedPersonId", "==", uid)),
            // Family posts have a comments subcollection
            deleteDocsWithSubcollection(db.collection("family_posts").where("authorId", "==", uid), "comments"),
        ]);
        // Note: consent_audit in BigQuery is intentionally retained for legal compliance.
        // evidence_holds are retained for audit trail integrity.
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
        const medicalDoc = await db.collection("medical_cards").doc(uid).get();
        const medicalData = medicalDoc.exists ? medicalDoc.data() : null;
        const [linksSnap, schedulesSnap, checkinsSnap, timelineSnap, tokensSnap, safeZonesSnap, sosSnap, familyPostsSnap, itinerariesSnap,] = await Promise.all([
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
            db.collection("safe_zones").where("userId", "==", uid).get(),
            db.collection("sos_events").where("protectedPersonId", "==", uid).get(),
            db.collection("family_posts").where("authorId", "==", uid).get(),
            db.collection("itineraries").where("userId", "==", uid).get(),
        ]);
        const exportData = {
            exportedAt: new Date().toISOString(),
            userId: uid,
            profile: userData,
            medicalCard: medicalData,
            guardianLinks: linksSnap.docs.map((d) => ({ id: d.id, ...d.data() })),
            dutySchedules: schedulesSnap.docs.map((d) => ({
                id: d.id,
                ...d.data(),
            })),
            checkins: checkinsSnap.docs.map((d) => ({ id: d.id, ...d.data() })),
            timeline: timelineSnap.docs.map((d) => ({ id: d.id, ...d.data() })),
            safeZones: safeZonesSnap.docs.map((d) => ({ id: d.id, ...d.data() })),
            sosEvents: sosSnap.docs.map((d) => ({ id: d.id, ...d.data() })),
            familyPosts: familyPostsSnap.docs.map((d) => ({ id: d.id, ...d.data() })),
            itineraries: itinerariesSnap.docs.map((d) => ({ id: d.id, ...d.data() })),
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