#!/bin/sh
# lib/config.sh — Key=value configuration file parser
#
# Dependencies: lib/error.sh (for fatal)
# Provides: config_read, config_get, config_clear
#
# Config file format:
#   key=value
#   # comments (lines starting with #)
#   blank lines are ignored
#   keys must be alphanumeric + underscore only

if [ "$_CFBUILD_CONFIG_SOURCED" = yes ]; then
    return 0 2>/dev/null || exit 0
fi

: "${_CFBUILD_ERROR_SOURCED:?lib/error.sh must be sourced before lib/config.sh}"

# Read a key=value config file into CFG_ namespace variables.
# The eval is safe: keys are validated to [a-zA-Z0-9_] only,
# and values use \$_value (not interpolated in the eval string).
config_read() {
    local _file
    _file="$1"

    [ -f "$_file" ] || fatal "Config file not found: $_file"

    local _key
    local _value
    while IFS='=' read -r _key _value; do
        # Skip comments and blank lines
        case "$_key" in
        '#'* | '') continue ;;
        esac

        # Strip leading/trailing whitespace from key
        _key=$(printf '%s' "$_key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # Validate key: alphanumeric and underscore only
        case "$_key" in
        *[!a-zA-Z0-9_]*)
            fatal "Invalid config key '$_key' in $_file (must be [a-zA-Z0-9_])"
            ;;
        esac

        # Strip leading/trailing whitespace from value
        _value=$(printf '%s' "$_value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # Store in CFG_ namespace
        eval "CFG_${_key}=\$_value"
    done <"$_file"
}

# Get a config value by key, with an optional default.
config_get() {
    local _key
    local _default
    _key="$1"
    _default="${2:-}"
    eval "printf '%s' \"\${CFG_${_key}:-\$_default}\""
}

# Check if a config key is set (non-empty)
config_has() {
    local _val
    _val=$(config_get "$1" "")
    [ -n "$_val" ]
}

# Clear all config values (reset CFG_ namespace)
config_clear() {
    # eval unset to avoid subshell (pipe+while runs in subshell,
    # so unset would not affect the parent).
    eval "unset $(set | sed -n 's/^\(CFG_[a-zA-Z0-9_]*\)=.*/\1/p' | tr '\n' ' ')" 2>/dev/null || true
}

_CFBUILD_CONFIG_SOURCED=yes
