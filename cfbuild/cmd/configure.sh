#!/bin/sh
# cmd/configure.sh — Run autogen and configure on CFEngine repositories
#
# Usage: cfbuild configure
#
# Runs autogen.sh (if present) and ./configure with appropriate flags
# on core, enterprise, nova, and masterfiles repositories.

. "$CFBUILD_ROOT/lib/deps.sh"

log_phase_start "configure"

# Determine which repos to build
_repos="core masterfiles"
_nova=no
if [ "$CFBUILD_PROJECT" = nova ]; then
    _nova=yes
    _repos="core enterprise masterfiles"
    if [ "$CFBUILD_ROLE" = hub ]; then
        _repos="core enterprise nova masterfiles"
    fi
fi

# Verify repos exist
for _repo in $_repos; do
    if [ ! -d "$CFBUILD_BASEDIR/$_repo" ]; then
        fatal "Repository not found: $CFBUILD_BASEDIR/$_repo"
    fi
done

# --- Step 1: Run autogen.sh on each repo ---

for _repo in $_repos; do
    if [ -f "$CFBUILD_BASEDIR/$_repo/autogen.sh" ]; then
        log_info "Running autogen.sh for $_repo"
        (cd "$CFBUILD_BASEDIR/$_repo" && NO_CONFIGURE=1 run_quiet ./autogen.sh)
    fi
done

# --- Step 2: Build configure arguments ---

_P="$CFBUILD_PREFIX"
_ARGS="--prefix=$_P --libdir=$_P/lib --with-workdir=$_P --sysconfdir=/etc"
_ARGS="$_ARGS --with-openssl=$_P --with-pcre2=$_P --with-librsync=$_P"
_ARGS="$_ARGS --with-init-script --with-lmdb=$_P"

# Resolve dependency list for --with/--without flags
_dep_list=$(dep_resolve_list)

# Optional deps: enable if in dep list, disable otherwise
# Note: "ldap" requires special handling because the dependency is called
# "openldap" but the configure flag is --with-ldap.
for _dep in ldap libxml2 libyaml librsync leech libacl libvirt libcurl; do
    case "$_dep" in
    ldap)
        case "$_dep_list" in
        *openldap*) _ARGS="$_ARGS --with-ldap=$_P" ;;
        *) _ARGS="$_ARGS --without-ldap" ;;
        esac
        ;;
    *)
        case "$_dep_list" in
        *"$_dep"*)
            _ARGS="$_ARGS --with-$_dep=$_P"
            ;;
        *)
            _ARGS="$_ARGS --without-$_dep"
            ;;
        esac
        ;;
    esac
done

# pthreads for MinGW
case "$_dep_list" in
*pthreads-w32*)
    _ARGS="$_ARGS --with-pthreads=$_P"
    ;;
esac

# PostgreSQL
case "$_dep_list" in
*postgresql*)
    _ARGS="$_ARGS --with-postgresql=$_P --without-mysql"
    ;;
*)
    _ARGS="$_ARGS --without-sql"
    ;;
esac

# Role-specific flags
case "$CFBUILD_ROLE" in
hub)
    _ARGS="$_ARGS --with-cfmod --with-enterprise-api --with-postgresql=$_P"
    ;;
agent)
    _ARGS="$_ARGS --without-cfmod --without-postgresql"
    ;;
esac

# systemd
if [ "$PLATFORM_HAS_SYSTEMD" = yes ]; then
    _ARGS="$_ARGS --with-systemd-service"
else
    _ARGS="$_ARGS --without-systemd-service"
fi

# SELinux policy for RHEL 8+
case "$PLATFORM_OS" in
rhel | centos | rocky)
    if [ "$PLATFORM_OS_VERSION_MAJOR" -ge 8 ] 2>/dev/null; then
        _ARGS="$_ARGS --with-selinux-policy"
    fi
    ;;
esac

# Cross-compilation host
case "$PLATFORM_CROSS_TARGET" in
x86-mingw) _ARGS="$_ARGS --host=i686-w64-mingw32" ;;
x64-mingw) _ARGS="$_ARGS --host=x86_64-w64-mingw32" ;;
esac

# Build type flags
_CFLAGS="$PLATFORM_CFLAGS"
case "$CFBUILD_TYPE" in
release)
    _CFLAGS="-g2 -O2 -DNDEBUG $_CFLAGS"
    ;;
debug)
    _ARGS="$_ARGS --enable-debug"
    _CFLAGS="-g2 -O1 $_CFLAGS"
    ;;
esac

# Solaris PKG_CONFIG_PATH override
if [ "$PLATFORM_OS" = solaris ]; then
    export PKG_CONFIG_PATH="$CFBUILD_PREFIX/lib/pkgconfig"
fi

# --- Step 3: Run ./configure on each repo ---

for _repo in $_repos; do
    # Skip nova for agents, masterfiles doesn't need separate configure in some cases
    case "$_repo" in
    nova)
        [ "$CFBUILD_ROLE" = hub ] || continue
        ;;
    esac

    if [ -f "$CFBUILD_BASEDIR/$_repo/configure" ]; then
        log_info "Running configure for $_repo"
        # $_ARGS is intentionally unquoted to split into multiple configure arguments.
        # shellcheck disable=SC2086
        (cd "$CFBUILD_BASEDIR/$_repo" &&
            run_quiet env CFLAGS="$_CFLAGS" ./configure $_ARGS)
    fi
done

log_phase_end
