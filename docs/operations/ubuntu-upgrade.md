# Ubuntu Auto-Upgrade Developer Documentation

This document covers the internal architecture and debugging procedures for the ACFS Ubuntu auto-upgrade feature.

## Overview

ACFS automatically upgrades Ubuntu to version 25.10 before running the main installation. The upgrade system handles:
- Multi-hop upgrades (e.g., 24.04 → 25.04 → 25.10; EOL interim releases like 24.10 may be skipped)
- Automatic reboots after each upgrade
- Resume via systemd service
- State persistence across reboots

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
# Get version as comparable number (2404, 2510)
ubuntu_get_version_number  # Returns: 2404 for Ubuntu 24.04

# Get version as string ("24.04", "25.10")
ubuntu_get_version_string  # Returns: "24.04"

# Compare versions (expects NUMBERS, not strings)
ubuntu_version_gte 2404 2510  # Returns: 1 (false, 24.04 < 25.10)
```

### Upgrade Path Calculation

```bash
# Calculate upgrade path (returns newline-separated list)
ubuntu_calculate_upgrade_path 2510
# Output (from Ubuntu 24.04):
# 25.04
# 25.10
```

### State Management

```bash
# Set upgrade stage
state_upgrade_set_stage "upgrading"

# Record completed upgrade
state_upgrade_complete_hop "25.04"

# Get current stage
state_upgrade_get_stage  # Returns: upgrading, awaiting_reboot, etc.

# Get next target version
state_upgrade_get_next_target  # Returns: "25.10" or empty if done
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
| `--skip-ubuntu-upgrade` | Skip automatic Ubuntu upgrade entirely |
| `--target-ubuntu=X.XX` | Set target version (default: 25.10) |

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `UBUNTU_TARGET_VERSION` | Target version string | "25.10" |
| `UBUNTU_TARGET_VERSION_NUM` | Target version number | 2510 |
| `UBUNTU_UPGRADE_MIN_DISK_MB` | Minimum disk space for upgrade | 5000 |
| `ACFS_RESUME_DIR` | State directory | /var/lib/acfs |
| `ACFS_UPGRADE_LOCK` | Lock file path | /var/run/acfs-upgrade.lock |

## Security Considerations

- Upgrades run as root (required by do-release-upgrade)
- State files in `/var/lib/acfs/` are root-owned
- Resume script validates state before executing
- Lock file prevents concurrent upgrade attempts
- No secrets are stored in state files
