# Ubuntu Upgrade Developer Documentation

This document covers the internal architecture and debugging procedures for the ACFS opt-in Ubuntu upgrade feature.

## Overview

Ordinary installs keep supported Ubuntu 22.04/24.04 LTS hosts on their current release. ACFS upgrades Ubuntu only when `--target-ubuntu=26.04` (or another supported LTS target) is passed explicitly, and `--skip-ubuntu-upgrade` suppresses that request in either argument order. Ubuntu 25.10 reached end-of-life on 2026-07-09; it is accepted only as a recovery source on the way to 26.04, never as a destination. The upgrade system handles:
- Reviewed LTS hops (22.04 → 24.04 → 26.04) and the 25.10 → 26.04 recovery hop. That hop moves 25.10's official archive URIs to old-releases.ubuntu.com only once old-releases actually serves `questing`; until Ubuntu archives it there, the regular archive still does, and sources are left alone. Stock 25.10 images ship uutils `env` 0.2 without `--default-signal`, so the installer's bootstrap handoff uses GNU `gnuenv` there.
- Automatic reboots after each upgrade
- Resume via systemd service
- State persistence across reboots

## Mixed Ubuntu archive suites (#463)

`acfs doctor` performs a read-only source audit on every normal run (including
JSON output), under `system.ubuntu_archive_suites`. It reads the installed
Ubuntu codename from `/etc/os-release`, then inspects enabled deb822 stanzas and
one-line entries in `/etc/apt/sources.list` and active `.list`/`.sources` files
in `/etc/apt/sources.list.d`. It reports filenames, line numbers and conflicting
suites. Commented entries, `Enabled: no` stanzas and backup/disabled filenames
are excluded. Malformed or unreadable active files require manual review.
Vendor suite labels alone never establish an Ubuntu mismatch. Official archive,
security, ports, old-releases, country archive endpoints and the Ubuntu mirror
list are recognized; independently hosted custom mirrors require manual
verification of their authenticated Release metadata (`Origin: Ubuntu`). A clean
audit does not establish package provenance or complete update delivery.

The specific legacy layout is an old-release `ubuntu.sources` alongside a
current-release `ubuntu-acfs-temp.sources`. ACFS versions before v0.10.0 could
restore the former after a successful upgrade. Current normal upgrades no longer
call that workaround. Updating ACFS alone does not reconcile these files.

### Manual recovery

Do this only after reviewing the actual contents and authorizing the specific
changes. Neither filename, nor the doctor's layout recognition, authorizes
deleting or disabling a repository. There is deliberately no automatic repair.

1. Confirm `ID=ubuntu`, `VERSION_ID` and `VERSION_CODENAME` in `/etc/os-release`
   agree with the completed upgrade and `/var/log/dist-upgrade/main.log`. If the
   upgrade is incomplete or metadata is ambiguous, stop and investigate it first.
2. Inventory **all** enabled entries, including custom mirrors and vendor
   repositories. Compare URIs, types (`deb`/`deb-src`), suites, components,
   architectures (including add/remove modifiers), Signed-By paths or inline
   keys, Trusted and all other options. Keep credentials out of shared reports.
   A missing Signed-By is not equivalent to an explicit keyring. Conflicting
   trust settings need an administrator's decision, not an automatic merge.
3. Back up `/etc/apt/sources.list` if present and the complete
   `/etc/apt/sources.list.d` directory, retaining ownership, modes, symlinks and
   contents, to a fresh root-owned directory outside the active source paths.
   Verify the backup and record every proposed changed file. Refuse existing
   backup or staging names. Retain this backup until validation is complete.
4. Stage a complete candidate source set outside `/etc/apt`. For each obsolete
   Ubuntu entry, decide whether to retarget it to the installed release or remove
   a verified duplicate from the candidate. Preserve every unique current-release
   repository, component, architecture and trust option, including entries in the
   temporary file. Keep unrelated vendor entries unchanged. Do not globally
   replace codenames, copy one file over another, or simply disable the temp file.
5. Validate candidate syntax and the full set for duplicate/trust conflicts.
   Test an authenticated refresh using APT's `Dir::Etc::sourcelist` and
   `Dir::Etc::sourceparts` pointing to the candidate, and `Dir::State::lists`
   pointing to a separate writable staging directory. Use
   `apt-get -o APT::Update::Error-Mode=any update` with those overrides; require
   exit status zero and no authentication errors. Never use `trusted=yes`,
   allow-insecure flags, or ignore a failed refresh to make validation pass.
6. With other package managers stopped, install the reviewed files preserving
   ownership/modes, using same-filesystem staged renames for individual files.
   Multiple source-file replacements are not one atomic transaction: keep APT
   idle until the entire set is installed. Run
   `sudo apt-get -o APT::Update::Error-Mode=any update` and require success, then
   rerun doctor and inspect `apt-cache policy` for obsolete origins.
7. On any failure, restore **every changed file** from the verified backup and
   remove only newly introduced files identified in your change inventory. Use
   same-filesystem staged restores, then refresh with error mode `any`. Report
   rollback refresh failures explicitly; do not claim successful recovery.
8. Separately review `apt-get -s full-upgrade` against the refreshed lists and
   installed package origins. Source reconciliation does not authorize package
   upgrades, removals or downgrades. The issue reporter's zero-change simulation
   applies only to that host's cache and package state.

## Architecture

### Components

```
scripts/lib/
├── ubuntu_upgrade.sh      # Core upgrade library (version detection, path calculation, execution)
├── upgrade_resume.sh      # Post-reboot resume logic
├── state.sh               # State persistence (upgrade progress tracking)
├── context.sh             # Error context tracking (try_step, set_phase)
├── report.sh              # Failure reporting
└── errors.sh              # Error pattern matching

/var/lib/acfs/             # Runtime state directory (created during upgrade)
├── state.json             # Main state file (upgrade progress, current phase)
├── upgrade_resume.sh      # Resume script (installed for systemd)
├── check_status.sh        # Status check script (for users)
└── env_snapshot.sh        # Environment variables snapshot

/etc/systemd/system/
└── acfs-upgrade-resume.service  # Oneshot service for post-reboot resume
```

### State Machine

```
┌─────────────────┐
│   not_started   │
└────────┬────────┘
         │ run_ubuntu_upgrade_phase()
         ▼
┌─────────────────┐
│    preparing    │ ← Preflight checks, snapshot recommendation
└────────┬────────┘
         │ ubuntu_start_upgrade_sequence()
         ▼
┌─────────────────┐
│   upgrading     │ ← do-release-upgrade running
└────────┬────────┘
         │ Upgrade completes
         ▼
┌─────────────────┐
│ awaiting_reboot │ ← Scheduled reboot pending
└────────┬────────┘
         │ System reboots
         ▼
┌─────────────────┐
│   resuming      │ ← acfs-upgrade-resume.service runs
└────────┬────────┘
         │ Check if more hops needed
         ├──────────────────────────────────┐
         │ (more hops)                      │ (at target)
         ▼                                  ▼
┌─────────────────┐               ┌─────────────────┐
│   upgrading     │               │    completed    │
└─────────────────┘               └────────┬────────┘
                                           │ Continue ACFS install
                                           ▼
                                  ┌─────────────────┐
                                  │  acfs_resumed   │
                                  └─────────────────┘
```

## Key Functions

### Version Detection

```bash
# Get version as comparable number (2404, 2604)
ubuntu_get_version_number  # Returns: 2404 for Ubuntu 24.04

# Get version as string ("24.04", "26.04")
ubuntu_get_version_string  # Returns: "24.04"

# Compare versions (expects NUMBERS, not strings)
ubuntu_version_gte 2404 2604  # Returns: 1 (false, 24.04 < 26.04)
```

### Upgrade Path Calculation

```bash
# Calculate upgrade path (returns newline-separated list)
ubuntu_calculate_upgrade_path 2604
# Output (from Ubuntu 22.04):
# 24.04
# 26.04
```

### State Management

```bash
# Set upgrade stage
state_upgrade_set_stage "upgrading"

# Record completed upgrade
state_upgrade_complete_hop "24.04"

# Get current stage
state_upgrade_get_stage  # Returns: upgrading, awaiting_reboot, etc.

# Get next target version
state_upgrade_get_next_target  # Returns: "26.04" or empty if done
```

## File Locations During Upgrade

| Path | Purpose | Created When |
|------|---------|--------------|
| `/var/lib/acfs/` | Runtime state directory | Upgrade starts |
| `/var/lib/acfs/state.json` | Upgrade progress state | Upgrade starts |
| `/var/lib/acfs/upgrade_resume.sh` | Resume script | Before first reboot |
| `/etc/systemd/system/acfs-upgrade-resume.service` | Systemd service | Before first reboot |
| `/var/log/acfs/upgrade_resume.log` | Resume script logs | Each reboot |
| `/var/log/acfs/install.log` | Main installer logs | Install start |
| `~/.acfs/state.json` | User-space state (post-upgrade) | ACFS install completes |

## Debugging Failed Upgrades

### Check Current Status

```bash
# Quick status check
/var/lib/acfs/check_status.sh

# View systemd service status
systemctl status acfs-upgrade-resume

# View resume service logs
journalctl -u acfs-upgrade-resume -n 50

# View detailed upgrade logs
cat /var/log/acfs/upgrade_resume.log

# View main state file
jq . /var/lib/acfs/state.json
```

### Common Failure Patterns

#### 1. do-release-upgrade Failed

**Symptoms:**
- State stuck in `upgrading`
- `/var/log/dist-upgrade/` contains error logs

**Resolution:**
```bash
# Check do-release-upgrade logs
cat /var/log/dist-upgrade/main.log

# Manually retry upgrade
do-release-upgrade -f DistUpgradeViewNonInteractive

# Or skip and continue ACFS
ts="$(date +%Y%m%d_%H%M%S)"
[ -f /var/lib/acfs/state.json ] && sudo mv /var/lib/acfs/state.json /var/lib/acfs/state.json.backup."$ts"
curl -fsSL .../install.sh | bash -s -- --yes --mode vibe --skip-ubuntu-upgrade
```

#### 2. Systemd Service Not Running

**Symptoms:**
- State shows `awaiting_reboot` but system rebooted
- No progress after reboot

**Resolution:**
```bash
# Check if service exists
systemctl status acfs-upgrade-resume

# Manually trigger resume
/var/lib/acfs/upgrade_resume.sh

# Check for service enable issues
systemctl is-enabled acfs-upgrade-resume
```

#### 3. Network Issues During Upgrade

**Symptoms:**
- `do-release-upgrade` fails with download errors

**Resolution:**
```bash
# Check network
ping archive.ubuntu.com

# Fix DNS
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf

# Retry
do-release-upgrade -f DistUpgradeViewNonInteractive
```

### Manual Recovery Steps

If the upgrade is stuck and you need to recover:

```bash
# 1. Check what state we're in
cat /var/lib/acfs/state.json | jq '.ubuntu_upgrade'

# 2. If stuck in awaiting_reboot, manually reboot
sudo reboot

# 3. If stuck in upgrading, check if upgrade completed
cat /etc/os-release | grep VERSION_ID

# 4. If at target version, manually update state
jq '.ubuntu_upgrade.current_stage = "completed" | .ubuntu_upgrade.needs_reboot = false' /var/lib/acfs/state.json > /tmp/state.json
sudo mv /tmp/state.json /var/lib/acfs/state.json

# 5. Disable the resume service
sudo systemctl disable acfs-upgrade-resume

# 6. Continue ACFS installation
curl -fsSL .../install.sh | bash -s -- --yes --mode vibe --skip-ubuntu-upgrade
```

### Force Clean Restart

To completely reset and start over:

```bash
# 1. Backup state files (recommended)
ts="$(date +%Y%m%d_%H%M%S)"
[ -d /var/lib/acfs ] && sudo mv /var/lib/acfs /var/lib/acfs.backup."$ts"
[ -f ~/.acfs/state.json ] && mv ~/.acfs/state.json ~/.acfs/state.json.backup."$ts"

# 2. Disable systemd service
sudo systemctl disable acfs-upgrade-resume 2>/dev/null
[ -f /etc/systemd/system/acfs-upgrade-resume.service ] && sudo mv /etc/systemd/system/acfs-upgrade-resume.service /etc/systemd/system/acfs-upgrade-resume.service.backup."$ts"
sudo systemctl daemon-reload

# 3. Start fresh
curl -fsSL .../install.sh | bash -s -- --yes --mode vibe
```

## Testing

### Unit Tests

```bash
# Run upgrade function tests
./tests/vm/test_ubuntu_upgrade_functions.sh
```

### Integration Testing

```bash
# Full upgrade simulation (requires Docker)
./tests/vm/test_upgrade_integration.sh
```

## CLI Flags

| Flag | Description |
|------|-------------|
| `--skip-ubuntu-upgrade` | Suppress an explicit upgrade request (wins in either argument order) |
| `--target-ubuntu=X.XX` | Opt into an upgrade to a supported LTS target (22.04, 24.04, or 26.04); without it, no upgrade runs |

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `UBUNTU_TARGET_VERSION` | Target version string | "26.04" |
| `UBUNTU_TARGET_VERSION_NUM` | Target version number (derived) | 2604 |
| `UBUNTU_UPGRADE_MIN_DISK_MB` | Minimum disk space for upgrade | 5000 |
| `ACFS_RESUME_DIR` | State directory | /var/lib/acfs |
| `ACFS_UPGRADE_LOCK` | Lock file path | /var/run/acfs-upgrade.lock |

## Security Considerations

- Upgrades run as root (required by do-release-upgrade)
- State files in `/var/lib/acfs/` are root-owned
- Resume script validates state before executing
- Lock file prevents concurrent upgrade attempts
- No secrets are stored in state files
