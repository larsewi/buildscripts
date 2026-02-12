#!/bin/sh
# lib/pkg.sh — Package management abstraction
#
# Dependencies: lib/platform.sh, lib/log.sh, lib/error.sh
# Provides: pkg_install, pkg_query, pkg_remove, pkg_uninstall_cfbuild,
#           pkg_uninstall_cfbuild_devel

if [ "$_CFBUILD_PKG_SOURCED" = yes ]; then
    return 0 2>/dev/null || exit 0
fi

: "${_CFBUILD_PLATFORM_SOURCED:?lib/platform.sh must be sourced before lib/pkg.sh}"

# --- Public API (dispatch by PLATFORM_PACKAGING) ---

# Install package file(s)
pkg_install() {
    log_debug "Installing package: $*"
    "_pkg_install_${PLATFORM_DEP_PACKAGING}" "$@"
}

# Query if a package is installed (returns 0 if yes)
pkg_query() {
    "_pkg_query_${PLATFORM_DEP_PACKAGING}" "$@"
}

# Remove a package by name pattern
pkg_remove() {
    "_pkg_remove_${PLATFORM_DEP_PACKAGING}" "$@"
}

# Uninstall all cfbuild-* packages
pkg_uninstall_cfbuild() {
    log_info "Removing cfbuild packages..."
    "_pkg_uninstall_cfbuild_${PLATFORM_DEP_PACKAGING}"
}

# Uninstall all cfbuild-*-devel packages
pkg_uninstall_cfbuild_devel() {
    log_info "Removing cfbuild-devel packages..."
    "_pkg_uninstall_cfbuild_devel_${PLATFORM_DEP_PACKAGING}"
}

# --- DEB implementations ---

_pkg_install_deb() {
    sudo dpkg -i "$@"
}

_pkg_query_deb() {
    dpkg -s "$1" >/dev/null 2>&1
}

_pkg_remove_deb() {
    local _pkgs
    _pkgs=$(dpkg -l | grep "^ii" | awk '{print $2}' | grep "$1" || true)
    if [ -n "$_pkgs" ]; then
        # $_pkgs is intentionally unquoted to pass each package name as a separate argument.
        # shellcheck disable=SC2086
        sudo dpkg --purge $_pkgs
    fi
}

_pkg_uninstall_cfbuild_deb() {
    _pkg_remove_deb 'cfbuild-'
}

_pkg_uninstall_cfbuild_devel_deb() {
    _pkg_remove_deb 'cfbuild-.*-devel'
}

# --- RPM implementations ---

_pkg_install_rpm() {
    sudo rpm -U --force "$@"
}

_pkg_query_rpm() {
    rpm -q "$1" >/dev/null 2>&1
}

_pkg_remove_rpm() {
    local _pkgs
    _pkgs=$(rpm -qa --queryformat "%{Name}\n" | grep "^$1" || true)
    if [ -n "$_pkgs" ]; then
        # $_pkgs is intentionally unquoted to pass each package name as a separate argument.
        # shellcheck disable=SC2086
        sudo rpm -e --nodeps $_pkgs
    fi
}

_pkg_uninstall_cfbuild_rpm() {
    _pkg_remove_rpm 'cfbuild-'
}

_pkg_uninstall_cfbuild_devel_rpm() {
    local _pkgs
    _pkgs=$(rpm -qa --queryformat "%{Name}\n" | grep 'cfbuild-.*-devel' || true)
    if [ -n "$_pkgs" ]; then
        # $_pkgs is intentionally unquoted to pass each package name as a separate argument.
        # shellcheck disable=SC2086
        sudo rpm -e --nodeps $_pkgs
    fi
}

# --- Solaris implementations ---

_pkg_install_solaris() {
    local _pkg
    for _pkg in "$@"; do
        sudo pkgadd -d "$_pkg" all
    done
}

_pkg_query_solaris() {
    pkginfo "$1" >/dev/null 2>&1
}

_pkg_remove_solaris() {
    local _pkgs
    _pkgs=$(pkginfo | awk '{print $2}' | grep "$1" || true)
    if [ -n "$_pkgs" ]; then
        local _p
        for _p in $_pkgs; do
            sudo pkgrm -n "$_p"
        done
    fi
}

_pkg_uninstall_cfbuild_solaris() {
    _pkg_remove_solaris 'cfbuild'
}

_pkg_uninstall_cfbuild_devel_solaris() {
    _pkg_remove_solaris 'cfbuild.*devel'
}

# --- HP-UX implementations ---

_pkg_install_hpux() {
    local _pkg
    for _pkg in "$@"; do
        sudo swinstall -s "$(pwd)/$_pkg"
    done
}

_pkg_query_hpux() {
    swlist "$1" >/dev/null 2>&1
}

_pkg_remove_hpux() {
    local _pkgs
    _pkgs=$(swlist | awk '{print $1}' | grep "$1" || true)
    if [ -n "$_pkgs" ]; then
        local _p
        for _p in $_pkgs; do
            sudo swremove "$_p"
        done
    fi
}

_pkg_uninstall_cfbuild_hpux() {
    _pkg_remove_hpux 'cfbuild'
}

_pkg_uninstall_cfbuild_devel_hpux() {
    _pkg_remove_hpux 'cfbuild.*devel'
}

# --- FreeBSD implementations ---

_pkg_install_freebsd() {
    local _pkg
    for _pkg in "$@"; do
        sudo pkg_add "$_pkg"
    done
}

_pkg_query_freebsd() {
    pkg_info -e "$1" >/dev/null 2>&1
}

_pkg_remove_freebsd() {
    local _pkgs
    _pkgs=$(pkg_info | awk '{print $1}' | grep "$1" || true)
    if [ -n "$_pkgs" ]; then
        local _p
        for _p in $_pkgs; do
            sudo pkg_delete "$_p"
        done
    fi
}

_pkg_uninstall_cfbuild_freebsd() {
    _pkg_remove_freebsd 'cfbuild'
}

_pkg_uninstall_cfbuild_devel_freebsd() {
    _pkg_remove_freebsd 'cfbuild.*devel'
}

# --- AIX implementations (uses RPM for deps) ---

_pkg_install_aix() {
    _pkg_install_rpm "$@"
}

_pkg_query_aix() {
    _pkg_query_rpm "$@"
}

_pkg_remove_aix() {
    _pkg_remove_rpm "$@"
}

_pkg_uninstall_cfbuild_aix() {
    _pkg_uninstall_cfbuild_rpm
}

_pkg_uninstall_cfbuild_devel_aix() {
    _pkg_uninstall_cfbuild_devel_rpm
}

_CFBUILD_PKG_SOURCED=yes
