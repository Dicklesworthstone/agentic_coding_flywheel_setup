#!/usr/bin/env bats
#
# Issue #387: install.sh's runtime install (install_asset calls) and
# scripts/lib/update.sh's runtime sync (file_pairs) are two hand-maintained
# lists of the same ~/.acfs runtime. holds.sh was in the update list but not
# the install list, so the `acfs hold` remediation printed by the checksum
# error did not exist on a fresh install. These tests pin the two lists to
# each other for every scripts/lib/*.sh runtime library so they cannot drift
# apart again, and check holds.sh specifically.

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    INSTALL_SH="$PROJECT_ROOT/install.sh"
    UPDATE_SH="$PROJECT_ROOT/scripts/lib/update.sh"
    GENERATE_TS="$PROJECT_ROOT/packages/manifest/src/generate.ts"
    DRIFT_SH="$PROJECT_ROOT/scripts/check-manifest-drift.sh"
}

# scripts/lib/*.sh sources that install.sh copies into the runtime.
_install_lib_sources() {
    grep -o 'install_asset "scripts/lib/[^"]*\.sh"' "$INSTALL_SH" \
        | sed 's/install_asset "//; s/"$//' | sort -u
}

# scripts/lib/*.sh sources in update.sh's file_pairs (repo side of "src:dst").
_update_lib_sources() {
    awk '
        /^    local -a file_pairs=\(/ { capture = 1; next }
        capture && /^    \)/ { exit }
        capture && /^ *"scripts\/lib\/[^":]*\.sh:/ {
            gsub(/"/, ""); sub(/^ +/, ""); sub(/:.*$/, ""); print
        }
    ' "$UPDATE_SH" | sort -u
}

@test "install.sh installs holds.sh into the runtime (acfs hold works on a fresh install)" {
    run grep -F 'install_asset "scripts/lib/holds.sh" "$ACFS_HOME/scripts/lib/holds.sh"' "$INSTALL_SH"
    [[ "$status" -eq 0 ]]
    # install_asset refuses anything outside the internal checksum ledger, so
    # the file must be a ledger member in every enumeration of that set.
    # Either quote style: the generator is formatted with double quotes now.
    grep -Eq "[\"']scripts/lib/holds\\.sh[\"']," "$GENERATE_TS"
    grep -Eq '^        scripts/lib/holds\.sh$' "$INSTALL_SH"
    grep -Eq '^    scripts/lib/holds\.sh$' "$DRIFT_SH"
    grep -Fq '[scripts/lib/holds.sh]=' "$PROJECT_ROOT/scripts/generated/internal_checksums.sh"
}

@test "every scripts/lib runtime library synced by update.sh is installed by install.sh" {
    local missing=""
    local src
    while IFS= read -r src; do
        [[ -n "$src" ]] || continue
        # The newproj wizard screens are installed by install.sh through a
        # loop over scripts/lib/newproj_screens/*.sh, not per-file calls.
        [[ "$src" == scripts/lib/newproj_screens/* ]] && continue
        if ! _install_lib_sources | grep -Fxq "$src"; then
            missing+="$src "
        fi
    done < <(_update_lib_sources)
    [[ -z "$missing" ]] || {
        echo "synced by update.sh but never installed by install.sh: $missing" >&2
        return 1
    }
}

@test "every scripts/lib runtime library installed by install.sh is synced by update.sh" {
    local missing=""
    local src
    while IFS= read -r src; do
        [[ -n "$src" ]] || continue
        if ! _update_lib_sources | grep -Fxq "$src"; then
            missing+="$src "
        fi
    done < <(_install_lib_sources)
    [[ -z "$missing" ]] || {
        echo "installed by install.sh but never refreshed by acfs update: $missing" >&2
        return 1
    }
}

@test "the parity helpers see both lists (guards against a silent empty comparison)" {
    local install_count update_count
    install_count="$(_install_lib_sources | wc -l | tr -d ' ')"
    update_count="$(_update_lib_sources | wc -l | tr -d ' ')"
    (( install_count > 40 ))
    (( update_count > 40 ))
    _install_lib_sources | grep -Fxq "scripts/lib/security.sh"
    _update_lib_sources | grep -Fxq "scripts/lib/security.sh"
}

@test "install.sh admits CHANGELOG.md as inert data and deploys it for acfs changelog" {
    # install_asset refuses anything outside the internal checksum ledger
    # unless it is declared inert rendered data; CHANGELOG.md is deliberately
    # outside the ledger so a changelog edit cannot break bootstrap.
    eval "$(sed -n '/^_acfs_internal_asset_is_rendered_data()/,/^}$/p' "$INSTALL_SH")"
    _acfs_internal_asset_is_rendered_data "CHANGELOG.md"
    _acfs_internal_asset_is_rendered_data "acfs/onboard/lessons/00_welcome.md"
    run _acfs_internal_asset_is_rendered_data "packages/x/CHANGELOG.md"
    [ "$status" -ne 0 ]
    run _acfs_internal_asset_is_rendered_data "scripts/lib/doctor.sh"
    [ "$status" -ne 0 ]
    grep -Fq 'install_asset "CHANGELOG.md" "$ACFS_HOME/CHANGELOG.md"' "$INSTALL_SH"
    grep -Fq '"CHANGELOG.md:CHANGELOG.md"' "$UPDATE_SH"
}
