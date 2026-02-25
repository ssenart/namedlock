# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-02-25

### Added
- `acquire` subcommand with non-blocking (default), `--wait`, and `--timeout` modes
- `release` subcommand — always exits 0, safe to call from cleanup handlers
- `status` subcommand — human-readable table showing HELD / FREE / STALE state
- `list` subcommand — machine-readable active lock names, one per line
- `wrap` subcommand — acquire, run command, auto-release on exit/signal
- `--version` / `-V` flag
- `--help` / `-h` / `help` subcommand
- Lock directory resolution: `$NAMEDLOCK_DIR` → `$XDG_RUNTIME_DIR/namedlock` → `$HOME/.cache/namedlock`
- Stale lock detection and automatic cleanup on next acquire
- Structured logging via `$NAMEDLOCK_LOG`
- Exit code 75 (`EX_TEMPFAIL`) on lock timeout — compatible with systemd restart policies
- 65-test bats suite covering CLI validation, lifecycle, stale cleanup, wait/timeout, wrap, directory resolution, logging, and concurrent mutual exclusion
- Makefile with `help`, `check-deps`, `install-deps`, `test`, `lint`, `install`, `uninstall`, `release` targets
- shellcheck-clean with `.shellcheckrc`

[Unreleased]: https://github.com/ssenart/namedlock/compare/1.0.0...HEAD
[1.0.0]: https://github.com/ssenart/namedlock/releases/tag/1.0.0
