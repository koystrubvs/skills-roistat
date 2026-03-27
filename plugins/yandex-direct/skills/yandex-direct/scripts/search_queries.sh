#!/bin/sh
# Yandex Direct Search Queries — what people actually searched
# Usage: bash search_queries.sh --date1 YYYY-MM-DD [--date2 ...] [--campaigns 123,456] [--limit 50] [--csv path]
# Useful for checking agency work: finding irrelevant queries, missing negatives
# POSIX sh compatible

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"

load_config
parse_common_params "$@"

REPORT_NAME="search_queries_${DATE1}_${DATE2}_$$"

# Build filter for specific campaigns
FILTER_BLOCK=""
if [ -n "$CAMPAIGN_IDS" ]; then
    IDS_JSON=$(printf '%s' "$CAMPAIGN_IDS" | python3 -c "import sys; ids=sys.stdin.read().strip().split(','); print(','.join(['\"'+i.strip()+'\"' for i in ids]))")
    FILTER_BLOCK="\"Filter\": [{\"Field\": \"CampaignId\", \"Operator\": \"IN\", \"Values\": [$IDS_JSON]}],"
fi

BODY=$(python3 -c "
import json
body = {
    'params': {
        'SelectionCriteria': {
            'DateFrom': '$DATE1',
            'DateTo': '$DATE2'
        },
        'FieldNames': [
            'CampaignName', 'AdGroupName', 'Query', 'Criterion',
            'Impressions', 'Clicks', 'Ctr', 'Cost', 'AvgCpc',
            'Conversions', 'CostPerConversion'
        ],
        'OrderBy': [{'Field': 'Cost', 'SortOrder': 'DESCENDING'}],
        'ReportName': '$REPORT_NAME',
        'ReportType': 'SEARCH_QUERY_PERFORMANCE_REPORT',
        'DateRangeType': 'CUSTOM_DATE',
        'Format': 'TSV',
        'IncludeVAT': 'YES',
        'IncludeDiscount': 'YES'
    }
}
filter_block = '$FILTER_BLOCK'
if filter_block:
    f = json.loads('{' + filter_block.rstrip(',') + '}')
    body['params']['SelectionCriteria'].update(f)
print(json.dumps(body, ensure_ascii=False))
")

# Check cache
CACHE_KEY=$(cache_key "sq_${DATE1}_${DATE2}_${CAMPAIGN_IDS}")
CACHE_FILE="$CACHE_DIR/reports/${CACHE_KEY}.tsv"

if [ -z "$NO_CACHE" ] && [ -f "$CACHE_FILE" ] && [ -s "$CACHE_FILE" ]; then
    echo "=== Search Queries [$DATE1 — $DATE2] (cached) ===" >&2
    DATA=$(cat "$CACHE_FILE")
    if [ -n "$CSV_OUT" ]; then
        printf '%s\n' "$DATA" | tr '\t' ',' > "$CSV_OUT"
        echo "Saved to $CSV_OUT" >&2
    fi
    if [ -n "$LIMIT" ]; then
        HEADER=$(printf '%s\n' "$DATA" | head -1)
        printf '%s\n' "$HEADER"
        printf '%s\n' "$DATA" | tail -n +2 | head -n "$LIMIT"
    else
        print_tsv_head "$DATA"
    fi
    exit 0
fi

echo "=== Search Queries [$DATE1 — $DATE2] ===" >&2

RESULT=$(direct_report "$BODY")

if [ -z "$RESULT" ]; then
    echo "Error: empty report result" >&2
    exit 1
fi

# Cache
mkdir -p "$CACHE_DIR/reports"
printf '%s\n' "$RESULT" | cache_put "$CACHE_FILE"

# CSV export
if [ -n "$CSV_OUT" ]; then
    printf '%s\n' "$RESULT" | tr '\t' ',' > "$CSV_OUT"
    echo "Saved to $CSV_OUT" >&2
fi

if [ -n "$LIMIT" ]; then
    HEADER=$(printf '%s\n' "$RESULT" | head -1)
    printf '%s\n' "$HEADER"
    printf '%s\n' "$RESULT" | tail -n +2 | head -n "$LIMIT"
else
    print_tsv_head "$RESULT"
fi
