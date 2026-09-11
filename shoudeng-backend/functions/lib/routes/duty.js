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
 * PUT /v1/duty-schedule
 * Update duty schedule for a guardian-protected pair.
 * Called by the protected person to assign schedule to a guardian.
 */
router.put("/", async (req, res) => {
    const uid = req.uid;
    const { guardianId, slots } = req.body;
    if (!guardianId || !slots) {
        res.status(400).json({ error: "guardianId and slots are required" });
        return;
    }
    try {
        // Verify the guardian link exists
        const linkId = `${guardianId}_${uid}`;
        const linkDoc = await db.collection("guardian_links").doc(linkId).get();
        if (!linkDoc.exists || linkDoc.data()?.status !== "active") {
            res.status(403).json({ error: "No active guardian link found" });
            return;
        }
        // Delete existing schedules for this pair
        const existingSnapshot = await db
            .collection("duty_schedules")
            .where("guardianId", "==", guardianId)
            .where("protectedPersonId", "==", uid)
            .get();
        const batch = db.batch();
        existingSnapshot.docs.forEach((doc) => batch.delete(doc.ref));
        // Create new schedule entries
        for (const slot of slots) {
            const days = slot.dayOfWeek || [1, 2, 3, 4, 5, 6, 7];
            for (const day of days) {
                const scheduleRef = db.collection("duty_schedules").doc();
                batch.set(scheduleRef, {
                    protectedPersonId: uid,
                    guardianId,
                    dayOfWeek: day,
                    startHour: slot.startHour,
                    endHour: slot.endHour,
                    timeZone: "Asia/Shanghai", // Would use user's timezone
                    isActive: true,
                });
            }
        }
        await batch.commit();
        res.json({ success: true });
    }
    catch (error) {
        console.error("[DutySchedule] update error:", error);
        res.status(500).json({ error: "Failed to update duty schedule" });
    }
});
exports.default = router;
//# sourceMappingURL=duty.js.map