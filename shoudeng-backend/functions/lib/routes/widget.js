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
 * GET /v1/widget/data
 * Lightweight endpoint for iOS widget data.
 * Returns minimal data to populate lock screen / home screen widgets.
 */
router.get("/data", async (req, res) => {
    const uid = req.uid;
    try {
        // User profile
        const userDoc = await db.collection("users").doc(uid).get();
        if (!userDoc.exists) {
            res.status(404).json({ error: "User not found" });
            return;
        }
        const user = userDoc.data();
        // Latest check-in
        const checkinSnap = await db
            .collection("checkins")
            .where("userId", "==", uid)
            .orderBy("timestamp", "desc")
            .limit(1)
            .get();
        const lastCheckIn = checkinSnap.empty
            ? null
            : checkinSnap.docs[0].data().timestamp.toDate().toISOString();
        // Active SOS
        const sosSnap = await db
            .collection("sos_events")
            .where("userId", "==", uid)
            .where("resolvedAt", "==", null)
            .limit(1)
            .get();
        const hasActiveSOS = !sosSnap.empty;
        // Guardian count
        const guardianCount = await db
            .collection("guardian_links")
            .where("protectedPersonId", "==", uid)
            .where("status", "==", "active")
            .count()
            .get();
        // Battery from user telemetry doc
        const telDoc = await db.collection("user_telemetry").doc(uid).get();
        const batteryLevel = telDoc.exists
            ? telDoc.data()?.batteryLevel ?? null
            : null;
        res.json({
            displayName: user.displayName || "",
            role: user.role || "protected",
            cityName: user.cityName || "",
            lastCheckIn,
            hasActiveSOS,
            guardianCount: guardianCount.data().count,
            batteryLevel,
            updatedAt: new Date().toISOString(),
        });
    }
    catch (error) {
        console.error("[Widget] data error:", error);
        res.status(500).json({ error: "Failed to fetch widget data" });
    }
});
exports.default = router;
//# sourceMappingURL=widget.js.map