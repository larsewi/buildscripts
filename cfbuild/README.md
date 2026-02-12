# cfbuild

A modular, POSIX shell build system for CFEngine. It provides a single entry
point for building, packaging, and testing CFEngine across Linux distributions
(Debian, Ubuntu, RHEL, CentOS, Rocky, SLES, openSUSE), Windows (MinGW
cross-compilation), AIX, Solaris, FreeBSD, and HP-UX.

Version: 0.1.0

## Quick Start

```sh
# Community edition, debug build (defaults)
./cfbuild build

# Enterprise hub, release build
./cfbuild --project=nova --role=hub --type=release build

# Build only specific dependencies
./cfbuild deps openssl libcurl

# Check what platform was detected
./cfbuild detect
```

## Usage

```
cfbuild [options] <command> [command-options]
```

### Global Options

| Option            | Description                                            | Default         |
|-------------------|--------------------------------------------------------|-----------------|
| `--project=PROJ`  | Project to build: `community`, `nova`                  | `community`     |
| `--role=ROLE`     | Role to build: `agent`, `hub`                          | `agent`         |
| `--type=TYPE`     | Build type: `debug`, `release`                         | `debug`         |
| `--prefix=PATH`   | Installation prefix                                    | `/var/cfengine` |
| `--cross=TARGET`  | Cross-compilation target (`x86-mingw`, `x64-mingw`)    | _(native)_      |
| `--no-tests`      | Skip tests during dependency builds and the test phase |                 |
| `--yes`, `-y`     | Skip confirmation prompts                              |                 |
| `--verbose`, `-v` | Verbose output (includes debug-level logs)             |                 |
| `--quiet`, `-q`   | Suppress non-error output                              |                 |
| `--help`, `-h`    | Show usage                                             |                 |
| `--version`       | Show version                                           |                 |

Options can also be set via environment variables with the `CFBUILD_` prefix
(e.g. `CFBUILD_PROJECT=nova`).

### Commands

#### `build` — Full pipeline

Runs the complete build pipeline: deps → configure → compile → package.

The prefix directory is preserved between runs so that unchanged dependencies
are skipped (based on stamp files and fingerprints). Run `cfbuild clean`
explicitly before `cfbuild build` if you need a full rebuild from scratch.

```sh
cfbuild --project=nova --role=hub --type=release build
```

#### `detect` — Print platform information

Prints detected platform variables and loaded configuration.

```sh
cfbuild detect          # Human-readable output
cfbuild detect --json   # JSON output (for CI/scripting)
```

#### `deps` — Build bundled dependencies

Builds and installs all bundled dependencies required for the current
project/role/platform combination. Specific dependencies can be listed to build
only those.

```sh
cfbuild deps                    # Build all resolved dependencies
cfbuild deps openssl libcurl    # Build only openssl and libcurl
cfbuild deps --force            # Rebuild all, ignoring stamps
```

| Option    | Description                                   |
|-----------|-----------------------------------------------|
| `--force` | Rebuild all dependencies regardless of stamps |

Dependencies are resolved automatically based on project, role, and platform.
Source tarballs are downloaded and cached in `~/.cache/cfbuild/sources/`.

Built dependencies are tracked with stamp files. On subsequent runs, a dependency
is skipped if its stamp fingerprint (covering config, patches, build scripts, and
environment) still matches and the prefix directory exists. Use `--force` or
`cfbuild clean` to trigger a full rebuild.

#### `configure` — Configure CFEngine repositories

Runs `autogen.sh` and `./configure` on each CFEngine repository with
appropriate flags for the current project, role, platform, and build type.

```sh
cfbuild configure
```

Repositories configured depend on the project and role:

| Project   | Role  | Repositories                        |
|-----------|-------|-------------------------------------|
| community | agent | core, masterfiles                   |
| nova      | agent | core, enterprise, masterfiles       |
| nova      | hub   | core, enterprise, nova, masterfiles |

#### `compile` — Build CFEngine

Runs `make` and `make install` on each repository. Build output goes to
`$BASEDIR/cfengine/dist`.

```sh
cfbuild compile
```

#### `package` — Create packages

Creates platform-specific packages (deb, rpm, etc.) from the compiled output.

```sh
cfbuild package
```

Package names are determined by the project/role combination:

| Project/Role | Package Name         |
|--------------|----------------------|
| community/*  | `cfengine-community` |
| nova/agent   | `cfengine-nova`      |
| nova/hub     | `cfengine-nova-hub`  |

Supported package formats: deb, rpm, AIX, Solaris, HP-UX, FreeBSD, MSI, MinGW.

#### `test` — Run tests

Runs CFEngine unit and acceptance tests.

```sh
cfbuild test                            # Run tests locally (default)
cfbuild test --local                    # Explicit local mode
cfbuild test --remote=build-host.local  # Run tests on a remote machine via SSH
cfbuild test --chroot                   # Run tests in a chroot environment
cfbuild test --chroot-root=/path        # Custom chroot root directory
```

Tests are skipped on MinGW and FreeBSD platforms. Use `--no-tests` on the
global options to skip the test phase entirely.

#### `container` — Run a build command inside a container

Runs any cfbuild command inside a container using podman (preferred) or docker.
This lets you build for a specific Linux distro without a matching host.

```sh
# Build inside a Debian 12 container
cfbuild --project=nova container --image=debian:12 build

# Build dependencies inside Rocky Linux 9
cfbuild container --image=rockylinux:9 deps

# Interactive shell inside the container
cfbuild container --image=ubuntu:24.04 --shell

# Print the run command without executing
cfbuild container --image=debian:12 --dry-run build
```

| Option            | Description                             | Default     |
|-------------------|-----------------------------------------|-------------|
| `--image=IMAGE`   | Base container image (required)         |             |
| `--engine=ENGINE` | Force `podman` or `docker`              | auto-detect |
| `--pull`          | Always pull base image and rebuild      | use cached  |
| `--shell`         | Drop into an interactive shell          |             |
| `--network=MODE`  | Container network mode (e.g., `host`)   |             |
| `--dry-run`       | Print the run command without executing |             |

Supported base images are mapped to distro families:

| Images                                                     | Family |
|------------------------------------------------------------|--------|
| `debian:*`, `ubuntu:*`                                     | apt    |
| `rockylinux:*`, `almalinux:*`, `centos:*`, `fedora:*`, UBI | dnf    |
| `opensuse/*`, `suse/*`, `sles:*`                           | zypper |

The first run builds a `cfbuild/<image>:latest` container image with build
prerequisites installed. Subsequent runs reuse the cached image. Use `--pull` to
force a rebuild.

#### `clean` — Remove build artifacts

Removes installed cfbuild packages, the prefix directory, and the dist
directory.

```sh
cfbuild clean         # Remove packages, prefix, and dist
cfbuild clean --all   # Also remove dependency build dirs and run make clean
```

## Workspace Layout

cfbuild expects the following repository layout:

```
workspace/
├── buildscripts/       # This repository (contains cfbuild/)
│   └── cfbuild/        # The build system
├── core/               # CFEngine core (always required)
├── enterprise/         # CFEngine Enterprise (nova only)
├── nova/               # CFEngine Nova hub (nova-hub only)
└── masterfiles/        # Default policy files (always required)
```

The workspace root (`$CFBUILD_BASEDIR`) is auto-detected as two levels above
the cfbuild directory.

## Platform Support

| Platform              | Packaging       | Notes                                                      |
|-----------------------|-----------------|------------------------------------------------------------|
| Debian / Ubuntu       | deb             | systemd service support                                    |
| RHEL / CentOS / Rocky | rpm             | System SSL on 8+, SELinux policy on 8+                     |
| SLES / openSUSE       | rpm             | System SSL on 15+                                          |
| AIX                   | aix (deps: rpm) | Requires GCC 6 from `/opt/freeware`, uses `gmake`          |
| Solaris               | solaris         | Uses OpenCSW, enforces 64-bit on SPARC                     |
| HP-UX                 | hpux            | Uses GCC, broken `mktemp`/`sed -i` handled by compat shims |
| FreeBSD               | freebsd         | Tests not supported                                        |
| Windows               | msi / mingw     | Cross-compilation from Linux via MinGW                     |

See [PLATFORMS.md](PLATFORMS.md) for platform config details and how to add new
platforms.

## Testing

cfbuild uses [ShellSpec](https://shellspec.info/) for unit tests and
[ShellCheck](https://www.shellcheck.net/) for static analysis.

```sh
cd cfbuild
make check      # Run lint + tests
make lint       # Run ShellCheck
make format     # Format with shfmt
```

## Further Reading

- [ARCHITECTURE.md](ARCHITECTURE.md) — how the build system works internally
- [DEPENDENCIES.md](DEPENDENCIES.md) — how to add and update bundled dependencies
- [PLATFORMS.md](PLATFORMS.md) — how to add and update platform support
