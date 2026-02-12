#!/bin/sh
# spec/lib/retry_spec.sh — Tests for lib/retry.sh

Describe 'retry'
    It 'succeeds immediately if command succeeds'
        When call retry 3 0 true
        The status should be success
    End

    It 'fails after max attempts'
        When call retry 2 0 false
        The status should be failure
        The error should include "Command failed"
    End

    It 'passes arguments to the command'
        test_cmd() { [ "$1" = "hello" ]; }
        When call retry 1 0 test_cmd "hello"
        The status should be success
    End
End
