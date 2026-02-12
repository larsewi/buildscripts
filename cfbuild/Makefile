.PHONY: test lint format check all

SHELL_FILES := cfbuild \
	$(wildcard lib/*.sh) \
	$(wildcard cmd/*.sh) \
	$(wildcard pkg/*.sh) \
	$(wildcard deps/*.sh)

all: check

# Run ShellSpec tests
test:
	@command -v shellspec >/dev/null 2>&1 || { echo "Error: shellspec not found. Install it from https://shellspec.info (e.g., curl -fsSL https://git.io/shellspec | sh)." >&2; exit 1; }
	shellspec

# Run ShellCheck and checkbashisms
lint:
	@command -v shellcheck >/dev/null 2>&1 || { echo "Error: shellcheck not found. Install it with your package manager (e.g., apt install shellcheck, brew install shellcheck)." >&2; exit 1; }
	shellcheck -s sh -x $(SHELL_FILES)
	@echo "ShellCheck passed."
	@if command -v checkbashisms >/dev/null 2>&1; then \
		for f in $(SHELL_FILES); do \
			checkbashisms -f $$f 2>/dev/null || true; \
		done; \
		echo "checkbashisms done."; \
	else \
		echo "checkbashisms not found, skipping (install via: apt install devscripts, or brew install checkbashisms)."; \
	fi

# Format with shfmt (POSIX shell, 4-space indent)
format:
	shfmt -w -i 4 -s -ln posix $(SHELL_FILES)

# Run both lint and test
check: lint test
