#!/bin/sh
# pkg/mingw.sh — MinGW cross-compilation packaging
#
# Delegates to the MSI handler for Windows package creation.

log_info "MinGW packaging: delegating to MSI handler"
. "$CFBUILD_ROOT/pkg/msi.sh"
