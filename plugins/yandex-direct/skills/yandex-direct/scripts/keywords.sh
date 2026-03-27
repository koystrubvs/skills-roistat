#!/bin/sh
# Yandex Direct Keywords — report on keyword performance
# Usage: bash keywords.sh --date1 YYYY-MM-DD [--date2 ...] [--campaigns 123,456] [--limit 50] [--sort cost|clicks|impressions] [--csv path]
# POSIX sh compatible

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"

load_config
parse_common_params "$@"

SORT_BY="Cost"

while [ $# -gt 0 ]; do
    case "$1" in
        --sort) SORT_BY="$2"; shift 2 ;;
        *)      shift ;;
    esac
done

# Normalize sort field
case "$SORT_BY" in
    cost|Cost)             SORT_BY="Cost" ;;
    clicks|Clicks)         SORT_BY="Clicks" ;;
    impressions|Impressions) SORT_BY="Impressions" ;;
    ctr|Ctr)               SORT_BY="Ctr" ;;
    conversions|Conversions) SORT_BY="Conversions" ;;
    *)                     SORT_BY="Cost" ;;
esac

REPORT_NAME="keywords_${DATE1}_${DATE2}_$$"

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
            'CampaignName', 'AdGroupName', 'Criterion', 'CriterionId',
            'Impressions', 'Clicks', 'Ctr', 'Cost', 'AvgCpc',
            'Conversions', 'CostPerConversion', 'BounceRate'
        ],
        'OrderBy': [{'Field': '$SORT_BY', 'SortOrder': 'DESCENDING'}],
        'ReportName': '$REPORT_NAME',
        'ReportType': 'CRITERIA_PERFORMANCE_REPORT',
        'DateRangeType': 'CUSTOM_DATE',
        'Format': 'TSV',
        'IncludeVAT': 'YES',
        'IncludeDiscount': 'YES'
    }
}
filter_block = '$FILTER_BLOCK'
if filter_block:
    import re
    f = json.loads('{' + filter_block.rstrip(',') + '}')
    body['params']['SelectionCriteria'].update(f)
print(json.dumps(body, ensure_ascii=False))
")

# Check cache
CACHE_KEY=$(cache_key "keywords_${DATE1}_${DATE2}_${CAMPAIGN_IDS}_${SORT_BY}")
CACHE_FILE="$CACHE_DIR/reports/${CACHE_KEY}.tsv"

if [ -z "$NO_CACHE" ] && [ -f "$CACHE_FILE" ] && [ -s "$CACHE_FILE" ]; then
    echo "=== Keywords [$DATE1 — $DATE2] sorted by $SORT_BY (cached) ===" >&2
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

echo "=== Keywords [$DATE1 — $DATE2] sorted by $SORT_BY ===" >&2

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
