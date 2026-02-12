#!/bin/sh
# spec/lib/deps_spec.sh — Tests for lib/deps.sh (dependency resolution)

Describe 'dep_resolve_list'
    setup() {
        . "$CFBUILD_ROOT/lib/platform.sh"
        . "$CFBUILD_ROOT/lib/deps.sh"
        # Mock platform detection for consistent test results
        PLATFORM_OS=debian
        PLATFORM_OS_VERSION_MAJOR=12
        CFG_os_family=linux
        CFG_extra_deps=""
    }
    Before 'setup'

    It 'includes common deps for community agent'
        CFBUILD_PROJECT=community
        CFBUILD_ROLE=agent
        When call dep_resolve_list
        The output should include "lmdb"
        The output should include "pcre2"
        The output should include "libxml2"
        The output should include "libyaml"
        The output should include "libcurl"
    End

    It 'includes enterprise deps for nova'
        CFBUILD_PROJECT=nova
        CFBUILD_ROLE=agent
        When call dep_resolve_list
        The output should include "openldap"
        The output should include "leech"
    End

    It 'includes hub deps for nova-hub'
        CFBUILD_PROJECT=nova
        CFBUILD_ROLE=hub
        When call dep_resolve_list
        The output should include "apache"
        The output should include "postgresql"
        The output should include "php"
        The output should include "libcurl-hub"
    End

    It 'does not include hub deps for agent'
        CFBUILD_PROJECT=community
        CFBUILD_ROLE=agent
        When call dep_resolve_list
        The output should not include "apache"
        The output should not include "postgresql"
    End

    It 'includes libattr and libacl on Linux'
        CFG_os_family=linux
        CFBUILD_PROJECT=community
        CFBUILD_ROLE=agent
        When call dep_resolve_list
        The output should include "libattr"
        The output should include "libacl"
    End

    It 'excludes libattr and libacl on AIX'
        CFG_os_family=aix
        CFBUILD_PROJECT=community
        CFBUILD_ROLE=agent
        When call dep_resolve_list
        The output should not include "libattr"
        The output should not include "libacl"
    End

    It 'skips openssl on RHEL 8+'
        PLATFORM_OS=rhel
        PLATFORM_OS_VERSION_MAJOR=8
        CFBUILD_PROJECT=community
        CFBUILD_ROLE=agent
        When call dep_resolve_list
        The output should not include "openssl"
    End
End
