#!/bin/sh
# pkg/deb.sh — Debian/Ubuntu package creation
#
# Creates DEB packages using dpkg-buildpackage.

log_info "Creating DEB package"

# Update debian control files for custom prefix
if [ "$CFBUILD_PREFIX" != /var/cfengine ]; then
    for _f in "$PKG_TEMPLATE_DIR/debian"/*; do
        if [ -f "$_f" ]; then
            compat_sed_inplace "s:/var/cfengine:$CFBUILD_PREFIX:g" "$_f"
        fi
    done
fi

# Prepare clean packaging directory
rm -rf "$CFBUILD_BASEDIR/$PKG_NAME/pkg"
mkdir -p "$CFBUILD_BASEDIR/$PKG_NAME/pkg"
cp -a "$PKG_TEMPLATE_DIR"/* "$CFBUILD_BASEDIR/$PKG_NAME/pkg/"

# Determine DEB version
if [ "$CFBUILD_TYPE" = release ]; then
    _DEB_VERSION="$PKG_VERSION-$PKG_RELEASE"
else
    _DEB_VERSION="${PKG_VERSION}~${PKG_BUILD_NUMBER}"
fi

# Generate debian changelog
if [ -f "$CFBUILD_BASEDIR/$PKG_NAME/pkg/debian/changelog.in" ]; then
    sed -e "s/@@VERSION@@/${_DEB_VERSION}${PKG_SAFE_PREFIX}.${PLATFORM_OS}${PLATFORM_OS_VERSION_MAJOR}/" \
        "$CFBUILD_BASEDIR/$PKG_NAME/pkg/debian/changelog.in" \
        >"$CFBUILD_BASEDIR/$PKG_NAME/pkg/debian/changelog"
fi

# Generate maintainer scripts
if [ -x "$PKG_TEMPLATE_DIR/../common/produce-script" ]; then
    "$PKG_TEMPLATE_DIR/../common/produce-script" "$PKG_NAME" preinstall deb \
        >"$CFBUILD_BASEDIR/$PKG_NAME/pkg/debian/$PKG_NAME.preinst"
    "$PKG_TEMPLATE_DIR/../common/produce-script" "$PKG_NAME" postinstall deb \
        >"$CFBUILD_BASEDIR/$PKG_NAME/pkg/debian/$PKG_NAME.postinst"
    "$PKG_TEMPLATE_DIR/../common/produce-script" "$PKG_NAME" preremove deb \
        >"$CFBUILD_BASEDIR/$PKG_NAME/pkg/debian/$PKG_NAME.prerm"
    "$PKG_TEMPLATE_DIR/../common/produce-script" "$PKG_NAME" postremove deb \
        >"$CFBUILD_BASEDIR/$PKG_NAME/pkg/debian/$PKG_NAME.postrm"
fi

# Build DEB package
log_info "Running dpkg-buildpackage..."
(
    cd "$CFBUILD_BASEDIR/$PKG_NAME/pkg" || exit 1
    run_quiet env \
        BUILDPREFIX="$CFBUILD_PREFIX" \
        DEB_BUILD_OPTIONS="$PKG_DEB_OPTIONS" \
        DEB_LDFLAGS_APPEND="$PLATFORM_LDFLAGS" \
        dpkg-buildpackage -b -us -uc -rfakeroot
)

# Find the created package (PKG_OUTPUT is used by cmd/package.sh)
# shellcheck disable=SC2231
for _f in "$CFBUILD_BASEDIR/$PKG_NAME"/${PKG_NAME}_*.deb; do
    # shellcheck disable=SC2034
    [ -f "$_f" ] && PKG_OUTPUT="$_f"
done

log_info "DEB package created successfully"
