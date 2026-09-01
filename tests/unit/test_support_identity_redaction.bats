#!/usr/bin/env bats
#
# Issue #369: acfs support-bundle failed closed because redaction never
# removed the raw target home from collected files (.zshrc, install logs,
# install summaries, doctor.json, state.json), so the final identity scan
# refused to create the archive on every real bundle. These tests exercise
# the identity-redaction pass against a fixture bundle containing each
# leaking form the reporter listed, plus JSON-escaped and binary variants,
# and prove the fail-closed verifier now passes -- and still fails when
# redaction is skipped.

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    SUPPORT_SH="$PROJECT_ROOT/scripts/lib/support.sh"

    # Logging stubs must exist before sourcing.
    log_step() { :; }
    log_section() { :; }
    log_detail() { :; }
    log_success() { :; }
    log_warn() { :; }
    log_error() { :; }
    log_info() { :; }

    # shellcheck source=../../scripts/lib/support.sh
    source "$SUPPORT_SH"

    REDACT=true
    REDACTION_COUNT=0
    VERBOSE=false

    # Fixture identity: a target home distinct from this machine's real
    # homes, plus a distinct collector home (root-run collection).
    SUPPORT_TARGET_HOME="/home/fixtureuser"
    _SUPPORT_CURRENT_HOME="/root"
    _SUPPORT_ACFS_HOME="/home/fixtureuser/.acfs"

    BUNDLE_DIR="$BATS_TEST_TMPDIR/bundle"
    mkdir -p "$BUNDLE_DIR/config" "$BUNDLE_DIR/logs"
}

# Populate the bundle with every leaking form from the issue report.
_write_leaky_bundle() {
    printf 'export PATH="%s/.cargo/bin:$PATH"\nexport ACFS_HOME="%s/.acfs"\n' \
        "$SUPPORT_TARGET_HOME" "$SUPPORT_TARGET_HOME" \
        > "$BUNDLE_DIR/config/.zshrc"
    printf '+ mkdir -p %s/.acfs\n+ chown fixtureuser %s/.zshrc\nHOME=%s\n' \
        "$SUPPORT_TARGET_HOME" "$SUPPORT_TARGET_HOME" "$_SUPPORT_CURRENT_HOME" \
        > "$BUNDLE_DIR/logs/install-20260830_214712.log"
    printf '{"target_home":"%s","cmd":"install -d %s/.local/bin"}\n' \
        "$SUPPORT_TARGET_HOME" "$SUPPORT_TARGET_HOME" \
        > "$BUNDLE_DIR/logs/install_summary_20260830_223352.json"
    # JSON-escaped form: \/home\/fixtureuser\/...
    printf '{"state_file":"\\/home\\/fixtureuser\\/.acfs\\/state.json"}\n' \
        > "$BUNDLE_DIR/doctor.json"
    printf '{"home":"%s","user":"fixtureuser"}\n' "$SUPPORT_TARGET_HOME" \
        > "$BUNDLE_DIR/state.json"
}

@test "identity redaction scrubs every leaking form and the fail-closed gate passes" {
    _write_leaky_bundle

    support_redact_identity "$BUNDLE_DIR"

    # No raw target or collector home anywhere in the bundle.
    ! grep -rF -- "$SUPPORT_TARGET_HOME" "$BUNDLE_DIR"
    ! grep -rF -- '\/home\/fixtureuser' "$BUNDLE_DIR"
    ! grep -rF -- "HOME=$_SUPPORT_CURRENT_HOME" "$BUNDLE_DIR"

    # Placeholders replace the values instead of deleting content.
    grep -qF '<REDACTED:target_home>/.cargo/bin' "$BUNDLE_DIR/config/.zshrc"
    grep -qF '+ mkdir -p <REDACTED:target_home>/.acfs' \
        "$BUNDLE_DIR/logs/install-20260830_214712.log"
    grep -qF '"target_home":"<REDACTED:target_home>"' \
        "$BUNDLE_DIR/logs/install_summary_20260830_223352.json"
    grep -qF '<REDACTED:target_home>' "$BUNDLE_DIR/doctor.json"
    grep -qF '"home":"<REDACTED:target_home>"' "$BUNDLE_DIR/state.json"
    grep -qF 'HOME=<REDACTED:collector_home>' \
        "$BUNDLE_DIR/logs/install-20260830_214712.log"

    # The final-byte postcondition scan now passes.
    SUPPORT_IDENTITY_SCAN_STATUS=""
    support_verify_identity_redaction "$BUNDLE_DIR"
    [[ "$SUPPORT_IDENTITY_SCAN_STATUS" == "pass" ]]
}

@test "verifier still fails closed when identity redaction did not run" {
    _write_leaky_bundle

    SUPPORT_IDENTITY_SCAN_STATUS=""
    ! support_verify_identity_redaction "$BUNDLE_DIR"
    [[ "$SUPPORT_IDENTITY_SCAN_STATUS" == "fail" ]]
}

@test "redact_bundle runs the identity pass over non-extension files too" {
    _write_leaky_bundle
    # A file outside redact_file's extension list still gets identity-scrubbed.
    printf 'target home is %s\n' "$SUPPORT_TARGET_HOME" \
        > "$BUNDLE_DIR/os-release-extra"

    redact_bundle "$BUNDLE_DIR"

    ! grep -rF -- "$SUPPORT_TARGET_HOME" "$BUNDLE_DIR"
    grep -qF '<REDACTED:target_home>' "$BUNDLE_DIR/os-release-extra"

    SUPPORT_IDENTITY_SCAN_STATUS=""
    support_verify_identity_redaction "$BUNDLE_DIR"
    [[ "$SUPPORT_IDENTITY_SCAN_STATUS" == "pass" ]]
}

@test "binary files holding the target home are blanked" {
    printf 'prefix\0%s\0suffix' "$SUPPORT_TARGET_HOME" \
        > "$BUNDLE_DIR/blob.bin"
    printf 'clean\0binary' > "$BUNDLE_DIR/clean.bin"

    support_redact_identity "$BUNDLE_DIR"

    [[ "$(cat "$BUNDLE_DIR/blob.bin")" == '<REDACTED:binary_file>' ]]
    # Binaries without identity content are left alone by this pass.
    grep -qF 'clean' "$BUNDLE_DIR/clean.bin"

    SUPPORT_IDENTITY_SCAN_STATUS=""
    support_verify_identity_redaction "$BUNDLE_DIR"
    [[ "$SUPPORT_IDENTITY_SCAN_STATUS" == "pass" ]]
}

@test "machine hostname is redacted from collected files" {
    local raw_hostname
    raw_hostname="$(hostname 2>/dev/null || true)"
    [[ -n "$raw_hostname" && "$raw_hostname" != "unknown" ]] \
        || skip "no usable hostname on this machine"

    printf 'collected on %s at boot\n' "$raw_hostname" \
        > "$BUNDLE_DIR/environment.txt"

    support_redact_identity "$BUNDLE_DIR"

    ! grep -rF -- "$raw_hostname" "$BUNDLE_DIR"
    grep -qF '<REDACTED:hostname>' "$BUNDLE_DIR/environment.txt"
}

@test "literal replacement treats regex metacharacters as data" {
    SUPPORT_TARGET_HOME='/home/fix.ture+user'
    printf 'path=%s/bin and also /home/fixXture+user/bin stays\n' \
        "$SUPPORT_TARGET_HOME" > "$BUNDLE_DIR/meta.txt"

    support_redact_identity "$BUNDLE_DIR"

    grep -qF 'path=<REDACTED:target_home>/bin' "$BUNDLE_DIR/meta.txt"
    # The dot must not act as a regex wildcard.
    grep -qF '/home/fixXture+user/bin stays' "$BUNDLE_DIR/meta.txt"
}

@test "candidate list is shared between redactor and verifier" {
    # Both sides derive from support_collect_identity_candidates, so the
    # builder must emit the expected labels for this fixture identity.
    support_collect_identity_candidates ""
    local joined="${_SUPPORT_IDENTITY_CANDIDATES[*]}"
    [[ "$joined" == *"target home /home/fixtureuser"* ]]
    [[ "$joined" == *"collector home /root"* ]]
    # ACFS home equal to <target>/.acfs is intentionally not a separate candidate.
    [[ "$joined" != *"ACFS home"* ]]
}
