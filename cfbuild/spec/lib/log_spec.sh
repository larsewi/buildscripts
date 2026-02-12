#!/bin/sh
# spec/lib/log_spec.sh — Tests for lib/log.sh

Describe 'log_info'
    # Re-enable output for testing
    setup() { CFBUILD_QUIET=; }
    Before 'setup'
    cleanup() { CFBUILD_QUIET=yes; }
    After 'cleanup'

    It 'outputs an INFO message to stdout'
        When call log_info "test message"
        The output should include "[INFO ]"
        The output should include "test message"
    End
End

Describe 'log_error'
    It 'outputs an ERROR message to stderr'
        When call log_error "error msg"
        The error should include "[ERROR]"
        The error should include "error msg"
    End
End

Describe 'log_debug'
    It 'suppresses output when CFBUILD_VERBOSE is not set'
        When call log_debug "debug msg"
        The output should equal ""
    End

    Describe 'when CFBUILD_VERBOSE is yes'
        setup_verbose() { CFBUILD_VERBOSE=yes; CFBUILD_QUIET=; }
        Before 'setup_verbose'
        cleanup_verbose() { CFBUILD_VERBOSE=; CFBUILD_QUIET=yes; }
        After 'cleanup_verbose'

        It 'outputs when CFBUILD_VERBOSE is yes'
            When call log_debug "debug msg"
            The output should include "[DEBUG]"
            The output should include "debug msg"
        End
    End
End

Describe 'log_phase_start'
    setup() { CFBUILD_QUIET=; }
    Before 'setup'
    cleanup() { CFBUILD_QUIET=yes; _CFBUILD_LOG_PHASE=""; }
    After 'cleanup'

    It 'sets the phase and outputs a message'
        When call log_phase_start "test-phase"
        The output should include "Phase: test-phase"
        The variable _CFBUILD_LOG_PHASE should equal "test-phase"
    End
End

Describe 'run_quiet'
    It 'suppresses output on success'
        When call run_quiet true
        The status should be success
        The output should equal ""
    End

    It 'shows output on failure'
        When call run_quiet false
        The status should be failure
        The error should include "Command failed"
    End
End
