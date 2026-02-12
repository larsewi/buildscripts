#!/bin/sh
# pkg/msi.sh — Windows MSI package creation (via WiX + Wine)
#
# Creates Windows MSI installer packages using the WiX toolset.
# This runs on Linux using Wine to execute the .NET-based WiX tools.

log_info "Creating Windows MSI package"

# MSI packaging is delegated to the existing package-msi script
# or a simplified version below if the original is not available.

_MSI_SCRIPT="$CFBUILD_BASEDIR/buildscripts/build-scripts/package-msi"
if [ -x "$_MSI_SCRIPT" ]; then
    log_info "Delegating to existing package-msi script"

    # Set up environment expected by the legacy script
    export PROJECT="$CFBUILD_PROJECT"
    export ROLE="$CFBUILD_ROLE"
    export BUILD_TYPE
    # CFBUILD_TYPE is not a misspelling of BUILD_TYPE; both are used intentionally.
    # shellcheck disable=SC2153
    case "$CFBUILD_TYPE" in
    debug) BUILD_TYPE=DEBUG ;;
    release) BUILD_TYPE=RELEASE ;;
    esac
    export BASEDIR="$CFBUILD_BASEDIR"
    export BUILDPREFIX="$CFBUILD_PREFIX"
    export PREFIX="$CFBUILD_PREFIX"
    export ARCH="$PLATFORM_ARCH"
    export CROSS_TARGET="$PLATFORM_CROSS_TARGET"

    "$_MSI_SCRIPT"
else
    log_info "Building MSI from scratch"

    # Verify Wine is available
    command -v wine >/dev/null 2>&1 || fatal "Wine is required for MSI packaging"

    # Determine cross-compile host triple
    local _host
    case "$PLATFORM_ARCH" in
    x64) _host="x86_64-w64-mingw32" ;;
    x86) _host="i686-w64-mingw32" ;;
    *) fatal "MSI packaging: unsupported arch: $PLATFORM_ARCH" ;;
    esac

    # WiX toolset location
    _WIX_DIR="${CFBUILD_BASEDIR}/wix"
    if [ ! -d "$_WIX_DIR" ]; then
        log_warn "WiX toolset not found at $_WIX_DIR"
        log_warn "MSI packaging requires the WiX toolset to be pre-installed"
        fatal "WiX toolset not available"
    fi

    _DIST="$CFBUILD_BASEDIR/cfengine/dist"
    _WXS="$PKG_TEMPLATE_DIR/msi/$PKG_NAME.wxs"

    if [ ! -f "$_WXS" ]; then
        fatal "WiX source file not found: $_WXS"
    fi

    # Compile .wxs to .wixobj
    log_info "Running candle.exe (WiX compiler)..."
    wine "$_WIX_DIR/candle.exe" -nologo \
        -dVersion="$PKG_VERSION" \
        -dSourceDir="$_DIST" \
        -dPlatform="$PLATFORM_ARCH" \
        -out "$CFBUILD_BASEDIR/$PKG_NAME/$PKG_NAME.wixobj" \
        "$_WXS"

    # Link .wixobj to .msi
    log_info "Running light.exe (WiX linker)..."
    wine "$_WIX_DIR/light.exe" -nologo \
        -out "$CFBUILD_BASEDIR/$PKG_NAME/$PKG_NAME-$PKG_VERSION-$PLATFORM_ARCH.msi" \
        "$CFBUILD_BASEDIR/$PKG_NAME/$PKG_NAME.wixobj"

    # PKG_OUTPUT is used by cmd/package.sh
    # shellcheck disable=SC2034
    PKG_OUTPUT="$CFBUILD_BASEDIR/$PKG_NAME/$PKG_NAME-$PKG_VERSION-$PLATFORM_ARCH.msi"
    log_info "MSI package created: $PKG_NAME-$PKG_VERSION-$PLATFORM_ARCH.msi"
fi
