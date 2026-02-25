#!/usr/bin/env bats
#
# namedlock.bats — Test suite for the namedlock tool
#
# Run with:  make test
#            bats tests/namedlock.bats
#

NL="$BATS_TEST_DIRNAME/../bin/namedlock"

# ── Helper libraries ──────────────────────────────────────────────────────────

setup() {
    load '/usr/lib/bats/bats-support/load'
    load '/usr/lib/bats/bats-assert/load'
    load '/usr/lib/bats/bats-file/load'

    # Fresh isolated lock directory per test
    export NAMEDLOCK_DIR
    NAMEDLOCK_DIR="$(mktemp -d)"
    unset NAMEDLOCK_LOG
}

teardown() {
    kill_all_holders
    rm -rf "$NAMEDLOCK_DIR"
}

# ── Helpers ───────────────────────────────────────────────────────────────────

kill_all_holders() {
    local dir="${1:-$NAMEDLOCK_DIR}"
    [[ -d "$dir" ]] || return 0
    for pidfile in "$dir"/*.pid; do
        [[ -e "$pidfile" ]] || continue
        local pid
        pid=$(cat "$pidfile" 2>/dev/null || true)
        [[ -n "$pid" ]] && kill -9 "$pid" 2>/dev/null || true
    done
}

# ── CLI: basics ───────────────────────────────────────────────────────────────

@test "no arguments prints usage and exits 2" {
    run -2 "$NL"
    assert_output --partial "Usage"
}

@test "--version exits 0 and prints version" {
    run -0 "$NL" --version
    assert_output --partial "namedlock"
    assert_output --regexp "[0-9]+\.[0-9]+\.[0-9]+"
}

@test "--help exits 0 and prints usage" {
    run -0 "$NL" --help
    assert_output --partial "Usage"
}

@test "help subcommand exits 0" {
    run -0 "$NL" help
}

@test "unknown command exits 2" {
    run -2 "$NL" bogus-command
}

# ── acquire: argument validation ──────────────────────────────────────────────

@test "acquire with no name exits 2" {
    run -2 "$NL" acquire
}

@test "acquire with invalid name (slash) exits 2" {
    run -2 "$NL" acquire "foo/bar"
    assert_output --partial "invalid lock name"
}

@test "acquire with invalid name (space) exits 2" {
    run -2 "$NL" acquire "foo bar"
}

@test "acquire with unknown option exits 2" {
    run -2 "$NL" acquire mylock --bogus
}

@test "acquire --timeout without value exits 2" {
    run -2 "$NL" acquire mylock --timeout
}

@test "acquire accepts names with dots, dashes, underscores" {
    run -0 "$NL" acquire "my-lock.v2_test"
}

# ── acquire: basic success ────────────────────────────────────────────────────

@test "acquire succeeds and prints a PID" {
    run -0 "$NL" acquire mylock
    [[ "$output" =~ ^[0-9]+$ ]]
}

@test "acquire creates pidfile" {
    "$NL" acquire mylock >/dev/null
    assert_file_exists "$NAMEDLOCK_DIR/mylock.pid"
}

@test "acquire creates lockfile" {
    "$NL" acquire mylock >/dev/null
    assert_file_exists "$NAMEDLOCK_DIR/mylock.lock"
}

@test "pidfile contains the printed PID" {
    pid=$("$NL" acquire mylock)
    assert_equal "$pid" "$(cat "$NAMEDLOCK_DIR/mylock.pid")"
}

@test "holder process is alive after acquire" {
    pid=$("$NL" acquire mylock)
    run kill -0 "$pid"
    assert_success
}

@test "lock dir is created automatically" {
    local subdir="$NAMEDLOCK_DIR/deep/sub"
    NAMEDLOCK_DIR="$subdir" run -0 "$NL" acquire mylock
    assert_dir_exists "$subdir"
    kill_all_holders "$subdir"
    rm -rf "$subdir"
}

# ── acquire: conflict ─────────────────────────────────────────────────────────

@test "second acquire without --wait exits 1" {
    "$NL" acquire mylock >/dev/null
    run -1 "$NL" acquire mylock
}

@test "second acquire without --wait is fast (under 1s)" {
    "$NL" acquire mylock >/dev/null
    t0=$(date +%s%3N)
    run -1 "$NL" acquire mylock
    t1=$(date +%s%3N)
    [ $(( t1 - t0 )) -lt 1000 ]
}

@test "second acquire does not clobber first holder's pidfile" {
    first_pid=$("$NL" acquire mylock)
    run -1 "$NL" acquire mylock
    assert_equal "$first_pid" "$(cat "$NAMEDLOCK_DIR/mylock.pid")"
}

# ── acquire: stale lock cleanup ───────────────────────────────────────────────

@test "acquire detects stale pidfile and succeeds" {
    first_pid=$("$NL" acquire mylock)
    kill -9 "$first_pid"
    sleep 0.2

    run -0 "$NL" acquire mylock
    [[ "$output" =~ ^[0-9]+$ ]]
}

@test "stale cleanup removes old pidfile before acquiring" {
    first_pid=$("$NL" acquire mylock)
    kill -9 "$first_pid"
    sleep 0.2

    new_pid=$("$NL" acquire mylock)
    refute_equal "$new_pid" "$first_pid"
    assert_equal "$new_pid" "$(cat "$NAMEDLOCK_DIR/mylock.pid")"
}

# ── acquire --wait / --timeout ────────────────────────────────────────────────

@test "acquire --wait succeeds once previous lock is released" {
    "$NL" acquire mylock >/dev/null
    ( sleep 1; "$NL" release mylock ) &
    bg_pid=$!

    t0=$(date +%s%3N)
    run -0 "$NL" acquire mylock --wait --timeout 5
    t1=$(date +%s%3N)

    wait "$bg_pid" 2>/dev/null || true
    [ $(( t1 - t0 )) -gt 500 ]
}

@test "acquire --timeout implies --wait" {
    "$NL" acquire mylock >/dev/null
    ( sleep 1; "$NL" release mylock ) &
    bg_pid=$!

    run -0 "$NL" acquire mylock --timeout 5
    wait "$bg_pid" 2>/dev/null || true
}

@test "acquire --wait --timeout exits 75 on timeout" {
    "$NL" acquire mylock >/dev/null
    run "$NL" acquire mylock --wait --timeout 1
    [ "$status" -eq 75 ]
}

@test "acquire --wait --timeout is reasonably fast" {
    "$NL" acquire mylock >/dev/null
    t0=$(date +%s%3N)
    run "$NL" acquire mylock --wait --timeout 1
    t1=$(date +%s%3N)
    [ "$status" -eq 75 ]
    [ $(( t1 - t0 )) -lt 8000 ]
}

# ── release ───────────────────────────────────────────────────────────────────

@test "release exits 0" {
    "$NL" acquire mylock >/dev/null
    run -0 "$NL" release mylock
}

@test "release removes pidfile" {
    "$NL" acquire mylock >/dev/null
    "$NL" release mylock
    assert_file_not_exists "$NAMEDLOCK_DIR/mylock.pid"
}

@test "release removes lockfile" {
    "$NL" acquire mylock >/dev/null
    "$NL" release mylock
    assert_file_not_exists "$NAMEDLOCK_DIR/mylock.lock"
}

@test "release kills holder process" {
    pid=$("$NL" acquire mylock)
    "$NL" release mylock
    sleep 0.2
    run kill -0 "$pid"
    assert_failure
}

@test "release is idempotent when lock not held" {
    run -0 "$NL" release mylock
}

@test "release always exits 0 even with invalid name" {
    run -0 "$NL" release ""
}

@test "double release is safe (exits 0 both times)" {
    "$NL" acquire mylock >/dev/null
    run -0 "$NL" release mylock
    run -0 "$NL" release mylock
}

@test "new acquire succeeds after release" {
    "$NL" acquire mylock >/dev/null
    "$NL" release mylock
    run -0 "$NL" acquire mylock
}

# ── status ────────────────────────────────────────────────────────────────────

@test "status shows HELD when lock is acquired" {
    "$NL" acquire mylock >/dev/null
    run -0 "$NL" status mylock
    assert_output --partial "HELD"
}

@test "status HELD line contains PID" {
    pid=$("$NL" acquire mylock)
    run "$NL" status mylock
    assert_output --partial "PID $pid"
}

@test "status shows FREE when lock is not held" {
    run -0 "$NL" status mylock
    assert_output --partial "FREE"
}

@test "status shows FREE after release" {
    "$NL" acquire mylock >/dev/null
    "$NL" release mylock
    run "$NL" status mylock
    assert_output --partial "FREE"
}

@test "status shows STALE when holder process is dead" {
    pid=$("$NL" acquire mylock)
    kill -9 "$pid"
    sleep 0.2
    run -0 "$NL" status mylock
    assert_output --partial "STALE"
}

@test "status with no name shows all locks" {
    "$NL" acquire lock-a >/dev/null
    "$NL" acquire lock-b >/dev/null
    run -0 "$NL" status
    assert_output --partial "lock-a"
    assert_output --partial "lock-b"
}

@test "status with no locks shows informational message" {
    run -0 "$NL" status
    assert_output --partial "no lock"
}

@test "status exits 2 for invalid name" {
    run -2 "$NL" status "bad/name"
}

# ── list ──────────────────────────────────────────────────────────────────────

@test "list outputs active lock name" {
    "$NL" acquire mylock >/dev/null
    run -0 "$NL" list
    assert_output "mylock"
}

@test "list outputs multiple active locks one per line" {
    "$NL" acquire lock-a >/dev/null
    "$NL" acquire lock-b >/dev/null
    run -0 "$NL" list
    assert_output --partial "lock-a"
    assert_output --partial "lock-b"
}

@test "list produces no output when no locks held" {
    run -0 "$NL" list
    refute_output
}

@test "list does not show released locks" {
    "$NL" acquire mylock >/dev/null
    "$NL" release mylock
    run "$NL" list
    refute_output
}

@test "list does not show stale locks" {
    pid=$("$NL" acquire mylock)
    kill -9 "$pid"
    sleep 0.2
    run -0 "$NL" list
    refute_output
}

# ── wrap ──────────────────────────────────────────────────────────────────────

@test "wrap runs the command" {
    run -0 "$NL" wrap mylock -- echo "hello from wrap"
    assert_output --partial "hello from wrap"
}

@test "wrap propagates command exit code 0" {
    run -0 "$NL" wrap mylock -- true
}

@test "wrap propagates non-zero command exit code" {
    run "$NL" wrap mylock -- bash -c "exit 42"
    [ "$status" -eq 42 ]
}

@test "wrap releases lock after command succeeds" {
    "$NL" wrap mylock -- true
    run "$NL" status mylock
    assert_output --partial "FREE"
}

@test "wrap releases lock after command fails" {
    "$NL" wrap mylock -- bash -c "exit 1" || true
    run "$NL" status mylock
    assert_output --partial "FREE"
}

@test "wrap does not leak PID to stdout" {
    run -0 "$NL" wrap mylock -- echo "only-this"
    assert_output "only-this"
}

@test "wrap with no name exits 2" {
    run -2 "$NL" wrap
}

@test "wrap with no command (missing --) exits 2" {
    run -2 "$NL" wrap mylock
}

@test "wrap exits 1 when lock is already held" {
    "$NL" acquire mylock >/dev/null
    run -1 "$NL" wrap mylock -- true
}

@test "wrap --wait acquires once lock is released" {
    "$NL" acquire mylock >/dev/null
    ( sleep 1; "$NL" release mylock ) &
    bg_pid=$!

    run -0 "$NL" wrap mylock --wait --timeout 5 -- echo "acquired"
    wait "$bg_pid" 2>/dev/null || true
    assert_output --partial "acquired"
}

# ── lock directory resolution ─────────────────────────────────────────────────

@test "NAMEDLOCK_DIR overrides XDG_RUNTIME_DIR" {
    local custom_dir
    custom_dir="$(mktemp -d)"
    NAMEDLOCK_DIR="$custom_dir" run -0 "$NL" acquire mylock
    assert_file_exists "$custom_dir/mylock.pid"
    kill_all_holders "$custom_dir"
    rm -rf "$custom_dir"
}

@test "falls back to XDG_RUNTIME_DIR/namedlock when NAMEDLOCK_DIR unset" {
    local xdg_dir
    xdg_dir="$(mktemp -d)"
    unset NAMEDLOCK_DIR
    XDG_RUNTIME_DIR="$xdg_dir" run -0 "$NL" acquire mylock
    assert_file_exists "$xdg_dir/namedlock/mylock.pid"
    kill_all_holders "$xdg_dir/namedlock"
    rm -rf "$xdg_dir"
}

@test "falls back to HOME/.cache/namedlock when both unset" {
    local fake_home
    fake_home="$(mktemp -d)"
    unset NAMEDLOCK_DIR
    unset XDG_RUNTIME_DIR
    HOME="$fake_home" run -0 "$NL" acquire mylock
    assert_file_exists "$fake_home/.cache/namedlock/mylock.pid"
    kill_all_holders "$fake_home/.cache/namedlock"
    rm -rf "$fake_home"
}

# ── NAMEDLOCK_LOG ─────────────────────────────────────────────────────────────

@test "NAMEDLOCK_LOG is written on acquire" {
    local logfile="$NAMEDLOCK_DIR/test.log"
    NAMEDLOCK_LOG="$logfile" "$NL" acquire mylock >/dev/null
    assert_file_exists "$logfile"
    run grep -q "acquire" "$logfile"
    assert_success
}

@test "NAMEDLOCK_LOG is written on release" {
    local logfile="$NAMEDLOCK_DIR/test.log"
    NAMEDLOCK_LOG="$logfile" "$NL" acquire mylock >/dev/null
    NAMEDLOCK_LOG="$logfile" "$NL" release mylock
    run grep -q "release" "$logfile"
    assert_success
}

@test "log lines match expected format" {
    local logfile="$NAMEDLOCK_DIR/test.log"
    NAMEDLOCK_LOG="$logfile" "$NL" acquire mylock >/dev/null
    run grep -qE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\] \[INFO\] \[namedlock\]' "$logfile"
    assert_success
}

@test "no log written when NAMEDLOCK_LOG is unset" {
    unset NAMEDLOCK_LOG
    "$NL" acquire mylock >/dev/null
    run find "$NAMEDLOCK_DIR" -name "*.log"
    refute_output
}

# ── Mutual exclusion (flock integrity) ───────────────────────────────────────

@test "flock prevents concurrent write — only one acquire wins" {
    local results_dir
    results_dir="$(mktemp -d)"

    local n=8
    for i in $(seq 1 $n); do
        (
            if "$NL" acquire mylock >/dev/null 2>&1; then
                touch "$results_dir/winner-$i"
            fi
        ) &
    done
    wait

    local winners
    winners=$(ls "$results_dir" | wc -l)
    rm -rf "$results_dir"
    assert_equal "$winners" "1"
}
