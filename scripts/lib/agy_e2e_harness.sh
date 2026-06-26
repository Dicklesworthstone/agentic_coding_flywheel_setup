#!/usr/bin/env bash
# agy_e2e_harness.sh — shared end-to-end test harness + structured-logging
# conventions for the Antigravity CLI (`agy`) migration (bead bd-47kjh.12).
#
# Every component's agy e2e (ACFS install, ntm spawn, casr resume, am identity,
# dcg guard, caam account) should SOURCE this file so they share:
#   - structured JSON-line logging (one event per line) + a per-run artifact dir
#   - skip-cleanly-if-agy-unauthenticated (e2e must never hard-fail in CI/headless)
#   - a model-guard assertion (reuses agy_model_guard.sh — "Gemini 3.1 Pro (High)")
#   - a headless agy round-trip helper (the only non-interactive way to drive agy)
#
# Design notes:
#   - This harness NEVER deletes files (honors ACFS RULE 1). Any agy conversation
#     it creates during a round-trip is LOGGED (uuid) and left in place; it is
#     harmless ephemeral history.
#   - It NEVER prints raw credentials. Auth is probed by file presence + an
#     optional live `--print`; only booleans/lengths/hashes are logged.
#
# Usage:
#   source "$ACFS_ROOT/scripts/lib/agy_e2e_harness.sh"
#   agy_e2e_init "casr-resume"
#   agy_e2e_skip_if_unauth || exit 0           # exits 0 (skip) when agy not usable
#   out="$(agy_e2e_print 'Reply with exactly: OK')" || agy_e2e_fail "round-trip failed"
#   agy_e2e_assert_model "$out" || agy_e2e_fail "forbidden model"
#   agy_e2e_pass "round-trip ok"
#
# Self-test (no agy required): bash scripts/lib/agy_e2e_harness.sh --self-test

# ---- locate the model guard (single source of truth for the model string) ----
_AGY_E2E_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
if [[ -r "$_AGY_E2E_LIB_DIR/agy_model_guard.sh" ]]; then
  source "$_AGY_E2E_LIB_DIR/agy_model_guard.sh"
fi

AGY_E2E_NAME="${AGY_E2E_NAME:-agy-e2e}"
AGY_E2E_ARTIFACT_DIR="${AGY_E2E_ARTIFACT_DIR:-}"
AGY_E2E_LOG="${AGY_E2E_LOG:-}"
AGY_E2E_FAILURES=0

# agy_e2e_init <name> [artifact_root] — set up the per-run artifact dir + JSONL log.
agy_e2e_init() {
  AGY_E2E_NAME="${1:-agy-e2e}"
  local root="${2:-${REPO_ROOT:-$PWD}/target/agy-e2e}"
  local ts; ts="$(date +%Y%m%d_%H%M%S 2>/dev/null || echo run)"
  AGY_E2E_ARTIFACT_DIR="$root/${AGY_E2E_NAME}_${ts}_$$"
  mkdir -p "$AGY_E2E_ARTIFACT_DIR"
  AGY_E2E_LOG="$AGY_E2E_ARTIFACT_DIR/events.jsonl"
  : > "$AGY_E2E_LOG"
  agy_e2e_log info harness_init "name=$AGY_E2E_NAME" "artifacts=$AGY_E2E_ARTIFACT_DIR"
}

# _agy_e2e_json_escape <string> — minimal JSON string escaper (quotes/backslash/newline/tab).
_agy_e2e_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# agy_e2e_log <level> <event> [key=value ...] — emit one structured JSON line to
# stdout (so a Monitor/CI can stream it) and append to the artifact log.
agy_e2e_log() {
  local level="${1:-info}" event="${2:-event}"; shift 2 || true
  local ts; ts="$(date -Iseconds 2>/dev/null || echo '-')"
  local line; line="{\"ts\":\"$ts\",\"level\":\"$(_agy_e2e_json_escape "$level")\",\"event\":\"$(_agy_e2e_json_escape "$event")\""
  local kv k v
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
    line+=",\"$(_agy_e2e_json_escape "$k")\":\"$(_agy_e2e_json_escape "$v")\""
  done
  line+="}"
  # Logs go to stderr (+ the jsonl artifact), keeping stdout clean for the
  # value-returning helpers (agy_e2e_print / _newest_conversation). Stream a run
  # with `tail -f "$AGY_E2E_LOG"` or by watching stderr.
  printf '%s\n' "$line" >&2
  [[ -n "$AGY_E2E_LOG" ]] && printf '%s\n' "$line" >> "$AGY_E2E_LOG"
  return 0
}

agy_e2e_pass() { agy_e2e_log pass "${2:-assertion}" "msg=${1:-ok}"; }
agy_e2e_fail() { AGY_E2E_FAILURES=$((AGY_E2E_FAILURES + 1)); agy_e2e_log fail "${2:-assertion}" "msg=${1:-failed}"; return 1; }
agy_e2e_skip() { agy_e2e_log skip "${2:-skipped}" "msg=${1:-skipped}"; }

# agy_e2e_have_agy — 0 if the agy binary is on PATH.
agy_e2e_have_agy() { command -v agy >/dev/null 2>&1; }

# agy_e2e_is_authed — 0 if agy looks authenticated (token file present).
agy_e2e_is_authed() { [[ -s "${HOME}/.gemini/antigravity-cli/antigravity-oauth-token" ]]; }

# agy_e2e_skip_if_unauth [reason] — log+return 1 (caller should `|| exit 0`) when
# agy is missing or unauthenticated, so e2e degrades to a clean SKIP, never a fail.
agy_e2e_skip_if_unauth() {
  if ! agy_e2e_have_agy; then agy_e2e_skip "${1:-agy not on PATH}" agy_unavailable; return 1; fi
  if ! agy_e2e_is_authed; then agy_e2e_skip "${1:-agy not authenticated}" agy_unauth; return 1; fi
  agy_e2e_log info agy_ready "version=$(agy --version 2>/dev/null | head -1)"
  return 0
}

# agy_e2e_required_model — echo the one allowed model string.
agy_e2e_required_model() { printf '%s' "${AGY_REQUIRED_MODEL:-Gemini 3.1 Pro (High)}"; }

# agy_e2e_assert_model <captured-output> — fail-closed: reject output that names a
# forbidden model family. Delegates to agy_model_guard's agy_assert_output_model.
agy_e2e_assert_model() {
  local text="${1:-}"
  if declare -F agy_assert_output_model >/dev/null 2>&1; then
    if agy_assert_output_model "$text" 2>/dev/null; then
      agy_e2e_log pass model_guard "model=$(agy_e2e_required_model)"; return 0
    fi
    agy_e2e_fail "output named a forbidden model (require $(agy_e2e_required_model))" model_guard; return 1
  fi
  agy_e2e_log warn model_guard "msg=agy_model_guard.sh not sourced; skipped model assertion"; return 0
}

# agy_e2e_print <prompt> [extra agy args...] — headless model-pinned round-trip.
# Echoes agy's stdout; captures stdout+stderr to the artifact dir. Returns agy's rc.
agy_e2e_print() {
  local prompt="${1:?prompt required}"; shift || true
  local out rc model; model="$(agy_e2e_required_model)"
  agy_e2e_log info agy_print "model=$model" "prompt=$prompt"
  out="$(agy --model "$model" --print "$prompt" "$@" 2>"${AGY_E2E_ARTIFACT_DIR:-/tmp}/agy_print.stderr")"; rc=$?
  [[ -n "$AGY_E2E_ARTIFACT_DIR" ]] && printf '%s' "$out" > "$AGY_E2E_ARTIFACT_DIR/agy_print.stdout"
  agy_e2e_log info agy_print_done "rc=$rc" "out_len=${#out}"
  printf '%s' "$out"
  return $rc
}

# agy_e2e_newest_conversation — echo the uuid (filename stem) of the newest agy
# conversation db, or empty. Useful to assert a round-trip persisted history.
agy_e2e_newest_conversation() {
  local dir="${HOME}/.gemini/antigravity-cli/conversations"
  [[ -d "$dir" ]] || return 0
  local newest=""
  local candidate=""
  while IFS= read -r -d '' candidate; do
    if [[ -z "$newest" || "$candidate" -nt "$newest" ]]; then
      newest="$candidate"
    fi
  done < <(find "$dir" -maxdepth 1 -type f -name '*.db' -print0 2>/dev/null)
  [[ -n "$newest" ]] && basename "$newest" .db
}

# agy_e2e_summary — log a final summary line; return nonzero if any failures.
agy_e2e_summary() {
  agy_e2e_log info harness_summary "failures=$AGY_E2E_FAILURES" "artifacts=${AGY_E2E_ARTIFACT_DIR:-none}"
  [[ "$AGY_E2E_FAILURES" -eq 0 ]]
}

# ---- self-test (no agy install required) -------------------------------------
_agy_e2e_self_test() {
  local fails=0
  AGY_E2E_LOG=""  # stdout-only for the self-test
  printf 'agy_e2e_harness self-test\n'
  [[ "$(agy_e2e_required_model)" == "Gemini 3.1 Pro (High)" ]] \
    && echo "  ok   required model" || { echo "  FAIL required model"; fails=$((fails+1)); }
  # json log line is valid-ish (has ts/level/event + the custom key)
  local line; line="$(agy_e2e_log info unit_test foo=bar 2>&1 | tail -1)"
  printf '%s' "$line" | grep -q '"event":"unit_test"' && printf '%s' "$line" | grep -q '"foo":"bar"' \
    && echo "  ok   json log line" || { echo "  FAIL json log line: $line"; fails=$((fails+1)); }
  # escaper handles quotes
  [[ "$(_agy_e2e_json_escape 'a"b\c')" == 'a\"b\\c' ]] \
    && echo "  ok   json escape" || { echo "  FAIL json escape"; fails=$((fails+1)); }
  # model assertion catches a forbidden model when the guard is present
  if declare -F agy_assert_output_model >/dev/null 2>&1; then
    AGY_E2E_FAILURES=0
    agy_e2e_assert_model "I am Gemini 3.5 Flash." >/dev/null 2>&1
    [[ "$AGY_E2E_FAILURES" -eq 1 ]] && echo "  ok   model guard catches forbidden" \
      || { echo "  FAIL model guard"; fails=$((fails+1)); }
    AGY_E2E_FAILURES=0
  else
    echo "  warn agy_model_guard.sh not found next to harness"
  fi
  if [[ $fails -eq 0 ]]; then printf 'SELF-TEST PASS\n'; return 0; fi
  printf 'SELF-TEST FAIL (%d)\n' "$fails"; return 1
}

if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  _agy_e2e_self_test
fi
