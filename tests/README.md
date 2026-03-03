# ACFS Test Suite

## Directory Structure

```
tests/
├── unit/                    # Unit tests (bats-core)
│   ├── test_helper.bash     # Common utilities, mocks, fixtures
│   ├── lib/                 # Tests for scripts/lib/*.sh
│   │   └── test_newproj_logging.bats
│   └── newproj/             # Tests for newproj TUI wizard
├── e2e/                     # End-to-end tests (bats + expect)
│   ├── test_helper.bash     # E2E-specific utilities
│   ├── lib/                 # E2E library (TUI driver, etc.)
│   │   └── tui_driver.sh    # TUI automation driver
│   ├── expect/              # Expect scripts for full TUI testing
│   │   ├── happy_path.exp   # Full wizard walkthrough
│   │   ├── navigation.exp   # Back/forward navigation
│   │   └── error_handling.exp
│   ├── test_happy_path.bats # Happy path E2E tests
│   ├── test_terminal_compat.bats # Terminal compatibility
│   ├── test_navigation.bats # Navigation and error recovery
│   └── run_e2e.sh           # E2E test runner
├── fixtures/                # Test fixtures
│   ├── sample_projects/     # Mock project directories
│   └── expected_outputs/    # Golden files for comparison
├── logs/                    # Test execution logs (gitignored)
├── vm/                      # Integration tests (Docker)
│   └── test_install_ubuntu.sh
└── web/                     # Web app tests
```

## Running Tests

### Unit Tests (bats-core)

```bash
# Run all unit tests
bats tests/unit/**/*.bats

# Run specific test file
bats tests/unit/lib/test_newproj_logging.bats

# Run with verbose output
bats --verbose-run tests/unit/**/*.bats

# Run with TAP output (for CI)
bats --tap tests/unit/**/*.bats
```

### End-to-End Tests (E2E)

E2E tests verify the complete TUI wizard workflow. They work in two modes:
- **CLI mode**: Tests CLI functionality without TTY (always works)
- **Expect mode**: Full interactive TUI testing (requires `expect`)

```bash
# Run all E2E tests
./tests/e2e/run_e2e.sh

# Quick mode (CLI tests only, no expect required)
./tests/e2e/run_e2e.sh --quick

# Install expect and run all tests
./tests/e2e/run_e2e.sh --with-expect

# Run specific test file
./tests/e2e/run_e2e.sh test_happy_path

# Run directly with bats
bats tests/e2e/test_happy_path.bats
```

#### E2E Test Categories

| File | Description |
|------|-------------|
| `test_happy_path.bats` | Normal successful workflow |
| `test_terminal_compat.bats` | Different TERM types, unicode, colors |
| `test_navigation.bats` | Back/forward, edit mode, error recovery |
| `test_cross_agent_resume_e2e.sh` | Real non-mock cross-agent resume matrix (`codex`/`claude`/`gemini`), defaulting to cross-CLI checks; self-resume baseline is optional |

#### Installing Expect

```bash
# Ubuntu/Debian
sudo apt install expect

# macOS
brew install expect
```

### Integration Tests

```bash
# Run Docker-based installer test
./tests/vm/test_install_ubuntu.sh

# Run real cross-agent resume matrix (requires authenticated CLI sessions)
bash ./tests/e2e/test_cross_agent_resume_e2e.sh

# Optional: include self-resume baseline diagnostics
ACFS_INCLUDE_SELF_RESUME_BASELINE=true bash ./tests/e2e/test_cross_agent_resume_e2e.sh
```

The cross-agent resume matrix writes detailed artifacts to `tests/e2e/logs/`.
By default it treats cross-CLI session isolation as expected behavior; strict mode exits non-zero when foreign session-id continuity checks fail.

## Writing Tests

### Test File Naming

- Unit test files: `test_<module_name>.bats`
- Fixtures: Descriptive names in appropriate subdirectory

### Test Helper

All bats tests should load the test helper:

```bash
#!/usr/bin/env bats

load '../test_helper'

setup() {
    common_setup
    # Your test-specific setup
}

teardown() {
    common_teardown
}
```

### Available Helpers

From `test_helper.bash`:

| Function | Purpose |
|----------|---------|
| `common_setup` | Standard setup (logging, mock terminal) |
| `common_teardown` | Standard teardown (cleanup) |
| `create_temp_project nodejs typescript` | Create temp dir with tech stack |
| `create_temp_dir` | Create empty temp directory |
| `source_lib "module_name"` | Source a scripts/lib/*.sh file |
| `mock_function "name" "return_value"` | Create mock function |
| `assert_success_logged` | Assert success with logging |
| `assert_contains_logged "expected"` | Assert output contains string |

### Example Test

```bash
@test "detect_tech_stack returns nodejs for package.json" {
    local tmpdir=$(create_temp_project "nodejs")

    source_lib "newproj_tui"
    run detect_tech_stack "$tmpdir"

    assert_success
    assert_output --partial "nodejs"
}
```

## Test Logs

Test execution logs are written to `tests/logs/` for debugging:

```
tests/logs/20260106_153045_test_name.log
```

Logs include:
- Test start/end timestamps
- Pass/fail status
- Debug output from assertions
- Captured command output

## Coverage

Run with coverage (requires kcov):

```bash
kcov --include-path=scripts/lib coverage/ bats tests/unit/**/*.bats
```

## CI Integration

Tests run automatically on:
- Pull requests
- Pushes to main branch

Required checks:
- `shellcheck` on all *.sh files
- `bats tests/unit/**/*.bats` passes
- `./tests/e2e/run_e2e.sh --quick` passes
- Integration test passes (on schedule)

### E2E Tests in CI

E2E tests run in quick mode (CLI tests only) by default in CI:

```yaml
# Example GitHub Actions
- name: Run E2E tests
  run: ./tests/e2e/run_e2e.sh --quick

# With expect (requires expect installation)
- name: Install expect
  run: sudo apt-get install -y expect
- name: Run full E2E tests
  run: ./tests/e2e/run_e2e.sh
```
