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
exports.insertHeartbeat = insertHeartbeat;
exports.insertLocationReport = insertLocationReport;
exports.insertCheckin = insertCheckin;
exports.insertConsentAudit = insertConsentAudit;
exports.queryHeartbeats = queryHeartbeats;
exports.queryLocations = queryLocations;
exports.getLatestHeartbeat = getLatestHeartbeat;
exports.computeDailyMerkleRoot = computeDailyMerkleRoot;
const bigquery_1 = require("@google-cloud/bigquery");
const crypto = __importStar(require("crypto"));
const uuid_1 = require("uuid");
const bigquery = new bigquery_1.BigQuery();
const DATASET = "shoudeng";
/**
 * Compute SHA-256 hash of all fields for tamper-proof integrity.
 */
function computeRowHash(fields) {
    const sorted = Object.keys(fields)
        .sort()
        .map((k) => `${k}=${String(fields[k] ?? "")}`)
        .join("|");
    return crypto.createHash("sha256").update(sorted).digest("hex");
}
/**
 * Insert a heartbeat signal into BigQuery.
 */
async function insertHeartbeat(data) {
    const row = {
        id: (0, uuid_1.v4)(),
        user_id: data.userId,
        timestamp: data.timestamp,
        source: data.source,
        battery_level: data.batteryLevel ?? null,
        battery_state: data.batteryState ?? null,
        latitude: data.latitude ?? null,
        longitude: data.longitude ?? null,
        accuracy: data.accuracy ?? null,
    };
    row.row_hash = computeRowHash(row);
    await bigquery.dataset(DATASET).table("heartbeat_signals").insert([row]);
}
/**
 * Insert a location report into BigQuery.
 */
async function insertLocationReport(data) {
    const row = {
        id: (0, uuid_1.v4)(),
        user_id: data.userId,
        timestamp: data.timestamp,
        latitude: data.latitude,
        longitude: data.longitude,
        accuracy: data.accuracy,
        altitude: data.altitude ?? null,
        speed: data.speed ?? null,
        is_in_safe_zone: data.isInSafeZone ?? null,
        safe_zone_name: data.safeZoneName ?? null,
    };
    row.row_hash = computeRowHash(row);
    await bigquery.dataset(DATASET).table("location_reports").insert([row]);
}
/**
 * Insert a check-in record into BigQuery.
 */
async function insertCheckin(data) {
    const row = {
        id: (0, uuid_1.v4)(),
        user_id: data.userId,
        timestamp: data.timestamp,
        latitude: data.latitude ?? null,
        longitude: data.longitude ?? null,
        note: data.note ?? null,
    };
    row.row_hash = computeRowHash(row);
    await bigquery.dataset(DATASET).table("checkins").insert([row]);
}
/**
 * Insert a consent audit record into BigQuery.
 */
async function insertConsentAudit(data) {
    const row = {
        id: (0, uuid_1.v4)(),
        user_id: data.userId,
        timestamp: new Date().toISOString(),
        consent_type: data.consentType,
        action: data.action,
        granted_to: data.grantedTo,
        detail: data.detail ?? null,
        ip_address: data.ipAddress ?? null,
        device_info: data.deviceInfo ?? null,
    };
    row.row_hash = computeRowHash(row);
    await bigquery.dataset(DATASET).table("consent_audit").insert([row]);
}
/**
 * Query heartbeat signals for a user within a time range.
 */
async function queryHeartbeats(userId, startTime, endTime) {
    const query = `
    SELECT * FROM \`${DATASET}.heartbeat_signals\`
    WHERE user_id = @userId
      AND timestamp BETWEEN @startTime AND @endTime
    ORDER BY timestamp DESC
  `;
    const [rows] = await bigquery.query({
        query,
        params: { userId, startTime, endTime },
    });
    return rows;
}
/**
 * Query location reports for a user within a time range.
 */
async function queryLocations(userId, startTime, endTime) {
    const query = `
    SELECT * FROM \`${DATASET}.location_reports\`
    WHERE user_id = @userId
      AND timestamp BETWEEN @startTime AND @endTime
    ORDER BY timestamp ASC
  `;
    const [rows] = await bigquery.query({
        query,
        params: { userId, startTime, endTime },
    });
    return rows;
}
/**
 * Get the latest heartbeat for a user.
 */
async function getLatestHeartbeat(userId) {
    const query = `
    SELECT * FROM \`${DATASET}.heartbeat_signals\`
    WHERE user_id = @userId
    ORDER BY timestamp DESC
    LIMIT 1
  `;
    const [rows] = await bigquery.query({ query, params: { userId } });
    return rows.length > 0 ? rows[0] : null;
}
/**
 * Compute Merkle root for integrity proof (daily scheduled job).
 */
async function computeDailyMerkleRoot(table, date) {
    const query = `
    SELECT row_hash FROM \`${DATASET}.${table}\`
    WHERE DATE(timestamp) = @date
    ORDER BY timestamp ASC
  `;
    const [rows] = await bigquery.query({ query, params: { date } });
    if (rows.length === 0) {
        return { root: "empty", count: 0 };
    }
    // Build Merkle tree from row hashes
    let hashes = rows.map((r) => String(r.row_hash));
    while (hashes.length > 1) {
        const next = [];
        for (let i = 0; i < hashes.length; i += 2) {
            const left = hashes[i];
            const right = i + 1 < hashes.length ? hashes[i + 1] : left;
            const combined = crypto
                .createHash("sha256")
                .update(left + right)
                .digest("hex");
            next.push(combined);
        }
        hashes = next;
    }
    return { root: hashes[0], count: rows.length };
}
//# sourceMappingURL=bigquery.js.map