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

@test "list_sessions: rejects non-numeric day and limit values before calling cass" {
    run list_sessions --days nope
    assert_failure
    assert_output --partial "positive integer"

    run list_sessions --limit zero
    assert_failure
    assert_output --partial "positive integer"
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
    assert_output --partial "password=[REDACTED]"
    assert_output --partial '"session_id": "123"'
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
