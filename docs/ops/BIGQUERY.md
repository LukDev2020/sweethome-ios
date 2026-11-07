# BigQuery dataset `shoudeng` (project `sweethome-b4e82`)

Production has **no BigQuery datasets**; the functions log
`Not found: Dataset sweethome-b4e82:shoudeng`, so these writes fail today:

| Table | Written by | Read by |
|---|---|---|
| `heartbeat_signals` | `POST /v1/heartbeat` (`insertHeartbeat`) | guardian status fallback, `checkHeartbeatMissing`, evidence bundles, export, retention, integrity proofs |
| `location_reports` | `POST /v1/location/report` and `/v1/location/batch` (`insertLocationReport`) | evidence bundles / trail, export, retention, integrity proofs |
| `checkins` | `POST /v1/checkin` (`insertCheckin`) | export, retention |
| `consent_audit` | consent changes, invites, evidence access, payment (`insertConsentAudit`) | kept on purpose (legal audit trail) |

Integrity proofs themselves are stored in Firestore (`integrity_proofs/{date}`); they *read*
`heartbeat_signals` and `location_reports` (`DATE(timestamp) = @date`).

## Create it

Needs the Google Cloud SDK (`bq`) logged in as a project owner (`gcloud auth login`), and the
BigQuery API enabled (it is by default; otherwise
`gcloud services enable bigquery.googleapis.com --project sweethome-b4e82`).

Preview the commands (calls nothing):

```bash
tools/bigquery/setup.sh sweethome-b4e82 --dry-run
```

Create the dataset and tables:

```bash
tools/bigquery/setup.sh sweethome-b4e82
```

Check:

```bash
bq --project_id=sweethome-b4e82 ls shoudeng
```

The script is idempotent: an existing dataset/table is left alone (it warns if partitioning,
clustering or location differ), and columns that were added to a schema file later are
appended to the live table (additive only). No functions redeploy is needed — the next write
succeeds.

## Migrations

Run each migration **before** deploying the functions that write the new column.

### 2026-11 — `location_reports.activity_type` (STRING, NULLABLE)

The phone's motion tag (`stationary`, `walking`, `running`, `cycling`, `driving`, `unknown`)
for each position, sent with every `/v1/location/report` and `/v1/location/batch`. Incident
reports use it for the activity of history points (before this, they guessed from speed).

1. Check whether the column is there already:

   ```bash
   bq --project_id=sweethome-b4e82 show --schema --format=prettyjson shoudeng.location_reports | grep activity_type
   ```

2. Add it. The setup script appends missing columns (preview with `--dry-run` first):

   ```bash
   tools/bigquery/setup.sh sweethome-b4e82 --dry-run
   ```

   ```bash
   tools/bigquery/setup.sh sweethome-b4e82
   ```

   Or with SQL alone (same result, additive only):

   ```bash
   bq --project_id=sweethome-b4e82 query --use_legacy_sql=false 'ALTER TABLE shoudeng.location_reports ADD COLUMN IF NOT EXISTS activity_type STRING'
   ```

   If the dataset doesn't exist yet, `setup.sh` creates the table with the column already in it.

3. Run step 1 again to check the column is there, then deploy the functions.

Old rows have `activity_type = NULL`; reports fall back to speed for them. A deploy that lands
before the column exists (or in the few minutes streaming inserts take to see a new column)
still keeps the position: `insertLocationReport` retries without `activity_type` on
"no such field: activity_type" and logs
`location_reports has no activity_type column — run tools/bigquery/setup.sh`. Only the tag is
lost in that case, so treat that log line as a sign the migration was missed.

## Layout

- Schemas: `tools/bigquery/schemas/<table>.json` (source of truth). `shoudeng-backend/bigquery/schema.sql`
  is the same DDL for reading. `src/__tests__/bigquery.schema.test.ts` fails if the insert code,
  the JSON schemas, the DDL and the script drift apart.
- Every table: `PARTITION BY DATE(timestamp)` (daily, on the device event time) and
  `CLUSTER BY user_id` — every query filters on `user_id` and/or a time range (history,
  evidence windows, per-user export/erasure, retention `DELETE … WHERE timestamp < cutoff`,
  integrity proofs by day), so both prune scans.
- No partition expiration: retention is per plan and per user (`ttlCleanup` →
  `applyBigQueryRetention`), and evidence holds must survive it. `consent_audit` is never
  deleted.
- `id`, `user_id`, `timestamp` are REQUIRED (and `latitude`/`longitude` for
  `location_reports`); `ingested_at` defaults to `CURRENT_TIMESTAMP()` and is not written
  by the code.

## Location: `US` multi-region

The Cloud Functions run in `us-central1`. BigQuery dataset location can't be changed later, so:

- **US multi-region** contains `us-central1`; reads and streaming inserts from the functions
  are same-location (no cross-region egress), and storage/query prices are the same as a
  single US region.
- Firebase's own BigQuery exports (Analytics, Crashlytics, Firestore export) default to **US**,
  and BigQuery can only join tables in the same location — `us-central1` would make them
  unjoinable with this data.
- Multi-region storage is replicated across US regions, which suits the evidence /
  consent-audit role of this data.

Pick `--location us-central1` only if a data-residency commitment requires a single region.
Either way the data sits in the US like Firestore and Functions do today; the privacy policy
must keep saying so for EU / UK / Japan users.

## Permissions

Gen-1 functions run as `sweethome-b4e82@appspot.gserviceaccount.com`. New projects give it
Editor, which includes BigQuery read/write and job creation. If that role was ever narrowed:

```bash
gcloud projects add-iam-policy-binding sweethome-b4e82 --member=serviceAccount:sweethome-b4e82@appspot.gserviceaccount.com --role=roles/bigquery.jobUser
```

```bash
bq add-iam-policy-binding --member=serviceAccount:sweethome-b4e82@appspot.gserviceaccount.com --role=roles/bigquery.dataEditor sweethome-b4e82:shoudeng
```
