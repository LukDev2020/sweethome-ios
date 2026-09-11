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
exports.checkCheckinOverdue = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
const fcm_1 = require("../services/fcm");
const db = admin.firestore();
// Default check-in interval (hours) — can be per-user configurable later
const CHECKIN_OVERDUE_HOURS = 8;
/**
 * Scheduled function: runs every 15 minutes.
 * Checks for protected persons who haven't checked in within threshold.
 * Sends reminder to their guardians.
 */
exports.checkCheckinOverdue = functions.pubsub
    .schedule("every 15 minutes")
    .onRun(async () => {
    console.log("[Scheduled] Running check-in overdue check");
    try {
        const cutoff = admin.firestore.Timestamp.fromDate(new Date(Date.now() - CHECKIN_OVERDUE_HOURS * 60 * 60 * 1000));
        // Get all protected users
        const usersSnapshot = await db
            .collection("users")
            .where("role", "==", "protected")
            .get();
        for (const userDoc of usersSnapshot.docs) {
            const userId = userDoc.id;
            const userName = userDoc.data().displayName;
            // Get latest check-in
            const checkinSnapshot = await db
                .collection("checkins")
                .where("userId", "==", userId)
                .orderBy("timestamp", "desc")
                .limit(1)
                .get();
            let isOverdue = false;
            if (checkinSnapshot.empty) {
                // Never checked in — overdue if account is older than threshold
                const createdAt = userDoc.data().createdAt;
                if (createdAt && createdAt.toDate() < cutoff.toDate()) {
                    isOverdue = true;
                }
            }
            else {
                const lastCheckin = checkinSnapshot.docs[0].data().timestamp;
                if (lastCheckin.toDate() < cutoff.toDate()) {
                    isOverdue = true;
                }
            }
            if (isOverdue) {
                console.log(`[Scheduled] Check-in overdue for ${userName}`);
                // Add timeline entry (only once — check if already added today)
                const todayStart = new Date();
                todayStart.setHours(0, 0, 0, 0);
                const existingEntry = await db
                    .collection("timeline_entries")
                    .where("userId", "==", userId)
                    .where("type", "==", "missedCheckIn")
                    .where("timestamp", ">=", admin.firestore.Timestamp.fromDate(todayStart))
                    .limit(1)
                    .get();
                if (existingEntry.empty) {
                    await db.collection("timeline_entries").add({
                        userId,
                        timestamp: admin.firestore.Timestamp.now(),
                        type: "missedCheckIn",
                        description: "超时未报平安",
                        detail: null,
                    });
                }
                // Notify guardians
                const linksSnapshot = await db
                    .collection("guardian_links")
                    .where("protectedPersonId", "==", userId)
                    .where("status", "==", "active")
                    .get();
                for (const linkDoc of linksSnapshot.docs) {
                    const guardianId = linkDoc.data().guardianId;
                    await (0, fcm_1.sendCheckinReminder)(guardianId, userName);
                }
            }
        }
    }
    catch (error) {
        console.error("[Scheduled] Check-in overdue check error:", error);
    }
});
//# sourceMappingURL=checkinOverdue.js.map