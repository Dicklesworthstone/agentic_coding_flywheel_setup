#!/usr/bin/env bash
# ============================================================
# ACFS E2E Test Helper
# Provides TUI automation, terminal simulation, and test utilities
# for end-to-end testing of the newproj wizard
# ============================================================

# Determine paths
E2E_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(cd "$E2E_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
ACFS_LIB_DIR="$PROJECT_ROOT/scripts/lib"
E2E_LIB_DIR="$E2E_DIR/lib"
E2E_LOGS_DIR="$E2E_DIR/logs"

# Ensure directories exist
mkdir -p "$E2E_LOGS_DIR"

# ============================================================
# Feature Detection
# ============================================================

# Check if expect is available
has_expect() {
    command -v expect &>/dev/null
}

# Check if script (typescript) is available
has_script() {
    command -v script &>/dev/null
}

# Check if we have a pseudo-TTY available
has_pty() {
    [[ -c /dev/ptmx ]] || [[ -c /dev/pty0 ]]
}

# ============================================================
# Load Dependencies
# ============================================================

# Load unit test helper for common functions
source "$TESTS_DIR/unit/test_helper.bash"

# Load test harness for structured logging
source "$TESTS_DIR/vm/lib/test_harness.sh"

# Load TUI driver
source "$E2E_LIB_DIR/tui_driver.sh"

# ============================================================
# E2E-Specific Setup
# ============================================================

# Array to track temp dirs for cleanup
declare -a E2E_TEMP_DIRS=()

# Set up E2E test environment
setup_e2e_env() {
    # Create test-specific directories
    E2E_TEST_DIR=$(mktemp -d)
    E2E_TEMP_DIRS+=("$E2E_TEST_DIR")

    # Set up logging
    E2E_TEST_LOG="$E2E_LOGS_DIR/$(date +%Y%m%d_%H%M%S)_${BATS_TEST_NAME:-e2e}.log"

    # Create artifact directory for this test
    E2E_ARTIFACT_DIR="$E2E_TEST_DIR/artifacts"
    mkdir -p "$E2E_ARTIFACT_DIR"

    # Set environment for TUI
    export TERM="${TERM:-xterm-256color}"
    export COLUMNS="${COLUMNS:-80}"
    export LINES="${LINES:-24}"

    # Disable CI detection for testing
    unset CI GITHUB_ACTIONS GITLAB_CI JENKINS_URL TRAVIS CIRCLECI

    # Enable test mode
    export ACFS_TEST_MODE=1
    export ACFS_LOG_DIR="$E2E_TEST_DIR/logs"
    export ACFS_LOG_LEVEL=0  # DEBUG level
    mkdir -p "$ACFS_LOG_DIR"

    log_e2e "INFO" "E2E test environment initialized"
    log_e2e "INFO" "Test directory: $E2E_TEST_DIR"
    log_e2e "INFO" "Artifact directory: $E2E_ARTIFACT_DIR"
}

# Clean up E2E test environment
teardown_e2e_env() {
    local exit_code=$?

    # Capture artifacts on failure
    if [[ $exit_code -ne 0 ]]; then
        capture_e2e_artifacts
    fi

    # Clean up temp directories
    for dir in "${E2E_TEMP_DIRS[@]}"; do
        [[ -d "$dir" ]] && rm -rf "$dir"
    done
    E2E_TEMP_DIRS=()

    # Reset environment
    unset ACFS_TEST_MODE ACFS_LOG_DIR

    log_e2e "INFO" "E2E test environment cleaned up (exit: $exit_code)"
}

# ============================================================
# E2E Logging
# ============================================================

log_e2e() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')

    echo "[$timestamp] [$level] $message" >> "${E2E_TEST_LOG:-/dev/null}"

    # Also echo to stderr for bats output on failure
    if [[ "$level" == "ERROR" ]] || [[ "$level" == "FAIL" ]]; then
        echo "[$level] $message" >&2
    fi
}

# ============================================================
# Artifact Capture
# ============================================================

capture_e2e_artifacts() {
    local dest_dir="${1:-$E2E_ARTIFACT_DIR}"

    log_e2e "INFO" "Capturing E2E artifacts to $dest_dir"

    # Capture ACFS logs
    if [[ -d "$ACFS_LOG_DIR" ]]; then
        cp -r "$ACFS_LOG_DIR" "$dest_dir/acfs_logs" 2>/dev/null || true
    fi

    # Capture TUI driver logs
    if [[ -f "$TUI_DRIVER_LOG" ]]; then
        cp "$TUI_DRIVER_LOG" "$dest_dir/tui_driver.log" 2>/dev/null || true
    fi

    # Capture screen output if available
    if [[ -f "$TUI_SCREEN_CAPTURE" ]]; then
        cp "$TUI_SCREEN_CAPTURE" "$dest_dir/screen_capture.txt" 2>/dev/null || true
    fi

    # List created project directory if exists
    if [[ -n "$E2E_PROJECT_DIR" ]] && [[ -d "$E2E_PROJECT_DIR" ]]; then
        find "$E2E_PROJECT_DIR" -type f > "$dest_dir/created_files.txt" 2>/dev/null || true
    fi
}

# ============================================================
# Project Verification Helpers
# ============================================================

# Verify a project was created correctly
verify_project_created() {
    local project_dir="$1"
    local project_name="${2:-$(basename "$project_dir")}"

    log_e2e "INFO" "Verifying project at: $project_dir"

    # Check directory exists
    if [[ ! -d "$project_dir" ]]; then
        log_e2e "FAIL" "Project directory not found: $project_dir"
        return 1
    fi

    # Check basic files
    local required_files=("README.md" ".gitignore")
    for file in "${required_files[@]}"; do
        if [[ ! -f "$project_dir/$file" ]]; then
            log_e2e "FAIL" "Required file not found: $file"
            return 1
        fi
    done

    # Check git initialized
    if [[ ! -d "$project_dir/.git" ]]; then
        log_e2e "FAIL" "Git repository not initialized"
        return 1
    fi

    log_e2e "PASS" "Project verification passed"
    return 0
}

# Verify specific features were enabled
verify_feature_enabled() {
    local project_dir="$1"
    local feature="$2"

    case "$feature" in
        agents|AGENTS.md)
            [[ -f "$project_dir/AGENTS.md" ]]
            ;;
        beads|br)
            [[ -d "$project_dir/.beads" ]] && [[ -f "$project_dir/.beads/beads.db" ]]
            ;;
        claude)
            [[ -d "$project_dir/.claude" ]] && [[ -f "$project_dir/.claude/settings.local.json" ]]
            ;;
        ubsignore)
            [[ -f "$project_dir/.ubsignore" ]]
            ;;
        *)
            log_e2e "WARN" "Unknown feature: $feature"
            return 1
            ;;
    esac
}

# ============================================================
# Screen Content Matchers
# ============================================================

# Check if screen output contains expected text
screen_contains() {
    local expected="$1"
    local screen_content="${2:-$TUI_LAST_OUTPUT}"

    if [[ "$screen_content" == *"$expected"* ]]; then
        return 0
    else
        log_e2e "DEBUG" "Screen does not contain: $expected"
        return 1
    fi
}

# Check if we're on a specific screen
on_screen() {
    local screen_name="$1"
    local screen_content="${2:-$TUI_LAST_OUTPUT}"

    case "$screen_name" in
        welcome)
            screen_contains "Welcome to ACFS" "$screen_content"
            ;;
        project_name)
            screen_contains "Project Name" "$screen_content"
            ;;
        directory)
            screen_contains "Project Directory" "$screen_content"
            ;;
        tech_stack)
            screen_contains "Technology Stack" "$screen_content"
            ;;
        features)
            screen_contains "Features" "$screen_content"
            ;;
        agents_preview)
            screen_contains "AGENTS.md Preview" "$screen_content"
            ;;
        confirmation)
            screen_contains "Review & Confirm" "$screen_content"
            ;;
        progress)
            screen_contains "Creating Project" "$screen_content"
            ;;
        success)
            screen_contains "Project Created" "$screen_content"
            ;;
        *)
            log_e2e "WARN" "Unknown screen: $screen_name"
            return 1
            ;;
    esac
}

# ============================================================
# Test Execution Helpers
# ============================================================

# Run the wizard with input sequence
run_wizard_with_input() {
    local input_sequence="$1"
    local project_name="${2:-test-project}"
    local project_base="${3:-$E2E_TEST_DIR}"

    E2E_PROJECT_DIR="$project_base/$project_name"

    log_e2e "INFO" "Running wizard with input sequence"
    log_e2e "DEBUG" "Project: $project_name at $E2E_PROJECT_DIR"

    tui_run_with_input "$ACFS_LIB_DIR/newproj.sh" "--interactive" <<< "$input_sequence"
}

# Run wizard through happy path (all defaults)
run_wizard_happy_path() {
    local project_name="${1:-happy-test}"
    local project_base="${2:-$E2E_TEST_DIR}"

    E2E_PROJECT_DIR="$project_base/$project_name"

    log_e2e "INFO" "Running happy path wizard"

    # Input sequence for happy path:
    # 1. Welcome: Enter
    # 2. Project name: type name, Enter
    # 3. Directory: Enter (accept default)
    # 4. Tech stack: Enter (skip selection)
    # 5. Features: Enter (accept defaults)
    # 6. AGENTS preview: Enter (continue)
    # 7. Confirmation: Enter (create)
    # 8. Success: q (quit)

    local input_sequence
    input_sequence=$(cat <<EOF

${project_name}
${project_base}/${project_name}



c
q
EOF
)

    tui_run_with_input "$ACFS_LIB_DIR/newproj.sh" "--interactive" <<< "$input_sequence"
}

# ============================================================
# Skip Helpers
# ============================================================

# Skip test if expect is not available
skip_without_expect() {
    if ! has_expect; then
        skip "expect not installed - install with: apt install expect"
    fi
}

# Skip test if not in a TTY
skip_without_tty() {
    if [[ ! -t 0 ]]; then
        skip "Test requires TTY (run interactively or with script)"
    fi
}

# Skip test if running in CI
skip_in_ci() {
    if [[ -n "${CI:-}" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        skip "Test skipped in CI environment"
    fi
}

# ============================================================
# Common Setup/Teardown
# ============================================================

e2e_setup() {
    setup_test_log
    setup_e2e_env
    tui_driver_init
}

e2e_teardown() {
    tui_driver_cleanup
    teardown_e2e_env
}
