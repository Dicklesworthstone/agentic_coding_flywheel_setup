#!/usr/bin/env bash
# ============================================================
# ACFS newproj - Create a new project with full ACFS tooling
# Creates a project with git, beads (bd), and Claude settings
# ============================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_help() {
    echo "Usage: acfs newproj <project-name> [directory]"
    echo ""
    echo "Create a new project with ACFS tooling (git, bd, claude settings)"
    echo ""
    echo "Arguments:"
    echo "  project-name    Name of the project (required)"
    echo "  directory       Directory path (default: /data/projects/<project-name>)"
    echo ""
    echo "Options:"
    echo "  -h, --help      Show this help message"
    echo "  --no-bd         Skip beads (bd) initialization"
    echo "  --no-claude     Skip Claude settings creation"
    echo ""
    echo "Examples:"
    echo "  acfs newproj myapp"
    echo "  acfs newproj myapp /home/ubuntu/projects/myapp"
    echo "  acfs newproj myapp --no-bd"
}

main() {
    local project_name=""
    local project_dir=""
    local skip_bd=false
    local skip_claude=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                print_help
                exit 0
                ;;
            --no-bd)
                skip_bd=true
                shift
                ;;
            --no-claude)
                skip_claude=true
                shift
                ;;
            -*)
                echo -e "${RED}Unknown option: $1${NC}" >&2
                print_help
                exit 1
                ;;
            *)
                if [[ -z "$project_name" ]]; then
                    project_name="$1"
                elif [[ -z "$project_dir" ]]; then
                    project_dir="$1"
                else
                    echo -e "${RED}Too many arguments${NC}" >&2
                    print_help
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Validate project name
    if [[ -z "$project_name" ]]; then
        echo -e "${RED}Error: Project name is required${NC}" >&2
        print_help
        exit 1
    fi

    # Validate project name format (alphanumeric, hyphens, underscores)
    if [[ ! "$project_name" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
        echo -e "${RED}Error: Project name must start with a letter and contain only letters, numbers, hyphens, and underscores${NC}" >&2
        exit 1
    fi

    # Set default directory
    if [[ -z "$project_dir" ]]; then
        project_dir="/data/projects/$project_name"
    fi

    # Check if directory already exists
    if [[ -d "$project_dir" ]]; then
        echo -e "${YELLOW}Warning: Directory $project_dir already exists${NC}"
        if [[ -d "$project_dir/.git" ]]; then
            echo -e "${CYAN}Git repository already initialized${NC}"
        fi
    fi

    echo -e "${CYAN}Creating project: $project_name${NC}"
    echo -e "${CYAN}Directory: $project_dir${NC}"
    echo ""

    # Create directory
    mkdir -p "$project_dir"
    cd "$project_dir"

    # Initialize git if not already
    if [[ ! -d .git ]]; then
        echo -e "${GREEN}Initializing git repository...${NC}"
        git init
        echo "# $project_name" > README.md
        git add README.md
        git commit -m "Initial commit"
    else
        echo -e "${CYAN}Git already initialized, skipping${NC}"
    fi

    # Initialize beads (bd) if available and not skipped
    if [[ "$skip_bd" == "false" ]]; then
        if command -v bd &>/dev/null; then
            if [[ ! -d .beads ]]; then
                echo -e "${GREEN}Initializing beads (bd)...${NC}"
                bd init
            else
                echo -e "${CYAN}Beads already initialized, skipping${NC}"
            fi
        else
            echo -e "${YELLOW}Warning: bd not found, skipping beads initialization${NC}"
            echo -e "${YELLOW}Install with: curl -fsSL https://agent-flywheel.com/install | bash -s -- --yes --only stack.beads_viewer${NC}"
        fi
    fi

    # Create Claude settings if not skipped
    if [[ "$skip_claude" == "false" ]]; then
        mkdir -p .claude/commands

        if [[ ! -f .claude/settings.toml ]]; then
            echo -e "${GREEN}Creating Claude settings...${NC}"
            cat > .claude/settings.toml << 'EOF'
# Claude Code project settings
# See: https://docs.anthropic.com/en/docs/claude-code/settings

[project]
# Project-specific settings go here

[permissions]
# allow = ["Bash(npm:*)", "Bash(bun:*)"]
EOF
        else
            echo -e "${CYAN}Claude settings already exist, skipping${NC}"
        fi
    fi

    echo ""
    echo -e "${GREEN}Project $project_name ready at $project_dir${NC}"
    echo ""
    echo "Next steps:"
    echo "  cd $project_dir"
    if [[ "$skip_bd" == "false" ]] && command -v bd &>/dev/null; then
        echo "  bd ready                    # Check for work"
        echo "  bd create --title=\"...\"    # Create tasks"
    fi
    echo "  cc                          # Start Claude Code"
}

main "$@"
