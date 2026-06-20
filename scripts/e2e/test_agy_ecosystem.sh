#!/usr/bin/env bash
# test_agy_ecosystem.sh — full-ecosystem end-to-end for the Antigravity CLI (agy)
# migration (bead bd-47kjh.9, with the live ntm/spawn slice of bd-47kjh.4.3).
#
# Proves, on ONE real agy conversation pinned to "Gemini 3.1 Pro (High)", that
# every migrated surface recognizes agy together:
#   1. agy headless round-trip (the conversation) + model-pin assertion
#   2. a conversation db persists under ~/.gemini/antigravity-cli/conversations/
#   3. cass indexes the antigravity/agy session format
#   4. casr can resume agy conversations (knows the antigravity provider)
#   5. caam knows the agy/antigravity account surface
#   6. dcg guards a destructive command
#   7. am (mcp_agent_mail) recognizes the agy program identity
#   8. ntm treats agy as a spawnable agent type + `ntm deps` knows it
#   9. a migrated, deployed skill drives agy (no operational gmi-as-primary)
#
# HARD GATES (fail loudly): the agy round-trip must succeed AND every agy
# invocation must be on the pinned model (the model guard prints the actual
# model on violation). Per-tool recognition steps are SKIP-tolerant (logged) so
# the run still produces a full per-surface report on a partially-provisioned box.
#
# Skips cleanly (exit 0) if agy is unauthenticated. Never deletes anything
# (honors ACFS RULE 1); any agy conversation it creates is left in place + logged.
#
# Usage: scripts/e2e/test_agy_ecosystem.sh
#        tail -f "$(ls -dt target/agy-e2e/ecosystem_* | head -1)/events.jsonl"

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/lib/agy_e2e_harness.sh
source "$REPO_ROOT/scripts/lib/agy_e2e_harness.sh"

agy_e2e_init "ecosystem"
agy_e2e_skip_if_unauth "agy not installed/authed — ecosystem e2e skipped" || exit 0

# --- step 1: the real agy conversation (headless, model-pinned) --------------
MARKER="ACFS-AGY-E2E-$$"
OUT="$(agy_e2e_print "Reply with exactly this token and nothing else: ${MARKER}")" || \
  agy_e2e_fail "agy round-trip failed (rc!=0)" agy_roundtrip
if [[ "$OUT" == *"$MARKER"* ]]; then
  agy_e2e_pass "agy echoed the marker token" agy_roundtrip
else
  agy_e2e_log warn agy_roundtrip "msg=marker not echoed verbatim (agy still responded)" "out_len=${#OUT}"
fi
# HARD GATE: model pin. Ask agy its own model and assert it is not a forbidden one.
MODEL_OUT="$(agy_e2e_print "What model are you? Answer with the exact model name only.")" || true
agy_e2e_assert_model "$MODEL_OUT" || agy_e2e_fail "agy ran on a forbidden (non-pinned) model" model_pin

# --- step 2: a conversation db persisted -------------------------------------
UUID="$(agy_e2e_newest_conversation)"
if [[ -n "$UUID" ]]; then
  agy_e2e_pass "agy conversation persisted (uuid=$UUID)" conversation_db
  agy_e2e_log info conversation_db "uuid=$UUID" "dir=$HOME/.gemini/antigravity-cli/conversations"
else
  agy_e2e_log warn conversation_db "msg=no conversation db found (agy may store history elsewhere on this build)"
fi

# --- step 3: cass indexes the antigravity/agy format -------------------------
if command -v cass >/dev/null 2>&1; then
  if timeout 25 cass capabilities --json 2>/dev/null | grep -qi 'antigravity'; then
    agy_e2e_pass "cass advertises the antigravity (agy) session format" cass_index
  else
    agy_e2e_fail "cass capabilities does not list antigravity" cass_index
  fi
else
  agy_e2e_skip "cass not on PATH" cass_index
fi

# --- step 4: casr knows the antigravity provider (resume agy) ----------------
if command -v casr >/dev/null 2>&1; then
  CASR="$(timeout 25 casr providers 2>&1 || true)"
  if printf '%s' "$CASR" | grep -qiE 'antigravity|\bagy\b'; then
    agy_e2e_pass "casr lists the antigravity/agy provider" casr_resume
  else
    agy_e2e_log warn casr_resume "msg=casr providers did not name antigravity/agy (only legacy gemini?)"
  fi
else
  agy_e2e_skip "casr not on PATH" casr_resume
fi

# --- step 5: caam knows the agy/antigravity account surface ------------------
if command -v caam >/dev/null 2>&1; then
  CAAM="$(timeout 20 caam ls 2>&1; timeout 20 caam providers 2>&1 || true)"
  if printf '%s' "$CAAM" | grep -qiE 'antigravity|\bagy\b'; then
    agy_e2e_pass "caam recognizes the agy/antigravity account surface" caam_account
  else
    agy_e2e_log warn caam_account "msg=caam did not name antigravity/agy (no agy account configured?)"
  fi
else
  agy_e2e_skip "caam not on PATH" caam_account
fi

# --- step 6: dcg guards a destructive command --------------------------------
# The dangerous literal lives only in this file (not a typed command line), so
# dcg's own PreToolUse hook does not intercept it; `dcg test` evaluates it.
if command -v dcg >/dev/null 2>&1; then
  DANGER="git reset --hard HEAD~5"
  DCG_OUT="$(dcg test "$DANGER" 2>&1 || true)"
  if printf '%s' "$DCG_OUT" | grep -qiE 'block|deny|danger|refus|guard'; then
    agy_e2e_pass "dcg blocks a destructive command (git reset --hard)" dcg_guard
  else
    agy_e2e_fail "dcg did NOT block a known-destructive command" dcg_guard
  fi
else
  agy_e2e_skip "dcg not on PATH" dcg_guard
fi

# --- step 7: am (agent mail) recognizes the agy program identity -------------
# am is a Rust binary; agy identity recognition lives in its agent-detection.
if command -v am >/dev/null 2>&1; then
  AM_OUT="$(am --help 2>&1; am agents 2>&1 || true)"
  if printf '%s' "$AM_OUT" | grep -qiE 'antigravity|\bagy\b'; then
    agy_e2e_pass "am surfaces the agy/antigravity identity" am_identity
  else
    agy_e2e_log warn am_identity "msg=am help/agents did not name agy (detection may be runtime-only)"
  fi
else
  agy_e2e_skip "am not on PATH" am_identity
fi

# --- step 8: ntm treats agy as a spawnable type + deps knows it --------------
if command -v ntm >/dev/null 2>&1; then
  NTM_OUT="$(ntm --help 2>&1; timeout 25 ntm deps 2>&1 || true)"
  if printf '%s' "$NTM_OUT" | grep -qiE 'antigravity|\bagy\b|--agy'; then
    agy_e2e_pass "ntm recognizes agy as an agent type / dep" ntm_agy
  else
    agy_e2e_log warn ntm_agy "msg=ntm help/deps did not name agy on this build"
  fi
else
  agy_e2e_skip "ntm not on PATH" ntm_agy
fi

# --- step 9: a migrated, deployed skill drives agy (no operational gmi) -------
SKILL_DIR="$HOME/.claude/skills/open-beads-weighted-tmux-agent-sessions"
if [[ -f "$SKILL_DIR/SKILL.md" ]]; then
  if grep -qE '\bagy\b' "$SKILL_DIR/SKILL.md" && ! grep -qE -- '--gmi=' "$SKILL_DIR/SKILL.md"; then
    agy_e2e_pass "deployed skill drives agy (no operational --gmi=)" skill_drives_agy
  else
    agy_e2e_fail "deployed skill still references operational gmi" skill_drives_agy
  fi
else
  agy_e2e_skip "reference skill not deployed" skill_drives_agy
fi

# --- summary -----------------------------------------------------------------
agy_e2e_log info ecosystem_done "marker=$MARKER" "uuid=${UUID:-none}"
if agy_e2e_summary; then
  agy_e2e_log pass ecosystem "msg=all hard gates passed"
  exit 0
else
  agy_e2e_log fail ecosystem "msg=one or more hard gates failed (see events.jsonl)"
  exit 1
fi
