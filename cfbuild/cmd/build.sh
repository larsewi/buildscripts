#!/bin/sh
# cmd/build.sh — Full build pipeline
#
# Usage: cfbuild build
#
# Runs: deps → configure → compile → package
# This is the main entry point for a complete build.
#
# Unlike 'cfbuild clean', this does NOT remove the prefix directory.
# Dependency stamps and install markers in the prefix are preserved so
# that unchanged dependencies are skipped on subsequent runs.
# Run 'cfbuild clean' explicitly before 'cfbuild build' if you need a
# full rebuild.

log_phase_start "full-build"

log_info "Starting full build pipeline"
printf '\n'
printf '  Platform\n'
printf '  --------\n'
printf '  Kernel:        %s\n' "$PLATFORM_KERNEL"
printf '  OS:            %s %s\n' "$PLATFORM_OS" "$PLATFORM_OS_VERSION"
printf '  Architecture:  %s\n' "$PLATFORM_ARCH"
printf '  Cross Target:  %s\n' "${PLATFORM_CROSS_TARGET:-none}"
printf '\n'
printf '  Build Configuration\n'
printf '  -------------------\n'
printf '  Packaging:     %s\n' "$PLATFORM_PACKAGING"
printf '  Dep Packaging: %s\n' "$PLATFORM_DEP_PACKAGING"
printf '  Make:          %s\n' "$PLATFORM_MAKE"
printf '  CC:            %s\n' "$PLATFORM_CC"
printf '  CPU Cores:     %s\n' "$PLATFORM_CORES"
printf '  Has systemd:   %s\n' "$PLATFORM_HAS_SYSTEMD"
printf '  LDFLAGS:       %s\n' "$PLATFORM_LDFLAGS"
printf '  CFLAGS:        %s\n' "$PLATFORM_CFLAGS"
printf '\n'
printf '  Project Settings\n'
printf '  ----------------\n'
printf '  Project:       %s\n' "$CFBUILD_PROJECT"
printf '  Role:          %s\n' "$CFBUILD_ROLE"
printf '  Build Type:    %s\n' "$CFBUILD_TYPE"
printf '  Prefix:        %s\n' "$CFBUILD_PREFIX"
printf '\n'

# Step 1: Clean build artifacts (preserve prefix for dep caching)
log_info "Step 1/5: Clean"
pkg_uninstall_cfbuild_devel 2>/dev/null || true
pkg_uninstall_cfbuild 2>/dev/null || true
_dist="$CFBUILD_BASEDIR/cfengine/dist"
if [ -d "$_dist" ]; then
    log_info "Removing dist directory: $_dist"
    rm -rf "$_dist"
fi
for _repo in core enterprise nova masterfiles; do
    if [ -d "$CFBUILD_BASEDIR/$_repo" ] && [ -f "$CFBUILD_BASEDIR/$_repo/Makefile" ]; then
        log_debug "Cleaning $_repo..."
        "$PLATFORM_MAKE" -C "$CFBUILD_BASEDIR/$_repo" clean >/dev/null 2>&1 || true
    fi
done

# Step 2: Dependencies
log_info "Step 2/5: Dependencies"
. "$CFBUILD_ROOT/cmd/deps.sh"

# Step 3: Configure
log_info "Step 3/5: Configure"
. "$CFBUILD_ROOT/cmd/configure.sh"

# Step 4: Compile
log_info "Step 4/5: Compile"
. "$CFBUILD_ROOT/cmd/compile.sh"

# Step 5: Package
log_info "Step 5/5: Package"
. "$CFBUILD_ROOT/cmd/package.sh"

log_phase_end
log_info "Full build pipeline complete"
