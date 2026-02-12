#!/bin/sh
# lib/error.sh — Error handling, cleanup stack, and fatal exit
#
# Dependencies: lib/log.sh (for log_error)
# Provides: fatal, register_cleanup_file, register_cleanup_dir
#
# IMPORTANT: Traps are installed at top-level (not inside functions) because
# AIX 5.3 /bin/sh fires trap 0 at function exit rather than script exit.

if [ "$_CFBUILD_ERROR_SOURCED" = yes ]; then
    return 0 2>/dev/null || exit 0
fi

: "${_CFBUILD_LOG_SOURCED:?lib/log.sh must be sourced before lib/error.sh}"

set -e

# Cleanup registry (space-separated paths)
_CFBUILD_CLEANUP_FILES=""
_CFBUILD_CLEANUP_DIRS=""

# Register a file for cleanup on exit
register_cleanup_file() {
    _CFBUILD_CLEANUP_FILES="$_CFBUILD_CLEANUP_FILES $1"
}

# Register a directory for cleanup on exit
register_cleanup_dir() {
    _CFBUILD_CLEANUP_DIRS="$_CFBUILD_CLEANUP_DIRS $1"
}

# Cleanup handler — runs on exit (normal or error)
_cfbuild_cleanup() {
    # Kill keepalive process if running (set by lib/deps.sh)
    if [ -n "$_DEP_KEEPALIVE_PID" ]; then
        kill "$_DEP_KEEPALIVE_PID" 2>/dev/null || true
        # Print newline only if at least one dot was printed (60s elapsed)
        local _now
        _now=$(date +%s 2>/dev/null || echo 0)
        if [ "$((_now - ${_DEP_KEEPALIVE_START:-0}))" -ge 60 ] 2>/dev/null; then
            printf '\n'
        fi
    fi
    local _f
    for _f in $_CFBUILD_CLEANUP_FILES; do
        rm -f "$_f" 2>/dev/null || true
    done
    local _d
    for _d in $_CFBUILD_CLEANUP_DIRS; do
        rm -rf "$_d" 2>/dev/null || true
    done
}

# Exit with an error message
fatal() {
    local _msg
    local _code
    _msg="${1:-unknown error}"
    _code="${2:-1}"
    log_error "FATAL: $_msg"
    exit "$_code"
}

# Install traps at top level (MUST be done here, not in a function, for AIX compat)
trap _cfbuild_cleanup EXIT HUP INT TERM

_CFBUILD_ERROR_SOURCED=yes
