#!/bin/sh
# pkg/solaris.sh — Solaris SVR4 package creation
#
# Creates Solaris packages using pkgmk and pkgtrans.

log_info "Creating Solaris SVR4 package"

# Prepare clean packaging directory
sudo rm -rf "$CFBUILD_BASEDIR/$PKG_NAME/pkg"
mkdir -p "$CFBUILD_BASEDIR/$PKG_NAME/pkg"

# Copy CFEngine distribution files
rsync -lpr "$CFBUILD_BASEDIR/cfengine/dist"/* "$CFBUILD_BASEDIR/$PKG_NAME/pkg/"
rsync -lpr "$CFBUILD_PREFIX/bin"/* "$CFBUILD_BASEDIR/$PKG_NAME/pkg$CFBUILD_PREFIX/bin/"
rsync -lpr "$CFBUILD_PREFIX/lib"/* "$CFBUILD_BASEDIR/$PKG_NAME/pkg$CFBUILD_PREFIX/lib/"

cd "$CFBUILD_BASEDIR/$PKG_NAME/pkg" || exit 1

# Generate package prototype file
pkgproto .=/ >../prototype.tmp
mv ../prototype.tmp .

# Build final prototype with proper ownership
(
    cat "$PKG_TEMPLATE_DIR/solaris/prototype.head"
    sed -e 's/^\([fd].* \)[^ ][^ ]*  *[^ ][^ ]*$/\1root root/' prototype.tmp |
        grep -E "^([^d]|d none $CFBUILD_PREFIX)"
) >prototype

# Generate pkginfo
_ARCH="$(uname -p)"
sed -e "s/@@PKG@@/$PKG_NAME/g" \
    -e "s/@@ARCH@@/$_ARCH/g" \
    -e "s/@@VERSION@@/${PKG_VERSION}${PKG_SAFE_PREFIX}/g" \
    "$PKG_TEMPLATE_DIR/solaris/pkginfo.in" >pkginfo

# Generate installation scripts
# "preinstall" etc. are phase name arguments to produce-script, not the output files they redirect to.
# shellcheck disable=SC2094
if [ -x "$PKG_TEMPLATE_DIR/../common/produce-script" ]; then
    "$PKG_TEMPLATE_DIR/../common/produce-script" "$PKG_NAME" preinstall pkg >preinstall
    "$PKG_TEMPLATE_DIR/../common/produce-script" "$PKG_NAME" postinstall pkg >postinstall
    "$PKG_TEMPLATE_DIR/../common/produce-script" "$PKG_NAME" preremove pkg >preremove
    "$PKG_TEMPLATE_DIR/../common/produce-script" "$PKG_NAME" postremove pkg >postremove
fi

# Build package
log_info "Running pkgmk..."
pkgmk -o -r "$(pwd)" -d "$CFBUILD_BASEDIR/$PKG_NAME/pkg"

# Determine package filename
if [ "$CFBUILD_TYPE" = release ]; then
    _NAME="$PKG_NAME-$PKG_VERSION.$PKG_RELEASE-solaris${PLATFORM_OS_VERSION}-${_ARCH}.pkg"
else
    _NAME="$PKG_NAME-$PKG_VERSION-solaris${PLATFORM_OS_VERSION}-${_ARCH}.pkg"
fi

# Create final package
log_info "Running pkgtrans..."
pkgtrans -o -s "$CFBUILD_BASEDIR/$PKG_NAME/pkg" "$CFBUILD_BASEDIR/$PKG_NAME/$_NAME" "CFE${PKG_NAME}"

# PKG_OUTPUT is used by cmd/package.sh
# shellcheck disable=SC2034
PKG_OUTPUT="$CFBUILD_BASEDIR/$PKG_NAME/$_NAME"

log_info "Solaris package created: $_NAME"
