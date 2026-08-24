#!/usr/bin/env bats

load '../test_helper'

setup() {
    common_setup
    source_lib "logging"
    source_lib "security"
    
    # Create dummy checksums file
    export CHECKSUMS_FILE=$(create_temp_file)
}

teardown() {
    common_teardown
}

write_security_checksums_fixture() {
    local output_file="$1"
    local tool=""
    local checksum=""
    local index=1

    printf 'installers:\n' > "$output_file"
    for tool in "${ACFS_SECURITY_REQUIRED_INSTALLERS[@]}"; do
        printf -v checksum '%064d' "$index"
        printf '  %s:\n' "$tool" >> "$output_file"
        printf '    url: "%s"\n' "${KNOWN_INSTALLERS[$tool]}" >> "$output_file"
        printf '    sha256: "%s"\n' "$checksum" >> "$output_file"
        index=$((index + 1))
    done
}

stub_acfs_curl_response() {
    STUB_ACFS_CURL_CONTENT="$1"
    STUB_ACFS_CURL_EXIT_CODE="${2:-0}"

    acfs_curl() {
        local output_file=""
        local args=("$@")
        local i

        for ((i=0; i<${#args[@]}; i++)); do
            if [[ "${args[$i]}" == "-o" ]]; then
                output_file="${args[$((i+1))]}"
                break
            fi
        done

        if [[ -n "$output_file" ]]; then
            printf '%s' "$STUB_ACFS_CURL_CONTENT" > "$output_file"
        else
            printf '%s' "$STUB_ACFS_CURL_CONTENT"
        fi

        return "$STUB_ACFS_CURL_EXIT_CODE"
    }
}

@test "enforce_https: allows https" {
    run enforce_https "https://example.com"
    assert_success
}

@test "enforce_https: blocks http" {
    run enforce_https "http://example.com"
    assert_failure
}

@test "verify_checksum: passes on match" {
    local content="verified content"
    local sha
    if command -v sha256sum &>/dev/null; then
        sha=$(echo -n "$content" | sha256sum | cut -d' ' -f1)
    else
        sha=$(echo -n "$content" | shasum -a 256 | cut -d' ' -f1)
    fi

    stub_acfs_curl_response "$content" 0

    run verify_checksum "https://example.com" "$sha" "test"
    assert_success
    assert_output --partial "$content"
    assert_output --partial "Verified: test"
}

@test "verify_checksum: clears RETURN cleanup trap after success" {
    local security_lib="$PROJECT_ROOT/scripts/lib/security.sh"

    run bash -c '
        set -euo pipefail
        source "$1"
        acfs_download_to_file() {
            printf "%s" "verified content" > "$2"
        }
        sha="$(printf "%s" "verified content" | sha256sum | cut -d" " -f1)"
        verify_checksum "https://example.com" "$sha" "test" >/dev/null 2>&1
        trap -p RETURN
    ' _ "$security_lib"
    assert_success
    assert_output ""
}

@test "fetch_checksum: clears RETURN cleanup trap after success" {
    local security_lib="$PROJECT_ROOT/scripts/lib/security.sh"

    run bash -c '
        set -euo pipefail
        source "$1"
        acfs_download_to_file() {
            printf "%s" "verified content" > "$2"
        }
        fetch_checksum "https://example.com" >/dev/null
        trap -p RETURN
    ' _ "$security_lib"
    assert_success
    assert_output ""
}

@test "verify_checksum: preserves caller RETURN trap" {
    local security_lib="$PROJECT_ROOT/scripts/lib/security.sh"

    run bash -c '
        set -euo pipefail
        source "$1"
        acfs_download_to_file() {
            printf "%s" "verified content" > "$2"
        }
        sha="$(printf "%s" "verified content" | sha256sum | cut -d" " -f1)"
        probe_return_trap() {
            trap "caller_return_seen=1" RETURN
            verify_checksum "https://example.com" "$sha" "test" >/dev/null 2>&1
            trap -p RETURN
        }
        probe_return_trap
    ' _ "$security_lib"
    assert_success
    assert_output --partial "caller_return_seen=1"
}

@test "fetch_checksum: preserves caller RETURN trap" {
    local security_lib="$PROJECT_ROOT/scripts/lib/security.sh"

    run bash -c '
        set -euo pipefail
        source "$1"
        acfs_download_to_file() {
            printf "%s" "verified content" > "$2"
        }
        probe_return_trap() {
            trap "caller_return_seen=1" RETURN
            fetch_checksum "https://example.com" >/dev/null 2>&1
            trap -p RETURN
        }
        probe_return_trap
    ' _ "$security_lib"
    assert_success
    assert_output --partial "caller_return_seen=1"
}

@test "fetch_and_run_with_recovery: preserves caller RETURN trap" {
    local security_lib="$PROJECT_ROOT/scripts/lib/security.sh"

    run bash -c '
        set -euo pipefail
        source "$1"
        acfs_download_to_file() {
            printf "%s" "printf ok" > "$2"
        }
        bash() {
            return 0
        }
        sha="$(printf "%s" "printf ok" | sha256sum | cut -d" " -f1)"
        probe_return_trap() {
            trap "caller_return_seen=1" RETURN
            fetch_and_run_with_recovery "https://example.com/install.sh" "$sha" "test" >/dev/null 2>&1
            trap -p RETURN
        }
        probe_return_trap
    ' _ "$security_lib"
    assert_success
    assert_output --partial "caller_return_seen=1"
}

@test "verify_checksum: fails on mismatch" {
    local content="malicious content"
    local sha="0000000000000000000000000000000000000000000000000000000000000000"

    stub_acfs_curl_response "$content" 0
    
    run verify_checksum "https://example.com" "$sha" "test"
    assert_failure
    assert_output --partial "Checksum mismatch"
}

@test "verify_checksum: rejects trusted-owner mismatch without refreshed checksum" {
    local security_lib="$PROJECT_ROOT/scripts/lib/security.sh"

    run bash -c '
        source "$1"
        acfs_download_to_file() {
            printf "%s" "changed trusted content" > "$2"
        }
        acfs_refresh_loaded_checksums_from_remote() {
            return 1
        }
        verify_checksum \
            "https://raw.githubusercontent.com/Dicklesworthstone/example/main/install.sh" \
            "0000000000000000000000000000000000000000000000000000000000000000" \
            "trusted_tool"
    ' _ "$security_lib"

    assert_failure
    assert_output --partial "Checksum mismatch"
    refute_output --partial "Trusted-tool auto-accept"
}

@test "acfs_curl: ignores shell function curl" {
    local security_lib="$PROJECT_ROOT/scripts/lib/security.sh"
    local marker="${BATS_TEST_TMPDIR:-/tmp}/acfs-curl-poison-marker"

    run bash -c '
        set -euo pipefail
        marker="$1"
        security_lib="$2"
        curl() {
            printf "poisoned\n" > "$marker"
            return 42
        }
        source "$security_lib"
        set +e
        acfs_curl "https://127.0.0.1:9/" >/dev/null 2>&1
        status=$?
        set -e
        [[ ! -e "$marker" ]]
        exit "$status"
    ' _ "$marker" "$security_lib"

    assert_failure
    [[ ! -e "$marker" ]]
}

@test "acfs_curl: refreshes stale cached curl path" {
    local security_lib="$PROJECT_ROOT/scripts/lib/security.sh"

    run bash -c '
        set -euo pipefail
        security_lib="$1"
        source "$security_lib"
        ACFS_CURL_BIN="/tmp/acfs-missing-curl"
        set +e
        acfs_curl "https://127.0.0.1:9/" >/dev/null 2>&1
        status=$?
        set -e
        [[ "$status" -ne 127 ]]
        [[ "$ACFS_CURL_BIN" = /* ]]
        [[ -x "$ACFS_CURL_BIN" ]]
    ' _ "$security_lib"

    assert_success
}

@test "acfs_download_to_file: treats root-level output parent as slash" {
    local recorded_dir="$BATS_TEST_TMPDIR/security-recorded-output-dir"

    acfs_security_mkdir_p() {
        printf '%s' "$1" > "$recorded_dir"
        [[ "$1" == "/" ]]
    }

    acfs_curl() {
        return 0
    }

    run acfs_download_to_file "https://example.com/install.sh" "/acfs-root-output" "root-target"
    assert_success
    assert_equal "$(cat "$recorded_dir")" "/"
}

@test "calculate_file_sha256: ignores shell function sha256sum" {
    local security_lib="$PROJECT_ROOT/scripts/lib/security.sh"
    local probe_file="${BATS_TEST_TMPDIR:-/tmp}/acfs-sha-poison-probe"

    run bash -c '
        set -euo pipefail
        probe_file="$1"
        security_lib="$2"
        printf "%s" "real-content" > "$probe_file"
        source "$security_lib"
        expected="$(calculate_file_sha256 "$probe_file")"
        sha256sum() {
            printf "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff  %s\n" "$1"
        }
        actual="$(calculate_file_sha256 "$probe_file")"
        [[ "$actual" == "$expected" ]]
        [[ "$actual" != "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" ]]
    ' _ "$probe_file" "$security_lib"

    assert_success
}

@test "verify_checksum: emits verified bytes with trusted cat and mktemp" {
    local security_lib="$PROJECT_ROOT/scripts/lib/security.sh"
    local fake_bin="$BATS_TEST_TMPDIR/security-fake-bin"
    local marker_dir="$BATS_TEST_TMPDIR/security-markers"
    local probe_file="$BATS_TEST_TMPDIR/security-expected-content"

    mkdir -p "$fake_bin" "$marker_dir"
    for tool in cat mktemp realpath; do
        cat > "$fake_bin/$tool" <<EOF
#!/usr/bin/env bash
: > "$marker_dir/$tool"
printf 'poisoned-%s' "$tool"
exit 0
EOF
        chmod +x "$fake_bin/$tool"
    done

    local system_bash
    system_bash="$(command -v bash)"
    run env PATH="$fake_bin:/usr/bin:/bin" "$system_bash" -s -- "$security_lib" "$probe_file" "$marker_dir" <<'EOF_TRUSTED_CAT'
set -euo pipefail
security_lib="$1"
probe_file="$2"
marker_dir="$3"
content='printf "trusted installer\n"'

# shellcheck source=/dev/null
source "$security_lib"

acfs_download_to_file() {
    printf '%s' "$content" > "$2"
}

printf '%s' "$content" > "$probe_file"
expected="$(calculate_file_sha256 "$probe_file")"
actual="$(verify_checksum "https://example.com/install.sh" "$expected" "test" 2>/dev/null)"

[[ "$actual" == "$content" ]]
[[ ! -e "$marker_dir/cat" ]]
[[ ! -e "$marker_dir/mktemp" ]]
[[ ! -e "$marker_dir/realpath" ]]
EOF_TRUSTED_CAT

    assert_success
}

@test "fetch_and_run: executes verified installer with trusted bash" {
    local security_lib="$PROJECT_ROOT/scripts/lib/security.sh"
    local fake_bin="$BATS_TEST_TMPDIR/security-fake-bash-bin"
    local marker="$BATS_TEST_TMPDIR/fake-bash-used"
    local probe_file="$BATS_TEST_TMPDIR/security-fetch-run-content"

    mkdir -p "$fake_bin"
    cat > "$fake_bin/bash" <<EOF
#!/bin/sh
if [ "\${1:-}" = "--probe" ]; then exit 0; fi
: > "$marker"
printf 'poisoned bash\n'
exit 0
EOF
    chmod +x "$fake_bin/bash"
    "$fake_bin/bash" --probe

    local system_bash
    system_bash="$(command -v bash)"
    run env PATH="$fake_bin:/usr/bin:/bin" "$system_bash" -s -- "$security_lib" "$probe_file" "$marker" <<'EOF_TRUSTED_PIPE_BASH'
set -euo pipefail
security_lib="$1"
probe_file="$2"
marker="$3"
content='printf "trusted-run:%s\n" "$1"'

# shellcheck source=/dev/null
source "$security_lib"

acfs_download_to_file() {
    printf '%s' "$content" > "$2"
}

printf '%s' "$content" > "$probe_file"
expected="$(calculate_file_sha256 "$probe_file")"
fetch_and_run "https://example.com/install.sh" "$expected" "test" "arg1"
[[ ! -e "$marker" ]]
EOF_TRUSTED_PIPE_BASH

    assert_success
    assert_output --partial "trusted-run:arg1"
    refute_output --partial "poisoned bash"
    [[ ! -e "$marker" ]]
}

@test "fetch_and_run: never executes a prefix when verification fails after producing bytes" {
    local security_lib="$PROJECT_ROOT/scripts/lib/security.sh"
    local marker="$BATS_TEST_TMPDIR/partial-installer-executed"

    local system_bash
    system_bash="$(command -v bash)"
    run "$system_bash" -s -- "$security_lib" "$marker" <<'EOF_NO_PARTIAL_EXECUTION'
set -euo pipefail
security_lib="$1"
marker="$2"

# shellcheck source=/dev/null
source "$security_lib"

# Model a late producer failure: an interpreter pipeline would execute this
# complete first command before learning that verification failed.
verify_checksum() {
    printf '%s\n' 'printf executed > "$1"'
    return 91
}

set +e
fetch_and_run "https://example.com/install.sh" "expected" "test" "$marker"
status=$?
set -e

[[ "$status" -eq 91 ]]
[[ ! -e "$marker" ]]
EOF_NO_PARTIAL_EXECUTION

    assert_success
    [[ ! -e "$marker" ]]
}

@test "production verified installer call sites do not use producer pipelines" {
    run grep -nE 'verify_checksum[^#]*\|' \
        "$PROJECT_ROOT"/scripts/lib/*.sh \
        "$PROJECT_ROOT"/scripts/generated/*.sh \
        "$PROJECT_ROOT/acfs.manifest.yaml"

    assert_failure
    assert_output ""
}

@test "fetch_and_run_with_recovery: executes verified file with trusted bash" {
    local security_lib="$PROJECT_ROOT/scripts/lib/security.sh"
    local fake_bin="$BATS_TEST_TMPDIR/security-fake-recovery-bin"
    local marker="$BATS_TEST_TMPDIR/fake-recovery-bash-used"
    local probe_file="$BATS_TEST_TMPDIR/security-recovery-run-content"

    mkdir -p "$fake_bin"
    cat > "$fake_bin/bash" <<EOF
#!/bin/sh
if [ "\${1:-}" = "--probe" ]; then exit 0; fi
: > "$marker"
printf 'poisoned recovery bash\n'
exit 0
EOF
    chmod +x "$fake_bin/bash"
    "$fake_bin/bash" --probe

    local system_bash
    system_bash="$(command -v bash)"
    run env PATH="$fake_bin:/usr/bin:/bin" "$system_bash" -s -- "$security_lib" "$probe_file" "$marker" <<'EOF_TRUSTED_FILE_BASH'
set -euo pipefail
security_lib="$1"
probe_file="$2"
marker="$3"
content='printf "trusted-recovery:%s\n" "$1"'

# shellcheck source=/dev/null
source "$security_lib"

acfs_download_to_file() {
    printf '%s' "$content" > "$2"
}

printf '%s' "$content" > "$probe_file"
expected="$(calculate_file_sha256 "$probe_file")"
fetch_and_run_with_recovery "https://example.com/install.sh" "$expected" "test" "arg2"
[[ ! -e "$marker" ]]
EOF_TRUSTED_FILE_BASH

    assert_success
    assert_output --partial "trusted-recovery:arg2"
    refute_output --partial "poisoned recovery bash"
    [[ ! -e "$marker" ]]
}

@test "load_checksums: parses yaml" {
    # Need full 64-char sha256 for regex
    local sha1="1111111111111111111111111111111111111111111111111111111111111111"
    local sha2="2222222222222222222222222222222222222222222222222222222222222222"
    local sha3="3333333333333333333333333333333333333333333333333333333333333333"

    cat > "$CHECKSUMS_FILE" <<EOF
installers:
  tool1:
    url: "https://example.com/1"
    sha256: "$sha1"
  tool2:
    url: 'https://example.com/2'
    sha256: "$sha2"
  tool3:
    url: https://example.com/3
    sha256: "$sha3"
EOF

    echo "DEBUG: CHECKSUMS_FILE=$CHECKSUMS_FILE" >&2
    cat "$CHECKSUMS_FILE" >&2

    # load_checksums populates global LOADED_CHECKSUMS
    # Since we use 'run', variables are lost.
    # We must call it directly to test state.
    
    load_checksums
    assert_equal "$?" "0"
    
    # Use get_checksum accessor
    local val1
    val1=$(get_checksum "tool1")
    echo "DEBUG: val1='$val1'" >&2
    assert_equal "$val1" "$sha1"
    
    local val2
    val2=$(get_checksum "tool2")
    assert_equal "$val2" "$sha2"

    local val3
    val3=$(get_checksum "tool3")
    assert_equal "$val3" "$sha3"

    assert_equal "${KNOWN_INSTALLERS[tool1]}" "https://example.com/1"
    assert_equal "${KNOWN_INSTALLERS[tool2]}" "https://example.com/2"
    assert_equal "${KNOWN_INSTALLERS[tool3]}" "https://example.com/3"
}

@test "load_checksums: failed reload preserves previous checksum state" {
    local good_sha="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    local bad_file
    bad_file="$(create_temp_file)"

    declare -gA LOADED_CHECKSUMS=()
    KNOWN_INSTALLERS["txn_tool"]="https://example.com/old"

    cat > "$CHECKSUMS_FILE" <<EOF
installers:
  txn_tool:
    url: "https://example.com/good"
    sha256: "$good_sha"
EOF

    load_checksums
    assert_equal "$?" "0"
    assert_equal "$(get_checksum "txn_tool")" "$good_sha"
    assert_equal "${KNOWN_INSTALLERS["txn_tool"]}" "https://example.com/good"

    cat > "$bad_file" <<'EOF'
installers:
  txn_tool:
    url: "https://example.com/bad"
    sha256: "not-a-valid-sha"
EOF

    if load_checksums "$bad_file"; then
        fail "malformed checksums reload unexpectedly succeeded"
    fi
    assert_equal "$(get_checksum "txn_tool")" "$good_sha"
    assert_equal "${KNOWN_INSTALLERS["txn_tool"]}" "https://example.com/good"
}

@test "load_checksums: rejects sha256 scalars with trailing garbage" {
    local good_sha="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    local bad_file
    bad_file="$(create_temp_file)"

    declare -gA LOADED_CHECKSUMS=()
    KNOWN_INSTALLERS["txn_tool"]="https://example.com/old"

    cat > "$CHECKSUMS_FILE" <<EOF
installers:
  txn_tool:
    url: "https://example.com/good"
    sha256: "$good_sha"
EOF

    load_checksums
    assert_equal "$?" "0"
    assert_equal "$(get_checksum "txn_tool")" "$good_sha"
    assert_equal "${KNOWN_INSTALLERS["txn_tool"]}" "https://example.com/good"

    cat > "$bad_file" <<EOF
installers:
  txn_tool:
    url: "https://example.com/bad"
    sha256: "${good_sha}trailing"
EOF

    if load_checksums "$bad_file"; then
        fail "checksum with trailing garbage unexpectedly loaded"
    fi
    assert_equal "$(get_checksum "txn_tool")" "$good_sha"
    assert_equal "${KNOWN_INSTALLERS["txn_tool"]}" "https://example.com/good"
}

@test "acfs_checksums_file_looks_valid: requires complete installer metadata" {
    local full_file
    local partial_file
    full_file="$(create_temp_file)"
    partial_file="$(create_temp_file)"

    write_security_checksums_fixture "$full_file"
    cat > "$partial_file" <<'EOF'
installers:
  mcp_agent_mail:
    url: "https://raw.githubusercontent.com/Dicklesworthstone/mcp_agent_mail_rust/refs/heads/main/install.sh"
    sha256: "1111111111111111111111111111111111111111111111111111111111111111"
EOF

    run acfs_checksums_file_looks_valid "$full_file"
    assert_success

    run acfs_checksums_file_looks_valid "$partial_file"
    assert_failure
}

@test "acfs_checksums_file_looks_valid: ignores dynamic local installer keys" {
    local full_file
    full_file="$(create_temp_file)"

    write_security_checksums_fixture "$full_file"
    KNOWN_INSTALLERS["local_only_tool"]="https://example.com/local-only.sh"

    run acfs_checksums_file_looks_valid "$full_file"
    assert_success
}

@test "acfs_refresh_loaded_checksums_from_remote: partial remote metadata preserves loaded state" {
    local existing_sha="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

    declare -gA LOADED_CHECKSUMS=([sentinel_tool]="$existing_sha")
    ACFS_CHECKSUMS_REMOTE_REFRESHED=false

    acfs_curl() {
        local output_file=""
        local args=("$@")
        local i

        for ((i=0; i<${#args[@]}; i++)); do
            if [[ "${args[$i]}" == "-o" ]]; then
                output_file="${args[$((i+1))]}"
                break
            fi
        done

        cat > "$output_file" <<'EOF'
installers:
  mcp_agent_mail:
    url: "https://raw.githubusercontent.com/Dicklesworthstone/mcp_agent_mail_rust/refs/heads/main/install.sh"
    sha256: "1111111111111111111111111111111111111111111111111111111111111111"
EOF
        return 0
    }

    acfs_download_to_file() {
        cat > "$2" <<'EOF'
installers:
  dcg:
    url: "https://raw.githubusercontent.com/Dicklesworthstone/destructive_command_guard/main/install.sh"
    sha256: "2222222222222222222222222222222222222222222222222222222222222222"
EOF
        return 0
    }

    if acfs_refresh_loaded_checksums_from_remote; then
        fail "partial remote checksums unexpectedly refreshed loaded state"
    fi

    assert_equal "$(get_checksum "sentinel_tool")" "$existing_sha"
    assert_equal "$ACFS_CHECKSUMS_REMOTE_REFRESHED" "false"
}
