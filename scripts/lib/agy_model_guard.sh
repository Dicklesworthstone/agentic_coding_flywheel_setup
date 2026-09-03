#!/usr/bin/env bash
# agy_model_guard.sh — canonical model-pin guard for the Antigravity CLI (`agy`).
#
# USER MANDATE (2026-08-24): every `agy` invocation across ACFS, the skills, and
# every spawned-agent flow MUST run on "Gemini 3.8 Flash (High)" and NOTHING else —
# never an older Flash generation (3.5/3.6), never a Medium/Low tier, never a
# Gemini Pro model, never an Anthropic/Claude model via agy, never GPT-OSS.
#
# This file is the SINGLE SOURCE OF TRUTH for the allowed-model string and the
# verification logic on the shell side. Source it; do not re-hardcode the model
# name elsewhere. The Go (ntm) and Rust (casr / franken_agent_detection) ports
# reference this same string. See docs/AGY_MIGRATION_REFERENCE.md §6
# (bead bd-47kjh.1.7).
#
# Usage:
#   source "$ACFS_ROOT/scripts/lib/agy_model_guard.sh"
#   agy_run --add-dir "$dir" --dangerously-skip-permissions --print "<prompt>"
#   #   -> runs: agy --model "Gemini 3.8 Flash (High)" <your args>
#   # For scripted/CI use that must prove the model post-hoc:
#   out="$(agy_run_checked --add-dir "$dir" --print "Reply with your model name.")" || exit 1
#
# Self-test (no agy install required): bash scripts/lib/agy_model_guard.sh --self-test

# The ONE allowed model. Defined here; referenced everywhere.
# shellcheck disable=SC2034  # exported for sourcing callers
readonly AGY_REQUIRED_MODEL="Gemini 3.8 Flash (High)"

# Forbidden-model families, as an extended-regex matched (case-insensitively)
# against any text where agy might self-report or echo a model name.
# Conservative backstop denylist of forbidden model families (case-insensitive).
# Covers any Medium/Low Flash tier, any pre-3.8 Flash generation, ANY Gemini Pro
# tier, all Anthropic/Claude families, and GPT/GPT-OSS — i.e. everything that is
# NOT the single allowed "Gemini 3.8 Flash (High)". This is a heuristic post-hoc
# check; the authoritative guarantee is the explicit `--model` flag +
# agy_verify_model.
# shellcheck disable=SC2034
readonly AGY_FORBIDDEN_MODEL_REGEX='Gemini [0-9][0-9.]* Flash \((Low|Medium)\)|Gemini [0-3]\.[0-7] Flash|Gemini [0-9][0-9.]* Pro|Claude (Sonnet|Opus|Haiku)|GPT-?OSS|gpt-[0-9]'

# Path to agy's persisted settings (holds the default "model").
agy_settings_path() {
  printf '%s\n' "${HOME}/.gemini/antigravity-cli/settings.json"
}

# agy_settings_model — echo the default model recorded in settings.json (may be
# empty if the file is missing or the key is unset). Tolerant: jq if present,
# else a grep/sed fallback so the guard works on a bare box.
agy_settings_model() {
  local settings
  settings="$(agy_settings_path)"
  [[ -r "$settings" ]] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r '.model // empty' "$settings" 2>/dev/null
  else
    grep -oE '"model"[[:space:]]*:[[:space:]]*"[^"]*"' "$settings" 2>/dev/null \
      | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/' | head -1
  fi
}

# agy_verify_model — fail-closed check that agy's persisted DEFAULT model is the
# required one. Returns 0 if OK, 1 otherwise (with a clear stderr message).
# Note: callers ALSO pass --model explicitly (the hard guarantee); this verifies
# the default has not drifted to a weaker model behind our back.
agy_verify_model() {
  local model
  model="$(agy_settings_model)"
  if [[ -z "$model" ]]; then
    printf 'agy model guard: no default model recorded at %s (agy installed/authed?). Explicit --model still enforced.\n' \
      "$(agy_settings_path)" >&2
    return 1
  fi
  if [[ "$model" != "$AGY_REQUIRED_MODEL" ]]; then
    printf 'agy model guard FAIL: settings default model is %q; require %q.\n' \
      "$model" "$AGY_REQUIRED_MODEL" >&2
    return 1
  fi
  return 0
}

# agy_assert_output_model <text> — fail-closed check that captured agy output does
# NOT reference any forbidden model family. Returns 0 if clean, 1 if a forbidden
# model is named. Use on captured --print output as a post-hoc proof.
agy_assert_output_model() {
  local text="${1:-}"
  if printf '%s' "$text" | grep -qiE "$AGY_FORBIDDEN_MODEL_REGEX"; then
    printf 'agy model guard FAIL: output references a forbidden model (require %q).\n' \
      "$AGY_REQUIRED_MODEL" >&2
    return 1
  fi
  return 0
}

# agy_run [args...] — run agy with the required model pinned. The --model flag is
# placed FIRST so it can never be swallowed as the value of a later --print
# (Go flag parsing: the prompt must be --print's value; keep callers' --print
# last in their own args). This is the enforcement; agy_verify_model is advisory.
agy_run() {
  if ! command -v agy >/dev/null 2>&1; then
    printf 'agy model guard: `agy` not found on PATH.\n' >&2
    return 127
  fi
  agy_verify_model || true   # warn-only: explicit --model below is the guarantee
  command agy --model "$AGY_REQUIRED_MODEL" "$@"
}

# agy_run_checked [args...] — like agy_run but CAPTURES output, asserts it names
# no forbidden model, then echoes the captured output. Fail-closed: returns
# nonzero if agy fails OR a forbidden model is detected. For scripts/CI/e2e.
# Captures BOTH stdout and stderr so a model banner printed to stderr cannot
# evade the assertion. The advisory agy_verify_model warning is emitted before
# the capture so it does not pollute the returned output.
agy_run_checked() {
  if ! command -v agy >/dev/null 2>&1; then
    printf 'agy model guard: `agy` not found on PATH.\n' >&2
    return 127
  fi
  agy_verify_model || true   # warn-only; emitted to stderr, not captured below
  local out rc
  out="$(command agy --model "$AGY_REQUIRED_MODEL" "$@" 2>&1)"; rc=$?
  if [[ $rc -ne 0 ]]; then
    printf '%s' "$out"
    return $rc
  fi
  if ! agy_assert_output_model "$out"; then
    # Surface what agy actually returned (to stderr) so the failure is debuggable.
    printf 'agy model guard: rejected output was:\n%s\n' "$out" >&2
    return 1
  fi
  printf '%s' "$out"
  return 0
}

# ---- self-test ---------------------------------------------------------------
_agy_guard_self_test() {
  local fails=0
  printf 'agy_model_guard self-test\n'

  if [[ "$AGY_REQUIRED_MODEL" == "Gemini 3.8 Flash (High)" ]]; then
    printf '  ok   required model constant\n'
  else
    printf '  FAIL required model constant: %q\n' "$AGY_REQUIRED_MODEL"; fails=$((fails + 1))
  fi

  # assert_output: allowed text passes
  if agy_assert_output_model "I am currently using the Gemini 3.8 Flash (High) model." 2>/dev/null; then
    printf '  ok   allowed-model output accepted\n'
  else
    printf '  FAIL allowed-model output rejected\n'; fails=$((fails + 1))
  fi

  # assert_output: each forbidden family is caught
  local bad
  for bad in \
    "Running on Gemini 3.8 Flash (Medium)." \
    "Running on Gemini 3.8 Flash (Low)." \
    "Using Gemini 3.7 Flash (High)." \
    "Running on Gemini 3.7 Flash (Medium)." \
    "Running on Gemini 3.7 Flash (Low)." \
    "Using Gemini 3.5 Flash (High)." \
    "Using Gemini 3.6 Flash (High)." \
    "I am Gemini 3.1 Pro (High)." \
    "I am Gemini 3.1 Pro (Low)." \
    "Switched to Claude Sonnet 4.6 (Thinking)." \
    "Using Claude Opus 4.6." \
    "I am Claude Haiku 4.5." \
    "switched to gpt-4o" \
    "Model: GPT-OSS 120B (Medium)."; do
    if agy_assert_output_model "$bad" 2>/dev/null; then
      printf '  FAIL forbidden output NOT caught: %s\n' "$bad"; fails=$((fails + 1))
    else
      printf '  ok   forbidden output caught: %s\n' "${bad%% *}..."
    fi
  done

  # verify_model handles a missing settings file without crashing (returns 1)
  if HOME="/nonexistent-$$-agyguard" agy_verify_model 2>/dev/null; then
    printf '  FAIL verify_model passed with no settings file\n'; fails=$((fails + 1))
  else
    printf '  ok   verify_model fail-closed on missing settings\n'
  fi

  if [[ $fails -eq 0 ]]; then
    printf 'SELF-TEST PASS\n'; return 0
  fi
  printf 'SELF-TEST FAIL (%d)\n' "$fails"; return 1
}

# Run self-test only when executed directly with --self-test (not when sourced).
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  _agy_guard_self_test
fi
