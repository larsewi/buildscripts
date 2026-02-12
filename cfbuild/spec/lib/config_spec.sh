#!/bin/sh
# spec/lib/config_spec.sh — Tests for lib/config.sh

Describe 'config_read'
    setup() {
        _test_conf=$(compat_mktemp)
        register_cleanup_file "$_test_conf"
    }
    Before 'setup'

    It 'reads simple key=value pairs'
        printf 'name=openssl\nversion=3.6.0\n' > "$_test_conf"
        When call config_read "$_test_conf"
        The variable CFG_name should equal "openssl"
        The variable CFG_version should equal "3.6.0"
    End

    It 'skips comment lines'
        printf '# this is a comment\nname=test\n' > "$_test_conf"
        When call config_read "$_test_conf"
        The variable CFG_name should equal "test"
    End

    It 'skips blank lines'
        printf '\nname=test\n\nversion=1.0\n' > "$_test_conf"
        When call config_read "$_test_conf"
        The variable CFG_name should equal "test"
        The variable CFG_version should equal "1.0"
    End

    It 'handles values with equals signs'
        printf 'flags=--with-foo=bar\n' > "$_test_conf"
        When call config_read "$_test_conf"
        The variable CFG_flags should equal "--with-foo=bar"
    End

    It 'handles empty values'
        printf 'empty=\n' > "$_test_conf"
        When call config_read "$_test_conf"
        The variable CFG_empty should equal ""
    End
End

Describe 'config_get'
    setup() {
        CFG_name="test_value"
    }
    Before 'setup'

    It 'returns the stored value'
        When call config_get name ""
        The output should equal "test_value"
    End

    It 'returns default when key is not set'
        When call config_get nonexistent "default_val"
        The output should equal "default_val"
    End
End

Describe 'config_has'
    setup() {
        CFG_present="value"
        CFG_empty=""
    }
    Before 'setup'

    It 'returns true for set keys'
        When call config_has present
        The status should be success
    End

    It 'returns false for empty keys'
        When call config_has empty
        The status should be failure
    End

    It 'returns false for missing keys'
        When call config_has missing
        The status should be failure
    End
End
