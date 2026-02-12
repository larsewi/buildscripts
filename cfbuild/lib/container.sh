#!/bin/sh
# lib/container.sh — Container runtime detection and helpers
#
# Dependencies: lib/log.sh, lib/error.sh
# Provides: ctr_detect_engine, ctr_image_exists, ctr_build_image,
#           ctr_needs_z_mount

if [ "$_CFBUILD_CONTAINER_SOURCED" = yes ]; then
    return 0 2>/dev/null || exit 0
fi

: "${_CFBUILD_LOG_SOURCED:?lib/log.sh must be sourced before lib/container.sh}"
: "${_CFBUILD_ERROR_SOURCED:?lib/error.sh must be sourced before lib/container.sh}"

# Container engine name (podman or docker) and full command path
CTR_ENGINE=""
CTR_ENGINE_CMD=""

# Detect a container engine (prefer podman, fall back to docker).
# Optionally pass a name to force a specific engine.
ctr_detect_engine() {
    local _force
    _force="${1:-}"

    if [ -n "$_force" ]; then
        CTR_ENGINE_CMD=$(command -v "$_force" 2>/dev/null) ||
            fatal "Requested container engine '$_force' not found in PATH"
        CTR_ENGINE="$_force"
        log_debug "Container engine (forced): $CTR_ENGINE ($CTR_ENGINE_CMD)"
        return 0
    fi

    # Auto-detect: prefer podman
    local _eng
    for _eng in podman docker; do
        CTR_ENGINE_CMD=$(command -v "$_eng" 2>/dev/null) && {
            CTR_ENGINE="$_eng"
            log_debug "Container engine (auto): $CTR_ENGINE ($CTR_ENGINE_CMD)"
            return 0
        }
    done

    fatal "No container engine found. Install podman or docker."
}

# Check whether a container image exists locally.
# Returns 0 if the image exists, 1 otherwise.
ctr_image_exists() {
    local _tag
    _tag="$1"
    "$CTR_ENGINE_CMD" image inspect "$_tag" >/dev/null 2>&1
}

# Build a container image from a Containerfile.
# Arguments: tag, containerfile_path [, network_mode]
ctr_build_image() {
    local _tag _containerfile _network
    _tag="$1"
    _containerfile="$2"
    _network="${3:-}"

    log_info "Building container image: $_tag"
    if [ -n "$_network" ]; then
        "$CTR_ENGINE_CMD" build --network="$_network" \
            -t "$_tag" -f "$_containerfile" \
            "$(dirname "$_containerfile")"
    else
        "$CTR_ENGINE_CMD" build -t "$_tag" -f "$_containerfile" \
            "$(dirname "$_containerfile")"
    fi
}

# Return 0 if SELinux is enforcing or permissive (need :Z volume flag).
ctr_needs_z_mount() {
    # getenforce is only available on SELinux-capable systems
    local _mode
    _mode=$(getenforce 2>/dev/null) || return 1
    case "$_mode" in
    Enforcing | Permissive) return 0 ;;
    *) return 1 ;;
    esac
}

_CFBUILD_CONTAINER_SOURCED=yes
