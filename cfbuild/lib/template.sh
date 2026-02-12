#!/bin/sh
# lib/template.sh — sed-based @VAR@ template expansion
#
# Dependencies: lib/error.sh (for fatal)
# Provides: template_expand
#
# Template files use @VARIABLE_NAME@ placeholders.
# Values are passed as KEY=VALUE arguments.

if [ "$_CFBUILD_TEMPLATE_SOURCED" = yes ]; then
    return 0 2>/dev/null || exit 0
fi

: "${_CFBUILD_ERROR_SOURCED:?lib/error.sh must be sourced before lib/template.sh}"

# Expand @VAR@ placeholders in a template file.
# Usage: template_expand <input> <output> KEY1=VALUE1 KEY2=VALUE2 ...
#
# Uses | as sed delimiter to avoid issues with paths containing /.
# If values might contain |, the caller must escape them.
template_expand() {
    local _input
    local _output
    _input="$1"
    _output="$2"
    shift 2

    [ -f "$_input" ] || fatal "template_expand: input file not found: $_input"

    # Build sed expression from KEY=VALUE pairs
    local _sed_expr
    _sed_expr=""
    local _pair
    local _key
    local _val
    for _pair in "$@"; do
        _key="${_pair%%=*}"
        _val="${_pair#*=}"

        # Escape sed special characters in value (& and \)
        _val=$(printf '%s' "$_val" | sed 's/[&\\]/\\&/g')

        _sed_expr="${_sed_expr}s|@${_key}@|${_val}|g;
"
    done

    if [ -z "$_sed_expr" ]; then
        # No substitutions — just copy
        cp "$_input" "$_output"
    else
        sed "$_sed_expr" "$_input" >"$_output"
    fi
}

_CFBUILD_TEMPLATE_SOURCED=yes
