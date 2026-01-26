# ACFS Doctor --fix: Safe Fixer Specification

> **Bead**: bd-31ps.6.1
> **Status**: Implementation spec for `acfs doctor --fix`

## Overview

This document defines the safe fixer whitelist and policy for `acfs doctor --fix`.
All fixers integrate with the autofix system (`scripts/lib/autofix.sh`) for:
- Crash-safe I/O with explicit fsync
- SHA256-verified backups before modifications
- Change recording with undo capability
- Automatic rollback on failure

## Fixer Categories

### Category 1: Safe Auto-Fix (runs with `--yes` or `--fix`)

These fixers are deterministic, idempotent, and safe to run automatically.

| Fixer ID | Check ID Pattern | Description | Undo Strategy |
|----------|------------------|-------------|---------------|
| `fix.path.ordering` | `path.*` | Prepend missing dirs to PATH in shell config | Restore backup |
| `fix.config.copy` | `config.*` | Copy missing ~/.acfs config files | Remove copied file |
| `fix.dcg.hook` | `hook.dcg.*` | Install DCG pre-tool-use hook | Run `dcg uninstall` |
| `fix.symlink.create` | `symlink.*` | Create missing tool symlinks | Remove symlink |
| `fix.plugin.clone` | `shell.plugins.*` | Clone missing zsh plugins | Remove cloned dir |
| `fix.acfs.sourcing` | `shell.acfs_sourced` | Add ACFS sourcing to .zshrc | Remove added lines |

### Category 2: Prompt Required (requires confirmation even with `--yes`)

These fixers modify user configuration files and need explicit approval.

| Fixer ID | Check ID Pattern | Description | Guard Condition |
|----------|------------------|-------------|-----------------|
| `fix.shell.rc` | `shell.rc.*` | Modify ~/.bashrc or ~/.zshrc | Always prompt |
| `fix.shell.default` | `shell.default` | Change default shell to zsh | Interactive only |

### Category 3: Manual Only (never auto-fix)

These operations require human judgment or elevated privileges.

| Check Pattern | Reason |
|---------------|--------|
| `*.sudo_required` | Needs root - prompt to run manually |
| `*.apt_install` | Package manager - suggest command |
| `*.service_restart` | Service management - suggest command |
| `*.file_delete` | Destructive - never auto-delete |

## Fixer Implementation Details

### 1. `fix.path.ordering` - PATH Directory Prepending

**Check**: Shell config doesn't have required directories at front of PATH

**Required directories** (in order):
```bash
$HOME/.local/bin
$HOME/.bun/bin
$HOME/.cargo/bin
$HOME/go/bin
$HOME/.atuin/bin
```

**Fix logic**:
```bash
# Guard: Only fix if directory exists and not already at front of PATH
fix_path_ordering() {
    local target_file="$HOME/.zshrc"
    local dirs_to_add=("$HOME/.local/bin" "$HOME/.bun/bin" ...)

    # Create backup via autofix
    local backup_json
    backup_json=$(create_backup "$target_file" "path-ordering")

    # Build PATH export line
    local export_line='export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"'

    # Append to file if not already present
    if ! grep -qF "$export_line" "$target_file"; then
        echo "" >> "$target_file"
        echo "# ACFS PATH ordering (added by doctor --fix)" >> "$target_file"
        echo "$export_line" >> "$target_file"
    fi

    # Record change with undo command
    record_change "path" "Added PATH ordering to $target_file" \
        "sed -i '/# ACFS PATH ordering/,/^export PATH/d' '$target_file'" \
        false "info" "[\"$target_file\"]" "$backup_json" "[]"
}
```

**Undo**: Restore from backup or remove added lines

---

### 2. `fix.config.copy` - Missing Config File Copy

**Check**: Required config files missing from ~/.acfs/

**Files to check**:
| Source | Destination |
|--------|-------------|
| `acfs/zsh/acfs.zshrc` | `~/.acfs/zsh/acfs.zshrc` |
| `acfs/tmux/tmux.conf` | `~/.acfs/tmux/tmux.conf` |
| `VERSION` | `~/.acfs/VERSION` |

**Fix logic**:
```bash
fix_config_copy() {
    local src="$1"
    local dest="$2"

    # Guard: Source must exist, dest must not
    [[ -f "$src" ]] || return 1
    [[ ! -f "$dest" ]] || return 0  # Already exists, skip

    # Ensure parent directory exists
    mkdir -p "$(dirname "$dest")"

    # Copy file
    cp -p "$src" "$dest"

    # Record change
    record_change "config" "Copied config: $(basename "$src")" \
        "rm -f '$dest'" \
        false "info" "[\"$dest\"]" "[]" "[]"
}
```

**Undo**: Remove copied file

---

### 3. `fix.dcg.hook` - DCG Hook Installation

**Check**: DCG hook not registered in Claude Code settings

**Fix logic**:
```bash
fix_dcg_hook() {
    # Guard: dcg command must exist
    command -v dcg &>/dev/null || return 1

    # Check if already installed
    if dcg doctor --format json 2>/dev/null | jq -e '.hook_installed == true' &>/dev/null; then
        return 0  # Already installed
    fi

    # Install hook
    dcg install

    # Record change
    record_change "hook" "Installed DCG pre-tool-use hook" \
        "dcg uninstall" \
        false "info" "[]" "[]" "[]"
}
```

**Undo**: Run `dcg uninstall`

---

### 4. `fix.symlink.create` - Missing Tool Symlinks

**Check**: Tool binary exists but symlink missing from PATH

**Common symlinks**:
| Binary Location | Symlink |
|-----------------|---------|
| `~/.cargo/bin/br` | `~/.local/bin/br` |
| `~/.cargo/bin/bv` | `~/.local/bin/bv` |

**Fix logic**:
```bash
fix_symlink_create() {
    local binary="$1"
    local symlink="$2"

    # Guard: Binary must exist, symlink must not
    [[ -x "$binary" ]] || return 1
    [[ ! -e "$symlink" ]] || return 0  # Already exists

    # Ensure symlink directory exists
    mkdir -p "$(dirname "$symlink")"

    # Create symlink
    ln -s "$binary" "$symlink"

    # Record change
    record_change "symlink" "Created symlink: $(basename "$symlink")" \
        "rm -f '$symlink'" \
        false "info" "[\"$symlink\"]" "[]" "[]"
}
```

**Undo**: Remove symlink

---

### 5. `fix.plugin.clone` - Missing Zsh Plugins

**Check**: Zsh plugin directory doesn't exist

**Plugins**:
| Plugin | Repo URL |
|--------|----------|
| zsh-autosuggestions | https://github.com/zsh-users/zsh-autosuggestions |
| zsh-syntax-highlighting | https://github.com/zsh-users/zsh-syntax-highlighting |

**Fix logic**:
```bash
fix_plugin_clone() {
    local plugin_name="$1"
    local repo_url="$2"
    local plugins_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"
    local target_dir="$plugins_dir/$plugin_name"

    # Guard: Must not already exist
    [[ ! -d "$target_dir" ]] || return 0

    # Clone plugin
    git clone --depth 1 "$repo_url" "$target_dir"

    # Record change
    record_change "plugin" "Cloned zsh plugin: $plugin_name" \
        "rm -rf '$target_dir'" \
        false "info" "[\"$target_dir\"]" "[]" "[]"
}
```

**Undo**: Remove cloned directory

---

### 6. `fix.acfs.sourcing` - ACFS Config Sourcing

**Check**: ~/.zshrc doesn't source ACFS config

**Expected line**:
```bash
[[ -f ~/.acfs/zsh/acfs.zshrc ]] && source ~/.acfs/zsh/acfs.zshrc
```

**Fix logic**:
```bash
fix_acfs_sourcing() {
    local zshrc="$HOME/.zshrc"
    local source_line='[[ -f ~/.acfs/zsh/acfs.zshrc ]] && source ~/.acfs/zsh/acfs.zshrc'

    # Guard: Check if already sourced
    if grep -qF "acfs.zshrc" "$zshrc" 2>/dev/null; then
        return 0  # Already present
    fi

    # Create backup
    local backup_json
    backup_json=$(create_backup "$zshrc" "acfs-sourcing")

    # Append sourcing line
    echo "" >> "$zshrc"
    echo "# ACFS configuration (added by doctor --fix)" >> "$zshrc"
    echo "$source_line" >> "$zshrc"

    # Record change
    record_change "config" "Added ACFS sourcing to .zshrc" \
        "sed -i '/# ACFS configuration/,+1d' '$zshrc'" \
        false "info" "[\"$zshrc\"]" "$backup_json" "[]"
}
```

**Undo**: Restore backup or remove added lines

---

## Dry-Run Report Format

When `--dry-run` is specified, output actions without applying:

```
DRY-RUN: acfs doctor --fix

Would apply the following fixes:

  [fix.path.ordering]
    Action: Prepend PATH directories to ~/.zshrc
    Files: ~/.zshrc
    Backup: Yes (SHA256 verified)
    Undo: sed -i '/# ACFS PATH/,/^export PATH/d' ~/.zshrc

  [fix.config.copy]
    Action: Copy acfs.zshrc to ~/.acfs/zsh/
    Files: ~/.acfs/zsh/acfs.zshrc
    Backup: N/A (new file)
    Undo: rm -f ~/.acfs/zsh/acfs.zshrc

  [fix.dcg.hook]
    Action: Install DCG pre-tool-use hook
    Files: ~/.config/claude-code/settings.json
    Backup: N/A (dcg manages)
    Undo: dcg uninstall

Fixes that require confirmation (--prompt):
  [fix.shell.default]
    Action: Change default shell to zsh
    Command: chsh -s $(which zsh)

Manual fixes (not auto-applied):
  [shell.ohmyzsh]
    Status: FAIL
    Suggestion: curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | bash

Summary: 3 auto-fixes, 1 prompted, 2 manual
```

---

## Rollback Strategy

All fixers use the autofix system for rollback capability:

1. **Before any fix**: `start_autofix_session()` is called
2. **Before file modification**: `create_backup()` creates SHA256-verified backup
3. **After each fix**: `record_change()` logs the change with undo command
4. **On failure**: `rollback_all_on_failure()` reverts all changes in reverse order
5. **On success**: `print_undo_summary()` shows what was changed and how to undo

### User-Initiated Undo

```bash
# List all changes
acfs undo --list

# Undo specific change
acfs undo chg_0001

# Undo all changes from a session
acfs undo --all

# Dry-run undo
acfs undo --dry-run chg_0001
```

---

## CLI Interface

```bash
# Run doctor with auto-fix
acfs doctor --fix

# Preview fixes without applying
acfs doctor --fix --dry-run

# Auto-approve safe fixes
acfs doctor --fix --yes

# JSON output for scripting
acfs doctor --fix --json

# Fix specific category only
acfs doctor --fix --only path,config
```

---

## Safety Invariants

1. **Never delete user files** - Only create, modify, or symlink
2. **Always backup before modify** - SHA256-verified backups
3. **Idempotent** - Safe to run multiple times
4. **Logged** - All changes recorded to `~/.local/share/acfs/doctor.log`
5. **Reversible** - Every fix has an undo command
6. **Non-destructive** - Package installs and sudo operations are suggestions only

---

## Testing Requirements

1. **Unit tests** for each fixer function
2. **Guard condition tests** - Verify fixers don't run when condition not met
3. **Idempotency tests** - Run fixer twice, second run is no-op
4. **Rollback tests** - Verify undo commands work correctly
5. **Dry-run tests** - Verify output format without side effects
6. **Integration tests** - Break tool, run doctor --fix, verify fixed
