#!/bin/sh
# lib/deps.sh — Dependency resolution and build helpers
#
# Dependencies: lib/config.sh, lib/platform.sh, lib/compat.sh, lib/log.sh, lib/error.sh
# Provides: dep_resolve_list, dep_build, dep_build_generic, dep_fetch_source,
#           dep_unpack_source, dep_apply_patches, dep_install_staging,
#           dep_autoconf_configure, dep_split_packages

if [ "$_CFBUILD_DEPS_SOURCED" = yes ]; then
    return 0 2>/dev/null || exit 0
fi

: "${_CFBUILD_CONFIG_SOURCED:?lib/config.sh must be sourced before lib/deps.sh}"
: "${_CFBUILD_PLATFORM_SOURCED:?lib/platform.sh must be sourced before lib/deps.sh}"

# Bump this when build logic changes in ways not captured by the per-dep
# fingerprint fields (configure_flags, build_type, patches, env vars, etc.).
# Examples: changing dep_build_generic, make flags, install logic.
# Do NOT bump for changes to stamp/caching helpers or new utility functions.
_DEPS_INFRA_VERSION=1

# Resolve the list of dependencies to build for the current project/role/platform.
# Reads etc/deps/*.conf files and filters by role and platform.
# Prints space-separated list of dep names in build order.
dep_resolve_list() {
    local _deps_dir
    _deps_dir="$CFBUILD_ROOT/etc/deps"
    local _os_family
    _os_family=$(config_get os_family "linux")
    local _result
    _result=""

    # Platform-specific deps first (order matters for linking)
    local _extra
    _extra=$(config_get extra_deps "")
    if [ -n "$_extra" ]; then
        _result="$_extra"
    fi

    # System SSL detection: skip zlib+openssl on RHEL 8+, SLES/openSUSE 15+
    local _system_ssl
    _system_ssl=no
    case "$PLATFORM_OS" in
    rhel | centos | rocky)
        if [ "$PLATFORM_OS_VERSION_MAJOR" -ge 8 ] 2>/dev/null; then
            _system_ssl=yes
        fi
        ;;
    opensuse | sles)
        if [ "$PLATFORM_OS_VERSION_MAJOR" -ge 15 ] 2>/dev/null; then
            _system_ssl=yes
        fi
        ;;
    esac
    export CFBUILD_SYSTEM_SSL="$_system_ssl"

    if [ "$_system_ssl" != yes ]; then
        _result="$_result zlib openssl"
    fi

    # SASL for solaris/hpux
    case "$_os_family" in
    solaris | hpux)
        _result="$_result sasl2"
        ;;
    esac

    # Common deps (all platforms)
    _result="$_result lmdb pcre2 libxml2 libyaml diffutils librsync"

    # Enterprise deps
    if [ "$CFBUILD_PROJECT" = nova ]; then
        _result="$_result openldap leech"
    fi

    # Non-exotic Linux deps
    case "$_os_family" in
    hpux | aix | solaris | freebsd | mingw) ;;
    *)
        _result="$_result libattr libacl"
        ;;
    esac

    # Role-specific deps
    case "$CFBUILD_ROLE" in
    hub)
        _result="$_result libcurl-hub nghttp2 libexpat apr apr-util apache git rsync postgresql php"
        ;;
    agent)
        _result="$_result libcurl"
        ;;
    esac

    # Trim leading whitespace and normalize spaces
    printf '%s' "$_result" | sed 's/^[[:space:]]*//;s/[[:space:]]\{1,\}/ /g'
}

# Keepalive: prints a dot every 60s to prevent remote session timeouts.
_DEP_KEEPALIVE_PID=""
_DEP_KEEPALIVE_START=""

_dep_keepalive_start() {
    _DEP_KEEPALIVE_START=$(date +%s 2>/dev/null || echo 0)
    (while true; do
        sleep 60
        printf '.'
    done) &
    _DEP_KEEPALIVE_PID=$!
}

_dep_keepalive_stop() {
    if [ -n "$_DEP_KEEPALIVE_PID" ]; then
        kill "$_DEP_KEEPALIVE_PID" 2>/dev/null || true
        wait "$_DEP_KEEPALIVE_PID" 2>/dev/null || true
        # Print newline only if at least one dot was printed (60s elapsed)
        local _now
        _now=$(date +%s 2>/dev/null || echo 0)
        if [ "$((_now - _DEP_KEEPALIVE_START))" -ge 60 ] 2>/dev/null; then
            printf '\n'
        fi
        _DEP_KEEPALIVE_PID=""
        _DEP_KEEPALIVE_START=""
    fi
}

# Build a single dependency.
# Usage: dep_build <dep_name>
dep_build() {
    local _name
    _name="$1"
    local _conf
    _conf="$CFBUILD_ROOT/etc/deps/${_name}.conf"

    if [ ! -f "$_conf" ]; then
        fatal "No config for dependency: $_name (expected $_conf)"
    fi

    # Clear previous dep config and load new one
    config_clear
    config_read "$_conf"

    # Check if this dep is already up to date
    if [ "$CFBUILD_FORCE_DEPS" != yes ] && _dep_stamp_check "$_name"; then
        log_info "Up to date, skipping"
        return 0
    fi

    # Fast path: stamp fingerprint matches but install marker is missing
    # (e.g., fresh container where the prefix is empty but the build dirs
    # on the mounted volume still have valid staging output).
    # Re-install from staging instead of doing a full rebuild.
    if [ "$CFBUILD_FORCE_DEPS" != yes ] && _dep_stamp_fingerprint_matches "$_name"; then
        local _staging
        _staging="$CFBUILD_BASEDIR/$_name/staging"
        if [ -d "$_staging" ]; then
            log_info "Reinstalling from staging (fingerprint match)"
            dep_install_staging "$_name"
            return 0
        fi
    fi

    _dep_keepalive_start

    local _build_type
    _build_type=$(config_get build_type autoconf)

    case "$_build_type" in
    custom)
        local _script
        _script=$(config_get build_script "")
        if [ -z "$_script" ]; then
            _dep_keepalive_stop
            fatal "Dependency $_name has build_type=custom but no build_script"
        fi
        local _script_path
        _script_path="$CFBUILD_ROOT/deps/$_script"
        if [ ! -f "$_script_path" ]; then
            _dep_keepalive_stop
            fatal "Custom build script not found: $_script_path"
        fi
        # Custom build script path is resolved at runtime from dep config.
        # shellcheck disable=SC1090
        . "$_script_path"
        ;;
    autoconf | cmake)
        dep_build_generic "$_name" "$_build_type"
        ;;
    *)
        _dep_keepalive_stop
        fatal "Unknown build_type '$_build_type' for dependency $_name"
        ;;
    esac

    # Install staged files to the prefix so subsequent deps can find them
    dep_install_staging "$_name"

    # Write stamp file so subsequent runs can skip this dep
    _dep_stamp_write "$_name"

    _dep_keepalive_stop
}

# Generic build template for autoconf/cmake dependencies.
dep_build_generic() {
    local _name
    local _build_system
    _name="$1"
    _build_system="$2"

    local _version
    _version=$(config_get version "")
    local _source
    _source=$(config_get source "")
    local _source_dir
    _source_dir=$(config_get source_dir "${_name}-${_version}")

    local _build_dir
    _build_dir="$CFBUILD_BASEDIR/$_name"
    mkdir -p "$_build_dir"
    cd "$_build_dir" || return 1

    # Unpack source (remove previous to ensure patches apply cleanly on rebuild)
    if [ -n "$_source" ]; then
        rm -rf "$_source_dir"
        dep_unpack_source "$_name" "$_source"
        cd "$_source_dir" 2>/dev/null || cd "$_name"* 2>/dev/null || true
    fi

    # Apply patches
    dep_apply_patches "$_name"

    # Configure
    local _prefix
    _prefix="${CFBUILD_PREFIX}"
    local _configure_flags
    _configure_flags=$(config_get configure_flags "" | sed "s|@PREFIX@|${_prefix}|g")

    case "$_build_system" in
    autoconf)
        log_debug "Running ./configure for $_name"
        if [ -f ./configure ]; then
            # LDFLAGS/CFLAGS are already exported by platform.sh, so they
            # are picked up by configure automatically. Passing them as
            # arguments breaks non-autoconf configure scripts (e.g. zlib).
            # $_configure_flags is intentionally unquoted to split into multiple arguments.
            # shellcheck disable=SC2086
            run_quiet ./configure \
                --prefix="$_prefix" \
                $_configure_flags
        elif [ -f ./config ]; then
            # $_configure_flags is intentionally unquoted to split into multiple arguments.
            # shellcheck disable=SC2086
            run_quiet ./config \
                --prefix="$_prefix" \
                $_configure_flags
        fi
        ;;
    cmake)
        log_debug "Running cmake for $_name"
        mkdir -p build && cd build || return 1
        # $_configure_flags is intentionally unquoted to split into multiple arguments.
        # shellcheck disable=SC2086
        run_quiet cmake .. \
            -DCMAKE_INSTALL_PREFIX="$_prefix" \
            -DCMAKE_C_FLAGS="$PLATFORM_CFLAGS" \
            $_configure_flags
        ;;
    esac

    # Build
    local _make_flags
    _make_flags=$(config_get make_flags "")
    log_debug "Running make for $_name"
    # $_make_flags is intentionally unquoted to split into multiple arguments.
    # shellcheck disable=SC2086
    run_quiet "$PLATFORM_MAKE" "$PLATFORM_MAKEFLAGS" $_make_flags

    # Test (if enabled and not skipped)
    local _tests
    _tests=$(config_get tests "$CFBUILD_TESTS")
    if [ "$_tests" = yes ]; then
        log_debug "Running tests for $_name"
        run_quiet "$PLATFORM_MAKE" test 2>/dev/null || run_quiet "$PLATFORM_MAKE" check 2>/dev/null || true
    fi

    # Install to staging directory
    local _staging
    _staging="$_build_dir/staging"
    mkdir -p "$_staging"
    log_debug "Installing $_name to staging dir"
    run_quiet "$PLATFORM_MAKE" DESTDIR="$_staging" install
}

# Copy staged dependency files to the actual prefix so that subsequent
# dependencies can find headers and libraries during their builds.
# Scans all staging subdirectories for the prefix path and copies contents.
# Usage: dep_install_staging <dep_name>
dep_install_staging() {
    local _name
    _name="$1"
    local _build_dir
    _build_dir="$CFBUILD_BASEDIR/$_name"
    local _staging
    _staging="$_build_dir/staging"

    if [ ! -d "$_staging" ]; then
        log_debug "No staging directory for $_name, skipping install"
        return 0
    fi

    # Create prefix if needed (writable by the build user)
    if [ ! -d "$CFBUILD_PREFIX" ]; then
        sudo mkdir -p "$CFBUILD_PREFIX"
        sudo chown "$(id -u):$(id -g)" "$CFBUILD_PREFIX"
    fi

    # Staging layout: DESTDIR creates <staging><prefix>/... directly.
    # Some packaging tools add a subdir: <staging>/<subdir><prefix>/...
    # Try the direct path first, then one and two levels of subdirectory.
    local _found
    _found=no

    # Direct DESTDIR layout: staging/var/cfengine/...
    if [ -d "$_staging${CFBUILD_PREFIX}" ]; then
        log_debug "Installing $_name from $_staging${CFBUILD_PREFIX} to $CFBUILD_PREFIX"
        cp -a "$_staging${CFBUILD_PREFIX}"/. "$CFBUILD_PREFIX"/
        _found=yes
    fi

    # One level deep (e.g. staging/cfbuild-openssl/var/cfengine)
    if [ "$_found" = no ]; then
        for _dir in "$_staging"/*"${CFBUILD_PREFIX}"; do
            if [ -d "$_dir" ]; then
                log_debug "Installing $_name from $_dir to $CFBUILD_PREFIX"
                cp -a "$_dir"/. "$CFBUILD_PREFIX"/
                _found=yes
            fi
        done
    fi

    # Two levels deep (e.g. staging/cfbuild-openssl-devel/sub/var/cfengine)
    if [ "$_found" = no ]; then
        for _dir in "$_staging"/*/*"${CFBUILD_PREFIX}"; do
            if [ -d "$_dir" ]; then
                log_debug "Installing $_name from $_dir to $CFBUILD_PREFIX"
                cp -a "$_dir"/. "$CFBUILD_PREFIX"/
                _found=yes
            fi
        done
    fi

    if [ "$_found" = no ]; then
        fatal "No prefix directory found in staging for $_name (expected ${CFBUILD_PREFIX} under $_staging)"
    fi

    # Write a per-dep marker so _dep_stamp_check can verify this
    # specific dependency's files are installed in the prefix.
    mkdir -p "$CFBUILD_PREFIX/.cfbuild_installed"
    : >"$CFBUILD_PREFIX/.cfbuild_installed/$_name"
}

# Local cache directory for downloaded source tarballs.
_CFBUILD_CACHE_DIR="${CFBUILD_CACHE_DIR:-${HOME}/.cache/cfbuild/sources}"

# Download a source tarball if not already present.
# Reads URL from deps-packaging/<name>/source and checksum from distfiles.
# Stores downloaded file in the local cache directory.
# Sets DEP_FETCH_RESULT to the path of the cached file on success.
# Usage: dep_fetch_source <dep_name> <tarball_filename>
dep_fetch_source() {
    local _name
    local _tarball
    _name="$1"
    _tarball="$2"

    DEP_FETCH_RESULT=""

    local _pkg_dir
    _pkg_dir="$CFBUILD_BASEDIR/buildscripts/deps-packaging/$_name"

    # Read download URLs from the source file
    local _source_file
    _source_file="$_pkg_dir/source"
    if [ ! -f "$_source_file" ]; then
        fatal "No source URL file for dependency: $_name (expected $_source_file)"
    fi
    local _urls
    _urls=$(cat "$_source_file")

    # Read expected checksum from distfiles
    local _distfile
    _distfile="$_pkg_dir/distfiles"
    local _expected_checksum
    _expected_checksum=""
    if [ -f "$_distfile" ]; then
        # Format: <sha256>  <filename> [options]
        _expected_checksum=$(awk '{print $1}' "$_distfile")
    fi

    # Check cache first
    mkdir -p "$_CFBUILD_CACHE_DIR"
    local _cached
    _cached="$_CFBUILD_CACHE_DIR/$_tarball"
    if [ -f "$_cached" ]; then
        if [ -n "$_expected_checksum" ]; then
            local _actual
            _actual=$(compat_sha256 "$_cached")
            if [ "$_actual" = "$_expected_checksum" ]; then
                log_debug "Using cached source: $_cached"
                DEP_FETCH_RESULT="$_cached"
                return 0
            fi
            log_warn "Cached file has wrong checksum, re-downloading: $_tarball"
            rm -f "$_cached"
        else
            log_debug "Using cached source (no checksum to verify): $_cached"
            DEP_FETCH_RESULT="$_cached"
            return 0
        fi
    fi

    # Download from each URL until one succeeds
    local _wget
    _wget=$(command -v wget 2>/dev/null || true)
    local _curl
    _curl=$(command -v curl 2>/dev/null || true)

    local _tmp
    _tmp="${_cached}.tmp.$$"

    local _url
    for _url in $_urls; do
        log_info "Downloading $_tarball from ${_url}..."

        # Try wget first
        if [ -n "$_wget" ]; then
            "$_wget" --no-check-certificate -t5 "${_url}${_tarball}" -O "$_tmp" >/dev/null 2>&1 || true
            # wget sometimes leaves an empty file on failure
            if [ -f "$_tmp" ] && [ ! -s "$_tmp" ]; then
                rm -f "$_tmp"
            fi
        fi

        # Try curl as fallback
        if [ ! -f "$_tmp" ] && [ -n "$_curl" ]; then
            "$_curl" -fsSL "${_url}${_tarball}" -o "$_tmp" 2>/dev/null || true
            if [ -f "$_tmp" ] && [ ! -s "$_tmp" ]; then
                rm -f "$_tmp"
            fi
        fi

        if [ -f "$_tmp" ]; then
            # Verify checksum if available
            if [ -n "$_expected_checksum" ]; then
                local _actual
                _actual=$(compat_sha256 "$_tmp")
                if [ "$_actual" != "$_expected_checksum" ]; then
                    log_warn "Downloaded $_tarball has wrong checksum (expected $_expected_checksum, got $_actual)"
                    rm -f "$_tmp"
                    continue
                fi
            fi

            mv "$_tmp" "$_cached"
            log_info "Downloaded and cached: $_tarball"
            DEP_FETCH_RESULT="$_cached"
            return 0
        fi
    done

    rm -f "$_tmp"
    fatal "Failed to download $_tarball from any source URL"
}

# Unpack a source tarball.
# Usage: dep_unpack_source <dep_name> <tarball_filename>
dep_unpack_source() {
    local _name
    local _tarball
    _name="$1"
    _tarball="$2"

    # Look for the source in deps-packaging/<name>/source/ or distfiles/
    local _source_path
    _source_path=""
    for _dir in \
        "$CFBUILD_BASEDIR/buildscripts/deps-packaging/$_name/source" \
        "$CFBUILD_BASEDIR/buildscripts/deps-packaging/$_name/distfiles" \
        "$CFBUILD_BASEDIR/buildscripts/deps-packaging/$_name" \
        "$_CFBUILD_CACHE_DIR"; do
        if [ -f "$_dir/$_tarball" ]; then
            _source_path="$_dir/$_tarball"
            break
        fi
    done

    # If not found locally, download it
    if [ -z "$_source_path" ]; then
        dep_fetch_source "$_name" "$_tarball"
        _source_path="$DEP_FETCH_RESULT"
    fi

    log_debug "Unpacking: $_source_path"
    compat_decompress "$_source_path"
}

# Apply patches for a dependency, selecting platform-specific patches.
# Usage: dep_apply_patches <dep_name>
dep_apply_patches() {
    local _name
    _name="$1"

    local _os_family
    _os_family=$(config_get os_family "linux")

    # Check for platform-specific patches first
    local _patches
    _patches=$(config_get "patches_${PLATFORM_OS}" "")
    if [ -z "$_patches" ]; then
        _patches=$(config_get "patches_${_os_family}" "")
    fi
    if [ -z "$_patches" ]; then
        _patches=$(config_get patches "")
    fi

    if [ -z "$_patches" ]; then
        return 0
    fi

    local _patch_dir
    _patch_dir="$CFBUILD_BASEDIR/buildscripts/deps-packaging/$_name"

    local _p
    for _p in $_patches; do
        local _patch_file
        _patch_file=""
        for _dir in "$_patch_dir" "$_patch_dir/source" "$_patch_dir/distfiles"; do
            if [ -f "$_dir/$_p" ]; then
                _patch_file="$_dir/$_p"
                break
            fi
        done

        if [ -z "$_patch_file" ]; then
            log_warn "Patch not found: $_p for $_name"
            continue
        fi

        log_debug "Applying patch: $_p"
        # Auto-detect strip level: try -p1 first, fall back to -p0
        if "$PLATFORM_PATCH" --dry-run -p1 <"$_patch_file" >/dev/null 2>&1; then
            run_quiet "$PLATFORM_PATCH" -p1 <"$_patch_file"
        elif "$PLATFORM_PATCH" --dry-run -p0 <"$_patch_file" >/dev/null 2>&1; then
            run_quiet "$PLATFORM_PATCH" -p0 <"$_patch_file"
        else
            fatal "Cannot apply patch $_p (tried -p1 and -p0)"
        fi
    done
}

# Check if Perl meets minimum version requirements (for OpenSSL builds).
# Returns 0 if ok, 1 if too old.
dep_check_perl() {
    local _perl
    _perl="${PERL:-$(command -v perl 2>/dev/null || true)}"

    if [ -z "$_perl" ]; then
        return 1
    fi

    # Require Perl >= 5.13.4 (needed by OpenSSL 1.1+)
    local _minor
    _minor=$("$_perl" -e 'print "$]"."\n"' | cut -d. -f2)
    if [ "$_minor" -lt 013004 ] 2>/dev/null; then
        return 1
    fi

    # Check for List::Util with pairs support (needed by OpenSSL 3.3.2+)
    if ! "$_perl" -e 'use List::Util qw(pairs);' 2>/dev/null; then
        return 1
    fi

    PERL="$_perl"
    export PERL
    return 0
}

# --- Stamp-based dependency rebuild skipping ---

# Return the path to the stamp file for a dependency.
_dep_stamp_path() {
    printf '%s' "$CFBUILD_BASEDIR/$1/.cfbuild_stamp"
}

# Compute a SHA-256 fingerprint of all inputs that affect the build output.
_dep_fingerprint() {
    local _name
    _name="$1"

    local _tmp
    _tmp=$(compat_mktemp)
    register_cleanup_file "$_tmp"

    # Dep config fields
    local _configure_flags
    _configure_flags=$(config_get configure_flags "" | sed "s|@PREFIX@|${CFBUILD_PREFIX}|g")
    {
        printf 'name=%s\n' "$(config_get name "")"
        printf 'version=%s\n' "$(config_get version "")"
        printf 'configure_flags=%s\n' "$_configure_flags"
        printf 'build_type=%s\n' "$(config_get build_type "autoconf")"
        printf 'make_flags=%s\n' "$(config_get make_flags "")"
        printf 'build_script=%s\n' "$(config_get build_script "")"
    } >>"$_tmp"

    # Patches: resolve using the same logic as dep_apply_patches
    local _os_family
    _os_family=$(config_get os_family "linux")
    local _patches
    _patches=$(config_get "patches_${PLATFORM_OS}" "")
    if [ -z "$_patches" ]; then
        _patches=$(config_get "patches_${_os_family}" "")
    fi
    if [ -z "$_patches" ]; then
        _patches=$(config_get patches "")
    fi
    printf 'patches=%s\n' "$_patches" >>"$_tmp"

    # Hash each patch file
    if [ -n "$_patches" ]; then
        local _patch_dir
        _patch_dir="$CFBUILD_BASEDIR/buildscripts/deps-packaging/$_name"
        local _p
        for _p in $_patches; do
            local _patch_file
            _patch_file=""
            local _d
            for _d in "$_patch_dir" "$_patch_dir/source" "$_patch_dir/distfiles"; do
                if [ -f "$_d/$_p" ]; then
                    _patch_file="$_d/$_p"
                    break
                fi
            done
            if [ -n "$_patch_file" ]; then
                printf 'patch_%s=%s\n' "$_p" "$(compat_sha256 "$_patch_file")" >>"$_tmp"
            fi
        done
    fi

    # Hash custom build script
    local _build_script
    _build_script=$(config_get build_script "")
    if [ -n "$_build_script" ]; then
        local _script_path
        _script_path="$CFBUILD_ROOT/deps/$_build_script"
        if [ -f "$_script_path" ]; then
            printf 'build_script_hash=%s\n' "$(compat_sha256 "$_script_path")" >>"$_tmp"
        fi
    fi

    # Environment variables
    {
        printf 'CFBUILD_TYPE=%s\n' "$CFBUILD_TYPE"
        printf 'CFBUILD_PREFIX=%s\n' "$CFBUILD_PREFIX"
        printf 'CFBUILD_TESTS=%s\n' "$CFBUILD_TESTS"
        printf 'CFBUILD_PROJECT=%s\n' "$CFBUILD_PROJECT"
        printf 'CFBUILD_ROLE=%s\n' "$CFBUILD_ROLE"
        printf 'PLATFORM_OS=%s\n' "$PLATFORM_OS"
        printf 'PLATFORM_ARCH=%s\n' "$PLATFORM_ARCH"
        printf 'PLATFORM_OS_VERSION_MAJOR=%s\n' "$PLATFORM_OS_VERSION_MAJOR"
        printf 'CFBUILD_CROSS_TARGET=%s\n' "$CFBUILD_CROSS_TARGET"
        printf 'PLATFORM_CFLAGS=%s\n' "$PLATFORM_CFLAGS"
        printf 'PLATFORM_LDFLAGS=%s\n' "$PLATFORM_LDFLAGS"
    } >>"$_tmp"

    # Infrastructure version — bump this when build logic in deps.sh changes
    # in ways not captured by the fields above (e.g., changing the generic
    # build template, make flags, install logic).  DO NOT bump for changes
    # that only add new helper functions or modify stamp/caching logic.
    printf 'deps_infra_version=%s\n' "$_DEPS_INFRA_VERSION" >>"$_tmp"

    compat_sha256 "$_tmp"
    rm -f "$_tmp"
}

# Check if a dependency is up to date (stamp exists, prefix exists, fingerprint matches).
# Returns 0 if up to date, 1 otherwise.
_dep_stamp_check() {
    local _name
    _name="$1"
    local _stamp
    _stamp=$(_dep_stamp_path "$_name")

    # Stamp file must exist
    [ -f "$_stamp" ] || return 1

    # Per-dep install marker must exist inside the prefix.
    # Clean removes the prefix (and markers), and fresh containers
    # start without a prefix, so this correctly forces a rebuild.
    [ -f "$CFBUILD_PREFIX/.cfbuild_installed/$_name" ] || return 1

    # Fingerprint must match
    local _stored
    _stored=$(cat "$_stamp")
    local _current
    _current=$(_dep_fingerprint "$_name")

    [ "$_stored" = "$_current" ]
}

# Check if a dependency's stamp fingerprint matches (ignoring install markers).
# Used for the fast-path: when the prefix was wiped (e.g., fresh container)
# but the build output in the staging directory is still valid.
# Returns 0 if the stamp exists and the fingerprint matches, 1 otherwise.
_dep_stamp_fingerprint_matches() {
    local _name
    _name="$1"
    local _stamp
    _stamp=$(_dep_stamp_path "$_name")

    # Stamp file must exist
    [ -f "$_stamp" ] || return 1

    # Fingerprint must match
    local _stored
    _stored=$(cat "$_stamp")
    local _current
    _current=$(_dep_fingerprint "$_name")

    [ "$_stored" = "$_current" ]
}

# Write the current fingerprint to the stamp file.
_dep_stamp_write() {
    local _name
    _name="$1"
    local _stamp
    _stamp=$(_dep_stamp_path "$_name")
    local _stamp_dir
    _stamp_dir=$(dirname "$_stamp")

    mkdir -p "$_stamp_dir"
    _dep_fingerprint "$_name" >"$_stamp"
}

_CFBUILD_DEPS_SOURCED=yes
