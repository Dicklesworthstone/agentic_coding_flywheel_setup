#!/usr/bin/env bash
# test_agy_install.sh — unit/contract tests for the agy (Antigravity CLI) install
# integration (bead bd-47kjh.5.4). Asserts the installer step exists + is
# checksum-gated, the manifest is drift-free, and config/docs reference agy.
#
# Run: bash tests/unit/test_agy_install.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT" || exit

PASS=0 FAIL=0
ok()   { printf '  ✓ PASS: %s\n' "$1"; PASS=$((PASS+1)); }
no()   { printf '  ✗ FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }
check(){ if eval "$2"; then ok "$1"; else no "$1"; fi; }

resolver_refuses_launcher_copy() {
  python3 - <<'PY'
import os
import pathlib
import sys
import tempfile

sys.path.insert(0, "scripts/lib")
import agy_locked

with tempfile.TemporaryDirectory() as temp_dir:
    root = pathlib.Path(temp_dir)
    bin_dir = root / "bin"
    bin_dir.mkdir()
    launcher_copy = bin_dir / "agy-real"
    launcher_copy.write_text(
        "#!/usr/bin/env python3\n"
        "LAUNCHER_MARKER = 'acfs-agy-locked-launcher-v1'\n",
        encoding="utf-8",
    )
    launcher_copy.chmod(0o755)

    os.environ["ACFS_BIN_DIR"] = str(bin_dir)
    agy_locked.HOME = root
    agy_locked.REAL_AGY = root / ".local" / "bin" / "agy-real"
    agy_locked.__file__ = str(root / "agy")

    assert not agy_locked.is_real_agy_candidate(launcher_copy)
    assert agy_locked.resolve_real_agy() == agy_locked.REAL_AGY
PY
}

dcg_adapter_contract() {
  python3 - <<'PY'
import contextlib
import io
import json
import os
import subprocess
import sys
import types

sys.path.insert(0, "scripts/lib")
import agy_locked

namespace = {"__name__": "acfs_dcg_hook_contract"}
exec(compile(agy_locked.DCG_HOOK_SOURCE, "<dcg-hook-contract>", "exec"), namespace)

real_run = namespace["subprocess"].run
real_stdin = sys.stdin
old_dcg_bin = os.environ.get("DCG_BIN")
old_marker = os.environ.get("ACFS_DCG_TEST_MARKER")
os.environ["DCG_BIN"] = "/contract/dcg"
os.environ["ACFS_DCG_TEST_MARKER"] = "preserved"


def invoke(raw, stdout="{}", returncode=0, stderr="", raises=None):
    calls = []

    def fake_run(argv, **kwargs):
        calls.append((list(argv), dict(kwargs)))
        if raises is not None:
            raise raises
        return types.SimpleNamespace(
            stdout=stdout,
            stderr=stderr,
            returncode=returncode,
        )

    namespace["subprocess"].run = fake_run
    sys.stdin = io.StringIO(raw)
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        assert namespace["main"]() == 0
    return json.loads(output.getvalue()), calls


try:
    malformed, malformed_calls = invoke("{")
    assert malformed["decision"] == "force_ask"
    assert malformed_calls == []

    missing, missing_calls = invoke(json.dumps({"toolCall": {"name": "run_command"}}))
    assert missing["decision"] == "force_ask"
    assert missing_calls == []

    envelope = json.dumps({
        "toolCall": {
            "name": "run_command",
            "args": {"CommandLine": "git status", "Cwd": "/tmp"},
        }
    })
    cases = [
        ({"decision": "deny", "reason": "denied"}, 0, "deny"),
        ({"decision": "block", "reason": "blocked"}, 1, "deny"),
        ({"decision": "ask", "reason": "review"}, 0, "force_ask"),
        ({"decision": "indeterminate"}, 0, "force_ask"),
        ({}, 1, "force_ask"),
        ({"decision": "allow"}, 1, "force_ask"),
        ({"decision": "allow"}, 0, "allow"),
        ({"decision": "warn"}, 0, "allow"),
        ({"decision": "log"}, 0, "allow"),
        ({"decision": "unknown"}, 0, "allow"),
        ({"decision": "unknown"}, 2, "allow"),
    ]
    for evaluator_result, returncode, expected in cases:
        decision, calls = invoke(
            envelope,
            stdout=json.dumps(evaluator_result),
            returncode=returncode,
        )
        assert decision["decision"] == expected, (evaluator_result, returncode, decision)
        assert len(calls) == 1
        argv, kwargs = calls[0]
        assert argv == [
            "/contract/dcg",
            "--robot",
            "--agent",
            "antigravity",
            "test",
            "--stdin",
        ]
        assert "git status" not in argv
        assert "--dialect" not in argv
        assert kwargs["input"] == "git status"
        assert kwargs["env"]["DCG_DIALECT"] == "posix"
        assert kwargs["env"]["ACFS_DCG_TEST_MARKER"] == "preserved"

    malformed_result, _ = invoke(envelope, stdout="not-json", returncode=0)
    assert malformed_result["decision"] == "allow"
    unavailable, _ = invoke(envelope, raises=OSError("missing dcg"))
    assert unavailable["decision"] == "allow"
    timed_out, _ = invoke(
        envelope,
        raises=subprocess.TimeoutExpired(cmd="dcg", timeout=4),
    )
    assert timed_out["decision"] == "allow"
finally:
    namespace["subprocess"].run = real_run
    sys.stdin = real_stdin
    if old_dcg_bin is None:
        os.environ.pop("DCG_BIN", None)
    else:
        os.environ["DCG_BIN"] = old_dcg_bin
    if old_marker is None:
        os.environ.pop("ACFS_DCG_TEST_MARKER", None)
    else:
        os.environ["ACFS_DCG_TEST_MARKER"] = old_marker
PY
}

dcg_hook_merge_is_global_and_idempotent() {
  python3 - <<'PY'
import copy
import sys

sys.path.insert(0, "scripts/lib")
import agy_locked

peer_one = {"type": "command", "command": "/opt/peer/check-one", "timeout": 7}
peer_two = {"type": "command", "command": "/opt/peer/check-two"}
seed = {
    "peer-group": {
        "enabled": False,
        "label": "preserve-me",
        "PreToolUse": [
            {
                "matcher": "run_command|view_file",
                "entryMetadata": {"owner": "peer"},
                "hooks": [
                    {"type": "command", "command": "env SAFE=1 dcg --robot"},
                    peer_one,
                ],
            },
            {
                "matcher": "*",
                "hooks": [{"type": "command", "command": "dcg hook"}],
            },
            {"matcher": "view_file", "hooks": [peer_two]},
        ],
        "PostToolUse": [{"command": "/opt/peer/post"}],
    },
    "hooks": {
        "nativeMetadata": 1,
        "PreToolUse": [
            {
                "matcher": "Bash",
                "hooks": [{"type": "command", "command": "dcg hook"}],
            }
        ],
    },
    "dcg": {
        "enabled": False,
        "customMetadata": "keep",
        "PreToolUse": [
            {
                "matcher": "run_.*",
                "hooks": [
                    {
                        "type": "command",
                        "command": "python3 /tmp/dcg-antigravity-hook.py",
                    }
                ],
            }
        ],
    },
}

current = copy.deepcopy(seed)
writes = []
agy_locked.ensure_hook_script = lambda: None
agy_locked.read_json = lambda _path, _description: copy.deepcopy(current)
agy_locked.write_json_if_changed = lambda _path, value: writes.append(copy.deepcopy(value))

agy_locked.ensure_dcg_hook()
first = writes[-1]

recognized = []
for group in first.values():
    if not isinstance(group, dict):
        continue
    for entry in group.get("PreToolUse", []):
        if not isinstance(entry, dict):
            continue
        for hook in entry.get("hooks", []):
            if agy_locked.is_dcg_hook(hook):
                recognized.append(hook)
assert len(recognized) == 1
assert recognized[0]["command"] == str(agy_locked.DCG_HOOK)

peer_group = first["peer-group"]
assert peer_group["enabled"] is False
assert peer_group["label"] == "preserve-me"
assert peer_group["PostToolUse"] == seed["peer-group"]["PostToolUse"]
assert peer_group["PreToolUse"] == [
    {
        "matcher": "run_command|view_file",
        "entryMetadata": {"owner": "peer"},
        "hooks": [peer_one],
    },
    {"matcher": "view_file", "hooks": [peer_two]},
]
assert first["hooks"] == {"nativeMetadata": 1, "PreToolUse": []}
assert first["dcg"]["enabled"] is True
assert first["dcg"]["customMetadata"] == "keep"
assert len(first["dcg"]["PreToolUse"]) == 1

current = copy.deepcopy(first)
writes.clear()
agy_locked.ensure_dcg_hook()
assert writes[-1] == first
PY
}

legacy_agy_source_contract() {
  local body=""
  local hash_line=""
  local ensure_bin_line=""
  local relocation_line=""

  body="$(sed -n '/^install_agy_locked_launchers() {$/,/^}$/p' install.sh)"
  [[ -n "$body" ]] || return 1
  ! grep -Eq 'find_asset|REPO_ROOT|ACFS_SCRIPT_DIR' <<<"$body" || return 1
  grep -Fq 'selected_source_root="$ACFS_BOOTSTRAP_DIR"' <<<"$body" || return 1
  grep -Fq 'selected_source_root="${SCRIPT_DIR:-}"' <<<"$body" || return 1
  grep -Fq 'selected_source_root" != "$trusted_source_root' <<<"$body" || return 1
  grep -Fq 'ACFS_INTERNAL_CHECKSUMS[scripts/lib/agy_locked.py]' <<<"$body" || return 1
  grep -Fq 'actual_source_sha="$(acfs_calculate_file_sha256 "$source_asset"' <<<"$body" || return 1

  hash_line="$(grep -nF 'actual_source_sha="$(acfs_calculate_file_sha256' <<<"$body" | head -n 1 | cut -d: -f1)"
  ensure_bin_line="$(grep -nF 'acfs_ensure_primary_bin_dir || return 1' <<<"$body" | head -n 1 | cut -d: -f1)"
  relocation_line="$(grep -nF 'Relocating real agy binary' <<<"$body" | head -n 1 | cut -d: -f1)"
  [[ "$hash_line" =~ ^[0-9]+$ ]] || return 1
  [[ "$ensure_bin_line" =~ ^[0-9]+$ ]] || return 1
  [[ "$relocation_line" =~ ^[0-9]+$ ]] || return 1
  (( hash_line < ensure_bin_line && ensure_bin_line < relocation_line )) || return 1

  [[ "$(grep -c 'install_agy_locked_launchers' install.sh)" -eq 2 ]] || return 1
  grep -Fq 'if ! install_agy_locked_launchers; then' install.sh || return 1
  grep -Fq 'Priming agy locked settings and dcg hook' <<<"$body" || return 1
}

echo "agy install contract tests"

# 1. KNOWN_INSTALLERS registers the antigravity installer URL (5.3).
# #390: the Antigravity CLI reads a prompt only from -p/--print, -i, or stdin,
# so `agy "<prompt>"` (the shape cc/cod accept, and the shape the onboarding
# docs taught) errored. The launcher forwards an unmistakable positional
# prompt as --print and leaves subcommands, prompt flags and `--` alone.
positional_prompt_parity_contract() {
  python3 - <<'PY'
import sys

sys.path.insert(0, "scripts/lib")
import agy_locked

cases = [
    # The onboarding block and doc examples become the supported form.
    (["Hello! Please confirm you're working."], ["--print", "Hello! Please confirm you're working."]),
    (["explain the repo structure"], ["--print", "explain the repo structure"]),
    # Flags before the prompt are scanned correctly (value, =value, boolean).
    (["--effort", "high", "review this PR"], ["--effort", "high", "--print", "review this PR"]),
    (["--effort=high", "review this PR"], ["--effort=high", "--print", "review this PR"]),
    (["-c", "what changed?"], ["-c", "--print", "what changed?"]),
    (["--agent", "reviewer", "Hello!"], ["--agent", "reviewer", "--print", "Hello!"]),
    # An explicit prompt source is never second-guessed.
    (["-p", "already a prompt"], ["-p", "already a prompt"]),
    (["--print=already", "x y"], ["--print=already", "x y"]),
    (["--prompt", "alias form"], ["--prompt", "alias form"]),
    (["-i", "interactive prompt"], ["-i", "interactive prompt"]),
    (["--prompt-interactive", "a b"], ["--prompt-interactive", "a b"]),
    (["--input-format", "stream-json", "weird positional"], ["--input-format", "stream-json", "weird positional"]),
    # Subcommands, subcommand-shaped words, `--`, stdin marker, empty argv.
    (["models"], ["models"]),
    (["mcp", "list"], ["mcp", "list"]),
    (["doctor"], ["doctor"]),
    (["--", "Hello there"], ["--", "Hello there"]),
    (["-"], ["-"]),
    ([], []),
    (["--version"], ["--version"]),
    (["--sandbox", "Fix it."], ["--sandbox", "--print", "Fix it."]),
]
for argv, want in cases:
    got = agy_locked.promote_positional_prompt(argv)
    assert got == want, f"{argv!r} -> {got!r}, want {want!r}"
    assert argv == list(argv), "input argv must not be mutated"

# main() applies the promotion AFTER model/permission flags are stripped.
src = open("scripts/lib/agy_locked.py", encoding="utf-8").read()
assert "*promote_positional_prompt(filtered_args(sys.argv[1:]))," in src, "main() does not promote a positional prompt"
# Every documented subcommand from `agy --help` 1.1.27 is protected.
for sub in ["agent", "agents", "changelog", "help", "install", "mcp", "mic-serve", "models", "plugin", "plugins", "remote-control", "update"]:
    assert sub in agy_locked.AGY_SUBCOMMANDS, sub
PY
}

# The launcher must actually hand agy-real `--print <prompt>` for the
# onboarding command, and pass a subcommand through untouched.
positional_prompt_launcher_end_to_end() {
  local sandbox
  sandbox="$(mktemp -d "${TMPDIR:-/tmp}/acfs-agy-parity.XXXXXX")" || return 1
  mkdir -p "$sandbox/.local/bin" || return 1
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@"\n' > "$sandbox/.local/bin/agy-real" || return 1
  chmod +x "$sandbox/.local/bin/agy-real" || return 1
  local out
  out="$(HOME="$sandbox" ACFS_BIN_DIR="$sandbox/.local/bin" python3 scripts/lib/agy_locked.py "Hello! Please confirm you're working." 2>/dev/null)" || return 1
  [[ "$out" == *$'--print\nHello! Please confirm you'"'"'re working.' ]] || { echo "  launcher argv: $out"; return 1; }
  out="$(HOME="$sandbox" ACFS_BIN_DIR="$sandbox/.local/bin" python3 scripts/lib/agy_locked.py models 2>/dev/null)" || return 1
  [[ "$out" != *"--print"* && "$out" == *$'\nmodels' ]] || { echo "  launcher argv: $out"; return 1; }
}

# Docs teach the form that works even without the wrapper.
docs_use_print_flag_for_agy_prompts() {
  local f
  local -a docs=(
    acfs/onboard/lessons/04_agents_login.md
    apps/web/components/lessons/agents-login-lesson.tsx
    apps/web/components/lessons/welcome-lesson.tsx
    apps/web/app/learn/commands/page.tsx
    apps/web/lib/commands.ts
  )
  for f in "${docs[@]}"; do
    [[ -f "$f" ]] || { echo "  missing $f"; return 1; }
    if grep -nE "\bagy ['\"]" "$f"; then
      echo "  $f still shows a positional agy prompt"
      return 1
    fi
    grep -qE "\bagy -p ['\"]" "$f" || { echo "  $f has no agy -p example"; return 1; }
  done
}

check "security.sh registers antigravity installer" \
  "grep -q '\[antigravity\]=\"https://antigravity.google/cli/install.sh\"' scripts/lib/security.sh"

# 2. checksums.yaml has an antigravity entry with a sha256 (checksum-monitored).
check "checksums.yaml has antigravity url" \
  "grep -A2 '^  antigravity:' checksums.yaml | grep -q 'antigravity.google/cli/install.sh'"
check "checksums.yaml antigravity has sha256" \
  "grep -A2 '^  antigravity:' checksums.yaml | grep -qE 'sha256: \"[0-9a-f]{64}\"'"

# 3. The manifest declares the agents.antigravity module (recommended, default-on).
check "manifest declares agents.antigravity" \
  "grep -q 'id: agents.antigravity' acfs.manifest.yaml"
check "agents.antigravity uses the verified_installer (antigravity) path" \
  "awk '/id: agents.antigravity/{f=1} f&&/tool: antigravity/{print;exit}' acfs.manifest.yaml | grep -q 'tool: antigravity'"

# 4. The generated installer contains a checksum-gated agy install step.
check "generated install_agents.sh has acfs_generated_install_agents_antigravity()" \
  "grep -q 'acfs_generated_install_agents_antigravity()' scripts/generated/install_agents.sh"
check "agy install step is checksum-gated (verify_checksum)" \
  "awk '/acfs_generated_install_agents_antigravity\(\)/{f=1} f&&/verify_checksum/{print;exit}' scripts/generated/install_agents.sh | grep -q verify_checksum"
check "agy generated install step installs the locked launchers" \
  "awk '/acfs_generated_install_agents_antigravity\(\)/{f=1} f&&/install -m 0755.*agy-locked/{print;exit}' scripts/generated/install_agents.sh | grep -q agy-locked && awk '/acfs_generated_install_agents_antigravity\(\)/{f=1} f&&/install -m 0755.*gmi/{print;exit}' scripts/generated/install_agents.sh | grep -q gmi"
check "agy generated install step primes locked settings" \
  "awk '/acfs_generated_install_agents_antigravity\(\)/{f=1} f&&/--acfs-prime-settings/{print;exit}' scripts/generated/install_agents.sh | grep -q -- --acfs-prime-settings"
check "agy generated install step fails closed when settings priming fails" \
  "grep -Fq 'if ! \"\$target_bin/agy-locked\" --acfs-prime-settings; then' scripts/generated/install_agents.sh && grep -Fq 'agents.antigravity: failed to prime locked settings and dcg hook' scripts/generated/install_agents.sh"
check "agy generated install step uses trusted relocation utilities" \
  "grep -Fq '/usr/bin/grep -aFq' scripts/generated/install_agents.sh && grep -Fq '/usr/bin/mv -f \"\$target_bin/agy\"' scripts/generated/install_agents.sh && grep -Fq '/usr/bin/install -m 0755' scripts/generated/install_agents.sh"
check "agy generated verification proves dcg hook registration" \
  "grep -Fq 'hook_registered = any(' scripts/generated/install_agents.sh && grep -Fq 'dcg_group.get(\"enabled\") is not True' scripts/generated/install_agents.sh"

# 5. agy is resolvable through the security layer (URL + checksum lookup).
check "get_checksum antigravity resolves to a 64-hex sha" \
  "bash -c 'source scripts/lib/security.sh >/dev/null 2>&1; export CHECKSUMS_FILE=checksums.yaml; load_checksums >/dev/null 2>&1; get_checksum antigravity' | grep -qE '^[0-9a-f]{64}$'"

# 6. Manifest drift is clean after generation (the recurring SHA256-drift hazard).
check "manifest drift is clean" \
  "bash scripts/check-manifest-drift.sh --quiet >/dev/null 2>&1"

# 7. Config/conventions reference agy (zshrc launcher + doctor check).
check "acfs.zshrc maps agy to the locked launcher" \
  "grep -q \"alias agy='\\\$HOME/.local/bin/agy-locked'\" acfs/zsh/acfs.zshrc"
check "acfs.zshrc maps gmi to the locked agy launcher" \
  "grep -q \"alias gmi='\\\$HOME/.local/bin/agy-locked'\" acfs/zsh/acfs.zshrc"
check "uca delegates all agent updates to the authoritative verified updater" \
  "grep -Fxq \"alias uca='acfs update --agents-only --force'\" acfs/zsh/acfs.zshrc"
check "uca contains no direct network-to-shell installer" \
  "! grep '^alias uca=' acfs/zsh/acfs.zshrc | grep -Eq 'curl|wget|\\|[[:space:]]*(bash|sh)([[:space:]]|$)'"
check "agy locked launcher pins the required model" \
  "grep -q 'MODEL = \"Gemini 3.8 Flash (High)\"' scripts/lib/agy_locked.py"
check "agy locked launcher strips -m and -model flags" \
  "python3 -c 'import sys; sys.path.insert(0, \"scripts/lib\"); import agy_locked; res = agy_locked.filtered_args([\"-m\", \"foo\", \"-m=bar\", \"--model=baz\", \"--model\", \"qux\", \"prompt\"]); assert res == [\"prompt\"], f\"got {res}\"'"
check "agy locked launcher points to agy-real" \
  "grep -q 'REAL_AGY = HOME / \".local\" / \"bin\" / \"agy-real\"' scripts/lib/agy_locked.py"
check "agy locked launcher refuses wrapper copies as the real binary" \
  "resolver_refuses_launcher_copy"
check "agy locked launcher never falls back to another agy wrapper" \
  "! sed -n '/^def resolve_real_agy():$/,/^    return REAL_AGY$/p' scripts/lib/agy_locked.py | grep -F ' / \"agy\"'"
# The lanes resolve grep to a trusted system binary ("$grep_bin", /usr/bin/grep), so match the
# marker probe itself rather than one spelling of the grep invocation.
check "all agy relocation lanes identify wrappers before replacing agy-real" \
  "grep -Fq -- \"-aFq 'Launch Antigravity CLI with ACFS pinned defaults'\" install.sh && grep -Fq -- \"-aFq 'Launch Antigravity CLI with ACFS pinned defaults'\" scripts/lib/update.sh && grep -Fq -- \"-aFq 'Launch Antigravity CLI with ACFS pinned defaults'\" acfs.manifest.yaml"
check "agy locked launcher pins always-proceed tool permission" \
  "grep -q '\"toolPermission\": \"always-proceed\"' scripts/lib/agy_locked.py"
check "agy locked launcher installs dcg hook support" \
  "grep -q 'dcg-antigravity-hook.py' scripts/lib/agy_locked.py"
check "agy dcg adapter obeys documented decisions and stdin-only invocation" \
  "dcg_adapter_contract"
check "agy dcg hook reconciliation is global and idempotent" \
  "dcg_hook_merge_is_global_and_idempotent"
check "legacy agy launcher binds and hashes the selected trusted source before mutation" \
  "legacy_agy_source_contract"
check "agy locked launcher supports installer priming" \
  "grep -q -- '--acfs-prime-settings' scripts/lib/agy_locked.py"
check "agy locked launcher only treats priming as an exact invocation" \
  "grep -Fq 'sys.argv[1:] == [PRIME_SETTINGS_FLAG]' scripts/lib/agy_locked.py"
check "agy locked launcher is valid Python" \
  "python3 -m py_compile scripts/lib/agy_locked.py"
check "agy locked launcher forwards a bare positional prompt as --print (#390)" \
  "positional_prompt_parity_contract"
check "agy locked launcher hands agy-real --print for the onboarding command and passes subcommands through" \
  "positional_prompt_launcher_end_to_end"
check "onboarding and web docs teach agy -p, the form that works without the wrapper" \
  "docs_use_print_flag_for_agy_prompts"
check "agents-only update does not fail on missing Bun when Codex is absent" \
  "grep -q 'not installed; Bun not installed either' scripts/lib/update.sh"
check "doctor checks for the agy alias" \
  "grep -q 'agent.alias.agy' scripts/lib/doctor.sh"

# 8. The shared e2e harness exists and self-tests clean (bd-47kjh.12).
check "agy e2e harness self-test passes" \
  "bash scripts/lib/agy_e2e_harness.sh --self-test >/dev/null 2>&1"

echo ""
echo "agy install contract: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
