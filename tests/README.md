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
├── vm/                      # Installer integration tests
│   ├── test_install_ubuntu.sh
│   ├── test_factory_install_ubuntu.sh
│   └── test_factory_install_qemu.sh
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

# Run the full Docker Ubuntu matrix
./tests/vm/test_install_ubuntu.sh --all

# Hang up the first install after cli_tools is checkpointed; --resume must skip it and finish
./tests/vm/test_install_ubuntu.sh --interrupt-resume

# Run the install in an arm64 container (binfmt/QEMU user emulation on x86_64 hosts; slow)
./tests/vm/test_install_ubuntu.sh --platform linux/arm64

# Run focused fresh-root curl|bash regression
./tests/vm/test_fresh_root_bootstrap_regression.sh

# Run authoritative factory-host E2E against a disposable fresh Ubuntu 24.04 LTS VM/VPS
# (an ordinary install preserves the host release)
./tests/vm/test_factory_install_ubuntu.sh --ssh-target root@203.0.113.10

# Run local authoritative VM E2E with QEMU/KVM and the official Ubuntu 24.04 cloud image
./tests/vm/test_factory_install_qemu.sh

# Opt-in 24.04 -> 26.04 upgrade/resume gate (the wizard's --target-ubuntu path)
./tests/vm/test_factory_install_qemu.sh --ubuntu 24.04 --target-ubuntu 26.04 --allow-install-reboot

# Run real cross-agent resume matrix (requires authenticated CLI sessions)
bash ./tests/e2e/test_cross_agent_resume_e2e.sh

# Optional: include self-resume baseline diagnostics
ACFS_INCLUDE_SELF_RESUME_BASELINE=true bash ./tests/e2e/test_cross_agent_resume_e2e.sh
```

The cross-agent resume matrix writes detailed artifacts to `tests/e2e/logs/`.
By default it treats cross-CLI session isolation as expected behavior; strict mode exits non-zero when foreign session-id continuity checks fail.

#### Docker vs Factory-Host Installer E2E

`tests/vm/test_install_ubuntu.sh` is the fast regression harness. It runs the installer in Ubuntu containers, defaulting to `24.04` and covering the supported LTS matrix (`22.04`, `24.04`, `26.04`) when invoked with `--all`. It is appropriate for CI, checksum drift, module-install smoke coverage, and idempotency checks.

`tests/vm/test_factory_install_ubuntu.sh` is the authoritative beginner-path harness. It requires SSH access to a freshly provisioned systemd-capable Ubuntu host, defaults to initial Ubuntu `24.04` and final Ubuntu `24.04`, runs the public `curl|bash` installer as root, and fails by default if the `ubuntu` user already exists before install. It then verifies user creation, SSH key merge/de-dupe behavior, passwordless sudo in vibe mode, `acfs doctor --json` with zero failures and zero warnings, core stack binaries, Agent Mail health, systemd user services, the nightly timer, and a second idempotent installer run.

`tests/vm/test_factory_install_qemu.sh` is the local no-Docker version of that same gate. It downloads and verifies the official Ubuntu cloud image, boots it under QEMU/KVM with cloud-init and root SSH, then calls `test_factory_install_ubuntu.sh` against the VM. Use it when you need realistic systemd, sshd, cloud-init, kernel, and filesystem behavior without provisioning a paid VPS.

The slower OS upgrade/resume path is opt-in: the installer upgrades only when `--target-ubuntu=26.04` is passed, as the wizard's command does. Both harnesses accept `--target-ubuntu <ver>` and pass it to the installer on the first and the idempotency run; a provisioning packet whose `install.command` carries `--target-ubuntu=VER` supplies it automatically. The expected final release then defaults to the target (an explicit `--expect-final-ubuntu` still wins), and an upgrade without `--allow-install-reboot` is refused before any SSH or VM boot, because the run would otherwise be reported as an installer failure at the first reboot.

The matching GitHub Actions workflow is `.github/workflows/installer-factory-e2e.yml`. Its scheduled/manual default backend is QEMU/KVM with the official Ubuntu cloud image, but that backend requires `/dev/kvm`; set `ACFS_FACTORY_RUNNER`, pass the manual `runner` input, or pass `client_payload.runner` to select a KVM-capable larger/self-hosted runner. Leave the manual/reusable `runner` input blank when you want the repository variable to apply. Reusable workflow callers may run the QEMU backend without SSH secrets. The workflow writes and uploads only run-specific artifact directories so repeated runs on a reused self-hosted workspace do not collide with, or upload, old QEMU overlay disks. The QEMU wrapper keeps its generated private SSH key outside the repository checkout, and the factory harness redacts installer logs plus the remote diagnostic archive before local upload. Use `backend=real-host` for a disposable provider VPS. Configure `ACFS_FACTORY_SSH_PRIVATE_KEY` and either pass `ssh_target` via the `acfs-factory-host-ready` repository dispatch payload or configure `ACFS_FACTORY_SSH_TARGET` as a fallback secret. If `backend=real-host` is requested without those credentials, the workflow fails instead of reporting a skipped green canary. Do not point the scheduled real-host sentinel at a reused server; the harness intentionally fails when `ubuntu` already exists before install.

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
