# cfbuild Architecture

How the cfbuild build system works, from the entry point down.

## 1. Entry Point

Everything starts with `./cfbuild`, a POSIX shell script that:

1. **Bootstraps** -- sources `lib/bootstrap.sh` to verify POSIX shell
   compliance (re-executing under a working shell on broken platforms like
   Solaris), then loads the core library modules in dependency order.
2. **Parses global options** -- `--project`, `--role`, `--type`, `--prefix`,
   etc. Defaults come from environment variables with the `CFBUILD_` prefix.
3. **Detects the platform** -- calls `platform_detect()` which identifies
   kernel, OS, architecture, and loads a matching config from `etc/platforms/`.
   See [PLATFORMS.md](PLATFORMS.md) for config details.
4. **Dispatches the command** -- sources `cmd/<command>.sh`, which inherits
   the full environment (all libraries, global variables, platform variables).

```
./cfbuild [options] <command>
    |
    +-- lib/bootstrap.sh        POSIX compliance check
    +-- lib/log.sh              Logging
    +-- lib/error.sh            Error handling, cleanup traps
    +-- lib/config.sh           Config file parser
    +-- lib/compat.sh           Portability shims
    +-- lib/platform.sh         Platform detection
    +-- lib/retry.sh            Retry wrapper
    +-- lib/template.sh         @VAR@ template expansion
    +-- lib/pkg.sh              Package manager abstraction
    |
    +-- platform_detect()       Detect kernel/OS/arch, load config
    |
    +-- cmd/<command>.sh        Execute the requested command
```

## 2. Build Pipeline

The `build` command (`cmd/build.sh`) orchestrates five phases, each
implemented as a separate command handler:

```
cfbuild build
    |
    Step 1/5: Clean       Remove old packages, wipe dist directory
    Step 2/5: Dependencies  (cmd/deps.sh)
    Step 3/5: Configure     (cmd/configure.sh)
    Step 4/5: Compile       (cmd/compile.sh)
    Step 5/5: Package       (cmd/package.sh)
```

Each phase can also be run independently (e.g. `cfbuild deps`, `cfbuild
configure`). See [README.md](README.md) for command usage.

### Configure

Determines which repositories to configure based on the project/role matrix,
then for each repository:

1. Runs `./autogen.sh` (with `NO_CONFIGURE=1`)
2. Assembles `./configure` arguments from dependency paths, role-specific
   flags, platform flags (systemd, SELinux, cross-compilation), and build type
   flags (`-g2 -O1` for debug, `-g2 -O2 -DNDEBUG` for release)
3. Runs `./configure`

### Package

Reads the version from `core/configure.ac` and dispatches to the appropriate
handler in `pkg/`:

| Format  | Handler          | Platforms                 |
|---------|------------------|---------------------------|
| deb     | `pkg/deb.sh`     | Debian, Ubuntu            |
| rpm     | `pkg/rpm.sh`     | RHEL, CentOS, Rocky, SLES |
| aix     | `pkg/aix.sh`     | AIX                       |
| solaris | `pkg/solaris.sh` | Solaris                   |
| hpux    | `pkg/hpux.sh`    | HP-UX                     |
| freebsd | `pkg/freebsd.sh` | FreeBSD                   |
| msi     | `pkg/msi.sh`     | Windows (cross-compiled)  |
| mingw   | `pkg/mingw.sh`   | Windows MinGW archive     |

## 3. Platform Detection

`platform_detect()` in `lib/platform.sh` runs this sequence:

```
platform_detect()
    +-- _detect_cross_target()     Check CFBUILD_CROSS_TARGET / Jenkins labels
    +-- _detect_kernel()           uname -s -> Linux, SunOS, AIX, HP-UX, FreeBSD
    +-- _detect_os()               Identify OS/distro (reads /etc/os-release)
    +-- _detect_arch()             CPU architecture
    +-- _detect_cores()            CPU count for parallel make
    +-- _load_platform_config()    Find and load etc/platforms/*.conf
    +-- _setup_path()              Prepend platform tool directories to PATH
    +-- _expand_platform_flags()   Substitute @PREFIX@ in flags
```

See [PLATFORMS.md](PLATFORMS.md) for config file format, resolution order,
and exported `PLATFORM_*` variables.

## 4. Dependency System

Dependencies are bundled libraries that CFEngine links against (OpenSSL,
libcurl, PCRE2, etc.). See [DEPENDENCIES.md](DEPENDENCIES.md) for config
format and how to add/update dependencies.

### Resolution

`dep_resolve_list()` in `lib/deps.sh` returns an ordered list based on
project, role, and platform. Categories in resolution order:

1. **Platform-specific** -- from `extra_deps` in platform config
2. **SSL** -- `zlib`, `openssl` (skipped on RHEL 8+, SLES/openSUSE 15+)
3. **Platform-family** -- e.g. `sasl2` on Solaris/HP-UX
4. **Common** -- `lmdb`, `pcre2`, `libxml2`, `libyaml`, `diffutils`,
   `librsync`
5. **Enterprise** -- `openldap`, `leech` (nova only)
6. **Linux-only** -- `libattr`, `libacl`
7. **Role-specific** -- agent gets `libcurl`; hub gets `libcurl-hub`,
   `nghttp2`, `libexpat`, `apr`, `apr-util`, `apache`, `git`, `rsync`,
   `postgresql`, `php`

### Build Lifecycle

```
dep_build(name)
    +-- config_read("etc/deps/${name}.conf")
    +-- _dep_stamp_check()                     Skip if unchanged
    +-- dep_build_generic() or custom script
    |   +-- dep_unpack_source()                Download + unpack tarball
    |   +-- dep_apply_patches()                Apply generic + OS-specific patches
    |   +-- ./configure or cmake
    |   +-- make
    |   +-- make install DESTDIR=staging/
    +-- dep_install_staging()                  Copy staging -> prefix
    +-- _dep_stamp_write()                     Record fingerprint
```

Stamp fingerprints cover config content, patch hashes, build script hash,
platform, architecture, build type, and prefix. Changed fingerprints trigger
automatic rebuilds.

## 5. Configuration System

All configuration uses key=value files parsed by `lib/config.sh` into `CFG_*`
shell variables, retrieved with `config_get(key, default)`.

```
etc/
 +-- defaults.conf      Global defaults (project, role, type, prefix)
 +-- platforms/         Platform configs (see PLATFORMS.md)
 +-- deps/             Dependency configs (see DEPENDENCIES.md)
 +-- products/         Product definitions (name, repos, roles)
 +-- containers/       Container distro-family configs (apt, dnf, zypper)
```

The `@PREFIX@` placeholder in config files is substituted with the actual
installation prefix at runtime.

## 6. Library Modules

| Module         | Role                                                         |
|----------------|--------------------------------------------------------------|
| `bootstrap.sh` | POSIX compliance check; re-execs under a working shell       |
| `log.sh`       | Timestamped logging with levels, phase tracking, `run_quiet` |
| `error.sh`     | `fatal()`, cleanup stack for temp files, trap handlers       |
| `config.sh`    | Key=value file parser (`config_read`/`config_get`)           |
| `compat.sh`    | Portability shims (mktemp, sha256, sed, realpath, nproc)     |
| `platform.sh`  | Platform detection, config loading, `PLATFORM_*` exports     |
| `retry.sh`     | Retry wrapper with configurable delay                        |
| `template.sh`  | `@VAR@` placeholder expansion via sed                        |
| `pkg.sh`       | Package manager abstraction (install, query, remove)         |
| `deps.sh`      | Dependency resolution, fetching, building, stamping          |
| `container.sh` | Container engine detection and image management              |

Several subsystems use dynamic function dispatch based on platform variables.
For example, `lib/pkg.sh` routes package operations to platform-specific
implementations by calling `_pkg_install_${PLATFORM_DEP_PACKAGING}`.

## 7. Environment Variables

### Build Settings

| Variable               | Description                          | Default                    |
|------------------------|--------------------------------------|----------------------------|
| `CFBUILD_PROJECT`      | `community` or `nova`                | `community`                |
| `CFBUILD_ROLE`         | `agent` or `hub`                     | `agent`                    |
| `CFBUILD_TYPE`         | `debug` or `release`                 | `debug`                    |
| `CFBUILD_PREFIX`       | Installation prefix                  | `/var/cfengine`            |
| `CFBUILD_CROSS_TARGET` | Cross-compilation target             | _(empty)_                  |
| `CFBUILD_TESTS`        | Run tests: `yes` or `no`             | `yes`                      |
| `CFBUILD_YES`          | Skip confirmation prompts            | `no`                       |
| `CFBUILD_VERBOSE`      | Enable verbose logging               | _(empty)_                  |
| `CFBUILD_QUIET`        | Suppress non-error output            | _(empty)_                  |
| `CFBUILD_FORCE_DEPS`   | Force rebuild of all dependencies    | `no`                       |
| `CFBUILD_CACHE_DIR`    | Source tarball cache                 | `~/.cache/cfbuild/sources` |
| `CFBUILD_SYSTEM_SSL`   | Using system OpenSSL (auto-detected) | `no`                       |
| `CFBUILD_IN_CONTAINER` | Set when running inside a container  | _(empty)_                  |

### Packaging (set by `cmd/package.sh`)

| Variable           | Description                      |
|--------------------|----------------------------------|
| `PKG_NAME`         | Package name                     |
| `PKG_VERSION`      | Version from `core/configure.ac` |
| `PKG_RELEASE`      | Package release number           |
| `PKG_BUILD_NUMBER` | CI build number                  |
| `PKG_TEMPLATE_DIR` | Packaging template directory     |

For `PLATFORM_*` variables, see [PLATFORMS.md](PLATFORMS.md).

## 8. Design Principles

- **POSIX shell only** -- no bash-specific features. The bootstrap module
  re-execs under a working shell on broken platforms (AIX, HP-UX, Solaris).
- **Config-driven platforms** -- platform behavior lives in `etc/platforms/`
  config files, not scattered conditionals. Adding a new Linux distro often
  requires only a new config file.
- **Incremental builds** -- fingerprint stamps skip unchanged dependencies.
  The fingerprint covers configs, patches, scripts, and environment.
- **Staging directories** -- dependencies install to a staging directory first,
  then get copied to the prefix. This isolates build from install.
- **Quiet by default** -- `run_quiet()` suppresses output on success, prints
  full output on failure.
