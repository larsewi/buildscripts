#!/bin/sh
# lib/platform.sh — Platform detection and config loading
#
# Dependencies: lib/config.sh, lib/compat.sh, lib/log.sh
# Provides: platform_detect, platform_id
#
# Detects the current platform (kernel, distribution, version, architecture)
# and loads the matching config file from etc/platforms/.
# Exports PLATFORM_* variables used throughout the build system.

if [ "$_CFBUILD_PLATFORM_SOURCED" = yes ]; then
    return 0 2>/dev/null || exit 0
fi

: "${_CFBUILD_CONFIG_SOURCED:?lib/config.sh must be sourced before lib/platform.sh}"
: "${_CFBUILD_COMPAT_SOURCED:?lib/compat.sh must be sourced before lib/platform.sh}"

# Detected raw values (set by _detect_* functions)
PLATFORM_KERNEL=""           # Linux, SunOS, AIX, HP-UX, FreeBSD
PLATFORM_OS=""               # debian, ubuntu, rhel, centos, sles, opensuse, rocky, solaris, aix, hpux, freebsd, mingw
PLATFORM_OS_VERSION=""       # Full version string (e.g. 11.4, 7.1, B.11.23)
PLATFORM_OS_VERSION_MAJOR="" # Major version only
PLATFORM_ARCH=""             # x86_64, aarch64, i386, sparc64, ppc64, ia64, x86, x64
PLATFORM_CROSS_TARGET=""     # Empty for native builds; x86-mingw or x64-mingw for cross

# Loaded from platform config (set by _load_platform_config)
PLATFORM_MAKE=""
PLATFORM_PATCH=""
PLATFORM_FUSER=""
PLATFORM_CC=""
PLATFORM_PACKAGING=""
PLATFORM_DEP_PACKAGING=""
PLATFORM_LDFLAGS=""
PLATFORM_CFLAGS=""
PLATFORM_CPPFLAGS=""
PLATFORM_RPATH_FLAG=""
PLATFORM_HAS_SYSTEMD=""

# Main entry point: detect everything and load config.
platform_detect() {
    _detect_cross_target
    if [ -n "$PLATFORM_CROSS_TARGET" ]; then
        _detect_cross_platform
    else
        _detect_kernel
        _detect_os
        _detect_arch
    fi
    _detect_cores
    _load_platform_config
    _setup_path
    _expand_platform_flags

    log_debug "Platform: $PLATFORM_OS $PLATFORM_OS_VERSION ($PLATFORM_ARCH)"
    log_debug "Packaging: $PLATFORM_PACKAGING (deps: $PLATFORM_DEP_PACKAGING)"
    log_debug "Make: $PLATFORM_MAKE, Cores: $PLATFORM_CORES"
}

# Return a short identifier for the current platform (used in config file lookup)
platform_id() {
    printf '%s\n' "$PLATFORM_OS"
}

# --- Internal detection functions ---

_detect_cross_target() {
    # Check if CFBUILD_CROSS_TARGET is set explicitly
    if [ -n "${CFBUILD_CROSS_TARGET:-}" ]; then
        PLATFORM_CROSS_TARGET="$CFBUILD_CROSS_TARGET"
        return
    fi
    # Check for Jenkins-style label
    case "${label:-}${JOB_NAME:-}" in
    *x86_64_mingw* | *x64_mingw* | *x64-mingw*)
        PLATFORM_CROSS_TARGET=x64-mingw
        ;;
    *i386_mingw* | *x86_mingw* | *x86-mingw*)
        PLATFORM_CROSS_TARGET=x86-mingw
        ;;
    esac
}

_detect_cross_platform() {
    case "$PLATFORM_CROSS_TARGET" in
    x64-mingw)
        PLATFORM_KERNEL=MinGW
        PLATFORM_OS=mingw
        PLATFORM_OS_VERSION=""
        PLATFORM_OS_VERSION_MAJOR=""
        PLATFORM_ARCH=x64
        ;;
    x86-mingw)
        PLATFORM_KERNEL=MinGW
        PLATFORM_OS=mingw
        PLATFORM_OS_VERSION=""
        PLATFORM_OS_VERSION_MAJOR=""
        PLATFORM_ARCH=x86
        ;;
    *)
        fatal "Unknown cross target: $PLATFORM_CROSS_TARGET"
        ;;
    esac
}

_detect_kernel() {
    PLATFORM_KERNEL=$(uname -s)
}

_detect_os() {
    case "$PLATFORM_KERNEL" in
    Linux)
        _detect_linux_distro
        ;;
    SunOS)
        PLATFORM_OS=solaris
        PLATFORM_OS_VERSION=$(uname -r | sed 's/^5\.//')
        PLATFORM_OS_VERSION_MAJOR="${PLATFORM_OS_VERSION%%.*}"
        ;;
    AIX)
        PLATFORM_OS=aix
        local _ver
        local _rel
        _ver=$(uname -v)
        _rel=$(uname -r)
        PLATFORM_OS_VERSION="${_ver}.${_rel}"
        PLATFORM_OS_VERSION_MAJOR="$_ver"
        ;;
    HP-UX)
        PLATFORM_OS=hpux
        PLATFORM_OS_VERSION=$(uname -r)
        PLATFORM_OS_VERSION_MAJOR="${PLATFORM_OS_VERSION%%.*}"
        ;;
    FreeBSD)
        PLATFORM_OS=freebsd
        PLATFORM_OS_VERSION=$(uname -r | sed 's/-.*//')
        PLATFORM_OS_VERSION_MAJOR="${PLATFORM_OS_VERSION%%.*}"
        ;;
    Darwin)
        PLATFORM_OS=darwin
        PLATFORM_OS_VERSION=$(sw_vers -productVersion 2>/dev/null || printf 'unknown')
        PLATFORM_OS_VERSION_MAJOR="${PLATFORM_OS_VERSION%%.*}"
        ;;
    *)
        fatal "Unsupported kernel: $PLATFORM_KERNEL"
        ;;
    esac
}

_detect_linux_distro() {
    # Prefer /etc/os-release (systemd standard, available on modern distros)
    if [ -f /etc/os-release ]; then
        local _id
        local _version_id
        _id=$(. /etc/os-release && printf '%s' "$ID")
        _version_id=$(. /etc/os-release && printf '%s' "$VERSION_ID")

        case "$_id" in
        debian)
            PLATFORM_OS=debian
            ;;
        ubuntu)
            PLATFORM_OS=ubuntu
            ;;
        rhel | redhat)
            PLATFORM_OS=rhel
            ;;
        centos)
            PLATFORM_OS=centos
            ;;
        rocky)
            PLATFORM_OS=rocky
            ;;
        sles)
            PLATFORM_OS=sles
            ;;
        opensuse*)
            PLATFORM_OS=opensuse
            ;;
        *)
            PLATFORM_OS="$_id"
            ;;
        esac
        PLATFORM_OS_VERSION="$_version_id"
        PLATFORM_OS_VERSION_MAJOR="${PLATFORM_OS_VERSION%%.*}"
        return
    fi

    # Fallback for older systems without os-release
    if [ -f /etc/debian_version ]; then
        PLATFORM_OS=debian
        PLATFORM_OS_VERSION=$(cat /etc/debian_version)
        PLATFORM_OS_VERSION_MAJOR="${PLATFORM_OS_VERSION%%.*}"
    elif [ -f /etc/redhat-release ]; then
        if grep -qi centos /etc/redhat-release 2>/dev/null; then
            PLATFORM_OS=centos
        elif grep -qi rocky /etc/redhat-release 2>/dev/null; then
            PLATFORM_OS=rocky
        else
            PLATFORM_OS=rhel
        fi
        PLATFORM_OS_VERSION=$(sed 's/.*release \([0-9.]*\).*/\1/' /etc/redhat-release)
        PLATFORM_OS_VERSION_MAJOR="${PLATFORM_OS_VERSION%%.*}"
    elif [ -f /etc/SuSE-release ]; then
        PLATFORM_OS=sles
        PLATFORM_OS_VERSION=$(sed -n 's/^VERSION *= *//p' /etc/SuSE-release)
        PLATFORM_OS_VERSION_MAJOR="${PLATFORM_OS_VERSION%%.*}"
    else
        PLATFORM_OS=linux_unknown
        PLATFORM_OS_VERSION=unknown
        PLATFORM_OS_VERSION_MAJOR=unknown
        log_warn "Could not detect Linux distribution"
    fi
}

_detect_arch() {
    case "$PLATFORM_KERNEL" in
    Linux)
        if command -v dpkg >/dev/null 2>&1; then
            PLATFORM_ARCH=$(dpkg --print-architecture)
        elif command -v rpm >/dev/null 2>&1; then
            PLATFORM_ARCH=$(rpm --eval '%{_arch}')
        else
            PLATFORM_ARCH=$(uname -m)
        fi
        # Normalize
        case "$PLATFORM_ARCH" in
        amd64) PLATFORM_ARCH=x86_64 ;;
        arm64) PLATFORM_ARCH=aarch64 ;;
        esac
        ;;
    SunOS)
        case "$(uname -p)" in
        sparc) PLATFORM_ARCH=sparc64 ;;
        i386 | i86pc) PLATFORM_ARCH=i86pc ;;
        *) PLATFORM_ARCH=$(uname -p) ;;
        esac
        ;;
    AIX)
        PLATFORM_ARCH=ppc64
        ;;
    HP-UX)
        PLATFORM_ARCH=$(uname -m)
        case "$PLATFORM_ARCH" in
        ia64 | 9000/*) ;; # Known architectures
        *) log_warn "Unknown HP-UX arch: $PLATFORM_ARCH" ;;
        esac
        ;;
    FreeBSD)
        PLATFORM_ARCH=$(uname -m)
        ;;
    esac
}

_detect_cores() {
    PLATFORM_CORES=$(compat_nproc)
    PLATFORM_MAKEFLAGS="-j$PLATFORM_CORES"
    export MAKEFLAGS="$PLATFORM_MAKEFLAGS"
}

# Map the detected OS to a platform config file and load it
_load_platform_config() {
    local _config_dir
    _config_dir="$CFBUILD_ROOT/etc/platforms"

    local _config_file
    _config_file="$(_resolve_platform_config_file "$_config_dir")"

    [ -f "$_config_file" ] || fatal "No platform config found for: $PLATFORM_OS (looked for $_config_file)"

    log_debug "Loading platform config: $_config_file"
    config_read "$_config_file"

    # Export platform variables from config
    PLATFORM_MAKE=$(config_get make make)
    PLATFORM_PATCH=$(config_get patch patch)
    PLATFORM_FUSER=$(config_get fuser fuser)
    PLATFORM_CC=$(config_get cc cc)
    PLATFORM_PACKAGING=$(config_get packaging "")
    PLATFORM_DEP_PACKAGING=$(config_get dep_packaging "$PLATFORM_PACKAGING")
    PLATFORM_LDFLAGS=$(config_get ldflags "")
    PLATFORM_CFLAGS=$(config_get cflags "")
    PLATFORM_CPPFLAGS=$(config_get cppflags "")
    PLATFORM_RPATH_FLAG=$(config_get rpath_flag "")
    PLATFORM_HAS_SYSTEMD=$(config_get has_systemd no)
    PLATFORM_HAS_MKTEMP=$(config_get has_mktemp yes)
    PLATFORM_SED_INPLACE=$(config_get sed_inplace no)

    export PLATFORM_MAKE PLATFORM_PATCH PLATFORM_FUSER PLATFORM_CC
    export PLATFORM_PACKAGING PLATFORM_DEP_PACKAGING
    export PLATFORM_LDFLAGS PLATFORM_CFLAGS PLATFORM_CPPFLAGS PLATFORM_RPATH_FLAG
    export PLATFORM_HAS_SYSTEMD PLATFORM_HAS_MKTEMP PLATFORM_SED_INPLACE
    export MAKE="$PLATFORM_MAKE"
}

# Resolve which config file to use based on detected OS
_resolve_platform_config_file() {
    local _dir
    _dir="$1"

    # Try most specific first, fall back to less specific
    # e.g., linux_debian_12.conf → linux_debian.conf → linux.conf
    local _specific
    _specific="${_dir}/${PLATFORM_KERNEL}_${PLATFORM_OS}_${PLATFORM_OS_VERSION_MAJOR}.conf"
    [ -f "$_specific" ] && {
        printf '%s' "$_specific"
        return
    }

    local _os_specific
    _os_specific="${_dir}/${PLATFORM_KERNEL}_${PLATFORM_OS}.conf"
    [ -f "$_os_specific" ] && {
        printf '%s' "$_os_specific"
        return
    }

    local _os_only
    _os_only="${_dir}/${PLATFORM_OS}.conf"
    [ -f "$_os_only" ] && {
        printf '%s' "$_os_only"
        return
    }

    local _kernel_only
    _kernel_only="${_dir}/${PLATFORM_KERNEL}.conf"
    [ -f "$_kernel_only" ] && {
        printf '%s' "$_kernel_only"
        return
    }

    # Return the os_only path so the error message is helpful
    printf '%s' "$_os_only"
}

_setup_path() {
    local _prepend
    _prepend=$(config_get path_prepend "")
    if [ -n "$_prepend" ]; then
        PATH="${_prepend}:$PATH"
        export PATH
    fi
}

_expand_platform_flags() {
    local _prefix
    _prefix="${CFBUILD_PREFIX:-/var/cfengine}"

    # Replace @PREFIX@ placeholders in flags
    PLATFORM_LDFLAGS=$(printf '%s' "$PLATFORM_LDFLAGS" | sed "s|@PREFIX@|${_prefix}|g")
    PLATFORM_CFLAGS=$(printf '%s' "$PLATFORM_CFLAGS" | sed "s|@PREFIX@|${_prefix}|g")
    PLATFORM_CPPFLAGS=$(printf '%s' "$PLATFORM_CPPFLAGS" | sed "s|@PREFIX@|${_prefix}|g")

    export LDFLAGS="$PLATFORM_LDFLAGS"
    export CFLAGS="$PLATFORM_CFLAGS"
    export CPPFLAGS="$PLATFORM_CPPFLAGS"
}

_CFBUILD_PLATFORM_SOURCED=yes
