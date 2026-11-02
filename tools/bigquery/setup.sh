#!/usr/bin/env bash
# Create the BigQuery dataset + tables the Cloud Functions write to (idempotent).
#
#   tools/bigquery/setup.sh <project-id> [--location US] [--dry-run]
#
# - Dataset `shoudeng` (default location: US multi-region — see docs/ops/BIGQUERY.md).
# - Tables heartbeat_signals, location_reports, checkins, consent_audit from
#   tools/bigquery/schemas/<table>.json, partitioned by DAY on `timestamp` and
#   clustered by `user_id`.
# - Safe to re-run: existing dataset/tables are kept; columns added to a schema
#   file later are appended to the live table (additive only, never drops/retypes).
# - --dry-run prints the commands without calling BigQuery.
#
# Needs: bq (Google Cloud SDK) logged in as an owner/BigQuery admin of the project, python3.
set -euo pipefail

DATASET="shoudeng"
TABLES=(heartbeat_signals location_reports checkins consent_audit)
SCHEMA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/schemas"

PROJECT=""
LOCATION="US"
DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --location) LOCATION="$2"; shift 2 ;;
    --location=*) LOCATION="${1#*=}"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) PROJECT="$1"; shift ;;
  esac
done
if [[ -z "$PROJECT" ]]; then
  echo "Usage: $0 <project-id> [--location US] [--dry-run]" >&2
  exit 2
fi

BQ=(bq --project_id="$PROJECT" --headless)

run() {
  echo "+ $*"
  if [[ $DRY_RUN -eq 0 ]]; then "$@"; fi
}

exists() { # exists <bq show args...>
  [[ $DRY_RUN -eq 1 ]] && return 1
  "${BQ[@]}" show "$@" >/dev/null 2>&1
}

json_get() { # json_get <python expression on `d`>   (stdin: JSON)
  python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"
}

upper() { tr '[:lower:]' '[:upper:]' <<<"$1"; } # macOS ships bash 3.2 (no ${x^^})

if [[ $DRY_RUN -eq 0 ]] && ! command -v bq >/dev/null; then
  echo "bq not found — install the Google Cloud SDK (brew install --cask google-cloud-sdk)." >&2
  exit 1
fi

# --- Dataset -------------------------------------------------------------------
if exists --dataset "$PROJECT:$DATASET"; then
  actual=$("${BQ[@]}" show --format=json --dataset "$PROJECT:$DATASET" | json_get 'd.get("location","")')
  echo "= dataset $PROJECT:$DATASET exists (location $actual)"
  if [[ "$(upper "$actual")" != "$(upper "$LOCATION")" ]]; then
    echo "  ! location is $actual, not $LOCATION — a dataset's location can't be changed; tables are created there." >&2
  fi
else
  run "${BQ[@]}" --location="$LOCATION" mk --dataset \
    --description "Lantern Care / 守灯 history: heartbeats, locations, check-ins, consent audit" \
    "$PROJECT:$DATASET"
fi

# --- Tables --------------------------------------------------------------------
for table in "${TABLES[@]}"; do
  schema="$SCHEMA_DIR/$table.json"
  ref="$PROJECT:$DATASET.$table"
  if exists "$ref"; then
    info=$("${BQ[@]}" show --format=json "$ref")
    partition=$(json_get '(d.get("timePartitioning") or {}).get("field","(none)")' <<<"$info")
    clustering=$(json_get '",".join((d.get("clustering") or {}).get("fields",[])) or "(none)"' <<<"$info")
    missing=$(python3 -c '
import json, sys
live = {f["name"] for f in json.load(sys.stdin)["schema"]["fields"]}
print(" ".join(f["name"] for f in json.load(open(sys.argv[1])) if f["name"] not in live))
' "$schema" <<<"$info")
    echo "= table $ref exists (partition: $partition, clustering: $clustering)"
    [[ "$partition" == "timestamp" ]] || echo "  ! not partitioned on timestamp — recreate it to get partition pruning" >&2
    [[ "$clustering" == "user_id" ]] || echo "  ! not clustered by user_id" >&2
    if [[ -n "$missing" ]]; then
      echo "  + adding columns: $missing"
      run "${BQ[@]}" update -t "$ref" "$schema"
    fi
  else
    run "${BQ[@]}" mk --table \
      --time_partitioning_type=DAY \
      --time_partitioning_field=timestamp \
      --clustering_fields=user_id \
      "$ref" "$schema"
  fi
done

echo "Done. Verify: bq --project_id=$PROJECT ls $DATASET"
