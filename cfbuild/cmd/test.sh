#!/bin/sh
# cmd/test.sh — Run CFEngine tests
#
# Usage: cfbuild test [--local | --remote=HOST | --chroot]
#
# Modes:
#   --local (default): Run tests on the current machine
#   --remote=HOST:     Transfer and run tests on a remote machine via SSH
#   --chroot:          Run tests in a chroot environment

log_phase_start "test"

_test_mode=local
_test_host=""
_chroot_root="${HOME}/testmachine-chroot"

for _arg in "$@"; do
    case "$_arg" in
    --local) _test_mode=local ;;
    --remote=*)
        _test_mode=remote
        _test_host="${_arg#*=}"
        ;;
    --chroot) _test_mode=chroot ;;
    --chroot-root=*) _chroot_root="${_arg#*=}" ;;
    esac
done

# Skip tests on certain platforms
case "$PLATFORM_OS" in
mingw | freebsd)
    log_warn "Tests not supported on $PLATFORM_OS, skipping"
    log_phase_end
    exit 0
    ;;
esac

if [ "$CFBUILD_TESTS" = no ]; then
    log_info "Tests disabled (--no-tests), skipping"
    log_phase_end
    exit 0
fi

# Determine which projects to test
_test_projects="core masterfiles"
if [ "$CFBUILD_PROJECT" = nova ]; then
    _test_projects="core enterprise masterfiles"
    if [ "$CFBUILD_ROLE" = hub ]; then
        _test_projects="core enterprise nova masterfiles"
    fi
fi

case "$_test_mode" in
local)
    log_info "Running tests locally"
    _dist="$CFBUILD_BASEDIR/cfengine/dist"
    for _proj in $_test_projects; do
        if [ -f "$CFBUILD_BASEDIR/$_proj/Makefile" ]; then
            log_info "Testing: $_proj"
            "$PLATFORM_MAKE" -C "$CFBUILD_BASEDIR/$_proj" check || {
                log_error "Tests failed for: $_proj"
            }
        fi
    done
    ;;
remote)
    log_info "Running tests on remote host: $_test_host"

    # Transfer built artifacts to remote machine
    log_info "Transferring artifacts to $_test_host..."
    _dist="$CFBUILD_BASEDIR/cfengine/dist"
    rsync -avz "$_dist/" "$_test_host:$CFBUILD_PREFIX/" ||
        fatal "Failed to transfer artifacts to $_test_host"

    # Run tests remotely
    for _proj in $_test_projects; do
        if [ -f "$CFBUILD_BASEDIR/$_proj/tests/acceptance/testall" ]; then
            log_info "Running acceptance tests for $_proj on $_test_host"
            # $CFBUILD_PREFIX is intentionally expanded on the client side.
            # shellcheck disable=SC2029
            ssh "$_test_host" "cd $CFBUILD_PREFIX && ./tests/acceptance/testall --printlog" || {
                log_error "Remote tests failed for: $_proj"
            }
        fi
    done
    ;;
chroot)
    log_info "Running tests in chroot: $_chroot_root"

    # Ensure chroot exists
    [ -d "$_chroot_root" ] || fatal "Chroot directory not found: $_chroot_root"

    # Mount necessary filesystems
    _mount_chroot_fs() {
        local _root
        _root="$1"
        if [ ! -d "$_root/proc" ]; then mkdir -p "$_root/proc"; fi

        case "$PLATFORM_KERNEL" in
        Linux)
            sudo mount -t proc proc "$_root/proc" 2>/dev/null || true
            ;;
        AIX)
            sudo mount -v namefs /proc "$_root/proc" 2>/dev/null || true
            ;;
        SunOS)
            sudo mount -F proc proc "$_root/proc" 2>/dev/null || true
            ;;
        esac
    }

    _mount_chroot_fs "$_chroot_root"

    # Copy dist into chroot
    _dist="$CFBUILD_BASEDIR/cfengine/dist"
    sudo rsync -a "$_dist$CFBUILD_PREFIX/" "$_chroot_root$CFBUILD_PREFIX/"

    # Run tests inside chroot
    for _proj in $_test_projects; do
        if [ -f "$CFBUILD_BASEDIR/$_proj/tests/acceptance/testall" ]; then
            log_info "Running acceptance tests for $_proj in chroot"
            sudo chroot "$_chroot_root" "$CFBUILD_PREFIX/tests/acceptance/testall" --printlog || {
                log_error "Chroot tests failed for: $_proj"
            }
        fi
    done

    # Cleanup mounts
    sudo umount "$_chroot_root/proc" 2>/dev/null || true
    ;;
esac

log_phase_end
log_info "Testing complete"
