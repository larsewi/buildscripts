#!/bin/sh
# deps/php.sh — Custom build for PHP
#
# PHP for CFEngine Mission Portal hub. Requires Apache, PostgreSQL,
# OpenLDAP, libcurl, and OpenSSL to be pre-installed.

dep_build_php() {
    local _version
    _version=$(config_get version "8.5.2")
    local _source
    _source=$(config_get source "php-${_version}.tar.gz")

    local _build_dir
    _build_dir="$CFBUILD_BASEDIR/php"
    mkdir -p "$_build_dir"
    cd "$_build_dir" || return 1

    # Unpack
    dep_unpack_source php "$_source"
    cd "php-${_version}" || return 1

    # Configure PHP with CFEngine-specific options
    local _ssl_flags
    _ssl_flags=""
    if [ "$CFBUILD_SYSTEM_SSL" = yes ]; then
        _ssl_flags="--with-openssl"
    else
        _ssl_flags="--with-openssl=$CFBUILD_PREFIX"
    fi

    log_debug "Configuring PHP"
    run_quiet ./configure \
        --prefix="$CFBUILD_PREFIX" \
        --with-apxs2="$CFBUILD_PREFIX/httpd/bin/apxs" \
        --with-config-file-path="$CFBUILD_PREFIX/httpd/php" \
        --with-pgsql="$CFBUILD_PREFIX" \
        --with-pdo-pgsql="$CFBUILD_PREFIX" \
        --with-ldap="$CFBUILD_PREFIX" \
        --with-curl="$CFBUILD_PREFIX" \
        "$_ssl_flags" \
        --with-libxml-dir="$CFBUILD_PREFIX" \
        --with-zlib="$CFBUILD_PREFIX" \
        --enable-mbstring \
        --enable-sockets \
        --enable-bcmath \
        --with-sodium=no \
        --without-sqlite3 \
        --without-pdo-sqlite \
        LDFLAGS="$PLATFORM_LDFLAGS" \
        CFLAGS="$PLATFORM_CFLAGS"

    # Build
    run_quiet "$PLATFORM_MAKE" "$PLATFORM_MAKEFLAGS"

    # Install to staging
    local _staging
    _staging="$_build_dir/staging"
    mkdir -p "$_staging"
    run_quiet "$PLATFORM_MAKE" DESTDIR="$_staging" install

    log_info "PHP ${_version} built and staged successfully"
}

dep_build_php
