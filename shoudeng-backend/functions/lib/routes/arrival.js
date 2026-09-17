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
 * POST /v1/arrival-report
 * One-tap "I arrived safely" with current location.
 * Notifies all guardians via push.
 */
router.post("/", async (req, res) => {
    const uid = req.uid;
    const { latitude, longitude, placeName } = req.body;
    try {
        const now = admin.firestore.Timestamp.now();
        const reportId = `${uid}_${Date.now()}`;
        await db.collection("arrival_reports").doc(reportId).set({
            userId: uid,
            latitude: latitude || null,
            longitude: longitude || null,
            placeName: placeName || null,
            timestamp: now,
        });
        // Also counts as a check-in
        await db.collection("checkins").add({
            userId: uid,
            timestamp: now,
            latitude: latitude || null,
            longitude: longitude || null,
            note: `到达报告：${placeName || "当前位置"}`,
        });
        // Add timeline entry
        await db.collection("timeline_entries").add({
            userId: uid,
            timestamp: now,
            type: "arrivalReport",
            description: `已安全到达${placeName ? "「" + placeName + "」" : ""}`,
            detail: null,
        });
        // Notify all guardians
        const userDoc = await db.collection("users").doc(uid).get();
        const userName = userDoc.exists ? userDoc.data().displayName : "被守护者";
        const linksSnapshot = await db
            .collection("guardian_links")
            .where("protectedPersonId", "==", uid)
            .where("status", "==", "active")
            .get();
        for (const linkDoc of linksSnapshot.docs) {
            const guardianId = linkDoc.data().guardianId;
            const tokens = await getTokensForUser(guardianId);
            if (tokens.length > 0) {
                await admin.messaging().sendEachForMulticast({
                    tokens,
                    notification: {
                        title: "到达报告",
                        body: `${userName}已安全到达${placeName ? "「" + placeName + "」" : ""}`,
                    },
                    data: {
                        action: "arrival_report",
                        reportId,
                    },
                });
            }
        }
        res.status(201).json({ success: true, reportId });
    }
    catch (error) {
        console.error("[Arrival] report error:", error);
        res.status(500).json({ error: "Failed to send arrival report" });
    }
});
/**
 * GET /v1/arrival-report/recent
 * Get recent arrival reports for a guardian's protected persons.
 */
router.get("/recent", async (req, res) => {
    const uid = req.uid;
    try {
        // Get all protected person IDs
        const linksSnapshot = await db
            .collection("guardian_links")
            .where("guardianId", "==", uid)
            .where("status", "==", "active")
            .get();
        const personIds = linksSnapshot.docs.map((d) => d.data().protectedPersonId);
        if (personIds.length === 0) {
            res.json([]);
            return;
        }
        // Get last 24h of reports
        const cutoff = admin.firestore.Timestamp.fromDate(new Date(Date.now() - 24 * 60 * 60 * 1000));
        const reports = [];
        for (const personId of personIds) {
            const snapshot = await db
                .collection("arrival_reports")
                .where("userId", "==", personId)
                .where("timestamp", ">=", cutoff)
                .orderBy("timestamp", "desc")
                .limit(10)
                .get();
            const userDoc = await db.collection("users").doc(personId).get();
            const displayName = userDoc.exists
                ? userDoc.data().displayName
                : "未知";
            for (const doc of snapshot.docs) {
                const data = doc.data();
                reports.push({
                    id: doc.id,
                    userId: personId,
                    displayName,
                    latitude: data.latitude,
                    longitude: data.longitude,
                    placeName: data.placeName,
                    timestamp: data.timestamp.toDate().toISOString(),
                });
            }
        }
        reports.sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime());
        res.json(reports);
    }
    catch (error) {
        console.error("[Arrival] recent error:", error);
        res.status(500).json({ error: "Failed to fetch recent reports" });
    }
});
async function getTokensForUser(userId) {
    const snapshot = await db
        .collection("device_tokens")
        .where("userId", "==", userId)
        .get();
    return snapshot.docs.map((doc) => doc.data().token);
}
exports.default = router;
//# sourceMappingURL=arrival.js.map