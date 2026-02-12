# Managing Dependencies in cfbuild

How to add new dependencies and update existing ones. For how dependency
resolution and building works internally, see
[ARCHITECTURE.md](ARCHITECTURE.md).

## How Dependencies Work

Each dependency has two parts:

1. **A config file** in `cfbuild/etc/deps/<name>.conf` -- version, build type,
   configure flags, and patches.
2. **Source metadata** in `deps-packaging/<name>/` -- download URL(s), SHA-256
   checksum, and patch files.

## Adding a New Dependency

### Step 1: Create the config file

Create `cfbuild/etc/deps/<name>.conf`:

```
name=mylib
version=1.2.3
source=mylib-1.2.3.tar.gz
roles=agent hub
build_type=autoconf
configure_flags=--disable-shared --enable-static
```

#### Config keys

| Key                | Required  | Default              | Description                                                    |
|--------------------|-----------|----------------------|----------------------------------------------------------------|
| `name`             | yes       | --                   | Dependency name, must match the filename                       |
| `version`          | yes       | --                   | Version string                                                 |
| `source`           | yes       | --                   | Source tarball filename                                        |
| `source_dir`       | no        | `${name}-${version}` | Directory name after unpacking                                 |
| `roles`            | no        | --                   | Space-separated roles: `agent`, `hub`, or both                 |
| `build_type`       | no        | `autoconf`           | Build system: `autoconf`, `cmake`, or `custom`                 |
| `build_script`     | if custom | --                   | Script filename in `cfbuild/deps/`                             |
| `configure_flags`  | no        | --                   | Flags passed to `./configure` or `cmake`                       |
| `patches`          | no        | --                   | Space-separated patch files (all platforms)                    |
| `patches_<os>`     | no        | --                   | OS-specific patches, e.g. `patches_aix`, `patches_solaris`     |
| `tests`            | no        | follows `--no-tests` | Override test behavior: `yes` or `no`                          |

The placeholder `@PREFIX@` in `configure_flags` is replaced at build time with
the actual installation prefix (default `/var/cfengine`).

### Step 2: Add source metadata

Create `deps-packaging/<name>/` with two files:

**`source`** -- base URL (tarball filename is appended):

```
https://example.com/releases/v1.2.3/
```

**`distfiles`** -- SHA-256 checksum and filename:

```
abc123def456...  mylib-1.2.3.tar.gz
```

### Step 3: Add patches (if needed)

Place patch files in `deps-packaging/<name>/`. Reference them in the config:

```
patches=fix-build.patch
patches_aix=aix-compat.patch
```

Patches are auto-detected for strip level (`-p1` then `-p0`). Lookup order:
`deps-packaging/<name>/`, then `source/`, then `distfiles/` subdirectories.

### Step 4: Register in the resolver

Edit `dep_resolve_list()` in `cfbuild/lib/deps.sh` and add the name to the
appropriate section. Position determines build order -- dependencies needed by
others must come first. The sections are:

```sh
# Platform-specific deps (from platform config extra_deps)
# SSL deps (zlib, openssl) -- skipped on RHEL 8+, SLES 15+
# Platform-family deps (sasl2 for solaris/hpux)
# Common deps: lmdb pcre2 libxml2 libyaml ...
# Enterprise deps (nova only): openldap leech
# Linux-only deps: libattr libacl
# Role-specific deps:
#   hub: libcurl-hub nghttp2 ... apache php
#   agent: libcurl
```

### Step 5: Custom build scripts (if needed)

For dependencies that don't use autoconf or cmake, set `build_type=custom` and
create `cfbuild/deps/<name>.sh`. The script must define and call a
`dep_build_<name>()` function:

```sh
#!/bin/sh
dep_build_mylib() {
    local _version _source _build_dir _staging
    _version=$(config_get version "")
    _source=$(config_get source "")
    _build_dir="$CFBUILD_BASEDIR/mylib"
    mkdir -p "$_build_dir"
    cd "$_build_dir" || return 1

    dep_unpack_source mylib "$_source"
    cd "mylib-${_version}" || return 1
    dep_apply_patches mylib

    run_quiet "$PLATFORM_MAKE" \
        CC="$PLATFORM_CC" CFLAGS="$PLATFORM_CFLAGS" \
        LDFLAGS="$PLATFORM_LDFLAGS" prefix="$CFBUILD_PREFIX" \
        "$PLATFORM_MAKEFLAGS"

    _staging="$_build_dir/staging"
    mkdir -p "$_staging"
    run_quiet "$PLATFORM_MAKE" \
        prefix="$CFBUILD_PREFIX" DESTDIR="$_staging" install
}

dep_build_mylib
```

Available variables: `$CFBUILD_PREFIX`, `$CFBUILD_BASEDIR`, `$CFBUILD_TYPE`,
`$CFBUILD_ROLE`, `$PLATFORM_MAKE`, `$PLATFORM_CC`, `$PLATFORM_CFLAGS`,
`$PLATFORM_LDFLAGS`, `$PLATFORM_MAKEFLAGS`, `$PLATFORM_ARCH`.

Available functions: `config_get`, `dep_unpack_source`, `dep_apply_patches`,
`run_quiet`, `log_info`/`log_warn`/`log_debug`, `fatal`.

## Updating an Existing Dependency

### Version bump

1. Update `version` and `source` in `cfbuild/etc/deps/<name>.conf`
   (and `source_dir` if it changed)
2. Update the checksum in `deps-packaging/<name>/distfiles`
3. Update the URL in `deps-packaging/<name>/source` if it changed
4. Review patches -- remove obsolete ones, update broken ones

The fingerprint system detects changes and rebuilds automatically.

### Other changes

- **Configure flags** -- edit `configure_flags` in the config
- **Patches** -- add/remove files in `deps-packaging/<name>/` and update the
  `patches` line
- **Build type** -- change `build_type` and create/remove the build script

All of these are covered by the fingerprint and trigger automatic rebuilds.

## Verifying Changes

```bash
./cfbuild deps mylib          # Build just the changed dependency
./cfbuild deps --force mylib  # Force rebuild even if stamp matches
./cfbuild deps                # Build all to verify nothing broke
```

## Examples

### Autoconf dependency (pcre2)

```
name=pcre2
version=10.47
source=pcre2-10.47.tar.gz
roles=agent hub
build_type=autoconf
configure_flags=--disable-cpp --enable-unicode
```

### Custom build with platform patches (openssl)

```
name=openssl
version=3.6.0
source=openssl-3.6.0.tar.gz
roles=agent hub
build_type=custom
build_script=openssl.sh
patches_aix=0006-Add-latomic-on-AIX-7.patch 0008-Define-_XOPEN_SOURCE_EXTENDED-as-1.patch
patches_solaris=0009-Define-_XOPEN_SOURCE-as-600-on-Solaris-SPARC.patch
patches_hpux=fixed-undeclared-identifier.patch
```
