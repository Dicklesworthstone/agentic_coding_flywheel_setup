#!/usr/bin/env bash
# ============================================================
# ACFS newproj TUI Wizard - Tech Stack Screen
# Multi-select for project tech stack
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_SCREEN_TECH_STACK_LOADED:-}" ]]; then
    return 0
fi
_ACFS_SCREEN_TECH_STACK_LOADED=1

# ============================================================
# Screen: Tech Stack
# ============================================================

# Screen metadata
SCREEN_TECH_STACK_ID="tech_stack"
SCREEN_TECH_STACK_TITLE="Tech Stack"
SCREEN_TECH_STACK_STEP=4
SCREEN_TECH_STACK_NEXT="features"
SCREEN_TECH_STACK_PREV="directory"

# Available tech stack options
declare -ga TECH_STACK_OPTIONS=(
    "nodejs:Node.js / JavaScript / TypeScript"
    "python:Python"
    "rust:Rust"
    "go:Go"
    "ruby:Ruby"
    "java:Java (Maven/Gradle)"
    "php:PHP"
    "elixir:Elixir"
    "docker:Docker / Containers"
    "other:Other / None"
)

# Get display name for tech stack
get_tech_option_display() {
    local key="$1"
    for opt in "${TECH_STACK_OPTIONS[@]}"; do
        local opt_key="${opt%%:*}"
        local opt_name="${opt#*:}"
        if [[ "$opt_key" == "$key" ]]; then
            echo "$opt_name"
            return
        fi
    done
    echo "$key"
}

# Detect tech stack from project directory (if exists) or current directory
detect_initial_tech_stack() {
    local dir="${1:-$(pwd)}"

    # Only detect if directory exists
    if [[ ! -d "$dir" ]]; then
        echo ""
        return
    fi

    # Use the detect_tech_stack function from newproj_detect.sh
    local detected
    detected=$(detect_tech_stack "$dir" 2>/dev/null)

    # Map detected tech to our option keys
    local selected=()
    for tech in $detected; do
        case "$tech" in
            nodejs|typescript|nextjs|nuxt|svelte|astro|vite)
                [[ ! " ${selected[*]} " =~ " nodejs " ]] && selected+=("nodejs")
                ;;
            python|python-legacy)
                [[ ! " ${selected[*]} " =~ " python " ]] && selected+=("python")
                ;;
            rust)
                selected+=("rust")
                ;;
            go)
                selected+=("go")
                ;;
            ruby)
                selected+=("ruby")
                ;;
            java|java-maven|java-gradle)
                [[ ! " ${selected[*]} " =~ " java " ]] && selected+=("java")
                ;;
            php)
                selected+=("php")
                ;;
            elixir)
                selected+=("elixir")
                ;;
            docker|docker-compose)
                [[ ! " ${selected[*]} " =~ " docker " ]] && selected+=("docker")
                ;;
        esac
    done

    echo "${selected[*]}"
}

# Render the tech stack screen
render_tech_stack_screen() {
    local selected="${1:-}"

    render_screen_header "Select Tech Stack" "$SCREEN_TECH_STACK_STEP" 9

    echo "What technologies will this project use?"
    echo "This helps generate appropriate AGENTS.md sections."
    echo ""

    # Show detection status
    local detected
    detected=$(state_get "detected_tech")
    if [[ -n "$detected" ]]; then
        local detected_labels=()
        local tech
        for tech in $detected; do
            detected_labels+=("$(get_tech_option_display "$tech")")
        done
        local detected_display=""
        for tech in "${detected_labels[@]}"; do
            if [[ -z "$detected_display" ]]; then
                detected_display="$tech"
            else
                detected_display+=", $tech"
            fi
        done
        echo -e "${TUI_SUCCESS}${BOX_CHECK} Auto-detected: ${detected_display}${TUI_NC}"
        echo ""
    fi

    # Show options with current selection
    echo "Available options:"
    echo ""

    local i=1
    for opt in "${TECH_STACK_OPTIONS[@]}"; do
        local key="${opt%%:*}"
        local name="${opt#*:}"

        local checkbox="[ ]"
        local color=""
        if [[ " $selected " =~ " $key " ]]; then
            if [[ "$TERM_HAS_UNICODE" == "true" ]]; then
                checkbox="[${TUI_SUCCESS}${BOX_CHECK}${TUI_NC}]"
            else
                checkbox="[x]"
            fi
            color="$TUI_PRIMARY"
        fi

        echo -e "  $i) $checkbox ${color}$name${TUI_NC}"
        ((i++))
    done

    echo ""
    echo -e "${TUI_GRAY}Enter numbers to toggle (e.g., 1 3 5), 'all', 'none', or press Enter when done${TUI_NC}"
}

# Parse selected options from state
parse_selected_options() {
    local tech_stack
    tech_stack=$(state_get "tech_stack")
    echo "$tech_stack"
}

# Toggle an option in the selection
toggle_option() {
    local key="$1"
    local current="$2"

    if [[ " $current " =~ " $key " ]]; then
        # Remove
        current="${current// $key / }"
        current="${current//$key /}"
        current="${current// $key/}"
        current="${current/$key/}"
        current=$(echo "$current" | xargs)  # Trim whitespace
    else
        # Add
        current="$current $key"
        current=$(echo "$current" | xargs)
    fi

    echo "$current"
}

# Handle input for tech stack screen
handle_tech_stack_input() {
    # Get current selection or detect
    local selected
    selected=$(state_get "tech_stack")

    if [[ -z "$selected" ]]; then
        # Try to detect from current directory
        selected=$(detect_initial_tech_stack)
        if [[ -n "$selected" ]]; then
            state_set "detected_tech" "$selected"
        fi
    fi

    while true; do
        # Redirect render output to /dev/tty so it displays even when
        # this function runs inside a $() capture (issue #214)
        render_tech_stack_screen "$selected" > /dev/tty

        local input=""
        if [[ "$GUM_AVAILABLE" == "true" && "$TERM_HAS_COLOR" == "true" ]]; then
            # Use gum for multi-select
            local options=()
            local preselected=()

            for opt in "${TECH_STACK_OPTIONS[@]}"; do
                local key="${opt%%:*}"
                local name="${opt#*:}"
                options+=("$name")
                if [[ " $selected " =~ " $key " ]]; then
                    preselected+=("$name")
                fi
            done

            local gum_selected
            gum_selected=$(gum choose --no-limit \
                --cursor.foreground "#cba6f7" \
                --selected.foreground "#a6e3a1" \
                --header "Select technologies (Space to toggle, Enter to confirm)" \
                "${options[@]}" 2>/dev/null) || {
                # User cancelled
                echo ""
                return 1
            }

            # Map back to keys
            selected=""
            while IFS= read -r line; do
                for opt in "${TECH_STACK_OPTIONS[@]}"; do
                    local key="${opt%%:*}"
                    local name="${opt#*:}"
                    if [[ "$name" == "$line" ]]; then
                        selected+="$key "
                    fi
                done
            done <<< "$gum_selected"
            selected=$(echo "$selected" | xargs)

            state_set "tech_stack" "$selected"
            log_input "tech_stack" "$selected"

            echo "$SCREEN_TECH_STACK_NEXT"
            return 0
        else
            # Fallback to text input — prompts go to /dev/tty (issue #214)
            echo "" > /dev/tty
            echo -n "Toggle options (or Enter to continue): " > /dev/tty
            read -r input < /dev/tty || true

            case "$input" in
                '')
                    # Done - continue
                    state_set "tech_stack" "$selected"
                    log_input "tech_stack" "$selected"
                    echo "$SCREEN_TECH_STACK_NEXT"
                    return 0
                    ;;
                'all')
                    # Select all except 'other'
                    selected=""
                    for opt in "${TECH_STACK_OPTIONS[@]}"; do
                        local key="${opt%%:*}"
                        if [[ "$key" != "other" ]]; then
                            selected+="$key "
                        fi
                    done
                    selected=$(echo "$selected" | xargs)
                    ;;
                'none')
                    # Clear selection
                    selected=""
                    ;;
                'back'|'b')
                    echo ""
                    return 1
                    ;;
                *)
                    # Toggle by numbers
                    for num in $input; do
                        if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -ge 1 ]] && [[ "$num" -le ${#TECH_STACK_OPTIONS[@]} ]]; then
                            local opt="${TECH_STACK_OPTIONS[$((num - 1))]}"
                            local key="${opt%%:*}"
                            selected=$(toggle_option "$key" "$selected")
                        fi
                    done
                    ;;
            esac
        fi
    done
}

# Run the tech stack screen
run_tech_stack_screen() {
    log_screen "ENTER" "tech_stack"

    local next
    next=$(handle_tech_stack_input)
    local result=$?

    if [[ $result -eq 0 ]] && [[ -n "$next" ]]; then
        navigate_forward "$next"
        return 0
    else
        navigate_back
        return 0
    fi
}
