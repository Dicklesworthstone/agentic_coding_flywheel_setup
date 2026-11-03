#!/usr/bin/env bats
#
# Issue #486: stack.wezterm_automata cloned the repository (now FrankenTerm)
# and ran `cargo build --release -p wa`. The workspace has no `wa` package, so
# the build could not succeed, and it compiled with no memory bound. The
# module must now refuse without cloning or compiling, name the supported
# FrankenTerm installer, and keep an explicit --only selection fatal.
#
# The generated function body is loaded from scripts/generated/install_stack.sh.
# Every external command its install step could reach (git, cargo, cp, rm,
# mktemp) is a recording stub, so nothing is cloned, built or deleted even if
# the old step comes back.

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    GENERATED="$PROJECT_ROOT/scripts/generated/install_stack.sh"

    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    CALLS="$BATS_TEST_TMPDIR/calls.log"
    FAKE_TMP="$BATS_TEST_TMPDIR/fake-build-dir"
    mkdir -p "$STUB_BIN" "$FAKE_TMP"
    : > "$CALLS"
    local tool
    for tool in git cargo cp rm wa; do
        printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 0\n' "$tool" "$CALLS" > "$STUB_BIN/$tool"
        chmod 755 "$STUB_BIN/$tool"
    done
    printf '#!/bin/sh\necho "mktemp $*" >> "%s"\necho "%s"\n' "$CALLS" "$FAKE_TMP" > "$STUB_BIN/mktemp"
    chmod 755 "$STUB_BIN/mktemp"
    export STUB_BIN CALLS

    LOGGED=""
    SKIPPED=""
    log_step() { LOGGED+="step: $*"$'\n'; }
    log_info() { LOGGED+="info: $*"$'\n'; }
    log_warn() { LOGGED+="warn: $*"$'\n'; }
    log_error() { LOGGED+="error: $*"$'\n'; }
    log_success() { LOGGED+="success: $*"$'\n'; }
    acfs_require_contract() { return 0; }
    acfs_generated_ensure_selection() { return 0; }
    should_run_module() { return 0; }
    record_skipped_tool() { SKIPPED+="$1|$2"$'\n'; }
    run_as_target_shell() { PATH="$STUB_BIN:/usr/bin:/bin" bash -s; }
    EXPLICIT=false
    acfs_module_explicitly_selected() { [[ "$EXPLICIT" == true ]]; }

    eval "$(sed -n '/^acfs_generated_install_stack_wezterm_automata() {$/,/^}$/p' "$GENERATED")"
    [[ "$(type -t acfs_generated_install_stack_wezterm_automata)" == "function" ]]
}

@test "stack.wezterm_automata refuses without cloning or compiling" {
    DRY_RUN=false
    run acfs_generated_install_stack_wezterm_automata
    [[ "$status" -eq 0 ]]
    ! grep -Eq '^(git|cargo|cp|rm|mktemp) ' "$CALLS"
    [[ "$output" == *"has no 'wa' package"* ]]
    [[ "$output" == *"frankenterm#installation"* ]]
}

@test "stack.wezterm_automata records the reason as an optional-module skip" {
    DRY_RUN=false
    acfs_generated_install_stack_wezterm_automata 2>/dev/null
    [[ "$SKIPPED" == "stack.wezterm_automata|install command failed: FrankenTerm is not installed by ACFS yet (no source build)"* ]]
    [[ "$LOGGED" != *"success: stack.wezterm_automata installed"* ]]
}

@test "stack.wezterm_automata stays fatal when explicitly requested with --only" {
    DRY_RUN=false
    EXPLICIT=true
    run acfs_generated_install_stack_wezterm_automata
    [[ "$status" -eq 1 ]]
    ! grep -Eq '^(git|cargo) ' "$CALLS"
}
