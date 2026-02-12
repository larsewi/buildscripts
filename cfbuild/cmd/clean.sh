#!/bin/sh
# cmd/clean.sh — Remove build artifacts and installed cfbuild packages
#
# Usage: cfbuild clean [--all]
#
# Removes cfbuild-* packages and the PREFIX directory.
# With --all, also removes dist/ and all dependency build directories.

log_phase_start "clean"

_clean_all=no
for _arg in "$@"; do
    case "$_arg" in
    --all) _clean_all=yes ;;
    esac
done

# Remove cfbuild dependency packages
log_info "Removing cfbuild packages..."
pkg_uninstall_cfbuild_devel 2>/dev/null || true
pkg_uninstall_cfbuild 2>/dev/null || true

# Remove PREFIX directory
if [ -d "$CFBUILD_PREFIX" ]; then
    log_info "Removing prefix directory: $CFBUILD_PREFIX"
    sudo rm -rf "$CFBUILD_PREFIX"
fi

# Remove dist directory
_dist="$CFBUILD_BASEDIR/cfengine/dist"
if [ -d "$_dist" ]; then
    log_info "Removing dist directory: $_dist"
    rm -rf "$_dist"
fi

if [ "$_clean_all" = yes ]; then
    # Remove dependency build directories
    log_info "Removing dependency build directories..."
    for _dep_dir in "$CFBUILD_BASEDIR"/*/staging; do
        if [ -d "$_dep_dir" ]; then
            _parent=$(dirname "$_dep_dir")
            log_debug "Removing: $_parent"
            rm -rf "$_parent"
        fi
    done

    # Clean core/enterprise/nova/masterfiles build artifacts
    for _repo in core enterprise nova masterfiles; do
        if [ -d "$CFBUILD_BASEDIR/$_repo" ] && [ -f "$CFBUILD_BASEDIR/$_repo/Makefile" ]; then
            log_info "Cleaning $_repo..."
            "$PLATFORM_MAKE" -C "$CFBUILD_BASEDIR/$_repo" clean >/dev/null 2>&1 || true
        fi
    done
fi

log_phase_end
log_info "Clean complete"
