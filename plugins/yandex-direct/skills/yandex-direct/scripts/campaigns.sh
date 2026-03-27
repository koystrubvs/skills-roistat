#!/bin/sh
# List Yandex Direct campaigns with status and type
# Usage: bash campaigns.sh [--login LOGIN] [--search TERM] [--status ACCEPTED|DRAFT|MODERATION]
# POSIX sh compatible

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"

load_config

STATUS_FILTER=""
SEARCH=""

while [ $# -gt 0 ]; do
    case "$1" in
        --login)   YANDEX_DIRECT_LOGIN="$2"; shift 2 ;;
        --search)  SEARCH="$2"; shift 2 ;;
        --status)  STATUS_FILTER="$2"; shift 2 ;;
        *)         shift ;;
    esac
done

CACHE_FILE="$CACHE_DIR/campaigns.tsv"

# Check cache (unless search needs fresh data)
if [ -z "$SEARCH" ] && cache_get "$CACHE_FILE" >/dev/null 2>&1; then
    echo "=== Campaigns (cached) ===" >&2
    DATA=$(cache_get "$CACHE_FILE")
    if [ -n "$STATUS_FILTER" ]; then
        HEADER=$(printf '%s\n' "$DATA" | head -1)
        printf '%s\n' "$HEADER"
        printf '%s\n' "$DATA" | tail -n +2 | grep -i "$STATUS_FILTER"
    else
        printf '%s\n' "$DATA"
    fi
    exit 0
fi

# Build request body
if [ -n "$STATUS_FILTER" ]; then
    BODY=$(cat <<ENDJSON
{
  "method": "get",
  "params": {
    "SelectionCriteria": {
      "Statuses": ["$STATUS_FILTER"]
    },
    "FieldNames": ["Id", "Name", "Status", "State", "Type", "DailyBudget", "Statistics"],
    "TextCampaignFieldNames": ["BiddingStrategy"],
    "Page": {"Limit": 1000}
  }
}
ENDJSON
)
else
    BODY=$(cat <<ENDJSON
{
  "method": "get",
  "params": {
    "SelectionCriteria": {},
    "FieldNames": ["Id", "Name", "Status", "State", "Type", "DailyBudget", "Statistics"],
    "TextCampaignFieldNames": ["BiddingStrategy"],
    "Page": {"Limit": 1000}
  }
}
ENDJSON
)
fi

RESULT=$(direct_post "campaigns" "$BODY")

if [ -z "$RESULT" ]; then
    echo "Error: empty response" >&2
    exit 1
fi

# Parse JSON with python
TSV=$(printf '%s' "$RESULT" | python3 -c "
import json, sys

data = json.load(sys.stdin)
campaigns = data.get('result', {}).get('Campaigns', [])
if not campaigns:
    print('No campaigns found')
    sys.exit(0)

print('ID\tName\tStatus\tState\tType\tDailyBudget')
for c in campaigns:
    cid = c.get('Id', '')
    name = c.get('Name', '')
    status = c.get('Status', '')
    state = c.get('State', '')
    ctype = c.get('Type', '')
    budget = c.get('DailyBudget', {})
    if isinstance(budget, dict):
        amount = budget.get('Amount', 0)
        # Amount is in currency units (not micros with our setting)
        budget_str = str(amount)
    else:
        budget_str = str(budget) if budget else '-'
    print(f'{cid}\t{name}\t{status}\t{state}\t{ctype}\t{budget_str}')
")

# Save to cache
mkdir -p "$CACHE_DIR"
printf '%s\n' "$TSV" | cache_put "$CACHE_FILE"

echo "=== Campaigns ===" >&2
if [ -n "$SEARCH" ]; then
    HEADER=$(printf '%s\n' "$TSV" | head -1)
    printf '%s\n' "$HEADER"
    printf '%s\n' "$TSV" | tail -n +2 | grep -i "$SEARCH"
else
    printf '%s\n' "$TSV"
fi
