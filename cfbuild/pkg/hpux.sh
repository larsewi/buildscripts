#!/bin/sh
# pkg/hpux.sh — HP-UX depot package creation
#
# Creates HP-UX depot packages using swpackage.

log_info "Creating HP-UX depot package"

_ARCH=$(uname -m)
_OS_VER=$(uname -r)

# Prepare clean packaging directory
rm -rf "$CFBUILD_BASEDIR/$PKG_NAME/pkg"
mkdir -p "$CFBUILD_BASEDIR/$PKG_NAME/pkg$CFBUILD_PREFIX"

# Copy CFEngine distribution files
cp -pr "$CFBUILD_BASEDIR/cfengine/dist"/* "$CFBUILD_BASEDIR/$PKG_NAME/pkg"
cp -pr "$CFBUILD_PREFIX/lib"/* "$CFBUILD_BASEDIR/$PKG_NAME/pkg$CFBUILD_PREFIX/lib"

# Generate installation scripts
_PREINSTALL="$CFBUILD_BASEDIR/$PKG_NAME/pkg/generated.preinstall"
_POSTINSTALL="$CFBUILD_BASEDIR/$PKG_NAME/pkg/generated.postinstall"
_PREREMOVE="$CFBUILD_BASEDIR/$PKG_NAME/pkg/generated.preremove"
_POSTREMOVE="$CFBUILD_BASEDIR/$PKG_NAME/pkg/generated.postremove"

if [ -x "$PKG_TEMPLATE_DIR/../common/produce-script" ]; then
    "$PKG_TEMPLATE_DIR/../common/produce-script" "$PKG_NAME" preinstall depot >"$_PREINSTALL"
    "$PKG_TEMPLATE_DIR/../common/produce-script" "$PKG_NAME" postinstall depot >"$_POSTINSTALL"
    "$PKG_TEMPLATE_DIR/../common/produce-script" "$PKG_NAME" preremove depot >"$_PREREMOVE"
    "$PKG_TEMPLATE_DIR/../common/produce-script" "$PKG_NAME" postremove depot >"$_POSTREMOVE"
fi

cd "$CFBUILD_BASEDIR/$PKG_NAME/pkg" || exit 1

# Determine package filename
if [ "$CFBUILD_TYPE" = release ]; then
    _NAME="$PKG_NAME-$PKG_VERSION.$PKG_RELEASE${PKG_SAFE_PREFIX}-$_OS_VER-$_ARCH"
else
    _NAME="$PKG_NAME-$PKG_VERSION${PKG_SAFE_PREFIX}-$_OS_VER-$_ARCH"
fi

# Generate PSF (Product Specification File)
_PSF="$CFBUILD_BASEDIR/$PKG_NAME/$PKG_NAME-${PKG_VERSION}${PKG_SAFE_PREFIX}.psf"

if [ -x "$PKG_TEMPLATE_DIR/hpux/psf.pl" ]; then
    "$PKG_TEMPLATE_DIR/hpux/psf.pl" . "$PKG_NAME" "$PKG_VERSION" >"$_PSF"
else
    # Generate a basic PSF if the perl script is not available
    log_warn "psf.pl not found, generating basic PSF"
    cat >"$_PSF" <<EOF
product
    tag         $PKG_NAME
    title       CFEngine - $PKG_NAME
    revision    $PKG_VERSION
    architecture $_ARCH
    machine_type *
    os_name     HP-UX
    os_release  $_OS_VER
    directory   /
    is_locatable false

    fileset
        tag     $PKG_NAME
        title   CFEngine - $PKG_NAME files
        revision $PKG_VERSION

        preinstall   generated.preinstall
        postinstall  generated.postinstall
        preremove    generated.preremove
        postremove   generated.postremove

        file_permissions -u 0022
        file *
    end

end
EOF
fi

# Create depot package
log_info "Running swpackage..."
/usr/sbin/swpackage -s "$_PSF" -x media_type=tape @ "$CFBUILD_BASEDIR/$PKG_NAME/pkg/$_NAME.depot"

# PKG_OUTPUT is used by cmd/package.sh
# shellcheck disable=SC2034
PKG_OUTPUT="$CFBUILD_BASEDIR/$PKG_NAME/pkg/$_NAME.depot"

log_info "HP-UX depot package created: $_NAME.depot"
