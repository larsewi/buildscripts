#!/bin/sh
# cmd/compile.sh — Compile and install CFEngine to dist directory
#
# Usage: cfbuild compile
#
# Runs make and make install on each CFEngine repository.
# Output goes to $CFBUILD_BASEDIR/cfengine/dist.

log_phase_start "compile"

_DIST="$CFBUILD_BASEDIR/cfengine/dist"
mkdir -p "$_DIST"

# Determine project type
_nova=no
if [ "$CFBUILD_PROJECT" = nova ]; then
    _nova=yes
fi

# Core — always built
log_info "Compiling core..."
run_quiet "$PLATFORM_MAKE" -C "$CFBUILD_BASEDIR/core" -k "$PLATFORM_MAKEFLAGS"
log_info "Installing core..."
run_quiet "$PLATFORM_MAKE" -C "$CFBUILD_BASEDIR/core" install DESTDIR="$_DIST"

# Enterprise — nova only
if [ "$_nova" = yes ]; then
    log_info "Compiling enterprise..."
    run_quiet "$PLATFORM_MAKE" -C "$CFBUILD_BASEDIR/enterprise" -k "$PLATFORM_MAKEFLAGS"
    log_info "Installing enterprise..."
    run_quiet "$PLATFORM_MAKE" -C "$CFBUILD_BASEDIR/enterprise" install DESTDIR="$_DIST"

    # Nova — hub only
    if [ "$CFBUILD_ROLE" = hub ]; then
        log_info "Compiling nova..."
        run_quiet "$PLATFORM_MAKE" -C "$CFBUILD_BASEDIR/nova" -k "$PLATFORM_MAKEFLAGS"
        log_info "Installing nova..."
        run_quiet "$PLATFORM_MAKE" -C "$CFBUILD_BASEDIR/nova" install DESTDIR="$_DIST"
    fi
fi

# Masterfiles — always installed
log_info "Installing masterfiles..."
run_quiet "$PLATFORM_MAKE" -C "$CFBUILD_BASEDIR/masterfiles" install DESTDIR="$_DIST"

log_phase_end
log_info "Compilation complete. Output: $_DIST"
