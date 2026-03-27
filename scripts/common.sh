#!/bin/sh
# Common functions for Roistat API skill
# POSIX sh compatible — no bashisms

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config/.env"
CACHE_DIR="$SCRIPT_DIR/../cache"

ROISTAT_API="https://cloud.roistat.com/api/v1"

METRIKA_TMPDIR="${TMPDIR:-/tmp}"
mkdir -p "$METRIKA_TMPDIR"

# --------------- Config ---------------

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        . "$CONFIG_FILE"
    fi

    if [ -z "$ROISTAT_API_KEY" ]; then
        echo "Error: ROISTAT_API_KEY not found." >&2
        echo "Set in config/.env or environment. See config/README.md." >&2
        exit 1
    fi
}

# --------------- Cache helpers ---------------

cache_dir_for_project() {
    _cdp_dir="$CACHE_DIR/project_$1"
    mkdir -p "$_cdp_dir/reports"
    echo "$_cdp_dir"
}

cache_key() {
    printf '%s' "$1" | cksum | awk '{print $1}'
}

cache_get() {
    if [ -f "$1" ] && [ -s "$1" ]; then
        cat "$1"
        return 0
    fi
    return 1
}

cache_put() {
    mkdir -p "$(dirname "$1")"
    cat > "$1"
}

# --------------- API helpers ---------------

# roistat_get <path>
# Makes authenticated GET request
roistat_get() {
    _rg_path="$1"
    shift
    _rg_url="${ROISTAT_API}${_rg_path}"
    _rg_sep="?"
    case "$_rg_url" in *"?"*) _rg_sep="&" ;; esac
    _rg_url="${_rg_url}${_rg_sep}key=${ROISTAT_API_KEY}"

    _rg_body=$(curl -s "$_rg_url" "$@") || {
        echo "Error: curl failed for $_rg_url" >&2
        return 1
    }

    _rg_status=$(printf '%s' "$_rg_body" | grep -o '"status":"[^"]*"' | head -1 | sed 's/.*"status":"//;s/".*//')
    if [ "$_rg_status" = "error" ]; then
        echo "Error from Roistat API:" >&2
        printf '%s' "$_rg_body" >&2
        echo >&2
        return 1
    fi

    printf '%s' "$_rg_body"
}

# roistat_post <path> <json_body>
# Makes authenticated POST request with JSON body
roistat_post() {
    _rp_path="$1"
    _rp_body="$2"
    shift 2
    _rp_url="${ROISTAT_API}${_rp_path}?key=${ROISTAT_API_KEY}"

    _rp_resp=$(curl -s -X POST "$_rp_url" \
        -H "Content-Type: application/json" \
        -d "$_rp_body" "$@") || {
        echo "Error: curl failed for $_rp_url" >&2
        return 1
    }

    _rp_status=$(printf '%s' "$_rp_resp" | grep -o '"status":"[^"]*"' | head -1 | sed 's/.*"status":"//;s/".*//')
    if [ "$_rp_status" = "error" ]; then
        echo "Error from Roistat API:" >&2
        printf '%s' "$_rp_resp" >&2
        echo >&2
        return 1
    fi

    printf '%s' "$_rp_resp"
}

# roistat_post_project <path> <project_id> <json_body>
# Adds project param to URL and posts
roistat_post_project() {
    _rpp_path="$1"
    _rpp_project="$2"
    _rpp_body="$3"
    shift 3
    _rpp_url="${ROISTAT_API}${_rpp_path}?key=${ROISTAT_API_KEY}&project=${_rpp_project}"

    _rpp_resp=$(curl -s -X POST "$_rpp_url" \
        -H "Content-Type: application/json" \
        -d "$_rpp_body" "$@") || {
        echo "Error: curl failed for $_rpp_url" >&2
        return 1
    }

    _rpp_status=$(printf '%s' "$_rpp_resp" | grep -o '"status":"[^"]*"' | head -1 | sed 's/.*"status":"//;s/".*//')
    if [ "$_rpp_status" = "error" ]; then
        echo "Error from Roistat API:" >&2
        printf '%s' "$_rpp_resp" >&2
        echo >&2
        return 1
    fi

    printf '%s' "$_rpp_resp"
}

# --------------- Output helpers ---------------

print_tsv_head() {
    _pth_file="$1"
    _pth_n="${2:-30}"
    if [ -f "$_pth_file" ]; then
        head -n "$_pth_n" "$_pth_file"
        _pth_total=$(wc -l < "$_pth_file" | tr -d ' ')
        if [ "$_pth_total" -gt "$_pth_n" ]; then
            echo "... ($(( _pth_total - _pth_n )) more rows, full data in: $_pth_file)"
        fi
    fi
}

# --------------- Common param parsing ---------------

parse_common_params() {
    PROJECT=""
    DATE_FROM=""
    DATE_TO=""
    INTERVAL=""
    LIMIT=""
    CSV_OUT=""
    NO_CACHE=""
    SEARCH=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --project)   PROJECT="$2"; shift 2 ;;
            --date-from) DATE_FROM="$2"; shift 2 ;;
            --date-to)   DATE_TO="$2"; shift 2 ;;
            --interval)  INTERVAL="$2"; shift 2 ;;
            --limit)     LIMIT="$2"; shift 2 ;;
            --csv)       CSV_OUT="$2"; shift 2 ;;
            --no-cache)  NO_CACHE="1"; shift ;;
            --search)    SEARCH="$2"; shift 2 ;;
            *)           shift ;;
        esac
    done

    if [ -z "$DATE_TO" ]; then
        DATE_TO=$(date +%Y-%m-%d)
    fi
}

require_project() {
    if [ -z "$PROJECT" ]; then
        echo "Error: --project <ID> is required." >&2
        exit 1
    fi
}

require_dates() {
    if [ -z "$DATE_FROM" ]; then
        echo "Error: --date-from YYYY-MM-DD is required." >&2
        exit 1
    fi
}
