# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in the `cfbuild/` directory.

## Overview

`cfbuild` is a modular, POSIX shell build system for CFEngine. See `README.md` in this directory for full documentation.

## Mandatory Workflows

- **Formatting**: After modifying any `.sh` file or the `cfbuild` entry point, run `make format` from the `cfbuild/` directory to format with shfmt (POSIX shell, 4-space indent).
- **Linting**: After formatting, run `make lint` and fix all issues before considering the task done.
- **Docs**: After changing any user-facing or internal behaviour, update the appropriate markdown file (see Documentation Layout below). Do not duplicate information across files.
- **Markdown tables**: When editing or creating markdown tables, always align the column separators (`|`) so that columns line up visually.

## Documentation Layout

Each markdown file has a single responsibility. When updating docs, put information in the correct file and cross-reference rather than duplicate.

| File              | Role                             | What goes here                                                                                                                                       |
|-------------------|----------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------|
| `README.md`       | CLI reference for users          | Quick start, usage, global options, command docs, workspace layout, platform support summary                                                         |
| `ARCHITECTURE.md` | How the system works internally  | Entry point flow, build pipeline, platform detection overview, dependency build lifecycle, library modules, environment variables, design principles |
| `DEPENDENCIES.md` | How-to for dependency management | Config key reference, adding/updating dependencies, custom build script template, examples                                                           |
| `PLATFORMS.md`    | How-to for platform management   | Platform config key reference, exported `PLATFORM_*` variables, existing configs table, adding new platforms, compat shims, checklist                |

## Code Conventions

- All scripts are POSIX shell (`#!/bin/sh`). Do not use bash-specific features.
- Libraries in `lib/` use a source guard pattern to prevent double-sourcing:
  ```sh
  if [ "$_CFBUILD_MYLIB_SOURCED" = yes ]; then
      return 0 2>/dev/null || exit 0
  fi
  ```
- Libraries declare their dependencies with `: "${_CFBUILD_DEP_SOURCED:?...}"`.
- Use `local` variables prefixed with `_` to avoid namespace collisions.
- Use `fatal "message"` for error exits, `log_info`/`log_warn`/`log_error`/`log_debug` for logging.
- Command handlers in `cmd/` are sourced (not executed) by the main `cfbuild` script, so they share its environment.

## Key Commands

```sh
make lint       # Run shellcheck (must pass)
make test       # Run ShellSpec unit tests
make format     # Format with shfmt (POSIX, 4-space indent)
make check      # lint + test
```

## Directory Layout

| Directory | Purpose |
|-----------|---------|
| `lib/`    | Core libraries, sourced by the main entry point or by commands        |
| `cmd/`    | Command handlers, one per cfbuild subcommand                          |
| `deps/`   | Custom dependency build scripts                                       |
| `pkg/`    | Package format handlers (deb, rpm, aix, etc.)                         |
| `etc/`    | Configuration files (defaults, deps, platforms, products, containers) |
| `spec/`   | ShellSpec test suite                                                  |
