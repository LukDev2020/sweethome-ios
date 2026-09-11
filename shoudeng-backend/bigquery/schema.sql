-- ShouDeng BigQuery Schema
-- Dataset: shoudeng
-- All tables use date partitioning on timestamp and clustering on user_id

-- 1. Heartbeat Signals
-- ~12 writes/hour per user, used for liveness detection
CREATE TABLE IF NOT EXISTS shoudeng.heartbeat_signals (
  id            STRING    NOT NULL,
  user_id       STRING    NOT NULL,
  timestamp     TIMESTAMP NOT NULL,
  source        STRING,            -- "timer" | "significantLocation" | "silentPush" | "appForeground" | "regionEvent" | "watchSync"
  battery_level FLOAT64,
  battery_state STRING,            -- "charging" | "unplugged" | "full" | "unknown"
  latitude      FLOAT64,
  longitude     FLOAT64,
  accuracy      FLOAT64,
  row_hash      STRING,            -- SHA-256 integrity hash
  ingested_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY DATE(timestamp)
CLUSTER BY user_id;

-- 2. Location Reports
-- Continuous during movement, every 10s during SOS
CREATE TABLE IF NOT EXISTS shoudeng.location_reports (
  id              STRING    NOT NULL,
  user_id         STRING    NOT NULL,
  timestamp       TIMESTAMP NOT NULL,
  latitude        FLOAT64   NOT NULL,
  longitude       FLOAT64   NOT NULL,
  accuracy        FLOAT64,
  altitude        FLOAT64,
  speed           FLOAT64,
  is_in_safe_zone BOOL,
  safe_zone_name  STRING,
  row_hash        STRING,
  ingested_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY DATE(timestamp)
CLUSTER BY user_id;

-- 3. Check-ins
-- 1-3 per day per user
CREATE TABLE IF NOT EXISTS shoudeng.checkins (
  id        STRING    NOT NULL,
  user_id   STRING    NOT NULL,
  timestamp TIMESTAMP NOT NULL,
  latitude  FLOAT64,
  longitude FLOAT64,
  note      STRING,
  row_hash  STRING,
  ingested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY DATE(timestamp)
CLUSTER BY user_id;

-- 4. Consent Audit Log
-- Immutable, never deleted — legal compliance
CREATE TABLE IF NOT EXISTS shoudeng.consent_audit (
  id             STRING    NOT NULL,
  user_id        STRING    NOT NULL,
  timestamp      TIMESTAMP NOT NULL,
  consent_type   STRING,           -- "location" | "notification" | "motion" | "guardian_link" | "data_export"
  action         STRING,           -- "granted" | "revoked" | "exported" | "accessed"
  granted_to     STRING,           -- target user ID or "system"
  detail         STRING,
  ip_address     STRING,
  device_info    STRING,
  row_hash       STRING,
  ingested_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY DATE(timestamp)
CLUSTER BY user_id;
