#!/bin/sh
# cmd/detect.sh — Print detected platform information
#
# Usage: cfbuild detect [--json]
#
# Prints all detected platform variables and loaded configuration.

_detect_json=no
for _arg in "$@"; do
    case "$_arg" in
    --json) _detect_json=yes ;;
    esac
done

if [ "$_detect_json" = yes ]; then
    # JSON output (useful for CI/scripting)
    printf '{\n'
    printf '  "kernel": "%s",\n' "$PLATFORM_KERNEL"
    printf '  "os": "%s",\n' "$PLATFORM_OS"
    printf '  "os_version": "%s",\n' "$PLATFORM_OS_VERSION"
    printf '  "os_version_major": "%s",\n' "$PLATFORM_OS_VERSION_MAJOR"
    printf '  "arch": "%s",\n' "$PLATFORM_ARCH"
    printf '  "cross_target": "%s",\n' "$PLATFORM_CROSS_TARGET"
    printf '  "packaging": "%s",\n' "$PLATFORM_PACKAGING"
    printf '  "dep_packaging": "%s",\n' "$PLATFORM_DEP_PACKAGING"
    printf '  "make": "%s",\n' "$PLATFORM_MAKE"
    printf '  "cc": "%s",\n' "$PLATFORM_CC"
    printf '  "cores": "%s",\n' "$PLATFORM_CORES"
    printf '  "has_systemd": "%s",\n' "$PLATFORM_HAS_SYSTEMD"
    printf '  "ldflags": "%s",\n' "$PLATFORM_LDFLAGS"
    printf '  "cflags": "%s",\n' "$PLATFORM_CFLAGS"
    printf '  "project": "%s",\n' "$CFBUILD_PROJECT"
    printf '  "role": "%s",\n' "$CFBUILD_ROLE"
    printf '  "type": "%s",\n' "$CFBUILD_TYPE"
    printf '  "prefix": "%s"\n' "$CFBUILD_PREFIX"
    printf '}\n'
else
    # Human-readable output
    printf 'Platform Detection Results\n'
    printf '==========================\n'
    printf 'Kernel:          %s\n' "$PLATFORM_KERNEL"
    printf 'OS:              %s\n' "$PLATFORM_OS"
    printf 'OS Version:      %s\n' "$PLATFORM_OS_VERSION"
    printf 'OS Version Major:%s\n' "$PLATFORM_OS_VERSION_MAJOR"
    printf 'Architecture:    %s\n' "$PLATFORM_ARCH"
    printf 'Cross Target:    %s\n' "${PLATFORM_CROSS_TARGET:-none}"
    printf '\n'
    printf 'Build Configuration\n'
    printf '==========================\n'
    printf 'Packaging:       %s\n' "$PLATFORM_PACKAGING"
    printf 'Dep Packaging:   %s\n' "$PLATFORM_DEP_PACKAGING"
    printf 'Make:            %s\n' "$PLATFORM_MAKE"
    printf 'CC:              %s\n' "$PLATFORM_CC"
    printf 'CPU Cores:       %s\n' "$PLATFORM_CORES"
    printf 'Has systemd:     %s\n' "$PLATFORM_HAS_SYSTEMD"
    printf 'LDFLAGS:         %s\n' "$PLATFORM_LDFLAGS"
    printf 'CFLAGS:          %s\n' "$PLATFORM_CFLAGS"
    printf '\n'
    printf 'Project Settings\n'
    printf '==========================\n'
    printf 'Project:         %s\n' "$CFBUILD_PROJECT"
    printf 'Role:            %s\n' "$CFBUILD_ROLE"
    printf 'Build Type:      %s\n' "$CFBUILD_TYPE"
    printf 'Prefix:          %s\n' "$CFBUILD_PREFIX"
fi
