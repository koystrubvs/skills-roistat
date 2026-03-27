#!/bin/sh
# Common functions for Yandex Direct API v5 skill
# POSIX sh compatible — no bashisms

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config/.env"
CACHE_DIR="$SCRIPT_DIR/../cache"

DIRECT_API="https://api.direct.yandex.com/json/v5"
DIRECT_REPORTS="https://api.direct.yandex.com/json/v5/reports"

# Ensure tmp directory exists
DIRECT_TMPDIR="${TMPDIR:-/tmp}"
mkdir -p "$DIRECT_TMPDIR"

# --------------- Config ---------------

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        . "$CONFIG_FILE"
    fi

    if [ -z "$YANDEX_DIRECT_TOKEN" ]; then
        echo "Error: YANDEX_DIRECT_TOKEN not found." >&2
        echo "Set in config/.env or environment. See config/README.md." >&2
        exit 1
    fi
}

# --------------- Cache helpers ---------------

# cache_key <params_string> — deterministic hash via cksum
cache_key() {
    printf '%s' "$1" | cksum | awk '{print $1}'
}

# cache_get <file_path> — prints cached file if exists and not empty
# Returns 0 if cache hit, 1 if miss
cache_get() {
    if [ -f "$1" ] && [ -s "$1" ]; then
        cat "$1"
        return 0
    fi
    return 1
}

# cache_put <file_path> — reads stdin, writes to file
cache_put() {
    mkdir -p "$(dirname "$1")"
    cat > "$1"
}

# --------------- API helpers ---------------

# direct_post <service_path> <json_body>
# Makes authenticated POST request to Direct API service endpoint
direct_post() {
    _dp_path="$1"
    _dp_body="$2"
    _dp_url="${DIRECT_API}/${_dp_path}"
    _dp_headers="${DIRECT_TMPDIR}/direct_headers_$$.txt"

    _dp_extra_headers=""
    if [ -n "${YANDEX_DIRECT_LOGIN:-}" ]; then
        _dp_extra_headers="-H Client-Login: $YANDEX_DIRECT_LOGIN"
    fi

    _dp_result=$(curl -s -X POST -D "$_dp_headers" \
        -H "Authorization: Bearer $YANDEX_DIRECT_TOKEN" \
        -H "Content-Type: application/json; charset=utf-8" \
        -H "Accept-Language: ru" \
        ${_dp_extra_headers} \
        -d "$_dp_body" \
        "$_dp_url") || {
        rm -f "$_dp_headers"
        echo "Error: curl failed for $_dp_url" >&2
        return 1
    }

    _dp_status=$(head -1 "$_dp_headers" | grep -o '[0-9][0-9][0-9]' | head -1)

    if [ -n "$_dp_status" ] && [ "$_dp_status" -ge 400 ] 2>/dev/null; then
        rm -f "$_dp_headers"
        echo "Error: HTTP $_dp_status from $_dp_url" >&2
        echo "$_dp_result" >&2
        return 1
    fi

    rm -f "$_dp_headers"
    printf '%s' "$_dp_result"
}

# direct_report <json_body> [output_file]
# Makes authenticated POST request to Reports API
# Handles 201/202 (report building) with retry
# Returns TSV data to stdout or saves to output_file
direct_report() {
    _dr_body="$1"
    _dr_output="${2:-}"
    _dr_headers="${DIRECT_TMPDIR}/direct_report_headers_$$.txt"
    _dr_max_retries=10
    _dr_retry=0
    _dr_delay=5

    while [ "$_dr_retry" -lt "$_dr_max_retries" ]; do
        _dr_extra=""
        if [ -n "${YANDEX_DIRECT_LOGIN:-}" ]; then
            _dr_extra="-H Client-Login: $YANDEX_DIRECT_LOGIN"
        fi

        if [ -n "$_dr_output" ]; then
            curl -s -X POST -D "$_dr_headers" \
                -H "Authorization: Bearer $YANDEX_DIRECT_TOKEN" \
                -H "Content-Type: application/json; charset=utf-8" \
                -H "Accept-Language: ru" \
                -H "processingMode: auto" \
                -H "returnMoneyInMicros: false" \
                -H "skipReportHeader: true" \
                -H "skipReportSummary: true" \
                ${_dr_extra} \
                -d "$_dr_body" \
                -o "$_dr_output" \
                "$DIRECT_REPORTS" || {
                rm -f "$_dr_headers"
                echo "Error: curl failed for Reports API" >&2
                return 1
            }
        else
            _dr_result=$(curl -s -X POST -D "$_dr_headers" \
                -H "Authorization: Bearer $YANDEX_DIRECT_TOKEN" \
                -H "Content-Type: application/json; charset=utf-8" \
                -H "Accept-Language: ru" \
                -H "processingMode: auto" \
                -H "returnMoneyInMicros: false" \
                -H "skipReportHeader: true" \
                -H "skipReportSummary: true" \
                ${_dr_extra} \
                -d "$_dr_body" \
                "$DIRECT_REPORTS") || {
                rm -f "$_dr_headers"
                echo "Error: curl failed for Reports API" >&2
                return 1
            }
        fi

        _dr_status=$(head -1 "$_dr_headers" | grep -o '[0-9][0-9][0-9]' | head -1)

        # 200 = report ready
        if [ "$_dr_status" = "200" ]; then
            rm -f "$_dr_headers"
            if [ -z "$_dr_output" ]; then
                printf '%s' "$_dr_result"
            fi
            return 0
        fi

        # 201 = report created offline, 202 = still building
        if [ "$_dr_status" = "201" ] || [ "$_dr_status" = "202" ]; then
            rm -f "$_dr_headers"
            _dr_retry=$(( _dr_retry + 1 ))
            echo "Report building... retry ${_dr_retry}/${_dr_max_retries}, waiting ${_dr_delay}s" >&2
            sleep "$_dr_delay"
            _dr_delay=$(( _dr_delay + 5 ))
            continue
        fi

        # Error
        rm -f "$_dr_headers"
        echo "Error: HTTP $_dr_status from Reports API" >&2
        if [ -n "$_dr_output" ] && [ -f "$_dr_output" ]; then
            cat "$_dr_output" >&2
        else
            echo "$_dr_result" >&2
        fi
        return 1
    done

    echo "Error: Report not ready after $_dr_max_retries retries" >&2
    return 1
}

# --------------- Money helpers ---------------

# micros_to_currency <value>
# Yandex Direct returns money as micros (× 1,000,000) when returnMoneyInMicros=true
# With returnMoneyInMicros=false, values are in currency units already
# We use returnMoneyInMicros=false, so no conversion needed

# --------------- Common param parsing ---------------

# parse_common_params "$@"
# Sets: DATE1, DATE2, CLIENT_LOGIN, CSV_OUT, NO_CACHE, LIMIT, CAMPAIGN_IDS
parse_common_params() {
    DATE1=""
    DATE2=""
    CLIENT_LOGIN=""
    CSV_OUT=""
    NO_CACHE=""
    LIMIT=""
    CAMPAIGN_IDS=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --date1)       DATE1="$2"; shift 2 ;;
            --date2)       DATE2="$2"; shift 2 ;;
            --login)       CLIENT_LOGIN="$2"; YANDEX_DIRECT_LOGIN="$2"; shift 2 ;;
            --csv)         CSV_OUT="$2"; shift 2 ;;
            --no-cache)    NO_CACHE="1"; shift ;;
            --limit)       LIMIT="$2"; shift 2 ;;
            --campaigns)   CAMPAIGN_IDS="$2"; shift 2 ;;
            *)             shift ;;
        esac
    done

    # Default dates
    if [ -z "$DATE2" ]; then
        DATE2=$(date +%Y-%m-%d)
    fi
    if [ -z "$DATE1" ]; then
        DATE1=$(date -d "30 days ago" +%Y-%m-%d 2>/dev/null || date -v-30d +%Y-%m-%d 2>/dev/null || DATE1="$DATE2")
    fi
}

# require_dates — exits if DATE1 not set
require_dates() {
    if [ -z "$DATE1" ]; then
        echo "Error: --date1 YYYY-MM-DD is required." >&2
        exit 1
    fi
}

# --------------- Output helpers ---------------

# print_tsv_head <data> [n_lines]
# Prints first N lines of TSV data (default 30)
print_tsv_head() {
    _pth_data="$1"
    _pth_n="${2:-30}"
    _pth_total=$(printf '%s\n' "$_pth_data" | wc -l | tr -d ' ')
    printf '%s\n' "$_pth_data" | head -n "$_pth_n"
    if [ "$_pth_total" -gt "$_pth_n" ]; then
        echo "... ($(( _pth_total - _pth_n )) more rows)"
    fi
}
