# Ubuntu upgrade entrypoint: supported targets and preserved checkpoints

The root installer's default destination is Ubuntu 26.04 LTS. An older supported
LTS destination is an explicit `--target-ubuntu=22.04` or `--target-ubuntu=24.04`
choice; `--skip-ubuntu-upgrade` suppresses a new distribution upgrade, not the
checks protecting an interrupted upgrade. An empty result or
failure while loading upgrade machinery, detecting the release, or computing
the upgrade path must not turn into a successful normal installation.

The existing release policy supplies these paths:

- 22.04 → 24.04 → 26.04.
- 24.04 → 26.04.
- 25.10 → 26.04, using the library's official EOL archive recovery.

25.10 is a recovery source, not a target or a successful newer-version no-op.
The entrypoint passes its validated destination to the library before loading
it. Package counts from `apt list` no longer decide whether to honor that
release destination. This change adds no development-release fallback.

## Checkpoints and recovery

The entrypoint reads existing system upgrade state before continuing. Invalid,
unsafe, unsupported-schema, or conflicting checkpoints are preserved and cause
a refusal. Missing jq must not make an existing checkpoint appear absent. Active
upgrades block a normal installation even on a fully patched LTS host.

A `pre_upgrade_reboot` checkpoint must agree with the requested destination.
Its stage is rechecked after acquiring the upgrade lock, and it is not cleared
until preflight and state validation succeed. A changed target, busy lock,
missing mandatory function, failed preflight, or failed state update does not
silently erase that checkpoint. An older completed checkpoint does not replace
the live OS version when a new supported upgrade is planned.

## Main workflow and minimal hosts

The normal installer checks the fixed system checkpoint before its install-lock
creation, generated-library loading, reset-state handling, Gum installation,
autofix, or package bootstrap. `--only`, `--only-phase`, and
`--skip-ubuntu-upgrade` cannot bypass an active or failed system-upgrade checkpoint.
Read-only listing, plan and print modes remain available for diagnosis.

After resolving selections, the installer validates privilege and target identity
and completes or delegates the upgrade phase before normal Gum, autofix and
dependency-install helpers. A requested reboot exits without running those
normal-install helpers. A failed upgrade returns failure rather than continuing.
This does not turn the initial remote source download into an offline operation
or hold the distribution-upgrade lock throughout every later installation phase.

An explicit `--target-ubuntu` still requests an upgrade with a narrow module or
phase selection. Without an explicit destination, narrow repairs do not initiate
a new distribution upgrade. An explicit `--skip-ubuntu-upgrade` wins over a new
upgrade request but never authorizes ignoring an unfinished checkpoint.

The upgrade phase bootstraps only its missing `jq` and `curl` prerequisites,
after source/root checks and lock acquisition. On Ubuntu 25.10 the library
recovers official APT locations before package acquisition. APT update uses
cooperative lock waiting and `APT::Update::Error-Mode=any`. Both binaries are
checked again after package installation; an exit-zero package command with a
missing binary is a failure, not permission to start the upgrade.

The policy loader does not accept an inherited "already loaded" flag. It sources
the verified library and propagates its return status explicitly, including when
called in a Bash conditional where errexit is suppressed.

Before a pre-upgrade reboot, persistent-directory creation, state validation,
checkpoint recording and resume-infrastructure setup must succeed. A failed
reboot delay or `shutdown` request returns failure and retains the checkpoint.
The optional MOTD update is not treated as evidence that a reboot was scheduled.
This is scheduling validation, not proof that a real reboot subsequently occurs.

## Verification and release requirements

In a disposable Linux container as root:

```bash
python3 tests/unit/test_ubuntu_upgrade_entrypoint.py
python3 tests/unit/test_ubuntu_upgrade_main.py
shellcheck install.sh
cd packages/manifest
bun run generate
bun run generate --validate
```

The regression suites extract the actual caller, loader, phase and policy
functions rather than sourcing the whole installer. They use real Bash control
flow, temporary install-lock files and jq checkpoint parsing. Connected tests run
those functions together, while substituting host identity, package operations,
upgrade locking, preflight, state writers and release execution. Test fixtures
redirect fixed reboot markers in memory, not through production environment
overrides. They do not upgrade a machine. Explicit test-only snapshot overrides
permit a documented partial-checkout run and must not be described as a full
installer, real release-upgrade, or boot/resume integration test.

Changing install.sh requires canonical regeneration of the internal checksum
ledger before publication or execution. Do not edit the ledger's hash by hand.
The full migration also requires the disposable-host upgrade/resume matrix,
bootstrap checks, generated-manifest validation, and external ACFS checker.
Unit tests alone do not certify a real host upgrade or close the migration bead.
