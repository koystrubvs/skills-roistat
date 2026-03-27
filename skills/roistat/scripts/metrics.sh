#!/bin/sh
# List available metrics for a Roistat project
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"
load_config
parse_common_params "$@"
require_project

_cache_dir=$(cache_dir_for_project "$PROJECT")
_cache_file="${_cache_dir}/metrics.tsv"

if [ -z "$NO_CACHE" ] && cache_get "$_cache_file" > /dev/null 2>&1; then
    echo "(cached)"
    print_tsv_head "$_cache_file" 50
    exit 0
fi

echo "Fetching metrics for project $PROJECT..."
_resp=$(roistat_post_project "/project/analytics/metrics-new" "$PROJECT" "{}")

printf '%s' "$_resp" | python3 -c "
import json, sys

d = json.load(sys.stdin)
metrics = d.get('data', d.get('metrics', []))

with open('$_cache_file', 'w') as f:
    for m in metrics:
        name = m.get('name', '')
        title = m.get('title', '')
        f.write('{}\t{}\n'.format(name, title))

print('Name\tTitle')
for m in metrics[:50]:
    print('{}\t{}'.format(m.get('name',''), m.get('title','')))

if len(metrics) > 50:
    print('... ({} more)'.format(len(metrics) - 50))

print()
print('Total metrics: {}'.format(len(metrics)))
print('Cached: $_cache_file')
" 2>&1
