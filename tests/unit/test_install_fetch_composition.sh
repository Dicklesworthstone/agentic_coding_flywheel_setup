#!/usr/bin/env bash
# ============================================================
# Composition proof across five same-day changes to the flywheel installer:
#   1. cache-buster removal (8433cd3f, README/install.sh)
#   2. cache-bust only for mutable refs (da50d8d7)
#   3. HTTP 429/503 retry classification (7a59cb29, scripts/lib/security.sh)
#   4. resolve-ref-to-SHA-once-per-run (64a5a6e8, install.sh)
#   5. record-and-continue + EXIT trap (faeeab8e, install.sh)
# (cm doctor timeout 131beac1 is a manifest-only change to an unrelated
# optional verify step; not part of the fetch/retry/abort chain, so it is
# not exercised here.)
#
# All against REAL, unmodified install.sh / scripts/lib/security.sh /
# scripts/lib/install_helpers.sh / scripts/generated/install_stack.sh.
# Network calls are REAL, over real HTTPS, using the real system curl
# binary (which the code resolves via hardcoded absolute paths only —
# /usr/bin/curl etc. — so it cannot be shadowed via PATH; a locally-hosted
# HTTPS stub was therefore not an option without installing a CA into the
# system trust store, which this test deliberately does not do). Instead of
# a local stub, controllable real HTTP statuses are sourced from
# httpbin.org (429/503/200 on demand) — a real second host, not GitHub, so
# this exercises the real curl + real retry-classification code without
# hammering GitHub or depending on being able to provoke a real rate limit
# there. What's stubbed and what's not is called out at each step.
# Network-dependent (Part B and Part C both need httpbin.org reachable, and
# Part B2/B4/C1 each take ~20s of real retry backoff -- the whole run is
# ~60-90s). Honors this repo's SKIP_NETWORK_TESTS convention (see
# tests/unit/test_github_api.sh) for CI/offline runs; also self-skips with a
# clear message (not a silent pass) if httpbin.org specifically is
# unreachable even when network tests are not globally skipped.
# ============================================================
set -uo pipefail

if [[ "${SKIP_NETWORK_TESTS:-false}" == "true" ]]; then
    echo "SKIPPED (SKIP_NETWORK_TESTS=true): this test needs real network to httpbin.org."
    exit 0
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/acfs-composition-proof.XXXXXX")"
cleanup_tmproot() { rm -rf "$TMPROOT"; }
trap cleanup_tmproot EXIT
mkdir -p "$TMPROOT"

FAIL=0
assert() {
    local desc="$1" cond="$2"
    if [[ "$cond" == "true" ]]; then
        echo "PASS: $desc"
    else
        echo "FAIL: $desc"
        FAIL=1
    fi
}
note() { echo "NOTE: $1"; }

SOURCEABLE="$TMPROOT/install_sourceable.sh"
total_lines="$(wc -l < "$REPO_ROOT/install.sh")"
last_line="$(tail -n 1 "$REPO_ROOT/install.sh")"
if [[ "$last_line" != 'main "$@"' ]]; then
    echo "FATAL: install.sh's last line changed shape; update this test's truncation assumption." >&2
    exit 2
fi
head -n "$((total_lines - 1))" "$REPO_ROOT/install.sh" > "$SOURCEABLE"
ln -sfn "$REPO_ROOT/scripts" "$TMPROOT/scripts"
ln -sfn "$REPO_ROOT/acfs" "$TMPROOT/acfs"
ln -sfn "$REPO_ROOT/checksums.yaml" "$TMPROOT/checksums.yaml"
ln -sfn "$REPO_ROOT/acfs.manifest.yaml" "$TMPROOT/acfs.manifest.yaml"

TARGET_USER="$(whoami)"
TARGET_HOME="$HOME"
MODE="vibe"
HAS_GUM=false
YES_MODE=true
# shellcheck disable=SC1090
source "$SOURCEABLE"
detect_environment
# install.sh's own `set -euo pipefail` is now active in this shell (it leaks
# in via sourcing above). Every step below intentionally exercises failure
# paths and checks their real, nonzero exit codes — under -e a bare
# nonzero-returning statement would abort this whole test script, so -e is
# turned off here (same reasoning install.sh's own cleanup() uses `set +e`
# for). All assertions still check real, explicitly captured exit codes.
set +e

echo "=============================================="
echo "PART A: SHA resolution success/failure does not corrupt or block the"
echo "        retry logic, in either direction (real network for the good"
echo "        case; a nonexistent repo, still real DNS+HTTP, for the failing"
echo "        case)."
echo "=============================================="

echo "-- A1: resolve a real ref against the real repo --"
sha_main="$(acfs_resolve_ref_sha "main")"
assert "A1. acfs_resolve_ref_sha resolves 'main' to a real 40-char SHA" \
    "$([[ "$sha_main" =~ ^[0-9a-f]{40}$ ]] && echo true || echo false)"
note "resolved main -> $sha_main"

eff_main="$(acfs_effective_ref "main")"
cb_main="$(acfs_cache_buster_suffix "$eff_main")"
assert "A2. cache-buster is empty for the resolved (immutable) ref" "$([[ -z "$cb_main" ]] && echo true || echo false)"

echo
echo "-- A3: force SHA resolution to fail (nonexistent owner/repo, real DNS+HTTP) --"
# Bare (unexported) assignment does not cross into a `bash -c` child process,
# so both env vars are passed inline on the command itself — the same style
# used for eff_bad below, which is what actually makes the child see them.
sha_bad="$(ACFS_REPO_OWNER="acfs-composition-test-nonexistent-owner-8f2b1c" ACFS_REPO_NAME="acfs-composition-test-nonexistent-repo-8f2b1c" \
    timeout 30 bash -c 'source "'"$SOURCEABLE"'" >/dev/null 2>&1; acfs_resolve_ref_sha "main" 2>/dev/null')"
assert "A3. resolution against a nonexistent repo degrades to empty (no crash, no hang)" \
    "$([[ -z "$sha_bad" ]] && echo true || echo false)"

eff_bad="$(ACFS_REPO_OWNER="acfs-composition-test-nonexistent-owner-8f2b1c" ACFS_REPO_NAME="acfs-composition-test-nonexistent-repo-8f2b1c" bash -c 'source "'"$SOURCEABLE"'"; acfs_effective_ref "main"')"
cb_bad="$(acfs_cache_buster_suffix "$eff_bad")"
assert "A4. failed resolution falls back to the raw ref ('main'), not empty/garbage" "$([[ "$eff_bad" == "main" ]] && echo true || echo false)"
assert "A5. failed resolution correctly RE-APPLIES the cache-buster (still mutable)" "$([[ -n "$cb_bad" ]] && echo true || echo false)"

echo
echo "-- A6: resolving a SECOND, real ref after a failed resolution doesn't leak state --"
ACFS_REPO_OWNER="Dicklesworthstone"
ACFS_REPO_NAME="agentic_coding_flywheel_setup"
sha_main_again="$(acfs_resolve_ref_sha "main")"
assert "A6. a real ref resolved after an unrelated failure still resolves correctly" \
    "$([[ "$sha_main_again" == "$sha_main" ]] && echo true || echo false)"

echo
echo "=============================================="
echo "PART B: the retry logic itself, exercised over REAL HTTPS via"
echo "        httpbin.org (a real, independent host — not GitHub, and not a"
echo "        stubbed curl; the real system curl binary hits it for real)."
echo "        This directly tests whether 'a fetch now goes through SHA"
echo "        resolution, then a retrying curl' actually retries on EVERY"
echo "        call site that fetch composition touches."
echo "=============================================="

command -v curl >/dev/null 2>&1 || { echo "FATAL: curl required"; exit 2; }
if ! timeout 8 curl -sS -o /dev/null -w '%{http_code}' https://httpbin.org/status/200 2>/dev/null | grep -q 200; then
    echo "SKIPPED (network to httpbin.org unavailable in this environment): Part B, Part C real-fetch legs."
    echo "Everything below this line that depends on httpbin.org is marked SKIP, not silently omitted."
    HTTPBIN_OK=false
else
    HTTPBIN_OK=true
fi

if [[ "$HTTPBIN_OK" == "true" ]]; then
    echo "-- B1: install.sh's own acfs_curl_with_retry() -- the function used by"
    echo "   bootstrap_repo_archive() (the curl|bash archive fetch) and by"
    echo "   acfs_download_file_and_verify_sha256() (lazygit/lazydocker) --"
    echo "   against a URL that ALWAYS returns 429 --"
    b1_out="$TMPROOT/b1_out"
    b1_start=$(date +%s)
    acfs_curl_with_retry "https://httpbin.org/status/429" "$b1_out" > "$TMPROOT/b1.log" 2>&1
    b1_rc=$?
    b1_end=$(date +%s)
    b1_elapsed=$((b1_end - b1_start))
    echo "   rc=$b1_rc elapsed=${b1_elapsed}s"
    sed 's/^/   | /' "$TMPROOT/b1.log"
    b1_retried="false"
    grep -qi "retry\|HTTP 429" "$TMPROOT/b1.log" && b1_retried="true"
    assert "B1. acfs_curl_with_retry on a persistent 429: DOES retry with backoff (elapsed >= 15s, HTTP 429 logged) — this was the composition GAP (still fatal-on-first-429 as of 229a14ee), now closed" \
        "$([[ "$b1_elapsed" -ge 15 && "$b1_retried" == "true" ]] && echo true || echo false)"

    echo
    echo "-- B2: security.sh's verify_checksum() / acfs_download_to_file() -- the"
    echo "   function used by essentially every manifest-driven module install"
    echo "   (stack.*, agents.*, etc. via verify_checksum) -- against the SAME"
    echo "   persistent-429 URL --"
    b2_log="$TMPROOT/b2.log"
    b2_start=$(date +%s)
    verify_checksum "https://httpbin.org/status/429" "0000000000000000000000000000000000000000000000000000000000000000" "composition-test-429" > "$b2_log" 2>&1
    b2_rc=$?
    b2_end=$(date +%s)
    b2_elapsed=$((b2_end - b2_start))
    echo "   rc=$b2_rc elapsed=${b2_elapsed}s"
    sed 's/^/   | /' "$b2_log"
    b2_retried="false"
    grep -qi "retry" "$b2_log" && b2_retried="true"
    assert "B2. verify_checksum on the SAME persistent 429: DOES retry (elapsed >= 15s, 'Retry' logged) — the fix's real mechanism" \
        "$([[ "$b2_elapsed" -ge 15 && "$b2_retried" == "true" ]] && echo true || echo false)"

    echo
    echo "-- B3: same comparison for HTTP 503 --"
    b3_out="$TMPROOT/b3_out"
    b3_start=$(date +%s)
    acfs_curl_with_retry "https://httpbin.org/status/503" "$b3_out" > "$TMPROOT/b3.log" 2>&1
    b3_elapsed=$(( $(date +%s) - b3_start ))
    b3_retried="false"
    grep -qi "retry\|HTTP 503" "$TMPROOT/b3.log" && b3_retried="true"
    assert "B3. acfs_curl_with_retry on persistent 503: also retried now (fix is not 429-specific)" \
        "$([[ "$b3_elapsed" -ge 15 && "$b3_retried" == "true" ]] && echo true || echo false)"

    b4_log="$TMPROOT/b4.log"
    b4_start=$(date +%s)
    verify_checksum "https://httpbin.org/status/503" "0000000000000000000000000000000000000000000000000000000000000000" "composition-test-503" > "$b4_log" 2>&1
    b4_elapsed=$(( $(date +%s) - b4_start ))
    b4_retried="false"
    grep -qi "retry" "$b4_log" && b4_retried="true"
    assert "B4. verify_checksum on persistent 503: DOES retry" \
        "$([[ "$b4_elapsed" -ge 15 && "$b4_retried" == "true" ]] && echo true || echo false)"
else
    note "B1-B4 SKIPPED: no network to httpbin.org from this sandbox."
fi

echo
echo "=============================================="
echo "PART C: composed abort path — a REAL fetch-exhaustion failure (not a"
echo "        return-1 stand-in) feeding into record-and-continue, still"
echo "        reaching skills install and the summary; and what the summary"
echo "        actually shows for it."
echo "=============================================="

if [[ "$HTTPBIN_OK" == "true" ]]; then
    source_generated_installers
    declare -f acfs_generated_install_stack_ntm >/dev/null 2>&1 || { echo "FATAL: real acfs_generated_install_stack_ntm not loaded"; exit 2; }
    declare -f acfs_generated_install_stack_meta_skill >/dev/null 2>&1 || { echo "FATAL: real acfs_generated_install_stack_meta_skill not loaded"; exit 2; }

    # The one deliberate substitution, and it's a narrower one than before:
    # only the URL acfs_generated_install_stack_ntm's real verify_checksum() call targets is
    # redirected to the persistent-429 endpoint. Every other line — the
    # verify_checksum call itself, the retry loop inside it, the record/log
    # calls, the return path — is the REAL, unmodified function body.
    real_ntm_body="$(declare -f acfs_generated_install_stack_ntm)"
    eval "${real_ntm_body/acfs_generated_install_stack_ntm/__real_acfs_generated_install_stack_ntm}"
    acfs_generated_install_stack_ntm() {
        local module_id="stack.ntm"
        acfs_require_contract "module:${module_id}" || return 1
        acfs_generated_ensure_selection || return 1
        if ! should_run_module "${module_id}"; then
            log_info "Skipping stack.ntm (not selected)"
            return 0
        fi
        log_step "Installing stack.ntm"
        # Real verify_checksum(), real retry loop, pointed at a URL that will
        # never stop returning 429 — a genuine fetch-exhaustion failure, not
        # a hand-written `return 1`.
        if ! verify_checksum "https://httpbin.org/status/429" "0000000000000000000000000000000000000000000000000000000000000000" "stack.ntm"; then
            log_error "stack.ntm: verified installer failed"
            return 1
        fi
        log_success "stack.ntm installed"
    }

    export ACFS_FORCE_REINSTALL=true
    DRY_RUN=true
    acfs_generated_ensure_selection || { echo "FATAL: acfs_generated_ensure_selection failed"; exit 2; }

    category_log="$TMPROOT/category_phase.log"
    category_rc=0
    c_start=$(date +%s)
    acfs_run_generated_category_phase "stack" "9" > "$category_log" 2>&1 || category_rc=$?
    c_elapsed=$(( $(date +%s) - c_start ))
    echo "   acfs_run_generated_category_phase rc=$category_rc elapsed=${c_elapsed}s"
    echo "   ACFS_MODULE_FAILURES = (${ACFS_MODULE_FAILURES[*]:-<empty>})"

    meta_skill_ran="false"
    grep -q "stack.meta_skill installed" "$category_log" && meta_skill_ran="true"
    ntm_recorded="false"
    ntm_recorded_reason=""
    for f in "${ACFS_MODULE_FAILURES[@]:-}"; do
        [[ "$f" == stack.ntm* ]] && { ntm_recorded="true"; ntm_recorded_reason="$f"; }
    done
    retries_happened="false"
    grep -qi "retry" "$category_log" && retries_happened="true"

    assert "C1. the induced failure really did exhaust retries (took >= 15s, 'Retry' logged in the category run, not an instant return-1)" \
        "$([[ "$c_elapsed" -ge 15 && "$retries_happened" == "true" ]] && echo true || echo false)"
    assert "C2. stack.ntm's exhausted-fetch failure is recorded (record-and-continue, not silently dropped)" "$ntm_recorded"
    assert "C3. real acfs_generated_install_stack_meta_skill STILL ran and installed despite stack.ntm's fetch exhausting all retries earlier in the same category loop" "$meta_skill_ran"
    assert "C4. generated category reports aggregate failure after later modules run" "$([[ $category_rc -ne 0 ]] && echo true || echo false)"

    DRY_RUN=false
    ACFS_SSH_KEY_WARNING=false
    summary_log="$TMPROOT/summary.log"
    print_summary > "$summary_log" 2>&1 || true

    names_module="false"
    grep -q "stack.ntm" "$summary_log" && names_module="true"
    says_complete="false"
    grep -q "Installation Complete" "$summary_log" && says_complete="true"
    says_failures="false"
    grep -q "Finished With Failures" "$summary_log" && says_failures="true"
    leaks_raw_curl_code="false"
    grep -Eq '(^| )22( |$)|exit code 22|curl.*22\b' "$summary_log" && leaks_raw_curl_code="true"
    leaks_raw_http_status="false"
    grep -q "429" "$summary_log" && leaks_raw_http_status="true"

    assert "C5. print_summary names 'stack.ntm' (not a raw curl exit code)" "$names_module"
    assert "C6. print_summary does not claim 'Installation Complete' over the broken run" "$([[ "$says_complete" == "false" ]] && echo true || echo false)"
    assert "C7. print_summary banner reads 'Finished With Failures'" "$says_failures"
    assert "C8. print_summary text does NOT leak curl exit code 22 anywhere" "$([[ "$leaks_raw_curl_code" == "false" ]] && echo true || echo false)"
    assert "C9. print_summary text does NOT leak the raw HTTP status 429 anywhere" "$([[ "$leaks_raw_http_status" == "false" ]] && echo true || echo false)"

    echo
    echo "   --- verbatim summary failure line for the fetch-exhaustion case ---"
    grep -A2 "did not install" "$summary_log" | sed 's/^/   | /'
    echo "   -------------------------------------------------------------"

    assert "C10. stack.ntm's fetch-exhaustion failure now carries a human-meaningful reason ('network'), not just the bare module id" \
        "$([[ "$ntm_recorded_reason" == "stack.ntm (network)" ]] && echo true || echo false)"

    # -- C11-C13: a DIFFERENT failure cause (real checksum mismatch, not
    # fetch exhaustion) must render with a DIFFERENT reason than C10's
    # network failure. Before this fix both rendered identically as the
    # bare module id; that collapse is exactly what this proves is gone.
    #
    # Deliberately does NOT re-run acfs_run_generated_category_phase: doing
    # so a second time reinstalls every REAL module in stack/phase 9 (not
    # just the one under test), which is expensive and was observed to blow
    # past this test's time budget. Instead this calls the module function
    # directly and applies install_helpers.sh's own record-and-continue
    # snippet (mirrored, not reimplemented differently) to the one call —
    # exercising the exact same reason-capture contract without paying for
    # a second full category run.
    install_stack_cass_checksum_probe() {
        local module_id="stack.cass"
        log_step "Installing stack.cass (checksum-mismatch probe)"
        # Real verify_checksum() against a real, reachable URL but the
        # WRONG expected checksum -- a genuine checksum mismatch, not a
        # network failure and not a hand-written return 1.
        if ! verify_checksum "https://httpbin.org/status/200" "0000000000000000000000000000000000000000000000000000000000000000" "stack.cass"; then
            log_error "stack.cass: verified installer failed"
            return 1
        fi
        log_success "stack.cass installed"
    }

    ACFS_LAST_MODULE_FAILURE_REASON=""
    cass_probe_log="$TMPROOT/cass_probe.log"
    if ! install_stack_cass_checksum_probe > "$cass_probe_log" 2>&1; then
        cass_failure_reason="${ACFS_LAST_MODULE_FAILURE_REASON:-installation failed}"
    else
        cass_failure_reason="<did not fail>"
    fi

    assert "C11. a genuine checksum-mismatch failure (stack.cass) sets reason 'checksum'" \
        "$([[ "$cass_failure_reason" == "checksum" ]] && echo true || echo false)"
    assert "C12. the fetch-exhaustion (network, from C10) and checksum-mismatch (checksum) failures produce DIFFERENT reasons — this is the collapse-of-distinct-states bug now fixed" \
        "$([[ "$ntm_recorded_reason" == "stack.ntm (network)" && "$cass_failure_reason" == "checksum" ]] && echo true || echo false)"

    leaks_22_v2="false"
    grep -Eq '(^| )22( |$)|exit code 22|curl.*22\b' "$cass_probe_log" && leaks_22_v2="true"
    leaks_429_status_v2="false"
    grep -q "HTTP 429" "$cass_probe_log" && leaks_429_status_v2="true"
    assert "C13. the checksum-mismatch reason itself is never a raw curl exit code or HTTP status" \
        "$([[ "$leaks_22_v2" == "false" && "$leaks_429_status_v2" == "false" && "$cass_failure_reason" == "checksum" ]] && echo true || echo false)"
else
    note "Part C SKIPPED: no network to httpbin.org from this sandbox."
fi

echo
echo "=============================================="
if [[ "$FAIL" -eq 0 ]]; then
    echo "ALL ASSERTIONS PASSED"
else
    echo "AT LEAST ONE ASSERTION FAILED"
fi
echo "=============================================="
exit "$FAIL"
