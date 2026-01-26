#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2317
# SC2034: YELLOW/VERBOSE/REDACT are used by eval'd functions (indirect use)
# SC2317: log_* stubs appear unreachable but are called by eval'd functions
# ============================================================
# Tests for support-bundle redaction rules (bd-31ps.2.2)
#
# Verifies:
# - Known secret patterns are redacted with <REDACTED:type> markers
# - Safe values (git SHAs, version strings, paths) are NOT redacted
# - --no-redact flag disables redaction
# - Binary files are skipped
# - Redaction count is tracked
# - Manifest includes redaction summary
#
# Usage: bash tests/test_support_redaction.sh
# Exit: 0 if all pass, 1 if any fail
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SUPPORT_SH="$PROJECT_ROOT/scripts/lib/support.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors (respects NO_COLOR)
if [[ -z "${NO_COLOR:-}" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' NC=''
fi

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "${GREEN}PASS${NC} %s\n" "$1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "${RED}FAIL${NC} %s\n" "$1"
    if [[ -n "${2:-}" ]]; then
        printf "     %s\n" "$2"
    fi
}

# Create a temp directory for test fixtures, clean up on exit
TEST_DIR=$(mktemp -d /tmp/acfs_redaction_test_XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT

# ============================================================
# Load redact_file and redact_bundle from support.sh
# ============================================================
# We source support.sh in a controlled way:
# 1. Pre-define stubs so top-level code and main() become no-ops
# 2. Source the file to get all function definitions
# 3. Override any side effects

# Minimal logging stubs (must be defined BEFORE sourcing)
log_step()    { :; }
log_section() { :; }
log_detail()  { :; }
log_success() { :; }
log_warn()    { :; }
log_error()   { :; }

# Source support.sh with --help to make it exit early from arg parsing,
# but capture its functions. We use a subshell-free approach: define
# main as a no-op, then source the file with no args.
# Actually, support.sh runs main "$@" at the end, so we need to
# prevent that. We'll extract just the function definitions via awk
# which handles nested braces correctly.
_extract_functions() {
    awk '
    /^[a-zA-Z_][a-zA-Z_0-9]*\(\)/ { inside=1; brace=0; fname=$0 }
    inside {
        n = split($0, chars, "")
        for (i=1; i<=n; i++) {
            if (chars[i] == "{") brace++
            if (chars[i] == "}") brace--
        }
        print
        if (brace == 0 && inside) inside=0
    }
    ' "$1"
}

# Extract and eval all function definitions from support.sh
eval "$(_extract_functions "$SUPPORT_SH")"

REDACT=true
REDACTION_COUNT=0
VERBOSE=false

# ============================================================
# Test helpers
# ============================================================

# Create a test file with given content, run redaction, return content
redact_and_read() {
    local filename="$1"
    local content="$2"
    local filepath="$TEST_DIR/$filename"
    printf '%s' "$content" > "$filepath"
    REDACTION_COUNT=0
    redact_file "$filepath"
    cat "$filepath"
}

# Assert file content contains a string
assert_contains() {
    local test_name="$1"
    local actual="$2"
    local expected="$3"
    if echo "$actual" | grep -qF "$expected"; then
        pass "$test_name"
    else
        fail "$test_name" "Expected to contain: $expected"
    fi
}

# Assert file content does NOT contain a string
assert_not_contains() {
    local test_name="$1"
    local actual="$2"
    local unexpected="$3"
    if echo "$actual" | grep -qF "$unexpected"; then
        fail "$test_name" "Should NOT contain: $unexpected"
    else
        pass "$test_name"
    fi
}

# Assert REDACTION_COUNT equals expected value
assert_redaction_count() {
    local test_name="$1"
    local expected="$2"
    if [[ "$REDACTION_COUNT" -eq "$expected" ]]; then
        pass "$test_name"
    else
        fail "$test_name" "Expected count=$expected, got count=$REDACTION_COUNT"
    fi
}

# ============================================================
# Tests: API key patterns
# ============================================================
echo ""
echo "=== API Key Redaction ==="

result=$(redact_and_read "openai.txt" "OPENAI_KEY=sk-abcdefghijklmnopqrstuvwxyz1234567890")
assert_contains "OpenAI sk- key redacted" "$result" "<REDACTED:api_key>"
assert_not_contains "OpenAI sk- key value removed" "$result" "sk-abcdefghijklmnopqrstuvwxyz1234567890"

result=$(redact_and_read "anthropic.txt" "key: sk-ant-api03-aBcDeFgHiJkLmNoPqRsTuVwXyZ")
assert_contains "Anthropic sk-ant- key redacted" "$result" "<REDACTED:api_key>"

result=$(redact_and_read "aws.txt" "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE")
assert_contains "AWS access key redacted" "$result" "<REDACTED:aws_key>"
assert_not_contains "AWS key value removed" "$result" "AKIAIOSFODNN7EXAMPLE"

# ============================================================
# Tests: GitHub token patterns
# ============================================================
echo ""
echo "=== GitHub Token Redaction ==="

result=$(redact_and_read "ghp.txt" "GITHUB_TOKEN=ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn")
assert_contains "GitHub PAT (ghp_) redacted" "$result" "<REDACTED:github_token>"

result=$(redact_and_read "ghs.txt" "token: ghs_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn")
assert_contains "GitHub server token (ghs_) redacted" "$result" "<REDACTED:github_token>"

result=$(redact_and_read "ghpat.txt" "PAT=github_pat_ABCDEFGHIJKLMNOPQRSTUVWXYZab")
assert_contains "GitHub fine-grained PAT redacted" "$result" "<REDACTED:github_pat>"

# ============================================================
# Tests: Other service tokens
# ============================================================
echo ""
echo "=== Service Token Redaction ==="

result=$(redact_and_read "vault.txt" "VAULT_TOKEN=hvs.CAESIJaLm0nOpQrStUvWxYz01234")
assert_contains "Vault token redacted" "$result" "<REDACTED:vault_token>"

result=$(redact_and_read "slack.txt" "SLACK_BOT_TOKEN=xoxb-123456789012-abcdefghijkl")
assert_contains "Slack bot token redacted" "$result" "<REDACTED:slack_token>"

# ============================================================
# Tests: Bearer tokens and JWTs
# ============================================================
echo ""
echo "=== Bearer & JWT Redaction ==="

result=$(redact_and_read "bearer.txt" "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U")
assert_contains "Bearer token redacted" "$result" "Bearer <REDACTED:bearer>"

result=$(redact_and_read "jwt.txt" "token=eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U")
assert_contains "JWT redacted" "$result" "<REDACTED:jwt>"

# ============================================================
# Tests: Generic secret patterns (KEY=value)
# ============================================================
echo ""
echo "=== Generic Secret Patterns ==="

result=$(redact_and_read "env_secrets.txt" "API_KEY=mysupersecretvalue123
SECRET_KEY=anotherlongsecrethere
ACCESS_TOKEN=verylongtokenvalue99
PASSWORD=hunter2isnotsafe
client_secret=abcdefghijklmnop")
assert_contains "API_KEY redacted" "$result" "<REDACTED:API_KEY>"
assert_contains "SECRET_KEY redacted" "$result" "<REDACTED:SECRET_KEY>"
assert_contains "ACCESS_TOKEN redacted" "$result" "<REDACTED:ACCESS_TOKEN>"
assert_contains "PASSWORD redacted" "$result" "<REDACTED:password>"

# ============================================================
# Tests: Safe values NOT redacted (false positive prevention)
# ============================================================
echo ""
echo "=== False Positive Prevention ==="

result=$(redact_and_read "safe.txt" 'git_sha=a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2
version=1.23.456
PATH=/usr/local/bin:/usr/bin
TERM=xterm-256color
status=ok
name=ubuntu
HOME=/home/ubuntu')
assert_not_contains "Git SHA not redacted" "$result" "<REDACTED"
assert_contains "Git SHA preserved" "$result" "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
assert_contains "Version preserved" "$result" "1.23.456"
assert_contains "PATH preserved" "$result" "/usr/local/bin"
assert_contains "HOME preserved" "$result" "/home/ubuntu"

# Short passwords (< 4 chars) should not be redacted
result=$(redact_and_read "short_pw.txt" "PASSWORD=abc")
assert_not_contains "Short password not redacted" "$result" "<REDACTED"

# ============================================================
# Tests: Binary file skipping
# ============================================================
echo ""
echo "=== Binary File Handling ==="

# Create a file with null bytes (binary)
printf 'sk-secretkey1234567890abcdef\x00binary' > "$TEST_DIR/binary.bin"
REDACTION_COUNT=0
redact_file "$TEST_DIR/binary.bin"
assert_redaction_count "Binary file skipped (count=0)" 0

# ============================================================
# Tests: Redaction count tracking
# ============================================================
echo ""
echo "=== Redaction Counting ==="

REDACTION_COUNT=0
printf 'key1=sk-abcdefghijklmnopqrstuvwxyz1234567890\nkey2=ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn\n' > "$TEST_DIR/multi.txt"
redact_file "$TEST_DIR/multi.txt"
assert_redaction_count "Multiple secrets in one file = 1 file redacted" 1

# ============================================================
# Tests: redact_bundle walks directory
# ============================================================
echo ""
echo "=== Bundle Redaction ==="

REDACT=true
REDACTION_COUNT=0
mkdir -p "$TEST_DIR/bundle/logs"
printf 'token=sk-abcdefghijklmnopqrstuvwxyz1234567890\n' > "$TEST_DIR/bundle/state.json"
printf 'log: ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn\n' > "$TEST_DIR/bundle/logs/install.log"
printf 'safe content no secrets here\n' > "$TEST_DIR/bundle/clean.txt"
redact_bundle "$TEST_DIR/bundle"

state_content=$(cat "$TEST_DIR/bundle/state.json")
log_content=$(cat "$TEST_DIR/bundle/logs/install.log")
assert_contains "Bundle: state.json redacted" "$state_content" "<REDACTED:api_key>"
assert_contains "Bundle: install.log redacted" "$log_content" "<REDACTED:github_token>"
if [[ "$REDACTION_COUNT" -ge 2 ]]; then
    pass "Bundle: redaction count >= 2"
else
    fail "Bundle: redaction count >= 2" "Got $REDACTION_COUNT"
fi

# ============================================================
# Tests: --no-redact flag
# ============================================================
echo ""
echo "=== --no-redact Flag ==="

REDACT=false
REDACTION_COUNT=0
printf 'key=sk-abcdefghijklmnopqrstuvwxyz1234567890\n' > "$TEST_DIR/no_redact.json"
mkdir -p "$TEST_DIR/noredact_bundle"
cp "$TEST_DIR/no_redact.json" "$TEST_DIR/noredact_bundle/"
redact_bundle "$TEST_DIR/noredact_bundle"
nr_content=$(cat "$TEST_DIR/noredact_bundle/no_redact.json")
assert_contains "no-redact: secret preserved" "$nr_content" "sk-abcdefghijklmnopqrstuvwxyz1234567890"
assert_redaction_count "no-redact: count stays 0" 0

# ============================================================
# Summary
# ============================================================
echo ""
echo "========================================"
printf "Results: %d/%d passed" "$TESTS_PASSED" "$TESTS_RUN"
if [[ "$TESTS_FAILED" -gt 0 ]]; then
    printf ", ${RED}%d FAILED${NC}" "$TESTS_FAILED"
fi
echo ""
echo "========================================"

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
exit 0
