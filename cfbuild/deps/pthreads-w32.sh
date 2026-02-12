#!/bin/sh
# deps/pthreads-w32.sh — Custom build for pthreads-w32
#
# Win32 does not support POSIX threads natively.
# pthreads-w32 provides a POSIX threading implementation for Windows.
# Built only for MinGW cross-compilation targets.

dep_build_pthreads_w32() {
    local _version
    _version=$(config_get version "2-9-1")
    local _source
    _source=$(config_get source "pthreads-w32-${_version}-release.tar.gz")

    local _build_dir
    _build_dir="$CFBUILD_BASEDIR/pthreads-w32"
    mkdir -p "$_build_dir"
    cd "$_build_dir" || return 1

    # Unpack
    dep_unpack_source pthreads-w32 "$_source"
    cd "pthreads-w32-${_version}-release" 2>/dev/null || cd pthreads-w32* 2>/dev/null || true

    # Determine cross-compile host
    local _host
    case "$PLATFORM_ARCH" in
    x64) _host="x86_64-w64-mingw32" ;;
    x86) _host="i686-w64-mingw32" ;;
    *) fatal "pthreads-w32: unsupported arch: $PLATFORM_ARCH" ;;
    esac

    # Build using the provided Makefile with CROSS prefix
    run_quiet "$PLATFORM_MAKE" CROSS="${_host}-" clean GC-static

    # Install to staging
    local _staging
    _staging="$_build_dir/staging"
    mkdir -p "$_staging/$CFBUILD_PREFIX/lib"
    mkdir -p "$_staging/$CFBUILD_PREFIX/include"
    cp libpthreadGC2.a "$_staging/$CFBUILD_PREFIX/lib/"
    cp pthread.h sched.h semaphore.h "$_staging/$CFBUILD_PREFIX/include/"

    log_info "pthreads-w32 ${_version} built and staged successfully"
}

dep_build_pthreads_w32
