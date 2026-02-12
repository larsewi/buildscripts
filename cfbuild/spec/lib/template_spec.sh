#!/bin/sh
# spec/lib/template_spec.sh — Tests for lib/template.sh

Describe 'template_expand'
    setup() {
        _input=$(compat_mktemp)
        _output=$(compat_mktemp)
        register_cleanup_file "$_input"
        register_cleanup_file "$_output"
    }
    Before 'setup'

    It 'expands simple @VAR@ placeholders'
        printf 'Name: @NAME@\nVersion: @VERSION@\n' > "$_input"
        When call template_expand "$_input" "$_output" "NAME=openssl" "VERSION=3.6.0"
        The contents of file "$_output" should include "Name: openssl"
        The contents of file "$_output" should include "Version: 3.6.0"
    End

    It 'expands path-like values'
        printf 'Prefix: @PREFIX@\n' > "$_input"
        When call template_expand "$_input" "$_output" "PREFIX=/var/cfengine"
        The contents of file "$_output" should include "Prefix: /var/cfengine"
    End

    It 'handles no substitutions (just copies)'
        printf 'No vars here\n' > "$_input"
        When call template_expand "$_input" "$_output"
        The contents of file "$_output" should include "No vars here"
    End

    It 'replaces multiple occurrences of the same var'
        printf '@X@ and @X@ again\n' > "$_input"
        When call template_expand "$_input" "$_output" "X=hello"
        The contents of file "$_output" should include "hello and hello again"
    End
End
