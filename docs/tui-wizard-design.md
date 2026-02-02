# newproj TUI Wizard Design

> Design for bead kfy5: Design newproj TUI wizard flow and screens
> Designer: BrightWolf (claude-code, opus-4.5)
> Date: 2026-01-07
> Based on: docs/tui-research.md

---

## Overview

The newproj TUI wizard guides users through project creation with 9 screens. Each screen collects or confirms information, with back navigation and state preservation.

---

## Screen Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   ┌─────────┐     ┌──────────────┐     ┌───────────┐       │
│   │ Welcome │────▶│ Project Name │────▶│ Directory │       │
│   └─────────┘     └──────────────┘     └───────────┘       │
│        │                  │                   │             │
│        ▼                  ▼                   ▼             │
│   [Exit]             [Back]              [Back]             │
│                                               │             │
│                           ┌───────────────────┘             │
│                           ▼                                 │
│                    ┌─────────────┐     ┌──────────┐        │
│                    │ Tech Stack  │────▶│ Features │        │
│                    └─────────────┘     └──────────┘        │
│                           │                   │             │
│                           ▼                   ▼             │
│                      [Back]              [Back]             │
│                                               │             │
│                           ┌───────────────────┘             │
│                           ▼                                 │
│                    ┌──────────────────┐                    │
│                    │ AGENTS.md Preview│                    │
│                    └──────────────────┘                    │
│                           │                                 │
│                           ▼                                 │
│                    ┌──────────────┐                        │
│                    │ Confirmation │                        │
│                    └──────────────┘                        │
│                           │                                 │
│                    ┌──────┴──────┐                         │
│                    ▼             ▼                         │
│               [Create]      [Back/Edit]                    │
│                    │                                        │
│                    ▼                                        │
│              ┌──────────┐                                  │
│              │ Progress │                                  │
│              └──────────┘                                  │
│                    │                                        │
│                    ▼                                        │
│              ┌─────────┐                                   │
│              │ Success │                                   │
│              └─────────┘                                   │
│                    │                                        │
│                    ▼                                        │
│               [Exit/Open]                                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Screen 1: Welcome

### Purpose
Introduce the wizard and set expectations.

### ASCII Mockup
```
╭─────────────────────────────────────────────────────────────────╮
│                                                                 │
│     █████╗  ██████╗███████╗███████╗                            │
│    ██╔══██╗██╔════╝██╔════╝██╔════╝                            │
│    ███████║██║     █████╗  ███████╗                            │
│    ██╔══██║██║     ██╔══╝  ╚════██║                            │
│    ██║  ██║╚██████╗██║     ███████║                            │
│    ╚═╝  ╚═╝ ╚═════╝╚═╝     ╚══════╝                            │
│                                                                 │
│    Welcome to the newproj wizard!                               │
│                                                                 │
│    This wizard will help you create a new project with:        │
│      • Git repository with .gitignore                          │
│      • Beads issue tracking (br)                                │
│      • Claude Code settings                                     │
│      • AGENTS.md tailored to your tech stack                   │
│      • UBS ignore patterns                                      │
│                                                                 │
│    Takes about 2 minutes.                                       │
│                                                                 │
╰─────────────────────────────────────────────────────────────────╯

                 ► Continue          Exit
```

### Interactions
| Key | Action |
|-----|--------|
| Enter | Continue to next screen |
| Escape / q | Exit wizard |

### State Changes
None (informational only)

---

## Screen 2: Project Name

### Purpose
Collect and validate the project name.

### ASCII Mockup
```
╭─────────────────────────────────────────────────────────────────╮
│  Step 1 of 7  ○ ○ ○ ○ ○ ○ ○                                    │
│  Project Name                                                   │
╰─────────────────────────────────────────────────────────────────╯

  Enter a name for your project:

  ┌─────────────────────────────────────────────────────────────┐
  │ my-awesome-project█                                         │
  └─────────────────────────────────────────────────────────────┘

  ✓ Valid project name

  Naming rules:
  • Start with a letter (a-z, A-Z)
  • Letters, numbers, hyphens, underscores only
  • No spaces

─────────────────────────────────────────────────────────────────
  [Enter] Continue   [Esc] Back   [Ctrl+C] Cancel
```

### Error State
```
  ┌─────────────────────────────────────────────────────────────┐
  │ 123-invalid█                                                │
  └─────────────────────────────────────────────────────────────┘

  ✖ Must start with a letter (a-z)
```

### Validation Rules
| Rule | Error Message |
|------|---------------|
| Empty | "Project name is required" |
| Starts with non-letter | "Must start with a letter (a-z)" |
| Invalid characters | "Only letters, numbers, hyphens, underscores allowed" |
| Reserved names | "Reserved name, please choose another" |

### State Changes
- Sets `WIZARD_STATE[project_name]`

---

## Screen 3: Directory

### Purpose
Choose where to create the project.

### ASCII Mockup
```
╭─────────────────────────────────────────────────────────────────╮
│  Step 2 of 7  ● ○ ○ ○ ○ ○ ○                                    │
│  Project Directory                                              │
╰─────────────────────────────────────────────────────────────────╯

  Where should we create "my-awesome-project"?

  ┌─────────────────────────────────────────────────────────────┐
  │ /data/projects/my-awesome-project█                          │
  └─────────────────────────────────────────────────────────────┘

  ✓ Directory will be created

  Tips:
  • Default: /data/projects/<name>
  • Use Tab for path completion (if gum available)
  • Parent directories will be created if needed

─────────────────────────────────────────────────────────────────
  [Enter] Continue   [Esc] Back   [Ctrl+C] Cancel
```

### Warning State (directory exists)
```
  ⚠ Directory already exists
    Existing contents will be preserved.
    ACFS files may be overwritten.
```

### Error State (no parent write permission)
```
  ✖ Cannot create directory
    No write permission to /root/projects
    Try: /data/projects/my-awesome-project
```

### Validation Rules
| Rule | Message Type | Message |
|------|--------------|---------|
| Directory exists | Warning | "Directory already exists. Existing contents preserved." |
| Parent not writable | Error | "Cannot create: no write permission" |
| Path is a file | Error | "Path exists and is a file, not directory" |

### State Changes
- Sets `WIZARD_STATE[project_dir]`

---

## Screen 4: Tech Stack Detection

### Purpose
Detect or select the project's technology stack.

### ASCII Mockup (with detection)
```
╭─────────────────────────────────────────────────────────────────╮
│  Step 3 of 7  ● ● ○ ○ ○ ○ ○                                    │
│  Tech Stack                                                     │
╰─────────────────────────────────────────────────────────────────╯

  We detected the following from your directory:
    📦 package.json → Node.js
    📘 tsconfig.json → TypeScript
    🐳 Dockerfile → Docker

  Confirm or modify your tech stack:

    [✓] Node.js / TypeScript
    [✓] Docker
    [ ] Python
    [ ] Rust
    [ ] Go
    [ ] Other

  Space to toggle, Enter to confirm

─────────────────────────────────────────────────────────────────
  [Enter] Continue   [Esc] Back   [Ctrl+C] Cancel
```

### ASCII Mockup (empty directory)
```
╭─────────────────────────────────────────────────────────────────╮
│  Step 3 of 7  ● ● ○ ○ ○ ○ ○                                    │
│  Tech Stack                                                     │
╰─────────────────────────────────────────────────────────────────╯

  No tech stack detected. What will you be building?

  Select all that apply:

    [ ] Node.js / TypeScript
    [ ] Python
    [ ] Rust
    [ ] Go
    [ ] Other

  This helps customize your AGENTS.md template.

─────────────────────────────────────────────────────────────────
  [Enter] Continue   [Esc] Back   [Ctrl+C] Cancel
```

### State Changes
- Sets `WIZARD_STATE[tech_stack]` (space-separated list)

---

## Screen 5: Features

### Purpose
Select which ACFS features to enable.

### ASCII Mockup
```
╭─────────────────────────────────────────────────────────────────╮
│  Step 4 of 7  ● ● ● ○ ○ ○ ○                                    │
│  ACFS Features                                                  │
╰─────────────────────────────────────────────────────────────────╯

  Which features do you want to enable?

    [✓] Beads issue tracking (br)
        Track work items with dependencies

    [✓] Claude Code settings
        Project-specific agent configuration

    [✓] AGENTS.md template
        Instructions for AI coding agents

    [✓] UBS ignore patterns (.ubsignore)
        Configure bug scanner exclusions

  All features recommended for new projects.

─────────────────────────────────────────────────────────────────
  [Enter] Continue   [Esc] Back   [Ctrl+C] Cancel
```

### State Changes
- Sets `WIZARD_STATE[enable_br]`
- Sets `WIZARD_STATE[enable_claude]`
- Sets `WIZARD_STATE[enable_agents]`
- Sets `WIZARD_STATE[enable_ubsignore]`

---

## Screen 6: AGENTS.md Preview

### Purpose
Preview and optionally customize the generated AGENTS.md.

### ASCII Mockup
```
╭─────────────────────────────────────────────────────────────────╮
│  Step 5 of 7  ● ● ● ● ○ ○ ○                                    │
│  AGENTS.md Preview                                              │
╰─────────────────────────────────────────────────────────────────╯

  Based on your selections, AGENTS.md will include:

  ┌─────────────────────────────────────────────────────────────┐
  │ # AGENTS.md — my-awesome-project                            │
  │                                                              │
  │ ## RULE 1 – ABSOLUTE                                        │
  │ You may NOT delete any file...                              │
  │                                                              │
  │ ## Node / JS Toolchain                                      │
  │ - Use **bun** for everything JS/TS                          │
  │ - Never use npm, yarn, or pnpm...                           │
  │                                                              │
  │ ## Docker Workflow                                          │
  │ - Build: `docker compose build`...                          │
  │                                                              │
  │ [Scroll: ↑↓ or j/k]                           (1/3 pages)   │
  └─────────────────────────────────────────────────────────────┘

  ► Accept as-is     Customize in $EDITOR     Back

─────────────────────────────────────────────────────────────────
  [Enter] Accept   [e] Edit   [Esc] Back   [Ctrl+C] Cancel
```

### Interactions
| Key | Action |
|-----|--------|
| Enter | Accept and continue |
| e | Open in $EDITOR for customization |
| ↑/↓ or j/k | Scroll preview |
| Escape | Back to previous screen |

### State Changes
- May modify AGENTS.md content if customized

---

## Screen 7: Confirmation

### Purpose
Review all choices before creating the project.

### ASCII Mockup
```
╭─────────────────────────────────────────────────────────────────╮
│  Step 6 of 7  ● ● ● ● ● ○ ○                                    │
│  Confirm & Create                                               │
╰─────────────────────────────────────────────────────────────────╯

  Review your project settings:

  ┌─────────────────────────────────────────────────────────────┐
  │  Project Name:   my-awesome-project                         │
  │  Directory:      /data/projects/my-awesome-project          │
  │  Tech Stack:     Node.js, TypeScript, Docker                │
  │                                                              │
  │  Features:                                                   │
  │    ✓ Beads (br)                                             │
  │    ✓ Claude Code settings                                   │
  │    ✓ AGENTS.md                                              │
  │    ✓ UBS ignore patterns                                    │
  └─────────────────────────────────────────────────────────────┘

  Files to be created:

    /data/projects/my-awesome-project/
    ├── .git/
    ├── .gitignore
    ├── .ubsignore
    ├── .beads/
    ├── .claude/
    │   └── settings.toml
    ├── AGENTS.md
    └── README.md

        ► Create Project          Edit Settings

─────────────────────────────────────────────────────────────────
  [Enter] Create   [e] Edit   [Ctrl+C] Cancel
```

### Interactions
| Key | Action |
|-----|--------|
| Enter | Create project |
| e | Go back to edit |
| Ctrl+C | Cancel |

---

## Screen 8: Progress

### Purpose
Show creation progress with status indicators.

### ASCII Mockup
```
╭─────────────────────────────────────────────────────────────────╮
│  Step 7 of 7  ● ● ● ● ● ● ○                                    │
│  Creating Project                                               │
╰─────────────────────────────────────────────────────────────────╯

  Creating my-awesome-project...

    ✓ Creating directory
    ✓ Initializing git repository
    ✓ Creating .gitignore
    ✓ Creating .ubsignore
    ⠋ Initializing beads (br)...
    ○ Creating Claude settings
    ○ Generating AGENTS.md
    ○ Creating README.md

  ████████████░░░░░░░░  60%

─────────────────────────────────────────────────────────────────
  Please wait...
```

### Error State
```
    ✓ Creating directory
    ✓ Initializing git repository
    ✖ Initializing beads (br)
      Error: br command not found

  ┌─────────────────────────────────────────────────────────────┐
  │  Some steps failed. What would you like to do?              │
  │                                                              │
  │  ► Skip failed steps and continue                           │
  │    Retry failed steps                                       │
  │    Cancel and rollback                                      │
  └─────────────────────────────────────────────────────────────┘
```

### State Changes
- Creates actual files and directories
- Rolls back on failure if user chooses

---

## Screen 9: Success

### Purpose
Celebrate completion and show next steps.

### ASCII Mockup
```
╭═════════════════════════════════════════════════════════════════╮
║                                                                 ║
║                    🎉 Project Created! 🎉                       ║
║                                                                 ║
╰═════════════════════════════════════════════════════════════════╯

  ✓ my-awesome-project is ready at:
    /data/projects/my-awesome-project

  What was created:
    ✓ Git repository initialized
    ✓ .gitignore with common patterns
    ✓ .ubsignore for bug scanner
    ✓ Beads initialized (.beads/)
    ✓ Claude settings (.claude/settings.toml)
    ✓ AGENTS.md with Node.js + TypeScript + Docker sections
    ✓ README.md

  Next steps:
    cd /data/projects/my-awesome-project
    claude .        # Start Claude Code
    br ready        # Check available work

        ► Open in Claude Code          Exit

─────────────────────────────────────────────────────────────────
  [Enter] Open Claude   [q] Exit
```

### Interactions
| Key | Action |
|-----|--------|
| Enter | Run `claude .` in project directory |
| q | Exit wizard |

---

## State Machine

```
┌─────────────────────────────────────────────────────────────────┐
│                         STATE MACHINE                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  State Variables:                                               │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ WIZARD_STATE[project_name] = ""                           │ │
│  │ WIZARD_STATE[project_dir] = ""                            │ │
│  │ WIZARD_STATE[tech_stack] = ""                             │ │
│  │ WIZARD_STATE[enable_br] = "true"                          │ │
│  │ WIZARD_STATE[enable_claude] = "true"                      │ │
│  │ WIZARD_STATE[enable_agents] = "true"                      │ │
│  │ WIZARD_STATE[enable_ubsignore] = "true"                   │ │
│  │ WIZARD_STATE[agents_md_content] = ""                      │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  Navigation:                                                    │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ WIZARD_SCREENS = [welcome, project_name, directory,      │ │
│  │                   tech_stack, features, agents_preview,   │ │
│  │                   confirmation, progress, success]        │ │
│  │ WIZARD_CURRENT = 0  # Current screen index               │ │
│  │ WIZARD_HISTORY = [] # For back navigation                │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  Transitions:                                                   │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ NEXT: Push current to history, increment WIZARD_CURRENT  │ │
│  │ BACK: Pop from history, restore state                    │ │
│  │ CANCEL: Confirm, cleanup, exit                           │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Input Validation Summary

| Screen | Field | Validation | Real-time? |
|--------|-------|------------|------------|
| project_name | name | ^[a-zA-Z][a-zA-Z0-9_-]*$ | Yes |
| directory | path | Writable parent, not a file | On submit |
| tech_stack | selection | At least one (or empty is OK) | No |
| features | selection | Any combination valid | No |
| agents_preview | content | Valid markdown (basic check) | On save |

---

## Error Recovery Flows

### 1. Ctrl+C at any screen
```
User presses Ctrl+C
    │
    ▼
Show confirmation: "Cancel wizard? (y/N)"
    │
    ├── Yes ──▶ Cleanup any partial state ──▶ Exit 0
    │
    └── No ──▶ Return to current screen
```

### 2. Directory creation fails
```
mkdir fails
    │
    ▼
Show error with diagnosis:
  - "No write permission" → Suggest sudo or different path
  - "Disk full" → Suggest df -h
  - "Path is file" → Suggest rename or different path
    │
    ▼
Options:
  - Try different path (go back)
  - Exit
```

### 3. br init fails
```
br init fails
    │
    ▼
Show warning (not fatal):
  "br initialization failed. You can run 'br init' later."
    │
    ▼
Continue with remaining steps (graceful degradation)
```

---

## Keyboard Shortcuts (All Screens)

| Key | Action |
|-----|--------|
| Enter | Confirm / Continue |
| Escape | Back / Cancel |
| Ctrl+C | Show cancel confirmation |
| Tab | Next field (if multiple) |
| Shift+Tab | Previous field |
| ↑/↓ | Navigate lists |
| Space | Toggle checkbox |
| j/k | Vim-style up/down |

---

## Accessibility Notes

### Color + Symbol
Every state uses both color AND symbol:
- ✓ Green = success
- ✖ Red = error
- ⚠ Yellow = warning
- ○ Gray = pending
- ● Blue = current/active

### Keyboard Only
All interactions work with keyboard only. No mouse required.

### Fallback Mode (TERM=dumb)
- Use ASCII box drawing (+ - |) instead of Unicode
- Use text labels instead of emoji
- Progress: [====    ] 50% instead of █░

---

## Implementation Notes

### gum commands to use

| Screen | gum command |
|--------|-------------|
| project_name | `gum input --placeholder "project-name"` |
| directory | `gum input --value "$default_path"` |
| tech_stack | `gum choose --no-limit` |
| features | `gum choose --no-limit --selected "..."` |
| agents_preview | `gum pager` or scroll with `gum style` |
| confirmation | `gum confirm` |
| progress | `gum spin` for each step |

### Files to create

```
scripts/lib/
├── newproj_tui.sh          # Main wizard entry
├── newproj_logging.sh      # Logging infrastructure
├── newproj_errors.sh       # Error handling
└── newproj_screens/
    ├── welcome.sh
    ├── project_name.sh
    ├── directory.sh
    ├── tech_stack.sh
    ├── features.sh
    ├── agents_preview.sh
    ├── confirmation.sh
    ├── progress.sh
    └── success.sh
```

---

## Appendix: Full State Example

After completing wizard:

```bash
WIZARD_STATE=(
    [project_name]="my-awesome-project"
    [project_dir]="/data/projects/my-awesome-project"
    [tech_stack]="nodejs typescript docker"
    [enable_br]="true"
    [enable_claude]="true"
    [enable_agents]="true"
    [enable_ubsignore]="true"
    [agents_md_content]="# AGENTS.md — my-awesome-project\n\n..."
)
```
