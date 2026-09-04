#!/usr/bin/env bats
#
# Process-storm watchdog (issue #348): the sampler, the /proc parsers, and the
# forensic snapshot. Everything runs against a synthetic /proc tree so the
# tests are deterministic and never depend on the host's real process table.

load '../test_helper'

setup() {
    common_setup

    unset TARGET_USER TARGET_HOME ACFS_BIN_DIR ACFS_STATE_FILE ACFS_HOME

    export HOME
    HOME="$(create_temp_dir)"
    export TARGET_HOME="$HOME"
    export UPDATE_LOG_DIR="$HOME/.acfs/logs/updates"

    source_lib "update"

    FAKE_PROC="$HOME/proc"
    mkdir -p "$FAKE_PROC"
}

teardown() {
    common_teardown
}

# Create a fake /proc entry. comm may contain spaces/parens to exercise the
# stat parser.
make_proc_entry() {
    local pid="$1" comm="$2" ppid="$3"
    shift 3
    local dir="$FAKE_PROC/$pid"

    mkdir -p "$dir"
    printf '%s\n' "$comm" > "$dir/comm"
    printf '%s (%s) S %s 1 1 0 -1 4194304 100 0 0 0 1 2 3 4\n' \
        "$pid" "$comm" "$ppid" > "$dir/stat"
    if (( $# > 0 )); then
        printf '%s\0' "$@" > "$dir/cmdline"
    else
        : > "$dir/cmdline"
    fi
}

make_proc_basics() {
    printf '0.10 0.20 0.30 2/300 12345\n' > "$FAKE_PROC/loadavg"
    {
        printf 'cpu  1 2 3 4 5 6 7\n'
        printf 'processes 987654\n'
        printf 'procs_running 12\n'
        printf 'procs_blocked 3\n'
    } > "$FAKE_PROC/stat"
    mkdir -p "$FAKE_PROC/sys/kernel"
    printf '4194304\n' > "$FAKE_PROC/sys/kernel/pid_max"
    printf '255000\n' > "$FAKE_PROC/sys/kernel/threads-max"
    {
        printf 'processor\t: 0\n'
        printf 'model name\t: fake\n'
        printf 'processor\t: 1\n'
        printf 'model name\t: fake\n'
        printf 'processor\t: 2\n'
    } > "$FAKE_PROC/cpuinfo"
}

@test "procwatch: cpu count comes from /proc/cpuinfo and never returns 0" {
    make_proc_basics
    run update_procwatch_cpu_count "$FAKE_PROC"
    assert_success
    assert_output "3"

    run update_procwatch_cpu_count "$FAKE_PROC/does-not-exist"
    assert_success
    assert_output "1"
}

@test "procwatch: ppid parses past a comm containing spaces and parentheses" {
    make_proc_entry 4242 "weird ) name" 991

    local got=""
    update_procwatch_read_ppid got "$FAKE_PROC/4242/stat"
    [ "$got" = "991" ]

    run update_procwatch_read_ppid got "$FAKE_PROC/nope/stat"
    assert_failure
}

@test "procwatch: cmdline rejoins NUL-separated argv" {
    make_proc_entry 4243 "ast-grep" 500 "ast-grep" "scan" "-c" "/tmp/rules.yml" "/srv/project"

    local got=""
    update_procwatch_read_cmdline got "$FAKE_PROC/4243/cmdline"
    [ "$got" = "ast-grep scan -c /tmp/rules.yml /srv/project" ]

    # An empty cmdline (kernel thread) is a failure, not an empty success.
    make_proc_entry 4244 "kworker" 2
    run update_procwatch_read_cmdline got "$FAKE_PROC/4244/cmdline"
    assert_failure
}

@test "procwatch: scan counts by process name and reports the top offender" {
    make_proc_basics
    local i
    for (( i = 0; i < 40; i++ )); do
        make_proc_entry "$(( 1000 + i ))" "ast-grep" "$(( 5000 + i ))" "ast-grep" "scan"
    done
    for (( i = 0; i < 3; i++ )); do
        make_proc_entry "$(( 2000 + i ))" "bash" 1 "bash"
    done

    update_procwatch_scan "$FAKE_PROC"
    [ "$PROCWATCH_TOTAL" -eq 43 ]
    [ "$PROCWATCH_TOP_COMM" = "ast-grep" ]
    [ "$PROCWATCH_TOP_COUNT" -eq 40 ]
    [ "${PROCWATCH_COUNTS[bash]}" -eq 3 ]
}

@test "procwatch: scan fails on a proc root with no processes" {
    run update_procwatch_scan "$FAKE_PROC"
    assert_failure
}

@test "procwatch: snapshot records the histogram, offenders, parents, and fork counter" {
    make_proc_basics
    local i
    # Distinct short-lived shell parents, one child each: the shape the
    # incident actually showed. Only half the parents still exist, which is
    # also what a live capture of a storm looks like.
    for (( i = 0; i < 12; i++ )); do
        if (( i < 6 )); then
            make_proc_entry "$(( 6000 + i ))" "sh" 1 "sh" "-c" "ast-grep scan"
        fi
        make_proc_entry "$(( 1000 + i ))" "ast-grep" "$(( 6000 + i ))" \
            "ast-grep" "scan" "-c" "rules.yml" "."
    done

    update_procwatch_scan "$FAKE_PROC"
    local dump="$HOME/storm.txt"
    run update_procwatch_dump "$FAKE_PROC" "$dump" "test trip" 5
    assert_success

    grep -q "reason:    test trip" "$dump"
    grep -q "loadavg:   0.10 0.20 0.30" "$dump"
    grep -q "forks:     987654" "$dump"
    grep -q "runnable:  12" "$dump"
    grep -q "pid_max:   4194304" "$dump"
    grep -q "top:       ast-grep x 12" "$dump"
    grep -q "ast-grep scan -c rules.yml \." "$dump"
    grep -q "ppid=6000" "$dump"
    grep -q "sh -c ast-grep scan" "$dump"

    # max_procs bounds the per-process listing but not the parent histogram.
    [ "$(grep -c '^  pid=' "$dump")" -eq 5 ]
    [ "$(grep -c '^  ppid=' "$dump")" -eq 12 ]
    grep -q "<gone>" "$dump"

    # Histogram is descending.
    local first
    first="$(awk '/^## process-name histogram/{getline; print; exit}' "$dump")"
    [[ "$first" == *"ast-grep"* ]]
}

@test "procwatch: loop writes a snapshot when a process name crosses the threshold" {
    make_proc_basics
    local i
    for (( i = 0; i < 20; i++ )); do
        make_proc_entry "$(( 1000 + i ))" "ast-grep" 900 "ast-grep" "scan"
    done
    local dumpdir="$HOME/dumps"
    mkdir -p "$dumpdir"

    run update_procwatch_loop "$FAKE_PROC" "$dumpdir" 1 10 100000 5 "" 1
    assert_success
    [[ "$output" == *"process-storm watchdog tripped"* ]]
    [[ "$output" == *"'ast-grep' reached 20"* ]]
    [ "$(find "$dumpdir" -name 'storm-*.txt' | wc -l | tr -d ' ')" -eq 1 ]
}

@test "procwatch: loop trips on total table size even with no single hot name" {
    make_proc_basics
    local i
    for (( i = 0; i < 20; i++ )); do
        make_proc_entry "$(( 1000 + i ))" "proc$i" 900 "proc$i"
    done
    local dumpdir="$HOME/dumps"
    mkdir -p "$dumpdir"

    run update_procwatch_loop "$FAKE_PROC" "$dumpdir" 1 100000 15 5 "" 1
    assert_success
    [[ "$output" == *"process table reached 20 entries"* ]]
}

@test "procwatch: loop stays silent below both thresholds" {
    make_proc_basics
    local i
    for (( i = 0; i < 20; i++ )); do
        make_proc_entry "$(( 1000 + i ))" "ast-grep" 900 "ast-grep"
    done
    local dumpdir="$HOME/dumps"
    mkdir -p "$dumpdir"

    run update_procwatch_loop "$FAKE_PROC" "$dumpdir" 1 100 100000 5 "" 1
    assert_success
    assert_output ""
    [ "$(find "$dumpdir" -name 'storm-*.txt' | wc -l | tr -d ' ')" -eq 0 ]
}

@test "procwatch: start is a no-op when disabled or when /proc is unavailable" {
    make_proc_basics
    export ACFS_PROCWATCH_DIR="$HOME/dumps"

    ACFS_PROCWATCH=0 ACFS_PROCWATCH_PROC="$FAKE_PROC" update_procwatch_start
    [ -z "$ACFS_PROCWATCH_PID" ]

    ACFS_PROCWATCH_PROC="$HOME/no-such-proc" update_procwatch_start
    [ -z "$ACFS_PROCWATCH_PID" ]

    # stop() is safe when nothing was started.
    run update_procwatch_stop
    assert_success
}

@test "procwatch: start launches a sampler that trips and can be stopped" {
    make_proc_basics
    local i
    for (( i = 0; i < 20; i++ )); do
        make_proc_entry "$(( 1000 + i ))" "ast-grep" 900 "ast-grep" "scan"
    done

    export ACFS_PROCWATCH_DIR="$HOME/dumps"
    export ACFS_PROCWATCH_PROC="$FAKE_PROC"
    export ACFS_PROCWATCH_THRESHOLD=10
    export ACFS_PROCWATCH_INTERVAL=1
    export ACFS_PROCWATCH_MAX_DUMPS=1

    update_procwatch_start
    [ -n "$ACFS_PROCWATCH_PID" ]

    local waited=0
    while (( waited < 50 )); do
        if compgen -G "$ACFS_PROCWATCH_DIR/storm-*.txt" > /dev/null; then
            break
        fi
        sleep 0.1
        waited=$(( waited + 1 ))
    done
    compgen -G "$ACFS_PROCWATCH_DIR/storm-*.txt" > /dev/null

    update_procwatch_stop
    [ -z "$ACFS_PROCWATCH_PID" ]
    # The tick FIFO is cleaned up.
    [ "$(find "$ACFS_PROCWATCH_DIR" -name '.tick.*' | wc -l | tr -d ' ')" -eq 0 ]
}

@test "procwatch: a non-numeric threshold override disables the watchdog rather than misbehaving" {
    make_proc_basics
    export ACFS_PROCWATCH_DIR="$HOME/dumps"
    export ACFS_PROCWATCH_PROC="$FAKE_PROC"
    export ACFS_PROCWATCH_THRESHOLD="lots"

    update_procwatch_start
    [ -z "$ACFS_PROCWATCH_PID" ]
}

@test "procwatch: scan short-circuits below the smallest threshold without reading /proc entries" {
    make_proc_basics
    local i
    for (( i = 0; i < 20; i++ )); do
        make_proc_entry "$(( 1000 + i ))" "ast-grep" 900 "ast-grep"
    done

    update_procwatch_scan "$FAKE_PROC" 100
    [ "$PROCWATCH_TOTAL" -eq 20 ]
    [ "$PROCWATCH_TOP_COUNT" -eq 0 ]
    [ "${#PROCWATCH_COUNTS[@]}" -eq 0 ]

    # At or above the bound it does the full pass.
    update_procwatch_scan "$FAKE_PROC" 20
    [ "$PROCWATCH_TOP_COMM" = "ast-grep" ]
    [ "$PROCWATCH_TOP_COUNT" -eq 20 ]
}
