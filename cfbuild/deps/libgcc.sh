#!/bin/sh
# deps/libgcc.sh — Custom build for libgcc runtime library
#
# On AIX and Solaris, the GCC runtime libraries (libgcc_s.so, libstdc++.so)
# are not in the default library path. We bundle them with CFEngine to avoid
# runtime dependency issues.

dep_build_libgcc() {
    local _os_family
    _os_family=$(config_get os_family "linux")

    local _staging
    _staging="$CFBUILD_BASEDIR/libgcc/staging"
    mkdir -p "$_staging/${CFBUILD_PREFIX}/lib"

    case "$_os_family" in
    aix)
        # On AIX, copy libgcc_s from the freeware GCC installation
        local _gcc_lib
        for _gcc_lib in /opt/freeware/lib/gcc/*/lib/libgcc_s.a \
            /opt/freeware/lib/libgcc_s.a; do
            if [ -f "$_gcc_lib" ]; then
                cp "$_gcc_lib" "$_staging/${CFBUILD_PREFIX}/lib/"
                log_info "Copied AIX libgcc: $_gcc_lib"
                break
            fi
        done
        ;;
    solaris)
        # On Solaris, copy libgcc_s from the CSW installation
        local _gcc_lib
        for _gcc_lib in /opt/csw/lib/libgcc_s.so* \
            /opt/csw/lib/amd64/libgcc_s.so* \
            /opt/csw/lib/sparcv9/libgcc_s.so*; do
            if [ -f "$_gcc_lib" ]; then
                cp "$_gcc_lib" "$_staging/${CFBUILD_PREFIX}/lib/"
                log_debug "Copied Solaris libgcc: $_gcc_lib"
            fi
        done
        log_info "Copied Solaris libgcc runtime libraries"
        ;;
    *)
        log_warn "libgcc build not needed for $_os_family"
        ;;
    esac
}

dep_build_libgcc
