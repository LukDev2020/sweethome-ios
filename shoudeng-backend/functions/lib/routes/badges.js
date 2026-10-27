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
router.use(auth_1.authMiddleware);
/**
 * GET /v1/badges
 * Returns badge counts for tab bar notification dots.
 * - overdueCheckins: protected persons who missed check-in
 * - activeSOS: active SOS events for this guardian
 * - unreadPosts: family feed posts since last read
 */
router.get("/", async (req, res) => {
    const uid = req.uid;
    try {
        // Overdue check-ins: protected persons whose last check-in is > 4 hours old
        let overdueCheckins = 0;
        const linksSnap = await db
            .collection("guardian_links")
            .where("guardianId", "==", uid)
            .where("status", "==", "active")
            .get();
        const fourHoursAgo = new Date(Date.now() - 4 * 60 * 60 * 1000);
        for (const linkDoc of linksSnap.docs) {
            const personId = linkDoc.data().protectedPersonId;
            const checkinSnap = await db
                .collection("checkins")
                .where("userId", "==", personId)
                .orderBy("timestamp", "desc")
                .limit(1)
                .get();
            if (checkinSnap.empty) {
                overdueCheckins++;
            }
            else {
                const lastCheckin = checkinSnap.docs[0].data().timestamp.toDate();
                if (lastCheckin < fourHoursAgo) {
                    overdueCheckins++;
                }
            }
        }
        // Active SOS events
        const sosSnap = await db
            .collection("sos_events")
            .where("resolvedAt", "==", null)
            .get();
        let activeSOS = 0;
        for (const doc of sosSnap.docs) {
            // Check if any of the guardian's protected persons triggered this SOS
            const eventData = doc.data();
            const isRelevant = linksSnap.docs.some((l) => l.data().protectedPersonId === eventData.userId);
            if (isRelevant)
                activeSOS++;
        }
        // Unread family posts since last read timestamp
        const prefsDoc = await db.collection("user_preferences").doc(uid).get();
        const lastReadStr = prefsDoc.exists
            ? prefsDoc.data()?.lastFeedRead
            : null;
        const lastRead = lastReadStr
            ? new Date(lastReadStr)
            : new Date(0);
        // Get family group
        const familyIds = new Set();
        familyIds.add(uid);
        linksSnap.docs.forEach((d) => familyIds.add(d.data().protectedPersonId));
        const asProtected = await db
            .collection("guardian_links")
            .where("protectedPersonId", "==", uid)
            .where("status", "==", "active")
            .get();
        asProtected.docs.forEach((d) => familyIds.add(d.data().guardianId));
        let unreadPosts = 0;
        const familyArr = Array.from(familyIds).filter((id) => id !== uid);
        if (familyArr.length > 0) {
            const postsSnap = await db
                .collection("family_posts")
                .where("authorId", "in", familyArr.slice(0, 30))
                .where("createdAt", ">", admin.firestore.Timestamp.fromDate(lastRead))
                .count()
                .get();
            unreadPosts = postsSnap.data().count;
        }
        res.json({
            overdueCheckins,
            activeSOS,
            unreadPosts,
        });
    }
    catch (error) {
        console.error("[Badges] error:", error);
        res.status(500).json({ error: "Failed to compute badge counts" });
    }
});
exports.default = router;
//# sourceMappingURL=badges.js.map