#!/bin/sh
# pkg/aix.sh — AIX BFF/LPP package creation
#
# AIX uses RPM for building, then converts to BFF (Backup File Format)
# for native AIX package management.

log_info "Creating AIX BFF package"

# First, build as RPM (AIX uses RPM for deps)
for _dir in BUILD RPMS SOURCES SRPMS; do
    mkdir -p "$CFBUILD_BASEDIR/$PKG_NAME/$_dir"
done

# Use AIX-specific spec template
_SPECIN="$PKG_TEMPLATE_DIR/$PKG_NAME.spec.aix.in"
if [ ! -f "$_SPECIN" ]; then
    _SPECIN="$PKG_TEMPLATE_DIR/$PKG_NAME.spec.in"
fi
_SPEC="$PKG_TEMPLATE_DIR/$PKG_NAME.spec"

# Generate installation scripts
if [ -x "$PKG_TEMPLATE_DIR/../common/produce-script" ]; then
    _PREINSTALL="$PKG_TEMPLATE_DIR/generated.preinstall"
    _POSTINSTALL="$PKG_TEMPLATE_DIR/generated.postinstall"
    _PREREMOVE="$PKG_TEMPLATE_DIR/generated.preremove"
    _POSTREMOVE="$PKG_TEMPLATE_DIR/generated.postremove"

    "$PKG_TEMPLATE_DIR/../common/produce-script" "$PKG_NAME" preinstall rpm >"$_PREINSTALL"
    "$PKG_TEMPLATE_DIR/../common/produce-script" "$PKG_NAME" postinstall rpm >"$_POSTINSTALL"
    "$PKG_TEMPLATE_DIR/../common/produce-script" "$PKG_NAME" preremove rpm >"$_PREREMOVE"
    "$PKG_TEMPLATE_DIR/../common/produce-script" "$PKG_NAME" postremove rpm >"$_POSTREMOVE"
fi

# Determine release number
_RPM_VERSION="$PKG_MAIN_VERSION"
if [ -z "$PKG_SUPP_VERSION" ]; then
    if [ "$CFBUILD_TYPE" = release ]; then
        _RPM_RELEASE="$PKG_RELEASE"
    else
        _RPM_RELEASE="$PKG_BUILD_NUMBER"
    fi
else
    if [ "$CFBUILD_TYPE" = release ]; then
        _RPM_RELEASE="$PKG_SUPP_VERSION"
    else
        _RPM_RELEASE="$PKG_SUPP_VERSION.$PKG_BUILD_NUMBER"
    fi
fi

# Generate spec from template
if [ -f "$_SPECIN" ]; then
    sed \
        -e "s/@@VERSION@@/$_RPM_VERSION/g" \
        -e "s/@@RELEASE@@/${PKG_SAFE_PREFIX}${_RPM_RELEASE}/g" \
        "$_SPECIN" >"$_SPEC"
fi

# Link packaging files to SOURCES
if command -v find >/dev/null 2>&1; then
    find "$CFBUILD_BASEDIR/buildscripts/packaging/$PKG_NAME" ! -name "*.spec" \
        -exec ln -sf {} "$CFBUILD_BASEDIR/$PKG_NAME/SOURCES" \; 2>/dev/null || true
fi

# Build RPM first
log_info "Running rpmbuild for AIX..."
eval rpmbuild -bb \
    --define "'_topdir $CFBUILD_BASEDIR/$PKG_NAME'" \
    --define "'buildprefix $CFBUILD_PREFIX'" \
    --define "'_basedir $CFBUILD_BASEDIR'" \
    "$PKG_RPM_OPTIONS" "'$_SPEC'"

# Convert RPM to BFF using the AIX-specific script
_BFF_SCRIPT="$PKG_TEMPLATE_DIR/$PKG_NAME.bff.sh"
if [ -x "$_BFF_SCRIPT" ]; then
    log_info "Converting RPM to BFF format..."
    "$_BFF_SCRIPT" "$_RPM_VERSION-${PKG_SAFE_PREFIX}${_RPM_RELEASE}" "$CFBUILD_BASEDIR" "$CFBUILD_PREFIX"
else
    log_warn "BFF conversion script not found: $_BFF_SCRIPT"
    log_info "RPM package created (BFF conversion skipped)"
fi

# Find the created package (PKG_OUTPUT is used by cmd/package.sh)
for _f in "$CFBUILD_BASEDIR/$PKG_NAME/RPMS"/*/*.rpm; do
    # shellcheck disable=SC2034
    [ -f "$_f" ] && PKG_OUTPUT="$_f"
done

log_info "AIX package creation complete"
