#!/bin/sh
# deps/lmdb.sh — Custom build for LMDB
#
# LMDB doesn't use autoconf — it has a simple Makefile in libraries/liblmdb/.
# Also needs special debug handling (always build with debug symbols in non-release).

dep_build_lmdb() {
    local _version
    _version=$(config_get version "0.9.33")
    local _source
    _source=$(config_get source "openldap-LMDB_${_version}.tar.gz")

    local _build_dir
    _build_dir="$CFBUILD_BASEDIR/lmdb"
    mkdir -p "$_build_dir"
    cd "$_build_dir" || return 1

    # Remove previous source to ensure patches apply cleanly on rebuild
    rm -rf "openldap-LMDB_${_version}" "lmdb-LMDB_${_version}"

    # Unpack — LMDB is distributed inside the OpenLDAP source
    dep_unpack_source lmdb "$_source"

    # Apply patches from the source root — patch paths are relative to it
    # (e.g. libraries/liblmdb/mdb.c), so we must apply before cd'ing deeper.
    cd "openldap-LMDB_${_version}" 2>/dev/null ||
        cd "lmdb-LMDB_${_version}" 2>/dev/null ||
        fatal "Could not find LMDB source directory"
    dep_apply_patches lmdb

    cd libraries/liblmdb ||
        fatal "Could not find liblmdb directory"

    # LMDB uses a simple Makefile; set flags via environment
    local _cflags
    _cflags="$PLATFORM_CFLAGS"

    # Always build LMDB with debug symbols in non-release builds (ENT-10777)
    if [ "$CFBUILD_TYPE" != release ]; then
        _cflags="$_cflags -g"
    fi

    # Build
    log_debug "Building LMDB"
    run_quiet "$PLATFORM_MAKE" \
        CC="${PLATFORM_CC}" \
        CFLAGS="$_cflags" \
        LDFLAGS="$PLATFORM_LDFLAGS" \
        prefix="$CFBUILD_PREFIX" \
        "$PLATFORM_MAKEFLAGS"

    # Build CFEngine-specific LMDB tools (added by patches, not in upstream Makefile)
    log_debug "Building lmdump and lmmgr"
    run_quiet "$PLATFORM_MAKE" \
        CC="${PLATFORM_CC}" \
        CFLAGS="$_cflags" \
        LDFLAGS="$PLATFORM_LDFLAGS" \
        lmdump.o lmmgr.o
    # shellcheck disable=SC2086
    ${PLATFORM_CC} $_cflags $PLATFORM_LDFLAGS lmdump.o liblmdb.a -lpthread -o lmdump
    # shellcheck disable=SC2086
    ${PLATFORM_CC} $_cflags $PLATFORM_LDFLAGS lmmgr.o liblmdb.a -lpthread -o lmmgr

    # Test
    if [ "$CFBUILD_TESTS" = yes ]; then
        run_quiet "$PLATFORM_MAKE" test || true
    fi

    # Install to staging
    local _staging
    _staging="$_build_dir/staging"
    mkdir -p "$_staging/$CFBUILD_PREFIX"
    run_quiet "$PLATFORM_MAKE" \
        prefix="$CFBUILD_PREFIX" \
        DESTDIR="$_staging" \
        install

    # Install CFEngine-specific tools (not handled by upstream Makefile)
    cp lmdump lmmgr "$_staging/$CFBUILD_PREFIX/bin/"

    log_info "LMDB ${_version} built and staged successfully"
}

dep_build_lmdb
