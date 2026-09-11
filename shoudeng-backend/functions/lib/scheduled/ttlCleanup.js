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
exports.ttlCleanup = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
const bigquery_1 = require("@google-cloud/bigquery");
const rateLimit_1 = require("../middleware/rateLimit");
const storage_1 = require("../services/storage");
const db = admin.firestore();
const bigquery = new bigquery_1.BigQuery();
const DATASET = "shoudeng";
// TTL rules (days)
const TTL = {
    heartbeat_signals: { free: 7, paid: 90 },
    location_reports: { free: 7, paid: 90 },
    checkins: { free: 30, paid: -1 }, // -1 = never delete
    // consent_audit: never deleted
    // sos_events: never deleted
};
/**
 * Scheduled function: runs daily at 3 AM UTC.
 * Cleans up expired data from BigQuery, respecting evidence holds.
 */
exports.ttlCleanup = functions.pubsub
    .schedule("0 3 * * *")
    .timeZone("Asia/Shanghai")
    .onRun(async () => {
    console.log("[Scheduled] Running TTL cleanup");
    try {
        // Get active evidence holds
        const holdsSnapshot = await db
            .collection("evidence_holds")
            .where("expiresAt", ">", admin.firestore.Timestamp.now())
            .get();
        const holds = holdsSnapshot.docs.map((doc) => ({
            protectedPersonId: doc.data().protectedPersonId,
            start: doc.data().timeWindowStart.toDate(),
            end: doc.data().timeWindowEnd.toDate(),
        }));
        console.log(`[TTL] Active evidence holds: ${holds.length}`);
        for (const [table, ttl] of Object.entries(TTL)) {
            // Use paid TTL if any user has an active subscription
            // In production, would run per-user with their specific plan
            const retentionDays = ttl.free;
            if (retentionDays === -1) {
                console.log(`[TTL] Skipping ${table} — no TTL`);
                continue;
            }
            const cutoffDate = new Date(Date.now() - retentionDays * 24 * 60 * 60 * 1000);
            // Build hold exclusion clauses
            let holdClauses = "";
            if (holds.length > 0) {
                const exclusions = holds
                    .map((h) => `NOT (user_id = '${h.protectedPersonId}' AND timestamp BETWEEN '${h.start.toISOString()}' AND '${h.end.toISOString()}')`)
                    .join(" AND ");
                holdClauses = `AND ${exclusions}`;
            }
            const query = `
          DELETE FROM \`${DATASET}.${table}\`
          WHERE timestamp < @cutoff
          ${holdClauses}
        `;
            try {
                const [job] = await bigquery.createQueryJob({
                    query,
                    params: { cutoff: cutoffDate.toISOString() },
                });
                const [rows] = await job.getQueryResults();
                console.log(`[TTL] Cleaned ${table}: cutoff ${cutoffDate.toISOString()}`);
            }
            catch (error) {
                console.error(`[TTL] Failed to clean ${table}:`, error);
            }
        }
        // Clean up expired evidence holds
        const expiredHolds = await db
            .collection("evidence_holds")
            .where("expiresAt", "<", admin.firestore.Timestamp.now())
            .get();
        for (const doc of expiredHolds.docs) {
            await doc.ref.delete();
            console.log(`[TTL] Removed expired evidence hold ${doc.id}`);
        }
        // Clean up expired invite codes
        const expiredInvites = await db
            .collection("invites")
            .where("status", "==", "pending")
            .where("expiresAt", "<", admin.firestore.Timestamp.now())
            .get();
        const batch = db.batch();
        expiredInvites.docs.forEach((doc) => {
            batch.update(doc.ref, { status: "expired" });
        });
        await batch.commit();
        console.log(`[TTL] Expired ${expiredInvites.size} invites`);
        // Clean up expired evidence share links
        const expiredShares = await db
            .collection("evidence_shares")
            .where("expiresAt", "<", admin.firestore.Timestamp.now())
            .get();
        for (const doc of expiredShares.docs) {
            await doc.ref.delete();
        }
        console.log(`[TTL] Removed ${expiredShares.size} expired share links`);
        // Clean up rate limit documents
        const rateLimitsCleaned = await (0, rateLimit_1.cleanupRateLimits)();
        console.log(`[TTL] Cleaned ${rateLimitsCleaned} rate limit entries`);
        // Clean up expired evidence files from Cloud Storage (older than 90 days)
        try {
            const evidenceCleaned = await (0, storage_1.cleanupExpiredEvidence)(90);
            console.log(`[TTL] Cleaned ${evidenceCleaned} expired evidence files`);
        }
        catch (storageError) {
            console.error("[TTL] Evidence cleanup error:", storageError);
        }
    }
    catch (error) {
        console.error("[Scheduled] TTL cleanup error:", error);
    }
});
//# sourceMappingURL=ttlCleanup.js.map