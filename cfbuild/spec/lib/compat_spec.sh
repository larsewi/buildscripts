#!/bin/sh
# spec/lib/compat_spec.sh — Tests for lib/compat.sh

Describe 'compat_mktemp'
    It 'creates a temporary file'
        When call compat_mktemp
        The output should be present
        The path "$(compat_mktemp)" should be file
    End
End

Describe 'compat_mktempdir'
    It 'creates a temporary directory'
        _dir=""
        result() { _dir=$(compat_mktempdir); printf '%s' "$_dir"; }
        When call result
        The output should be present
    End
End

Describe 'compat_sha256'
    setup() {
        _test_file=$(compat_mktemp)
        printf 'hello world\n' > "$_test_file"
        register_cleanup_file "$_test_file"
    }
    Before 'setup'

    It 'computes a sha256 hash'
        When call compat_sha256 "$_test_file"
        The output should be present
        The length of output should not equal 0
    End
End

Describe 'compat_nproc'
    It 'returns a positive number'
        When call compat_nproc
        The output should be present
    End
End

Describe 'compat_sed_inplace'
    setup() {
        _test_file=$(compat_mktemp)
        printf 'hello world\n' > "$_test_file"
        register_cleanup_file "$_test_file"
    }
    Before 'setup'

    It 'replaces text in a file'
        When call compat_sed_inplace 's/hello/goodbye/' "$_test_file"
        The contents of file "$_test_file" should include "goodbye world"
    End
End
