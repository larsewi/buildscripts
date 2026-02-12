#!/bin/sh
# cmd/deps.sh — Build and install bundled dependencies
#
# Usage: cfbuild deps [--force] [dep_name ...]
#
# If specific dep names are given, only those are built.
# Otherwise, the full dependency list for the current project/role/platform is built.
# Use --force to rebuild all dependencies regardless of stamps.

. "$CFBUILD_ROOT/lib/deps.sh"

# Parse command-specific options
while [ $# -gt 0 ]; do
    case "$1" in
    --force)
        CFBUILD_FORCE_DEPS=yes
        export CFBUILD_FORCE_DEPS
        shift
        ;;
    --)
        shift
        break
        ;;
    -*) fatal "Unknown deps option: $1" ;;
    *) break ;;
    esac
done

log_phase_start "dependencies"

if [ "$CFBUILD_FORCE_DEPS" = yes ]; then
    log_info "Force rebuild requested"
fi

# Resolve dependency list
if [ $# -gt 0 ]; then
    _dep_list="$*"
    log_info "Building specified dependencies: $_dep_list"
else
    _dep_list=$(dep_resolve_list)
    log_info "Resolved dependency list: $_dep_list"
fi

# Check and install Perl if needed (required by OpenSSL)
_needs_perl=no
for _dep in $_dep_list; do
    case "$_dep" in
    openssl) _needs_perl=yes ;;
    esac
done

if [ "$_needs_perl" = yes ]; then
    if ! dep_check_perl; then
        log_warn "System Perl is too old or missing required modules"
        log_info "A suitable Perl must be installed manually or via the build host setup script"
        log_info "OpenSSL requires Perl >= 5.13.4 with List::Util >= 1.29"
    fi
fi

# Build version string for package naming
_revision=""
if [ -f "$CFBUILD_BASEDIR/buildscripts/deps-packaging/revision" ]; then
    _revision=$(cat "$CFBUILD_BASEDIR/buildscripts/deps-packaging/revision")
fi

case "$CFBUILD_TYPE" in
debug) _versuffix="+untested" ;;
release) _versuffix="+release" ;;
*) _versuffix="" ;;
esac

case "$PLATFORM_ARCH" in
x86 | x64) _crossver="+mingw${PLATFORM_ARCH}" ;;
*) _crossver="" ;;
esac

_safe_prefix=""
if [ "$CFBUILD_PREFIX" != "/var/cfengine" ]; then
    _safe_prefix="+$(printf '%s' "$CFBUILD_PREFIX" | sed 's:/::g')"
fi

_dep_version="0+${_revision}${_versuffix}${_crossver}${_safe_prefix}"

# Build each dependency
_dep_count=0
_dep_total=0
for _d in $_dep_list; do
    _dep_total=$((_dep_total + 1))
done

for _dep in $_dep_list; do
    _dep_count=$((_dep_count + 1))
    _dep_conf="$CFBUILD_ROOT/etc/deps/${_dep}.conf"
    _dep_ver=""
    if [ -f "$_dep_conf" ]; then
        _dep_ver=$(sed -n 's/^version=//p' "$_dep_conf")
    fi
    log_info "[$_dep_count/$_dep_total] $_dep ${_dep_ver}"

    dep_build "$_dep"
done

log_phase_end
log_info "All dependencies built successfully"
