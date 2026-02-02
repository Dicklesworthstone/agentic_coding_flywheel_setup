#!/usr/bin/env bash
# ============================================================
# ACFS newproj TUI Wizard - AGENTS.md Preview Screen
# Shows preview of generated AGENTS.md content
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_SCREEN_AGENTS_PREVIEW_LOADED:-}" ]]; then
    return 0
fi
_ACFS_SCREEN_AGENTS_PREVIEW_LOADED=1

# ============================================================
# Screen: AGENTS.md Preview
# ============================================================

# Screen metadata
SCREEN_AGENTS_PREVIEW_ID="agents_preview"
SCREEN_AGENTS_PREVIEW_TITLE="AGENTS.md Preview"
SCREEN_AGENTS_PREVIEW_STEP=6
SCREEN_AGENTS_PREVIEW_NEXT="confirmation"
SCREEN_AGENTS_PREVIEW_PREV="features"

# Generate preview content based on current state
generate_preview_content() {
    local project_name
    project_name=$(state_get "project_name")

    local tech_stack
    tech_stack=$(state_get "tech_stack")

    # Convert tech_stack string to array
    local tech_array=()
    for tech in $tech_stack; do
        case "$tech" in
            nodejs) tech_array+=("nodejs") ;;
            python) tech_array+=("python") ;;
            rust) tech_array+=("rust") ;;
            go) tech_array+=("go") ;;
            ruby) tech_array+=("ruby") ;;
            java) tech_array+=("java-maven") ;;
            php) tech_array+=("php") ;;
            elixir) tech_array+=("elixir") ;;
            docker) tech_array+=("docker") ;;
        esac
    done

    # Set generation flags from state
    export AGENTS_ENABLE_BR=$(state_get "enable_br")
    export AGENTS_ENABLE_CONSOLE="false"

    # Generate content using newproj_agents.sh
    generate_agents_md "$project_name" "${tech_array[@]}"
}

# Get preview sections summary
get_preview_summary() {
    local project_name
    project_name=$(state_get "project_name")

    local tech_stack
    tech_stack=$(state_get "tech_stack")

    # Convert tech_stack string to array
    local tech_array=()
    for tech in $tech_stack; do
        case "$tech" in
            nodejs) tech_array+=("nodejs") ;;
            python) tech_array+=("python") ;;
            rust) tech_array+=("rust") ;;
            go) tech_array+=("go") ;;
            ruby) tech_array+=("ruby") ;;
            java) tech_array+=("java-maven") ;;
            php) tech_array+=("php") ;;
            elixir) tech_array+=("elixir") ;;
            docker) tech_array+=("docker") ;;
        esac
    done

    # Set generation flags from state
    export AGENTS_ENABLE_BR=$(state_get "enable_br")
    export AGENTS_ENABLE_CONSOLE="false"

    preview_agents_md "$project_name" "${tech_array[@]}"
}

# Render the agents preview screen
render_agents_preview_screen() {
    render_screen_header "AGENTS.md Preview" "$SCREEN_AGENTS_PREVIEW_STEP" 9

    # Check if AGENTS.md is enabled
    local agents_enabled
    agents_enabled=$(state_get "enable_agents")

    if [[ "$agents_enabled" != "true" ]]; then
        echo -e "${TUI_WARNING}AGENTS.md generation is disabled.${TUI_NC}"
        echo ""
        echo "No AGENTS.md file will be created for this project."
        echo ""
        echo "Press Enter to continue, or press b to go back and enable it."
        return
    fi

    echo "The following AGENTS.md will be generated:"
    echo ""

    # Show section summary
    get_preview_summary

    echo ""
    draw_line 50

    echo ""
    echo "Options:"
    echo "  [Enter]     Accept and continue"
    echo "  [v]         View full content"
    echo "  [e]         Edit in $EDITOR"
    echo "  [b/Esc]     Go back"
}

# View full AGENTS.md content
view_full_content() {
    local content
    content=$(generate_preview_content)

    if [[ "$GUM_AVAILABLE" == "true" && "$GLOW_AVAILABLE" == "true" ]]; then
        # Use gum pager with glow for markdown rendering
        echo "$content" | glow - | gum pager
    elif [[ "$GUM_AVAILABLE" == "true" ]]; then
        # Use gum pager
        echo "$content" | gum pager
    else
        # Use less or fallback
        if command -v less &>/dev/null; then
            echo "$content" | less
        else
            echo "$content" | more
        fi
    fi
}

# Edit AGENTS.md content in editor
edit_content() {
    local content
    content=$(generate_preview_content)

    # Create temp file
    # Use TMPDIR if set, otherwise /tmp. Use mktemp to create a safe file.
    local tmp_dir="${TMPDIR:-/tmp}"
    local tmpfile
    tmpfile=$(mktemp "${tmp_dir}/agents_md_preview.XXXXXX")
    # Rename to add .md extension for syntax highlighting (atomic rename is not strictly required here as it's a temp file)
    mv "$tmpfile" "${tmpfile}.md"
    tmpfile="${tmpfile}.md"

    echo "$content" > "$tmpfile"

    # Open in editor
    local editor="${EDITOR:-vim}"
    local -a editor_cmd=()
    IFS=' ' read -r -a editor_cmd <<< "$editor"
    if [[ ${#editor_cmd[@]} -eq 0 ]]; then
        editor_cmd=("vim")
    fi

    if command -v "${editor_cmd[0]}" &>/dev/null; then
        "${editor_cmd[@]}" "$tmpfile"

        # Read back edited content
        if [[ -f "$tmpfile" ]]; then
            local edited_content
            edited_content=$(cat "$tmpfile")

            # Store for later use
            state_set "agents_md_custom" "$edited_content"
            rm -f "$tmpfile"
            return 0
        fi
    else
        echo -e "${TUI_ERROR}Editor '${editor_cmd[0]}' not found${TUI_NC}"
        rm -f "$tmpfile"
        return 1
    fi
}

# Handle input for agents preview screen
handle_agents_preview_input() {
    while true; do
        render_agents_preview_screen

        local key
        read -rsn1 key

        case "$key" in
            '')
                # Enter - continue
                log_input "agents_preview" "accept"
                echo "$SCREEN_AGENTS_PREVIEW_NEXT"
                return 0
                ;;
            'v'|'V')
                # View full content
                log_input "agents_preview" "view"
                view_full_content
                ;;
            'e'|'E')
                # Edit content
                log_input "agents_preview" "edit"
                if edit_content; then
                    echo -e "${TUI_SUCCESS}Content saved${TUI_NC}"
                    sleep 1
                fi
                ;;
            'b'|'B')
                # Go back
                log_input "agents_preview" "back"
                return 1
                ;;
            $'\e')
                # Escape - check for escape sequence
                read -rsn2 -t 0.1 escape_seq || true
                if [[ -z "$escape_seq" ]]; then
                    # Plain escape - go back
                    log_input "agents_preview" "escape_back"
                    return 1
                fi
                ;;
        esac
    done
}

# Run the agents preview screen
run_agents_preview_screen() {
    log_screen "ENTER" "agents_preview"

    local next
    next=$(handle_agents_preview_input)
    local result=$?

    if [[ $result -eq 0 ]] && [[ -n "$next" ]]; then
        navigate_forward "$next"
        return 0
    else
        navigate_back
        return 0
    fi
}
