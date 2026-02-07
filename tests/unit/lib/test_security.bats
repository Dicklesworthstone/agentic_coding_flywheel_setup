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

    # Stub curl to return content (handles -o flag)
    stub_curl "$content" 0

    run verify_checksum "https://example.com" "$sha" "test"
    assert_success
    assert_output --partial "$content"
    assert_output --partial "Verified: test"
}

@test "verify_checksum: fails on mismatch" {
    local content="malicious content"
    local sha="0000000000000000000000000000000000000000000000000000000000000000"

    stub_curl "$content" 0
    
    run verify_checksum "https://example.com" "$sha" "test"
    assert_failure
    assert_output --partial "Checksum mismatch"
}

@test "load_checksums: parses yaml" {
    # Need full 64-char sha256 for regex
    local sha1="1111111111111111111111111111111111111111111111111111111111111111"
    local sha2="2222222222222222222222222222222222222222222222222222222222222222"

    cat > "$CHECKSUMS_FILE" <<EOF
installers:
  tool1:
    url: "https://example.com/1"
    sha256: "$sha1"
  tool2:
    url: "https://example.com/2"
    sha256: "$sha2"
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
}
