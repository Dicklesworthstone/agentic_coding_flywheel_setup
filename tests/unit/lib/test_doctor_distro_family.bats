#!/usr/bin/env bats

# Doctor distro-family behaviour (#384, #385)
#
# Two layers used to disagree with install.sh about the same facts on
# Arch/Omarchy:
#   #384 the safe-mode sudo check tested for Debian's `sudo` group, so a
#        healthy Arch install (which grants through `wheel`) always FAILed.
#   #385 doctor warned about stack.srps, which install.sh skips by design
#        because SRPS's upstream installer is apt-only.
#
# doctor.sh ends in `main "$@"`, so it cannot be sourced directly. The tests
# below strip that final line to load the function definitions alone, and
# assert the file still ends that way so the technique fails loudly rather
# than silently testing nothing.

load '../test_helper'

setup() {
    common_setup
    DOCTOR_SH="$PROJECT_ROOT/scripts/lib/doctor.sh"
    [[ -f "$DOCTOR_SH" ]] || fail "doctor.sh not found at $DOCTOR_SH"
}

teardown() {
    common_teardown
}

# Load doctor.sh's function definitions without executing its entrypoint.
load_doctor_functions() {
    local last_line=""
    last_line="$(tail -n 1 "$DOCTOR_SH")"
    [[ "$last_line" == 'main "$@"' ]] \
        || fail "doctor.sh no longer ends in 'main \"\$@\"' (got: $last_line)"
    # shellcheck disable=SC1090
    source <(sed '$d' "$DOCTOR_SH") >/dev/null 2>&1 || true
}

# ============================================================
# #384 — safe-mode sudo entitlement
# ============================================================

@test "sudo entitlement passes when the sudoers policy lists an entitlement" {
    load_doctor_functions

    local bin_dir="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$bin_dir"
    # `sudo -ln true` exits 0: the user has an entitlement, whatever group
    # the distro grants it through.
    printf '#!/usr/bin/env bash\nexit 0\n' > "$bin_dir/sudo"
    # `id -nG` deliberately reports NEITHER admin group, so a pass here can
    # only come from the behavioural test.
    printf '#!/usr/bin/env bash\necho "someone docker"\n' > "$bin_dir/id"
    chmod +x "$bin_dir/sudo" "$bin_dir/id"

    run _acfs_doctor_has_sudo_entitlement "$bin_dir/sudo" "$bin_dir/id" "$(command -v grep)"
    [ "$status" -eq 0 ]
}

@test "sudo entitlement falls back to wheel membership on Arch" {
    load_doctor_functions

    local bin_dir="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$bin_dir"
    # Listing itself requires authentication, so the behavioural test cannot
    # answer; this is the case that used to FAIL on every Arch install.
    printf '#!/usr/bin/env bash\nexit 1\n' > "$bin_dir/sudo"
    printf '#!/usr/bin/env bash\necho "ericziko wheel docker"\n' > "$bin_dir/id"
    chmod +x "$bin_dir/sudo" "$bin_dir/id"

    run _acfs_doctor_has_sudo_entitlement "$bin_dir/sudo" "$bin_dir/id" "$(command -v grep)"
    [ "$status" -eq 0 ]
}

@test "sudo entitlement still accepts the Debian sudo group" {
    load_doctor_functions

    local bin_dir="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$bin_dir"
    printf '#!/usr/bin/env bash\nexit 1\n' > "$bin_dir/sudo"
    printf '#!/usr/bin/env bash\necho "ubuntu sudo docker"\n' > "$bin_dir/id"
    chmod +x "$bin_dir/sudo" "$bin_dir/id"

    run _acfs_doctor_has_sudo_entitlement "$bin_dir/sudo" "$bin_dir/id" "$(command -v grep)"
    [ "$status" -eq 0 ]
}

@test "sudo entitlement fails when neither the policy nor a group grants it" {
    load_doctor_functions

    local bin_dir="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$bin_dir"
    printf '#!/usr/bin/env bash\nexit 1\n' > "$bin_dir/sudo"
    printf '#!/usr/bin/env bash\necho "nobody docker"\n' > "$bin_dir/id"
    chmod +x "$bin_dir/sudo" "$bin_dir/id"

    run _acfs_doctor_has_sudo_entitlement "$bin_dir/sudo" "$bin_dir/id" "$(command -v grep)"
    [ "$status" -ne 0 ]
}

@test "sudo entitlement fails when sudo is not installed at all" {
    load_doctor_functions

    run _acfs_doctor_has_sudo_entitlement "" "$(command -v id)" "$(command -v grep)"
    [ "$status" -ne 0 ]
}

@test "the remediation hint names the admin group this distro actually uses" {
    load_doctor_functions

    _ACFS_DOCTOR_IS_ARCH_FAMILY=true
    run _acfs_doctor_admin_group_name
    [ "$status" -eq 0 ]
    [ "$output" = "wheel" ]

    _ACFS_DOCTOR_IS_ARCH_FAMILY=false
    run _acfs_doctor_admin_group_name
    [ "$status" -eq 0 ]
    [ "$output" = "sudo" ]
}

# ============================================================
# #385 — manifest-declared distro-family applicability
# ============================================================

@test "the manifest declares stack.srps as ubuntu-only" {
    run grep -E "^    families: \[ubuntu\]$" "$PROJECT_ROOT/acfs.manifest.yaml"
    [ "$status" -eq 0 ]
}

@test "both generated indexes carry the family gate for stack.srps" {
    for generated in scripts/generated/manifest_index.sh scripts/generated/doctor_checks.sh; do
        run grep -F "['stack.srps']=\"ubuntu\"" "$PROJECT_ROOT/$generated"
        [ "$status" -eq 0 ]
    done
}

@test "doctor skips a module the manifest does not apply to this family" {
    load_doctor_functions
    declare -gA ACFS_MODULE_FAMILIES=( ['stack.srps']="ubuntu" )

    ACFS_DISTRO_FAMILY=arch run _acfs_doctor_module_applies_to_family "stack.srps"
    [ "$status" -ne 0 ]

    ACFS_DISTRO_FAMILY=ubuntu run _acfs_doctor_module_applies_to_family "stack.srps"
    [ "$status" -eq 0 ]
}

@test "doctor keeps checking modules with no declared family restriction" {
    load_doctor_functions
    declare -gA ACFS_MODULE_FAMILIES=( ['stack.srps']="ubuntu" )

    ACFS_DISTRO_FAMILY=arch run _acfs_doctor_module_applies_to_family "stack.cass"
    [ "$status" -eq 0 ]
}

@test "doctor checks every module when no family map was generated" {
    load_doctor_functions
    unset ACFS_MODULE_FAMILIES

    ACFS_DISTRO_FAMILY=arch run _acfs_doctor_module_applies_to_family "stack.srps"
    [ "$status" -eq 0 ]
}

@test "a full doctor run reports SKIP for stack.srps on arch and checks it on ubuntu" {
    if [[ -z "${ACFS_RUN_DOCTOR_TESTS:-}" ]]; then
        skip "Doctor tests disabled (set ACFS_RUN_DOCTOR_TESTS=1 to enable)"
    fi
    command -v jq &>/dev/null || skip "jq not available"

    local arch_status ubuntu_status
    arch_status="$(ACFS_DISTRO_FAMILY=arch NO_CACHE=true bash "$DOCTOR_SH" --json 2>/dev/null \
        | jq -r '[.checks[]? | select(.id | startswith("stack.srps")) | .status] | unique | join(",")')"
    [ "$arch_status" = "skip" ]

    ubuntu_status="$(ACFS_DISTRO_FAMILY=ubuntu NO_CACHE=true bash "$DOCTOR_SH" --json 2>/dev/null \
        | jq -r '[.checks[]? | select(.id | startswith("stack.srps")) | .status] | unique | join(",")')"
    [ -n "$ubuntu_status" ]
    [ "$ubuntu_status" != "skip" ]
}

@test "install.sh gates stack.srps on the manifest, not a hardcoded family" {
    run grep -F 'acfs_module_supports_family "stack.srps"' "$PROJECT_ROOT/install.sh"
    [ "$status" -eq 0 ]

    # The SRPS branch must not carry its own family test any more, or the two
    # layers can drift apart again the way they did in #385.
    run bash -c "grep -B5 'Skipping SRPS (apt-based' '$PROJECT_ROOT/install.sh' | grep -c 'ACFS_DISTRO_FAMILY.*!='"
    [ "$output" = "0" ]
}

@test "acfs_module_supports_family reads the generated family map" {
    source_lib "install_helpers"
    declare -gA ACFS_MODULE_FAMILIES=( ['stack.srps']="ubuntu" )

    run acfs_module_supports_family "stack.srps" "ubuntu"
    [ "$status" -eq 0 ]

    run acfs_module_supports_family "stack.srps" "arch"
    [ "$status" -ne 0 ]

    # A module with no entry applies everywhere.
    run acfs_module_supports_family "stack.cass" "arch"
    [ "$status" -eq 0 ]

    # A multi-family declaration matches any listed family.
    ACFS_MODULE_FAMILIES['stack.demo']="ubuntu arch"
    run acfs_module_supports_family "stack.demo" "arch"
    [ "$status" -eq 0 ]
}

@test "acfs_module_supports_family does not invent a restriction without a map" {
    source_lib "install_helpers"
    unset ACFS_MODULE_FAMILIES

    run acfs_module_supports_family "stack.srps" "arch"
    [ "$status" -eq 0 ]
}
