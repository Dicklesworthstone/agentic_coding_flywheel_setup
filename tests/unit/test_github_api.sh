#!/usr/bin/env bash
# ============================================================
# Unit tests for scripts/lib/github_api.sh
# Tests rate limit detection and backoff logic
#
# Related: bd-1lug
# ============================================================

set -euo pipefail

# Test directory setup
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
LIB_DIR="$PROJECT_ROOT/scripts/lib"

# Source the library
source "$LIB_DIR/github_api.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Test helper
test_pass() {
    local name="$1"
    ((TESTS_PASSED++)) || true  # Avoid set -e failure when incrementing from 0
    echo -e "${GREEN}[PASS]${NC} $name"
}

test_fail() {
    local name="$1"
    local reason="${2:-}"
    ((TESTS_FAILED++)) || true  # Avoid set -e failure when incrementing from 0
    echo -e "${RED}[FAIL]${NC} $name"
    [[ -n "$reason" ]] && echo "       $reason"
}

run_test() {
    local name="$1"
    shift
    ((TESTS_RUN++)) || true  # Avoid set -e failure when incrementing from 0

    if "$@"; then
        test_pass "$name"
    else
        test_fail "$name" "Command returned non-zero"
    fi
}

# ============================================================
# Rate Limit Detection Tests
# ============================================================

test_rate_limit_403_with_body() {
    # Test: HTTP 403 with "rate limit" in body should be detected
    local body="API rate limit exceeded for user"
    if _is_rate_limited "403" "$body" ""; then
        return 0
    fi
    return 1
}

test_rate_limit_429() {
    # Test: HTTP 429 should be detected as rate limit
    if _is_rate_limited "429" "" "0"; then
        return 0
    fi
    return 1
}

test_rate_limit_remaining_zero() {
    # Test: X-RateLimit-Remaining: 0 should be detected
    if _is_rate_limited "403" "" "0"; then
        return 0
    fi
    return 1
}

test_rate_limit_abuse_detection() {
    # Test: "abuse detection" in body should be detected
    local body="You have triggered an abuse detection mechanism"
    if _is_rate_limited "403" "$body" ""; then
        return 0
    fi
    return 1
}

test_not_rate_limited_200() {
    # Test: HTTP 200 should NOT be rate limited
    if _is_rate_limited "200" "" ""; then
        return 1  # 200 should not be rate limited
    fi
    return 0
}

test_not_rate_limited_404() {
    # Test: HTTP 404 should NOT be rate limited
    if _is_rate_limited "404" "" ""; then
        return 1  # 404 should not be rate limited
    fi
    return 0
}

test_not_rate_limited_403_no_indicators() {
    # Test: HTTP 403 without rate limit indicators should NOT be detected
    local body="Bad credentials"
    if _is_rate_limited "403" "$body" "50"; then
        return 1  # Should not be rate limited (remaining > 0, no rate limit text)
    fi
    return 0
}

# ============================================================
# Reset Wait Time Tests
# ============================================================

test_reset_wait_time_valid() {
    # Test: Valid reset timestamp should return correct wait time
    local now future wait_time
    now=$(date +%s)
    future=$((now + 30))

    wait_time=$(_get_reset_wait_time "$future")

    # Should be approximately 31 (30 + 1 for safety)
    if [[ "$wait_time" -ge 28 && "$wait_time" -le 35 ]]; then
        return 0
    fi
    echo "Expected ~31, got $wait_time" >&2
    return 1
}

test_reset_wait_time_past() {
    # Test: Past timestamp should return max backoff
    local past wait_time
    past=$(($(date +%s) - 100))

    wait_time=$(_get_reset_wait_time "$past")

    if [[ "$wait_time" == "$GITHUB_BACKOFF_MAX" ]]; then
        return 0
    fi
    echo "Expected $GITHUB_BACKOFF_MAX, got $wait_time" >&2
    return 1
}

test_reset_wait_time_invalid() {
    # Test: Invalid timestamp should return max backoff
    local wait_time
    wait_time=$(_get_reset_wait_time "invalid")

    if [[ "$wait_time" == "$GITHUB_BACKOFF_MAX" ]]; then
        return 0
    fi
    echo "Expected $GITHUB_BACKOFF_MAX, got $wait_time" >&2
    return 1
}

test_has_gh_auth_prefers_target_home_binary() {
    local temp_dir target_home fake_path marker status=1
    local old_home="${HOME:-}"
    local old_path="${PATH:-}"
    local old_target_user="${TARGET_USER-__unset__}"
    local old_target_home="${TARGET_HOME-__unset__}"
    local old_acfs_bin_dir="${ACFS_BIN_DIR-__unset__}"

    temp_dir=$(mktemp -d)
    target_home="$temp_dir/target"
    fake_path="$temp_dir/fake-path"
    marker="$temp_dir/marker"

    mkdir -p "$target_home/.local/bin" "$fake_path"

    cat > "$target_home/.local/bin/gh" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "auth" && "\${2:-}" == "status" ]]; then
    printf 'target\n' > "$marker"
    exit 0
fi
exit 1
EOF
    chmod +x "$target_home/.local/bin/gh"

    cat > "$fake_path/gh" <<EOF
#!/usr/bin/env bash
printf 'path\n' > "$marker"
exit 1
EOF
    chmod +x "$fake_path/gh"

    HOME="relative-home"
    PATH="$fake_path:/usr/bin:/bin"
    unset TARGET_USER
    TARGET_HOME="$target_home"
    ACFS_BIN_DIR="$target_home/.local/bin"

    if _has_gh_auth; then
        status=0
    fi

    PATH="$old_path"
    HOME="$old_home"
    if [[ "$old_target_user" == "__unset__" ]]; then
        unset TARGET_USER
    else
        TARGET_USER="$old_target_user"
    fi
    if [[ "$old_target_home" == "__unset__" ]]; then
        unset TARGET_HOME
    else
        TARGET_HOME="$old_target_home"
    fi
    if [[ "$old_acfs_bin_dir" == "__unset__" ]]; then
        unset ACFS_BIN_DIR
    else
        ACFS_BIN_DIR="$old_acfs_bin_dir"
    fi

    if [[ "$status" -ne 0 ]]; then
        rm -rf "$temp_dir"
        return 1
    fi

    if [[ "$(cat "$marker" 2>/dev/null)" != "target" ]]; then
        rm -rf "$temp_dir"
        return 1
    fi

    rm -rf "$temp_dir"
    return 0
}

# ============================================================
# Integration Tests (require network)
# ============================================================

test_fetch_valid_url() {
    # Test: Fetch a known good URL should succeed
    local tmp_file
    tmp_file=$(mktemp)
    trap 'rm -f -- "${tmp_file:-}" 2>/dev/null || true; trap - RETURN' RETURN

    # Use a small, stable GitHub file
    if github_fetch_with_backoff "https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/main/README.md" "$tmp_file" "test" 2>/dev/null; then
        if [[ -s "$tmp_file" ]]; then
            return 0
        fi
    fi
    return 1
}

test_fetch_invalid_url() {
    # Test: Fetch non-existent URL should fail with exit code 2
    local tmp_file status=0
    tmp_file=$(mktemp)
    trap 'rm -f -- "${tmp_file:-}" 2>/dev/null || true; trap - RETURN' RETURN

    github_fetch_with_backoff "https://api.github.com/repos/nonexistent-user-12345/nonexistent-repo-67890/contents" "$tmp_file" "test" 2>/dev/null || status=$?

    if [[ "$status" == "2" ]]; then
        return 0
    fi
    echo "Expected exit code 2, got $status" >&2
    return 1
}

test_fetch_valid_url_without_base_args() {
    # Regression test: github_fetch_with_backoff should still work when
    # ACFS_CURL_BASE_ARGS is unset.
    local tmp_file status=1 had_base_args=false
    local -a saved_base_args=()
    tmp_file=$(mktemp)

    if declare -p ACFS_CURL_BASE_ARGS &>/dev/null; then
        had_base_args=true
        saved_base_args=("${ACFS_CURL_BASE_ARGS[@]}")
        unset ACFS_CURL_BASE_ARGS
    fi

    if github_fetch_with_backoff "https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/main/README.md" "$tmp_file" "test" 2>/dev/null; then
        if [[ -s "$tmp_file" ]]; then
            status=0
        fi
    fi

    if [[ "$had_base_args" == "true" ]]; then
        ACFS_CURL_BASE_ARGS=("${saved_base_args[@]}")
    else
        unset ACFS_CURL_BASE_ARGS 2>/dev/null || true
    fi

    rm -f "$tmp_file"
    return "$status"
}

test_fetch_with_backoff_strips_fail_flag_for_rate_limit_status() {
    # Regression test: github_fetch_with_backoff must inspect 403/429 bodies.
    # Curl's -f/--fail turns those HTTP responses into generic failures before
    # the rate-limit classifier can see the response headers and body.
    local temp_dir tmp_file status=1

    temp_dir=$(mktemp -d)
    tmp_file=$(mktemp)

    cat > "$temp_dir/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log_file="$TEST_GITHUB_CURL_DIR/argv.log"
calls_file="$TEST_GITHUB_CURL_DIR/calls"

for arg in "$@"; do
    printf '%s\n' "$arg" >> "$log_file"
    case "$arg" in
        -f|--fail|--fail-with-body|-[!-]*f*)
            printf 'unexpected fail flag: %s\n' "$arg" >&2
            exit 97
            ;;
    esac
done

headers=""
output=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -D)
            headers="$2"
            shift 2
            ;;
        -o)
            output="$2"
            shift 2
            ;;
        -w)
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

calls=0
[[ -f "$calls_file" ]] && calls="$(<"$calls_file")"
calls=$((calls + 1))
printf '%s\n' "$calls" > "$calls_file"

if [[ "$calls" -eq 1 ]]; then
    printf 'HTTP/2 403\r\nx-ratelimit-remaining: 0\r\n\r\n' > "$headers"
    printf 'API rate limit exceeded\n' > "$output"
    printf '403'
    exit 0
fi

printf 'HTTP/2 200\r\nx-ratelimit-remaining: 1\r\n\r\n' > "$headers"
printf 'ok\n' > "$output"
printf '200'
EOF
    chmod +x "$temp_dir/curl"

    if TEST_GITHUB_CURL_DIR="$temp_dir" GITHUB_MAX_RETRIES=2 bash -c '
        set -euo pipefail
        source "$1"
        _github_api_curl_binary_path() {
            printf "%s/curl\n" "$TEST_GITHUB_CURL_DIR"
        }
        ACFS_CURL_BASE_ARGS=(--proto "=https" --proto-redir "=https" --connect-timeout 30 --max-time 300 -fsSL)
        GITHUB_BACKOFF_INITIAL=0
        GITHUB_BACKOFF_MAX=1
        github_fetch_with_backoff "https://example.invalid/file" "$2" "rate-limit-status-test" >/dev/null 2>/dev/null
    ' _ "$LIB_DIR/github_api.sh" "$tmp_file"; then
        if [[ "$(cat "$tmp_file" 2>/dev/null)" == "ok" ]] && [[ "$(cat "$temp_dir/calls" 2>/dev/null)" == "2" ]]; then
            status=0
        fi
    fi

    rm -rf "$temp_dir"
    rm -f "$tmp_file"
    return "$status"
}

test_fetch_with_backoff_clears_return_trap() {
    # Regression test: library functions are sourced into long-lived shells, so
    # temp-file cleanup must not leave a stale RETURN trap behind.
    local temp_dir tmp_file trap_output status=0
    temp_dir=$(mktemp -d)
    tmp_file=$(mktemp)

    cat > "$temp_dir/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
    printf '%s\n' '--proto'
    exit 0
fi

headers=""
output=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -D)
            headers="$2"
            shift 2
            ;;
        -o)
            output="$2"
            shift 2
            ;;
        -w)
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

printf 'HTTP/2 200\r\nx-ratelimit-remaining: 1\r\n\r\n' > "$headers"
printf 'ok\n' > "$output"
printf '200'
EOF
    chmod +x "$temp_dir/curl"

    trap_output="$(
        TEST_GITHUB_CURL_DIR="$temp_dir" GITHUB_MAX_RETRIES=1 bash -c '
            set -euo pipefail
            source "$1"
            _github_api_curl_binary_path() {
                printf "%s/curl\n" "$TEST_GITHUB_CURL_DIR"
            }
            github_fetch_with_backoff "https://example.invalid/file" "$2" "trap-test" >/dev/null
            trap -p RETURN
        ' _ "$LIB_DIR/github_api.sh" "$tmp_file"
    )" || status=$?

    rm -rf "$temp_dir"
    rm -f "$tmp_file"

    [[ "$status" -eq 0 && -z "$trap_output" ]]
}

test_fetch_with_backoff_preserves_caller_return_trap() {
    local temp_dir tmp_file trap_output status=0
    temp_dir=$(mktemp -d)
    tmp_file=$(mktemp)

    cat > "$temp_dir/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
    printf '%s\n' '--proto'
    exit 0
fi

headers=""
output=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -D)
            headers="$2"
            shift 2
            ;;
        -o)
            output="$2"
            shift 2
            ;;
        -w)
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

printf 'HTTP/2 200\r\nx-ratelimit-remaining: 1\r\n\r\n' > "$headers"
printf 'ok\n' > "$output"
printf '200'
EOF
    chmod +x "$temp_dir/curl"

    trap_output="$(
        TEST_GITHUB_CURL_DIR="$temp_dir" GITHUB_MAX_RETRIES=1 bash -c '
            set -euo pipefail
            source "$1"
            output_file="$2"
            _github_api_curl_binary_path() {
                printf "%s/curl\n" "$TEST_GITHUB_CURL_DIR"
            }
            probe_return_trap() {
                trap "caller_return_seen=1" RETURN
                github_fetch_with_backoff "https://example.invalid/file" "$output_file" "trap-test" >/dev/null
                trap -p RETURN
            }
            probe_return_trap
        ' _ "$LIB_DIR/github_api.sh" "$tmp_file"
    )" || status=$?

    rm -rf "$temp_dir"
    rm -f "$tmp_file"

    [[ "$status" -eq 0 && "$trap_output" == *"caller_return_seen=1"* ]]
}

test_fetch_with_backoff_reports_output_write_failure() {
    local temp_dir missing_output status=0
    temp_dir=$(mktemp -d)
    missing_output="$temp_dir/missing/result.txt"

    cat > "$temp_dir/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
    printf '%s\n' '--proto'
    exit 0
fi

headers=""
output=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -D)
            headers="$2"
            shift 2
            ;;
        -o)
            output="$2"
            shift 2
            ;;
        -w)
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

printf 'HTTP/2 200\r\nx-ratelimit-remaining: 1\r\n\r\n' > "$headers"
printf 'ok\n' > "$output"
printf '200'
EOF
    chmod +x "$temp_dir/curl"

    TEST_GITHUB_CURL_DIR="$temp_dir" GITHUB_MAX_RETRIES=1 bash -c '
        set -euo pipefail
        source "$1"
        _github_api_curl_binary_path() {
            printf "%s/curl\n" "$TEST_GITHUB_CURL_DIR"
        }
        github_fetch_with_backoff "https://example.invalid/file" "$2" "write-failure-test" >/dev/null
    ' _ "$LIB_DIR/github_api.sh" "$missing_output" || status=$?

    rm -rf "$temp_dir"

    [[ "$status" -ne 0 ]]
}

test_fetch_with_backoff_ignores_shell_function_curl() {
    local temp_dir marker output status=0

    temp_dir=$(mktemp -d)
    marker="$temp_dir/poisoned"
    output="$temp_dir/output"

    ACFS_POISON_MARKER="$marker" GITHUB_MAX_RETRIES=1 bash -c '
        set -euo pipefail
        source "$1"
        curl() {
            printf poisoned > "$ACFS_POISON_MARKER"
            printf 000
            return 0
        }
        ACFS_CURL_BASE_ARGS=(--connect-timeout 1 --max-time 1 -sS)
        github_fetch_with_backoff "https://127.0.0.1:9/acfs" "$2" "function-poison-test" >/dev/null 2>/dev/null
    ' _ "$LIB_DIR/github_api.sh" "$output" || status=$?

    [[ "$status" -ne 0 && ! -e "$marker" ]]
}

test_fetch_with_backoff_content_encoding() {
    local scenario="$1"
    local temp_dir status=0 fetch_status=0 expect_failure=false
    local output_mode=file library_mode=normal decoded_limit=16777216
    temp_dir=$(mktemp -d)

    # Preserve NUL and trailing newline bytes through both file and stdout APIs.
    printf 'fixture\000payload\n\n' > "$temp_dir/expected"
    printf 'keep existing destination\n' > "$temp_dir/sentinel"
    cp "$temp_dir/sentinel" "$temp_dir/result"
    printf 'HTTP/2 200\r\nContent-Encoding: gzip\r\n\r\n' > "$temp_dir/headers"
    gzip -n -c "$temp_dir/expected" > "$temp_dir/body"
    case "$scenario" in
        gzip) ;;
        gzip-stdout) output_mode=stdout ;;
        x-gzip)
            printf 'HTTP/2 200\r\nCoNtEnT-EnCoDiNg: X-GZip\r\n\r\n' > "$temp_dir/headers"
            ;;
        redirect-identity|standalone-redirect)
            printf 'HTTP/1.1 302 Found\r\nContent-Encoding: gzip\r\n\r\nHTTP/2 200\r\n\r\n' > "$temp_dir/headers"
            cp "$temp_dir/expected" "$temp_dir/body"
            [[ "$scenario" == standalone-redirect ]] && library_mode=standalone
            ;;
        redirect-gzip)
            printf 'HTTP/1.1 302 Found\r\nContent-Encoding: br\r\n\r\nHTTP/2 200\r\nContent-Encoding: gzip\r\n\r\n' > "$temp_dir/headers"
            ;;
        invalid-gzip|invalid-gzip-stdout)
            printf 'not a gzip stream\n' > "$temp_dir/body"
            expect_failure=true
            [[ "$scenario" == invalid-gzip-stdout ]] && output_mode=stdout
            ;;
        unsupported)
            printf 'HTTP/2 200\r\nContent-Encoding: br\r\n\r\n' > "$temp_dir/headers"
            expect_failure=true
            ;;
        oversized) decoded_limit=4; expect_failure=true ;;
        archive)
            printf 'HTTP/2 200\r\nContent-Type: application/gzip\r\n\r\n' > "$temp_dir/headers"
            cp "$temp_dir/body" "$temp_dir/expected"
            ;;
        standalone-identity)
            library_mode=standalone
            printf 'HTTP/2 200\r\nContent-Encoding: identity\r\n\r\n' > "$temp_dir/headers"
            cp "$temp_dir/expected" "$temp_dir/body"
            ;;
        standalone-gzip) library_mode=standalone; expect_failure=true ;;
        *) return 1 ;;
    esac

    cat > "$temp_dir/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
headers=""
output=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -D) headers="$2"; shift 2 ;;
        -o) output="$2"; shift 2 ;;
        -w) shift 2 ;;
        *) shift ;;
    esac
done
cp "$TEST_GITHUB_CURL_DIR/headers" "$headers"
cp "$TEST_GITHUB_CURL_DIR/body" "$output"
printf '200'
EOF
    chmod +x "$temp_dir/curl"

    TEST_GITHUB_CURL_DIR="$temp_dir" bash -c '
        set -euo pipefail
        if [[ "$3" == standalone ]]; then
            # A caller can provide acfs_curl without shipping security.sh.
            acfs_curl() { return 0; }
        fi
        source "$1"
        _github_api_curl_binary_path() {
            printf "%s/curl\n" "$TEST_GITHUB_CURL_DIR"
        }
        _github_effective_token() { printf ""; }
        ACFS_CURL_BASE_ARGS=(--proto "=https" --proto-redir "=https" -sSL)
        ACFS_DOWNLOAD_MAX_DECODED_BYTES="$4"
        GITHUB_MAX_RETRIES=1
        output="$TEST_GITHUB_CURL_DIR/result"
        [[ "$2" == stdout ]] && output=""
        github_fetch_with_backoff "https://raw.githubusercontent.com/example/project/main/fixture" "$output" "encoding-test"
    ' _ "$LIB_DIR/github_api.sh" "$output_mode" "$library_mode" "$decoded_limit" \
        > "$temp_dir/stdout" 2> "$temp_dir/stderr" || fetch_status=$?

    if [[ "$expect_failure" == true ]]; then
        [[ "$fetch_status" -ne 0 ]] || status=1
        cmp -s "$temp_dir/sentinel" "$temp_dir/result" || status=1
        [[ ! -s "$temp_dir/stdout" ]] || status=1
    elif [[ "$output_mode" == stdout ]]; then
        [[ "$fetch_status" -eq 0 ]] || status=1
        cmp -s "$temp_dir/expected" "$temp_dir/stdout" || status=1
        cmp -s "$temp_dir/sentinel" "$temp_dir/result" || status=1
    else
        [[ "$fetch_status" -eq 0 ]] || status=1
        cmp -s "$temp_dir/expected" "$temp_dir/result" || status=1
        [[ ! -s "$temp_dir/stdout" ]] || status=1
    fi

    if [[ "$status" -ne 0 ]]; then
        printf 'Scenario %s: fetch status %s; fixture retained at %s\n' "$scenario" "$fetch_status" "$temp_dir" >&2
        cat "$temp_dir/stderr" >&2
    fi
    return "$status"
}

test_latest_release_returns_nonzero_on_fetch_failure() {
    (
        github_api_fetch() {
            return 2
        }

        local output status=0
        output="$(github_get_latest_release "owner/repo")" || status=$?
        [[ "$status" -ne 0 && -z "$output" ]]
    )
}

test_latest_release_preserves_caller_return_trap() {
    (
        github_api_fetch() {
            printf '{"tag_name":"v1.2.3"}' > "$2"
            return 0
        }

        local trap_output
        probe_return_trap() {
            trap "caller_return_seen=1" RETURN
            github_get_latest_release "owner/repo" >/dev/null
            trap -p RETURN
        }
        trap_output="$(probe_return_trap)"
        [[ "$trap_output" == *"caller_return_seen=1"* ]]
    )
}

# ============================================================
# Main
# ============================================================

main() {
    echo "============================================================"
    echo "GitHub API Rate Limit Backoff Tests"
    echo "============================================================"
    echo ""

    echo "--- Rate Limit Detection ---"
    run_test "403 with rate limit body" test_rate_limit_403_with_body
    run_test "429 response" test_rate_limit_429
    run_test "X-RateLimit-Remaining: 0" test_rate_limit_remaining_zero
    run_test "Abuse detection" test_rate_limit_abuse_detection
    run_test "200 not rate limited" test_not_rate_limited_200
    run_test "404 not rate limited" test_not_rate_limited_404
    run_test "403 without indicators" test_not_rate_limited_403_no_indicators

    echo ""
    echo "--- Reset Wait Time ---"
    run_test "Valid future timestamp" test_reset_wait_time_valid
    run_test "Past timestamp" test_reset_wait_time_past
    run_test "Invalid timestamp" test_reset_wait_time_invalid

    echo ""
    echo "--- Auth Detection ---"
    run_test "Target-home gh beats current PATH gh" test_has_gh_auth_prefers_target_home_binary

    echo ""
    echo "--- Cleanup Discipline ---"
    run_test "Fetch backoff strips curl fail flag for rate limits" test_fetch_with_backoff_strips_fail_flag_for_rate_limit_status
    run_test "Fetch backoff clears RETURN trap" test_fetch_with_backoff_clears_return_trap
    run_test "Fetch backoff preserves caller RETURN trap" test_fetch_with_backoff_preserves_caller_return_trap
    run_test "Fetch backoff reports output write failure" test_fetch_with_backoff_reports_output_write_failure
    run_test "Fetch backoff ignores shell function curl" test_fetch_with_backoff_ignores_shell_function_curl
    run_test "Latest release failure returns non-zero" test_latest_release_returns_nonzero_on_fetch_failure
    run_test "Latest release preserves caller RETURN trap" test_latest_release_preserves_caller_return_trap

    echo ""
    echo "--- Response Content Encoding (offline fixtures) ---"
    run_test "Gzip final response decodes before file publication" test_fetch_with_backoff_content_encoding gzip
    run_test "Gzip final response decodes before stdout publication" test_fetch_with_backoff_content_encoding gzip-stdout
    run_test "Mixed-case x-gzip coding decodes" test_fetch_with_backoff_content_encoding x-gzip
    run_test "Intermediate redirect coding is ignored" test_fetch_with_backoff_content_encoding redirect-identity
    run_test "Final gzip coding wins over redirect coding" test_fetch_with_backoff_content_encoding redirect-gzip
    run_test "Invalid gzip leaves destination untouched" test_fetch_with_backoff_content_encoding invalid-gzip
    run_test "Invalid gzip emits no response body" test_fetch_with_backoff_content_encoding invalid-gzip-stdout
    run_test "Unsupported coding leaves destination untouched" test_fetch_with_backoff_content_encoding unsupported
    run_test "Oversized decoded body leaves destination untouched" test_fetch_with_backoff_content_encoding oversized
    run_test "Gzip archive without content coding stays intact" test_fetch_with_backoff_content_encoding archive
    run_test "Standalone helper still accepts identity responses" test_fetch_with_backoff_content_encoding standalone-identity
    run_test "Standalone helper ignores intermediate redirect coding" test_fetch_with_backoff_content_encoding standalone-redirect
    run_test "Standalone helper fails closed without a gzip decoder" test_fetch_with_backoff_content_encoding standalone-gzip

    # Skip network tests if SKIP_NETWORK_TESTS is set
    if [[ "${SKIP_NETWORK_TESTS:-}" != "true" ]]; then
        echo ""
        echo "--- Network Integration ---"
        run_test "Fetch valid URL" test_fetch_valid_url
        run_test "Fetch invalid URL" test_fetch_invalid_url
        run_test "Fetch valid URL without ACFS_CURL_BASE_ARGS" test_fetch_valid_url_without_base_args
    else
        echo ""
        echo "(Skipping network tests - SKIP_NETWORK_TESTS=true)"
    fi

    echo ""
    echo "============================================================"
    echo "Results: $TESTS_PASSED/$TESTS_RUN passed"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}$TESTS_FAILED test(s) failed${NC}"
        return 1
    else
        echo -e "${GREEN}All tests passed${NC}"
        return 0
    fi
}

main "$@"
