#!/bin/sh
# List Roistat projects
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"
load_config
parse_common_params "$@"

CACHE_FILE="$CACHE_DIR/projects.tsv"

if [ -z "$NO_CACHE" ] && [ -z "$SEARCH" ] && cache_get "$CACHE_FILE" > /dev/null 2>&1; then
    echo "(cached)"
    print_tsv_head "$CACHE_FILE"
    exit 0
fi

if [ -z "$NO_CACHE" ] && [ -n "$SEARCH" ] && [ -f "$CACHE_FILE" ]; then
    echo "(searching cache for '$SEARCH')"
    _found=$(grep -i "$SEARCH" "$CACHE_FILE" 2>/dev/null || true)
    if [ -n "$_found" ]; then
        echo "ID	Name	Currency	Created"
        echo "$_found"
    else
        echo "(no matches for '$SEARCH')"
    fi
    echo
    echo "(cached: $CACHE_FILE)"
    exit 0
fi

echo "Fetching projects from API..."
_resp=$(roistat_get "/user/projects")

printf '%s' "$_resp" | python3 -c "
import json, sys
d = json.load(sys.stdin)
projects = d.get('projects', [])
lines = []
for p in projects:
    lines.append('{}\t{}\t{}\t{}'.format(p['id'], p['name'], p.get('currency',''), p.get('creation_date','')))

# Write TSV cache
with open('$CACHE_FILE', 'w') as f:
    for l in lines:
        f.write(l + '\n')

# Print
print('ID\tName\tCurrency\tCreated')
for l in lines:
    print(l)
print()
print('Total projects: {}'.format(len(projects)))
print('Cached: $CACHE_FILE')
" 2>&1

if [ -n "$SEARCH" ] && [ -f "$CACHE_FILE" ]; then
    echo
    echo "Filtering for '$SEARCH':"
    grep -i "$SEARCH" "$CACHE_FILE" 2>/dev/null || echo "(no matches)"
fi
