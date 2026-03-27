#!/bin/sh
# Yandex Direct Reports API — campaign/ad performance stats
# Usage: bash report.sh --date1 YYYY-MM-DD [--date2 ...] [--type campaign|daily|adgroup] [--campaigns 123,456] [--csv path]
# POSIX sh compatible

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"

load_config
parse_common_params "$@"

REPORT_TYPE="campaign"

# Parse extra params
for arg in "$@"; do
    case "$_prev" in
        --type) REPORT_TYPE="$arg" ;;
    esac
    _prev="$arg"
done

# Reset _prev
_prev=""
while [ $# -gt 0 ]; do
    case "$1" in
        --type) REPORT_TYPE="$2"; shift 2 ;;
        *)      shift ;;
    esac
done

# Build report request based on type
REPORT_NAME="direct_${REPORT_TYPE}_${DATE1}_${DATE2}_$$"

case "$REPORT_TYPE" in
    campaign)
        FIELDS='"CampaignName","CampaignId","Impressions","Clicks","Ctr","Cost","AvgCpc","Conversions","CostPerConversion","BounceRate"'
        REPORT_TYPE_API="CAMPAIGN_PERFORMANCE_REPORT"
        ;;
    daily)
        FIELDS='"Date","Impressions","Clicks","Ctr","Cost","AvgCpc","Conversions","CostPerConversion"'
        REPORT_TYPE_API="CUSTOM_REPORT"
        ;;
    adgroup)
        FIELDS='"CampaignName","AdGroupName","AdGroupId","Impressions","Clicks","Ctr","Cost","AvgCpc","Conversions","CostPerConversion"'
        REPORT_TYPE_API="ADGROUP_PERFORMANCE_REPORT"
        ;;
    search_query)
        FIELDS='"CampaignName","AdGroupName","Query","Impressions","Clicks","Ctr","Cost","Conversions"'
        REPORT_TYPE_API="SEARCH_QUERY_PERFORMANCE_REPORT"
        ;;
    *)
        echo "Error: Unknown report type '$REPORT_TYPE'. Use: campaign, daily, adgroup, search_query" >&2
        exit 1
        ;;
esac

# Build filter for specific campaigns
FILTER_BLOCK=""
if [ -n "$CAMPAIGN_IDS" ]; then
    # Convert comma-separated to JSON array
    IDS_JSON=$(printf '%s' "$CAMPAIGN_IDS" | python3 -c "import sys; ids=sys.stdin.read().strip().split(','); print(','.join(['\"'+i.strip()+'\"' for i in ids]))")
    FILTER_BLOCK=$(cat <<ENDJSON
      "Filter": [
        {
          "Field": "CampaignId",
          "Operator": "IN",
          "Values": [$IDS_JSON]
        }
      ],
ENDJSON
)
fi

BODY=$(cat <<ENDJSON
{
  "params": {
    "SelectionCriteria": {
      "DateFrom": "$DATE1",
      "DateTo": "$DATE2"${FILTER_BLOCK:+,
$FILTER_BLOCK}
    },
    "FieldNames": [$FIELDS],
    "ReportName": "$REPORT_NAME",
    "ReportType": "$REPORT_TYPE_API",
    "DateRangeType": "CUSTOM_DATE",
    "Format": "TSV",
    "IncludeVAT": "YES",
    "IncludeDiscount": "YES"
  }
}
ENDJSON
)

# Fix JSON — remove trailing comma before closing brace if filter empty
BODY=$(printf '%s' "$BODY" | python3 -c "
import json, sys
# Parse loosely, re-serialize
text = sys.stdin.read()
# Simple approach: just parse the JSON
data = json.loads(text)
print(json.dumps(data, ensure_ascii=False))
")

# Check cache
CACHE_KEY=$(cache_key "report_${REPORT_TYPE}_${DATE1}_${DATE2}_${CAMPAIGN_IDS}")
CACHE_FILE="$CACHE_DIR/reports/${CACHE_KEY}.tsv"

if [ -z "$NO_CACHE" ] && [ -f "$CACHE_FILE" ] && [ -s "$CACHE_FILE" ]; then
    echo "=== Report: $REPORT_TYPE [$DATE1 — $DATE2] (cached) ===" >&2
    DATA=$(cat "$CACHE_FILE")
    if [ -n "$CSV_OUT" ]; then
        printf '%s\n' "$DATA" | tr '\t' ',' > "$CSV_OUT"
        echo "Saved to $CSV_OUT" >&2
    fi
    print_tsv_head "$DATA"
    exit 0
fi

echo "=== Report: $REPORT_TYPE [$DATE1 — $DATE2] ===" >&2

RESULT=$(direct_report "$BODY")

if [ -z "$RESULT" ]; then
    echo "Error: empty report result" >&2
    exit 1
fi

# Cache result
mkdir -p "$CACHE_DIR/reports"
printf '%s\n' "$RESULT" | cache_put "$CACHE_FILE"

# CSV export
if [ -n "$CSV_OUT" ]; then
    printf '%s\n' "$RESULT" | tr '\t' ',' > "$CSV_OUT"
    echo "Saved to $CSV_OUT" >&2
fi

print_tsv_head "$RESULT"
