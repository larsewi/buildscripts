#!/bin/sh
# lib/log.sh — Structured logging
#
# Dependencies: none
# Provides: log_info, log_warn, log_error, log_debug, log_phase_start,
#           log_phase_end, run_quiet

if [ "$_CFBUILD_LOG_SOURCED" = yes ]; then
    return 0 2>/dev/null || exit 0
fi

# Current build phase (set by log_phase_start)
_CFBUILD_LOG_PHASE=""

# Internal: format and print a log message
# Uses printf for portability (echo interprets backslashes on HP-UX/AIX)
_log() {
    local _level
    _level="$1"
    shift

    # Respect quiet mode for non-error messages
    if [ "$CFBUILD_QUIET" = yes ] && [ "$_level" != ERROR ]; then
        return 0
    fi

    local _timestamp
    _timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf '%s' '-')

    local _phase_tag
    _phase_tag=""
    if [ -n "$_CFBUILD_LOG_PHASE" ]; then
        _phase_tag="[$_CFBUILD_LOG_PHASE] "
    fi

    if [ "$_level" = ERROR ]; then
        printf '[%s] [%-5s] %s%s\n' "$_timestamp" "$_level" "$_phase_tag" "$*" >&2
    else
        printf '[%s] [%-5s] %s%s\n' "$_timestamp" "$_level" "$_phase_tag" "$*"
    fi
}

log_info() {
    _log INFO "$@"
}

log_warn() {
    _log WARN "$@"
}

log_error() {
    _log ERROR "$@"
}

log_debug() {
    if [ "$CFBUILD_VERBOSE" = yes ]; then
        _log DEBUG "$@"
    fi
}

# Start a named build phase (shown in log output)
log_phase_start() {
    _CFBUILD_LOG_PHASE="$1"
    log_info "=== Phase: $1 ==="
}

# End the current build phase
log_phase_end() {
    log_info "=== Done: $_CFBUILD_LOG_PHASE ==="
    _CFBUILD_LOG_PHASE=""
}

# Run a command, suppressing output on success, printing it on failure.
# This replaces the old run_and_print_on_failure pattern.
run_quiet() {
    local _tmp_out
    local _rc
    _tmp_out="${TMPDIR:-/tmp}/cfbuild-rq.$$.$(date +%s 2>/dev/null || printf '%s' '0')"

    log_debug "Running: $*"

    "$@" >"$_tmp_out" 2>&1 && {
        rm -f "$_tmp_out"
        return 0
    }
    _rc=$?
    log_error "Command failed (exit $_rc): $*"
    log_error "--- output ---"
    cat "$_tmp_out" >&2
    log_error "--- end output ---"
    rm -f "$_tmp_out"
    return "$_rc"
}

_CFBUILD_LOG_SOURCED=yes
