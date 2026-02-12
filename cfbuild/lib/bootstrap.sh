#!/bin/sh
# lib/bootstrap.sh — POSIX shell compliance check and re-execution
#
# Dependencies: none (must be sourceable by any /bin/sh)
# Provides: Ensures the running shell supports required POSIX features.
#           Re-execs under a compliant shell if the current one is broken.

if [ "$_CFBUILD_BOOTSTRAP_DONE" = yes ]; then
    return 0 2>/dev/null || exit 0
fi

# Test whether the current shell supports the features we need.
# Some platforms (notably Solaris) ship a /bin/sh that lacks POSIX
# features like $(command) substitution, local variables, or arithmetic.
_cfbuild_test_shell() {
    # Test command substitution
    _test_var=$(printf 'ok') || return 1
    [ "$_test_var" = ok ] || return 1

    # Test local keyword (not strictly POSIX, but supported everywhere we care about)
    _cfbuild_test_local() {
        local _x
        _x=1
        return 0
    }
    _cfbuild_test_local || return 1
    unset -f _cfbuild_test_local

    # Test arithmetic expansion
    _test_var=$((1 + 1))
    [ "$_test_var" = 2 ] || return 1

    unset _test_var
    return 0
}

if ! _cfbuild_test_shell 2>/dev/null; then
    # Try known POSIX-compliant shells on exotic platforms
    for _shell in /usr/xpg4/bin/sh /usr/bin/ksh /usr/bin/bash; do
        if [ -x "$_shell" ]; then
            printf '%s\n' "cfbuild: re-executing under $_shell (current shell lacks POSIX features)" >&2
            exec "$_shell" "$0" "$@"
        fi
    done
    printf '%s\n' "cfbuild: FATAL: no POSIX-compliant shell found" >&2
    exit 99
fi

unset -f _cfbuild_test_shell
_CFBUILD_BOOTSTRAP_DONE=yes
