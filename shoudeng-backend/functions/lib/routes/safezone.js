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
const uuid_1 = require("uuid");
const auth_1 = require("../middleware/auth");
const router = (0, express_1.Router)();
const db = admin.firestore();
router.use(auth_1.authMiddleware);
/**
 * POST /v1/safe-zone/save
 * Create or update a safe zone for the current user.
 */
router.post("/save", async (req, res) => {
    const uid = req.uid;
    const { name, latitude, longitude, radius, id: existingId } = req.body;
    if (!name || latitude === undefined || longitude === undefined) {
        res
            .status(400)
            .json({ error: "name, latitude, and longitude are required" });
        return;
    }
    try {
        const zoneId = existingId || (0, uuid_1.v4)();
        await db
            .collection("safe_zones")
            .doc(zoneId)
            .set({
            userId: uid,
            name,
            latitude,
            longitude,
            radiusMeters: radius || 100,
            type: "custom",
            isActive: true,
            createdAt: admin.firestore.Timestamp.now(),
        }, { merge: true });
        res.json({
            id: zoneId,
            name,
            latitude,
            longitude,
            radius: radius || 100,
            isAutoSuggested: false,
        });
    }
    catch (error) {
        console.error("[SafeZone] save error:", error);
        res.status(500).json({ error: "Failed to save safe zone" });
    }
});
/**
 * GET /v1/safe-zones
 * Get all active safe zones for the current user.
 */
router.get("/", async (req, res) => {
    const uid = req.uid;
    try {
        const snapshot = await db
            .collection("safe_zones")
            .where("userId", "==", uid)
            .where("isActive", "==", true)
            .get();
        const zones = snapshot.docs.map((doc) => {
            const data = doc.data();
            return {
                id: doc.id,
                name: data.name,
                latitude: data.latitude,
                longitude: data.longitude,
                radius: data.radiusMeters,
                isAutoSuggested: data.type !== "custom",
            };
        });
        res.json(zones);
    }
    catch (error) {
        console.error("[SafeZone] fetch error:", error);
        res.status(500).json({ error: "Failed to fetch safe zones" });
    }
});
exports.default = router;
//# sourceMappingURL=safezone.js.map