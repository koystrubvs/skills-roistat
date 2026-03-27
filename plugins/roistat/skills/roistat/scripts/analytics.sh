#!/bin/sh
# Roistat analytics data — main report script
# Usage: bash scripts/analytics.sh --project ID --date-from YYYY-MM-DD [--date-to ...] [--dimension ...] [--metrics ...] [--interval ...]
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"
load_config

# Parse params
PROJECT=""
DATE_FROM=""
DATE_TO=""
DIMENSION="marker_level_1"
METRICS="visits,leads,sales,revenue,marketing_cost,roi,cpl,conversion_visits_to_leads"
INTERVAL=""
NO_CACHE=""
CSV_OUT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --project)   PROJECT="$2"; shift 2 ;;
        --date-from) DATE_FROM="$2"; shift 2 ;;
        --date-to)   DATE_TO="$2"; shift 2 ;;
        --dimension) DIMENSION="$2"; shift 2 ;;
        --metrics)   METRICS="$2"; shift 2 ;;
        --interval)  INTERVAL="$2"; shift 2 ;;
        --no-cache)  NO_CACHE="1"; shift ;;
        --csv)       CSV_OUT="$2"; shift 2 ;;
        *)           shift ;;
    esac
done

if [ -z "$PROJECT" ]; then
    echo "Error: --project <ID> is required." >&2; exit 1
fi
if [ -z "$DATE_FROM" ]; then
    echo "Error: --date-from YYYY-MM-DD is required." >&2; exit 1
fi
if [ -z "$DATE_TO" ]; then
    DATE_TO=$(date +%Y-%m-%d)
fi

# Build dimensions JSON array
_dims_json=$(printf '%s' "$DIMENSION" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip().split(',')))")

# Build metrics JSON array
_metrics_json=$(printf '%s' "$METRICS" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip().split(',')))")

# Build interval part
_interval_json=""
if [ -n "$INTERVAL" ]; then
    _interval_json=", \"interval\": \"$INTERVAL\""
fi

_body="{
  \"dimensions\": $_dims_json,
  \"metrics\": $_metrics_json,
  \"period\": {\"from\": \"${DATE_FROM}T00:00:00\", \"to\": \"${DATE_TO}T23:59:59\"}
  $_interval_json
}"

# Cache key
_cache_dir=$(cache_dir_for_project "$PROJECT")
_ck=$(cache_key "${DIMENSION}_${METRICS}_${DATE_FROM}_${DATE_TO}_${INTERVAL}")
_cache_file="${_cache_dir}/reports/analytics_${_ck}.tsv"

if [ -z "$NO_CACHE" ] && cache_get "$_cache_file" > /dev/null 2>&1; then
    echo "(cached)"
    print_tsv_head "$_cache_file"
    exit 0
fi

echo "Fetching analytics for project $PROJECT ($DATE_FROM — $DATE_TO)..."
_resp=$(roistat_post_project "/project/analytics/data" "$PROJECT" "$_body")

printf '%s' "$_resp" | python3 -c "
import json, sys, csv, io

d = json.load(sys.stdin)
data = d.get('data', [])
interval = '$INTERVAL'

def extract_items(block):
    if isinstance(block, dict):
        return block.get('items', [block])
    return [block]

rows = []

# Handle interval (time-series) vs flat response
if isinstance(data, list) and len(data) > 0:
    for block in data:
        items = []
        period_label = ''
        if isinstance(block, dict):
            items = block.get('items', [])
            period_from = block.get('period', {}).get('from', '')
            period_to = block.get('period', {}).get('to', '')
            if period_from:
                period_label = period_from[:10]
        else:
            items = data
            break

        for item in items:
            dims = item.get('dimensions', {})
            metrics_list = item.get('metrics', [])

            dim_title = ''
            for k, v in dims.items():
                if isinstance(v, dict):
                    dim_title = v.get('title', v.get('value', ''))
                else:
                    dim_title = str(v)

            row = {}
            if period_label:
                row['period'] = period_label
            row['channel'] = dim_title

            for m in metrics_list:
                if isinstance(m, dict):
                    name = m.get('metric_name', '')
                    val = m.get('value', 0)
                    if isinstance(val, float):
                        if val == int(val):
                            val = int(val)
                        else:
                            val = round(val, 2)
                    row[name] = val

            rows.append(row)

if not rows:
    print('No data returned.')
    sys.exit(0)

# Collect all keys
all_keys = []
for r in rows:
    for k in r:
        if k not in all_keys:
            all_keys.append(k)

# Write TSV
cache_path = '$_cache_file'
with open(cache_path, 'w') as f:
    f.write('\t'.join(all_keys) + '\n')
    for r in rows:
        vals = [str(r.get(k, '')) for k in all_keys]
        f.write('\t'.join(vals) + '\n')

# Print (max 30 rows)
print('\t'.join(all_keys))
for i, r in enumerate(rows):
    if i >= 30:
        print('... ({} more rows, full data in: {})'.format(len(rows) - 30, cache_path))
        break
    vals = [str(r.get(k, '')) for k in all_keys]
    print('\t'.join(vals))

if len(rows) <= 30:
    print()
    print('Cached: {}'.format(cache_path))

# CSV export
csv_path = '$CSV_OUT'
if csv_path:
    with open(csv_path, 'w', newline='', encoding='utf-8-sig') as f:
        w = csv.DictWriter(f, fieldnames=all_keys, delimiter=';')
        w.writeheader()
        w.writerows(rows)
    print('CSV exported: {}'.format(csv_path))
" 2>&1
