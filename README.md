# namedlock

Named lock tool for multi-process shell synchronization.

Provides `acquire` / `release` / `wrap` primitives keyed by a symbolic name,
using `flock` + detached background holder processes.  Designed to be composable
with shell scripts, systemd units, and cron jobs.

## Usage

```
namedlock acquire <name> [--wait] [--timeout <seconds>]
namedlock release <name>
namedlock status  [<name>]
namedlock list
namedlock wrap <name> [--wait] [--timeout <secs>] -- <cmd> [args…]
```

### acquire

Acquires an exclusive named lock.  By default (non-blocking), exits immediately
with code 1 if the lock is already held.

```bash
namedlock acquire my-job               # non-blocking
namedlock acquire my-job --wait        # block indefinitely
namedlock acquire my-job --wait --timeout 30   # block up to 30 s
```

Prints the holder PID on success.  `--timeout` implies `--wait`.

### release

Releases a previously acquired lock.  Always exits 0 — safe to call from
cleanup handlers even if the lock was never acquired.

```bash
namedlock release my-job
```

### status

Prints a human-readable table of lock state.

```bash
namedlock status           # all known locks
namedlock status my-job    # single lock
```

Example output:
```
my-job                    HELD by PID 12345     (runtime: 42s)
other-lock                FREE
stale-lock                STALE (PID 99999 not running)
```

### list

Prints one active lock name per line (for scripting).

```bash
for lock in $(namedlock list); do
    echo "active: $lock"
done
```

### wrap

Acquires the lock, runs a command, then releases the lock automatically —
even if the command fails or is interrupted.

```bash
namedlock wrap my-job -- rsync -av /src/ /dst/
namedlock wrap my-job --wait --timeout 60 -- ./long-running-task.sh
```

The wrapped command's exit code is propagated.

## Exit codes

| Code | Meaning |
|------|---------|
| 0    | Success |
| 1    | Lock already held (acquire without `--wait`), or release/wrap error |
| 2    | Invalid arguments |
| 75   | Timeout waiting for lock (`EX_TEMPFAIL` — compatible with systemd restart policies) |

## Lock directory

Resolved in priority order:

1. `$NAMEDLOCK_DIR` — user override
2. `$XDG_RUNTIME_DIR/namedlock` — systemd user runtime dir (tmpfs, auto-cleaned on logout)
3. `$HOME/.cache/namedlock` — persistent fallback

Per lock: `<dir>/<name>.lock` (held open by flock) + `<dir>/<name>.pid`

Lock names are restricted to `[a-zA-Z0-9_.-]` — safe as filenames, no path traversal.

## Environment variables

| Variable | Purpose |
|----------|---------|
| `NAMEDLOCK_DIR` | Override lock directory |
| `NAMEDLOCK_LOG` | If set, append structured log lines to this file |

Log format: `[YYYY-MM-DD HH:MM:SS] [LEVEL] [namedlock] …`

## Mechanism

`acquire` spawns a detached background process (`nohup bash -c …`) that opens
the lock file on fd 9 and calls `flock`.  The holder writes its PID atomically
(via `.tmp` + `mv`) and then loops indefinitely, keeping fd 9 open.  The parent
polls the pidfile (0.1 s interval) until the holder is confirmed running.

`release` reads the PID, sends `SIGTERM`, waits 0.5 s, sends `SIGKILL` if still
alive, then removes both files.

Stale locks (pidfile present but process dead) are detected and cleaned up
automatically on the next `acquire`.

## Tests

The test suite uses [bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

**Requirements:** `bats`, `bats-support`, `bats-assert`, `bats-file` (all via apt — see Dependencies).

```bash
make test
# or directly:
bats tests/namedlock.bats
```

Coverage includes CLI validation, acquire/release lifecycle, stale lock detection,
blocking wait with timeout, `wrap` exit-code propagation, lock-directory resolution,
logging, and concurrent-acquire mutual exclusion.

## Dependencies

| Dependency | Kind | Package | Notes |
|------------|------|---------|-------|
| `bash` ≥ 4.2 | runtime | pre-installed | associative arrays, `[[ ]]` |
| `flock` | runtime | `util-linux` | pre-installed on Debian/Ubuntu |
| `sleep infinity` | runtime | `coreutils` | pre-installed on Debian/Ubuntu |
| `bats` ≥ 1.5 | test | `bats` | `sudo apt install bats` |
| `bats-support` | test | `bats-support` | `sudo apt install bats-support` |
| `bats-assert` | test | `bats-assert` | `sudo apt install bats-assert` |
| `bats-file` | test | `bats-file` | `sudo apt install bats-file` |
| `shellcheck` | lint | `shellcheck` | `sudo apt install shellcheck` |

Install all at once:

```bash
make install-deps
# or manually:
sudo apt install bats bats-support bats-assert bats-file shellcheck
```

Check all dependencies are present:

```bash
make check-deps
```

## Installation

```bash
make install              # installs to ~/.local/bin/namedlock
make install PREFIX=/usr  # system-wide
```

Or symlink directly:

```bash
ln -s /path/to/tools/namedlock/bin/namedlock ~/.local/bin/namedlock
```

### Ansible

For fleet deployments or IaC-managed hosts, an Ansible role is provided under `ansible/`.

The install scope is controlled by the `install_scope` variable:

| `install_scope` | Install path | Runs as |
|-----------------|-------------|---------|
| `user` (default) | `~/.local/bin/` | current user |
| `system` | `/usr/local/bin/` | root (via sudo) |

No `--become` flag is needed — the playbook manages privilege escalation
internally based on `install_scope`.

Overridable variables (pass with `-e`):

| Variable | Default | Description |
|----------|---------|-------------|
| `install_scope` | `user` | `user` or `system` |
| `namedlock_install_dir` | `~/.local/bin` | install path for user scope |
| `namedlock_system_install_dir` | `/usr/local/bin` | install path for system scope |
| `namedlock_source` | `bin/namedlock` (on controller) | path to binary on control node |
| `namedlock_install_test_deps` | `false` | also install bats/shellcheck test deps |

```bash
# Local  - user install
ansible-playbook -i ansible/inventory.example.yml ansible/install.yml --limit localhost

# Local  - system install
ansible-playbook -i ansible/inventory.example.yml ansible/install.yml --limit localhost \
  -e install_scope=system

# Remote - user install
ansible-playbook -i ansible/inventory.example.yml ansible/install.yml \
  --limit myserver.example.com

# Remote - system install
ansible-playbook -i ansible/inventory.example.yml ansible/install.yml \
  --limit myserver.example.com \
  -e install_scope=system

# With test/lint deps (e.g. CI host)
ansible-playbook -i ansible/inventory.example.yml ansible/install.yml --limit localhost \
  -e install_scope=system \
  -e namedlock_install_test_deps=true

# Dry run
ansible-playbook -i ansible/inventory.example.yml ansible/install.yml --limit localhost \
  --check --diff
```

To uninstall, swap the playbook — all flags mirror install:

```bash
# Local  - user uninstall
ansible-playbook -i ansible/inventory.example.yml ansible/uninstall.yml --limit localhost

# Local  - system uninstall
ansible-playbook -i ansible/inventory.example.yml ansible/uninstall.yml --limit localhost \
  -e install_scope=system

# Remote - user uninstall
ansible-playbook -i ansible/inventory.example.yml ansible/uninstall.yml \
  --limit myserver.example.com

# Remote - system uninstall
ansible-playbook -i ansible/inventory.example.yml ansible/uninstall.yml \
  --limit myserver.example.com \
  -e install_scope=system
```

Copy `ansible/inventory.example.yml` to `ansible/inventory.<hostname>.yml` and edit for your environment.
The role reads the binary from the controller (`bin/namedlock`) and pushes it to targets — no `make` required on remote hosts.

## Monitoring

### Check lock state

```bash
# All locks (human-readable table)
namedlock status

# Single lock
namedlock status borgmatic
```

Example output:
```
borgmatic    HELD by PID 12345    (runtime: 42s)
other-lock   FREE
stale-lock   STALE (PID 99999 not running)
```

### List active locks (for scripting)

```bash
namedlock list
```

### Inspect the lock directory

```bash
# Resolve the active lock directory
echo "${NAMEDLOCK_DIR:-${XDG_RUNTIME_DIR:+$XDG_RUNTIME_DIR/namedlock}}"
# fallback: $HOME/.cache/namedlock

ls -la "${XDG_RUNTIME_DIR:-$HOME/.cache}/namedlock/"
```

Each lock leaves two files: `<name>.lock` (held open by flock) and `<name>.pid`.

### Enable structured logging

```bash
export NAMEDLOCK_LOG=/var/log/namedlock.log
namedlock acquire borgmatic
tail -f /var/log/namedlock.log
```

Log format: `[YYYY-MM-DD HH:MM:SS] [LEVEL] [namedlock] …`

---

## Troubleshooting

### `namedlock: command not found`

The binary is not in `PATH`. Install it or add the install directory:

```bash
# User install
export PATH="$HOME/.local/bin:$PATH"

# System install
sudo cp bin/namedlock /usr/local/bin/namedlock
```

### Lock stuck — process died without releasing

`namedlock status` reports `STALE` when the holder PID is no longer running.
Stale locks are detected and cleaned up automatically on the next `acquire`:

```bash
namedlock status borgmatic   # shows STALE
namedlock acquire borgmatic  # auto-cleans stale lock, then acquires
```

To force-release manually:

```bash
namedlock release borgmatic  # always exits 0, safe on stale locks
```

### Lock held after a borgmatic error

When borgmatic is configured with namedlock hooks and a backup fails,
the `after: error` hook should release the lock:

```yaml
commands:
  - after: error
    run:
      - namedlock release borgmatic
```

If the hook itself failed (e.g. `namedlock` not in PATH for the systemd
service), the lock will be stale. Verify the binary is accessible in the
service's environment:

```bash
# User service
systemctl --user show borgmatic.service | grep Environment

# Release manually
namedlock release borgmatic
```

### Exit code 1 — lock already held

A concurrent process holds the lock. Use `--wait` to block until it is
released, or `--timeout` to cap the wait:

```bash
namedlock acquire borgmatic --wait --timeout 60
```

### Exit code 75 — timeout waiting for lock

The lock was not released within the timeout period. Check what process
holds it and whether it is still healthy:

```bash
namedlock status borgmatic
ps -p $(cat "${XDG_RUNTIME_DIR:-$HOME/.cache}/namedlock/borgmatic.pid")
```

### Permission denied on lock directory

The lock directory is not writable. Override with `NAMEDLOCK_DIR`:

```bash
export NAMEDLOCK_DIR=/tmp/namedlock-$(id -u)
mkdir -p "$NAMEDLOCK_DIR"
```

### `flock: command not found`

`flock` is part of `util-linux`, pre-installed on Debian/Ubuntu. If missing:

```bash
sudo apt install util-linux
```

---

## Verification

```bash
# 1. Basic acquire/release
namedlock acquire test-lock
namedlock status test-lock        # HELD
namedlock list                    # test-lock
namedlock release test-lock
namedlock status test-lock        # FREE

# 2. Conflict detection
namedlock acquire test-lock
namedlock acquire test-lock       # exits 1
namedlock release test-lock

# 3. Blocking wait
namedlock acquire test-lock
( sleep 2; namedlock release test-lock ) &
namedlock acquire test-lock --wait --timeout 5   # succeeds after ~2 s

# 4. Wrap
namedlock wrap test-lock -- echo "inside lock"
namedlock status test-lock        # FREE (auto-released)

# 5. Stale lock cleanup
namedlock acquire test-lock
kill "$(cat "${XDG_RUNTIME_DIR:-$HOME/.cache}/namedlock/test-lock.pid")"
namedlock acquire test-lock       # detects stale, succeeds

# 6. Timeout exit code
namedlock acquire test-lock
namedlock acquire test-lock --wait --timeout 1   # exits 75
namedlock release test-lock
```

