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
// POST /v1/silent-alarm/schedule — Set or update silent alarm schedule
router.post("/schedule", auth_1.authMiddleware, async (req, res) => {
    const userId = req.userId;
    const { enabled, times, windowMinutes, gracePeriodMisses } = req.body;
    if (typeof enabled !== "boolean") {
        return res.status(400).json({ error: "enabled must be a boolean" });
    }
    if (enabled) {
        if (!Array.isArray(times) || times.length === 0) {
            return res.status(400).json({ error: "times must be a non-empty array" });
        }
        for (const t of times) {
            if (typeof t.hour !== "number" || typeof t.minute !== "number") {
                return res.status(400).json({ error: "each time must have hour and minute" });
            }
            if (t.hour < 0 || t.hour > 23 || t.minute < 0 || t.minute > 59) {
                return res.status(400).json({ error: "invalid time values" });
            }
        }
    }
    await db.collection("silent_alarm_schedules").doc(userId).set({
        enabled,
        times: enabled ? times : [],
        windowMinutes: windowMinutes || 30,
        gracePeriodMisses: gracePeriodMisses || 3,
        consecutiveMisses: 0,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return res.json({ success: true });
});
// POST /v1/silent-alarm/confirm — User confirms they are safe
router.post("/confirm", auth_1.authMiddleware, async (req, res) => {
    const userId = req.userId;
    const ref = db.collection("silent_alarm_schedules").doc(userId);
    const doc = await ref.get();
    if (!doc.exists) {
        return res.status(404).json({ error: "No silent alarm configured" });
    }
    await ref.update({
        consecutiveMisses: 0,
        lastConfirmedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    // Log the check-in to timeline
    await db.collection("timeline_entries").add({
        userId,
        type: "silent_alarm_confirmed",
        description: "安全确认已完成",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
    return res.json({ success: true });
});
// GET /v1/silent-alarm — Get current schedule
router.get("/", auth_1.authMiddleware, async (req, res) => {
    const userId = req.userId;
    const doc = await db.collection("silent_alarm_schedules").doc(userId).get();
    if (!doc.exists) {
        return res.json({ enabled: false, times: [], windowMinutes: 30, gracePeriodMisses: 3 });
    }
    return res.json(doc.data());
});
exports.default = router;
//# sourceMappingURL=silentAlarm.js.map