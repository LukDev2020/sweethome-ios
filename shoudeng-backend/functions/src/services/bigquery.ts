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

/** The phone's motion tag (Location.ActivityType in the app; CoreMotion says "automotive"). */
export const LOCATION_ACTIVITY_TYPES = ["stationary", "walking", "running", "cycling", "driving", "unknown"] as const;

/** `activity_type` column value: a known tag, or null — never free text from the client. */
export function locationActivityType(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const tag = value.trim().toLowerCase();
  if (tag === "automotive") return "driving";
  return (LOCATION_ACTIVITY_TYPES as readonly string[]).includes(tag) ? tag : null;
}

/**
 * The live table has no activity_type column yet (deployed before
 * `tools/bigquery/setup.sh` added it): BigQuery rejects the whole row with
 * "no such field: activity_type".
 */
function isMissingActivityColumn(error: unknown): boolean {
  const e = error as { message?: unknown; errors?: unknown };
  let text = typeof e?.message === "string" ? e.message : "";
  try { text += JSON.stringify(e?.errors ?? ""); } catch { /* ignore */ }
  return /no such field/i.test(text) && text.includes("activity_type");
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
  activityType?: string;
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
    activity_type: locationActivityType(data.activityType),
  };
  row.row_hash = computeRowHash(row);

  const table = bigquery.dataset(DATASET).table("location_reports");
  try {
    await table.insert([row]);
  } catch (error) {
    // Migration not run yet: keep the position, lose only the tag (docs/ops/BIGQUERY.md)
    if (!isMissingActivityColumn(error)) throw error;
    console.warn("[BigQuery] location_reports has no activity_type column — run tools/bigquery/setup.sh; inserting without it");
    const withoutActivity = { ...row };
    delete withoutActivity.activity_type;
    delete withoutActivity.row_hash;
    withoutActivity.row_hash = computeRowHash(withoutActivity);
    await table.insert([withoutActivity]);
  }
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
 * BigQuery returns TIMESTAMP / DATETIME / DATE columns as wrapper objects
 * (`BigQueryTimestamp { value: "2026-10-30T12:00:00.000Z" }`). Serialising one
 * with `res.json` yields `{"value": ...}` and `String(obj)` yields
 * "[object Object]", so every row read from BigQuery is normalised to ISO-8601
 * strings before it reaches route code.
 */
export function bqTimestampToIso(v: unknown): string | null {
  if (v == null) return null;
  if (v instanceof Date) return isNaN(v.getTime()) ? null : v.toISOString();
  if (typeof v === "object" && "value" in (v as Record<string, unknown>)) {
    return bqTimestampToIso((v as { value: unknown }).value);
  }
  if (typeof v === "string" || typeof v === "number") {
    const d = new Date(v);
    return isNaN(d.getTime()) ? null : d.toISOString();
  }
  return null;
}

const TIMESTAMP_COLUMNS = new Set(["timestamp", "created_at", "updated_at"]);

export function normalizeBigQueryRow(
  row: Record<string, unknown>
): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(row)) {
    const isWrapper =
      v != null && typeof v === "object" && !Array.isArray(v) && "value" in (v as object);
    out[k] = TIMESTAMP_COLUMNS.has(k) || isWrapper || v instanceof Date
      ? bqTimestampToIso(v)
      : v;
  }
  return out;
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
  return rows.map(normalizeBigQueryRow);
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
  return rows.map(normalizeBigQueryRow);
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
  return rows.length > 0 ? normalizeBigQueryRow(rows[0]) : null;
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
