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
const evidence_1 = require("../services/evidence");
const bigquery_1 = require("../services/bigquery");
const storage_1 = require("../services/storage");
const router = (0, express_1.Router)();
const db = admin.firestore();
/**
 * POST /v1/evidence/generate
 * Generate an evidence bundle (PDF data, JSON, or GPX) for a protected person.
 * Requires authentication — only guardians of the person can request.
 */
router.post("/generate", auth_1.authMiddleware, async (req, res) => {
    const uid = req.uid;
    const { protectedPersonId, timeWindowStart, timeWindowEnd, format, reason } = req.body;
    if (!protectedPersonId || !timeWindowStart || !timeWindowEnd) {
        res.status(400).json({
            error: "protectedPersonId, timeWindowStart, and timeWindowEnd are required",
        });
        return;
    }
    try {
        // Verify requester is a guardian of this person
        const linkId = `${uid}_${protectedPersonId}`;
        const linkDoc = await db.collection("guardian_links").doc(linkId).get();
        if (!linkDoc.exists || linkDoc.data()?.status !== "active") {
            // Also check if the user is the protected person themselves
            if (uid !== protectedPersonId) {
                res.status(403).json({ error: "Not authorized to access this data" });
                return;
            }
        }
        const bundle = await (0, evidence_1.generateEvidenceBundle)({
            protectedPersonId,
            timeWindowStart,
            timeWindowEnd,
            format: format || "json",
            requestedBy: uid,
            reason: reason || "user_request",
        });
        if (format === "gpx") {
            // Return GPX XML
            const userDoc = await db
                .collection("users")
                .doc(protectedPersonId)
                .get();
            const personName = userDoc.exists
                ? userDoc.data().displayName
                : "Unknown";
            const gpx = (0, evidence_1.generateGPX)(bundle.locations, personName);
            res.set("Content-Type", "application/gpx+xml");
            res.set("Content-Disposition", `attachment; filename="${personName}_track.gpx"`);
            res.send(gpx);
            return;
        }
        // Upload to Cloud Storage and return download URL + inline data
        try {
            const downloadUrl = await (0, storage_1.uploadEvidenceBundle)(bundle.bundleId, bundle, "json");
            res.json({ ...bundle, downloadUrl });
        }
        catch {
            // If storage upload fails, still return the data inline
            res.json(bundle);
        }
    }
    catch (error) {
        console.error("[Evidence] generate error:", error);
        res.status(500).json({ error: "Failed to generate evidence bundle" });
    }
});
/**
 * POST /v1/evidence/share
 * Create a time-limited share link for emergency data.
 * Returns a token that can be accessed without authentication.
 */
router.post("/share", auth_1.authMiddleware, async (req, res) => {
    const uid = req.uid;
    const { protectedPersonId, expiresInHours } = req.body;
    if (!protectedPersonId) {
        res.status(400).json({ error: "protectedPersonId is required" });
        return;
    }
    try {
        const token = await (0, evidence_1.createShareToken)({
            protectedPersonId,
            createdBy: uid,
            expiresInHours: expiresInHours || 48,
        });
        const shareUrl = `${req.protocol}://${req.get("host")}/v1/evidence/share/${token}`;
        res.json({ token, shareUrl, expiresInHours: expiresInHours || 48 });
    }
    catch (error) {
        console.error("[Evidence] share creation error:", error);
        res.status(500).json({ error: "Failed to create share link" });
    }
});
/**
 * GET /v1/evidence/share/:token
 * Access shared emergency data without authentication.
 * Returns last 24h of location + SOS data as JSON (rendered as web page by frontend).
 */
router.get("/share/:token", async (req, res) => {
    const { token } = req.params;
    try {
        const shareDoc = await db.collection("evidence_shares").doc(token).get();
        if (!shareDoc.exists) {
            res.status(404).json({ error: "Share link not found" });
            return;
        }
        const shareData = shareDoc.data();
        // Check expiry
        if (shareData.expiresAt.toDate() < new Date()) {
            res.status(410).json({ error: "Share link has expired" });
            return;
        }
        // Check access count
        if (shareData.accessCount >= shareData.maxAccess) {
            res.status(410).json({ error: "Share link access limit reached" });
            return;
        }
        // Increment access count
        await shareDoc.ref.update({
            accessCount: admin.firestore.FieldValue.increment(1),
        });
        const protectedPersonId = shareData.protectedPersonId;
        // Fetch last 24h of data
        const now = new Date();
        const oneDayAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000);
        const [locations, heartbeats] = await Promise.all([
            (0, bigquery_1.queryLocations)(protectedPersonId, oneDayAgo.toISOString(), now.toISOString()),
            (0, bigquery_1.queryHeartbeats)(protectedPersonId, oneDayAgo.toISOString(), now.toISOString()),
        ]);
        // Fetch user profile
        const userDoc = await db
            .collection("users")
            .doc(protectedPersonId)
            .get();
        const userName = userDoc.exists ? userDoc.data().displayName : "Unknown";
        // Fetch active SOS events
        const sosSnapshot = await db
            .collection("sos_events")
            .where("protectedPersonId", "==", protectedPersonId)
            .where("resolvedAt", "==", null)
            .get();
        const sosEvents = sosSnapshot.docs.map((d) => ({ id: d.id, ...d.data() }));
        res.json({
            personName: userName,
            locations,
            heartbeats: heartbeats.map((h) => ({
                timestamp: h.timestamp,
                batteryLevel: h.battery_level,
                batteryState: h.battery_state,
            })),
            activeSOS: sosEvents,
            generatedAt: now.toISOString(),
            disclaimer: "此数据由守灯安全应用自动生成，仅供紧急参考。数据完整性可通过 SHA-256 哈希验证。",
        });
    }
    catch (error) {
        console.error("[Evidence] share access error:", error);
        res.status(500).json({ error: "Failed to retrieve shared data" });
    }
});
exports.default = router;
//# sourceMappingURL=evidence.js.map