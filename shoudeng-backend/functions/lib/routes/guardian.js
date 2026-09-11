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
const bigquery_1 = require("../services/bigquery");
const geocoding_1 = require("../services/geocoding");
const router = (0, express_1.Router)();
const db = admin.firestore();
router.use(auth_1.authMiddleware);
/**
 * GET /v1/guardian/protected-persons
 * Get all protected persons that this guardian is watching, with their current status.
 * This is the main data source for GuardianHomeView.
 */
router.get("/protected-persons", async (req, res) => {
    const uid = req.uid;
    try {
        // Find all active guardian links where this user is the guardian
        const linksSnapshot = await db
            .collection("guardian_links")
            .where("guardianId", "==", uid)
            .where("status", "==", "active")
            .get();
        if (linksSnapshot.empty) {
            res.json([]);
            return;
        }
        const result = [];
        for (const linkDoc of linksSnapshot.docs) {
            const link = linkDoc.data();
            const personId = link.protectedPersonId;
            // Fetch user profile
            const userDoc = await db.collection("users").doc(personId).get();
            if (!userDoc.exists)
                continue;
            const user = userDoc.data();
            // Count protection layers (number of active guardians)
            const guardianCount = await db
                .collection("guardian_links")
                .where("protectedPersonId", "==", personId)
                .where("status", "==", "active")
                .count()
                .get();
            // Get latest heartbeat from BigQuery
            const latestHeartbeat = await (0, bigquery_1.getLatestHeartbeat)(personId);
            // Get latest check-in from Firestore
            const checkinSnapshot = await db
                .collection("checkins")
                .where("userId", "==", personId)
                .orderBy("timestamp", "desc")
                .limit(1)
                .get();
            const lastCheckIn = checkinSnapshot.empty
                ? null
                : checkinSnapshot.docs[0].data().timestamp.toDate().toISOString();
            // Get latest location from BigQuery heartbeat
            const lat = latestHeartbeat?.latitude ?? null;
            const lng = latestHeartbeat?.longitude ?? null;
            const locationTimestamp = latestHeartbeat?.timestamp ?? null;
            // Compute safety status
            const status = computeSafetyStatus(lastCheckIn ? new Date(lastCheckIn) : null, latestHeartbeat?.timestamp
                ? new Date(String(latestHeartbeat.timestamp))
                : null);
            result.push({
                personId,
                displayName: user.displayName,
                status,
                latitude: lat,
                longitude: lng,
                locationTimestamp,
                locationAddress: lat != null && lng != null
                    ? await (0, geocoding_1.reverseGeocode)(lat, lng)
                    : null,
                batteryLevel: latestHeartbeat?.battery_level ?? null,
                batteryState: latestHeartbeat?.battery_state ?? "unknown",
                lastCheckIn,
                lastPhoneActivity: latestHeartbeat?.timestamp
                    ? String(latestHeartbeat.timestamp)
                    : null,
                protectionLayers: guardianCount.data().count,
            });
        }
        res.json(result);
    }
    catch (error) {
        console.error("[Guardian] fetch protected persons error:", error);
        res.status(500).json({ error: "Failed to fetch protected persons" });
    }
});
/**
 * Compute safety status based on check-in and heartbeat recency.
 */
function computeSafetyStatus(lastCheckIn, lastHeartbeat) {
    const now = Date.now();
    // No data at all
    if (!lastCheckIn && !lastHeartbeat)
        return "unreachable";
    // Check heartbeat (phone connectivity)
    if (lastHeartbeat) {
        const heartbeatAge = now - lastHeartbeat.getTime();
        // No heartbeat for 30+ minutes → unreachable
        if (heartbeatAge > 30 * 60 * 1000)
            return "unreachable";
    }
    // Check check-in recency
    if (lastCheckIn) {
        const checkinAge = now - lastCheckIn.getTime();
        if (checkinAge > 8 * 60 * 60 * 1000)
            return "overdue"; // 8 hours
        if (checkinAge > 6 * 60 * 60 * 1000)
            return "pendingCheckIn"; // 6 hours
    }
    else {
        // Never checked in
        return "pendingCheckIn";
    }
    return "normal";
}
exports.default = router;
//# sourceMappingURL=guardian.js.map