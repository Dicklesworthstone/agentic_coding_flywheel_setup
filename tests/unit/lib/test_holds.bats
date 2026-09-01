#!/usr/bin/env bats
#
# Per-tool version holds (issue #357): parsing, add/remove/list, and
# expiry semantics for scripts/lib/holds.sh.

load '../test_helper'

setup() {
    common_setup

    export HOME="$(create_temp_dir)"
    export ACFS_HOLDS_FILE="$HOME/.acfs/holds.yaml"
    unset ACFS_HOME

    source_lib "holds"
}

teardown() {
    common_teardown
}

@test "holds file path honors ACFS_HOLDS_FILE, then ACFS_HOME, then HOME" {
    run acfs_holds_file
    assert_success
    assert_output "$HOME/.acfs/holds.yaml"

    unset ACFS_HOLDS_FILE
    export ACFS_HOME="$HOME/custom-acfs"
    run acfs_holds_file
    assert_success
    assert_output "$HOME/custom-acfs/holds.yaml"

    unset ACFS_HOME
    run acfs_holds_file
    assert_success
    assert_output "$HOME/.acfs/holds.yaml"
}

@test "add records tool, version, owner, reason, expiry; lookup returns them" {
    run acfs_holds_add br "0.4.1" "henry" "0.5.2 cannot read beads DBs" "2099-01-02"
    assert_success

    run acfs_holds_lookup br
    assert_success
    assert_output "$(printf '0.4.1\thenry\t0.5.2 cannot read beads DBs\t2099-01-02')"
}

@test "add without a reason is rejected" {
    run acfs_holds_add br "current" "henry" "" ""
    assert_failure
    [[ "$output" == *"reason"* ]]
}

@test "add rejects a malformed expiry and an already-expired expiry" {
    run acfs_holds_add br "current" "henry" "why" "next-tuesday"
    assert_failure
    [[ "$output" == *"Invalid expiry"* ]]

    run acfs_holds_add br "current" "henry" "why" "2001-01-01"
    assert_failure
    [[ "$output" == *"already-expired"* ]]
}

@test "add rejects invalid tool names" {
    run acfs_holds_add "../evil" "current" "henry" "why" ""
    assert_failure
    run acfs_holds_add "a b" "current" "henry" "why" ""
    assert_failure
}

@test "active hold: details include version, owner, reason, expiry" {
    acfs_holds_add br "0.4.1" "henry" "regression" "2099-01-02"

    run acfs_holds_active_details br
    assert_success
    assert_output "held at 0.4.1 by henry: regression (expires 2099-01-02)"
}

@test "hold without expiry is active forever" {
    acfs_holds_add ntm "current" "ops" "waiting on upstream fix" ""

    run acfs_holds_active_details ntm
    assert_success
    [[ "$output" == *"(expires never)"* ]]
}

@test "expired hold returns rc 2 (warn-and-ignore), not active" {
    # Write an expired entry directly; acfs_holds_add refuses to create one.
    mkdir -p "$HOME/.acfs"
    cat > "$ACFS_HOLDS_FILE" <<'EOF'
holds:
  br:
    held_version: "0.4.1"
    owner: "henry"
    reason: "old regression"
    expiry: "2020-01-01"
EOF

    run acfs_holds_active_details br
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"expires 2020-01-01"* ]]
}

@test "lookup of an unheld tool fails" {
    acfs_holds_add br "current" "henry" "why" ""
    run acfs_holds_lookup cass
    assert_failure
}

@test "remove deletes only the targeted entry" {
    acfs_holds_add br "current" "henry" "why br" ""
    acfs_holds_add ntm "current" "henry" "why ntm" ""

    run acfs_holds_remove br
    assert_success

    run acfs_holds_lookup br
    assert_failure
    run acfs_holds_lookup ntm
    assert_success
}

@test "remove of an unheld tool fails with a message" {
    run acfs_holds_remove nothing-held
    assert_failure
    [[ "$output" == *"No hold recorded"* ]]
}

@test "list shows every hold and flags expired ones" {
    acfs_holds_add br "0.4.1" "henry" "regression" "2099-01-02"
    mkdir -p "$HOME/.acfs"
    cat >> "$ACFS_HOLDS_FILE" <<'EOF'
  old_tool:
    held_version: "1.0.0"
    owner: "ops"
    reason: "ancient pin"
    expiry: "2020-01-01"
EOF

    run acfs_holds_list
    assert_success
    [[ "$output" == *"br"* ]]
    [[ "$output" == *"regression"* ]]
    [[ "$output" == *"old_tool"* ]]
    [[ "$output" == *"EXPIRED - ignored by updates"* ]]
}

@test "list with no holds says so" {
    run acfs_holds_list
    assert_success
    [[ "$output" == *"No version holds recorded"* ]]
}

@test "values containing quotes round-trip" {
    acfs_holds_add br "current" "henry" 'breaks "beads" DBs' ""
    run acfs_holds_lookup br
    assert_success
    [[ "$output" == *'breaks "beads" DBs'* ]]
}

@test "CLI: add/list/remove flow via direct execution" {
    run bash "$ACFS_LIB_DIR/holds.sh" add br --version 0.4.1 --reason "regression" --expiry 2099-01-02 --owner henry
    assert_success
    [[ "$output" == *"Hold recorded"* ]]

    run bash "$ACFS_LIB_DIR/holds.sh" list
    assert_success
    [[ "$output" == *"br"* ]]
    [[ "$output" == *"henry"* ]]

    run bash "$ACFS_LIB_DIR/holds.sh" remove br
    assert_success
    [[ "$output" == *"Hold removed"* ]]

    run bash "$ACFS_LIB_DIR/holds.sh" list
    assert_success
    [[ "$output" == *"No version holds recorded"* ]]
}

@test "CLI: add requires a tool and a reason" {
    run bash "$ACFS_LIB_DIR/holds.sh" add --reason "why"
    assert_failure

    run bash "$ACFS_LIB_DIR/holds.sh" add br
    assert_failure
    [[ "$output" == *"reason"* ]]
}
