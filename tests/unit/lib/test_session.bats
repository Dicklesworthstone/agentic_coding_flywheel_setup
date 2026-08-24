#!/usr/bin/env bats

load '../test_helper'

setup() {
    common_setup
    source_lib "logging"
    source_lib "session"
    
    if ! command -v jq &>/dev/null; then
        skip "jq not installed"
    fi
}

teardown() {
    common_teardown
}

@test "validate_session_export: validates valid json" {
    local valid_json='{
        "schema_version": 1,
        "session_id": "123",
        "agent": "claude-code",
        "stats": { "turns": 5 }
    }'
    local file=$(create_temp_file "$valid_json")
    
    run validate_session_export "$file"
    assert_success
}

@test "validate_session_export: rejects invalid json" {
    local invalid_json='{ "schema_version": 1 }' # missing session_id/agent
    local file=$(create_temp_file "$invalid_json")
    
    run validate_session_export "$file"
    assert_failure
}

@test "validate_session_export: rejects blank required strings" {
    local invalid_json='{
        "schema_version": 1,
        "session_id": "   ",
        "agent": "   ",
        "stats": { "turns": 5 }
    }'
    local file
    file=$(create_temp_file "$invalid_json")

    run validate_session_export "$file"
    assert_failure
    assert_output --partial "missing required fields"
}

@test "session IDs use one bounded filename-safe grammar" {
    run acfs_session_validate_id "session_ABC-123"
    assert_success

    local invalid_id
    for invalid_id in "../escape" "nested/session" "." "-leading" "contains space" $'line\nbreak'; do
        run acfs_session_validate_id "$invalid_id"
        assert_failure
        assert_output --partial "must be 1-128 characters"
    done

    local too_long
    printf -v too_long '%0129d' 0
    run acfs_session_validate_id "$too_long"
    assert_failure
    assert_output --partial "must be 1-128 characters"
}

@test "validate_session_export: rejects path-like session IDs" {
    local invalid_json='{
        "schema_version": 1,
        "session_id": "../../outside",
        "agent": "claude-code",
        "stats": { "turns": 1 }
    }'
    local file
    file=$(create_temp_file "$invalid_json")

    run validate_session_export "$file"
    assert_failure
    assert_output --partial "Session export ID must be"
}

@test "list_sessions: rejects non-numeric day and limit values before calling cass" {
    run list_sessions --days nope
    assert_failure
    assert_output --partial "positive integer"

    run list_sessions --limit zero
    assert_failure
    assert_output --partial "positive integer"
}

@test "session library: sources under set -u without HOME" {
    run env -i PATH="/usr/bin:/bin" bash -c 'set -euo pipefail; source "$1"; printf "<%s>\n" "${ACFS_SESSIONS_DIR:-}"' _ "$PROJECT_ROOT/scripts/lib/session.sh"
    assert_success
    assert_output "<>"
}

@test "session library: uses TARGET_HOME fallback when HOME is absent" {
    local target_home
    target_home="$(create_temp_dir)"

    run env -i PATH="/usr/bin:/bin" TARGET_HOME="$target_home" bash -c 'set -euo pipefail; source "$1"; printf "%s\n" "$ACFS_SESSIONS_DIR"' _ "$PROJECT_ROOT/scripts/lib/session.sh"
    assert_success
    assert_output "$target_home/.acfs/sessions"
}

@test "session library: TARGET_HOME beats caller HOME for default storage" {
    local caller_home target_home
    caller_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"

    run env -i PATH="/usr/bin:/bin" HOME="$caller_home" TARGET_HOME="$target_home" bash -c 'set -euo pipefail; source "$1"; printf "%s\n" "$ACFS_SESSIONS_DIR"' _ "$PROJECT_ROOT/scripts/lib/session.sh"
    assert_success
    assert_output "$target_home/.acfs/sessions"
}

@test "native session helpers fail clearly without any home context" {
    run env -i PATH="/usr/bin:/bin" bash -c 'set -euo pipefail; source "$1"; session_project_dir_key_gemini "/tmp/acfs-project"' _ "$PROJECT_ROOT/scripts/lib/session.sh"
    assert_failure
    assert_output --partial "Unable to resolve GEMINI_HOME"
    refute_output --partial "unbound variable"
}

@test "native session helpers use TARGET_HOME when caller HOME is absent" {
    local target_home
    target_home="$(create_temp_dir)"

    run env -i PATH="/usr/bin:/bin" TARGET_HOME="$target_home" bash -c 'set -euo pipefail; source "$1"; acfs_session_provider_home_dir CLAUDE_HOME ".claude"; acfs_session_provider_home_dir CODEX_HOME ".codex"; acfs_session_provider_home_dir GEMINI_HOME ".gemini"' _ "$PROJECT_ROOT/scripts/lib/session.sh"
    assert_success
    assert_output "$target_home/.claude
$target_home/.codex
$target_home/.gemini"
}

@test "export_session: streams output" {
    local file=$(create_temp_file "dummy session")
    local output_file=$(create_temp_file)
    
    # Mock cass export to output valid JSON
    init_stub_dir
    cat > "$STUB_DIR/cass" <<EOF
#!/bin/bash
if [[ "\$1" == "export" ]]; then
    echo '{"schema_version": 1, "session_id": "1", "agent": "claude-code", "stats": {"turns":1}, "content": "streaming test"}'
    exit 0
fi
echo "Unknown command: \$@" >&2
exit 1
EOF
    chmod +x "$STUB_DIR/cass"
    
    run export_session "$file" --output "$output_file"
    assert_success
    
    run cat "$output_file"
    assert_output --partial "streaming test"
}

@test "export_session: fails clearly when output path cannot be written" {
    local file
    file=$(create_temp_file "dummy session")
    local missing_parent
    missing_parent="$(create_temp_dir)/missing"
    local output_file="${missing_parent}/export.json"

    init_stub_dir
    cat > "$STUB_DIR/cass" <<EOF
#!/bin/bash
if [[ "\$1" == "export" ]]; then
    echo '{"schema_version": 1, "session_id": "1", "agent": "claude-code", "stats": {"turns":1}, "content": "streaming test"}'
    exit 0
fi
echo "Unknown command: \$@" >&2
exit 1
EOF
    chmod +x "$STUB_DIR/cass"

    run export_session "$file" --output "$output_file"
    assert_failure
    assert_output --partial "Failed to write exported session"
}

@test "export_session: cleanup does not leak into the caller scope" {
    local file
    file=$(create_temp_file "dummy session")
    local sentinel
    sentinel=$(create_temp_file "caller sentinel")

    init_stub_dir
    cat > "$STUB_DIR/cass" <<EOF
#!/bin/bash
if [[ "\$1" == "export" ]]; then
    echo '{"schema_version": 1, "session_id": "1", "agent": "claude-code", "stats": {"turns":1}, "content": "streaming test"}'
    exit 0
fi
echo "Unknown command: \$@" >&2
exit 1
EOF
    chmod +x "$STUB_DIR/cass"

    caller_wrapper() {
        local tmp_export="$sentinel"
        export_session "$file" >/dev/null
    }

    run caller_wrapper
    assert_success
    [[ -f "$sentinel" ]]
}

@test "export_session: preserves caller RETURN trap through sanitization" {
    local file
    file=$(create_temp_file "dummy session")

    init_stub_dir
    cat > "$STUB_DIR/cass" <<EOF
#!/bin/bash
if [[ "\$1" == "export" ]]; then
    echo '{"schema_version": 1, "session_id": "1", "agent": "claude-code", "stats": {"turns":1}, "content": "streaming test"}'
    exit 0
fi
echo "Unknown command: \$@" >&2
exit 1
EOF
    chmod +x "$STUB_DIR/cass"

    caller_wrapper() {
        trap 'printf "%s\n" export-caller-return-fired' RETURN
        export_session "$file" >/dev/null || return 1
        trap -p RETURN
    }

    run caller_wrapper
    assert_success
    assert_output --partial "export-caller-return-fired"
}

@test "export_session: refuses markdown output when sanitized replacement fails" {
    local file
    file=$(create_temp_file "dummy session")

    init_stub_dir
    cat > "$STUB_DIR/cass" <<EOF
#!/bin/bash
if [[ "\$1" == "export" ]]; then
    echo 'markdown password=secret123'
    exit 0
fi
echo "Unknown command: \$@" >&2
exit 1
EOF
    cat > "$STUB_DIR/mv" <<'EOF'
#!/bin/bash
if [[ "${ACFS_FAIL_SANITIZED_MV:-}" == "1" ]]; then
    for arg in "$@"; do
        if [[ "$arg" == *.sanitized ]]; then
            exit 1
        fi
    done
fi
if [[ -x /usr/bin/mv ]]; then
    exec /usr/bin/mv "$@"
fi
exec /bin/mv "$@"
EOF
    chmod +x "$STUB_DIR/cass" "$STUB_DIR/mv"

    export ACFS_FAIL_SANITIZED_MV=1
    run export_session "$file" --format markdown
    assert_failure
    assert_output --partial "Sanitization failed; refusing to output unsanitized export"
    refute_output --partial "password=secret123"
}

@test "sanitize_content: redacts complete and truncated private-key blocks" {
    local content=$'before\n-----BEGIN OPENSSH PRIVATE KEY-----\nprivate-payload-one\n-----END OPENSSH PRIVATE KEY-----\nmiddle\n-----BEGIN EC PRIVATE KEY-----\nprivate-payload-two'

    run sanitize_content "$content"
    assert_success
    assert_output --partial "before"
    assert_output --partial "middle"
    assert_output --partial "[PRIVATE_KEY_REDACTED]"
    refute_output --partial "BEGIN OPENSSH PRIVATE KEY"
    refute_output --partial "private-payload-one"
    refute_output --partial "BEGIN EC PRIVATE KEY"
    refute_output --partial "private-payload-two"
}

@test "sanitize_session_export: redacts nested PEM private keys" {
    local json='{
        "schema_version": 1,
        "session_id": "pem-session",
        "agent": "claude-code",
        "stats": { "turns": 1 },
        "sanitized_transcript": [{
            "content": "before\n-----BEGIN RSA PRIVATE KEY-----\nprivate-json-payload\n-----END RSA PRIVATE KEY-----\nafter"
        }]
    }'
    local file
    file=$(create_temp_file "$json")

    run sanitize_session_export "$file"
    assert_success

    run cat "$file"
    assert_success
    assert_output --partial "[PRIVATE_KEY_REDACTED]"
    assert_output --partial "after"
    refute_output --partial "BEGIN RSA PRIVATE KEY"
    refute_output --partial "private-json-payload"
}

@test "export_session: private-key postcondition cannot be bypassed for JSON" {
    local file
    file=$(create_temp_file "dummy session")

    init_stub_dir
    cat > "$STUB_DIR/cass" <<'EOF'
#!/bin/bash
if [[ "$1" == "export" ]]; then
    printf '%s\n' '{"schema_version":1,"session_id":"pem-session","agent":"claude-code","content":"-----BEGIN PRIVATE KEY-----\nprivate-export-payload\n-----END PRIVATE KEY-----"}'
    exit 0
fi
exit 1
EOF
    chmod +x "$STUB_DIR/cass"

    run export_session "$file" --format json --no-sanitize
    assert_failure
    assert_output --partial "Private-key material remains"
    refute_output --partial "private-export-payload"
}

@test "export_session: private-key postcondition cannot be bypassed for Markdown" {
    local file
    file=$(create_temp_file "dummy session")

    init_stub_dir
    cat > "$STUB_DIR/cass" <<'EOF'
#!/bin/bash
if [[ "$1" == "export" ]]; then
    printf '%s\n' 'before' '-----BEGIN PGP PRIVATE KEY BLOCK-----' 'private-markdown-payload' '-----END PGP PRIVATE KEY BLOCK-----'
    exit 0
fi
exit 1
EOF
    chmod +x "$STUB_DIR/cass"

    run export_session "$file" --format markdown --no-sanitize
    assert_failure
    assert_output --partial "Private-key material remains"
    refute_output --partial "private-markdown-payload"
}

@test "sanitize_session_export: preserves structure and redacts secrets" {
    local json='{
        "schema_version": 1,
        "session_id": "123",
        "agent": "claude-code",
        "stats": { "turns": 1 },
        "sanitized_transcript": [
            { "content": "my secret is password=secret123" }
        ]
    }'
    local file=$(create_temp_file "$json")
    
    run sanitize_session_export "$file"
    assert_success
    
    run cat "$file"
    assert_output --partial "[SECRET_REDACTED]"
    assert_output --partial '"session_id": "123"'
}

@test "sanitize_session_export: ignores PATH-poisoned jq" {
    local system_jq=""
    local candidate
    for candidate in /usr/bin/jq /bin/jq /usr/local/bin/jq /usr/local/sbin/jq /usr/sbin/jq /sbin/jq; do
        if [[ -x "$candidate" ]]; then
            system_jq="$candidate"
            break
        fi
    done
    [[ -n "$system_jq" ]] || skip "system jq required for PATH trust test"

    local fake_bin
    local marker
    local file
    fake_bin="$(create_temp_dir)"
    marker="$BATS_TEST_TMPDIR/session-fake-jq-used"
    cat > "$fake_bin/jq" <<EOF
#!/usr/bin/env bash
: > "$marker"
last="\${@: -1}"
if [[ -f "\$last" ]]; then
    cat -- "\$last"
fi
exit 0
EOF
    chmod +x "$fake_bin/jq"

    file=$(create_temp_file '{
        "schema_version": 1,
        "session_id": "123",
        "agent": "claude-code",
        "stats": { "turns": 1 },
        "sanitized_transcript": [
            { "content": "password=supersecret123" }
        ]
    }')

    run env PATH="$fake_bin:/usr/bin:/bin" bash -c '
        set -euo pipefail
        source "$1"
        sanitize_session_export "$2"
        cat "$2"
    ' _ "$PROJECT_ROOT/scripts/lib/session.sh" "$file"

    assert_success
    refute_output --partial "supersecret123"
    assert_output --partial "[SECRET_REDACTED]"
    [[ ! -e "$marker" ]] || fail "sanitize_session_export used PATH-poisoned jq"
}

@test "sanitize_session_export: clears RETURN cleanup trap after success" {
    local json='{
        "schema_version": 1,
        "session_id": "123",
        "agent": "claude-code",
        "stats": { "turns": 1 },
        "sanitized_transcript": [
            { "content": "no secrets here" }
        ]
    }'
    local file
    file=$(create_temp_file "$json")

    run bash -c '
        set -euo pipefail
        source "$1"
        sanitize_session_export "$2" >/dev/null
        trap -p RETURN
    ' _ "$PROJECT_ROOT/scripts/lib/session.sh" "$file"

    assert_success
    assert_output ""
}

@test "sanitize_session_export: preserves caller RETURN trap" {
    local json='{
        "schema_version": 1,
        "session_id": "123",
        "agent": "claude-code",
        "stats": { "turns": 1 },
        "sanitized_transcript": [
            { "content": "no secrets here" }
        ]
    }'
    local file
    file=$(create_temp_file "$json")

    caller_wrapper() {
        trap 'printf "%s\n" sanitize-caller-return-fired' RETURN
        sanitize_session_export "$file" >/dev/null || return 1
        trap -p RETURN
    }

    run caller_wrapper
    assert_success
    assert_output --partial "sanitize-caller-return-fired"
}

@test "import_session: rejects malformed ACFS exports" {
    local malformed='{
        "schema_version": 1
    }'
    local file
    file=$(create_temp_file "$malformed")

    run import_session "$file" --dry-run
    assert_failure
    assert_output --partial "missing required fields"
}

@test "import_session: refuses a generated-ID collision without changing the existing session" {
    local test_home
    test_home=$(create_temp_dir)
    export HOME="$test_home"
    export ACFS_SESSIONS_DIR="$HOME/.acfs/sessions"
    mkdir -p "$ACFS_SESSIONS_DIR"
    printf '%s\n' "existing-session-sentinel" > "$ACFS_SESSIONS_DIR/fixed-id.json"

    generate_session_id() {
        printf '%s\n' "fixed-id"
    }

    local valid='{
        "schema_version": 1,
        "session_id": "import-source",
        "agent": "claude-code",
        "stats": { "turns": 1 },
        "sanitized_transcript": []
    }'
    local file
    file=$(create_temp_file "$valid")

    run import_session "$file"
    assert_failure
    assert_output --partial "Refusing to overwrite existing session destination"

    run cat "$ACFS_SESSIONS_DIR/fixed-id.json"
    assert_success
    assert_output "existing-session-sentinel"
}

@test "show_session: rejects traversal IDs before filesystem access" {
    run show_session "../../outside"
    assert_failure
    assert_output --partial "Session ID must be"
}

@test "import_session: preserves caller RETURN trap" {
    local test_home
    test_home=$(create_temp_dir)
    export HOME="$test_home"
    export ACFS_SESSIONS_DIR="$HOME/.acfs/sessions"

    local valid='{
        "schema_version": 1,
        "session_id": "import-source",
        "agent": "claude-code",
        "stats": { "turns": 1 },
        "sanitized_transcript": [
            { "role": "user", "content": "hello", "timestamp": "2026-03-03T01:00:00Z" }
        ]
    }'
    local file
    file=$(create_temp_file "$valid")

    caller_wrapper() {
        trap 'printf "%s\n" import-caller-return-fired' RETURN
        import_session "$file" >/dev/null || return 1
        trap -p RETURN
    }

    run caller_wrapper
    assert_success
    assert_output --partial "import-caller-return-fired"
}

@test "convert_session_native: codex -> claude writes native file and sessions-index" {
    local test_home
    test_home=$(create_temp_dir)
    export HOME="$test_home"
    export CLAUDE_HOME="$HOME/.claude"
    export CODEX_HOME="$HOME/.codex"
    export GEMINI_HOME="$HOME/.gemini"

    local codex_src="$test_home/source_codex.jsonl"
    cat > "$codex_src" <<'EOF'
{"timestamp":"2026-03-03T01:00:00Z","type":"session_meta","payload":{"id":"src-codex-id","cwd":"/data/projects/agentic_coding_flywheel_setup"}}
{"timestamp":"2026-03-03T01:00:01Z","type":"event_msg","payload":{"type":"user_message","message":"hello from codex"}}
{"timestamp":"2026-03-03T01:00:02Z","type":"response_item","payload":{"role":"assistant","content":[{"type":"output_text","text":"hello from assistant"}]}}
EOF

    run convert_session_native "$codex_src" --from codex --to claude-code --workspace "/data/projects/agentic_coding_flywheel_setup" --json
    assert_success

    local written_path target_session_id resume_command
    written_path="$(jq -r '.written_path' <<<"$output")"
    target_session_id="$(jq -r '.target_session_id' <<<"$output")"
    resume_command="$(jq -r '.resume_command' <<<"$output")"

    [[ -f "$written_path" ]]
    [[ "$written_path" == "$HOME/.claude/projects/-data-projects-agentic-coding-flywheel-setup/"*".jsonl" ]]

    run jq -r 'select(.type=="user" or .type=="assistant") | .type' "$written_path"
    assert_output --partial "user"
    assert_output --partial "assistant"

    local index_file="$HOME/.claude/projects/-data-projects-agentic-coding-flywheel-setup/sessions-index.json"
    [[ -f "$index_file" ]]
    run jq -r --arg sid "$target_session_id" '.entries[] | select(.sessionId == $sid) | .fullPath' "$index_file"
    assert_success
    assert_equal "$output" "$written_path"
    assert_equal "$resume_command" "claude -r $target_session_id"
}

@test "native conversion: refuses invalid and pre-existing target session IDs" {
    local test_home
    test_home=$(create_temp_dir)
    export HOME="$test_home"
    export CLAUDE_HOME="$HOME/.claude"

    local canonical
    canonical=$(create_temp_file '{
        "workspace": "/data/project",
        "source_session_id": "source-id",
        "messages": [{"role":"user","content":"hello","timestamp":"2026-03-03T01:00:00Z"}]
    }')

    run write_native_claude_from_canonical "$canonical" "/data/project" "../escape" true
    assert_failure
    assert_output --partial "Target session ID must be"

    local target_dir="$CLAUDE_HOME/projects/-data-project"
    local target_file="$target_dir/fixed-id.jsonl"
    mkdir -p "$target_dir"
    printf '%s\n' "existing-native-sentinel" > "$target_file"

    run write_native_claude_from_canonical "$canonical" "/data/project" "fixed-id" false
    assert_failure
    assert_output --partial "Refusing to overwrite existing session destination"

    run cat "$target_file"
    assert_success
    assert_output "existing-native-sentinel"
}

@test "native conversion: malformed Claude index cannot publish the staged target" {
    local test_home
    test_home=$(create_temp_dir)
    export HOME="$test_home"
    export CLAUDE_HOME="$HOME/.claude"

    local canonical
    canonical=$(create_temp_file '{
        "workspace": "/data/project",
        "source_session_id": "source-id",
        "messages": [{"role":"user","content":"hello","timestamp":"2026-03-03T01:00:00Z"}]
    }')

    local target_dir="$CLAUDE_HOME/projects/-data-project"
    local target_file="$target_dir/fixed-id.jsonl"
    mkdir -p "$target_dir"
    printf '%s\n' '{malformed' > "$target_dir/sessions-index.json"

    run write_native_claude_from_canonical "$canonical" "/data/project" "fixed-id" false
    assert_failure
    assert_output --partial "Failed to update Claude sessions-index"
    [[ ! -e "$target_file" ]]
}

@test "native conversion: malformed Gemini logs cannot publish the staged target" {
    local test_home
    test_home=$(create_temp_dir)
    export HOME="$test_home"
    export GEMINI_HOME="$HOME/.gemini"

    local canonical
    canonical=$(create_temp_file '{
        "workspace": "/data/project",
        "source_session_id": "source-id",
        "project_hash": "project-hash",
        "messages": [{"role":"user","content":"hello","timestamp":"2026-03-03T01:00:00Z"}]
    }')

    local root_dir="$GEMINI_HOME/tmp/project"
    mkdir -p "$root_dir"
    printf '%s\n' '/data/project' > "$root_dir/.project_root"
    printf '%s\n' '{malformed' > "$root_dir/logs.json"

    run write_native_gemini_from_canonical "$canonical" "/data/project" "fixed-id" false
    assert_failure
    assert_output --partial "Refusing to replace malformed Gemini logs file"
    if compgen -G "$root_dir/chats/session-*-fixed-id.json" >/dev/null; then
        fail "Gemini target was published before logs metadata validated"
    fi
}

@test "convert_session_native: preserves caller RETURN trap" {
    local test_home
    test_home=$(create_temp_dir)
    export HOME="$test_home"
    export CLAUDE_HOME="$HOME/.claude"
    export CODEX_HOME="$HOME/.codex"
    export GEMINI_HOME="$HOME/.gemini"

    local codex_src="$test_home/source_codex_return_trap.jsonl"
    cat > "$codex_src" <<'EOF'
{"timestamp":"2026-03-03T01:00:00Z","type":"session_meta","payload":{"id":"src-codex-id","cwd":"/data/projects/agentic_coding_flywheel_setup"}}
{"timestamp":"2026-03-03T01:00:01Z","type":"event_msg","payload":{"type":"user_message","message":"hello from codex"}}
{"timestamp":"2026-03-03T01:00:02Z","type":"response_item","payload":{"role":"assistant","content":[{"type":"output_text","text":"hello from assistant"}]}}
EOF

    caller_wrapper() {
        trap 'printf "%s\n" convert-caller-return-fired' RETURN
        convert_session_native "$codex_src" --from codex --to claude-code --workspace "/data/projects/agentic_coding_flywheel_setup" --json >/dev/null || return 1
        trap -p RETURN
    }

    run caller_wrapper
    assert_success
    assert_output --partial "convert-caller-return-fired"
}

@test "convert_session_native: claude -> codex writes native rollout format" {
    local test_home
    test_home=$(create_temp_dir)
    export HOME="$test_home"
    export CLAUDE_HOME="$HOME/.claude"
    export CODEX_HOME="$HOME/.codex"
    export GEMINI_HOME="$HOME/.gemini"

    local claude_src="$test_home/source_claude.jsonl"
    cat > "$claude_src" <<'EOF'
{"parentUuid":null,"isSidechain":false,"userType":"external","cwd":"/data/projects/agentic_coding_flywheel_setup","sessionId":"src-claude-id","version":"2.1.32","gitBranch":"main","type":"user","message":{"role":"user","content":"hello from claude"},"uuid":"u1","timestamp":"2026-03-03T01:10:00Z"}
{"parentUuid":"u1","isSidechain":false,"userType":"external","cwd":"/data/projects/agentic_coding_flywheel_setup","sessionId":"src-claude-id","version":"2.1.32","gitBranch":"main","type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"assistant reply"}]},"uuid":"u2","timestamp":"2026-03-03T01:10:01Z"}
EOF

    run convert_session_native "$claude_src" --from claude-code --to codex --workspace "/data/projects/agentic_coding_flywheel_setup" --json
    assert_success

    local written_path target_session_id resume_command
    written_path="$(jq -r '.written_path' <<<"$output")"
    target_session_id="$(jq -r '.target_session_id' <<<"$output")"
    resume_command="$(jq -r '.resume_command' <<<"$output")"

    [[ -f "$written_path" ]]
    [[ "$written_path" == "$HOME/.codex/sessions/"*"/rollout-"*".jsonl" ]]

    run head -n 1 "$written_path"
    assert_output --partial '"type":"session_meta"'
    assert_output --partial "\"id\":\"$target_session_id\""

    run jq -r '.type' "$written_path"
    assert_output --partial "session_meta"
    assert_output --partial "event_msg"
    assert_output --partial "response_item"
    assert_equal "$resume_command" "codex exec resume $target_session_id"
}

@test "convert_session_native: codex -> gemini writes chat json and logs" {
    local test_home
    test_home=$(create_temp_dir)
    export HOME="$test_home"
    export CLAUDE_HOME="$HOME/.claude"
    export CODEX_HOME="$HOME/.codex"
    export GEMINI_HOME="$HOME/.gemini"

    local codex_src="$test_home/source_codex_for_gemini.jsonl"
    cat > "$codex_src" <<'EOF'
{"timestamp":"2026-03-03T02:00:00Z","type":"session_meta","payload":{"id":"src-codex-id-2","cwd":"/data/projects/agentic_coding_flywheel_setup"}}
{"timestamp":"2026-03-03T02:00:01Z","type":"event_msg","payload":{"type":"user_message","message":"gemini please continue"}}
{"timestamp":"2026-03-03T02:00:02Z","type":"response_item","payload":{"role":"assistant","content":[{"type":"output_text","text":"continuing now"}]}}
EOF

    run convert_session_native "$codex_src" --from codex --to gemini --workspace "/data/projects/agentic_coding_flywheel_setup" --json
    assert_success

    local written_path target_session_id
    written_path="$(jq -r '.written_path' <<<"$output")"
    target_session_id="$(jq -r '.target_session_id' <<<"$output")"

    [[ -f "$written_path" ]]
    [[ "$written_path" == "$HOME/.gemini/tmp/agentic-coding-flywheel-setup/chats/session-"*".json" ]]

    run jq -r '.sessionId' "$written_path"
    assert_equal "$output" "$target_session_id"

    run jq -r '.messages[0].type' "$written_path"
    assert_equal "$output" "user"

    run jq -r '.projectHash' "$written_path"
    [[ "$output" =~ ^[0-9a-f]{64}$ ]]

    local root_dir
    root_dir="$(dirname "$(dirname "$written_path")")"
    local logs_file="$root_dir/logs.json"
    [[ -f "$logs_file" ]]
    run jq -r --arg sid "$target_session_id" '.[] | select(.sessionId == $sid) | .type' "$logs_file"
    assert_success
    assert_output --partial "user"
}
