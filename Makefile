PREFIX  ?= $(HOME)/.local

SCRIPT  := bin/namedlock
TESTS   := tests/namedlock.bats

BATS_LIBS := /usr/lib/bats

.DEFAULT_GOAL := help

# ── Targets ───────────────────────────────────────────────────────────────────

.PHONY: help
help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "  install-deps  Install all dependencies via apt (Debian/Ubuntu)"
	@echo "  check-deps    Check that required dependencies are present"
	@echo "  test          Run the bats test suite"
	@echo "  lint          Run shellcheck static analysis"
	@echo "  install       Install namedlock to PREFIX/bin  (default: ~/.local/bin)"
	@echo "  uninstall     Remove namedlock from PREFIX/bin"
	@echo ""
	@echo "  PREFIX=$(PREFIX)"

.PHONY: install-deps
install-deps:
	sudo apt install -y bats bats-support bats-assert bats-file shellcheck

.PHONY: check-deps
check-deps:
	@command -v bash       >/dev/null || { echo "MISSING (runtime): bash";                               exit 1; }
	@command -v flock      >/dev/null || { echo "MISSING (runtime): flock      — sudo apt install util-linux"; exit 1; }
	@command -v sleep      >/dev/null || { echo "MISSING (runtime): sleep      — sudo apt install coreutils"; exit 1; }
	@command -v bats       >/dev/null || { echo "MISSING (test):    bats       — sudo apt install bats";       exit 1; }
	@test -f $(BATS_LIBS)/bats-support/load.bash || { echo "MISSING (test):    bats-support — sudo apt install bats-support"; exit 1; }
	@test -f $(BATS_LIBS)/bats-assert/load.bash  || { echo "MISSING (test):    bats-assert  — sudo apt install bats-assert";  exit 1; }
	@test -f $(BATS_LIBS)/bats-file/load.bash    || { echo "MISSING (test):    bats-file    — sudo apt install bats-file";    exit 1; }
	@command -v shellcheck >/dev/null || { echo "MISSING (lint):    shellcheck — sudo apt install shellcheck (optional)"; }
	@echo "all required dependencies found"

.PHONY: test
test:
	bats $(TESTS)

.PHONY: lint
lint:
	@command -v shellcheck >/dev/null 2>&1 || \
		{ echo "shellcheck not found — install with: sudo apt install shellcheck"; exit 1; }
	shellcheck $(SCRIPT)

.PHONY: install
install:
	install -Dm755 $(SCRIPT) $(PREFIX)/bin/namedlock
	@echo "Installed to $(PREFIX)/bin/namedlock"

.PHONY: uninstall
uninstall:
	rm -f $(PREFIX)/bin/namedlock
	@echo "Removed $(PREFIX)/bin/namedlock"
