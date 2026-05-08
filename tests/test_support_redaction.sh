#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2317
# SC2034: YELLOW is intentionally kept alongside the shared color palette pattern.
# SC2317: log_* stubs are fallback definitions when support.sh is sourced without logging helpers.
# ============================================================
# Tests for support-bundle redaction rules (bd-31ps.2.2)
#
# Verifies:
# - Known secret patterns are redacted with <REDACTED:type> markers
# - Safe values (git SHAs, version strings, paths) are NOT redacted
# - --no-redact flag disables redaction
# - Binary files are replaced with a redaction marker
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
# Minimal logging stubs (must be defined BEFORE sourcing)
log_step()    { :; }
log_section() { :; }
log_detail()  { :; }
log_success() { :; }
log_warn()    { :; }
log_error()   { :; }

# shellcheck source=../scripts/lib/support.sh
source "$SUPPORT_SH"

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
        fail "$test_name" "Expected marker/category was not present"
    fi
}

# Assert file content does NOT contain a string
assert_not_contains() {
    local test_name="$1"
    local actual="$2"
    local unexpected="$3"
    if echo "$actual" | grep -qF "$unexpected"; then
        fail "$test_name" "Sensitive fixture value was present in output"
    else
        pass "$test_name"
    fi
}

assert_equals() {
    local test_name="$1"
    local actual="$2"
    local expected="$3"
    if [[ "$actual" == "$expected" ]]; then
        pass "$test_name"
    else
        fail "$test_name" "Expected value did not match"
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
# Tests: support.sh source safety
# ============================================================
echo ""
echo "=== Source Safety ==="

source_output=""
if source_output=$(SUPPORT_SH="$SUPPORT_SH" bash -lc '
    set +e +u
    set +o pipefail
    log_step() { :; }
    log_section() { :; }
    log_detail() { :; }
    log_success() { :; }
    log_warn() { :; }
    log_error() { :; }
    HOME=relative-home
    set -- --bogus keep
    source "$SUPPORT_SH"
    if [[ $- == *e* || $- == *u* ]]; then
        printf "bad-shell-flags:%s\n" "$-"
        exit 1
    fi
    if shopt -qo pipefail; then
        printf "bad-shell-flags:pipefail\n"
        exit 1
    fi
    declare -F redact_file >/dev/null
    declare -F redact_bundle >/dev/null
    printf "%s|%s|%s|%s\n" "$HOME" "$#" "$1" "$2"
' 2>&1); then
    assert_equals "support.sh sourcing preserves caller env and shell flags" "$source_output" "relative-home|2|--bogus|keep"
else
    fail "support.sh sourcing preserves caller env and shell flags" "$source_output"
fi

if jq_bin=$(command -v jq 2>/dev/null); then
    jq_dir="$(dirname "$jq_bin")"
    env_output=""
    if env_output=$(env -i PATH="$jq_dir:/usr/bin:/bin" HOME="$TEST_DIR/no-shell-home" SUPPORT_SH="$SUPPORT_SH" TEST_BUNDLE="$TEST_DIR/no-shell-bundle" JQ_BIN="$jq_bin" bash -lc '
        set -euo pipefail
        unset SHELL
        mkdir -p "$HOME" "$TEST_BUNDLE"
        log_step() { :; }
        log_section() { :; }
        log_detail() { :; }
        log_success() { :; }
        log_warn() { :; }
        log_error() { :; }
        source "$SUPPORT_SH"
        _SUPPORT_CURRENT_HOME="$HOME"
        _SUPPORT_ACFS_HOME=""
        SUPPORT_TARGET_HOME="$HOME"
        SUPPORT_TARGET_USER="tester"
        BUNDLE_FILES=()
        capture_env_summary "$TEST_BUNDLE"
        "$JQ_BIN" -r ".shell" "$TEST_BUNDLE/environment.json"
    ' 2>&1); then
        assert_equals "environment summary tolerates unset SHELL" "$env_output" "unknown"
    else
        fail "environment summary tolerates unset SHELL" "$env_output"
    fi
else
    pass "environment summary tolerates unset SHELL (jq unavailable skip)"
fi

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

result=$(redact_and_read "gho.txt" "oauth: gho_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn")
assert_contains "GitHub OAuth token (gho_) redacted" "$result" "<REDACTED:github_token>"

result=$(redact_and_read "ghu.txt" "app_user: ghu_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn")
assert_contains "GitHub App user token (ghu_) redacted" "$result" "<REDACTED:github_token>"

result=$(redact_and_read "ghs.txt" "token: ghs_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn")
assert_contains "GitHub server token (ghs_) redacted" "$result" "<REDACTED:github_token>"

result=$(redact_and_read "ghr.txt" "refresh: ghr_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn")
assert_contains "GitHub App refresh token (ghr_) redacted" "$result" "<REDACTED:github_token>"

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

result=$(redact_and_read "credential_urls.txt" "DATABASE_URL=postgres://acfs:supersecret@db.example.com/app
REDIS_URL=redis://:redispassword@localhost:6379/0
PUBLIC_URL=https://example.com:443/path")
assert_contains "Database URL credentials redacted" "$result" "postgres://<REDACTED:credentials>@db.example.com/app"
assert_contains "Redis URL credentials redacted" "$result" "redis://<REDACTED:credentials>@localhost:6379/0"
assert_contains "Non-credential URL preserved" "$result" "https://example.com:443/path"
assert_not_contains "URL passwords removed" "$result" "supersecret"

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

result=$(redact_and_read "spaced_env_secrets.txt" "API_KEY = mysupersecretvalue123
DB_PASSWORD = hunter2
VERCEL_TOKEN : vercel-token-value-12345")
assert_contains "Spaced API_KEY redacted" "$result" "API_KEY = <REDACTED:API_KEY>"
assert_contains "Spaced password redacted" "$result" "DB_PASSWORD = <REDACTED:password>"
assert_contains "Spaced colon token redacted" "$result" "VERCEL_TOKEN : <REDACTED:generic_secret>"
assert_not_contains "Spaced secret values removed" "$result" "mysupersecretvalue123"
assert_not_contains "Spaced password value removed" "$result" "hunter2"
assert_not_contains "Spaced token value removed" "$result" "vercel-token-value-12345"

result=$(redact_and_read "prefixed_env_secrets.txt" "GEMINI_API_KEY=AIzaSyExampleValue12345
VERCEL_TOKEN=vercel-token-value-12345
AWS_SECRET_ACCESS_KEY=awssecretaccessvalue123
DB_PASSWORD=hunter2
my-service-token=plain-secret-token-123")
assert_contains "Prefixed API key redacted" "$result" "GEMINI_API_KEY=<REDACTED:API_KEY>"
assert_contains "Prefixed token redacted" "$result" "VERCEL_TOKEN=<REDACTED:generic_secret>"
assert_contains "Prefixed access key redacted" "$result" "AWS_SECRET_ACCESS_KEY=<REDACTED:generic_secret>"
assert_contains "Prefixed password redacted" "$result" "DB_PASSWORD=<REDACTED:password>"
assert_contains "Hyphenated token key redacted" "$result" "my-service-token=<REDACTED:generic_secret>"
assert_not_contains "Prefixed secret values removed" "$result" "AIzaSyExampleValue12345"

result=$(redact_and_read "prefixed_json_secrets.txt" '{"gemini_api_key":"AIzaSyExampleValue12345","db_password":"hunter2"}')
assert_contains "Prefixed JSON API key redacted" "$result" '"gemini_api_key": "<REDACTED:generic_secret>"'
assert_contains "Prefixed JSON password redacted" "$result" '"db_password": "<REDACTED:password>"'

result=$(redact_and_read "tabbed_json_secrets.txt" $'{"api_key"\t:\t"mysupersecretvalue123","db_password"\t:\t"hunter2"}')
assert_contains "Tabbed JSON API key redacted" "$result" '"api_key": "<REDACTED:api_key>"'
assert_contains "Tabbed JSON password redacted" "$result" '"db_password": "<REDACTED:password>"'
assert_not_contains "Tabbed JSON secret values removed" "$result" "mysupersecretvalue123"
assert_not_contains "Tabbed JSON password value removed" "$result" "hunter2"

result=$(redact_and_read "camel_secret_keys.txt" "vercelToken=vercel-token-value-12345
dbPassword=hunter2
tokenCount=123456789")
assert_contains "CamelCase token redacted" "$result" "vercelToken=<REDACTED:generic_secret>"
assert_contains "CamelCase password redacted" "$result" "dbPassword=<REDACTED:password>"
assert_contains "CamelCase metric preserved" "$result" "tokenCount=123456789"

result=$(redact_and_read "camel_json_secrets.txt" '{"geminiApiKey":"AIzaSyExampleValue12345","dbPassword":"hunter2","tokenCount":"123456789"}')
assert_contains "CamelCase JSON API key redacted" "$result" '"geminiApiKey": "<REDACTED:generic_secret>"'
assert_contains "CamelCase JSON password redacted" "$result" '"dbPassword": "<REDACTED:password>"'
assert_contains "CamelCase JSON metric preserved" "$result" '"tokenCount":"123456789"'

result=$(redact_and_read "quoted_env_secrets.txt" "PASSWORD='correct horse battery staple'
VERCEL_TOKEN = \"quoted token value 12345\"
client_secret = 'quoted client secret value'")
assert_contains "Single-quoted password with spaces redacted" "$result" "PASSWORD='<REDACTED:password>'"
assert_contains "Double-quoted token with spaces redacted" "$result" "VERCEL_TOKEN = \"<REDACTED:generic_secret>\""
assert_contains "Single-quoted client secret with spaces redacted" "$result" "client_secret = '<REDACTED:client_secret>'"
assert_not_contains "Quoted password value removed" "$result" "correct horse battery staple"
assert_not_contains "Quoted token value removed" "$result" "quoted token value 12345"
assert_not_contains "Quoted client secret value removed" "$result" "quoted client secret value"

result=$(redact_and_read "generated_password_log.txt" "WARN: Generated password for 'ubuntu': abcdefghijklmnopqrstuvwxyz123456")
assert_contains "Generated ACFS password redacted" "$result" "Generated password for 'ubuntu': <REDACTED:password>"
assert_not_contains "Generated ACFS password value removed" "$result" "abcdefghijklmnopqrstuvwxyz123456"

result=$(redact_and_read "mail_thread_snippet.json" '{"thread_snippet":"user pasted ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn in a private thread","body_md":"Please inspect /home/alice/private/repo and use token ABCDEFGHIJKLMNOPQRSTUVWXYZ"}')
assert_contains "Agent Mail thread snippet redacted" "$result" '"thread_snippet": "<REDACTED:message_snippet>"'
assert_contains "Agent Mail body redacted" "$result" '"body_md": "<REDACTED:message_snippet>"'
assert_not_contains "Agent Mail private thread text removed" "$result" "private thread"
assert_not_contains "Agent Mail body path removed" "$result" "/home/alice/private"

result=$(redact_and_read "command_diagnostics.json" '{"command":"cd /home/alice/private/repo && OPENAI_API_KEY=sk-abcdefghijklmnopqrstuvwxyz1234567890 cargo test","cwd":"/home/alice/private/repo"}')
assert_contains "Command-line API key redacted" "$result" "<REDACTED:api_key>"
assert_contains "Command-line home path redacted" "$result" "<REDACTED:path>"
assert_not_contains "Command-line API key value removed" "$result" "sk-abcdefghijklmnopqrstuvwxyz1234567890"
assert_not_contains "Command-line private path removed" "$result" "/home/alice/private"

result=$(redact_and_read "openssh_private_key_log.txt" $'before\n-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAA\n-----END OPENSSH PRIVATE KEY-----\nafter')
assert_contains "OpenSSH private key block redacted" "$result" "<REDACTED:private_key>"
assert_not_contains "OpenSSH private key header removed" "$result" "BEGIN OPENSSH PRIVATE KEY"
assert_not_contains "OpenSSH private key payload removed" "$result" "b3BlbnNzaC1rZXktdjE"
assert_contains "Text after private key preserved" "$result" "after"

result=$(redact_and_read "pgp_private_key_log.txt" $'-----BEGIN PGP PRIVATE KEY BLOCK-----\nprivate-payload-line\n-----END PGP PRIVATE KEY BLOCK-----')
assert_contains "PGP private key block redacted" "$result" "<REDACTED:private_key>"
assert_not_contains "PGP private key payload removed" "$result" "private-payload-line"

result=$(redact_and_read "truncated_private_key_log.txt" $'before\n-----BEGIN RSA PRIVATE KEY-----\ntruncated-private-payload')
assert_contains "Truncated private key block redacted" "$result" "<REDACTED:private_key>"
assert_not_contains "Truncated private key header removed" "$result" "BEGIN RSA PRIVATE KEY"
assert_not_contains "Truncated private key payload removed" "$result" "truncated-private-payload"

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
HOME=/home/ubuntu
token_count=123456789
secret_rotation_count=987654321')
assert_not_contains "Git SHA not redacted" "$result" "<REDACTED"
assert_contains "Git SHA preserved" "$result" "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
assert_contains "Version preserved" "$result" "1.23.456"
assert_contains "PATH preserved" "$result" "/usr/local/bin"
assert_contains "HOME preserved" "$result" "/home/ubuntu"
assert_contains "Metric token_count preserved" "$result" "token_count=123456789"

# Short passwords (< 4 chars) should not be redacted
result=$(redact_and_read "short_pw.txt" "PASSWORD=abc")
assert_not_contains "Short password not redacted" "$result" "<REDACTED"

# ============================================================
# Tests: Binary file handling
# ============================================================
echo ""
echo "=== Binary File Handling ==="

# Create a file with null bytes (binary). Bundle-local binary copies fail closed:
# keep the file path for manifest inventory, but replace opaque bytes with a marker.
printf 'sk-secretkey1234567890abcdef\x00binary' > "$TEST_DIR/binary.bin"
REDACTION_COUNT=0
redact_file "$TEST_DIR/binary.bin"
binary_result=$(cat "$TEST_DIR/binary.bin")
assert_equals "Binary file replaced with marker" "$binary_result" "<REDACTED:binary_file>"
assert_redaction_count "Binary file replacement counted" 1

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
printf '%s\n' "{\"message\":\"Generated password for 'ubuntu': abcdefghijklmnopqrstuvwxyz123456\"}" > "$TEST_DIR/bundle/events.jsonl"
printf 'log: ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn\n' > "$TEST_DIR/bundle/logs/install.log"
printf '%s\n' "-----BEGIN PRIVATE KEY-----" "QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVo=" "-----END PRIVATE KEY-----" > "$TEST_DIR/bundle/logs/private-key.log"
printf 'safe content no secrets here\n' > "$TEST_DIR/bundle/clean.txt"
redact_bundle "$TEST_DIR/bundle"

state_content=$(cat "$TEST_DIR/bundle/state.json")
jsonl_content=$(cat "$TEST_DIR/bundle/events.jsonl")
log_content=$(cat "$TEST_DIR/bundle/logs/install.log")
private_key_content=$(cat "$TEST_DIR/bundle/logs/private-key.log")
assert_contains "Bundle: state.json redacted" "$state_content" "<REDACTED:api_key>"
assert_contains "Bundle: events.jsonl redacted" "$jsonl_content" "<REDACTED:password>"
assert_not_contains "Bundle: events.jsonl password removed" "$jsonl_content" "abcdefghijklmnopqrstuvwxyz123456"
assert_contains "Bundle: install.log redacted" "$log_content" "<REDACTED:github_token>"
assert_contains "Bundle: private key redacted" "$private_key_content" "<REDACTED:private_key>"
assert_not_contains "Bundle: private key payload removed" "$private_key_content" "QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVo="
if [[ "$REDACTION_COUNT" -ge 4 ]]; then
    pass "Bundle: redaction count >= 4"
else
    fail "Bundle: redaction count >= 4" "Got $REDACTION_COUNT"
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
