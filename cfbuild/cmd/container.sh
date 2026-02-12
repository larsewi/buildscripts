#!/bin/sh
# cmd/container.sh — Run a cfbuild command inside a container
#
# Usage: cfbuild [options] container [container-options] <command> [command-args]
#
# Options:
#   --image=IMAGE    Base container image (required, e.g., debian:12)
#   --engine=ENGINE  Force podman or docker (default: auto-detect)
#   --pull           Always pull base image and rebuild
#   --shell          Drop into an interactive shell
#   --network=MODE   Container network mode (e.g., host)
#   --dry-run        Print the run command without executing

# --- Recursion guard ---
if [ "${CFBUILD_IN_CONTAINER:-}" = yes ]; then
    fatal "Already running inside a container. Nested containers are not supported."
fi

# --- Load container library ---
. "$CFBUILD_ROOT/lib/container.sh"

# --- Parse container-specific options ---
_ctr_image=""
_ctr_engine=""
_ctr_pull=no
_ctr_shell=no
_ctr_network=""
_ctr_dry_run=no

while [ $# -gt 0 ]; do
    case "$1" in
    --image=*)
        _ctr_image="${1#*=}"
        shift
        ;;
    --engine=*)
        _ctr_engine="${1#*=}"
        shift
        ;;
    --pull)
        _ctr_pull=yes
        shift
        ;;
    --shell)
        _ctr_shell=yes
        shift
        ;;
    --network=*)
        _ctr_network="${1#*=}"
        shift
        ;;
    --dry-run)
        _ctr_dry_run=yes
        shift
        ;;
    --)
        shift
        break
        ;;
    -*) fatal "Unknown container option: $1" ;;
    *) break ;;
    esac
done

[ -n "$_ctr_image" ] || fatal "Container image is required (use --image=IMAGE)"

# --- Detect container engine ---
ctr_detect_engine "$_ctr_engine"

# --- Determine distro family from image name ---
_ctr_family=""
case "$_ctr_image" in
debian:* | debian/* | ubuntu:* | ubuntu/*)
    _ctr_family=apt
    ;;
rockylinux:* | rockylinux/* | almalinux:* | almalinux/* | \
    centos:* | centos/* | fedora:* | fedora/* | \
    redhat/* | registry.access.redhat.com/ubi*)
    _ctr_family=dnf
    ;;
opensuse/* | suse/* | sles:* | sles/*)
    _ctr_family=zypper
    ;;
*)
    fatal "Cannot determine distro family for image '$_ctr_image'. Supported: debian, ubuntu, rockylinux, almalinux, centos, fedora, UBI, opensuse, suse, sles"
    ;;
esac

log_debug "Distro family: $_ctr_family"

# --- Load distro-family config ---
_ctr_conf="$CFBUILD_ROOT/etc/containers/${_ctr_family}.conf"
config_clear
config_read "$_ctr_conf"

_pkg_update=$(config_get pkg_update)
_pkg_install=$(config_get pkg_install)
_pkg_clean=$(config_get pkg_clean)
_build_prereqs=$(config_get build_prereqs)

# --- Sanitize image name for use as a tag ---
_sanitized_image=$(printf '%s' "$_ctr_image" | sed 's|[:/]|-|g')
_ctr_tag="cfbuild/${_sanitized_image}:latest"

# --- Pull base image if requested ---
if [ "$_ctr_pull" = yes ]; then
    log_info "Pulling base image: $_ctr_image"
    "$CTR_ENGINE_CMD" pull "$_ctr_image"
fi

# --- Build cfbuild-ready image if needed ---
if [ "$_ctr_pull" = yes ] || ! ctr_image_exists "$_ctr_tag"; then
    _ctr_tmpdir="${TMPDIR:-/tmp}/cfbuild-ctr.$$"
    mkdir -p "$_ctr_tmpdir"
    register_cleanup_dir "$_ctr_tmpdir"

    _ctr_containerfile="$_ctr_tmpdir/Containerfile"
    cat >"$_ctr_containerfile" <<EOF
FROM $_ctr_image
RUN $_pkg_update && $_pkg_install $_build_prereqs && $_pkg_clean
RUN echo 'ALL ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/cfbuild
WORKDIR /workspace
EOF

    log_debug "Generated Containerfile:"
    log_debug "$(cat "$_ctr_containerfile")"

    ctr_build_image "$_ctr_tag" "$_ctr_containerfile" "$_ctr_network"
fi

# --- Determine volume mount flags ---
_z=""
if ctr_needs_z_mount; then
    _z=":Z"
fi

# --- UID mapping flags ---
_userns_flag=""
if [ "$CTR_ENGINE" = podman ]; then
    _userns_flag="--userns=keep-id"
else
    _userns_flag="--user=$(id -u):$(id -g)"
fi

# --- Cache directory ---
_cache_dir="${CFBUILD_CACHE_DIR:-$HOME/.cache/cfbuild}"
mkdir -p "$_cache_dir"

# --- Save inner command args before set -- overwrites them ---
# shellcheck disable=SC2086
_inner_args="$*"

# --- Reconstruct global flags to forward ---
_fwd_verbose=""
_fwd_quiet=""
_fwd_no_tests=""
[ "$CFBUILD_VERBOSE" = yes ] && _fwd_verbose="--verbose"
[ "$CFBUILD_QUIET" = yes ] && _fwd_quiet="--quiet"
[ "$CFBUILD_TESTS" = no ] && _fwd_no_tests="--no-tests"

# --- Network flag for run ---
_ctr_net_flag=""
if [ -n "$_ctr_network" ]; then
    _ctr_net_flag="--network=$_ctr_network"
fi

# --- Build the run command ---
if [ "$_ctr_shell" = yes ]; then
    # Interactive shell mode
    set -- \
        "$CTR_ENGINE_CMD" run --rm -it \
        -v "$CFBUILD_BASEDIR:/workspace${_z}" \
        -v "${_cache_dir}:/cache${_z}" \
        -e CFBUILD_IN_CONTAINER=yes \
        -e CFBUILD_CACHE_DIR=/cache \
        -e CFBUILD_HOST_BASEDIR="$CFBUILD_BASEDIR" \
        "$_userns_flag"
    [ -n "$_ctr_net_flag" ] && set -- "$@" "$_ctr_net_flag"
    set -- "$@" "$_ctr_tag" /bin/sh
else
    set -- \
        "$CTR_ENGINE_CMD" run --rm \
        -v "$CFBUILD_BASEDIR:/workspace${_z}" \
        -v "${_cache_dir}:/cache${_z}" \
        -e CFBUILD_IN_CONTAINER=yes \
        -e CFBUILD_CACHE_DIR=/cache \
        -e CFBUILD_HOST_BASEDIR="$CFBUILD_BASEDIR" \
        "$_userns_flag"
    [ -n "$_ctr_net_flag" ] && set -- "$@" "$_ctr_net_flag"
    set -- "$@" \
        "$_ctr_tag" \
        /workspace/buildscripts/cfbuild/cfbuild \
        --project="$CFBUILD_PROJECT" --role="$CFBUILD_ROLE" \
        --type="$CFBUILD_TYPE" --prefix="$CFBUILD_PREFIX"

    # Append optional flags (only if non-empty)
    [ -n "$_fwd_verbose" ] && set -- "$@" "$_fwd_verbose"
    [ -n "$_fwd_quiet" ] && set -- "$@" "$_fwd_quiet"
    [ -n "$_fwd_no_tests" ] && set -- "$@" "$_fwd_no_tests"

    # Append the inner command and its arguments
    # shellcheck disable=SC2086
    set -- "$@" $_inner_args
fi

# --- Execute or print ---
if [ "$_ctr_dry_run" = yes ]; then
    log_info "Dry run — would execute:"
    printf '%s\n' "$*"
    exit 0
fi

log_info "Running inside container: $_ctr_tag"
log_debug "Command: $*"
exec "$@"
