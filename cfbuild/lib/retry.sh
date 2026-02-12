#!/bin/sh
# lib/retry.sh — Retry wrapper with backoff
#
# Dependencies: lib/log.sh
# Provides: retry

if [ "$_CFBUILD_RETRY_SOURCED" = yes ]; then
    return 0 2>/dev/null || exit 0
fi

: "${_CFBUILD_LOG_SOURCED:?lib/log.sh must be sourced before lib/retry.sh}"

# Retry a command up to N times with a delay between attempts.
# Usage: retry <max_attempts> <delay_seconds> <command> [args...]
retry() {
    local _max
    local _delay
    _max="$1"
    _delay="$2"
    shift 2

    local _attempt
    local _rc
    _attempt=1
    while [ "$_attempt" -le "$_max" ]; do
        "$@" && return 0
        _rc=$?
        if [ "$_attempt" -lt "$_max" ]; then
            log_warn "Command failed (attempt $_attempt/$_max, exit $_rc): $*"
            log_warn "Retrying in ${_delay}s..."
            sleep "$_delay"
        else
            log_error "Command failed after $_max attempts (exit $_rc): $*"
            return "$_rc"
        fi
        _attempt=$((_attempt + 1))
    done
}

_CFBUILD_RETRY_SOURCED=yes
