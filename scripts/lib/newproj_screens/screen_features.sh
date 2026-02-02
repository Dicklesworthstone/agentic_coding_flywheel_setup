#!/usr/bin/env bash
# ============================================================
# ACFS newproj TUI Wizard - Features Screen
# Multi-select for optional project features
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_SCREEN_FEATURES_LOADED:-}" ]]; then
    return 0
fi
_ACFS_SCREEN_FEATURES_LOADED=1

# ============================================================
# Screen: Features
# ============================================================

# Screen metadata
SCREEN_FEATURES_ID="features"
SCREEN_FEATURES_TITLE="Features"
SCREEN_FEATURES_STEP=5
SCREEN_FEATURES_NEXT="agents_preview"
SCREEN_FEATURES_PREV="tech_stack"

# Available features with descriptions
declare -ga FEATURE_OPTIONS=(
    "br:Beads issue tracking (br):Track work with dependencies and smart prioritization"
    "claude:Claude Code settings:Project-specific Claude Code configuration"
    "agents:AGENTS.md template:Instructions for AI coding assistants"
    "ubsignore:UBS ignore patterns:Configure Ultimate Bug Scanner exclusions"
)

# Get feature state key
get_feature_key() {
    local id="$1"
    echo "enable_$id"
}

# Render the features screen
render_features_screen() {
    render_screen_header "Select Project Features" "$SCREEN_FEATURES_STEP" 9

    echo "Which features would you like to include?"
    echo ""

    local i=1
    for opt in "${FEATURE_OPTIONS[@]}"; do
        local id="${opt%%:*}"
        local rest="${opt#*:}"
        local name="${rest%%:*}"
        local desc="${rest#*:}"

        local key
        key=$(get_feature_key "$id")
        local enabled
        enabled=$(state_get "$key")

        local checkbox
        local color=""

        if [[ "$enabled" == "true" ]]; then
            if [[ "$TERM_HAS_UNICODE" == "true" ]]; then
                checkbox="[${TUI_SUCCESS}${BOX_CHECK}${TUI_NC}]"
            else
                checkbox="[x]"
            fi
            color="$TUI_PRIMARY"
        else
            checkbox="[ ]"
        fi

        echo -e "  $i) $checkbox ${color}$name${TUI_NC}"
        echo -e "     ${TUI_GRAY}$desc${TUI_NC}"
        echo ""
        ((i++))
    done

    echo -e "${TUI_GRAY}Enter numbers to toggle (e.g., 1 3), 'all', 'none', or press Enter when done${TUI_NC}"
}

# Toggle a feature
toggle_feature() {
    local id="$1"
    local key
    key=$(get_feature_key "$id")

    local current
    current=$(state_get "$key")

    if [[ "$current" == "true" ]]; then
        state_set "$key" "false"
    else
        state_set "$key" "true"
    fi
}

# Handle input for features screen
handle_features_input() {
    while true; do
        render_features_screen

        local input=""

        if [[ "$GUM_AVAILABLE" == "true" && "$TERM_HAS_COLOR" == "true" ]]; then
            # Build options list for gum
            local options=()
            local preselected=()

            for opt in "${FEATURE_OPTIONS[@]}"; do
                local id="${opt%%:*}"
                local rest="${opt#*:}"
                local name="${rest%%:*}"

                options+=("$name")

                local key
                key=$(get_feature_key "$id")
                if [[ "$(state_get "$key")" == "true" ]]; then
                    preselected+=("$name")
                fi
            done

            local gum_selected
            gum_selected=$(gum choose --no-limit \
                --cursor.foreground "#cba6f7" \
                --selected.foreground "#a6e3a1" \
                --header "Select features (Space to toggle, Enter to confirm)" \
                "${options[@]}" 2>/dev/null) || {
                # User cancelled
                return 1
            }

            # Set all to false first
            for opt in "${FEATURE_OPTIONS[@]}"; do
                local id="${opt%%:*}"
                local key
                key=$(get_feature_key "$id")
                state_set "$key" "false"
            done

            # Then enable selected
            while IFS= read -r line; do
                for opt in "${FEATURE_OPTIONS[@]}"; do
                    local id="${opt%%:*}"
                    local rest="${opt#*:}"
                    local name="${rest%%:*}"
                    if [[ "$name" == "$line" ]]; then
                        local key
                        key=$(get_feature_key "$id")
                        state_set "$key" "true"
                    fi
                done
            done <<< "$gum_selected"

            log_input "features" "$gum_selected"
            echo "$SCREEN_FEATURES_NEXT"
            return 0
        else
            # Fallback to text input
            echo ""
            read -r -p "Toggle options (or Enter to continue): " input

            case "$input" in
                '')
                    # Done - continue
                    log_input "features" "confirmed"
                    echo "$SCREEN_FEATURES_NEXT"
                    return 0
                    ;;
                'all')
                    for opt in "${FEATURE_OPTIONS[@]}"; do
                        local id="${opt%%:*}"
                        local key
                        key=$(get_feature_key "$id")
                        state_set "$key" "true"
                    done
                    ;;
                'none')
                    for opt in "${FEATURE_OPTIONS[@]}"; do
                        local id="${opt%%:*}"
                        local key
                        key=$(get_feature_key "$id")
                        state_set "$key" "false"
                    done
                    ;;
                'back'|'b')
                    return 1
                    ;;
                *)
                    # Toggle by numbers
                    for num in $input; do
                        if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -ge 1 ]] && [[ "$num" -le ${#FEATURE_OPTIONS[@]} ]]; then
                            local opt="${FEATURE_OPTIONS[$((num - 1))]}"
                            local id="${opt%%:*}"
                            toggle_feature "$id"
                        fi
                    done
                    ;;
            esac
        fi
    done
}

# Run the features screen
run_features_screen() {
    log_screen "ENTER" "features"

    local next
    next=$(handle_features_input)
    local result=$?

    if [[ $result -eq 0 ]] && [[ -n "$next" ]]; then
        navigate_forward "$next"
        return 0
    else
        navigate_back
        return 0
    fi
}
