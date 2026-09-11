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
exports.default = router;
//# sourceMappingURL=device.js.map