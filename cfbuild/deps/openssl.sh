#!/bin/sh
# deps/openssl.sh — Custom build for OpenSSL
#
# OpenSSL uses its own Perl-based Configure system with platform-specific
# targets. This cannot be handled by the generic autoconf template.

dep_build_openssl() {
    local _version
    _version=$(config_get version "3.6.0")
    local _source
    _source=$(config_get source "openssl-${_version}.tar.gz")

    local _build_dir
    _build_dir="$CFBUILD_BASEDIR/openssl"
    mkdir -p "$_build_dir"
    cd "$_build_dir" || return 1

    # Unpack
    dep_unpack_source openssl "$_source"
    cd "openssl-${_version}" || return 1

    # Apply platform-specific patches
    dep_apply_patches openssl

    # Create prefix dir if needed (writable by the build user)
    if [ ! -d "$CFBUILD_PREFIX" ]; then
        sudo mkdir -p "$CFBUILD_PREFIX"
        sudo chown "$(id -u):$(id -g)" "$CFBUILD_PREFIX"
    fi
    mkdir -p "$CFBUILD_PREFIX/include"

    # Determine configure target based on platform
    local _target
    _target=""
    local _os_family
    _os_family=$(config_get os_family "linux")

    case "$_os_family" in
    aix)
        # AIX needs -bexpfull for symbols starting with underscore
        LDFLAGS="$LDFLAGS -Wl,-bexpfull"
        local _aix_ver
        _aix_ver=$(uname -v 2>/dev/null || printf '7')
        if [ "$_aix_ver" -eq 7 ] 2>/dev/null; then
            _target="aix7-gcc"
        else
            _target="aix-gcc"
        fi
        ;;
    solaris)
        case "$PLATFORM_ARCH" in
        sparc64)
            _target="solaris64-sparcv9-gcc"
            ;;
        *)
            _target="solaris-x86-gcc"
            ;;
        esac
        # To pick up libgcc_s.so
        export LD_LIBRARY_PATH="$CFBUILD_PREFIX/lib"
        ;;
    hpux)
        _target="hpux-ia64-gcc"
        export LD_LIBRARY_PATH="$CFBUILD_PREFIX/lib"
        ;;
    mingw)
        case "$PLATFORM_ARCH" in
        x64) _target="mingw64" ;;
        x86) _target="mingw" ;;
        esac
        ;;
    esac

    # Read config flags for the current role
    local _config_flags
    _config_flags=""
    local _flags_file
    for _flags_file in \
        "$CFBUILD_BASEDIR/buildscripts/deps-packaging/openssl/config_flags_${CFBUILD_ROLE}.txt" \
        "$CFBUILD_ROOT/deps/openssl/config_flags_${CFBUILD_ROLE}.txt"; do
        if [ -f "$_flags_file" ]; then
            _config_flags=$(cat "$_flags_file")
            break
        fi
    done

    # Debug build flags
    local _debug_flags
    local _debug_cflags
    _debug_flags=""
    _debug_cflags=""
    if [ "$CFBUILD_TYPE" = debug ]; then
        _debug_flags="no-asm -DPURIFY"
        _debug_cflags="-g2 -O1 -fno-omit-frame-pointer"
    fi

    # Configure
    log_debug "Configuring OpenSSL: target=$_target"
    # Flag variables are intentionally unquoted to split into multiple arguments.
    # shellcheck disable=SC2086
    run_quiet $PERL ./Configure $_target $_config_flags \
        $_debug_flags \
        --prefix="$CFBUILD_PREFIX" \
        $_debug_cflags \
        $LDFLAGS \
        --libdir=lib

    run_quiet "$PERL" configdata.pm --dump || true

    # Remove optimization flags in debug mode
    if [ "$CFBUILD_TYPE" = debug ]; then
        if [ -f Makefile ]; then
            sed 's/ -O3//;s/ -fomit-frame-pointer//' Makefile >Makefile.tmp &&
                mv Makefile.tmp Makefile
        fi
    fi

    # Build
    run_quiet "$PLATFORM_MAKE" depend
    run_quiet "$PLATFORM_MAKE" "$PLATFORM_MAKEFLAGS"

    # Test
    if [ "$CFBUILD_TESTS" = yes ] && [ "$CFBUILD_TYPE" = release ]; then
        "$PLATFORM_MAKE" test || true
    fi

    # Install to staging
    local _staging
    _staging="$_build_dir/staging"
    mkdir -p "$_staging"
    run_quiet "$PLATFORM_MAKE" DESTDIR="${_staging}/cfbuild-openssl-devel" install_sw
    run_quiet "$PLATFORM_MAKE" DESTDIR="${_staging}/cfbuild-openssl-devel" install_ssldirs

    # Split runtime and devel packages
    local _devel_prefix
    _devel_prefix="${_staging}/cfbuild-openssl-devel${CFBUILD_PREFIX}"
    local _runtime_prefix
    _runtime_prefix="${_staging}/cfbuild-openssl${CFBUILD_PREFIX}"

    # Clean up unnecessary files
    rm -rf "${_devel_prefix:?}/bin"
    rm -rf "${_devel_prefix}/ssl"
    rm -rf "${_devel_prefix}/lib/fips"*
    rm -rf "${_devel_prefix}/lib/cmake/OpenSSL"

    # On AIX, .a files ARE shared libraries (they contain shared objects)
    case "$_os_family" in
    aix)
        # Keep .a files on AIX
        ;;
    *)
        rm -f "${_devel_prefix}/lib/"*.a
        ;;
    esac

    # Move runtime libraries to separate package dir
    mkdir -p "${_runtime_prefix}/lib"
    mv "${_devel_prefix}/lib/libcrypto.so"* "${_runtime_prefix}/lib/" 2>/dev/null || true
    mv "${_devel_prefix}/lib/libssl.so"* "${_runtime_prefix}/lib/" 2>/dev/null || true
    if [ -d "${_devel_prefix}/lib/ossl-modules" ]; then
        mv "${_devel_prefix}/lib/ossl-modules" "${_runtime_prefix}/lib/"
    fi

    log_info "OpenSSL ${_version} built and staged successfully"
}

# Entry point
dep_build_openssl
