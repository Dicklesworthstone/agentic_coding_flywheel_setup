#!/usr/bin/env bats

load '../test_helper'

setup() {
    common_setup
    source_lib "logging"
    source_lib "state"
    
    # Setup a temp state file
    export ACFS_HOME=$(create_temp_dir)
    export ACFS_STATE_FILE="$ACFS_HOME/state.json"
}

teardown() {
    common_teardown
}


@test "state: both parsers preserve safe and vibe modes with legacy and scoped checkpoints" {
    local python_fallback=false parser install_mode scoped
    command() {
        if [[ "$python_fallback" == true && "$1" == -v && "$2" == jq ]]; then
            return 1
        fi
        builtin command "$@"
    }
    for parser in jq python; do
        python_fallback=false
        [[ "$parser" != python ]] || python_fallback=true
        for install_mode in safe vibe; do
            for scoped in false true; do
                jq -n --arg mode "$install_mode" --argjson scoped "$scoped" '
                    {mode:$mode} + if $scoped then {
                        module_selection:{schema_version:1,selected_modules:["lang.bun"]}
                    } else {} end' > "$ACFS_STATE_FILE"
                cp "$ACFS_STATE_FILE" "$BATS_TEST_TMPDIR/mode-before-read.json"
                state_load_module_selection "$ACFS_STATE_FILE"
                [[ "$ACFS_STATE_INSTALL_MODE" == "$install_mode" ]]
                if [[ "$scoped" == true ]]; then
                    [[ "$ACFS_STATE_SELECTION_MODE" == scoped ]]
                    state_module_is_selected lang.bun
                else
                    [[ "$ACFS_STATE_SELECTION_MODE" == legacy ]]
                fi
                run cmp "$ACFS_STATE_FILE" "$BATS_TEST_TMPDIR/mode-before-read.json"
                assert_success
            done
        done
    done
}

@test "state: missing legacy modes and missing checkpoints clear a previous mode" {
    local python_fallback=false parser checkpoint
    command() {
        if [[ "$python_fallback" == true && "$1" == -v && "$2" == jq ]]; then
            return 1
        fi
        builtin command "$@"
    }
    for parser in jq python; do
        python_fallback=false
        [[ "$parser" != python ]] || python_fallback=true
        printf '%s\n' '{"mode":"safe"}' > "$ACFS_STATE_FILE"
        printf '%s\n' '{}' > "$ACFS_HOME/legacy.json"
        printf '%s\n' '{"module_selection":{"schema_version":1,"selected_modules":["lang.bun"]}}' > "$ACFS_HOME/scoped.json"
        for checkpoint in "$ACFS_HOME/legacy.json" "$ACFS_HOME/scoped.json" "$ACFS_HOME/not-installed.json"; do
            state_load_module_selection "$ACFS_STATE_FILE"
            [[ "$ACFS_STATE_INSTALL_MODE" == safe ]]
            state_load_module_selection "$checkpoint"
            [[ -z "$ACFS_STATE_INSTALL_MODE" ]]
        done
    done
}

@test "state: both parsers reject invalid install modes without retaining earlier policy" {
    local python_fallback=false parser invalid_mode scoped
    command() {
        if [[ "$python_fallback" == true && "$1" == -v && "$2" == jq ]]; then
            return 1
        fi
        builtin command "$@"
    }
    for parser in jq python; do
        python_fallback=false
        [[ "$parser" != python ]] || python_fallback=true
        for invalid_mode in null false 0 '[]' '{}' '""' '"unknown"' '"safe\nvibe"'; do
            for scoped in false true; do
                printf '%s\n' '{"mode":"safe","module_selection":{"schema_version":1,"selected_modules":["lang.bun"]}}' > "$ACFS_HOME/valid-mode.json"
                state_load_module_selection "$ACFS_HOME/valid-mode.json"
                [[ "$ACFS_STATE_INSTALL_MODE" == safe ]]
                jq -n --argjson mode "$invalid_mode" --argjson scoped "$scoped" '
                    {mode:$mode} + if $scoped then {
                        module_selection:{schema_version:1,selected_modules:["lang.bun"]}
                    } else {} end' > "$ACFS_STATE_FILE"
                cp "$ACFS_STATE_FILE" "$BATS_TEST_TMPDIR/invalid-mode-before-read.json"
                if state_load_module_selection "$ACFS_STATE_FILE"; then
                    return 1
                fi
                [[ "$ACFS_STATE_SELECTION_MODE" == invalid ]]
                [[ -z "$ACFS_STATE_INSTALL_MODE" ]]
                [[ "${#ACFS_STATE_SELECTED_MODULES[@]}" -eq 0 ]]
                run cmp "$ACFS_STATE_FILE" "$BATS_TEST_TMPDIR/invalid-mode-before-read.json"
                assert_success
            done
        done
    done
}


@test "state: accepted mode changes persist without narrowing scoped or legacy intent" {
    local scoped
    for scoped in false true; do
        jq -n --argjson scoped "$scoped" '
            {mode:"safe",operator_note:"retain me",completed_phases:["user_setup"]} +
            if $scoped then {
                module_selection:{schema_version:1,selected_modules:["lang.bun"],requested_modules:[]}
            } else {} end' > "$ACFS_STATE_FILE"
        MODE=vibe
        state_record_module_selection lang.bun
        run jq -e --argjson scoped "$scoped" '
            .mode == "vibe" and .operator_note == "retain me" and
            .completed_phases == ["user_setup"] and
            (if $scoped then .module_selection.selected_modules == ["lang.bun"]
             else has("module_selection") | not end)' "$ACFS_STATE_FILE"
        assert_success

        unset MODE
        cp "$ACFS_STATE_FILE" "$BATS_TEST_TMPDIR/accepted-mode.json"
        state_record_module_selection lang.bun
        run cmp "$ACFS_STATE_FILE" "$BATS_TEST_TMPDIR/accepted-mode.json"
        assert_success

        MODE=safe
        state_record_module_selection lang.bun
        state_load_module_selection "$ACFS_STATE_FILE"
        [[ "$ACFS_STATE_INSTALL_MODE" == safe ]]
    done
}

@test "state: init creates valid json" {
    run state_init
    assert_success
    
    run cat "$ACFS_STATE_FILE"
    assert_output --partial '"version":'
    assert_output --partial '"completed_phases": []'
}

@test "state: explicit optional requests survive bootstrap and later targeted repairs" {
    local python_fallback=false parser
    command() {
        if [[ "$python_fallback" == true && "${1:-}" == -v && "${2:-}" == jq ]]; then
            return 1
        fi
        builtin command "$@"
    }
    declare -A ACFS_PLAN_REASON=(
        [agents.grok]="explicitly requested"
        [agents.codex]="phase 7"
    )
    ACFS_EFFECTIVE_PLAN=(agents.grok agents.codex)
    for parser in jq python; do
        python_fallback=false
        [[ "$parser" != python ]] || python_fallback=true
        ACFS_STATE_FILE="$ACFS_HOME/$parser.json"
        state_init
        state_load_module_selection "$ACFS_STATE_FILE"
        [[ "${ACFS_STATE_REQUESTED_MODULES[*]}" == agents.grok ]]
        run jq -e '.module_selection.requested_modules == ["agents.grok"]' "$ACFS_STATE_FILE"
        assert_success
    done

    python_fallback=false
    ACFS_PLAN_REASON=([agents.codex]="explicitly requested")
    state_record_module_selection agents.codex
    state_load_module_selection "$ACFS_STATE_FILE"
    [[ "${ACFS_STATE_REQUESTED_MODULES[*]}" == "agents.grok agents.codex" ]]
    cp "$ACFS_STATE_FILE" "$BATS_TEST_TMPDIR/requirements-before-repeat.json"
    state_record_module_selection agents.codex
    run cmp "$ACFS_STATE_FILE" "$BATS_TEST_TMPDIR/requirements-before-repeat.json"
    assert_success
}

@test "state: force reinstall and progress recovery retain explicit required roots" {
    ACFS_EFFECTIVE_PLAN=(agents.grok agents.codex)
    declare -A ACFS_PLAN_REASON=([agents.grok]="explicitly requested")
    state_init
    ACFS_FORCE_REINSTALL=true
    ACFS_EFFECTIVE_PLAN=(lang.go)
    ACFS_PLAN_REASON=([lang.go]="explicitly requested")
    local result=0
    confirm_resume || result=$?
    [[ "$result" -eq 1 ]]
    state_init
    state_load_module_selection "$ACFS_STATE_FILE"
    [[ "${ACFS_STATE_REQUESTED_MODULES[*]}" == "agents.grok lang.go" ]]

    YES_MODE=true
    printf '%s\n' '{"schema_version":3,"module_selection":{"schema_version":1,"selected_modules":["agents.grok"],"requested_modules":["agents.grok"]}}' > "$ACFS_STATE_FILE"
    ACFS_FORCE_REINSTALL=false
    ACFS_EFFECTIVE_PLAN=(lang.bun)
    ACFS_PLAN_REASON=()
    state_ensure_valid
    [[ ! -f "$ACFS_STATE_FILE" ]]
    result=0
    confirm_resume || result=$?
    [[ "$result" -eq 1 ]]
    state_init
    state_load_module_selection "$ACFS_STATE_FILE"
    [[ "${ACFS_STATE_REQUESTED_MODULES[*]}" == agents.grok ]]
    state_module_is_selected lang.bun
}

@test "state: both parsers reject invalid requested roots and clear prior policy" {
    local python_fallback=false parser requested
    command() {
        if [[ "$python_fallback" == true && "${1:-}" == -v && "${2:-}" == jq ]]; then
            return 1
        fi
        builtin command "$@"
    }
    for parser in jq python; do
        python_fallback=false
        [[ "$parser" != python ]] || python_fallback=true
        printf '%s\n' '{"module_selection":{"schema_version":1,"selected_modules":["agents.grok"]}}' > "$ACFS_STATE_FILE"
        state_load_module_selection "$ACFS_STATE_FILE"
        [[ ${#ACFS_STATE_REQUESTED_MODULES[@]} -eq 0 ]]
        for requested in null false '{}' '"agents.grok"' '[null]' '[true]' \
            '["agents.grok","agents.grok"]' '["agents.codex"]' '["agents.grok\n"]'; do
            jq -n --argjson requested "$requested" \
                '{module_selection:{schema_version:1,selected_modules:["agents.grok"],requested_modules:$requested}}' > "$ACFS_STATE_FILE"
            ACFS_STATE_REQUESTED_MODULES=(agents.grok)
            if state_load_module_selection "$ACFS_STATE_FILE"; then
                fail "Accepted invalid requested roots using $parser: $requested"
            fi
            [[ "$ACFS_STATE_SELECTION_MODE" == invalid ]]
            [[ ${#ACFS_STATE_SELECTED_MODULES[@]} -eq 0 ]]
            [[ ${#ACFS_STATE_REQUESTED_MODULES[@]} -eq 0 ]]
        done
    done
}

@test "state: default legacy identity policy rejects conflicts and cannot weaken custom reads" {
    local target_home="$ACFS_HOME/identity-home"
    local checkpoint="$target_home/.acfs/state.json"
    local python_fallback=false parser identity
    mkdir -p "$target_home/.acfs"
    command() {
        if [[ "$python_fallback" == true && "${1:-}" == -v && "${2:-}" == jq ]]; then
            return 1
        fi
        builtin command "$@"
    }
    for parser in jq python; do
        python_fallback=false
        [[ "$parser" != python ]] || python_fallback=true
        printf '%s\n' '{}' > "$checkpoint"
        state_load_module_selection "$checkpoint" "$target_home" fixture allow-legacy-identity
        [[ "$ACFS_STATE_SELECTION_MODE" == legacy ]]
        if state_load_module_selection "$checkpoint" "$target_home" fixture; then
            fail "Strict custom identity accepted absent metadata with $parser"
        fi
        for identity in '{"target_home":null}' '{"target_home":false}' '{"target_home":17}' \
            '{"target_home":"/another/home"}' '{"target_user":null}' '{"target_user":[]}' \
            '{"target_user":17}' '{"target_user":"someone_else"}'; do
            printf '%s\n' "$identity" > "$checkpoint"
            if state_load_module_selection "$checkpoint" "$target_home" fixture allow-legacy-identity; then
                fail "Accepted foreign or invalid default identity using $parser: $identity"
            fi
        done
        jq -n --arg home "$target_home" '{target_home:$home,target_user:"fixture"}' > "$checkpoint"
        state_load_module_selection "$checkpoint" "$target_home" fixture
        state_load_module_selection "$checkpoint" "$target_home" fixture allow-legacy-identity
        cp "$checkpoint" "$ACFS_HOME/custom-checkpoint.json"
        state_load_module_selection "$ACFS_HOME/custom-checkpoint.json" "$target_home" fixture
        if state_load_module_selection "$ACFS_HOME/custom-checkpoint.json" "$target_home" fixture allow-legacy-identity; then
            fail "Default-only policy accepted a custom path using $parser"
        fi
        if state_load_module_selection "$checkpoint" "$target_home" fixture unknown-policy; then
            fail "Accepted an unknown identity policy using $parser"
        fi
        state_load_module_selection "$ACFS_HOME/missing-home/.acfs/state.json" "$ACFS_HOME/missing-home" fixture allow-legacy-identity
        [[ "$ACFS_STATE_SELECTION_MODE" == legacy ]]
    done
}

@test "state: saved scope excludes unrelated phases while completed selected phases stay verifiable" {
    ACFS_EFFECTIVE_PLAN=(lang.bun)
    declare -A ACFS_MODULE_PHASE=([lang.bun]=6)
    ONLY_MODULES=()
    ONLY_PHASES=()
    ACFS_SAVED_SELECTION_ACTIVE=true
    state_init
    state_phase_complete languages
    local verification_status=0
    acfs_verify_phase() {
        printf '%s:%s\n' "$1" "$2" >> "$ACFS_HOME/verification-events"
        return "$verification_status"
    }
    state_should_skip_phase agents
    [[ ! -f "$ACFS_HOME/verification-events" ]]
    state_should_skip_phase languages
    run cat "$ACFS_HOME/verification-events"
    assert_output "languages:resume"
    verification_status=1
    if state_should_skip_phase languages; then
        fail "A failed selected verifier was skipped"
    fi
    verification_status=0
    ONLY_MODULES=(lang.bun)
    if state_should_skip_phase languages; then
        fail "An explicit selected repair was skipped"
    fi
}

@test "state: fresh module selection survives a separate maintenance process" {
    ACFS_EFFECTIVE_PLAN=(base.system lang.bun agents.claude)
    state_init

    run bash -eu -c '
        source "$1"
        state_load_module_selection "$2"
        [[ "$ACFS_STATE_SELECTION_MODE" == scoped ]]
        state_validate_module_selection_catalog base.system lang.bun agents.claude stack.ntm
        state_module_is_selected agents.claude
        if state_module_is_selected stack.ntm; then exit 21; fi
        printf "%s\n" "${ACFS_STATE_SELECTED_MODULES[@]}"
    ' _ "$PROJECT_ROOT/scripts/lib/state.sh" "$ACFS_STATE_FILE"
    assert_success
    assert_output $'base.system\nlang.bun\nagents.claude'
}

@test "state: targeted repair extends scope without hiding selected failures" {
    ACFS_EFFECTIVE_PLAN=(base.system agents.claude)
    state_init
    state_phase_start agents
    state_phase_fail agents agents.claude "selected installer failed"
    state_update '.skipped_tools = ["agents.claude"] | .operator_note = "retain me"'

    state_record_module_selection base.system lang.go
    state_load_module_selection "$ACFS_STATE_FILE"
    state_module_is_selected agents.claude
    state_module_is_selected lang.go
    run jq -er '.failed_phase == "agents" and .operator_note == "retain me" and .module_selection.selected_modules == ["base.system", "agents.claude", "lang.go"]' "$ACFS_STATE_FILE"
    assert_success
    assert_output true

    cp "$ACFS_STATE_FILE" "$BATS_TEST_TMPDIR/before-repeat.json"
    state_record_module_selection lang.go base.system
    run cmp "$ACFS_STATE_FILE" "$BATS_TEST_TMPDIR/before-repeat.json"
    assert_success
}

@test "state: zero-phase retries preserve the earlier managed scope" {
    ACFS_EFFECTIVE_PLAN=(base.system agents.claude)
    state_init
    ACFS_EFFECTIVE_PLAN=(base.system agents.codex)
    local result=0
    confirm_resume || result=$?
    [[ "$result" -eq 1 ]]
    state_init
    state_load_module_selection "$ACFS_STATE_FILE"
    state_module_is_selected agents.claude
    state_module_is_selected agents.codex
}

@test "state: force-reinstall repair preserves scope across the checkpoint backup" {
    ACFS_EFFECTIVE_PLAN=(base.system agents.claude)
    state_init
    ACFS_EFFECTIVE_PLAN=(base.system lang.go)
    ACFS_FORCE_REINSTALL=true
    local result=0
    confirm_resume || result=$?
    [[ "$result" -eq 1 ]]
    [[ ! -f "$ACFS_STATE_FILE" ]]
    state_init
    state_load_module_selection "$ACFS_STATE_FILE"
    state_module_is_selected agents.claude
    state_module_is_selected lang.go
}

@test "state: targeted and force reinstall do not narrow legacy checkpoints" {
    state_init
    ACFS_EFFECTIVE_PLAN=(lang.go)
    state_record_module_selection lang.go
    ACFS_FORCE_REINSTALL=true
    local result=0
    confirm_resume || result=$?
    [[ "$result" -eq 1 ]]
    state_init
    state_load_module_selection "$ACFS_STATE_FILE"
    [[ "$ACFS_STATE_SELECTION_MODE" == legacy ]]
    state_module_is_selected stack.ntm
    run jq -er 'has("module_selection") | not' "$ACFS_STATE_FILE"
    assert_success
    assert_output true
}

@test "state: module selection is cleared before reading another target" {
    ACFS_EFFECTIVE_PLAN=(agents.claude)
    state_init
    state_load_module_selection "$ACFS_STATE_FILE"
    [[ "$ACFS_STATE_SELECTION_MODE" == scoped ]]
    state_load_module_selection "$ACFS_HOME/not-installed.json"
    [[ "$ACFS_STATE_SELECTION_MODE" == legacy ]]
    [[ ${#ACFS_STATE_SELECTED_MODULES[@]} -eq 0 ]]
    state_module_is_selected agents.codex

    printf '%s\n' '{"module_selection":null}' > "$ACFS_HOME/broken.json"
    if state_load_module_selection "$ACFS_HOME/broken.json"; then return 1; fi
    [[ "$ACFS_STATE_SELECTION_MODE" == invalid ]]
    [[ ${#ACFS_STATE_SELECTED_MODULES[@]} -eq 0 ]]
    run state_module_is_selected agents.claude
    [[ "$status" -eq 2 ]]
}

@test "state: malformed explicit module selections fail without overwriting the checkpoint" {
    local selection
    for selection in 'null' 'false' '[]' '{}' \
        '{"schema_version":2,"selected_modules":["lang.go"]}' \
        '{"schema_version":true,"selected_modules":["lang.go"]}' \
        '{"schema_version":1,"selected_modules":[]}' \
        '{"schema_version":1,"selected_modules":"lang.go"}' \
        '{"schema_version":1,"selected_modules":[null]}' \
        '{"schema_version":1,"selected_modules":["lang.go","lang.go"]}' \
        '{"schema_version":1,"selected_modules":["lang.go\n"]}' \
        '{"schema_version":1,"selected_modules":["../../etc/passwd"]}'; do
        jq -n --argjson scope "$selection" '{schema_version:3,version:"test",mode:"safe",completed_phases:[],module_selection:$scope}' > "$ACFS_STATE_FILE"
        cp "$ACFS_STATE_FILE" "$BATS_TEST_TMPDIR/invalid-before.json"
        run state_record_module_selection agents.claude
        assert_failure
        run cmp "$ACFS_STATE_FILE" "$BATS_TEST_TMPDIR/invalid-before.json"
        assert_success
    done
}

@test "state: bootstrap without jq records the same scope and rejects malformed selections" {
    # Exercise the production bootstrap serializer and Python read-only fallback.
    # jq remains callable below to inspect the resulting file, but availability
    # detection models a fresh machine before the base dependencies are installed.
    command() {
        if [[ "${1:-}" == -v && "${2:-}" == jq ]]; then
            return 1
        fi
        builtin command "$@"
    }
    ACFS_EFFECTIVE_PLAN=(base.system agents.claude)
    state_init
    state_load_module_selection "$ACFS_STATE_FILE"
    [[ "$ACFS_STATE_SELECTION_MODE" == scoped ]]
    state_module_is_selected agents.claude
    run jq -er '.module_selection == {schema_version:1,selected_modules:["base.system","agents.claude"],requested_modules:[]}' "$ACFS_STATE_FILE"
    assert_success
    assert_output true

    local selection
    for selection in 'null' \
        '{"schema_version":true,"selected_modules":["lang.go"]}' \
        '{"schema_version":2,"selected_modules":["lang.go"]}' \
        '{"schema_version":1,"selected_modules":[]}' \
        '{"schema_version":1,"selected_modules":["lang.go","lang.go"]}' \
        '{"schema_version":1,"selected_modules":["lang.go\n"]}'; do
        jq -n --argjson scope "$selection" '{module_selection:$scope}' > "$ACFS_HOME/python-invalid.json"
        run state_load_module_selection "$ACFS_HOME/python-invalid.json"
        assert_failure
    done
    printf '%s\n' '{}' '{}' > "$ACFS_HOME/python-stream.json"
    run state_load_module_selection "$ACFS_HOME/python-stream.json"
    assert_failure
    printf '%s\n' '{}' > "$ACFS_HOME/python-legacy.json"
    state_load_module_selection "$ACFS_HOME/python-legacy.json"
    [[ "$ACFS_STATE_SELECTION_MODE" == legacy ]]
}

@test "state: invalid scope cannot be erased by force-reinstall" {
    state_init
    state_update '.module_selection = {schema_version:1,selected_modules:[]}'
    cp "$ACFS_STATE_FILE" "$BATS_TEST_TMPDIR/invalid-before.json"
    ACFS_FORCE_REINSTALL=true
    run confirm_resume
    [[ "$status" -eq 3 ]]
    run cmp "$ACFS_STATE_FILE" "$BATS_TEST_TMPDIR/invalid-before.json"
    assert_success
}

@test "state: automatic recovery refuses invalid scope before backing up damaged state" {
    YES_MODE=true
    printf '%s\n' '{"module_selection":{"schema_version":1,"selected_modules":[]}}' > "$ACFS_STATE_FILE"
    cp "$ACFS_STATE_FILE" "$BATS_TEST_TMPDIR/recovery-before.json"
    run state_ensure_valid
    assert_failure
    run cmp "$ACFS_STATE_FILE" "$BATS_TEST_TMPDIR/recovery-before.json"
    assert_success

    printf '%s\n' '{"module_selection":' > "$ACFS_STATE_FILE"
    cp "$ACFS_STATE_FILE" "$BATS_TEST_TMPDIR/recovery-before.json"
    run confirm_resume
    [[ "$status" -eq 3 ]]
    run cmp "$ACFS_STATE_FILE" "$BATS_TEST_TMPDIR/recovery-before.json"
    assert_success
}

@test "state: recovery preserves valid scope when outer progress fields are damaged" {
    YES_MODE=true
    printf '%s\n' '{"schema_version":3,"module_selection":{"schema_version":1,"selected_modules":["agents.claude"]}}' > "$ACFS_STATE_FILE"
    ACFS_EFFECTIVE_PLAN=(lang.go)
    state_ensure_valid
    [[ ! -f "$ACFS_STATE_FILE" ]]
    local result=0
    confirm_resume || result=$?
    [[ "$result" -eq 1 ]]
    state_init
    state_load_module_selection "$ACFS_STATE_FILE"
    state_module_is_selected agents.claude
    state_module_is_selected lang.go
}

@test "state: recovery preserves legacy full-install scope across progress reset" {
    YES_MODE=true
    printf '%s\n' '{"schema_version":3}' > "$ACFS_STATE_FILE"
    ACFS_EFFECTIVE_PLAN=(lang.go)
    state_ensure_valid
    [[ ! -f "$ACFS_STATE_FILE" ]]
    local result=0
    confirm_resume || result=$?
    [[ "$result" -eq 1 ]]
    state_init
    state_load_module_selection "$ACFS_STATE_FILE"
    [[ "$ACFS_STATE_SELECTION_MODE" == legacy ]]
    state_module_is_selected agents.claude
}

@test "state: unknown module selections require a compatible catalogue" {
    ACFS_EFFECTIVE_PLAN=(stack.future_tool)
    state_init
    state_load_module_selection "$ACFS_STATE_FILE"
    run state_validate_module_selection_catalog base.system agents.claude
    assert_failure
    assert_output --partial 'unsupported module: stack.future_tool'
    run state_validate_module_selection_catalog
    assert_failure
    assert_output --partial 'catalogue is unavailable'
    run state_validate_module_selection_catalog stack.future_tool
    assert_success
}

@test "state: module selection read rejects streams links and multiple JSON objects" {
    mkfifo "$ACFS_HOME/state-pipe"
    run state_load_module_selection "$ACFS_HOME/state-pipe"
    assert_failure
    state_init
    ln -s "$ACFS_STATE_FILE" "$ACFS_HOME/state-link"
    run state_load_module_selection "$ACFS_HOME/state-link"
    assert_failure
    printf '%s\n' '{}' '{}' > "$ACFS_HOME/two-states.json"
    run state_load_module_selection "$ACFS_HOME/two-states.json"
    assert_failure
}

@test "state: module selection write failure preserves prior scope and releases its lock" {
    ACFS_EFFECTIVE_PLAN=(lang.go)
    state_init
    cp "$ACFS_STATE_FILE" "$BATS_TEST_TMPDIR/write-before.json"
    state_write_atomic() { return 1; }
    if state_record_module_selection agents.claude; then return 1; fi
    [[ "$_ACFS_STATE_LOCKED" == false ]]
    run cmp "$ACFS_STATE_FILE" "$BATS_TEST_TMPDIR/write-before.json"
    assert_success
}

@test "state: module selection readers are read-only and ignore inherited policy" {
    ACFS_EFFECTIVE_PLAN=(lang.go)
    state_init
    cp "$ACFS_STATE_FILE" "$BATS_TEST_TMPDIR/read-before.json"
    run env ACFS_STATE_SELECTION_MODE=legacy bash -eu -c '
        source "$1"
        rc=0
        state_module_is_selected agents.claude || rc=$?
        [[ "$rc" -eq 2 ]]
        state_load_module_selection "$2"
        state_module_is_selected lang.go
    ' _ "$PROJECT_ROOT/scripts/lib/state.sh" "$ACFS_STATE_FILE"
    assert_success
    assert_output ''
    run cmp "$ACFS_STATE_FILE" "$BATS_TEST_TMPDIR/read-before.json"
    assert_success
}

@test "state: custom checkpoints validate target identity with either parser" {
    jq -n '{target_home:"/home/custom",target_user:"custom",module_selection:{schema_version:1,selected_modules:["lang.go"]}}' > "$ACFS_STATE_FILE"
    local parser
    for parser in jq python; do
        if [[ "$parser" == python ]]; then
            command() {
                if [[ "${1:-}" == -v && "${2:-}" == jq ]]; then return 1; fi
                builtin command "$@"
            }
            if command -v jq >/dev/null 2>&1; then return 1; fi
        fi
        state_load_module_selection "$ACFS_STATE_FILE" /home/custom custom
        state_module_is_selected lang.go
        run state_load_module_selection "$ACFS_STATE_FILE" /home/other custom
        assert_failure
        assert_output --partial 'does not belong to the resolved target'
        run state_load_module_selection "$ACFS_STATE_FILE" /home/custom other
        assert_failure
        run state_load_module_selection "$ACFS_HOME/not-installed.json" /home/custom custom
        assert_failure
        printf '%s\n' '{}' > "$ACFS_HOME/missing-identity.json"
        run state_load_module_selection "$ACFS_HOME/missing-identity.json" /home/custom custom
        assert_failure
    done
}

@test "state: validation rejects non-integer schema data before Bash arithmetic" {
    local marker="$BATS_TEST_TMPDIR/arithmetic-marker"
    printf \
        '{"schema_version":"probe[$(touch %s)]","version":"0.7.0","mode":"vibe","completed_phases":[]}\n' \
        "$marker" > "$ACFS_STATE_FILE"

    run state_validate

    [ "$status" -eq 3 ]
    refute_output --partial "probe["
    [[ ! -e "$marker" ]]
}

@test "state: validation accepts only bounded integer schema versions" {
    local schema_version
    for schema_version in '2.5' '0' '2147483648' '"3"' 'null' '[]'; do
        printf '{"schema_version":%s,"version":"0.7.0","mode":"vibe","completed_phases":[]}\n' \
            "$schema_version" > "$ACFS_STATE_FILE"

        run state_validate
        [ "$status" -eq 3 ]
    done
}

@test "state: init tolerates missing ACFS_VERSION under nounset" {
    local state_root
    state_root=$(create_temp_dir)

    run env -i PATH="$PATH" HOME="$state_root/home" ACFS_HOME="$state_root/acfs" ACFS_STATE_FILE="$state_root/acfs/state.json" bash -u -c '
        mkdir -p "$HOME" "$ACFS_HOME"
        source "$1"
        state_init
        jq -r .version "$ACFS_STATE_FILE"
    ' _ "$PROJECT_ROOT/scripts/lib/state.sh"
    assert_success
    assert_output "unknown"
}

@test "state: system binary resolver rejects pathlike names" {
    run state_system_binary_path "."
    assert_failure
    run state_system_binary_path ".."
    assert_failure
    run state_system_binary_path "../bin/sh"
    assert_failure
    run state_system_binary_path "/bin/sh"
    assert_failure
    run state_system_binary_path "sh name"
    assert_failure
}

@test "state: init sudo fallback is noninteractive" {
    [[ "$EUID" -ne 0 ]] || skip "sudo fallback is bypassed when tests run as root"

    local fake_bin
    local real_id
    local real_mkdir
    local state_root
    local sudo_log

    fake_bin=$(create_temp_dir)
    real_id="$(command -v id)"
    real_mkdir="$(command -v mkdir)"
    state_root="$BATS_TEST_TMPDIR/state-sudo-fallback"
    sudo_log="$BATS_TEST_TMPDIR/state-sudo-argv.txt"

    export ACFS_FAKE_CHOWN="$fake_bin/chown"
    export ACFS_FAKE_MKDIR="$fake_bin/mkdir"
    export ACFS_FAKE_SUDO="$fake_bin/sudo"
    export ACFS_FAKE_SUDO_LOG="$sudo_log"
    export ACFS_REAL_ID="$real_id"
    export ACFS_REAL_MKDIR="$real_mkdir"
    export ACFS_STATE_FILE="$state_root/state.json"

    cat > "$ACFS_FAKE_MKDIR" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${ACFS_FAKE_SUDO_ACTIVE:-}" != "1" ]]; then
    exit 73
fi
exec "$ACFS_REAL_MKDIR" "$@"
EOF
    chmod +x "$ACFS_FAKE_MKDIR"

    cat > "$ACFS_FAKE_SUDO" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" != "-n" ]]; then
    printf 'missing -n\n' >> "$ACFS_FAKE_SUDO_LOG"
    exit 91
fi
printf '%s\n' "$@" >> "$ACFS_FAKE_SUDO_LOG"
shift
ACFS_FAKE_SUDO_ACTIVE=1 exec "$@"
EOF
    chmod +x "$ACFS_FAKE_SUDO"

    cat > "$ACFS_FAKE_CHOWN" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
    chmod +x "$ACFS_FAKE_CHOWN"

    state_system_binary_path() {
        case "${1:-}" in
            chown) printf '%s\n' "$ACFS_FAKE_CHOWN" ;;
            id) printf '%s\n' "$ACFS_REAL_ID" ;;
            mkdir) printf '%s\n' "$ACFS_FAKE_MKDIR" ;;
            sudo) printf '%s\n' "$ACFS_FAKE_SUDO" ;;
            *) command -v "${1:-}" ;;
        esac
    }

    run state_init
    assert_success

    run test -f "$ACFS_STATE_FILE"
    assert_success
    run grep -Fx -- "$ACFS_FAKE_MKDIR" "$sudo_log"
    assert_success
    run grep -Fx -- "$ACFS_FAKE_CHOWN" "$sudo_log"
    assert_success
}

@test "state: privileged directory fallback source is noninteractive" {
    local state_lib="$PROJECT_ROOT/scripts/lib/state.sh"

    run grep -F '"$sudo_bin" -n "$mkdir_bin" -p "$state_dir"' "$state_lib"
    assert_success
    run grep -F '"$sudo_bin" -n "$chown_bin"' "$state_lib"
    assert_success
}

@test "state: save and load round trip" {
    state_init
    
    local content='{"test": "value"}'
    run state_save "$content"
    assert_success
    
    run state_load
    assert_success
    assert_output --partial '"test": "value"'
}

@test "state: phase lifecycle" {
    state_init
    
    # Start
    run state_phase_start "phase1" "step1"
    assert_success
    
    run state_get ".current_phase"
    assert_output "phase1"
    
    # Complete
    run state_phase_complete "phase1"
    assert_success
    
    run state_is_phase_completed "phase1"
    assert_success # Returns 0 (true in bash)
    
    run state_get ".current_phase"
    assert_output ""
}

@test "state: fail records error" {
    state_init
    state_phase_start "phase1"
    
    run state_phase_fail "phase1" "stepX" "Something blew up"
    assert_success
    
    run state_get ".failed_phase"
    assert_output "phase1"
    
    run state_get ".failed_error"
    assert_output "Something blew up"
}

@test "state: later phase start preserves the prior failure diagnosis" {
    state_init
    state_phase_start "phase1" "first step"
    state_phase_fail "phase1" "broken step" "Something blew up"

    run state_phase_start "phase2" "continuing best-effort work"
    assert_success

    run state_get ".failed_phase"
    assert_output "phase1"
    run state_get ".failed_step"
    assert_output "broken step"
    run state_get ".failed_error"
    assert_output "Something blew up"
}

@test "state: starting a retry preserves failure until the failed work recovers" {
    state_init
    state_phase_start "phase1" "first step"
    state_phase_fail "phase1" "broken step" "Something blew up"

    run state_phase_start "phase1" "retrying"
    assert_success

    run state_get ".failed_phase"
    assert_output "phase1"
    run state_get ".failed_step"
    assert_output "broken step"
    run state_get ".failed_error"
    assert_output "Something blew up"

    run state_phase_complete "phase1"
    assert_failure

    state_step_result "phase1" "broken step" success
    run state_phase_complete "phase1"
    assert_success
    run state_get ".failed_phase"
    assert_output ""
}

@test "state: swallowed mandatory failures block phase completion" {
    state_init
    state_phase_start cli_tools
    state_step_result cli_tools packages failed true 'sudo: a password is required'
    state_step_result cli_tools diagnostics success

    run state_phase_complete cli_tools
    assert_failure
    run state_is_phase_completed cli_tools
    assert_failure
    run state_get '.partial_phases | index("cli_tools") != null'
    assert_output true
    run state_get '.phase_steps.cli_tools.packages.error'
    assert_output 'sudo: a password is required'
    run state_has_required_failures
    assert_success
}

@test "state: a required result that could not be persisted blocks completion" {
    state_init
    state_phase_start cli_tools
    local original_writer
    original_writer="$(declare -f state_write_atomic)"
    state_write_atomic() { return 1; }
    state_step_result cli_tools packages failed true 'sudo denied' || true
    eval "$original_writer"

    state_step_result cli_tools diagnostics success
    run state_phase_complete cli_tools
    assert_failure
    run state_is_phase_completed cli_tools
    assert_failure

    # A fresh attempt can recover once writes and the required work succeed.
    state_phase_start cli_tools
    state_step_result cli_tools packages success
    run state_phase_complete cli_tools
    assert_success
}

@test "state: malformed required-step metadata fails the success guard closed" {
    state_init
    state_update '.phase_steps = "invalid"'
    run state_has_required_failures
    assert_success
}

@test "state: missing jq cannot turn a previous completion into a successful run" {
    state_init
    state_phase_complete cli_tools
    local marker="$BATS_TEST_TMPDIR/phase-executed"
    fixture_phase() { touch "$marker"; }
    command() {
        if [[ "${1:-}" == -v && "${2:-}" == jq ]]; then
            return 1
        fi
        builtin command "$@"
    }
    run run_phase cli_tools CLI fixture_phase
    assert_failure
    [[ ! -e "$marker" ]]
    run state_has_required_failures
    assert_success
}

@test "state: recovering one required step preserves another failure" {
    state_init
    state_phase_start cloud_db
    state_step_result cloud_db package failed true 'package installation failed'
    state_step_result cloud_db service failed true 'service did not start'
    state_step_result cloud_db service success

    run state_get '.failed_step'
    assert_output package
    run state_phase_complete cloud_db
    assert_failure

    state_step_result cloud_db package success
    state_phase_complete cloud_db
    run state_has_required_failures
    assert_failure
}

@test "state: optional failures remain recorded without blocking completion" {
    state_init
    state_phase_start cli_tools
    state_step_result cli_tools required success true
    state_step_result cli_tools optional failed false 'optional unavailable'
    state_phase_complete cli_tools

    run state_is_phase_completed cli_tools
    assert_success
    run state_get '.phase_steps.cli_tools.optional.status'
    assert_output failed
    run state_has_required_failures
    assert_failure
}

@test "state: live verification only reconciles previous attempts" {
    state_init
    state_phase_start cloud_db
    state_step_result cloud_db package failed true 'dependency unavailable'
    state_phase_start cloud_db
    state_step_result cloud_db service failed true 'privileged command denied'

    run state_phase_reconcile cloud_db
    assert_failure
    run state_get '.phase_steps.cloud_db.package.status'
    assert_output failed

    state_step_result cloud_db service success
    state_phase_reconcile cloud_db
    state_phase_complete cloud_db
    run state_get '.phase_steps.cloud_db.package.status'
    assert_output verified
    run state_get '.phase_steps.cloud_db.package.error'
    assert_output 'dependency unavailable'
}

@test "state: interrupted phase invalidates completion and retains running work" {
    state_init
    state_phase_complete languages
    state_phase_start languages
    state_step_result languages runtime running
    state_mark_interrupted

    run state_is_phase_completed languages
    assert_failure
    run state_get '.partial_phases | index("languages") != null'
    assert_output true
    run state_get '.phase_steps.languages.runtime.status'
    assert_output failed
    run state_get '.failed_error'
    assert_output 'Installation interrupted'
    run state_has_required_failures
    assert_success
}

@test "state: legacy completion does not override a failure marker" {
    state_init
    state_update '.completed_phases = ["cli_tools"] | .failed_phase = "cli_tools" | .failed_step = "packages" | .failed_error = "denied"'
    run state_is_phase_completed cli_tools
    assert_failure
    state_phase_start cli_tools
    run state_phase_complete cli_tools
    assert_failure
    state_step_result cli_tools packages success
    state_phase_complete cli_tools
    run state_is_phase_completed cli_tools
    assert_success
}

@test "state: legacy object partial records migrate without losing failures" {
    state_init
    state_update '.completed_phases = ["cli_tools"] | .partial_phases = {cli_tools: {failures: [{step: "packages", error: "denied"}]}, cloud_db: {failures: []}}'
    run state_is_phase_completed cli_tools
    assert_failure
    state_phase_start cli_tools
    run state_get '.phase_steps.cli_tools.packages.error'
    assert_output denied
    run state_phase_complete cli_tools
    assert_failure
    state_step_result cli_tools packages success
    state_phase_complete cli_tools
    jq -e '.partial_phases == ["cloud_db"] and .phase_steps.cli_tools.packages.status == "success"' "$ACFS_STATE_FILE"
}

@test "state: mandatory failure cannot be erased by phase completion" {
    state_init
    state_phase_start cli_tools
    state_phase_fail cli_tools "sudo pacman" "permission denied"
    run state_phase_complete cli_tools
    assert_failure
    run state_is_phase_completed cli_tools
    assert_failure
    run state_get .failed_step
    assert_output "sudo pacman"
    jq -e '.phase_steps.cli_tools["sudo pacman"].error == "permission denied"' "$ACFS_STATE_FILE"
}

@test "state: failures in another phase do not erase partial phase evidence" {
    state_init
    state_phase_start cli_tools
    state_phase_fail cli_tools packages denied
    state_phase_start cloud_db
    state_phase_fail cloud_db postgres denied
    run state_phase_complete cli_tools
    assert_failure
}

@test "state: interrupted attempt invalidates stale completion and retry can recover" {
    state_init
    state_phase_complete cli_tools
    state_phase_start cli_tools
    run state_is_phase_completed cli_tools
    assert_failure
    jq -e '.partial_phases | index("cli_tools") != null' "$ACFS_STATE_FILE"
    state_phase_fail cli_tools dependency missing
    state_phase_start cli_tools
    state_step_result cli_tools dependency success
    state_phase_complete cli_tools
    run state_is_phase_completed cli_tools
    assert_success
    jq -e '.partial_phases == [] and .failed_phase == null' "$ACFS_STATE_FILE"
}

@test "state: interruption after a successful step retains that success" {
    state_init
    state_phase_start finalize
    state_step_result finalize configuration running
    state_step_result finalize configuration success
    state_mark_interrupted
    run state_get '.phase_steps.finalize.configuration.status'
    assert_output success
    run state_get '.partial_phases | index("finalize") != null'
    assert_output true
    run state_has_required_failures
    assert_success
}

@test "state: run_phase rejects swallowed mandatory failure and recovers" {
    state_init
    broken_phase() { state_phase_fail cli_tools "sudo install" denied; return 0; }
    run run_phase cli_tools CLI broken_phase
    assert_failure
    run state_is_phase_completed cli_tools
    assert_failure
    repaired_phase() { state_step_result cli_tools "sudo install" success; }
    run run_phase cli_tools CLI repaired_phase
    assert_success
    run state_is_phase_completed cli_tools
    assert_success
}

@test "state: explicit optional step failure does not dirty the phase" {
    source_lib error_tracking
    state_init
    optional_phase() { try_step_optional optional false || true; }
    run run_phase cli_tools CLI optional_phase
    assert_success
}

@test "state: optional reclassification retains unrelated mandatory failures" {
    state_init
    state_phase_start cli_tools
    state_phase_fail cli_tools packages denied
    state_phase_fail cli_tools optional unavailable
    state_step_optional cli_tools optional
    run state_phase_complete cli_tools
    assert_failure
    jq -e '[.phase_steps.cli_tools[] | select(.required)] | length == 1' "$ACFS_STATE_FILE"
    run state_get '.failed_step'
    assert_output packages
}

@test "state: failed privileged command is partial until dependency recovery" {
    source_lib error_tracking
    state_init
    dependency="$BATS_TEST_TMPDIR/dependency"
    fake_sudo() { [[ -f "$dependency" ]] || return 1; }
    install_phase() {
        set_phase cli_tools CLI
        try_step "sudo package install" fake_sudo || true
    }
    run run_phase cli_tools CLI install_phase
    assert_failure
    run state_is_phase_completed cli_tools
    assert_failure
    touch "$dependency"
    run run_phase cli_tools CLI install_phase
    assert_success
    jq -e '.partial_phases == []' "$ACFS_STATE_FILE"
}

@test "state: module failures cannot hide behind successful phase return" {
    state_init
    declare -a ACFS_MODULE_FAILURES=()
    module_phase() { ACFS_MODULE_FAILURES+=("required module failed verification"); return 0; }
    run run_phase cli_tools CLI module_phase
    assert_failure
    run state_is_phase_completed cli_tools
    assert_failure
}

@test "state: explicit phase skip still overrides stale completion" {
    state_init
    state_phase_complete cli_tools
    state_phase_skip cli_tools
    run state_should_skip_phase cli_tools
    assert_success
}

@test "installer: smoke rejects missing essential tools and required database until repaired" {
    eval "$(sed -n '/^run_smoke_test() {/,/^}/p' "$PROJECT_ROOT/install.sh")"
    eval "$(sed -n '/^acfs_legacy_module_selected() {/,/^}/p' "$PROJECT_ROOT/install.sh")"
    TARGET_USER=tester
    TARGET_HOME="$BATS_TEST_TMPDIR/target"
    ACFS_BIN_DIR="$TARGET_HOME/.local/bin"
    MODE=vibe
    SKIP_POSTGRES=false
    SKIP_VAULT=true
    SKIP_CLOUD=true
    mkdir -p "$ACFS_BIN_DIR" "$TARGET_HOME/.bun/bin" "$TARGET_HOME/.cargo/bin"
    local binary
    for binary in uv claude codex agy agy-locked agy-real onboard; do
        touch "$ACFS_BIN_DIR/$binary"
        chmod +x "$ACFS_BIN_DIR/$binary"
    done
    touch "$TARGET_HOME/.bun/bin/bun" "$TARGET_HOME/.cargo/bin/cargo"
    chmod +x "$TARGET_HOME/.bun/bin/bun" "$TARGET_HOME/.cargo/bin/cargo"
    acfs_early_system_binary_path() { printf /bin/true; }
    acfs_early_getent_passwd_entry() { printf 'tester:x:1000:1000::/home/tester:/bin/zsh'; }
    user_login_shell_configured() { return 0; }
    binary_installed() { return 0; }
    run_as_target() { return 1; }
    acfs_smoke_install_fix_command() { printf repair; }
    missing_cli=true
    missing_db=true
    required_db=true
    acfs_postgres_ready() { [[ "$missing_db" != true ]]; }
    acfs_legacy_module_is_required() { [[ "$required_db" == true ]]; }
    _smoke_run_as_target() {
        if [[ "$1" == 'command -v direnv >/dev/null' && "$missing_cli" == true ]]; then
            return 1
        fi
        return 0
    }
    run run_smoke_test
    assert_failure
    assert_output --partial 'Required CLI missing: direnv'
    assert_output --partial 'PostgreSQL: required server is not functional'
    missing_cli=false
    run run_smoke_test
    assert_failure
    missing_db=false
    run run_smoke_test
    assert_success
    assert_output --partial '15/15 critical passed'
    missing_db=true
    required_db=false
    run run_smoke_test
    assert_success
    assert_output --partial 'PostgreSQL: not running (optional)'
    SKIP_POSTGRES=true
    run run_smoke_test
    assert_success
    assert_output --partial '14/14 critical passed'
}

@test "state: skip logic" {
    state_init

    run state_phase_skip "skipped_phase"
    assert_success

    run state_should_skip_phase "skipped_phase"
    assert_success # Returns 0 (true)

    run state_should_skip_phase "other_phase"
    assert_failure # Returns 1 (false)
}

@test "state: --only dependency closure runs dependency phases" {
    state_init

    # shellcheck source=../../../scripts/generated/manifest_index.sh
    source "$PROJECT_ROOT/scripts/generated/manifest_index.sh"
    ACFS_MANIFEST_INDEX_LOADED=true
    source_lib "install_helpers"

    ONLY_MODULES=("stack.ntm")
    ONLY_PHASES=()
    SKIP_MODULES=()
    NO_DEPS=false

    acfs_resolve_selection || {
        echo "acfs_resolve_selection failed"
        return 1
    }
    [[ " ${ACFS_EFFECTIVE_PLAN[*]} " == *" base.system "* ]] || {
        echo "base.system missing from effective plan"
        return 1
    }
    [[ " ${ACFS_EFFECTIVE_PLAN[*]} " == *" cli.modern "* ]] || {
        echo "cli.modern missing from effective plan"
        return 1
    }
    [[ " ${ACFS_EFFECTIVE_PLAN[*]} " == *" stack.ntm "* ]] || {
        echo "stack.ntm missing from effective plan"
        return 1
    }

    run state_should_skip_phase "user_setup"
    assert_failure

    run state_should_skip_phase "cli_tools"
    assert_failure

    run state_should_skip_phase "stack"
    assert_failure

    run state_should_skip_phase "languages"
    assert_success
}

@test "state: --only-phase dependency closure runs dependency phases" {
    state_init

    # shellcheck source=../../../scripts/generated/manifest_index.sh
    source "$PROJECT_ROOT/scripts/generated/manifest_index.sh"
    ACFS_MANIFEST_INDEX_LOADED=true
    source_lib "install_helpers"

    ONLY_MODULES=()
    ONLY_PHASES=("stack")
    SKIP_MODULES=()
    NO_DEPS=false

    acfs_resolve_selection || {
        echo "acfs_resolve_selection failed"
        return 1
    }
    [[ " ${ACFS_EFFECTIVE_PLAN[*]} " == *" stack.ntm "* ]] || {
        echo "stack.ntm missing from effective plan"
        return 1
    }
    [[ " ${ACFS_EFFECTIVE_PLAN[*]} " == *" lang.bun "* ]] || {
        echo "lang.bun missing from effective plan"
        return 1
    }
    [[ " ${ACFS_EFFECTIVE_PLAN[*]} " == *" agents.claude "* ]] || {
        echo "agents.claude missing from effective plan"
        return 1
    }

    run state_should_skip_phase "user_setup"
    assert_failure

    run state_should_skip_phase "languages"
    assert_failure

    run state_should_skip_phase "agents"
    assert_failure

    run state_should_skip_phase "stack"
    assert_failure
}

@test "state: selected dependency phase reruns even if completed" {
    state_init
    state_phase_complete "cli_tools"

    # shellcheck source=../../../scripts/generated/manifest_index.sh
    source "$PROJECT_ROOT/scripts/generated/manifest_index.sh"
    ACFS_MANIFEST_INDEX_LOADED=true
    source_lib "install_helpers"

    ONLY_MODULES=("stack.ntm")
    ONLY_PHASES=()
    SKIP_MODULES=()
    NO_DEPS=false

    acfs_resolve_selection || {
        echo "acfs_resolve_selection failed"
        return 1
    }

    run state_should_skip_phase "cli_tools"
    assert_failure
}

@test "state: completed phase is skipped only after live verification" {
    state_init
    state_phase_complete "cli_tools"

    # shellcheck source=../../../scripts/generated/manifest_index.sh
    source "$PROJECT_ROOT/scripts/generated/manifest_index.sh"
    ACFS_MANIFEST_INDEX_LOADED=true
    source_lib "install_helpers"

    ONLY_MODULES=()
    ONLY_PHASES=()
    SKIP_MODULES=()
    NO_DEPS=false

    acfs_resolve_selection || {
        echo "acfs_resolve_selection failed"
        return 1
    }

    run state_should_skip_phase "cli_tools"
    assert_failure

    acfs_verify_phase() { [[ "$1" == cli_tools && "$2" == resume ]]; }
    run state_should_skip_phase "cli_tools"
    assert_success

    acfs_verify_phase() { return 1; }
    run state_should_skip_phase "cli_tools"
    assert_failure
}

@test "state: completed shell setup re-enters component checks for an approved account" {
    state_init
    state_phase_complete "shell_setup"
    ONLY_MODULES=()
    ONLY_PHASES=()
    ACFS_EFFECTIVE_PLAN=("shell.zsh" "shell.login" "shell.omz")

    user_login_shell_configured() { printf 'unexpected account probe\n'; }

    run state_should_skip_phase "shell_setup"
    assert_failure
    assert_output ""
}

@test "state: completed shell setup reruns when account verification fails" {
    state_init
    state_phase_complete "shell_setup"
    ONLY_MODULES=()
    ONLY_PHASES=()
    ACFS_EFFECTIVE_PLAN=("shell.zsh" "shell.login" "shell.omz")

    user_login_shell_configured() { return 1; }

    run state_should_skip_phase "shell_setup"
    assert_failure
}

@test "state: unsafe completed shell setup remains skipped for an unrelated subset" {
    state_init
    state_phase_complete "shell_setup"
    ONLY_MODULES=("stack.ntm")
    ONLY_PHASES=()
    ACFS_EFFECTIVE_PLAN=("stack.ntm")
    declare -gA ACFS_MODULE_PHASE=([stack.ntm]=9)

    user_login_shell_configured() { printf 'unexpected account probe\n'; return 1; }

    run state_should_skip_phase "shell_setup"
    assert_success
    assert_output ""
}

@test "state: explicit shell phase skip is preserved on full resume" {
    state_init
    state_phase_complete "shell_setup"
    state_phase_skip "shell_setup"
    ONLY_MODULES=()
    ONLY_PHASES=()
    ACFS_EFFECTIVE_PLAN=("shell.zsh" "shell.login" "shell.omz")

    user_login_shell_configured() { printf 'unexpected account probe\n'; return 1; }

    run state_should_skip_phase "shell_setup"
    assert_success
    assert_output ""
}

@test "state: shell resume re-enters without loading the account library" {
    state_init
    state_phase_complete "shell_setup"
    ONLY_MODULES=()
    ONLY_PHASES=()
    unset -f user_login_shell_configured

    run state_should_skip_phase "shell_setup"
    assert_failure
}

@test "state: update atomic" {
    state_init
    
    run state_update '.new_field = "exists"'
    assert_success
    
    run state_get ".new_field"
    assert_output "exists"
}

@test "state: update with args escapes dynamic values" {
    state_init

    run state_update_with_args '.quoted = $value' --arg value '24.04"; halt'
    assert_success

    run state_get ".quoted"
    assert_output '24.04"; halt'
}

@test "state: nested state_save keeps outer lock held" {
    state_init

    _state_acquire_lock
    state_save '{"nested": "value"}'

    [[ "${_ACFS_STATE_LOCKED:-}" == "true" ]]
    [[ "${_ACFS_STATE_LOCK_DEPTH:-0}" -eq 1 ]]

    _state_release_lock
    [[ "${_ACFS_STATE_LOCKED:-}" == "false" ]]
    [[ "${_ACFS_STATE_LOCK_DEPTH:-0}" -eq 0 ]]

    run state_get ".nested"
    assert_output "value"
}

# Keep these process tests independent of Bats' own subshell and inherited
# descriptors. The optional source override also permits checking that the
# regression fixtures fail against a saved pre-fix library.
run_state_lock_fixture() {
    run timeout 15 env -i PATH="$PATH" HOME="$HOME" \
        TMPDIR="$BATS_TEST_TMPDIR" ACFS_HOME="$BATS_TEST_TMPDIR" \
        ACFS_STATE_FILE="$BATS_TEST_TMPDIR/state.json" \
        ACFS_STATE_LOCK_TIMEOUT=1 \
        bash -eu -c "$1" _ \
        "${ACFS_STATE_LIB_SOURCE:-$PROJECT_ROOT/scripts/lib/state.sh}" \
        "$BATS_TEST_TMPDIR"
}

@test "state: lock ownership ignores an exported library load marker" {
    run_state_lock_fixture '
        export _ACFS_STATE_SH_LOADED=1
        source "$1"

        _state_acquire_lock
        _state_release_lock
        flock -n "$ACFS_STATE_FILE.lock" true
    '
    assert_success
}

@test "state: lock ownership survives repeated source in parent and child" {
    run_state_lock_fixture '
        source "$1"
        _state_acquire_lock
        source "$1"
        _state_acquire_lock
        _state_release_lock

        if flock -n "$ACFS_STATE_FILE.lock" true; then
            echo "Repeated source released the parent state transaction" >&2
            exit 47
        fi
        ( source "$1"; _state_release_lock )
        if flock -n "$ACFS_STATE_FILE.lock" true; then
            echo "Repeated child source released the parent state transaction" >&2
            exit 48
        fi

        _state_release_lock
        flock -n "$ACFS_STATE_FILE.lock" true
    '
    assert_success
}

@test "state: lock ownership ignores an inherited installer descriptor" {
    run_state_lock_fixture '
        exec 199>"$2/install.lock"
        flock -n 199
        export ACFS_LOCK_FD=199
        export _ACFS_STATE_LOCK_FILE="$ACFS_STATE_FILE.lock"
        source "$1"

        _state_acquire_lock
        _state_release_lock

        if flock -n "$2/install.lock" true; then
            echo "State release unlocked the installer descriptor" >&2
            exit 41
        fi
        flock -u 199
        flock -n "$2/install.lock" true
    '
    assert_success
}

@test "state: lock ownership rejects forged inherited ownership metadata" {
    run_state_lock_fixture '
        exec 199>"$ACFS_STATE_FILE.lock"
        flock -n 199
        export _ACFS_STATE_LOCKED=true
        export _ACFS_STATE_LOCK_DEPTH=1
        export _ACFS_STATE_LOCK_FILE="$ACFS_STATE_FILE.lock"
        export _ACFS_STATE_LOCK_OWNER_PID="$BASHPID"
        source "$1"

        if _state_acquire_lock; then
            _state_release_lock
            echo "Inherited metadata bypassed a contended state lock" >&2
            exit 42
        fi
        if flock -n "$ACFS_STATE_FILE.lock" true; then
            echo "Failed state acquisition released another owner" >&2
            exit 43
        fi
        flock -u 199
        _state_acquire_lock
        _state_release_lock
    '
    assert_success
}

@test "state: lock ownership prevents a child from unlocking its parent" {
    run_state_lock_fixture '
        source "$1"
        _state_acquire_lock
        ( _state_release_lock )

        if flock -n "$ACFS_STATE_FILE.lock" true; then
            echo "Child release unlocked the parent state transaction" >&2
            exit 44
        fi
        _state_release_lock
        flock -n "$ACFS_STATE_FILE.lock" true
    '
    assert_success
}

@test "state: lock ownership makes child acquisition wait for its parent" {
    run_state_lock_fixture '
        source "$1"
        _state_acquire_lock

        if ( _state_acquire_lock ); then
            echo "Child acquired a state lock still owned by its parent" >&2
            exit 45
        fi
        if flock -n "$ACFS_STATE_FILE.lock" true; then
            echo "Timed out child released the parent state transaction" >&2
            exit 46
        fi

        _state_release_lock
        ( _state_acquire_lock; _state_release_lock )
        flock -n "$ACFS_STATE_FILE.lock" true
    '
    assert_success
}

@test "state: lock ownership serializes inherited parallel state updates" {
    run_state_lock_fixture '
        source "$1"
        fixture="$2"
        export ACFS_STATE_LOCK_TIMEOUT=5
        printf "{\"counter\":0}\n" > "$ACFS_STATE_FILE"
        first=""
        second=""
        cleanup_workers() {
            _state_release_lock
            : > "$fixture/released"
            if [[ -n "$first" ]]; then
                kill "$first" 2>/dev/null || true
                wait "$first" 2>/dev/null || true
            fi
            if [[ -n "$second" ]]; then
                kill "$second" 2>/dev/null || true
                wait "$second" 2>/dev/null || true
            fi
        }
        trap cleanup_workers EXIT
        _state_acquire_lock

        # Observe real flock calls without changing their result. A child with
        # inherited ownership must reach this wait before reading the state.
        flock() {
            if [[ "${1:-}" == "-w" && -n "${worker:-}" ]]; then
                : > "$fixture/$worker.waiting"
            fi
            command flock "$@"
        }
        # A broken inherited fast path reaches jq while the parent still owns
        # the lock. Hold both old snapshots until the parent has observed them.
        jq() {
            if [[ "$*" == ".counter += 1" ]]; then
                : > "$fixture/$worker.reading"
                while [[ ! -e "$fixture/released" ]]; do sleep 0.01; done
            fi
            command jq "$@"
        }
        ( worker=one; state_update ".counter += 1" ) &
        first=$!
        ( worker=two; state_update ".counter += 1" ) &
        second=$!

        for worker in one two; do
            for ((attempt=0; attempt<300; attempt++)); do
                if [[ -e "$fixture/$worker.waiting" || -e "$fixture/$worker.reading" ]]; then
                    break
                fi
                sleep 0.01
            done
            [[ -e "$fixture/$worker.waiting" || -e "$fixture/$worker.reading" ]]
        done
        blocked=true
        if [[ -e "$fixture/one.reading" || -e "$fixture/two.reading" ]]; then
            blocked=false
        fi

        _state_release_lock
        : > "$fixture/released"
        wait "$first"
        first=""
        wait "$second"
        second=""

        counter=$(command jq -r .counter "$ACFS_STATE_FILE")
        printf "blocked_before_release=%s counter=%s\n" "$blocked" "$counter"
        [[ "$blocked" == true && "$counter" == 2 ]]
        flock -n "$ACFS_STATE_FILE.lock" true
    '
    assert_success
    assert_output "blocked_before_release=true counter=2"
}

@test "state: first lock acquisition succeeds under nounset" {
    local state_root
    state_root=$(create_temp_dir)

    run env -i PATH="$PATH" HOME="$state_root/home" ACFS_HOME="$state_root/acfs" ACFS_STATE_FILE="$state_root/acfs/state.json" bash -u -c '
        mkdir -p "$HOME" "$ACFS_HOME"
        source "$1"
        _state_acquire_lock
        printf "locked=%s fd=%s\n" "${_ACFS_STATE_LOCKED:-}" "${ACFS_LOCK_FD:-}"
        _state_release_lock
    ' _ "$PROJECT_ROOT/scripts/lib/state.sh"
    assert_success
    assert_output --partial "locked=true fd="
}

@test "state: ubuntu upgrade helpers escape dynamic values" {
    state_init

    run state_upgrade_init '24.04"; halt' '25.10"; halt' '["25.04","25.10"]'
    assert_success

    run state_upgrade_start '24.04"; from' '25.04"; to'
    assert_success

    run state_upgrade_complete '25.04"; done'
    assert_success

    run state_get ".ubuntu_upgrade.original_version"
    assert_output '24.04"; halt'

    run state_get ".ubuntu_upgrade.target_version"
    assert_output '25.10"; halt'

    run state_get ".ubuntu_upgrade.completed_upgrades[0].from"
    assert_output '24.04"; from'

    run state_get ".ubuntu_upgrade.completed_upgrades[0].to"
    assert_output '25.04"; done'

    run state_upgrade_needs_reboot
    assert_success

    run state_get ".ubuntu_upgrade.resume_after_reboot"
    assert_output "true"

    run state_upgrade_resumed
    assert_success

    run state_get ".ubuntu_upgrade.current_stage"
    assert_output "resumed"

    run state_get ".ubuntu_upgrade.needs_reboot | tostring"
    assert_output "false"

    run state_get ".ubuntu_upgrade.resume_after_reboot | tostring"
    assert_output "false"

    run state_upgrade_set_error 'failed "quoted" upgrade'
    assert_success

    run state_get ".ubuntu_upgrade.last_error"
    assert_output 'failed "quoted" upgrade'

    run state_upgrade_mark_complete
    assert_success

    run state_get ".ubuntu_upgrade.current_stage"
    assert_output "completed"

    run state_get ".ubuntu_upgrade.resume_after_reboot | tostring"
    assert_output "false"

    run state_get ".ubuntu_upgrade.current_upgrade"
    assert_output ""

    run state_get ".ubuntu_upgrade.completed_at"
    assert_success
    [[ -n "$output" ]]
}

@test "state: get file prefers passwd-resolved target home when ACFS_HOME unset" {
    local stub_home
    stub_home=$(create_temp_dir)

    unset ACFS_HOME
    unset ACFS_STATE_FILE
    export TARGET_USER="dummy"
    export TARGET_HOME=""
    export HOME="/tmp/not-the-target-home"

    state_getent_passwd_entry() {
        if [[ "${1:-}" == "dummy" ]]; then
            printf "dummy:x:1000:1000::%s:/bin/bash\n" "$stub_home"
            return 0
        fi
        return 1
    }

    run state_get_file
    assert_success
    assert_output "$stub_home/.acfs/state.json"
}

@test "state: init uses passwd-resolved target home when ACFS_HOME unset" {
    local stub_home
    stub_home=$(create_temp_dir)

    unset ACFS_HOME
    unset ACFS_STATE_FILE
    export TARGET_USER="dummy"
    export TARGET_HOME=""
    export HOME="/tmp/not-the-target-home"

    state_getent_passwd_entry() {
        if [[ "${1:-}" == "dummy" ]]; then
            printf "dummy:x:1000:1000::%s:/bin/bash\n" "$stub_home"
            return 0
        fi
        return 1
    }

    run state_init
    assert_success

    run test -f "$stub_home/.acfs/state.json"
    assert_success
}

@test "state: init persists resolved target home when TARGET_HOME unset" {
    local stub_home
    stub_home=$(create_temp_dir)

    unset ACFS_HOME
    unset ACFS_STATE_FILE
    export TARGET_USER="dummy"
    export TARGET_HOME=""
    export HOME="/tmp/not-the-target-home"

    state_getent_passwd_entry() {
        if [[ "${1:-}" == "dummy" ]]; then
            printf "dummy:x:1000:1000::%s:/bin/bash\n" "$stub_home"
            return 0
        fi
        return 1
    }

    run state_init
    assert_success

    run state_get ".target_home"
    assert_success
    assert_output "$stub_home"
}

@test "state: backup and remove accepts passwd-resolved user state path" {
    local stub_home
    stub_home=$(create_temp_dir)

    unset ACFS_HOME
    unset ACFS_STATE_FILE
    export TARGET_USER="dummy"
    export TARGET_HOME=""
    export HOME="/tmp/not-the-target-home"

    state_getent_passwd_entry() {
        if [[ "${1:-}" == "dummy" ]]; then
            printf "dummy:x:1000:1000::%s:/bin/bash\n" "$stub_home"
            return 0
        fi
        return 1
    }

    mkdir -p "$stub_home/.acfs"
    printf '{"schema_version":3}\n' > "$stub_home/.acfs/state.json"

    run state_backup_and_remove
    assert_success

    run test ! -f "$stub_home/.acfs/state.json"
    assert_success

    run bash -lc "shopt -s nullglob; files=(\"$stub_home/.acfs/state.json.backup.\"*); [[ \${#files[@]} -eq 1 ]]"
    assert_success
}

@test "state: resolve target home rejects invalid fallback usernames" {
    unset ACFS_HOME
    unset ACFS_STATE_FILE
    export TARGET_HOME=""
    export TARGET_USER="../bad-user"
    export HOME="/"

    getent() {
        return 2
    }

    run state_resolve_target_home
    assert_failure
}

@test "state: resolve target home accepts dotted usernames but fails closed when unresolved" {
    unset ACFS_HOME
    unset ACFS_STATE_FILE
    export TARGET_HOME=""
    export TARGET_USER="john.doe"
    export HOME="/"

    getent() {
        return 2
    }

    run state_resolve_target_home
    assert_failure
}

@test "state: resolve target home prefers target user passwd home over stale TARGET_HOME" {
    local stale_home
    local passwd_home
    stale_home="$(create_temp_dir)"
    passwd_home="$(create_temp_dir)"

    unset ACFS_HOME
    unset ACFS_STATE_FILE
    export TARGET_HOME="$stale_home"
    export TARGET_USER="targetuser"
    export HOME="$stale_home"

    state_resolve_current_user() {
        printf 'calleruser\n'
    }

    state_getent_passwd_entry() {
        if [[ "${1:-}" == "targetuser" ]]; then
            printf 'targetuser:x:1000:1000::%s:/bin/bash\n' "$passwd_home"
            return 0
        fi
        return 1
    }

    run state_resolve_target_home
    assert_success
    assert_output "$passwd_home"
}

@test "state: resolve target home rejects invalid TARGET_USER before TARGET_HOME" {
    local target_home
    target_home="$(create_temp_dir)"

    unset ACFS_HOME
    unset ACFS_STATE_FILE
    export TARGET_HOME="$target_home"
    export TARGET_USER="../bad-user"
    export HOME="$target_home"

    run state_resolve_target_home
    assert_failure
}

@test "state: resolve target home fails closed for unresolved target with stale TARGET_HOME" {
    local stale_home
    stale_home="$(create_temp_dir)"

    unset ACFS_HOME
    unset ACFS_STATE_FILE
    export TARGET_HOME="$stale_home"
    export TARGET_USER="missinguser"
    export HOME="$stale_home"

    state_resolve_current_user() {
        printf 'calleruser\n'
    }

    state_getent_passwd_entry() {
        return 1
    }

    run state_resolve_target_home
    assert_failure
}

@test "state.sh: ownership target-home probes are best-effort under set -e" {
    run grep -n 'target_home="$(state_resolve_target_home)"' "$PROJECT_ROOT/scripts/lib/state.sh"
    assert_failure
}
