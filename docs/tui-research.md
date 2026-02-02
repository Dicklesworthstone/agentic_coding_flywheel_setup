# TUI Research Findings

> Research for bead 9dqi: Research onboard TUI implementation patterns
> Researcher: BrightWolf (claude-code, opus-4.5)
> Date: 2026-01-07

## Executive Summary

The existing `packages/onboard/onboard.sh` provides an excellent, production-ready TUI implementation that we should model the newproj wizard after. Key decision: **Use gum with pure bash fallback**, consistent with existing ACFS patterns.

---

## Onboard Analysis

### Structure
- **Location**: `packages/onboard/onboard.sh` (~1350 lines)
- **State file**: `$HOME/.acfs/onboard_progress.json`
- **Lessons dir**: `$HOME/.acfs/onboard/lessons/`

### TUI Library Used
- **Primary**: [gum](https://github.com/charmbracelet/gum) (Charmbracelet)
- **Fallback**: Pure bash with ANSI escape codes
- **Detection**: `command -v gum &>/dev/null`

### Screen Lifecycle Pattern
```bash
# Typical screen flow in onboard.sh:
1. clear                    # Clear screen
2. print_header             # Render progress bar + branding
3. render content           # Lesson/menu content
4. capture input            # gum choose OR read -rp
5. process action           # Navigate, mark complete, etc.
6. loop or return           # Stay in menu or return to parent
```

### State Management Approach
```bash
# JSON progress file structure:
{
  "completed": [0, 1, 2],      # Array of completed lesson indices
  "current": 3,                 # Current lesson index
  "started_at": "ISO8601",
  "last_accessed": "ISO8601"
}

# Key functions:
get_completed()      # Parse JSON, return CSV of completed indices
is_completed(N)      # Check if lesson N is in completed array
mark_completed(N)    # Add N to completed array, update current
set_current(N)       # Update current without marking complete
reset_progress()     # Clear all progress with backup
```

### Color Scheme (Catppuccin Mocha)
```bash
ACFS_PRIMARY="#89b4fa"    # Blue - primary actions
ACFS_SECONDARY="#74c7ec"  # Teal - secondary
ACFS_SUCCESS="#a6e3a1"    # Green - success states
ACFS_WARNING="#f9e2af"    # Yellow - warnings
ACFS_ERROR="#f38ba8"      # Red - errors
ACFS_MUTED="#6c7086"      # Gray - muted text
ACFS_ACCENT="#cba6f7"     # Purple - accents
ACFS_PINK="#f5c2e7"       # Pink - headings
ACFS_TEAL="#94e2d5"       # Teal - highlights
```

---

## Recommended Approach for newproj

### TUI Library: gum with bash fallback

**Rationale:**
1. Already used in onboard.sh - consistent UX
2. ACFS installer already has gum in manifest (can be installed)
3. `scripts/lib/gum_ui.sh` provides reusable themed components
4. Fallback to bash ensures wizard works even without gum

### File Organization

```
scripts/lib/
├── newproj.sh              # Existing CLI implementation
├── newproj_tui.sh          # NEW: TUI framework + main loop
├── newproj_logging.sh      # NEW: Detailed logging
├── newproj_errors.sh       # NEW: Error handling
├── newproj_screens/        # NEW: Individual screen modules
│   ├── welcome.sh
│   ├── project_name.sh
│   ├── directory.sh
│   ├── tech_stack.sh
│   ├── features.sh
│   ├── agents_preview.sh
│   ├── confirmation.sh
│   ├── progress.sh
│   └── success.sh
└── gum_ui.sh               # EXISTING: Reusable gum wrappers
```

### State Management

Adapt onboard.sh's JSON approach but simpler (single session, no persistence):

```bash
declare -A WIZARD_STATE=(
    [project_name]=""
    [project_dir]=""
    [tech_stack]=""           # Space-separated: "nodejs typescript docker"
    [enable_br]="true"
    [enable_claude]="true"
    [enable_agents]="true"
    [enable_ubsignore]="true"
)

# History stack for back navigation
declare -a WIZARD_HISTORY=()
WIZARD_CURRENT_SCREEN=""
```

---

## Reusable Components from ACFS

### From gum_ui.sh (scripts/lib/gum_ui.sh)

| Function | Purpose | Use in newproj |
|----------|---------|----------------|
| `gum_step()` | Step indicator `[1/N] message` | Progress header |
| `gum_success()` | Green checkmark message | Completion confirmations |
| `gum_error()` | Red X error message | Validation errors |
| `gum_warn()` | Yellow warning message | Warnings (dir exists) |
| `gum_box()` | Bordered box with title | Confirmation summary |
| `gum_confirm()` | Yes/No prompt | Cancel confirmation |
| `gum_choose()` | Selection menu | Feature toggles |
| `gum_spin()` | Spinner for operations | Creating project |
| `gum_section()` | Section header | Screen titles |
| `print_banner()` | ACFS ASCII banner | Welcome screen |
| `print_compact_banner()` | Smaller banner | Screen headers |

### From onboard.sh (patterns to adapt)

| Pattern | How onboard.sh does it | Adapt for newproj |
|---------|------------------------|-------------------|
| Progress bar | `render_progress_bar()` | Show wizard step progress |
| Screen navigation | `show_lesson()` with nav menu | Similar for wizard screens |
| Input validation | Not extensive | Add real-time validation |
| Celebration | `show_celebration()` | Success screen at end |
| Markdown rendering | `render_markdown()` with glow/gum/bat | AGENTS.md preview |

---

## Gaps to Fill (newproj needs but onboard lacks)

1. **Real-time input validation**
   - onboard.sh doesn't validate lesson choices beyond [1-9]
   - newproj needs: project name validation, directory checks

2. **Text input with editing**
   - onboard.sh uses simple `read -rp`
   - newproj needs: `gum input` with placeholder, validation

3. **Multi-select checkboxes**
   - onboard.sh uses `gum choose` for single select
   - newproj needs: `gum choose --no-limit` for feature selection

4. **Tech stack detection**
   - onboard.sh doesn't detect anything
   - newproj needs: scan directory for config files

5. **AGENTS.md generation**
   - onboard.sh doesn't generate files
   - newproj needs: dynamic content based on tech stack

6. **Transaction rollback**
   - onboard.sh doesn't create files that need cleanup
   - newproj needs: cleanup on Ctrl+C or failure

---

## Decision Record

### Decision 1: TUI Library
- **Choice**: gum with pure bash fallback
- **Rationale**: Consistent with onboard.sh, gum_ui.sh exists, beautiful output
- **Alternative rejected**: dialog/whiptail (dated look, not consistent with ACFS)

### Decision 2: State Management
- **Choice**: Bash associative array + history stack
- **Rationale**: Single session, no persistence needed, simpler than JSON
- **Persist**: Only for resume-after-failure (optional enhancement)

### Decision 3: Screen Architecture
- **Choice**: One file per screen in newproj_screens/
- **Rationale**: Matches onboard.sh's modular approach, easier testing
- **Each screen**: render() + input() + validate() functions

### Decision 4: Color Scheme
- **Choice**: Reuse Catppuccin Mocha from gum_ui.sh
- **Rationale**: Consistent with ACFS installer and onboard
- **Import**: Source gum_ui.sh at start of newproj_tui.sh

### Decision 5: Fallback Strategy
- **Choice**: Full wizard works without gum, just less pretty
- **Rationale**: Users should be able to use wizard immediately
- **Implementation**: Every gum call has if/else with read fallback

---

## Implementation Recommendations

### 1. Start with gum_ui.sh
```bash
# At top of newproj_tui.sh:
source "$SCRIPT_DIR/gum_ui.sh"
source "$SCRIPT_DIR/newproj_logging.sh"
source "$SCRIPT_DIR/newproj_errors.sh"
```

### 2. Use gum input for text fields
```bash
read_project_name() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum input \
            --placeholder "my-awesome-project" \
            --prompt "> " \
            --prompt.foreground "$ACFS_PRIMARY" \
            --cursor.foreground "$ACFS_ACCENT"
    else
        read -rp "> " input
        echo "$input"
    fi
}
```

### 3. Use gum choose with --no-limit for multi-select
```bash
select_features() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum choose --no-limit \
            --cursor.foreground "$ACFS_ACCENT" \
            --selected.foreground "$ACFS_SUCCESS" \
            "Beads issue tracking (br)" \
            "Claude Code settings" \
            "AGENTS.md template" \
            "UBS ignore patterns"
    else
        # Bash fallback with numbered options
    fi
}
```

### 4. Adapt render_progress_bar from onboard.sh
```bash
render_wizard_progress() {
    local current=$1
    local total=9  # Number of wizard steps
    local percent=$((current * 100 / total))
    local filled=$((percent / 5))
    local empty=$((20 - filled))

    local bar=""
    for ((i = 0; i < filled; i++)); do bar+="█"; done
    for ((i = 0; i < empty; i++)); do bar+="░"; done
    echo "$bar $current/$total"
}
```

---

## Prototype Sketch

```bash
#!/usr/bin/env bash
# newproj_tui.sh - TUI wizard for newproj

source "$SCRIPT_DIR/gum_ui.sh"

declare -A WIZARD_STATE
declare -a WIZARD_SCREENS=(welcome project_name directory tech_stack features agents_preview confirmation progress success)
WIZARD_CURRENT=0

run_wizard() {
    setup_signal_handlers
    init_logging

    while [[ $WIZARD_CURRENT -lt ${#WIZARD_SCREENS[@]} ]]; do
        local screen="${WIZARD_SCREENS[$WIZARD_CURRENT]}"
        log_screen "ENTER" "$screen"

        # Source and run screen
        source "$SCRIPT_DIR/newproj_screens/${screen}.sh"

        clear
        print_header
        render_${screen}

        local action
        action=$(handle_${screen}_input)

        case "$action" in
            next) ((WIZARD_CURRENT++)) ;;
            back) ((WIZARD_CURRENT > 0)) && ((WIZARD_CURRENT--)) ;;
            cancel) confirm_cancel && exit 0 ;;
        esac
    done

    finalize_logging 0
}
```

---

## Next Steps

This research enables **kfy5 (Design wizard flow)** to proceed with concrete patterns:

1. Use gum + bash fallback (proven in onboard.sh)
2. Source gum_ui.sh for consistent styling
3. Follow onboard.sh screen lifecycle pattern
4. Add newproj-specific: validation, tech detection, file generation
5. Implement error handling with cleanup (not in onboard.sh)

---

## Appendix: Key Files Analyzed

| File | Lines | Purpose |
|------|-------|---------|
| `packages/onboard/onboard.sh` | 1357 | Complete TUI implementation |
| `scripts/lib/gum_ui.sh` | 397 | Reusable gum wrappers |
| `packages/onboard/src/lib/authChecks.ts` | 336 | Auth check patterns (TypeScript) |
