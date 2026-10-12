#!/usr/bin/env bash
# Exercise real retained descriptors on macOS fdescfs and Linux procfs.
# Preserve fixtures and snapshots; no cleanup bypass or fake identity checks.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Optional first argument lets the exact oracle exercise an incumbent library.
# shellcheck source=../../scripts/lib/security.sh
source "${1:-$REPO_ROOT/scripts/lib/security.sh}"

ACFS_SECURITY_RETAIN_TEMP_FILES=true
fixture="$(mktemp -d "${TMPDIR:-/tmp}/acfs-fd-identity.XXXXXX")"
printf 'Retaining descriptor test fixtures: %s\n' "$fixture" >&2
passed=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
accept() {
    local label="$1"
    shift
    "$@" || fail "$label"
    printf 'PASS: %s\n' "$label" >&2
    passed=$((passed + 1))
}
reject() {
    local label="$1"
    shift
    if "$@"; then fail "$label was accepted"; fi
    printf 'PASS: %s\n' "$label" >&2
    passed=$((passed + 1))
}

printf 'original policy\n' > "$fixture/policy"
printf 'different inode\n' > "$fixture/other"
test_snapshot="" test_identity_fd="" test_digest=""
accept 'regular policy opens a bound snapshot' acfs_security_open_bound_snapshot \
    "$fixture/policy" 1024 "$fixture/snapshot.XXXXXX" 'test policy' \
    test_snapshot test_identity_fd test_digest
accept 'snapshot bytes match the input' cmp "$fixture/policy" "$test_snapshot"
(
    exec {probe_fd}< "$fixture/policy"
    acfs_security_close_fd "$probe_fd"
    printf 'stderr remains connected\n' >&2
) 2> "$fixture/stderr-probe"
accept 'closing a descriptor preserves stderr' grep -Fx 'stderr remains connected' "$fixture/stderr-probe"
accept 'unchanged bound snapshot remains current' acfs_security_bound_snapshot_is_current \
    "$fixture/policy" "$test_identity_fd" "$test_digest" 1024 'test policy'

exec {second_fd}< "$fixture/policy"
exec {other_fd}< "$fixture/other"
exec {directory_fd}< "$fixture"
accept 'two handles for the same regular file match' acfs_security_fd_matches_path \
    "$fixture/policy" "$test_identity_fd" "$second_fd"
reject 'a different source inode cannot match' acfs_security_fd_matches_path \
    "$fixture/other" "$test_identity_fd"
reject 'a different comparison handle cannot match' acfs_security_fd_matches_path \
    "$fixture/policy" "$test_identity_fd" "$other_fd"
reject 'a directory descriptor cannot match' acfs_security_fd_matches_path \
    "$fixture/policy" "$directory_fd"
ln -s "$fixture/policy" "$fixture/symlink"
reject 'a symlink source cannot match' acfs_security_fd_matches_path \
    "$fixture/symlink" "$test_identity_fd"
reject 'a missing path cannot match' acfs_security_fd_matches_path \
    "$fixture/missing" "$test_identity_fd"
reject 'a nonnumeric descriptor cannot match' acfs_security_fd_matches_path \
    "$fixture/policy" 'invalid'

# Same inode, changed contents: identity alone must not authorize emission.
printf 'changed policy\n' >> "$fixture/policy"
reject 'changed bytes invalidate the retained snapshot' acfs_security_bound_snapshot_is_current \
    "$fixture/policy" "$test_identity_fd" "$test_digest" 1024 'test policy'
acfs_security_close_fd "$test_identity_fd"
acfs_security_close_fd "$second_fd"
acfs_security_close_fd "$other_fd"
acfs_security_close_fd "$directory_fd"
printf 'PASS: %s descriptor and byte-binding checks\n' "$passed"

# The monitor must be able to advance trusted pins while external review waits,
# using the same complete report rather than a fabricated match partition.
command cp "$REPO_ROOT/checksums.yaml" "$fixture/current.yaml"
declare -A fixture_urls=() fixture_hashes=()
acfs_load_checksums_strict "$fixture/current.yaml" fixture_urls fixture_hashes
fixture_digest="$(calculate_file_sha256 "$fixture/current.yaml")"
trusted_actual="$(printf 'a%.0s' {1..64})"
external_actual="$(printf 'b%.0s' {1..64})"
[[ "${fixture_hashes[br]}" != "$trusted_actual" && "${fixture_hashes[omp]}" != "$external_actual" ]] \
    || fail 'fixture hashes accidentally equal observations'
for fixture_tool in "${!fixture_hashes[@]}"; do
    fixture_actual="${fixture_hashes[$fixture_tool]}"
    if [[ "$fixture_tool" == br ]]; then fixture_actual="$trusted_actual"; fi
    if [[ "$fixture_tool" == omp ]]; then fixture_actual="$external_actual"; fi
    jq -cn --arg name "$fixture_tool" --arg url "${fixture_urls[$fixture_tool]}" \
        --arg expected "${fixture_hashes[$fixture_tool]}" --arg actual "$fixture_actual" \
        '{name:$name,url:$url,expected:$expected,actual:$actual}'
done > "$fixture/observations.jsonl"
jq -cs --arg digest "$fixture_digest" '{
    schema:"acfs.installer-checksum-verification.v1", schemaVersion:1,
    timestamp:"2026-10-12T00:00:00Z", checksumsYamlSha256:$digest, total:length,
    matches:[.[] | select(.actual == .expected) | {name,url,checksum:.expected}],
    mismatches:[.[] | select(.actual != .expected)], errors:[], skipped:[]
}' "$fixture/observations.jsonl" > "$fixture/report.json"

accept 'offline builder accepts complete observations' acfs_build_checksum_candidate \
    "$fixture/current.yaml" "$fixture/report.json" > "$fixture/full.yaml"
accept 'strict default accepts the full mismatch set' acfs_validate_checksum_candidate \
    "$fixture/current.yaml" "$fixture/full.yaml" "$fixture/report.json" > "$fixture/full-validated.yaml"
accept 'offline subset builder selects the trusted mismatch' acfs_build_checksum_candidate \
    "$fixture/current.yaml" "$fixture/report.json" omp > "$fixture/subset.yaml"
declare -A subset_urls=() subset_hashes=()
acfs_load_checksums_strict "$fixture/subset.yaml" subset_urls subset_hashes
accept 'trusted pin advances to the first observation' test "${subset_hashes[br]}" = "$trusted_actual"
accept 'unapproved external pin remains unchanged' test "${subset_hashes[omp]}" = "${fixture_hashes[omp]}"
for fixture_tool in "${!fixture_hashes[@]}"; do
    accept "URL remains unchanged: $fixture_tool" test "${subset_urls[$fixture_tool]}" = "${fixture_urls[$fixture_tool]}"
    if [[ "$fixture_tool" != br ]]; then
        accept "unselected pin remains unchanged: $fixture_tool" test "${subset_hashes[$fixture_tool]}" = "${fixture_hashes[$fixture_tool]}"
    fi
done
accept 'explicit subset validates with the complete original report' acfs_validate_checksum_candidate \
    "$fixture/current.yaml" "$fixture/subset.yaml" "$fixture/report.json" omp > "$fixture/subset-validated.yaml"
reject 'strict default still rejects a partial mismatch set' acfs_validate_checksum_candidate \
    "$fixture/current.yaml" "$fixture/subset.yaml" "$fixture/report.json" > "$fixture/rejected-default"
reject 'selection rejects a change to an unselected external pin' acfs_validate_checksum_candidate \
    "$fixture/current.yaml" "$fixture/full.yaml" "$fixture/report.json" omp > "$fixture/rejected-unselected"
reject 'selection rejects a missing selected change' acfs_validate_checksum_candidate \
    "$fixture/current.yaml" "$fixture/subset.yaml" "$fixture/report.json" br > "$fixture/rejected-missing"

for bad_selection in '' br,br missing bun ',br' 'br,' 'br omp'; do
    reject "builder rejects invalid selection: [$bad_selection]" acfs_build_checksum_candidate \
        "$fixture/current.yaml" "$fixture/report.json" "$bad_selection" > "$fixture/rejected-selection-${passed}"
    reject "validator rejects invalid selection: [$bad_selection]" acfs_validate_checksum_candidate \
        "$fixture/current.yaml" "$fixture/subset.yaml" "$fixture/report.json" "$bad_selection" > "$fixture/rejected-selection-${passed}"
done
reject 'builder rejects repeated deferred names' acfs_build_checksum_candidate \
    "$fixture/current.yaml" "$fixture/report.json" omp omp > "$fixture/rejected-duplicate-builder"
reject 'validator rejects repeated deferred names' acfs_validate_checksum_candidate \
    "$fixture/current.yaml" "$fixture/subset.yaml" "$fixture/report.json" omp omp > "$fixture/rejected-duplicate-validator"

jq -c '.checksumsYamlSha256 = ("0" * 64)' "$fixture/report.json" > "$fixture/forged-digest.json"
jq -c '.mismatches[0].expected = ("0" * 64)' "$fixture/report.json" > "$fixture/forged-expected.json"
jq -c '.mismatches[0].url = "https://example.com/forged"' "$fixture/report.json" > "$fixture/forged-url.json"
jq -c '.matches |= .[1:]' "$fixture/report.json" > "$fixture/incomplete.json"
jq -c '.errors = [{name:.matches[0].name,url:.matches[0].url,error:"network failure"}] | .matches |= .[1:]' \
    "$fixture/report.json" > "$fixture/error.json"
jq -c '.skipped = [{name:.matches[0].name,url:.matches[0].url,reason:"unavailable"}] | .matches |= .[1:]' \
    "$fixture/report.json" > "$fixture/skipped.json"
for bad_report in forged-digest forged-expected forged-url incomplete error skipped; do
    reject "builder rejects $bad_report evidence without output" acfs_build_checksum_candidate \
        "$fixture/current.yaml" "$fixture/$bad_report.json" br > "$fixture/rejected-$bad_report"
    accept "$bad_report emitted no candidate bytes" test ! -s "$fixture/rejected-$bad_report"
    reject "validator rejects $bad_report evidence" acfs_validate_checksum_candidate \
        "$fixture/current.yaml" "$fixture/subset.yaml" "$fixture/$bad_report.json" br > "$fixture/rejected-validator-$bad_report"
done

reject 'offline builder rejects symlink policy' acfs_build_checksum_candidate \
    "$fixture/symlink" "$fixture/report.json" br > "$fixture/rejected-symlink"
ln "$fixture/current.yaml" "$fixture/policy-alias.yaml"
reject 'offline builder rejects policy/report hard-link aliases' acfs_build_checksum_candidate \
    "$fixture/current.yaml" "$fixture/policy-alias.yaml" br > "$fixture/rejected-hardlink"
command cp "$fixture/report.json" "$fixture/race-report.json"
command cp "$fixture/current.yaml" "$fixture/race-policy.yaml"
if (
    race_armed=false
    acfs_security_date() {
        if [[ "$race_armed" == true ]]; then
            printf '# concurrent writer changed the policy\n' >> "$fixture/race-policy.yaml"
        fi
        command date "$@"
    }
    acfs_security_date -Iseconds > "$fixture/date-probe"
    race_armed=true
    acfs_build_checksum_candidate "$fixture/race-policy.yaml" "$fixture/race-report.json" br
) > "$fixture/rejected-race"; then fail 'offline builder accepted a changed original policy'; fi
accept 'source race emitted no candidate bytes' test ! -s "$fixture/rejected-race"
printf 'PASS: %s total descriptor, evidence and candidate checks\n' "$passed"
