# Managing Platforms in cfbuild

How to add and update platform support. For how platform detection works
internally, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Platform Config Files

### Location and naming

Platform configs live in `cfbuild/etc/platforms/`. The system searches for a
match in this priority order:

1. `${KERNEL}_${OS}_${VERSION_MAJOR}.conf` (e.g. `Linux_debian_12.conf`)
2. `${KERNEL}_${OS}.conf` (e.g. `Linux_debian.conf`)
3. `${OS}.conf` (e.g. `debian.conf`)
4. `${KERNEL}.conf` (e.g. `Linux.conf`)

This allows version-specific overrides while sharing a common base.

### Config keys

| Key            | Default   | Description                                                                       |
|----------------|-----------|-----------------------------------------------------------------------------------|
| `os_family`    | --        | Platform family: `linux`, `freebsd`, `solaris`, `aix`, `hpux`, `mingw`            |
| `packaging`    | --        | Output package format: `deb`, `rpm`, `aix`, `solaris`, `hpux`, `freebsd`, `mingw` |
| `dep_packaging`| `packaging` | Package manager for build deps (may differ from `packaging`)                    |
| `shell`        | `/bin/sh` | Shell interpreter                                                                 |
| `make`         | `make`    | GNU make command (`make` or `gmake`)                                              |
| `patch`        | `patch`   | Patch command (may need full path on some platforms)                              |
| `fuser`        | `fuser`   | fuser command path                                                                |
| `cc`           | `cc`      | C compiler command                                                                |
| `sha256_cmd`   | --        | SHA-256 hashing command (platform-specific)                                       |
| `sed_inplace`  | `no`      | Whether `sed -i` works                                                            |
| `has_mktemp`   | `yes`     | Whether `mktemp` works                                                            |
| `has_systemd`  | `no`      | Whether systemd is available                                                      |
| `rpath_flag`   | --        | RPATH linker flag format (varies by platform)                                     |
| `ldflags`      | --        | Linker flags (`@PREFIX@` substituted at runtime)                                  |
| `cflags`       | --        | C compiler flags (`@PREFIX@` substituted at runtime)                              |
| `cppflags`     | --        | C preprocessor flags (`@PREFIX@` substituted at runtime)                          |
| `path_prepend` | --        | Colon-separated directories to prepend to `$PATH`                                 |
| `extra_deps`   | --        | Space-separated platform-specific mandatory dependencies                          |

### Exported variables

After loading the config, these `PLATFORM_*` variables are exported:

| Variable                    | Source                             |
|-----------------------------|------------------------------------|
| `PLATFORM_KERNEL`           | Detected: `uname -s` result        |
| `PLATFORM_OS`               | Detected: normalized OS identifier |
| `PLATFORM_OS_VERSION`       | Detected: full version string      |
| `PLATFORM_OS_VERSION_MAJOR` | Detected: major version only       |
| `PLATFORM_ARCH`             | Detected: CPU architecture         |
| `PLATFORM_CROSS_TARGET`     | Detected: cross target or empty    |
| `PLATFORM_CORES`            | Detected: CPU core count           |
| `PLATFORM_MAKEFLAGS`        | Derived: `-j${PLATFORM_CORES}`     |
| `PLATFORM_MAKE`             | From config: `make`                |
| `PLATFORM_PATCH`            | From config: `patch`               |
| `PLATFORM_FUSER`            | From config: `fuser`               |
| `PLATFORM_CC`               | From config: `cc`                  |
| `PLATFORM_PACKAGING`        | From config: `packaging`           |
| `PLATFORM_DEP_PACKAGING`    | From config: `dep_packaging`       |
| `PLATFORM_LDFLAGS`          | From config: `ldflags` (expanded)  |
| `PLATFORM_CFLAGS`           | From config: `cflags` (expanded)   |
| `PLATFORM_CPPFLAGS`         | From config: `cppflags` (expanded) |
| `PLATFORM_RPATH_FLAG`       | From config: `rpath_flag`          |
| `PLATFORM_HAS_SYSTEMD`      | From config: `has_systemd`         |
| `PLATFORM_HAS_MKTEMP`       | From config: `has_mktemp`          |
| `PLATFORM_SED_INPLACE`      | From config: `sed_inplace`         |

Additionally, `LDFLAGS`, `CFLAGS`, `CPPFLAGS`, and `MAKEFLAGS` are exported
from their `PLATFORM_*` counterparts so that build tools pick them up
automatically.

### Existing platform configs

| Config File          | OS Family | Packaging | RPATH Flag    | Notable Differences                            |
|----------------------|-----------|-----------|---------------|------------------------------------------------|
| `Linux_debian.conf`  | linux     | deb       | `-Wl,-rpath,` | Also covers Ubuntu                             |
| `Linux_rhel.conf`    | linux     | rpm       | `-Wl,-rpath,` | Also covers CentOS, Rocky via aliases          |
| `Linux_sles.conf`    | linux     | rpm       | `-Wl,-rpath,` | Same as openSUSE                               |
| `freebsd.conf`       | freebsd   | freebsd   | `-Wl,-rpath,` | Uses `gmake`, prepends `/usr/local/bin`        |
| `SunOS_solaris.conf` | solaris   | solaris   | `-Wl,-R,`     | Uses `gmake`, `/opt/csw/bin/gpatch`, XPG4 sh   |
| `AIX_aix.conf`       | aix       | aix       | (none)        | Uses `-Wl,-blibpath` instead of RPATH          |
| `HP-UX_hpux.conf`    | hpux      | hpux      | `-Wl,+b`      | Uses `gmake`, broken `mktemp` and `sed -i`     |
| `mingw.conf`         | mingw     | mingw     | (none)        | Cross-compilation from Linux, `-static-libgcc` |

## Adding a New Platform

### Step 1: Add OS detection (if needed)

**New Linux distribution** -- add a case to `_detect_linux_distro()` in
`cfbuild/lib/platform.sh` matching the `ID` field from `/etc/os-release`.

**New kernel** -- add cases to `_detect_os()` and `_detect_arch()` in
`cfbuild/lib/platform.sh`.

### Step 2: Create the platform config file

Create `cfbuild/etc/platforms/${KERNEL}_${OS}.conf`. Key decisions:

- **`os_family`** -- determines dependency filtering and patch selection
- **`packaging`** -- which `pkg/*.sh` handler creates packages
- **`dep_packaging`** -- which `lib/pkg.sh` functions manage build deps
  (can differ from `packaging`, e.g. AIX uses `aix`/`rpm`)
- **`rpath_flag`** -- `-Wl,-rpath,` (GNU ld), `-Wl,-R,` (Solaris),
  `-Wl,+b` (HP-UX)
- **`extra_deps`** -- platform-only dependencies (e.g. `libgcc libiconv`)
- **Capability flags** -- set `sed_inplace`, `has_mktemp`, `has_systemd`
  accurately; `lib/compat.sh` provides fallbacks for broken tools

### Step 3: Add package manager functions (if new dep_packaging)

Add five functions to `lib/pkg.sh` following the pattern
`_pkg_{action}_{format}` where `{format}` matches `dep_packaging`:
`_pkg_install_*`, `_pkg_query_*`, `_pkg_remove_*`,
`_pkg_uninstall_cfbuild_*`, `_pkg_uninstall_cfbuild_devel_*`.

### Step 4: Create a package handler (if new packaging format)

Create `cfbuild/pkg/<format>.sh`. It is sourced by `cmd/package.sh` and has
access to `$PKG_NAME`, `$PKG_VERSION`, `$PKG_RELEASE`, `$PKG_BUILD_NUMBER`,
`$PKG_TEMPLATE_DIR`, `$CFBUILD_PREFIX`, and all `$PLATFORM_*` variables.

### Step 5: Add compatibility shims (if needed)

Extend functions in `lib/compat.sh` if standard tools are broken or missing:

| Function             | What it handles                                     |
|----------------------|-----------------------------------------------------|
| `compat_mktemp`      | Broken `mktemp` (HP-UX) or missing `mktemp`         |
| `compat_mktempdir`   | Same, for directories                               |
| `compat_sha256`      | Different SHA-256 tools per platform                |
| `compat_sed_inplace` | Portable `sed -i` replacement (never uses `sed -i`) |
| `compat_realpath`    | Missing `realpath`/`readlink -f`                    |
| `compat_nproc`       | Different ways to count CPU cores                   |
| `compat_decompress`  | Archive extraction                                  |

### Step 6: Update dependency resolution (if needed)

Edit `dep_resolve_list()` in `cfbuild/lib/deps.sh` if the platform needs:
- System SSL instead of bundled (add to the system SSL detection block)
- Excluded deps (add `os_family` to the skip list)
- Use `extra_deps` in the platform config for simple additions

### Step 7: Add dependency patches (if needed)

Add `patches_<os>=fix.patch` to dependency configs in `cfbuild/etc/deps/`.
Place patch files in `deps-packaging/<dep_name>/`.

### Step 8: Add a container config (if Linux)

Create or reuse a config in `cfbuild/etc/containers/<pkg_manager>.conf`:

```
pkg_update=mypkg update
pkg_install=mypkg install -y
pkg_clean=mypkg clean all
build_prereqs=gcc make autoconf automake libtool bison flex git wget curl ...
```

## Checklist

- [ ] OS detection works (`cfbuild detect`)
- [ ] Platform config file found by the resolver
- [ ] GNU make, patch, and C compiler accessible
- [ ] SHA-256 hashing works
- [ ] `sed -i` / `mktemp` capability flags set correctly
- [ ] RPATH flag format correct
- [ ] Package manager functions exist for `dep_packaging`
- [ ] Package handler exists for `packaging`
- [ ] Dependencies build (`cfbuild deps`)
- [ ] CFEngine packages build (`cfbuild package`)
