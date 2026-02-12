#!/bin/sh
# pkg/rpm.sh — RPM package creation (RHEL, CentOS, Rocky, SUSE)
#
# Creates RPM packages from the compiled CFEngine distribution.

log_info "Creating RPM package"

# Create RPM build directory structure
for _dir in BUILD RPMS SOURCES SRPMS; do
    mkdir -p "$CFBUILD_BASEDIR/$PKG_NAME/$_dir"
done

# Spec file paths
_SPEC="$PKG_TEMPLATE_DIR/$PKG_NAME.spec"
_SPECIN="$PKG_TEMPLATE_DIR/$PKG_NAME.spec.in"
_PREINSTALL="$PKG_TEMPLATE_DIR/generated.preinstall"
_POSTINSTALL="$PKG_TEMPLATE_DIR/generated.postinstall"
_PREREMOVE="$PKG_TEMPLATE_DIR/generated.preremove"
_POSTREMOVE="$PKG_TEMPLATE_DIR/generated.postremove"

# Generate installation scripts from templates
if [ -x "$PKG_TEMPLATE_DIR/../common/produce-script" ]; then
    "$PKG_TEMPLATE_DIR/../common/produce-script" "$PKG_NAME" preinstall rpm >"$_PREINSTALL"
    "$PKG_TEMPLATE_DIR/../common/produce-script" "$PKG_NAME" postinstall rpm >"$_POSTINSTALL"
    "$PKG_TEMPLATE_DIR/../common/produce-script" "$PKG_NAME" preremove rpm >"$_PREREMOVE"
    "$PKG_TEMPLATE_DIR/../common/produce-script" "$PKG_NAME" postremove rpm >"$_POSTREMOVE"
fi

# Determine RPM release number
_RPM_VERSION="$PKG_MAIN_VERSION"
_RPM_RELEASE=""

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

# RHEL-specific: detect system dependency versions
_SELINUX_POLICY_VERSION=""
_OPENSSL_VERSION=""
case "$PLATFORM_OS" in
rhel | centos | rocky)
    _SELINUX_POLICY_VERSION=$(rpm -q --qf '%{VERSION}\n' selinux-policy 2>/dev/null || printf '')
    _OPENSSL_VERSION=$(rpm -q --provides openssl-libs 2>/dev/null |
        sed -n 's/^.*OPENSSL_\([0-9.]*\).*$/\1/p' | sort -n | tail -1 || printf '')
    ;;
esac

# Generate spec file from template
if [ -f "$_SPECIN" ]; then
    sed \
        -e "s/@@VERSION@@/$_RPM_VERSION/g" \
        -e "s/@@RELEASE@@/${PKG_SAFE_PREFIX}${_RPM_RELEASE}/g" \
        -e "s/@@SELINUX_POLICY_VERSION@@/$_SELINUX_POLICY_VERSION/g" \
        -e "s/@@OPENSSL_VERSION@@/$_OPENSSL_VERSION/g" \
        "$_SPECIN" >"$_SPEC"

    # Inject pre/post scripts into spec if the script files exist
    for _phase in pre post preun postun; do
        case "$_phase" in
        pre) _script_file="$_PREINSTALL" ;;
        post) _script_file="$_POSTINSTALL" ;;
        preun) _script_file="$_PREREMOVE" ;;
        postun) _script_file="$_POSTREMOVE" ;;
        esac
        if [ -f "$_script_file" ]; then
            # Insert script content after %<phase> line
            _tmp="$_SPEC.tmp.$$"
            sed "/^%${_phase}\$/r $_script_file" "$_SPEC" >"$_tmp" && mv "$_tmp" "$_SPEC"
        fi
    done
fi

# Link packaging files to SOURCES
if command -v find >/dev/null 2>&1; then
    find "$CFBUILD_BASEDIR/buildscripts/packaging/$PKG_NAME" ! -name "*.spec" -exec ln -sf {} "$CFBUILD_BASEDIR/$PKG_NAME/SOURCES" \; 2>/dev/null || true
fi

# Build RPM
# RHEL 10+ rpmbuild is strict about RPATH — allow /var/cfengine/lib
export QA_RPATHS=2

log_info "Running rpmbuild..."
eval run_quiet rpmbuild -bb \
    --define "'_topdir $CFBUILD_BASEDIR/$PKG_NAME'" \
    --define "'buildprefix $CFBUILD_PREFIX'" \
    --define "'_basedir $CFBUILD_BASEDIR'" \
    "$PKG_RPM_OPTIONS" "'$_SPEC'"

# Find the created package (PKG_OUTPUT is used by cmd/package.sh)
for _f in "$CFBUILD_BASEDIR/$PKG_NAME/RPMS"/*/*.rpm; do
    # shellcheck disable=SC2034
    [ -f "$_f" ] && PKG_OUTPUT="$_f"
done

log_info "RPM package created successfully"
