#!/bin/sh
# pkg/freebsd.sh — FreeBSD TBZ package creation
#
# Creates FreeBSD packages using pkg_create.

log_info "Creating FreeBSD TBZ package"

_ARCH=$(uname -m)

# Prepare clean packaging directory
rm -rf "$CFBUILD_BASEDIR/$PKG_NAME/pkg"
mkdir -p "$CFBUILD_BASEDIR/$PKG_NAME/pkg"

# Copy CFEngine distribution files
cp -pr "$CFBUILD_BASEDIR/cfengine/dist"/* "$CFBUILD_BASEDIR/$PKG_NAME/pkg/"
cp -pr "$CFBUILD_PREFIX/lib"/* "$CFBUILD_BASEDIR/$PKG_NAME/pkg$CFBUILD_PREFIX/lib/"

cd "$CFBUILD_BASEDIR/$PKG_NAME/pkg" || exit 1

# Generate packing list
_PLIST="$CFBUILD_BASEDIR/$PKG_NAME/plist"
find . -type f | sed 's|^\./||' >"$_PLIST"

# Generate installation scripts
_PREINSTALL="$CFBUILD_BASEDIR/$PKG_NAME/preinstall"
_POSTINSTALL="$CFBUILD_BASEDIR/$PKG_NAME/postinstall"
_PREREMOVE="$CFBUILD_BASEDIR/$PKG_NAME/preremove"

if [ -x "$PKG_TEMPLATE_DIR/../common/produce-script" ]; then
    "$PKG_TEMPLATE_DIR/../common/produce-script" "$PKG_NAME" preinstall freebsd >"$_PREINSTALL"
    "$PKG_TEMPLATE_DIR/../common/produce-script" "$PKG_NAME" postinstall freebsd >"$_POSTINSTALL"
    "$PKG_TEMPLATE_DIR/../common/produce-script" "$PKG_NAME" preremove freebsd >"$_PREREMOVE"
fi

# Determine package filename
if [ "$CFBUILD_TYPE" = release ]; then
    _NAME="$PKG_NAME-$PKG_VERSION.$PKG_RELEASE"
else
    _NAME="$PKG_NAME-$PKG_VERSION"
fi

# Create TBZ package
log_info "Running pkg_create..."
pkg_create \
    -c "CFEngine - $PKG_NAME" \
    -d "CFEngine configuration management agent" \
    -f "$_PLIST" \
    -p / \
    -i "$_PREINSTALL" \
    -I "$_POSTINSTALL" \
    -k "$_PREREMOVE" \
    "$CFBUILD_BASEDIR/$PKG_NAME/$_NAME.tbz"

# PKG_OUTPUT is used by cmd/package.sh
# shellcheck disable=SC2034
PKG_OUTPUT="$CFBUILD_BASEDIR/$PKG_NAME/$_NAME.tbz"

log_info "FreeBSD package created: $_NAME.tbz"
