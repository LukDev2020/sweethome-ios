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
 * POST /v1/device/token
 * Register or update an APNs device token for push notifications.
 */
router.post("/token", async (req, res) => {
    const uid = req.uid;
    const { token, platform, environment } = req.body;
    if (!token || !platform) {
        res.status(400).json({ error: "token and platform are required" });
        return;
    }
    try {
        // Use token as document ID to avoid duplicates
        const tokenId = `${uid}_${platform}`;
        await db
            .collection("device_tokens")
            .doc(tokenId)
            .set({
            userId: uid,
            token,
            platform,
            environment: environment || "production",
            updatedAt: admin.firestore.Timestamp.now(),
        });
        res.json({ success: true });
    }
    catch (error) {
        console.error("[Device] token registration error:", error);
        res.status(500).json({ error: "Failed to register device token" });
    }
});
/**
 * POST /v1/device/ble-tag
 * Sync a paired/unpaired BLE tracker tag.
 */
router.post("/ble-tag", async (req, res) => {
    const uid = req.uid;
    const { tagId, name, type, action } = req.body;
    if (!tagId || !name || !type || !action) {
        res.status(400).json({ error: "tagId, name, type, and action are required" });
        return;
    }
    try {
        if (action === "paired") {
            await db.collection("users").doc(uid).collection("ble_tags").doc(tagId).set({
                name,
                type,
                pairedAt: admin.firestore.Timestamp.now(),
                isActive: true,
            });
        }
        else if (action === "unpaired") {
            await db.collection("users").doc(uid).collection("ble_tags").doc(tagId).delete();
        }
        res.json({ success: true });
    }
    catch (error) {
        console.error("[Device] BLE tag sync error:", error);
        res.status(500).json({ error: "Failed to sync BLE tag" });
    }
});
/**
 * POST /v1/device/ble-sightings
 * Batch upload BLE tag sighting locations.
 */
router.post("/ble-sightings", async (req, res) => {
    const uid = req.uid;
    const { sightings } = req.body;
    if (!Array.isArray(sightings) || sightings.length === 0) {
        res.status(400).json({ error: "sightings array is required" });
        return;
    }
    try {
        const batch = db.batch();
        for (const s of sightings.slice(0, 50)) {
            const ref = db.collection("users").doc(uid).collection("ble_sightings").doc();
            batch.set(ref, {
                tagId: s.tagId,
                latitude: s.latitude,
                longitude: s.longitude,
                rssi: s.rssi,
                timestamp: s.timestamp ? new Date(s.timestamp) : admin.firestore.Timestamp.now(),
            });
        }
        await batch.commit();
        res.json({ success: true });
    }
    catch (error) {
        console.error("[Device] BLE sighting upload error:", error);
        res.status(500).json({ error: "Failed to upload sightings" });
    }
});
/**
 * POST /v1/device/ble-separation
 * Notify guardians that a BLE tag went out of range.
 */
router.post("/ble-separation", async (req, res) => {
    const uid = req.uid;
    const { tagName, latitude, longitude } = req.body;
    if (!tagName) {
        res.status(400).json({ error: "tagName is required" });
        return;
    }
    try {
        // Get all guardians linked to this protected person
        const links = await db.collection("links")
            .where("protectedPersonId", "==", uid)
            .where("status", "==", "active")
            .get();
        const notifications = [];
        for (const link of links.docs) {
            const guardianId = link.data().guardianId;
            const tokens = await db.collection("device_tokens")
                .where("userId", "==", guardianId)
                .get();
            for (const tokenDoc of tokens.docs) {
                const token = tokenDoc.data().token;
                if (token) {
                    notifications.push(admin.messaging().sendToDevice(token, {
                        notification: {
                            title: "分离提醒",
                            body: `蓝牙标签「${tagName}」已超出范围`,
                        },
                        data: {
                            type: "ble_separation",
                            tagName,
                            protectedPersonId: uid,
                            ...(latitude ? { latitude: String(latitude) } : {}),
                            ...(longitude ? { longitude: String(longitude) } : {}),
                        },
                    }));
                }
            }
        }
        await Promise.all(notifications);
        // Log timeline entry
        await db.collection("users").doc(uid).collection("timeline").add({
            type: "ble_separation",
            description: `蓝牙标签「${tagName}」超出范围`,
            latitude: latitude || null,
            longitude: longitude || null,
            timestamp: admin.firestore.Timestamp.now(),
        });
        res.json({ success: true });
    }
    catch (error) {
        console.error("[Device] BLE separation alert error:", error);
        res.status(500).json({ error: "Failed to send separation alert" });
    }
});
exports.default = router;
//# sourceMappingURL=device.js.map