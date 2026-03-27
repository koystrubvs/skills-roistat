#!/bin/sh
# List Roistat advertising sources/channels for a project
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"
load_config
parse_common_params "$@"
require_project

_cache_dir=$(cache_dir_for_project "$PROJECT")
_cache_file="${_cache_dir}/sources.tsv"

if [ -z "$NO_CACHE" ] && cache_get "$_cache_file" > /dev/null 2>&1; then
    echo "(cached)"
    print_tsv_head "$_cache_file"
    exit 0
fi

echo "Fetching sources for project $PROJECT..."
_resp=$(roistat_post_project "/project/analytics/source/list" "$PROJECT" "{}")

printf '%s' "$_resp" | python3 -c "
import json, sys

d = json.load(sys.stdin)
sources = d.get('data', d.get('sources', []))

if isinstance(sources, dict):
    items = []
    def flatten(obj, prefix=''):
        if isinstance(obj, dict):
            for k, v in obj.items():
                title = v.get('title', k) if isinstance(v, dict) else k
                new_prefix = prefix + '/' + title if prefix else title
                items.append({'id': k, 'title': new_prefix})
                children = v.get('children', {}) if isinstance(v, dict) else {}
                if children:
                    flatten(children, new_prefix)
    flatten(sources)
    sources = items

with open('$_cache_file', 'w') as f:
    for s in sources:
        sid = s.get('id', s.get('value', ''))
        title = s.get('title', s.get('name', ''))
        f.write('{}\t{}\n'.format(sid, title))

print('ID\tTitle')
for s in sources[:30]:
    sid = s.get('id', s.get('value', ''))
    title = s.get('title', s.get('name', ''))
    print('{}\t{}'.format(sid, title))

if len(sources) > 30:
    print('... ({} more)'.format(len(sources) - 30))

print()
print('Total sources: {}'.format(len(sources)))
print('Cached: $_cache_file')
" 2>&1
