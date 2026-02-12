#!/bin/sh
# spec/support/helper.sh — ShellSpec test helpers
#
# Loaded before all tests via .shellspec --require

# Set CFBUILD_ROOT for all tests (use shellspec's working directory)
CFBUILD_ROOT="${CFBUILD_ROOT:-$(pwd)}"
export CFBUILD_ROOT

# Source core libraries for unit tests
# (individual spec files can override by mocking)
. "$CFBUILD_ROOT/lib/bootstrap.sh"
. "$CFBUILD_ROOT/lib/log.sh"
. "$CFBUILD_ROOT/lib/error.sh"
. "$CFBUILD_ROOT/lib/config.sh"
. "$CFBUILD_ROOT/lib/compat.sh"
. "$CFBUILD_ROOT/lib/retry.sh"
. "$CFBUILD_ROOT/lib/template.sh"

# Suppress log output during tests
CFBUILD_QUIET=yes
export CFBUILD_QUIET

# Set default test values
CFBUILD_PROJECT=community
CFBUILD_ROLE=agent
CFBUILD_TYPE=debug
CFBUILD_PREFIX=/var/cfengine
CFBUILD_VERBOSE=
CFBUILD_TESTS=yes
export CFBUILD_PROJECT CFBUILD_ROLE CFBUILD_TYPE CFBUILD_PREFIX
