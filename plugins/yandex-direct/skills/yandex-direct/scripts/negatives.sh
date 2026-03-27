#!/bin/sh
# List negative keywords for campaigns
# Usage: bash negatives.sh [--campaigns 123,456] [--login LOGIN]
# POSIX sh compatible

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"

load_config

CAMPAIGN_IDS=""

while [ $# -gt 0 ]; do
    case "$1" in
        --campaigns) CAMPAIGN_IDS="$2"; shift 2 ;;
        --login)     YANDEX_DIRECT_LOGIN="$2"; shift 2 ;;
        *)           shift ;;
    esac
done

if [ -z "$CAMPAIGN_IDS" ]; then
    echo "Error: --campaigns <id1,id2,...> is required" >&2
    echo "Use campaigns.sh first to get campaign IDs" >&2
    exit 1
fi

# Get negative keywords for campaigns
IDS_JSON=$(printf '%s' "$CAMPAIGN_IDS" | python3 -c "import sys; ids=sys.stdin.read().strip().split(','); print(','.join([i.strip() for i in ids]))")

BODY=$(python3 -c "
import json
ids = [int(i.strip()) for i in '$CAMPAIGN_IDS'.split(',')]
body = {
    'method': 'get',
    'params': {
        'SelectionCriteria': {
            'CampaignIds': ids
        },
        'FieldNames': ['CampaignId', 'NegativeKeywords']
    }
}
print(json.dumps(body, ensure_ascii=False))
")

RESULT=$(direct_post "campaignnegativekeywords" "$BODY" 2>/dev/null)

if [ -z "$RESULT" ]; then
    # Try via campaigns endpoint (NegativeKeywords is a campaign field)
    BODY2=$(python3 -c "
import json
ids = [int(i.strip()) for i in '$CAMPAIGN_IDS'.split(',')]
body = {
    'method': 'get',
    'params': {
        'SelectionCriteria': {'Ids': ids},
        'FieldNames': ['Id', 'Name', 'NegativeKeywords']
    }
}
print(json.dumps(body, ensure_ascii=False))
")
    RESULT=$(direct_post "campaigns" "$BODY2")
fi

if [ -z "$RESULT" ]; then
    echo "Error: empty response" >&2
    exit 1
fi

# Parse
python3 -c "
import json, sys
data = json.load(sys.stdin)

# Try campaigns format
campaigns = data.get('result', {}).get('Campaigns', [])
if campaigns:
    for c in campaigns:
        cid = c.get('Id', '')
        name = c.get('Name', '')
        negatives = c.get('NegativeKeywords', {})
        if isinstance(negatives, dict):
            items = negatives.get('Items', [])
        elif isinstance(negatives, list):
            items = negatives
        else:
            items = []
        print(f'Campaign: {name} (ID: {cid})')
        if items:
            print(f'  Negative keywords ({len(items)}):')
            for kw in sorted(items):
                print(f'    - {kw}')
        else:
            print('  NO negative keywords!')
        print()
    sys.exit(0)

# Try negative keywords format
nk = data.get('result', {}).get('NegativeKeywords', [])
if nk:
    for item in nk:
        cid = item.get('CampaignId', '')
        kws = item.get('NegativeKeywords', [])
        print(f'Campaign ID: {cid}')
        if kws:
            print(f'  Negative keywords ({len(kws)}):')
            for kw in sorted(kws):
                print(f'    - {kw}')
        else:
            print('  NO negative keywords!')
        print()
else:
    print('No negative keywords data found')
" <<ENDJSON
$RESULT
ENDJSON
