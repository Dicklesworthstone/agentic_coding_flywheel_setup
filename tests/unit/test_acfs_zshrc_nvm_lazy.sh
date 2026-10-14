#!/usr/bin/env bash
# ============================================================
# acfs.zshrc nvm block: node bin resolved without forking
# (numeric glob sort == sort -V | tail -n 1), nvm.sh sourced only
# when `nvm` is first run.
# Usage: bash tests/unit/test_acfs_zshrc_nvm_lazy.sh
# ============================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ZSHRC="$REPO_ROOT/acfs/zsh/acfs.zshrc"

if ! command -v zsh >/dev/null 2>&1; then
    echo "SKIP: zsh not installed"
    exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/acfs-nvm-lazy.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# The nvm block only, so the test needs neither oh-my-zsh nor the other tools.
BLOCK="$WORK/nvm-block.zsh"
awk '/^# nvm \(Node Version Manager\)/{on=1} /^# Zoxide/{on=0} on' "$ZSHRC" > "$BLOCK"
if ! grep -q 'NVM_DIR/nvm.sh' "$BLOCK"; then
    echo "FAIL: could not extract the nvm block from $ZSHRC"
    exit 1
fi

PASS=0
FAIL=0
check() {
    local name="$1" want="$2" got="$3"
    if [[ "$got" == "$want" ]]; then
        PASS=$((PASS + 1)); echo "ok   $name"
    else
        FAIL=$((FAIL + 1)); echo "FAIL $name"; echo "     want: $want"; echo "     got:  $got"
    fi
}

make_nvm_dir() {
    local dir="$1"; shift
    mkdir -p "$dir"
    # Fake nvm.sh: records that it was sourced and defines the real `nvm`.
    cat > "$dir/nvm.sh" <<'EOF'
print -r -- sourced >> "$NVM_DIR/sourced.log"
nvm() { print -r -- "real-nvm $*"; }
EOF
    local v
    for v in "$@"; do
        mkdir -p "$dir/versions/node/$v/bin"
        printf '#!/bin/sh\n' > "$dir/versions/node/$v/bin/node"
        chmod +x "$dir/versions/node/$v/bin/node"
    done
}

# Runs the block in a clean zsh and prints: NVM_BIN|nvm.sh-sourced-count|type-of-nvm
run_block() {
    local nvm_dir="$1" pre="${2:-}"
    env -i HOME="$WORK" PATH="/usr/bin:/bin" NVM_DIR="$nvm_dir" ${NVM_BIN_PRESET:+NVM_BIN="$NVM_BIN_PRESET"} \
        zsh -f -c "$pre; source '$BLOCK'; print -r -- \"\${NVM_BIN#$nvm_dir/}|\$([[ -f \$NVM_DIR/sourced.log ]] && wc -l < \$NVM_DIR/sourced.log | tr -d ' ' || print 0)|\${\${PATH%%:*}#$nvm_dir/}\"" 2>&1
}

VERSIONS=(v9.11.2 v10.0.0 v22.9.0 v22.10.0 v22.10.1 v8.17.0)

D1="$WORK/nvm1"; make_nvm_dir "$D1" "${VERSIONS[@]}"
check "newest version by numeric order, nvm.sh not sourced" \
    "versions/node/v22.10.1/bin|0|versions/node/v22.10.1/bin" "$(run_block "$D1")"

D2="$WORK/nvm2"; make_nvm_dir "$D2" "${VERSIONS[@]}"; mkdir -p "$D2/alias"; printf 'v10.0.0\n' > "$D2/alias/default"
check "pinned default alias wins" \
    "versions/node/v10.0.0/bin|0|versions/node/v10.0.0/bin" "$(run_block "$D2")"

D3="$WORK/nvm3"; make_nvm_dir "$D3" "${VERSIONS[@]}"; mkdir -p "$D3/alias"; printf 'lts/*\n' > "$D3/alias/default"
check "symbolic default alias falls back to newest" \
    "versions/node/v22.10.1/bin|0|versions/node/v22.10.1/bin" "$(run_block "$D3")"

D4="$WORK/nvm4"; make_nvm_dir "$D4" "${VERSIONS[@]}"
check "caller's ksh_glob / no_bare_glob_qual options don't break resolution" \
    "versions/node/v22.10.1/bin|0|versions/node/v22.10.1/bin" "$(run_block "$D4" 'setopt ksh_glob no_bare_glob_qual')"

D5="$WORK/nvm5"; make_nvm_dir "$D5"
check "no versions installed: NVM_BIN unset, PATH untouched" \
    "|0|/usr/bin" "$(run_block "$D5")"

D6="$WORK/nvm6"; make_nvm_dir "$D6" "${VERSIONS[@]}"
got="$(env -i HOME="$WORK" PATH="/usr/bin:/bin" NVM_DIR="$D6" zsh -f -c "source '$BLOCK'; nvm --version; nvm ls; wc -l < \$NVM_DIR/sourced.log | tr -d ' '" 2>&1)"
check "first nvm call sources nvm.sh once and runs the real nvm" \
    "real-nvm --version
real-nvm ls
1" "$got"

D7="$WORK/nvm7"; make_nvm_dir "$D7" "${VERSIONS[@]}"
NVM_BIN_PRESET="$D7/versions/node/v9.11.2/bin"
check "valid inherited NVM_BIN is kept" \
    "versions/node/v9.11.2/bin|0|/usr/bin" "$(run_block "$D7")"
unset NVM_BIN_PRESET

D8="$WORK/nvm8"; make_nvm_dir "$D8" "${VERSIONS[@]}"
got="$(env -i HOME="$WORK" PATH="/usr/bin:/bin" NVM_DIR="$D8" zsh -f -c "nvm() { print -r -- already-loaded; }; source '$BLOCK'; nvm x" 2>&1)"
check "re-sourcing keeps an already-loaded nvm" "already-loaded" "$got"

if command -v sort >/dev/null && printf 'a\n' | sort -V >/dev/null 2>&1; then
    want="$(printf '%s\n' "${VERSIONS[@]}" | sort -V | tail -n 1)"
    check "matches sort -V" "versions/node/$want/bin" "$(run_block "$D1" | cut -d'|' -f1)"
fi

echo "passed=$PASS failed=$FAIL"
[[ $FAIL -eq 0 ]]
