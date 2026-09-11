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
exports.checkHeartbeatMissing = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
const bigquery_1 = require("../services/bigquery");
const fcm_1 = require("../services/fcm");
const db = admin.firestore();
// Threshold in minutes before alerting guardians
const HEARTBEAT_MISSING_THRESHOLD_MIN = 30;
/**
 * Scheduled function: runs every 5 minutes.
 * Checks for protected persons whose heartbeat is missing beyond threshold.
 * Sends alert to their guardians.
 */
exports.checkHeartbeatMissing = functions.pubsub
    .schedule("every 5 minutes")
    .onRun(async () => {
    console.log("[Scheduled] Running heartbeat missing check");
    try {
        // Get all protected users
        const usersSnapshot = await db
            .collection("users")
            .where("role", "==", "protected")
            .get();
        for (const userDoc of usersSnapshot.docs) {
            const userId = userDoc.id;
            const userName = userDoc.data().displayName;
            // Get latest heartbeat from BigQuery
            const latest = await (0, bigquery_1.getLatestHeartbeat)(userId);
            if (!latest || !latest.timestamp) {
                // No heartbeat ever recorded — skip (might be new user)
                continue;
            }
            const lastTime = new Date(String(latest.timestamp));
            const minutesAgo = (Date.now() - lastTime.getTime()) / (1000 * 60);
            if (minutesAgo > HEARTBEAT_MISSING_THRESHOLD_MIN) {
                console.log(`[Scheduled] Heartbeat missing for ${userName} (${Math.round(minutesAgo)} min)`);
                // Find guardians
                const linksSnapshot = await db
                    .collection("guardian_links")
                    .where("protectedPersonId", "==", userId)
                    .where("status", "==", "active")
                    .get();
                for (const linkDoc of linksSnapshot.docs) {
                    const guardianId = linkDoc.data().guardianId;
                    await (0, fcm_1.sendHeartbeatMissingAlert)(guardianId, userName, Math.round(minutesAgo));
                }
            }
        }
    }
    catch (error) {
        console.error("[Scheduled] Heartbeat check error:", error);
    }
});
//# sourceMappingURL=heartbeatCheck.js.map