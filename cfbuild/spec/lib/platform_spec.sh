#!/bin/sh
# spec/lib/platform_spec.sh — Tests for lib/platform.sh

Describe '_detect_kernel'
    It 'detects the current kernel'
        . "$CFBUILD_ROOT/lib/platform.sh"
        When call _detect_kernel
        The variable PLATFORM_KERNEL should be present
    End
End

Describe '_detect_linux_distro'
    It 'detects a Linux distribution on Linux systems'
        # Only run on Linux
        Skip if "not Linux" [ "$(uname -s)" != "Linux" ]
        . "$CFBUILD_ROOT/lib/platform.sh"
        PLATFORM_KERNEL=Linux
        When call _detect_os
        The variable PLATFORM_OS should be present
        The variable PLATFORM_OS_VERSION should be present
    End
End

Describe '_resolve_platform_config_file'
    . "$CFBUILD_ROOT/lib/platform.sh"

    It 'finds a config file for the detected platform'
        PLATFORM_KERNEL=Linux
        PLATFORM_OS=debian
        PLATFORM_OS_VERSION_MAJOR=12
        When call _resolve_platform_config_file "$CFBUILD_ROOT/etc/platforms"
        The output should be present
    End

    It 'tries kernel_os pattern'
        PLATFORM_KERNEL=AIX
        PLATFORM_OS=aix
        PLATFORM_OS_VERSION_MAJOR=7
        When call _resolve_platform_config_file "$CFBUILD_ROOT/etc/platforms"
        The output should include "aix"
    End
End

Describe 'platform_detect'
    It 'detects the current platform and loads config'
        # Only meaningful on Linux (CI environment)
        Skip if "not Linux" [ "$(uname -s)" != "Linux" ]
        . "$CFBUILD_ROOT/lib/platform.sh"
        _CFBUILD_PLATFORM_SOURCED=  # Reset guard to allow re-detection
        CFBUILD_PREFIX=/var/cfengine
        When call platform_detect
        The variable PLATFORM_MAKE should be present
        The variable PLATFORM_PACKAGING should be present
    End
End
