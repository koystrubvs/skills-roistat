#!/bin/sh
# Roistat calls analytics
# Usage: bash scripts/calls.sh --project ID --date-from YYYY-MM-DD [--date-to ...] [--interval ...]
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"
load_config
parse_common_params "$@"
require_project
require_dates

INTERVAL=""
for arg in "$@"; do
    case "$_prev" in
        --interval) INTERVAL="$arg" ;;
    esac
    _prev="$arg"
done

_metrics="calls,uniqueCalls,uniquePhoneCalls,missedCalls,missedCallsShare,answeredCalls,duration,callCost,callsConversion"

_interval_json=""
if [ -n "$INTERVAL" ]; then
    _interval_json=", \"interval\": \"$INTERVAL\""
fi

_body="{
  \"dimensions\": [\"marker_level_1\"],
  \"metrics\": [$(printf '%s' "$_metrics" | sed 's/[^,]*/"&"/g')],
  \"period\": {\"from\": \"${DATE_FROM}T00:00:00\", \"to\": \"${DATE_TO}T23:59:59\"}
  $_interval_json
}"

_cache_dir=$(cache_dir_for_project "$PROJECT")
_ck=$(cache_key "calls_${DATE_FROM}_${DATE_TO}_${INTERVAL}")
_cache_file="${_cache_dir}/reports/calls_${_ck}.tsv"

if [ -z "$NO_CACHE" ] && cache_get "$_cache_file" > /dev/null 2>&1; then
    echo "(cached)"
    print_tsv_head "$_cache_file"
    exit 0
fi

echo "Fetching calls data for project $PROJECT ($DATE_FROM — $DATE_TO)..."
_resp=$(roistat_post_project "/project/analytics/data" "$PROJECT" "$_body")

printf '%s' "$_resp" | python3 -c "
import json, sys

d = json.load(sys.stdin)
data = d.get('data', [])

rows = []
for block in data:
    items = block.get('items', []) if isinstance(block, dict) else []
    period_label = ''
    if isinstance(block, dict):
        pf = block.get('period', {}).get('from', '')
        if pf: period_label = pf[:10]

    for item in items:
        dims = item.get('dimensions', {})
        metrics = item.get('metrics', [])

        dim_title = ''
        for k, v in dims.items():
            dim_title = v.get('title', '') if isinstance(v, dict) else str(v)

        row = {}
        if period_label:
            row['period'] = period_label
        row['channel'] = dim_title

        for m in metrics:
            if isinstance(m, dict):
                name = m.get('metric_name', '')
                val = m.get('value', 0)
                if isinstance(val, float) and val == int(val):
                    val = int(val)
                elif isinstance(val, float):
                    val = round(val, 2)
                row[name] = val
        rows.append(row)

if not rows:
    print('No calls data.')
    sys.exit(0)

all_keys = []
for r in rows:
    for k in r:
        if k not in all_keys:
            all_keys.append(k)

with open('$_cache_file', 'w') as f:
    f.write('\t'.join(all_keys) + '\n')
    for r in rows:
        f.write('\t'.join(str(r.get(k,'')) for k in all_keys) + '\n')

print('\t'.join(all_keys))
for i, r in enumerate(rows):
    if i >= 30:
        print('... ({} more rows)'.format(len(rows) - 30))
        break
    print('\t'.join(str(r.get(k,'')) for k in all_keys))

print()
print('Cached: $_cache_file')
" 2>&1
