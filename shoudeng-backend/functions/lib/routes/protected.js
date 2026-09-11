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
 * GET /v1/protected/guardians
 * Get all guardians for the current protected person.
 * This is the data source for ProtectedHomeView guardian list.
 */
router.get("/guardians", async (req, res) => {
    const uid = req.uid;
    try {
        // Find all active guardian links where this user is the protected person
        const linksSnapshot = await db
            .collection("guardian_links")
            .where("protectedPersonId", "==", uid)
            .where("status", "==", "active")
            .get();
        if (linksSnapshot.empty) {
            res.json([]);
            return;
        }
        const guardians = [];
        for (const linkDoc of linksSnapshot.docs) {
            const link = linkDoc.data();
            const guardianId = link.guardianId;
            // Fetch guardian user profile
            const userDoc = await db.collection("users").doc(guardianId).get();
            if (!userDoc.exists)
                continue;
            const user = userDoc.data();
            // Check if guardian is currently on duty
            const isOnDuty = await checkOnDuty(guardianId, uid);
            // Get duty schedule
            const scheduleSnapshot = await db
                .collection("duty_schedules")
                .where("guardianId", "==", guardianId)
                .where("protectedPersonId", "==", uid)
                .where("isActive", "==", true)
                .get();
            const dutySlots = scheduleSnapshot.docs.map((d) => d.data());
            guardians.push({
                id: guardianId,
                user: {
                    id: guardianId,
                    displayName: user.displayName,
                    role: "guardian",
                    avatarInitial: user.avatarInitial,
                    timeZone: user.timeZone,
                    countryCode: user.countryCode,
                    cityName: user.cityName,
                    createdAt: user.createdAt.toDate().toISOString(),
                },
                permissions: {
                    canSeeLocation: true,
                    canSeeBattery: true,
                    canSeeHealth: false,
                    canSeePhoneActivity: false,
                    canHearEmergencyAudio: true,
                },
                isOnDuty,
                dutySchedule: dutySlots.length > 0
                    ? {
                        guardianId,
                        slots: dutySlots.map((s) => ({
                            startHour: s.startHour,
                            endHour: s.endHour,
                            dayOfWeek: [s.dayOfWeek],
                            isConfirmed: true,
                        })),
                    }
                    : null,
                averageResponseTime: 120, // Default 2 minutes, would be computed from history
                linkedSince: link.createdAt.toDate().toISOString(),
            });
        }
        res.json(guardians);
    }
    catch (error) {
        console.error("[Protected] fetch guardians error:", error);
        res.status(500).json({ error: "Failed to fetch guardians" });
    }
});
/**
 * Check if a guardian is currently on duty for a protected person.
 */
async function checkOnDuty(guardianId, protectedPersonId) {
    const now = new Date();
    const currentHour = now.getHours();
    const currentDay = now.getDay() || 7; // Convert 0 (Sunday) to 7
    const snapshot = await admin
        .firestore()
        .collection("duty_schedules")
        .where("guardianId", "==", guardianId)
        .where("protectedPersonId", "==", protectedPersonId)
        .where("isActive", "==", true)
        .where("dayOfWeek", "==", currentDay)
        .get();
    for (const doc of snapshot.docs) {
        const schedule = doc.data();
        if (currentHour >= schedule.startHour && currentHour < schedule.endHour) {
            return true;
        }
    }
    // If no schedule exists, all guardians are considered on duty
    const anySchedule = await admin
        .firestore()
        .collection("duty_schedules")
        .where("guardianId", "==", guardianId)
        .where("protectedPersonId", "==", protectedPersonId)
        .limit(1)
        .get();
    return anySchedule.empty; // On duty if no schedule configured
}
exports.default = router;
//# sourceMappingURL=protected.js.map