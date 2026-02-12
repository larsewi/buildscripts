#!/bin/sh
# deps/apache.sh — Custom build for Apache HTTPD
#
# Apache requires APR and APR-util to be pre-installed, and has
# CFEngine-specific module configuration.

dep_build_apache() {
    local _version
    _version=$(config_get version "2.4.66")
    local _source
    _source=$(config_get source "httpd-${_version}.tar.gz")

    local _build_dir
    _build_dir="$CFBUILD_BASEDIR/apache"
    mkdir -p "$_build_dir"
    cd "$_build_dir" || return 1

    # Unpack
    dep_unpack_source apache "$_source"
    cd "httpd-${_version}" || return 1

    # Apply patches
    dep_apply_patches apache

    # Configure Apache with CFEngine-specific options
    log_debug "Configuring Apache HTTPD"
    run_quiet ./configure \
        --prefix="$CFBUILD_PREFIX/httpd" \
        --enable-so \
        --enable-mods-shared="all ssl" \
        --with-z="$CFBUILD_PREFIX" \
        --with-ssl="$CFBUILD_PREFIX" \
        --with-apr="$CFBUILD_PREFIX" \
        --with-apr-util="$CFBUILD_PREFIX" \
        --with-pcre="$CFBUILD_PREFIX/bin/pcre2-config" \
        --sysconfdir="$CFBUILD_PREFIX/httpd/conf" \
        --enable-mpms-shared=all \
        --enable-rewrite \
        --enable-headers \
        --disable-dav \
        LDFLAGS="$PLATFORM_LDFLAGS" \
        CFLAGS="$PLATFORM_CFLAGS"

    # Build
    run_quiet "$PLATFORM_MAKE" "$PLATFORM_MAKEFLAGS"

    # Install to staging
    local _staging
    _staging="$_build_dir/staging"
    mkdir -p "$_staging"
    run_quiet "$PLATFORM_MAKE" DESTDIR="$_staging" install

    log_info "Apache HTTPD ${_version} built and staged successfully"
}

dep_build_apache
