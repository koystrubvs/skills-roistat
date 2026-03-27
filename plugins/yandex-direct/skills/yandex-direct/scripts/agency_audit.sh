#!/bin/sh
# Agency audit — quick health check of Yandex Direct account
# Combines multiple reports to identify issues:
# - Campaigns with high spend but low conversions
# - Keywords with low CTR (wasting budget)
# - Search queries that are irrelevant (no negatives)
# - Daily spend trends
#
# Usage: bash agency_audit.sh --date1 YYYY-MM-DD [--date2 ...] [--login LOGIN] [--csv path]
# POSIX sh compatible

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"

load_config
parse_common_params "$@"

echo "=== Agency Audit [$DATE1 — $DATE2] ===" >&2
echo "" >&2

# 1. Campaign performance
echo "--- 1. Campaign Performance ---" >&2
CAMP_REPORT_NAME="audit_campaigns_${DATE1}_${DATE2}_$$"
CAMP_BODY=$(python3 -c "
import json
body = {
    'params': {
        'SelectionCriteria': {'DateFrom': '$DATE1', 'DateTo': '$DATE2'},
        'FieldNames': ['CampaignName','CampaignId','Impressions','Clicks','Ctr','Cost','AvgCpc','Conversions','CostPerConversion','BounceRate'],
        'OrderBy': [{'Field': 'Cost', 'SortOrder': 'DESCENDING'}],
        'ReportName': '$CAMP_REPORT_NAME',
        'ReportType': 'CAMPAIGN_PERFORMANCE_REPORT',
        'DateRangeType': 'CUSTOM_DATE',
        'Format': 'TSV',
        'IncludeVAT': 'YES',
        'IncludeDiscount': 'YES'
    }
}
print(json.dumps(body, ensure_ascii=False))
")

CAMP_RESULT=$(direct_report "$CAMP_BODY")
echo "$CAMP_RESULT"
echo ""

# 2. Daily spend trend
echo "--- 2. Daily Spend Trend ---" >&2
DAILY_REPORT_NAME="audit_daily_${DATE1}_${DATE2}_$$"
DAILY_BODY=$(python3 -c "
import json
body = {
    'params': {
        'SelectionCriteria': {'DateFrom': '$DATE1', 'DateTo': '$DATE2'},
        'FieldNames': ['Date','Impressions','Clicks','Ctr','Cost','Conversions'],
        'OrderBy': [{'Field': 'Date'}],
        'ReportName': '$DAILY_REPORT_NAME',
        'ReportType': 'CUSTOM_REPORT',
        'DateRangeType': 'CUSTOM_DATE',
        'Format': 'TSV',
        'IncludeVAT': 'YES',
        'IncludeDiscount': 'YES'
    }
}
print(json.dumps(body, ensure_ascii=False))
")

DAILY_RESULT=$(direct_report "$DAILY_BODY")
echo "$DAILY_RESULT"
echo ""

# 3. Top keywords by spend (potential waste)
echo "--- 3. Top 20 Keywords by Spend ---" >&2
KW_REPORT_NAME="audit_keywords_${DATE1}_${DATE2}_$$"
KW_BODY=$(python3 -c "
import json
body = {
    'params': {
        'SelectionCriteria': {'DateFrom': '$DATE1', 'DateTo': '$DATE2'},
        'FieldNames': ['CampaignName','Criterion','Impressions','Clicks','Ctr','Cost','AvgCpc','Conversions','CostPerConversion'],
        'OrderBy': [{'Field': 'Cost', 'SortOrder': 'DESCENDING'}],
        'ReportName': '$KW_REPORT_NAME',
        'ReportType': 'CRITERIA_PERFORMANCE_REPORT',
        'DateRangeType': 'CUSTOM_DATE',
        'Format': 'TSV',
        'IncludeVAT': 'YES',
        'IncludeDiscount': 'YES'
    }
}
print(json.dumps(body, ensure_ascii=False))
")

KW_RESULT=$(direct_report "$KW_BODY")
# Show header + top 20
printf '%s\n' "$KW_RESULT" | head -1
printf '%s\n' "$KW_RESULT" | tail -n +2 | head -20
KW_TOTAL=$(printf '%s\n' "$KW_RESULT" | wc -l | tr -d ' ')
if [ "$KW_TOTAL" -gt 21 ]; then
    echo "... ($(( KW_TOTAL - 21 )) more keywords)"
fi
echo ""

# 4. Top search queries by spend (check for irrelevant)
echo "--- 4. Top 20 Search Queries by Spend ---" >&2
SQ_REPORT_NAME="audit_sq_${DATE1}_${DATE2}_$$"
SQ_BODY=$(python3 -c "
import json
body = {
    'params': {
        'SelectionCriteria': {'DateFrom': '$DATE1', 'DateTo': '$DATE2'},
        'FieldNames': ['CampaignName','Query','Criterion','Impressions','Clicks','Ctr','Cost','Conversions'],
        'OrderBy': [{'Field': 'Cost', 'SortOrder': 'DESCENDING'}],
        'ReportName': '$SQ_REPORT_NAME',
        'ReportType': 'SEARCH_QUERY_PERFORMANCE_REPORT',
        'DateRangeType': 'CUSTOM_DATE',
        'Format': 'TSV',
        'IncludeVAT': 'YES',
        'IncludeDiscount': 'YES'
    }
}
print(json.dumps(body, ensure_ascii=False))
")

SQ_RESULT=$(direct_report "$SQ_BODY")
printf '%s\n' "$SQ_RESULT" | head -1
printf '%s\n' "$SQ_RESULT" | tail -n +2 | head -20
SQ_TOTAL=$(printf '%s\n' "$SQ_RESULT" | wc -l | tr -d ' ')
if [ "$SQ_TOTAL" -gt 21 ]; then
    echo "... ($(( SQ_TOTAL - 21 )) more queries)"
fi

# CSV export all sections
if [ -n "$CSV_OUT" ]; then
    {
        echo "=== CAMPAIGNS ==="
        printf '%s\n' "$CAMP_RESULT" | tr '\t' ','
        echo ""
        echo "=== DAILY ==="
        printf '%s\n' "$DAILY_RESULT" | tr '\t' ','
        echo ""
        echo "=== KEYWORDS ==="
        printf '%s\n' "$KW_RESULT" | tr '\t' ','
        echo ""
        echo "=== SEARCH QUERIES ==="
        printf '%s\n' "$SQ_RESULT" | tr '\t' ','
    } > "$CSV_OUT"
    echo "" >&2
    echo "Full audit saved to $CSV_OUT" >&2
fi
