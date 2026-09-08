# Lesson 34: Disk Pressure Defense with SBH

skills:
  - sbh
  - system-tools
  - reliability

---

# What is SBH?

Ever had a build fail because /tmp filled up, or lost work because the disk hit 100%? SBH prevents that.

**SBH (Storage Ballast Helper)** pre-allocates a configurable ballast file on disk. When free space drops below a threshold, SBH automatically shrinks the ballast to free space, giving your system breathing room before a real out-of-space crash.

---

# Checking Installation

Verify SBH is installed:

```bash
sbh --help
```

---

# Checking Status

See current disk usage and ballast state:

```bash
sbh status
```

This shows free space, ballast size, and whether protection is active.

---

# How It Works

SBH creates a ballast file (default: 2 GB) that acts as an emergency reserve:

1. Normal operation: ballast file sits idle, occupying reserved space
2. Disk pressure: SBH detects low free space and shrinks the ballast
3. Recovery: once space is freed, SBH restores the ballast

---

# Why SBH Matters for Agents

AI coding agents generate large build artifacts, download dependencies, and create temporary files. SBH protects against:

- Cargo builds filling up /tmp
- Node modules exhausting disk space
- Docker images consuming all storage
- Lost work from out-of-space filesystem errors

---

# Common Scenarios

```bash
# Check current protection status
sbh status

# Manually release one ballast file to free space right now
sbh ballast release 1

# Disk already full? Zero-write recovery of stale build artifacts
sbh emergency

# Re-provision the ballast once you have freed disk space
sbh ballast replenish
```

`sbh ballast status` shows the ballast inventory, and anything `sbh clean`
quarantined comes back with `sbh undo`.

---

# Summary

You've learned:
1. **sbh status** - Check disk protection state
2. **sbh ballast release** / **sbh emergency** - Emergency space recovery
3. **sbh ballast replenish** - Re-enable protection
4. How ballast files prevent out-of-space crashes during builds
