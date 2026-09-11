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
exports.computeIntegrityProof = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
const bigquery_1 = require("../services/bigquery");
const db = admin.firestore();
/**
 * Scheduled function: runs daily at 4 AM UTC.
 * Computes Merkle roots for the previous day's BigQuery data.
 * Stores in Firestore integrity_proofs collection for tamper detection.
 */
exports.computeIntegrityProof = functions.pubsub
    .schedule("0 4 * * *")
    .timeZone("Asia/Shanghai")
    .onRun(async () => {
    // Compute for yesterday
    const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const dateStr = yesterday.toISOString().substring(0, 10);
    console.log(`[Scheduled] Computing integrity proof for ${dateStr}`);
    try {
        // Compute Merkle roots for each table
        const [heartbeatResult, locationResult] = await Promise.all([
            (0, bigquery_1.computeDailyMerkleRoot)("heartbeat_signals", dateStr),
            (0, bigquery_1.computeDailyMerkleRoot)("location_reports", dateStr),
        ]);
        const totalRecords = heartbeatResult.count + locationResult.count;
        // Store in Firestore
        await db
            .collection("integrity_proofs")
            .doc(dateStr)
            .set({
            date: dateStr,
            heartbeatMerkleRoot: heartbeatResult.root,
            locationMerkleRoot: locationResult.root,
            recordCount: totalRecords,
            computedAt: admin.firestore.Timestamp.now(),
        });
        console.log(`[Scheduled] Integrity proof for ${dateStr}: ` +
            `heartbeats=${heartbeatResult.count} (${heartbeatResult.root.substring(0, 12)}...), ` +
            `locations=${locationResult.count} (${locationResult.root.substring(0, 12)}...)`);
    }
    catch (error) {
        console.error(`[Scheduled] Integrity proof computation failed for ${dateStr}:`, error);
    }
});
//# sourceMappingURL=integrityProof.js.map