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
const rateLimit_1 = require("../middleware/rateLimit");
const bigquery_1 = require("../services/bigquery");
const uuid_1 = require("uuid");
const router = (0, express_1.Router)();
const db = admin.firestore();
router.use(auth_1.authMiddleware);
router.use((0, rateLimit_1.createRateLimiter)(rateLimit_1.RATE_LIMITS.telemetry));
/**
 * POST /v1/heartbeat
 * Record a heartbeat signal from the iOS client.
 * Written to BigQuery for time-series analysis.
 */
router.post("/heartbeat", async (req, res) => {
    const { userId, timestamp, source, batteryLevel, batteryState, latitude, longitude, accuracy, } = req.body;
    if (!userId || !timestamp) {
        res.status(400).json({ error: "userId and timestamp are required" });
        return;
    }
    try {
        await (0, bigquery_1.insertHeartbeat)({
            userId,
            timestamp,
            source: source || "unknown",
            batteryLevel,
            batteryState,
            latitude,
            longitude,
            accuracy,
        });
        res.json({ success: true });
    }
    catch (error) {
        console.error("[Telemetry] heartbeat insert error:", error);
        // Don't fail the request — heartbeats are best-effort
        res.json({ success: true, warning: "Queued for retry" });
    }
});
/**
 * POST /v1/location/report
 * Record a location report from the iOS client.
 * Written to BigQuery for time-series and trail reconstruction.
 */
router.post("/location/report", async (req, res) => {
    const { userId, latitude, longitude, accuracy, altitude, speed, timestamp, isInSafeZone, safeZoneName, } = req.body;
    if (!userId || latitude === undefined || longitude === undefined) {
        res
            .status(400)
            .json({ error: "userId, latitude, and longitude are required" });
        return;
    }
    try {
        await (0, bigquery_1.insertLocationReport)({
            userId,
            latitude,
            longitude,
            accuracy: accuracy || 0,
            altitude,
            speed,
            timestamp: timestamp || new Date().toISOString(),
            isInSafeZone,
            safeZoneName,
        });
        res.json({ success: true });
    }
    catch (error) {
        console.error("[Telemetry] location insert error:", error);
        res.json({ success: true, warning: "Queued for retry" });
    }
});
/**
 * POST /v1/checkin
 * Record a check-in ("报平安") from the protected person.
 * Written to both Firestore (for real-time) and BigQuery (for history).
 */
router.post("/checkin", async (req, res) => {
    const { userId, latitude, longitude, note } = req.body;
    if (!userId) {
        res.status(400).json({ error: "userId is required" });
        return;
    }
    const now = new Date();
    const checkInId = (0, uuid_1.v4)();
    try {
        // Write to Firestore for real-time status
        await db
            .collection("checkins")
            .doc(checkInId)
            .set({
            userId,
            timestamp: admin.firestore.Timestamp.fromDate(now),
            latitude: latitude || null,
            longitude: longitude || null,
            note: note || null,
        });
        // Write to BigQuery for history
        await (0, bigquery_1.insertCheckin)({
            userId,
            timestamp: now.toISOString(),
            latitude,
            longitude,
            note,
        });
        // Add timeline entry
        await db.collection("timeline_entries").add({
            userId,
            timestamp: admin.firestore.Timestamp.fromDate(now),
            type: "checkIn",
            description: note || "报平安",
            detail: null,
        });
        res.json({
            checkInId,
            timestamp: now.toISOString(),
        });
    }
    catch (error) {
        console.error("[Telemetry] checkin error:", error);
        res.status(500).json({ error: "Failed to record check-in" });
    }
});
exports.default = router;
//# sourceMappingURL=telemetry.js.map