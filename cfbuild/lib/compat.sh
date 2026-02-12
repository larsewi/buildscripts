#!/bin/sh
# lib/compat.sh — Portability shims for exotic platforms
#
# Dependencies: lib/error.sh (for fatal)
# Provides: compat_mktemp, compat_mktempdir, compat_sha256, compat_sed_inplace,
#           compat_realpath, compat_nproc

if [ "$_CFBUILD_COMPAT_SOURCED" = yes ]; then
    return 0 2>/dev/null || exit 0
fi

: "${_CFBUILD_ERROR_SOURCED:?lib/error.sh must be sourced before lib/compat.sh}"

# Create a temporary file portably.
# mktemp is broken on HP-UX and missing on some AIX versions.
compat_mktemp() {
    local _dir
    _dir="${TMPDIR:-/tmp}"

    if command -v mktemp >/dev/null 2>&1; then
        # Test that mktemp actually works (HP-UX mktemp is broken)
        local _test
        _test=$(mktemp "${_dir}/cfbuild-test.XXXXXX" 2>/dev/null) || true
        if [ -f "$_test" ]; then
            rm -f "$_test"
            mktemp "${_dir}/cfbuild.XXXXXX"
            return
        fi
    fi

    # Fallback: PID + timestamp
    local _name
    _name="${_dir}/cfbuild.${$}.$(date +%s 2>/dev/null || printf '%s' '0')"
    (umask 077 && : >"$_name") || fatal "Failed to create temp file: $_name"
    printf '%s\n' "$_name"
}

# Create a temporary directory portably.
compat_mktempdir() {
    local _dir
    _dir="${TMPDIR:-/tmp}"

    if command -v mktemp >/dev/null 2>&1; then
        local _test
        _test=$(mktemp -d "${_dir}/cfbuild-test.XXXXXX" 2>/dev/null) || true
        if [ -d "$_test" ]; then
            rmdir "$_test"
            mktemp -d "${_dir}/cfbuild.XXXXXX"
            return
        fi
    fi

    # Fallback
    local _name
    _name="${_dir}/cfbuild.${$}.$(date +%s 2>/dev/null || printf '%s' '0')"
    (umask 077 && mkdir "$_name") || fatal "Failed to create temp dir: $_name"
    printf '%s\n' "$_name"
}

# Compute SHA-256 hash of a file. Different platforms have different tools.
compat_sha256() {
    local _file
    _file="$1"
    [ -f "$_file" ] || fatal "compat_sha256: file not found: $_file"

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$_file" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$_file" | cut -d' ' -f1
    elif command -v digest >/dev/null 2>&1; then
        # Solaris
        digest -a sha256 "$_file"
    elif command -v openssl >/dev/null 2>&1; then
        # AIX, HP-UX
        openssl dgst -sha256 "$_file" | sed 's/.*= //'
    else
        fatal "No SHA-256 tool found on this platform"
    fi
}

# Portable sed in-place editing.
# NEVER uses sed -i (not available on Solaris, HP-UX, AIX).
# Always writes to a temp file and renames.
compat_sed_inplace() {
    local _expr
    local _file
    _expr="$1"
    _file="$2"

    [ -f "$_file" ] || fatal "compat_sed_inplace: file not found: $_file"

    local _tmp
    _tmp="${_file}.cfbuild-tmp.$$"
    sed "$_expr" "$_file" >"$_tmp" && mv "$_tmp" "$_file"
}

# Portable realpath (resolve symlinks and relative paths).
compat_realpath() {
    if command -v realpath >/dev/null 2>&1; then
        realpath "$1"
    elif command -v readlink >/dev/null 2>&1; then
        readlink -f "$1" 2>/dev/null || _compat_realpath_fallback "$1"
    else
        _compat_realpath_fallback "$1"
    fi
}

_compat_realpath_fallback() {
    local _target
    _target="$1"
    if [ -d "$_target" ]; then
        (cd "$_target" && pwd -P)
    elif [ -f "$_target" ]; then
        local _dir
        local _base
        _dir=$(dirname "$_target")
        _base=$(basename "$_target")
        printf '%s/%s\n' "$(cd "$_dir" && pwd -P)" "$_base"
    else
        # Doesn't exist yet — resolve parent dir
        local _dir
        local _base
        _dir=$(dirname "$_target")
        _base=$(basename "$_target")
        printf '%s/%s\n' "$(cd "$_dir" 2>/dev/null && pwd -P || printf '%s' "$_dir")" "$_base"
    fi
}

# Portable nproc (get number of CPU cores).
compat_nproc() {
    if command -v nproc >/dev/null 2>&1; then
        nproc
    elif [ -f /proc/cpuinfo ]; then
        # Linux fallback
        grep -c '^processor' /proc/cpuinfo
    elif command -v sysctl >/dev/null 2>&1; then
        # FreeBSD, macOS
        sysctl -n hw.ncpu 2>/dev/null || printf '1\n'
    elif command -v lsdev >/dev/null 2>&1; then
        # AIX
        lsdev -Cc processor | wc -l | tr -d ' '
    elif command -v ioscan >/dev/null 2>&1; then
        # HP-UX
        ioscan -fnkC processor | grep -c '^processor' 2>/dev/null || printf '1\n'
    elif command -v psrinfo >/dev/null 2>&1; then
        # Solaris
        psrinfo | wc -l | tr -d ' '
    else
        printf '1\n'
    fi
}

# Portable decompress (handles .gz, .tgz, .bz2, .xz)
compat_decompress() {
    local _file
    _file="$1"
    case "$_file" in
    *.tar.gz | *.tgz)
        gzip -dc "$_file" | tar xf -
        ;;
    *.tar.bz2)
        bzip2 -dc "$_file" | tar xf -
        ;;
    *.tar.xz)
        xz -dc "$_file" | tar xf -
        ;;
    *.gz)
        gzip -dc "$_file"
        ;;
    *)
        fatal "compat_decompress: unknown format: $_file"
        ;;
    esac
}

_CFBUILD_COMPAT_SOURCED=yes
