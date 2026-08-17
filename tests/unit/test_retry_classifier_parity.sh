#!/usr/bin/env bash
# ============================================================
# Drift guard for the two acfs_is_retryable_http_status() copies.
#
# install.sh's copy exists only because it must be self-sufficient during
# bootstrap_repo_archive() -- the curl|bash archive fetch runs BEFORE
# scripts/lib/security.sh has been fetched to disk, so that copy cannot be
# sourced from the main one; it has to be duplicated (see the comment above
# install.sh's acfs_is_retryable_http_status for the full ordering
# argument). Duplicated logic drifts. Someone fixes a bug in one copy, or
# adds 408 or 425 to one classifier's retry list, and the bootstrap path
# silently starts disagreeing with the main path on which HTTP statuses are
# worth retrying -- invisible until the exact incident (a real rate limit or
# outage) that exercises the bootstrap leg specifically.
#
# This test makes that drift a FAILING TEST instead of a silent behavior
# difference: it extracts BOTH function bodies verbatim from their real
# source files (not paraphrased, not hand-copied logic), evals each under a
# distinct name so they can coexist in one process, feeds both the exact
# same set of HTTP statuses, and asserts identical verdicts for every one --
# the retryable set, the fatal set, and edge cases neither list currently
# names (408, 425, 500, 200, 301, and invalid/empty input).
#
# Same principle this repo already applies to generated-file drift via
# check-manifest-drift.sh, applied here to two independently-maintained
# copies of security-relevant logic instead of a generated/source pair.
# ============================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL_SH="$REPO_ROOT/install.sh"
SECURITY_SH="$REPO_ROOT/scripts/lib/security.sh"

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

extract_function() {
    local file="$1" func_name="$2"
    local body=""
    body="$(sed -n "/^${func_name}()[[:space:]]*{/,/^}/p" "$file")"
    [[ -n "$body" ]] || { echo "FATAL: could not extract ${func_name}() from $file" >&2; exit 2; }
    printf '%s' "$body"
}

install_sh_body="$(extract_function "$INSTALL_SH" "acfs_is_retryable_http_status")"
security_sh_body="$(extract_function "$SECURITY_SH" "acfs_is_retryable_http_status")"

# Rename each copy so both can be loaded into this one process without one
# silently shadowing the other -- the whole point is to call BOTH real
# implementations, not accidentally test one against itself.
eval "${install_sh_body/acfs_is_retryable_http_status/install_sh_is_retryable_http_status}"
eval "${security_sh_body/acfs_is_retryable_http_status/security_sh_is_retryable_http_status}"

declare -f install_sh_is_retryable_http_status >/dev/null 2>&1 \
    || { echo "FATAL: install_sh_is_retryable_http_status did not load"; exit 2; }
declare -f security_sh_is_retryable_http_status >/dev/null 2>&1 \
    || { echo "FATAL: security_sh_is_retryable_http_status did not load"; exit 2; }

# Retryable set, fatal set, and edge cases neither list currently names.
# 408 (Request Timeout) and 425 (Too Early) are named explicitly because
# they are exactly the kind of addition someone plausibly makes to ONE
# classifier and forgets to mirror into the other. 500 is a real server
# error neither list retries (deliberately -- a 500 is not guaranteed
# transient the way 502/503/504 are). 200/301 and empty/non-numeric input
# are shape edge cases, not just status-code edge cases.
TEST_STATUSES=(429 503 502 504 404 403 408 425 500 501 200 301 0 "" "abc")

echo "Testing ${#TEST_STATUSES[@]} statuses against both classifiers..."
for status in "${TEST_STATUSES[@]}"; do
    install_verdict="not-retryable"
    install_sh_is_retryable_http_status "$status" && install_verdict="retryable"
    security_verdict="not-retryable"
    security_sh_is_retryable_http_status "$status" && security_verdict="retryable"

    label="${status:-<empty>}"
    if [[ "$install_verdict" == "$security_verdict" ]]; then
        echo "PASS: status '$label': both classifiers agree ($install_verdict)"
    else
        echo "FAIL: status '$label': install.sh says $install_verdict, security.sh says $security_verdict -- CLASSIFIERS HAVE DRIFTED"
        FAIL=1
    fi
done

# Sanity checks so this test cannot pass by both classifiers being
# vacuously wrong in the same direction (e.g. both always returning
# "not-retryable" would trivially "agree" on everything above).
install_sh_is_retryable_http_status 429
assert "sanity: install.sh's copy actually treats 429 as retryable (not a vacuous always-false stub)" \
    "$([[ $? -eq 0 ]] && echo true || echo false)"
security_sh_is_retryable_http_status 429
assert "sanity: security.sh's copy actually treats 429 as retryable (not a vacuous always-false stub)" \
    "$([[ $? -eq 0 ]] && echo true || echo false)"
install_sh_is_retryable_http_status 404
assert "sanity: install.sh's copy actually treats 404 as fatal (not a vacuous always-true stub)" \
    "$([[ $? -ne 0 ]] && echo true || echo false)"
security_sh_is_retryable_http_status 404
assert "sanity: security.sh's copy actually treats 404 as fatal (not a vacuous always-true stub)" \
    "$([[ $? -ne 0 ]] && echo true || echo false)"

echo
echo "=============================================="
if [[ "$FAIL" -eq 0 ]]; then
    echo "ALL ASSERTIONS PASSED"
else
    echo "AT LEAST ONE ASSERTION FAILED"
fi
echo "=============================================="

exit "$FAIL"
