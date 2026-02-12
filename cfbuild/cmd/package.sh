#!/bin/sh
# cmd/package.sh — Create platform-specific packages
#
# Usage: cfbuild package
#
# Dispatches to the appropriate package format handler based on the
# detected platform packaging system.

. "$CFBUILD_ROOT/lib/deps.sh"

log_phase_start "package"

# --- Determine package name ---

case "$CFBUILD_PROJECT-$CFBUILD_ROLE" in
community-*)
    PKG_NAME=cfengine-community
    PKG_RPM_OPTIONS=""
    PKG_DEB_OPTIONS=""
    ;;
nova-hub)
    PKG_NAME=cfengine-nova-hub
    # Embedded quotes are consumed literally by the rpm handler.
    # shellcheck disable=SC2089
    PKG_RPM_OPTIONS="--define 'with_expansion 1'"
    PKG_DEB_OPTIONS=""
    ;;
nova-agent)
    PKG_NAME=cfengine-nova
    PKG_RPM_OPTIONS=""
    PKG_DEB_OPTIONS=""
    ;;
*)
    fatal "Unknown project/role combination: $CFBUILD_PROJECT-$CFBUILD_ROLE"
    ;;
esac

# --- Debug/release build options ---

case "$CFBUILD_TYPE" in
debug)
    PKG_DEB_OPTIONS="noopt nostrip"
    # Embedded quotes are consumed literally by the rpm handler.
    # shellcheck disable=SC2089
    PKG_RPM_OPTIONS="$PKG_RPM_OPTIONS --define 'with_optimize 0' --define 'with_debugsym 1'"
    ;;
release)
    PKG_DEB_OPTIONS="nostrip"
    ;;
esac

# --- Remove devel packages before packaging ---

pkg_uninstall_cfbuild_devel 2>/dev/null || true

# --- Version handling ---

# Read version from the CFEngine source
PKG_VERSION="${CFBUILD_VERSION:-0.0.0}"
if [ -f "$CFBUILD_BASEDIR/core/configure.ac" ]; then
    _detected_ver=$(sed -n 's/.*AC_INIT.*\[\([0-9][0-9.]*\)\].*/\1/p' "$CFBUILD_BASEDIR/core/configure.ac" 2>/dev/null || true)
    if [ -n "$_detected_ver" ]; then
        PKG_VERSION="$_detected_ver"
    fi
fi

# Split version on tilde: MAIN~SUPP
case "$PKG_VERSION" in
*~*)
    PKG_MAIN_VERSION="${PKG_VERSION%~*}"
    PKG_SUPP_VERSION="${PKG_VERSION#*~}"
    ;;
*)
    PKG_MAIN_VERSION="$PKG_VERSION"
    PKG_SUPP_VERSION=""
    ;;
esac

PKG_RELEASE="${CFBUILD_RELEASE:-1}"
PKG_BUILD_NUMBER="${BUILD_NUMBER:-0}"

# Safe prefix for non-standard installations
PKG_SAFE_PREFIX=""
if [ "$CFBUILD_PREFIX" != /var/cfengine ]; then
    PKG_SAFE_PREFIX="$(printf '%s' "$CFBUILD_PREFIX" | sed 's:/::g')"
fi

# Packaging spec/template directory
PKG_TEMPLATE_DIR="$CFBUILD_BASEDIR/buildscripts/packaging/$PKG_NAME"

export PKG_NAME PKG_VERSION PKG_MAIN_VERSION PKG_SUPP_VERSION
export PKG_RELEASE PKG_BUILD_NUMBER PKG_SAFE_PREFIX PKG_TEMPLATE_DIR
# PKG_RPM_OPTIONS carries embedded quotes intentionally (see SC2089 above).
# shellcheck disable=SC2090
export PKG_RPM_OPTIONS PKG_DEB_OPTIONS

log_info "Packaging: $PKG_NAME $PKG_VERSION ($PLATFORM_PACKAGING)"

# --- Dispatch to format handler ---

_handler="$CFBUILD_ROOT/pkg/${PLATFORM_PACKAGING}.sh"
if [ ! -f "$_handler" ]; then
    fatal "No package handler for format: $PLATFORM_PACKAGING (expected $_handler)"
fi

# Package handler is resolved dynamically from PLATFORM_PACKAGING.
# shellcheck disable=SC1090
. "$_handler"

if [ -n "${PKG_OUTPUT:-}" ]; then
    _display_path="$PKG_OUTPUT"
    if [ "${CFBUILD_IN_CONTAINER:-}" = yes ] && [ -n "${CFBUILD_HOST_BASEDIR:-}" ]; then
        _display_path="${CFBUILD_HOST_BASEDIR}${PKG_OUTPUT#"$CFBUILD_BASEDIR"}"
    fi
    log_info "Package: $_display_path"
fi

log_phase_end
log_info "Packaging complete: $PKG_NAME"
