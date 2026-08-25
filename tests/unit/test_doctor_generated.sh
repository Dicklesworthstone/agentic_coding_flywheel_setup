#!/usr/bin/env bash
# ============================================================
# Unit tests for doctor generated checks and fix suggestions
#
# Tests that doctor.sh properly integrates generated manifest
# checks and provides actionable fix suggestions.
#
# Run with: bash tests/unit/test_doctor_generated.sh
#
# Related beads:
#   - bd-31ps.5.1: Doctor: integrate generated checks
#   - bd-31ps.5.2: Doctor: per-module fix suggestions
#   - bd-31ps.5.3: Tests: doctor generated checks + hints
# ============================================================

set -uo pipefail

# Get the absolute path to the scripts directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source the test harness
source "$REPO_ROOT/tests/vm/lib/test_harness.sh"

# Log file
LOG_FILE="/tmp/acfs_doctor_generated_test_$(date +%Y%m%d_%H%M%S).log"
DOCTOR_JSON_OUTPUT=""
DOCTOR_JSON_LOADED=false

# Redirect all output to log file as well
exec > >(tee -a "$LOG_FILE") 2>&1

ensure_doctor_json_output() {
    if [[ "$DOCTOR_JSON_LOADED" != "true" ]]; then
        DOCTOR_JSON_OUTPUT="$(bash "$REPO_ROOT/scripts/lib/doctor.sh" --json 2>&1 || true)"
        DOCTOR_JSON_LOADED=true
    fi
}

# ============================================================
# Test Cases
# ============================================================

test_generated_checks_file_exists() {
    harness_section "Test: Generated doctor_checks.sh exists"

    local checks_file="$REPO_ROOT/scripts/generated/doctor_checks.sh"
    if [[ -f "$checks_file" ]]; then
        harness_pass "doctor_checks.sh exists"
    else
        harness_fail "doctor_checks.sh not found at $checks_file"
        return 1
    fi

    # Check that it has MANIFEST_CHECKS array
    if grep -q 'declare -a MANIFEST_CHECKS=' "$checks_file"; then
        harness_pass "MANIFEST_CHECKS array is defined"
    else
        harness_fail "MANIFEST_CHECKS array not found"
        return 1
    fi

    # Count number of checks
    local check_count
    check_count=$(grep -c '^\s*"' "$checks_file" 2>/dev/null || echo "0")
    if [[ "$check_count" -gt 50 ]]; then
        harness_pass "MANIFEST_CHECKS has $check_count entries"
    else
        harness_fail "MANIFEST_CHECKS has too few entries ($check_count)"
    fi
}

test_doctor_sources_generated_checks() {
    harness_section "Test: doctor.sh sources generated checks"

    local doctor_file="$REPO_ROOT/scripts/lib/doctor.sh"

    # Check that doctor.sh loads the generated checks
    if grep -q 'doctor_checks.sh' "$doctor_file"; then
        harness_pass "doctor.sh references doctor_checks.sh"
    else
        harness_fail "doctor.sh does not reference doctor_checks.sh"
        return 1
    fi

    # Check for MANIFEST_CHECKS_LOADED variable
    if grep -q 'MANIFEST_CHECKS_LOADED' "$doctor_file"; then
        harness_pass "MANIFEST_CHECKS_LOADED tracking exists"
    else
        harness_fail "MANIFEST_CHECKS_LOADED tracking missing"
    fi
}

test_doctor_lsof_version_probe_captures_stderr() {
    harness_section "Test: doctor lsof version probe captures stderr"

    local doctor_file="$REPO_ROOT/scripts/lib/doctor.sh"
    local probe_def=""
    probe_def="$(awk '
        /^doctor_version_probe\(\)[[:space:]]*\{/ { in_function = 1 }
        in_function { print }
        in_function && /^}[[:space:]]*$/ { exit }
    ' "$doctor_file")"

    if [[ -z "$probe_def" ]]; then
        harness_fail "doctor_version_probe function not found"
        return 1
    fi

    if ! grep -Fq 'merge "$exec_path" -v' "$doctor_file"; then
        harness_fail "lsof version path does not request stderr capture"
        return 1
    fi

    if bash -c "$probe_def"$'\n''doctor_version_probe "" 2 merge' >/dev/null 2>&1; then
        harness_fail "doctor_version_probe accepts calls without a command when timeout is unavailable"
        return 1
    else
        harness_pass "doctor_version_probe rejects calls without a command"
    fi

    local shadow_output=""
    shadow_output="$(bash -c "$probe_def"$'\n''head() { printf "%s\n" "shadowed-head"; }'$'\n''doctor_version_probe "" 2 merge /usr/bin/printf "%s\n%s\n" "real" "ignored"' 2>&1 || true)"
    if [[ "$shadow_output" == "real" ]]; then
        harness_pass "doctor_version_probe ignores shadowed head functions"
    else
        harness_fail "doctor_version_probe used a shadowed head function" "$shadow_output"
        return 1
    fi

    if [[ -x /usr/bin/lsof && -x /usr/bin/timeout ]]; then
        local output=""
        output="$(bash -c "$probe_def"$'\n''doctor_version_probe /usr/bin/timeout 2 merge /usr/bin/lsof -v' 2>&1 || true)"
        if [[ "$output" == "lsof version information:" ]]; then
            harness_pass "lsof -v stderr banner is captured"
        else
            harness_fail "lsof -v stderr banner was not captured" "$output"
        fi
    else
        harness_pass "lsof/timeout unavailable; static stderr-capture path is present"
    fi
}

test_fix_suggestion_builder_exists() {
    harness_section "Test: Fix suggestion builder exists"

    local doctor_file="$REPO_ROOT/scripts/lib/doctor.sh"

    # Check for build_fix_suggestion function
    if grep -q 'build_fix_suggestion()' "$doctor_file"; then
        harness_pass "build_fix_suggestion function exists"
    else
        harness_fail "build_fix_suggestion function missing"
        return 1
    fi

    # Check for fix_for_module helper
    if grep -q 'fix_for_module()' "$doctor_file"; then
        harness_pass "fix_for_module helper exists"
    else
        harness_fail "fix_for_module helper missing"
    fi
}

test_fix_suggestion_format() {
    harness_section "Test: Fix suggestions have correct format"

    # Get fix suggestions from actual doctor JSON output (more realistic test)
    local output
    ensure_doctor_json_output
    output="$DOCTOR_JSON_OUTPUT"

    # Extract an install-style fix suggestion from the output.
    # Some checks legitimately emit manual repair hints (for example,
    # `am doctor repair --yes`) before the install suggestions, so the test
    # must not assume the first fix is always a curl installer command.
    local fix_output
    fix_output=$(echo "$output" | jq -r '[.checks[] | select(.fix and (.fix | test("curl -fsSL")))] | .[0].fix // empty' 2>/dev/null)

    if [[ -z "$fix_output" ]]; then
        harness_fail "No install-style fix suggestions found in doctor output"
        harness_capture_output "doctor_output" "$output"
        return 1
    fi

    # Check fix output has expected components
    if echo "$fix_output" | grep -q 'curl -fsSL'; then
        harness_pass "Fix suggestion uses curl"
    else
        harness_fail "Fix suggestion missing curl"
        harness_capture_output "fix_output" "$fix_output"
        return 1
    fi

    if echo "$fix_output" | grep -q 'agent-flywheel.com/install'; then
        harness_pass "Fix suggestion uses correct URL"
    else
        harness_fail "Fix suggestion missing correct URL"
    fi

    if echo "$fix_output" | grep -q '\-\-yes'; then
        harness_pass "Fix suggestion has --yes flag"
    else
        harness_fail "Fix suggestion missing --yes flag"
    fi

    if echo "$fix_output" | grep -q '\-\-mode'; then
        harness_pass "Fix suggestion has --mode flag"
    else
        harness_fail "Fix suggestion missing --mode flag"
    fi

    # Check that fix suggestions include --only with a module ID pattern
    if echo "$fix_output" | grep -qE '\-\-only [a-z]+\.[a-z]+'; then
        harness_pass "Fix suggestion has --only with module ID"
    else
        harness_fail "Fix suggestion missing --only with module ID"
        harness_capture_output "fix_output" "$fix_output"
    fi
}

test_doctor_json_includes_fix_hints() {
    harness_section "Test: Doctor JSON output includes fix hints"

    local output
    ensure_doctor_json_output
    output="$DOCTOR_JSON_OUTPUT"

    # Check JSON is valid
    if echo "$output" | jq -e '.' >/dev/null 2>&1; then
        harness_pass "Doctor JSON output is valid"
    else
        harness_fail "Doctor JSON output is invalid"
        harness_capture_output "doctor_json_output" "$output"
        return 1
    fi

    # Check that checks array exists
    local check_count
    check_count=$(echo "$output" | jq '.checks | length' 2>/dev/null)
    if [[ "$check_count" -gt 30 ]]; then
        harness_pass "Doctor reports $check_count checks"
    else
        harness_fail "Doctor reports too few checks ($check_count)"
    fi

    # Check that at least some checks have fix hints
    local fix_count
    fix_count=$(echo "$output" | jq '[.checks[] | select(.fix)] | length' 2>/dev/null)
    if [[ "$fix_count" -gt 0 ]]; then
        harness_pass "Doctor includes $fix_count fix hints"
    else
        harness_fail "Doctor includes no fix hints"
    fi
}

test_failed_checks_have_fix_hints() {
    harness_section "Test: Failed checks have fix hints"

    local output
    ensure_doctor_json_output
    output="$DOCTOR_JSON_OUTPUT"

    # Get failed checks
    local failed_checks
    failed_checks=$(echo "$output" | jq '[.checks[] | select(.status == "fail")]' 2>/dev/null)

    local failed_count
    failed_count=$(echo "$failed_checks" | jq 'length' 2>/dev/null || echo "0")

    if [[ "$failed_count" -eq 0 ]]; then
        harness_pass "No failed checks (all passing) - cannot test fix hints"
        return 0
    fi

    # Check that failed checks have fix hints
    local failed_with_fix
    failed_with_fix=$(echo "$failed_checks" | jq '[.[] | select(.fix)] | length' 2>/dev/null || echo "0")

    if [[ "$failed_with_fix" -eq "$failed_count" ]]; then
        harness_pass "All $failed_count failed checks have fix hints"
    else
        harness_fail "$failed_with_fix of $failed_count failed checks have fix hints"
        harness_capture_output "failed_checks" "$failed_checks"
    fi
}

test_warn_checks_have_fix_hints() {
    harness_section "Test: Warning checks have fix hints"

    local output
    ensure_doctor_json_output
    output="$DOCTOR_JSON_OUTPUT"

    # Get warning checks
    local warn_checks
    warn_checks=$(echo "$output" | jq '[.checks[] | select(.status == "warn")]' 2>/dev/null)

    local warn_count
    warn_count=$(echo "$warn_checks" | jq 'length' 2>/dev/null || echo "0")

    if [[ "$warn_count" -eq 0 ]]; then
        harness_pass "No warning checks - cannot test fix hints"
        return 0
    fi

    # Check that warning checks have fix hints
    local warn_with_fix
    warn_with_fix=$(echo "$warn_checks" | jq '[.[] | select(.fix)] | length' 2>/dev/null || echo "0")

    if [[ "$warn_with_fix" -ge "$((warn_count / 2))" ]]; then
        harness_pass "$warn_with_fix of $warn_count warning checks have fix hints"
    else
        harness_fail "Only $warn_with_fix of $warn_count warning checks have fix hints"
        harness_capture_output "warn_checks" "$warn_checks"
    fi
}

test_fix_hint_uses_module_id() {
    harness_section "Test: Fix hints use correct module IDs"

    local output
    ensure_doctor_json_output
    output="$DOCTOR_JSON_OUTPUT"

    # Sample a few installer-backed checks and verify fix hints reference
    # their module. Some modules intentionally return bespoke prose guidance
    # instead of an ACFS reinstall command, so skip those here.
    local samples
    samples=$(echo "$output" | jq -r '.checks[] | select(.fix and .id and (.fix | contains("agent-flywheel.com/install"))) | "\(.id)|\(.fix)"' 2>/dev/null | head -5)

    local checks_passed=0
    local checks_total=0

    while IFS='|' read -r check_id fix_hint; do
        [[ -z "$check_id" ]] && continue
        ((checks_total++))

        # Extract module ID from check ID (strip trailing .N suffix)
        local module_id
        module_id=$(echo "$check_id" | sed 's/\.[0-9]*$//')

        if echo "$fix_hint" | grep -q "\-\-only $module_id"; then
            ((checks_passed++))
        fi
    done <<< "$samples"

    if [[ "$checks_total" -eq 0 ]]; then
        harness_pass "No checks with fix hints to verify"
    elif [[ "$checks_passed" -eq "$checks_total" ]]; then
        harness_pass "All $checks_total sampled fix hints use correct module IDs"
    else
        harness_fail "Only $checks_passed of $checks_total fix hints use correct module IDs"
    fi
}

test_manifest_checks_have_required_fields() {
    harness_section "Test: Manifest checks have required fields"

    local checks_file="$REPO_ROOT/scripts/generated/doctor_checks.sh"

    # Extract first 5 checks and verify format
    local sample_checks
    sample_checks=$(grep -E '^\s+"[a-z]' "$checks_file" | head -5)

    local valid=0
    local total=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        ((total++))

        # Expected format: "id<TAB>description<TAB>command<TAB>required/optional"
        # Check for at least 3 tabs (4 fields)
        local tab_count
        tab_count=$(echo "$line" | tr -cd '\t' | wc -c)
        if [[ "$tab_count" -ge 3 ]]; then
            ((valid++))
        fi
    done <<< "$sample_checks"

    if [[ "$valid" -eq "$total" ]]; then
        harness_pass "All $total sampled manifest checks have correct format"
    else
        harness_fail "Only $valid of $total manifest checks have correct format"
    fi
}

test_doctor_summary_counts() {
    harness_section "Test: Doctor summary has correct counts"

    local output
    ensure_doctor_json_output
    output="$DOCTOR_JSON_OUTPUT"

    # Get summary counts
    local pass_count warn_count fail_count
    pass_count=$(echo "$output" | jq '.summary.pass // 0' 2>/dev/null)
    warn_count=$(echo "$output" | jq '.summary.warn // 0' 2>/dev/null)
    fail_count=$(echo "$output" | jq '.summary.fail // 0' 2>/dev/null)

    # Calculate expected totals from checks array
    local calc_pass calc_warn calc_fail
    calc_pass=$(echo "$output" | jq '[.checks[] | select(.status == "pass")] | length' 2>/dev/null)
    calc_warn=$(echo "$output" | jq '[.checks[] | select(.status == "warn")] | length' 2>/dev/null)
    calc_fail=$(echo "$output" | jq '[.checks[] | select(.status == "fail")] | length' 2>/dev/null)

    if [[ "$pass_count" -eq "$calc_pass" ]]; then
        harness_pass "Pass count matches: $pass_count"
    else
        harness_fail "Pass count mismatch: summary=$pass_count calculated=$calc_pass"
    fi

    if [[ "$warn_count" -eq "$calc_warn" ]]; then
        harness_pass "Warn count matches: $warn_count"
    else
        harness_fail "Warn count mismatch: summary=$warn_count calculated=$calc_warn"
    fi

    if [[ "$fail_count" -eq "$calc_fail" ]]; then
        harness_pass "Fail count matches: $fail_count"
    else
        harness_fail "Fail count mismatch: summary=$fail_count calculated=$calc_fail"
    fi
}

test_root_checks_preserve_target_context() {
    harness_section "Test: Root manifest checks preserve target context"

    local doctor_file checks_file
    doctor_file="$REPO_ROOT/scripts/lib/doctor.sh"
    checks_file="$REPO_ROOT/scripts/generated/doctor_checks.sh"

    if grep -Fq 'TARGET_USER="$target_user"' "$doctor_file" && grep -Fq 'TARGET_HOME="$target_home"' "$doctor_file"; then
        harness_pass "doctor.sh preserves TARGET_USER and TARGET_HOME for root checks"
    else
        harness_fail "doctor.sh does not preserve TARGET_USER and TARGET_HOME for root checks"
    fi

    if grep -Fq 'TARGET_USER="$target_user"' "$checks_file" && grep -Fq 'TARGET_HOME="$target_home"' "$checks_file"; then
        harness_pass "generated doctor_checks.sh preserves TARGET_USER and TARGET_HOME for root checks"
    else
        harness_fail "generated doctor_checks.sh does not preserve TARGET_USER and TARGET_HOME for root checks"
    fi
}

test_generated_manifest_checks_use_hardened_target_path() {
    harness_section "Test: Generated manifest checks use hardened target PATH"

    local checks_file="$REPO_ROOT/scripts/generated/doctor_checks.sh"

    if grep -Fq 'local system_path_prefix="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"' "$checks_file"; then
        harness_pass "generated doctor_checks.sh defines trusted system path prefix"
    else
        harness_fail "generated doctor_checks.sh does not define trusted system path prefix"
    fi

    if grep -Fq 'local -a target_path_entries=()' "$checks_file"         && grep -Fq 'target_path_prefix=$(IFS=:; echo "${target_path_entries[*]}")' "$checks_file"         && grep -Fq 'target_path="$target_path_prefix${PATH:+:$PATH}"' "$checks_file"; then
        harness_pass "generated doctor_checks.sh prefers trusted target PATH ordering"
    else
        harness_fail "generated doctor_checks.sh does not use hardened target PATH ordering"
    fi
}

test_generated_run_manifest_check_command_handles_unresolved_target_home_by_context() {
    harness_section "Test: Generated run_manifest_check_command only requires TARGET_HOME for target_user checks"

    local checks_file="$REPO_ROOT/scripts/generated/doctor_checks.sh"
    local temp_root=""
    temp_root="$(mktemp -d)"
    local fake_bin="$temp_root/fake-bin"
    local fake_home="$temp_root/fake-home"
    mkdir -p "$fake_bin" "$fake_home"

    cat > "$fake_bin/getent" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
    chmod +x "$fake_bin/getent"

    cat > "$fake_bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo-called=%s\n' "$*"
EOF
    chmod +x "$fake_bin/sudo"

    local root_output=""
    root_output=$(HOME="$fake_home" PATH="$fake_bin:/usr/bin:/bin" TARGET_USER=customuser bash -c '
        source "'"$checks_file"'"
        run_manifest_check_command root "printf \"%s\\n\" root-check-ran"
    ' 2>&1 || true)

    if [[ "$root_output" == *"root-check-ran"* ]] && [[ "$root_output" != *"Unable to resolve TARGET_HOME"* ]]; then
        harness_pass "root checks still dispatch when TARGET_HOME is unresolved"
    else
        harness_fail "root checks still dispatch when TARGET_HOME is unresolved" "$root_output"
    fi

    local target_user_output=""
    target_user_output=$(HOME="$fake_home" PATH="$fake_bin:/usr/bin:/bin" TARGET_USER=customuser bash -c '
        source "'"$checks_file"'"
        run_manifest_check_command target_user "printf target-user-check-ran\\n"
    ' 2>&1 || true)

    if [[ "$target_user_output" == *"Invalid TARGET_HOME for 'customuser': <empty> (must be an absolute path and cannot be '/')"* ]] \
        && [[ "$target_user_output" != *"sudo-called="* ]]; then
        harness_pass "target_user checks fail closed when TARGET_HOME is unresolved"
    else
        harness_fail "target_user checks fail closed when TARGET_HOME is unresolved" "$target_user_output"
    fi

    rm -rf "$temp_root"
}

test_workspace_checks_are_not_required_health_failures() {
    harness_section "Test: Workspace onboarding checks are not required health failures"

    local doctor_file checks_file output
    doctor_file="$REPO_ROOT/scripts/lib/doctor.sh"
    checks_file="$REPO_ROOT/scripts/generated/doctor_checks.sh"

    if grep -Eq 'acfs\.workspace\|acfs\.workspace\.\*' "$doctor_file"; then
        harness_pass "doctor.sh suppresses manifest duplicates for acfs.workspace"
    else
        harness_fail "doctor.sh does not suppress manifest duplicates for acfs.workspace"
    fi

    if grep -F 'acfs.workspace.1' "$checks_file" | grep -Fq $'\toptional\t'; then
        harness_pass "generated acfs.workspace checks are optional"
    else
        harness_fail "generated acfs.workspace checks are still required"
    fi

    ensure_doctor_json_output
    output="$DOCTOR_JSON_OUTPUT"
    local workspace_check_count
    workspace_check_count=$(echo "$output" | jq '[.checks[] | select(.id | startswith("acfs.workspace"))] | length' 2>/dev/null || echo "0")
    if [[ "$workspace_check_count" -eq 0 ]]; then
        harness_pass "doctor output no longer surfaces acfs.workspace onboarding checks"
    else
        harness_fail "doctor output still surfaces acfs.workspace onboarding checks"
        harness_capture_output "doctor_json_output" "$output"
    fi
}

test_base_filesystem_3_verify_runs_with_injected_helpers() {
    harness_section "Test: base.filesystem.3 verify uses injected helper resolution"

    local checks_file="$REPO_ROOT/scripts/generated/doctor_checks.sh"
    if [[ ! -f "$checks_file" ]]; then
        harness_fail "doctor_checks.sh not found at $checks_file"
        return
    fi

    # Extract the encoded command for base.filesystem.3 from the
    # MANIFEST_CHECKS array. The bash array entries contain literal
    # \" sequences (escaped quotes), so awk -v RS='"' would split
    # mid-entry and silently truncate the command to a comment-only
    # prefix — the test would then "pass" by running an empty
    # script. Source the file in a clean subshell instead and pull
    # the entry directly from the array.
    local entry=""
    entry="$(bash -c "
        set -euo pipefail
        source ${checks_file@Q}
        for e in \"\${MANIFEST_CHECKS[@]}\"; do
            if [[ \"\$e\" == 'base.filesystem.3'\$'\\t'* ]]; then
                printf '%s' \"\$e\"
                exit 0
            fi
        done
        exit 1
    ")"
    if [[ -z "$entry" ]]; then
        harness_fail "could not extract base.filesystem.3 entry from $checks_file"
        return
    fi

    # Strip leading "base.filesystem.3\t<desc>\t" and trailing
    # "\trequired\troot" to isolate the command body, then decode
    # the embedded \\n \" \$ etc. via printf %b — same way the
    # doctor decodes manifest commands.
    local rest="${entry#base.filesystem.3$'\t'}"  # strip id
    rest="${rest#*$'\t'}"                          # strip desc
    local encoded_cmd="${rest%$'\t'required$'\t'root}"
    local cmd=""
    cmd="$(printf '%b' "$encoded_cmd")"

    # Sanity: the decoded body must contain the actual verify
    # logic (test -d "$target_home/.acfs"). If it doesn't, the
    # extraction broke and we'd false-pass on a stub.
    if [[ "$cmd" != *'test -d "$target_home/.acfs"'* ]]; then
        harness_fail "decoded base.filesystem.3 body is missing the verify line — extraction is broken" \
            "first 400 chars: ${cmd:0:400}"
        return
    fi

    local temp_root=""
    temp_root="$(mktemp -d)"
    mkdir -p "$temp_root/.acfs"

    # The generated doctor runner injects these helpers before manifest
    # commands that reference acfs_generated_* functions. Keep this harness
    # minimal, but model that real execution path so the test does not pass by
    # trusting inherited TARGET_HOME directly.
    local helper_prelude=""
    helper_prelude='
acfs_generated_getent_passwd_entry() {
    local user="${1:-}"
    [[ -n "$user" && -n "${ACFS_TEST_PASSWD_HOME:-}" ]] || return 1
    printf "%s:x:1000:1000::%s:/bin/bash\n" "$user" "$ACFS_TEST_PASSWD_HOME"
}
acfs_generated_passwd_home_from_entry() {
    local entry="${1:-}"
    local home=""
    [[ -n "$entry" ]] || return 1
    IFS=: read -r _ _ _ _ _ home _ <<< "$entry"
    [[ -n "$home" && "$home" == /* && "$home" != "/" ]] || return 1
    printf "%s\n" "${home%/}"
}
acfs_generated_resolve_current_user() {
    [[ -n "${USER:-}" ]] || return 1
    printf "%s\n" "$USER"
}
'
    local wrapped_cmd="${helper_prelude}"$'\n'"${cmd}"

    local output=""
    output="$(env -i \
        PATH="/usr/local/bin:/usr/bin:/bin" \
        TARGET_USER="$(id -un)" \
        TARGET_HOME="$temp_root/stale-home" \
        ACFS_TEST_PASSWD_HOME="$temp_root" \
        bash -o pipefail -c "$wrapped_cmd" 2>&1)"
    local rc=$?

    if [[ $rc -eq 0 ]]; then
        harness_pass "base.filesystem.3 repairs stale TARGET_HOME through passwd helper data"
    else
        harness_fail "base.filesystem.3 fails with stale TARGET_HOME despite helper data (rc=$rc)" "$output"
    fi

    # Same again, but WITHOUT TARGET_HOME — exercise the injected passwd
    # fallback for callers that don't pre-resolve.
    output="$(env -i \
        PATH="/usr/local/bin:/usr/bin:/bin" \
        TARGET_USER="$(id -un)" \
        ACFS_TEST_PASSWD_HOME="$temp_root" \
        USER="$(id -un)" \
        HOME="$temp_root" \
        bash -o pipefail -c "$wrapped_cmd" 2>&1)"
    rc=$?

    if [[ $rc -eq 0 ]]; then
        harness_pass "base.filesystem.3 falls back to getent / HOME when TARGET_HOME is unset"
    else
        harness_fail "base.filesystem.3 fallback path failed (rc=$rc)" "$output"
    fi

    # Negative test: with no TARGET_HOME, no matching USER, and
    # no HOME, the verify must FAIL CLOSED — the prior
    # implementation could silently succeed in some environments.
    # Run without `|| true` so $? captures bash -c's actual exit.
    output="$(env -i \
        PATH="/usr/local/bin:/usr/bin:/bin" \
        TARGET_USER="nonexistent_user_that_should_not_exist_anywhere_xyz" \
        bash -o pipefail -c "$wrapped_cmd" 2>&1)"
    rc=$?
    if [[ $rc -ne 0 ]] && [[ "$output" == *"Unable to resolve TARGET_HOME"* ]]; then
        harness_pass "base.filesystem.3 fails closed with explanatory error when nothing resolves"
    else
        harness_fail "base.filesystem.3 should fail closed with diagnostic when no resolution path works" \
            "rc=$rc output: $output"
    fi

    rm -rf "$temp_root"
}

test_generated_target_home_fallbacks_are_dynamic() {
    harness_section "Test: Generated target-home fallbacks are dynamic"

    local doctor_file filesystem_file stack_file
    doctor_file="$REPO_ROOT/scripts/generated/doctor_checks.sh"
    filesystem_file="$REPO_ROOT/scripts/generated/install_filesystem.sh"
    stack_file="$REPO_ROOT/scripts/generated/install_stack.sh"

    if grep -Fq '${TARGET_HOME:-/home/ubuntu}' "$doctor_file"; then
        harness_fail "doctor_checks.sh still hardcodes /home/ubuntu for TARGET_HOME fallback"
    else
        harness_pass "doctor_checks.sh no longer hardcodes /home/ubuntu for TARGET_HOME fallback"
    fi

    if grep -Fq 'target_home="/home/$target_user"' "$doctor_file"; then
        harness_fail "doctor_checks.sh still guesses /home/\$target_user in run_manifest_check_command"
    else
        harness_pass "doctor_checks.sh no longer guesses /home/\$target_user in run_manifest_check_command"
    fi

    if grep -Fq '${TARGET_HOME:-/home/ubuntu}' "$filesystem_file"; then
        harness_fail "install_filesystem.sh still hardcodes /home/ubuntu for TARGET_HOME fallback"
    else
        harness_pass "install_filesystem.sh no longer hardcodes /home/ubuntu for TARGET_HOME fallback"
    fi

    if grep -Fq '${TARGET_HOME:-/home/ubuntu}' "$stack_file"; then
        harness_fail "install_stack.sh still hardcodes /home/ubuntu for TARGET_HOME fallback"
    else
        harness_pass "install_stack.sh no longer hardcodes /home/ubuntu for TARGET_HOME fallback"
    fi

    if grep -Fq 'acfs_generated_getent_passwd_entry "${TARGET_USER:-ubuntu}"' "$filesystem_file"; then
        harness_pass "install_filesystem.sh resolves TARGET_HOME through getent when unset"
    else
        harness_fail "install_filesystem.sh does not resolve TARGET_HOME through getent when unset"
    fi
}

test_meta_skill_arm64_linux_guidance() {
    harness_section "Test: meta_skill ARM64 Linux guidance is specific"

    local doctor_file arm64_branch
    doctor_file="$REPO_ROOT/scripts/lib/doctor.sh"
    arm64_branch="$(sed -n '/aarch64-Linux|arm64-Linux)/,/;;/p' "$doctor_file")"

    if [[ -z "$arm64_branch" ]]; then
        harness_fail "meta_skill ARM64 Linux branch is missing from doctor.sh"
        return 1
    fi

    if echo "$arm64_branch" | grep -q 'ARM64 Linux binary not yet available (see https://github.com/Dicklesworthstone/meta_skill/issues/1)'; then
        harness_pass "meta_skill ARM64 Linux warning includes the upstream issue link"
    else
        harness_fail "meta_skill ARM64 Linux warning is missing the specific upstream guidance"
        harness_capture_output "meta_skill_arm64_branch" "$arm64_branch"
    fi

    if echo "$arm64_branch" | grep -q 'No checksum-anchored Linux ARM64 installer is available; wait for a verified release artifact'; then
        harness_pass "meta_skill ARM64 Linux guidance fails closed without an anchored source"
    else
        harness_fail "meta_skill ARM64 Linux guidance does not explain the anchored-source requirement"
        harness_capture_output "meta_skill_arm64_branch" "$arm64_branch"
    fi

    if echo "$arm64_branch" | grep -q 'curl -fsSL'; then
        harness_fail "meta_skill ARM64 Linux branch still suggests the raw installer path"
        harness_capture_output "meta_skill_arm64_branch" "$arm64_branch"
    else
        harness_pass "meta_skill ARM64 Linux branch avoids the raw installer path"
    fi
}

test_manifest_supplemental_coverage_is_precise() {
    harness_section "Test: Manifest supplemental coverage keeps intended checks"

    local output
    ensure_doctor_json_output
    output="$DOCTOR_JSON_OUTPUT"

    local postgres_service_count
    postgres_service_count=$(echo "$output" | jq '[.checks[] | select(.id == "db.postgres18.2")] | length' 2>/dev/null || echo "0")
    if [[ "$postgres_service_count" -eq 1 ]]; then
        harness_pass "PostgreSQL service health check remains in doctor output"
    else
        harness_fail "PostgreSQL service health check is missing from doctor output"
        harness_capture_output "doctor_json_output" "$output"
    fi

    local agent_mail_supplemental_count
    agent_mail_supplemental_count=$(echo "$output" | jq '[.checks[] | select(.id == "stack.mcp_agent_mail.2")] | length' 2>/dev/null || echo "0")
    if [[ "$agent_mail_supplemental_count" -eq 0 ]]; then
        harness_pass "Agent Mail supplemental duplicate remains suppressed"
    else
        harness_fail "Agent Mail supplemental duplicate leaked into doctor output"
        harness_capture_output "doctor_json_output" "$output"
    fi

    local agent_mail_bespoke_count
    agent_mail_bespoke_count=$(echo "$output" | jq '[.checks[] | select(.id == "stack.mcp_agent_mail")] | length' 2>/dev/null || echo "0")
    if [[ "$agent_mail_bespoke_count" -eq 1 ]]; then
        harness_pass "Agent Mail bespoke check is still present"
    else
        harness_fail "Agent Mail bespoke check is missing from doctor output"
        harness_capture_output "doctor_json_output" "$output"
    fi
}

test_manifest_guard_scripts_cover_all_generated_outputs() {
    harness_section "Test: Manifest guard scripts cover all generated outputs"

    local hook_file="$REPO_ROOT/scripts/hooks/pre-commit"
    local drift_file="$REPO_ROOT/scripts/check-manifest-drift.sh"
    local ledger_guard=""

    if grep -Fq 'git add apps/web/lib/generated/' "$hook_file"; then
        harness_pass "Pre-commit hook stages apps/web/lib/generated/"
    else
        harness_fail "Pre-commit hook does not stage apps/web/lib/generated/"
    fi

    ledger_guard="$(sed -n '/^# Internal checksum ledger guard/,$p' "$hook_file")"
    if [[ "$ledger_guard" == *'ledger_is_staged=false'* ]] \
        && [[ "$ledger_guard" == *'ledger_is_staged=true'* ]] \
        && [[ "$ledger_guard" == *'git show "HEAD:$LEDGER_PATH"'* ]] \
        && [[ "$ledger_guard" == *'git diff --name-only --diff-filter=ACMRD'* ]] \
        && [[ "$ledger_guard" == *'Cannot verify the checksum ledger with unstaged covered changes'* ]] \
        && [[ "$ledger_guard" == *'Checksum-covered files are staged for deletion'* ]]; then
        harness_pass "Checksum ledger guard keeps staged and working-tree snapshots separate"
    else
        harness_fail "Checksum ledger guard can mix staged and working-tree snapshots"
    fi

    if [[ "$ledger_guard" != *'bun run generate'* ]] \
        && [[ "$ledger_guard" != *'git add -- "$LEDGER_PATH"'* ]]; then
        harness_pass "Checksum ledger guard verifies without mutating the index or working tree"
    else
        harness_fail "Checksum ledger guard mutates repository state during verification"
    fi

    if grep -q 'bun run generate:diff' "$drift_file"; then
        harness_pass "Manifest drift check validates generated artifacts via generate:diff"
    else
        harness_fail "Manifest drift check does not validate generated artifacts via generate:diff"
    fi

    if grep -Fq 'src/drift-contract.ts --json --root "$REPO_ROOT"' "$drift_file" \
        && grep -Fq 'manifest_contract' "$drift_file"; then
        harness_pass "Manifest drift check validates semantic manifest contract"
    else
        harness_fail "Manifest drift check does not validate semantic manifest contract"
    fi

    if grep -Fq 'EXPECTED_AGENT_MAIL_MCP_URL="http://127.0.0.1:8765/mcp/"' "$drift_file" \
        && ! grep -Fq 'am --version' "$drift_file"; then
        harness_pass "Manifest drift check uses deterministic repo MCP URL"
    else
        harness_fail "Manifest drift check still depends on local Agent Mail CLI version"
    fi

    if grep -Fq '${#INTERNAL_CHECKSUM_PATHS[@]} -ne "$INTERNAL_CHECKSUMS_EXPECTED_COUNT"' "$drift_file" \
        && grep -Fq 'INTERNAL_DRIFT_FILES+=("internal checksum index (parsed ${#INTERNAL_CHECKSUM_PATHS[@]} of expected $INTERNAL_CHECKSUMS_EXPECTED_COUNT)")' "$drift_file" \
        && grep -Fq 'Internal checksum index malformed: parsed ${#INTERNAL_CHECKSUM_PATHS[@]} of expected $INTERNAL_CHECKSUMS_EXPECTED_COUNT entries' "$drift_file"; then
        harness_pass "Manifest drift check fails closed on partial internal checksum parsing"
    else
        harness_fail "Manifest drift check can silently lose internal checksum coverage"
    fi

    if grep -Fq 'verified-installer checksum validation' "$drift_file" \
        && grep -Fq 'checksums.yaml' "$drift_file"; then
        harness_pass "Manifest drift auto-fix refuses dirty checksum source"
    else
        harness_fail "Manifest drift auto-fix can validate against uncommitted checksums.yaml"
    fi

    local drift_output=""
    local drift_status=0
    drift_output=$(PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        "$drift_file" --json --quiet 2>&1) || drift_status=$?
    if [[ "$drift_status" -eq 0 ]] \
        && echo "$drift_output" | jq -e '
            .repo_mcp_configs.expected_url == "http://127.0.0.1:8765/mcp/" and
            .repo_mcp_configs.drifted == 0 and
            .manifest_contract.drifted == 0 and
            (
                (.manifest_contract.status == "clean" and .manifest_contract.checked > 0) or
                .manifest_contract.status == "skipped"
            )
        ' >/dev/null 2>&1; then
        harness_pass "Manifest drift check passes when am is absent from PATH"
    else
        harness_fail "Manifest drift check should not require am in PATH"
        harness_capture_output "manifest_drift_without_am" "$drift_output"
    fi
}

# ============================================================
# Main
# ============================================================

main() {
    harness_init "Doctor Generated Checks Tests"

    harness_info "Log file: $LOG_FILE"

    # Run tests
    test_generated_checks_file_exists
    test_doctor_sources_generated_checks
    test_doctor_lsof_version_probe_captures_stderr
    test_fix_suggestion_builder_exists
    test_fix_suggestion_format
    test_doctor_json_includes_fix_hints
    test_failed_checks_have_fix_hints
    test_warn_checks_have_fix_hints
    test_fix_hint_uses_module_id
    test_manifest_checks_have_required_fields
    test_doctor_summary_counts
    test_root_checks_preserve_target_context
    test_generated_manifest_checks_use_hardened_target_path
    test_generated_run_manifest_check_command_handles_unresolved_target_home_by_context
    test_base_filesystem_3_verify_runs_with_injected_helpers
    test_workspace_checks_are_not_required_health_failures
    test_generated_target_home_fallbacks_are_dynamic
    test_meta_skill_arm64_linux_guidance
    test_manifest_supplemental_coverage_is_precise
    test_manifest_guard_scripts_cover_all_generated_outputs

    # Summary
    harness_section "Test Summary"
    harness_info "Log written to: $LOG_FILE"

    harness_summary
}

main "$@"
