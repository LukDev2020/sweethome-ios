import { BigQuery } from "@google-cloud/bigquery";
import * as crypto from "crypto";
import { v4 as uuidv4 } from "uuid";

const bigquery = new BigQuery();
const DATASET = "shoudeng";

/**
 * Compute SHA-256 hash of all fields for tamper-proof integrity.
 */
function computeRowHash(fields: Record<string, unknown>): string {
  const sorted = Object.keys(fields)
    .sort()
    .map((k) => `${k}=${String(fields[k] ?? "")}`)
    .join("|");
  return crypto.createHash("sha256").update(sorted).digest("hex");
}

/**
 * Insert a heartbeat signal into BigQuery.
 */
export async function insertHeartbeat(data: {
  userId: string;
  timestamp: string;
  source: string;
  batteryLevel?: number;
  batteryState?: string;
  latitude?: number;
  longitude?: number;
  accuracy?: number;
}): Promise<void> {
  const row: Record<string, unknown> = {
    id: uuidv4(),
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
export async function insertLocationReport(data: {
  userId: string;
  latitude: number;
  longitude: number;
  accuracy: number;
  altitude?: number;
  speed?: number;
  timestamp: string;
  isInSafeZone?: boolean;
  safeZoneName?: string;
}): Promise<void> {
  const row: Record<string, unknown> = {
    id: uuidv4(),
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
export async function insertCheckin(data: {
  userId: string;
  timestamp: string;
  latitude?: number;
  longitude?: number;
  note?: string;
}): Promise<void> {
  const row: Record<string, unknown> = {
    id: uuidv4(),
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
export async function insertConsentAudit(data: {
  userId: string;
  consentType: string;
  action: string;
  grantedTo: string;
  detail?: string;
  ipAddress?: string;
  deviceInfo?: string;
}): Promise<void> {
  const row: Record<string, unknown> = {
    id: uuidv4(),
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
export async function queryHeartbeats(
  userId: string,
  startTime: string,
  endTime: string
): Promise<Record<string, unknown>[]> {
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
export async function queryLocations(
  userId: string,
  startTime: string,
  endTime: string
): Promise<Record<string, unknown>[]> {
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
export async function getLatestHeartbeat(
  userId: string
): Promise<Record<string, unknown> | null> {
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
export async function computeDailyMerkleRoot(
  table: string,
  date: string
): Promise<{ root: string; count: number }> {
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
  let hashes = rows.map((r: Record<string, unknown>) => String(r.row_hash));

  while (hashes.length > 1) {
    const next: string[] = [];
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
