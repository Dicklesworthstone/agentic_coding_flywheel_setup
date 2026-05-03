#!/usr/bin/env bats

load '../test_helper'

setup() {
    common_setup
    source_lib "logging"
    source_lib "error_tracking"
}

teardown() {
    common_teardown
}

@test "failed-tools retry defaults fail clearly without HOME context" {
    run env -i PATH="/usr/bin:/bin" bash -c 'set -euo pipefail; source "$1"; source "$2"; save_failed_tools_for_retry' _ "$PROJECT_ROOT/scripts/lib/logging.sh" "$PROJECT_ROOT/scripts/lib/error_tracking.sh"
    assert_failure
    assert_output --partial "Unable to resolve failed-tools retry file"
    refute_output --partial "unbound variable"

    run env -i PATH="/usr/bin:/bin" bash -c 'set -euo pipefail; source "$1"; source "$2"; load_failed_tools_for_retry' _ "$PROJECT_ROOT/scripts/lib/logging.sh" "$PROJECT_ROOT/scripts/lib/error_tracking.sh"
    assert_failure
    assert_output --partial "Unable to resolve failed-tools retry file"
    refute_output --partial "unbound variable"
}

@test "failed-tools retry defaults use TARGET_HOME when HOME is absent" {
    local target_home
    target_home="$(create_temp_dir)"

    run env -i PATH="/usr/bin:/bin" TARGET_HOME="$target_home" bash -c 'set -euo pipefail; source "$1"; source "$2"; track_failed_tool atuin "hook missing"; save_failed_tools_for_retry; clear_install_tracking; load_failed_tools_for_retry; get_failed_tools_list' _ "$PROJECT_ROOT/scripts/lib/logging.sh" "$PROJECT_ROOT/scripts/lib/error_tracking.sh"
    assert_success
    assert_output --partial "atuin"
}

@test "try_step preserves caller errexit-off state" {
    run env -i PATH="/usr/bin:/bin" bash -c '
        set +e
        source "$1"
        before=$-
        try_step "successful command" true >/dev/null 2>&1
        after_success=$-
        status=0
        try_step "failing command" false >/dev/null 2>&1 || status=$?
        after_failure=$-
        [[ "$after_success" != *e* ]] || exit 2
        [[ "$after_failure" != *e* ]] || exit 3
        printf "status=%s\nbefore=%s\nafter_success=%s\nafter_failure=%s\n" \
            "$status" "$before" "$after_success" "$after_failure"
    ' _ "$PROJECT_ROOT/scripts/lib/error_tracking.sh"

    assert_success
    assert_output --partial "status=1"
    assert_output --partial "after_success="
    assert_output --partial "after_failure="
}

@test "try_step_eval missing command string fails without unbound variable" {
    run env -i PATH="/usr/bin:/bin" /usr/bin/bash -c '
        set -euo pipefail
        source "$1"
        status=0
        try_step_eval "missing eval command" || status=$?
        printf "status=%s\n" "$status"
        printf "last_error=%s\n" "$LAST_ERROR"
        printf "last_error_code=%s\n" "$LAST_ERROR_CODE"
    ' _ "$PROJECT_ROOT/scripts/lib/error_tracking.sh"

    assert_success
    assert_output --partial "status=1"
    assert_output --partial "last_error=try_step_eval: missing command string for: missing eval command"
    assert_output --partial "last_error_code=1"
    refute_output --partial "unbound variable"
}

@test "try_step_eval uses trusted bash instead of PATH bash" {
    local fake_bin
    local marker

    fake_bin="$(create_temp_dir)/bin"
    marker="$(create_temp_dir)/poisoned-bash"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/bash" <<'EOF'
#!/bin/sh
printf poisoned > "$ACFS_POISON_MARKER"
exit 43
EOF
    chmod +x "$fake_bin/bash"

    run env -i ACFS_POISON_MARKER="$marker" PATH="$fake_bin:/usr/bin:/bin" /usr/bin/bash -c '
        set -euo pipefail
        source "$1"
        try_step_eval "trusted bash probe" "true" >/dev/null 2>&1
        [[ ! -e "$2" ]] || exit 44
        printf "trusted bash used\n"
    ' _ "$PROJECT_ROOT/scripts/lib/error_tracking.sh" "$marker"

    assert_success
    assert_output "trusted bash used"
}
