# Plan: Single Source of Truth Manifest Architecture

## Executive Summary

Transform the manifest system from "documentation that generates unused scripts" into the **actual driver** of installation.

The manifest becomes the canonical definition of:
- what gets installed
- how it gets installed (including run-as + verified upstream installers)
- how it is verified (doctor checks)
- how it is selected/filtered (only/skip/phase with dependency closure)

`install.sh` becomes a thin orchestration layer that:
- bootstraps a **self-consistent** copy of the repo in `curl|bash` mode (single archive download; no piecemeal raw-file sourcing)
- sources shared libs + generated installers (as local files)
- performs hand-maintained orchestration steps (user normalization, finalization, UX)
- calls generated module functions in a deterministic order

## Project Policies (Non-Negotiable)

- **No outside contributors:** ACFS is maintained internally. Do not add contributing guides, “PRs welcome” language, or any workflow/documentation aimed at external contributors.
- **`curl | bash` is the primary entrypoint:** The design must work when `install.sh` runs without a local checkout (i.e., `SCRIPT_DIR` may be empty).
- **Generated scripts are libraries:** Generated `scripts/generated/*.sh` must be safely `source`-able (no global `set -euo pipefail`, no top-level side effects, and contract validation must `return`, not `exit`).
- **Deterministic generation:** Generated scripts must not embed timestamps or non-deterministic content; CI drift checks require stable output for a given manifest input.
- **No implicit “set -e” landmines:** Generated module functions must explicitly handle errors (so `install.sh` can keep strict mode without optional modules accidentally terminating the whole run).
- **Bootstrap must be atomic + validated before sourcing:** Never `source` partially-downloaded files. Download → validate (`bash -n`) → atomically rename → then `source`.
- **CLI compatibility:** Existing installer flags and wizard flows must continue to work. New generic `--only/--skip` is additive; any legacy flags must be implemented as wrappers over manifest-driven selection (no behavior drift).

## Non-Goals

- Not rewriting the installer in TypeScript or requiring Bun on the target VPS before base packages are installed.
- Not supporting non-Ubuntu targets.
- Not building a backend service for installs (installer remains standalone Bash).
- Not changing the “internal-only maintenance” posture.

## Definitions

- **Module:** A single manifest-defined unit of installation + verification (`id`, `install`, `verify`, etc.).
- **Orchestration step:** Hand-maintained installer logic that is intentionally *not* a module (e.g., root→ubuntu normalization).
- **Phase:** A coarse install ordering group (1–10). Modules must declare a phase (or be orchestration-only).
- **Category:** A human grouping (base/shell/lang/etc). Useful for generated file layout, not ordering.
- **Verified installer:** An upstream script executed only after HTTPS + SHA256 verification against `checksums.yaml`.

---

## Module Taxonomy (Phase 0 Spec)

This section defines the canonical categories, tags, and default behaviors for manifest modules.

### Canonical Categories

Categories determine generated file layout (`scripts/generated/install_<category>.sh`) and provide logical grouping:

| Category | Description | Generated File | Phase |
|----------|-------------|----------------|-------|
| `base` | System foundation (apt packages, filesystem) | `install_base.sh` | 1, 3 |
| `shell` | Shell environment (zsh, oh-my-zsh, p10k) | `install_shell.sh` | 4 |
| `cli` | Modern CLI tools (ripgrep, fzf, etc.) | `install_cli.sh` | 5 |
| `lang` | Language runtimes (bun, uv, rust, go) | `install_lang.sh` | 6 |
| `agents` | Coding agents (claude, codex, gemini) | `install_agents.sh` | 7 |
| `cloud` | Cloud & database tools | `install_cloud.sh` | 8 |
| `stack` | Dicklesworthstone stack (ntm, bv, cass, etc.) | `install_stack.sh` | 9 |
| `acfs` | ACFS finalization (onboard, doctor) | `install_acfs.sh` | 10 |

**Notes:**
- `users` (e.g., `users.ubuntu`) is an **orchestration-only** category with `generated: false`
- `tools` modules (e.g., `tools.atuin`) are merged into `lang` or `cli` based on their nature
- `db` modules (e.g., `db.postgres18`) are merged into `cloud` category

### Canonical Tags

Tags enable flexible filtering and behavior classification:

| Tag | Description | Usage |
|-----|-------------|-------|
| `critical` | MUST succeed for system to work | `is_critical_tool()` in `scripts/lib/tools.sh` |
| `recommended` | Safe to skip with warning | Default for optional tools |
| `runtime` | Language runtime or manager | `lang.bun`, `lang.rust`, etc. |
| `agent` | AI coding assistant | `agents.*` modules |
| `cloud` | Cloud provider CLI | `cloud.*` modules |
| `database` | Database server or client | `db.postgres18` |
| `shell-ux` | Shell enhancements | `tools.atuin`, `tools.zoxide`, `shell.zsh` |
| `cli-modern` | Modern CLI replacements | `bat`, `eza`, `ripgrep`, `fd` |
| `orchestration` | Not generated; hand-maintained | `users.ubuntu`, `base.filesystem` (partial) |
| `optional` | Explicitly opt-in only | Modules with `enabled_by_default: false` |

### Default Install Policy (`enabled_by_default`)

Controls whether a module is included in the default install:

| Pattern | `enabled_by_default` | Rationale |
|---------|---------------------|-----------|
| `base.*` | `true` | Required for system |
| `shell.*` | `true` | Required for shell UX |
| `cli.modern` | `true` | Core developer UX |
| `lang.*` | `true` | Required by agents and stack |
| `tools.atuin` | `true` | Core shell history UX |
| `tools.zoxide` | `true` | Core navigation UX |
| `tools.ast_grep` | `true` | Required by UBS |
| `agents.*` | `true` | Core workflow |
| `stack.*` | `true` | Core workflow (Dicklesworthstone stack) |
| `acfs.*` | `true` | ACFS finalization |
| `db.postgres18` | **`false`** | Heavy; `--skip-postgres` exists |
| `tools.vault` | **`false`** | Specialized; `--skip-vault` exists |
| `cloud.*` | **`false`** | Specialized; `--skip-cloud` exists |

**Rationale for opt-out defaults:**
- PostgreSQL 18 is a heavy install (~500MB) that many users don't need
- Vault is specialized for secrets management workflows
- Cloud CLIs (wrangler, supabase, convex, vercel) are only needed for specific providers

### Legacy Flag → Module/Tag Mapping

Preserve existing CLI ergonomics while migrating to manifest-driven selection:

| Legacy Flag | New Behavior | Implementation |
|-------------|--------------|----------------|
| `--skip-postgres` | `--skip db.postgres18` | Map in `parse_args` |
| `--skip-vault` | `--skip tools.vault` | Map in `parse_args` |
| `--skip-cloud` | `--skip cloud.wrangler,cloud.supabase,cloud.convex,cloud.vercel` OR `--skip-tag cloud` | Map in `parse_args` |
| `--skip-preflight` | Orchestrator flag (not module-related) | Keep as-is |
| `--mode vibe` | Sets `MODE=vibe` env var | Keep as-is |
| `--mode safe` | Sets `MODE=safe` env var | Keep as-is |

**New generic flags (additive):**
- `--only <id1,id2,...>` — Install only specified modules + their dependencies
- `--skip <id1,id2,...>` — Skip specified modules (fails if skipping required deps)
- `--only-phase <N,...>` — Install only specified phases
- `--skip-tag <tag>` — Skip all modules with given tag
- `--no-deps` — Expert-only: disable automatic dependency expansion
- `--print-plan` — Show execution plan and exit
- `--list-modules` — List all modules with their metadata

### Category → Install.sh Phase Mapping

How categories map to install.sh phases:

| Phase | Categories | Description |
|-------|------------|-------------|
| 1 | `base` (system) | Base apt packages |
| 2 | — | User normalization (orchestration) |
| 3 | `base` (filesystem) | Filesystem setup |
| 4 | `shell` | Zsh + oh-my-zsh + plugins |
| 5 | `cli` | Modern CLI tools |
| 6 | `lang` | Language runtimes + tools |
| 7 | `agents` | Coding agents |
| 8 | `cloud` | Cloud & database tools |
| 9 | `stack` | Dicklesworthstone stack |
| 10 | `acfs` | Finalization |

### Category → Wizard Step Mapping

For website wizard progress display (step 8 "Run Installer"):

| Category | Wizard Display | Visibility |
|----------|---------------|------------|
| `base` | "Installing base packages..." | Progress only |
| `shell` | "Setting up shell..." | Progress only |
| `cli` | "Installing CLI tools..." | Progress only |
| `lang` | "Installing language runtimes..." | Visible (Bun, uv, Rust, Go) |
| `agents` | "Installing coding agents..." | Visible (Claude, Codex, Gemini) |
| `cloud` | "Installing cloud tools..." | Visible if enabled |
| `stack` | "Installing agent stack..." | Visible (NTM, beads, etc.) |
| `acfs` | "Finalizing..." | Progress only |

### Critical vs Recommended Classification

Alignment with `scripts/lib/tools.sh`:

| Classification | Tags | Behavior on Failure |
|----------------|------|---------------------|
| CRITICAL | `critical` | Abort installation |
| RECOMMENDED | `recommended` | Log warning, continue |
| (unclassified) | — | Treat as RECOMMENDED |

**CRITICAL tools** (from `scripts/lib/tools.sh`):
- `git`, `curl` — Network/VCS foundation
- `bun` — JS runtime, required by many installs
- `uv` — Python tooling
- `go` — Go compiler, required by lazygit etc.
- `zsh` — Target shell
- `mise`, `rustup`, `cargo` — Runtime managers

All other tools are RECOMMENDED (can skip on failure).

---

## Selection Contract (Phase 0 Spec)

This section defines the exact semantics for module filtering, dependency resolution, and plan computation.

### CLI Input Flags

| Flag | Type | Description |
|------|------|-------------|
| `--only <ids>` | Filter | Install ONLY these modules (+ deps unless `--no-deps`) |
| `--only-phase <nums>` | Filter | Install ONLY modules in these phases (+ deps) |
| `--skip <ids>` | Filter | Skip these modules (fails if required dep) |
| `--skip-tag <tag>` | Filter | Skip all modules with this tag |
| `--no-deps` | Modifier | Disable automatic dependency expansion (expert-only) |
| `--print-plan` | Introspection | Print execution plan and exit |
| `--list-modules` | Introspection | List all modules with metadata and exit |

**Legacy flags (mapped internally):**
- `--skip-postgres` → `--skip db.postgres18`
- `--skip-vault` → `--skip tools.vault`
- `--skip-cloud` → `--skip cloud.wrangler,cloud.supabase,cloud.convex,cloud.vercel`

### Selection Algorithm

```
1. INITIALIZE starting_set:
   - If --only provided: starting_set = {explicit module IDs}
   - If --only-phase provided: starting_set = {modules in those phases}
   - Else: starting_set = {modules where enabled_by_default=true}

2. EXPAND dependencies (unless --no-deps):
   - For each module in starting_set:
     - Add all transitive dependencies (from ACFS_MODULE_DEPS)
     - Dependencies are added even if enabled_by_default=false

3. APPLY skips:
   - For each module in --skip:
     - If module is a required dependency of any remaining module:
       - FAIL EARLY: "Cannot skip X: required by Y"
     - Else: Remove from set

4. VALIDATE:
   - If any module ID in --only/--skip is unknown: FAIL EARLY
   - If any phase in --only-phase is invalid (not 1-10): FAIL EARLY

5. OUTPUT:
   - ACFS_EFFECTIVE_RUN[module_id]=1  (hash for O(1) membership test)
   - ACFS_EFFECTIVE_PLAN=(...)        (ordered list, filtered from ACFS_MODULES_IN_ORDER)
```

### Output Structures

```bash
# Populated by acfs_resolve_selection() after sourcing manifest_index.sh

# Fast membership test (assoc array)
declare -A ACFS_EFFECTIVE_RUN=(
    [base.system]=1
    [base.filesystem]=1
    [lang.bun]=1
    # ...
)

# Ordered execution plan (array, subset of ACFS_MODULES_IN_ORDER)
ACFS_EFFECTIVE_PLAN=(
    base.system
    base.filesystem
    shell.zsh
    lang.bun
    # ...
)

# Optional: diagnostic info for --print-plan
declare -A ACFS_PLAN_REASON=(
    [base.system]="default"
    [lang.bun]="only"
    [lang.rust]="dep:lang.bun"
    # ...
)
```

### Golden Path Examples

#### 1. Default Install (No Flags)
```bash
./install.sh --yes --mode vibe
```
- Selection: All modules with `enabled_by_default: true`
- Result: Full stack (base, shell, cli, lang, agents, stack, acfs)
- Skipped: `db.postgres18`, `tools.vault`, `cloud.*` (opt-in)

#### 2. Install Single Module with Dependencies
```bash
./install.sh --only lang.bun
```
- Starting set: `{lang.bun}`
- Dependency expansion: Adds `base.system` (implicit dep for all)
- Result: `base.system → lang.bun`

#### 3. Install Module WITHOUT Dependencies (Expert)
```bash
./install.sh --only lang.bun --no-deps
```
- **WARNING:** "Running without dependency expansion. Module may fail if prerequisites missing."
- Starting set: `{lang.bun}` (no expansion)
- Result: Only `lang.bun` (may fail if `curl` not present)

#### 4. Skip a Module That's a Dependency (FAIL)
```bash
./install.sh --only lang.bun --skip base.system
```
- **ERROR:** "Cannot skip base.system: required by lang.bun"
- Exit code: 1 (installation aborts before any work)

#### 5. Install Only Cloud Tools (Opt-in)
```bash
./install.sh --only cloud.wrangler,cloud.supabase,cloud.convex,cloud.vercel
```
- Starting set: `{cloud.wrangler, cloud.supabase, cloud.convex, cloud.vercel}`
- Dependency expansion: Adds `base.system`, `lang.bun` (required by Bun CLIs)
- Result: `base.system → lang.bun → cloud.wrangler → cloud.supabase → cloud.convex → cloud.vercel`

#### 6. Legacy Flag Equivalence
```bash
# Old way
./install.sh --skip-postgres --skip-cloud

# Equivalent new way
./install.sh --skip db.postgres18 --skip-tag cloud
```
- Both produce identical `ACFS_EFFECTIVE_PLAN`

#### 7. Print Plan Without Running
```bash
./install.sh --print-plan --only lang.bun
```
- Output (human-readable, stable ordering):
```
ACFS Installation Plan
======================
Phase 1: Base
  ✓ base.system (dependency of lang.bun)

Phase 6: Languages
  ✓ lang.bun (explicitly requested)

Total: 2 modules
```
- **No side effects:** Does not modify state.json, does not require preflight

### Error Messages

| Condition | Message | Exit Code |
|-----------|---------|-----------|
| Unknown module in `--only` | `Unknown module: foo.bar (not in manifest)` | 1 |
| Unknown module in `--skip` | `Unknown module: foo.bar (not in manifest)` | 1 |
| Invalid phase | `Invalid phase: 15 (must be 1-10)` | 1 |
| Skip required dep | `Cannot skip base.system: required by lang.bun, agents.claude` | 1 |
| `--no-deps` warning | `WARNING: Running without dependency expansion. Modules may fail if prerequisites are missing.` | (continues) |

### Interaction with State/Resume

Selection computes the **full effective plan** regardless of resume state:
- Resume logic (from `state.json`) determines the **starting point** within that plan
- If flags change what would run, `--print-plan` shows the new plan
- Selection does NOT modify `state.json`

Example:
```bash
# First run: interrupted after phase 4
./install.sh --mode vibe
# ^C

# Resume: same plan, starts from phase 5
./install.sh --resume

# Changed flags: different plan, starts from beginning
./install.sh --only lang.bun
# Warns: "Previous state.json exists but --only changes the plan. Starting fresh."
```

### Implementation Location

| Component | Location | Responsibility |
|-----------|----------|----------------|
| `acfs_resolve_selection()` | `scripts/lib/install_helpers.sh` | Algorithm implementation |
| `should_run_module()` | `scripts/lib/install_helpers.sh` | O(1) membership test |
| `ACFS_MODULE_DEPS` | `scripts/generated/manifest_index.sh` | Dependency graph data |
| `ACFS_MODULES_IN_ORDER` | `scripts/generated/manifest_index.sh` | Topological order data |
| `parse_args()` | `install.sh` | CLI parsing + legacy flag mapping |

---

## Bootstrap Contract (Phase 0 Spec)

This section defines the `curl | bash` bootstrap process for atomic, validated, self-consistent installs.

### Core Principle: Never Source from Network

```bash
# WRONG: Race conditions, partial downloads, mixed refs
source <(curl -fsSL https://example.com/script.sh)

# RIGHT: Download → Validate → Extract → Validate → Source
curl -fsSL "$ARCHIVE_URL" -o "$TMP_ARCHIVE"
# ... validation steps ...
source "$ACFS_LIB_DIR/security.sh"
```

### Required Environment Variables

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `ACFS_REPO_OWNER` | Yes | GitHub org/user | `Dicklesworthstone` |
| `ACFS_REPO_NAME` | Yes | Repository name | `agentic_coding_flywheel_setup` |
| `ACFS_REF` | Yes | Branch, tag, or SHA | `main`, `v1.2.3`, `abc1234` |
| `ACFS_BOOTSTRAP_DIR` | No | Override temp dir | `/tmp/acfs-bootstrap` |
| `ACFS_KEEP_BOOTSTRAP` | No | Keep extracted tree | `1` (for debugging) |

### Archive Download URL

```bash
# GitHub archive URL (single ref, atomic snapshot)
ARCHIVE_URL="https://github.com/${ACFS_REPO_OWNER}/${ACFS_REPO_NAME}/archive/${ACFS_REF}.tar.gz"
```

### Bootstrap Sequence (Pseudocode)

```bash
acfs_bootstrap() {
    # 1. CREATE TEMP DIRECTORY
    ACFS_BOOTSTRAP_DIR="${ACFS_BOOTSTRAP_DIR:-$(mktemp -d -t acfs-bootstrap.XXXXXX)}"
    trap 'rm -rf "$ACFS_BOOTSTRAP_DIR"' EXIT  # cleanup unless ACFS_KEEP_BOOTSTRAP

    # 2. DOWNLOAD ARCHIVE
    local archive_file="$ACFS_BOOTSTRAP_DIR/archive.tar.gz"
    if ! curl -fsSL --max-time 60 "$ARCHIVE_URL" -o "$archive_file"; then
        fail "BOOTSTRAP_DOWNLOAD_FAILED: Could not download archive from $ARCHIVE_URL"
    fi

    # 3. VALIDATE ARCHIVE (basic check)
    if ! file "$archive_file" | grep -q "gzip compressed"; then
        fail "BOOTSTRAP_INVALID_ARCHIVE: Downloaded file is not a valid gzip archive"
    fi

    # 4. EXTRACT ARCHIVE
    local extract_dir="$ACFS_BOOTSTRAP_DIR/extracted"
    if ! tar -xzf "$archive_file" -C "$ACFS_BOOTSTRAP_DIR"; then
        fail "BOOTSTRAP_EXTRACT_FAILED: Could not extract archive"
    fi
    # GitHub archives extract to repo-ref/ directory
    extract_dir="$(find "$ACFS_BOOTSTRAP_DIR" -maxdepth 1 -type d -name '*-*' | head -1)"

    # 5. VALIDATE REQUIRED FILES EXIST
    local required_files=(
        "scripts/lib/security.sh"
        "scripts/lib/logging.sh"
        "scripts/lib/tools.sh"
        "acfs.manifest.yaml"
        "checksums.yaml"
    )
    for f in "${required_files[@]}"; do
        [[ -f "$extract_dir/$f" ]] || fail "BOOTSTRAP_MISSING_FILE: $f not found in archive"
    done

    # 6. SYNTAX-CHECK ALL SHELL SCRIPTS
    while IFS= read -r -d '' script; do
        if ! bash -n "$script"; then
            fail "BOOTSTRAP_SYNTAX_ERROR: $script has syntax errors"
        fi
    done < <(find "$extract_dir/scripts" -name "*.sh" -print0)

    # 7. COHERENCE CHECK (manifest vs generated index)
    local manifest_sha256
    manifest_sha256=$(sha256sum "$extract_dir/acfs.manifest.yaml" | cut -d' ' -f1)
    local index_sha256=""
    if [[ -f "$extract_dir/scripts/generated/manifest_index.sh" ]]; then
        index_sha256=$(grep -oP 'ACFS_MANIFEST_SHA256="\K[^"]+' \
            "$extract_dir/scripts/generated/manifest_index.sh" || true)
    fi
    if [[ -n "$index_sha256" && "$manifest_sha256" != "$index_sha256" ]]; then
        fail "BOOTSTRAP_COHERENCE_FAILED: Manifest SHA256 mismatch (mixed ref or stale generated output)"
    fi

    # 8. SET UP ENVIRONMENT (only after all validations pass)
    export ACFS_ROOT="$extract_dir"
    export ACFS_LIB_DIR="$extract_dir/scripts/lib"
    export ACFS_GENERATED_DIR="$extract_dir/scripts/generated"
    export ACFS_ASSETS_DIR="$extract_dir/acfs"

    # 9. SOURCE ESSENTIAL LIBRARIES
    source "$ACFS_LIB_DIR/logging.sh"
    source "$ACFS_LIB_DIR/security.sh"
    source "$ACFS_LIB_DIR/tools.sh"
    if [[ -f "$ACFS_GENERATED_DIR/manifest_index.sh" ]]; then
        source "$ACFS_GENERATED_DIR/manifest_index.sh"
    fi

    log_success "Bootstrap complete from $ACFS_REF"
}
```

### Extraction Set (Required Files)

| Path | Purpose |
|------|---------|
| `scripts/lib/**` | Core installer libraries |
| `scripts/generated/**` | Manifest-generated scripts |
| `scripts/preflight.sh` | Pre-flight validation |
| `acfs/**` | Assets deployed to `~/.acfs/` |
| `acfs.manifest.yaml` | Module definitions |
| `checksums.yaml` | Verified installer checksums |

**Note:** Full `scripts/**` extraction is recommended over minimal allowlist to avoid "forgot to add new script" failures.

### Failure Modes

| Code | Condition | Message | Cause |
|------|-----------|---------|-------|
| `BOOTSTRAP_DOWNLOAD_FAILED` | Network error | "Could not download archive from $URL" | Network timeout, 404, rate limit |
| `BOOTSTRAP_INVALID_ARCHIVE` | Corrupt download | "Downloaded file is not a valid gzip archive" | Partial download, HTML error page |
| `BOOTSTRAP_EXTRACT_FAILED` | Tar error | "Could not extract archive" | Disk full, permissions |
| `BOOTSTRAP_MISSING_FILE` | Incomplete archive | "$file not found in archive" | Wrong ref, partial upload |
| `BOOTSTRAP_SYNTAX_ERROR` | Shell syntax | "$script has syntax errors" | Corrupt file, encoding issue |
| `BOOTSTRAP_COHERENCE_FAILED` | Mixed ref | "Manifest SHA256 mismatch" | Stale generated/, partial push |

### Atomicity Guarantees

1. **Download is atomic:** Archive saved to temp file first
2. **Extraction is atomic:** Extracts to temp directory
3. **Environment only set after ALL validations pass**
4. **Cleanup on failure:** `trap` ensures temp dir removed

### User Recovery Actions

| Failure | Action |
|---------|--------|
| `BOOTSTRAP_DOWNLOAD_FAILED` | Check internet, try again, or use `--ref` with specific tag |
| `BOOTSTRAP_COHERENCE_FAILED` | Wait for upstream to fix, or use `--ref` with known-good tag |
| `BOOTSTRAP_SYNTAX_ERROR` | Report bug with script name |

### Debug Mode

```bash
# Keep bootstrap directory for debugging
ACFS_KEEP_BOOTSTRAP=1 curl -fsSL ... | bash -s -- --mode vibe

# After failure, inspect extracted files
ls /tmp/acfs-bootstrap.*/
```

---

## Generated Module Runtime Contract (Phase 0 Spec)

This section defines the contract between `install.sh` (orchestrator) and generated module functions.

### Core Principles

1. **Generated scripts are libraries:** Safe to `source` at any time (no side effects at import)
2. **Contract validation at call-time:** Each module function validates its environment at entry
3. **Orchestrator owns reliability UX:** Resume/state, phase framing, error reporting live in install.sh
4. **Modules are deterministic units:** Run install/verify, return status code, never `exit`

### Module Function Structure

Every generated module function follows this structure:

```bash
acfs_install_<module_id>() {
    # ─────────────────────────────────────────────────────────────
    # 1. LOCAL IDENTITY + CONTRACT CHECK
    # ─────────────────────────────────────────────────────────────
    local module_id="lang.bun"
    local module_phase=6
    local module_optional=false  # true for optional modules

    acfs_require_contract "module:${module_id}" || return 1

    # ─────────────────────────────────────────────────────────────
    # 2. SELECTION CHECK (no side effects if filtered)
    # ─────────────────────────────────────────────────────────────
    if ! should_run_module "$module_id" "$module_phase"; then
        log_debug "$module_id: skipped (not in effective plan)"
        return 0
    fi

    # ─────────────────────────────────────────────────────────────
    # 3. IDEMPOTENCY CHECK (runs even in DRY_RUN)
    # ─────────────────────────────────────────────────────────────
    if acfs_module_installed "$module_id"; then
        log_info "$module_id: already installed, skipping"
        return 0
    fi

    # ─────────────────────────────────────────────────────────────
    # 4. DRY RUN HANDLING
    # ─────────────────────────────────────────────────────────────
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: would install $module_id"
        # Show what would happen:
        log_detail "  → curl -fsSL https://bun.sh/install | bash"
        return 0
    fi

    # ─────────────────────────────────────────────────────────────
    # 5. INSTALLATION (wrapped for strict-mode safety)
    # ─────────────────────────────────────────────────────────────
    log_info "Installing $module_id..."

    # Option A: Verified upstream installer
    if ! acfs_run_verified_upstream_script_as_target_user "bun" "bash"; then
        return $(acfs_handle_module_failure "$module_id" "$module_optional" "Verified installer failed")
    fi

    # Option B: Direct commands (each wrapped)
    # if ! run_as_target_user_shell 'curl -fsSL https://bun.sh/install | bash'; then
    #     return $(acfs_handle_module_failure "$module_id" "$module_optional" "Install command failed")
    # fi

    # ─────────────────────────────────────────────────────────────
    # 6. VERIFICATION
    # ─────────────────────────────────────────────────────────────
    log_detail "Verifying $module_id..."
    if ! run_as_target_user_shell '~/.bun/bin/bun --version'; then
        return $(acfs_handle_module_failure "$module_id" "$module_optional" "Verification failed")
    fi

    log_success "$module_id installed"
    return 0
}
```

### Entry Requirements

| Requirement | Purpose |
|-------------|---------|
| `local module_id="..."` | Self-identification for logging/state |
| `local module_phase=N` | Phase number for selection filtering |
| `local module_optional=true/false` | Failure behavior control |
| `acfs_require_contract "module:${module_id}"` | Validate orchestrator environment |

### Contract Validation

`acfs_require_contract()` verifies the module is running in a properly initialized environment:

```bash
acfs_require_contract() {
    local contract="$1"

    case "$contract" in
        module:*)
            # Verify orchestrator has initialized these
            [[ -n "${ACFS_EFFECTIVE_RUN[*]:-}" ]] || return 1
            [[ -n "${ACFS_LIB_DIR:-}" ]] || return 1
            [[ "$(type -t should_run_module)" == "function" ]] || return 1
            [[ "$(type -t run_as_target_user_shell)" == "function" ]] || return 1
            ;;
    esac
    return 0
}
```

### Selection Check Semantics

```bash
should_run_module() {
    local module_id="$1"
    local module_phase="$2"

    # O(1) lookup in associative array populated by selection algorithm
    [[ -n "${ACFS_EFFECTIVE_RUN[$module_id]:-}" ]]
}
```

### Idempotency Check

Installed check MUST be side-effect-free and run even in DRY_RUN mode:

```bash
acfs_module_installed() {
    local module_id="$1"

    # Use manifest's installed_check if available
    case "$module_id" in
        lang.bun)
            [[ -x "$HOME/.bun/bin/bun" ]] && return 0 ;;
        lang.rust)
            [[ -x "$HOME/.cargo/bin/cargo" ]] && return 0 ;;
        # ... generated from manifest installed_check field
    esac
    return 1
}
```

### DRY_RUN Semantics

| Mode | Behavior |
|------|----------|
| `DRY_RUN=false` | Normal execution |
| `DRY_RUN=true` | Show what would happen, skip side effects |

In DRY_RUN mode, modules MUST:
- Run installed_check and report current state
- Print what they would do (log_info "dry-run: would ...")
- NOT execute install commands
- NOT modify any files
- Return 0 (no simulated failures)

### Return Code Semantics

| Module Type | Condition | Return | Side Effect |
|-------------|-----------|--------|-------------|
| Non-optional | Install success | 0 | None |
| Non-optional | Install failure | 1 | Orchestrator aborts |
| Non-optional | Verify failure | 1 | Orchestrator aborts |
| Optional | Install failure | 0 | Log warning, record skip |
| Optional | Verify failure | 0 | Log warning, record skip |

### Failure Handling Helper

```bash
acfs_handle_module_failure() {
    local module_id="$1"
    local is_optional="$2"
    local reason="$3"

    if [[ "$is_optional" == "true" ]]; then
        log_warn "$module_id: $reason (optional, continuing)"
        record_skipped_tool "$module_id" "$reason"
        echo 0  # return 0
    else
        log_error "$module_id: $reason"
        echo 1  # return 1
    fi
}
```

### Verified Installer Execution

Remote installers MUST use shared verified pathways:

```bash
# RIGHT: Uses checksums.yaml validation
acfs_run_verified_upstream_script_as_target_user "bun" "bash"

# WRONG: Never inline curl|bash in generated code
curl -fsSL https://bun.sh/install | bash
```

### Strict-Mode Safety

Generated modules must NEVER rely on `set -e` for flow control. Every risky operation is explicitly wrapped:

```bash
# WRONG: set -e makes this a landmine
curl ... | bash
bun --version

# RIGHT: Explicit error handling
if ! curl ... | bash; then
    return $(acfs_handle_module_failure ...)
fi
if ! bun --version; then
    return $(acfs_handle_module_failure ...)
fi
```

### Skip Tracking Integration

Optional module failures integrate with:
- `record_skipped_tool()` — Logs skip reason (from `scripts/lib/tools.sh`)
- `report_skipped_tools()` — End-of-install summary
- `acfs doctor` — Shows skipped tools in "Intentionally Skipped" section

### Module Function Naming Convention

| Pattern | Generated From |
|---------|----------------|
| `acfs_install_lang_bun` | Module ID `lang.bun` |
| `acfs_install_stack_ntm` | Module ID `stack.ntm` |
| `acfs_install_base_system` | Module ID `base.system` |

Dots in module IDs are converted to underscores.

### Generated Script Header

All generated module scripts include:

```bash
#!/usr/bin/env bash
# ============================================================
# AUTO-GENERATED FROM acfs.manifest.yaml - DO NOT EDIT
# Regenerate: bun run generate (from packages/manifest)
# Manifest SHA256: abc123...
# Generated: 2025-12-21T12:00:00Z
# ============================================================
# This file is a library. Source it, then call functions.
# It has no side effects when sourced.
```

## How This Plan Interacts With Other ACFS Work

This plan is intentionally focused on **eliminating “two universes” drift** (manifest vs install.sh), but it must coexist cleanly with the project’s other reliability initiatives.

### Must-Remain-True Invariants

- **Installer reliability work remains valid after refactor.** Features like preflight, resume/state, and structured error reporting must live in (or be callable from) the orchestrator/libs so they survive category-by-category migration.
- **Generated scripts are “library code”, not “programs”.** They must remain safe to `source` at any time (for `--list-modules`, `--print-plan`, argument parsing) and must not mutate global state on import.
- **State + skip tracking must still make sense.** When a module is optional or explicitly skipped, the system must be able to explain “why it’s missing” later (especially in `acfs doctor` output).

### Concrete Touchpoints (Existing Epics)

- **Preflight (EPIC: Pre-Flight Validation):** Preflight runs *before* any installs. It should not depend on generated scripts (it can run before bootstrap completes, or immediately after bootstrap but before sourcing).
- **Resume + state.json (EPIC: Phase-Granular Progress Persistence):** Phase wrappers (`run_phase`) should wrap *orchestrator* phase calls, not module internals. Module calls should be treated as “steps” for error context (and optionally recorded as completed modules if we choose to track at module granularity).
- **Per-phase error reporting (EPIC: Per-Phase Error Reporting):** `try_step` and `report_failure` should remain orchestrator-owned. Generated modules should return non-zero on failure (or 0 if optional), with enough context (module_id) so the orchestrator can report consistently.
- **Checksum recovery (EPIC: Checkpoint-Based Checksum Recovery):** Verified upstream installers are the generator’s default for remote scripts. The checksum recovery UX must remain centralized (in `scripts/lib/security.sh` and related helpers) so generated modules inherit it automatically.
- **Doctor deep checks (EPIC: Enhanced Doctor with Functional Tests):** Manifest-driven `verify:` stays “fast existence checks”. Deep checks remain a separate opt-in mode; do not push connectivity/auth checks into generated verify steps.

---

## Current State (The Problem)

```
┌─────────────────────────────────────────────────────────────────┐
│                    TWO PARALLEL UNIVERSES                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Universe A (Unused):                                            │
│  ┌──────────────────┐    ┌─────────────┐    ┌─────────────────┐ │
│  │ acfs.manifest.yaml│───▶│ generate.ts │───▶│ scripts/generated/│
│  │ (50+ modules)     │    │             │    │ (NEVER EXECUTED) │
│  └──────────────────┘    └─────────────┘    └─────────────────┘ │
│                                                                  │
│  Universe B (Actual):                                            │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    install.sh (1575 lines)                │   │
│  │   - Hand-maintained, duplicates manifest logic            │   │
│  │   - Contains orchestration + module installation          │   │
│  │   - Drifts from manifest over time                        │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Symptoms:**
- Manifest changes don't affect installation
- install.sh and manifest can disagree
- Duplicated effort maintaining both
- "Single source of truth" is a lie

---

## Target State (The Solution)

```
┌─────────────────────────────────────────────────────────────────┐
│                    SINGLE SOURCE OF TRUTH                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────┐    ┌─────────────┐    ┌─────────────────┐ │
│  │ acfs.manifest.yaml│───▶│ generate.ts │───▶│ scripts/generated/│
│  │ (enhanced schema) │    │ (enhanced)  │    │ install_*.sh    │ │
│  └──────────────────┘    └─────────────┘    └────────┬────────┘ │
│                                                       │          │
│                                                       ▼          │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              install.sh (THIN ORCHESTRATOR)               │   │
│  │  - Sources generated scripts                              │   │
│  │  - curl|bash: downloads archive then sources extracted     │   │
│  │  - Handles phases, user normalization, filesystem         │   │
│  │  - Calls: install_lang_bun, install_agents_claude, etc.   │   │
│  │  - NO module-specific installation logic                  │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   scripts/lib/*.sh                        │   │
│  │  - Shared utilities (logging, security, run_as_target)    │   │
│  │  - Used by both install.sh and generated scripts          │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Alternative Approaches Considered

| Approach | Pros | Cons | Verdict |
|----------|------|------|---------|
| **Pre-generate + source** (chosen) | Simple, debuggable, works offline, committed to git | Must regenerate when manifest changes | ✅ Best |
| **Runtime generation** | Always in sync | Needs bun on target before installation, chicken-egg problem | ❌ |
| **Bash reads YAML directly** | No generation step | Bash YAML parsing is painful, need to bundle parser | ❌ |
| **Transpile to single file** | Single artifact | Loses modularity, harder to debug | ❌ |

---

## Environment Contract

Generated scripts have a strict contract with install.sh. This contract MUST be documented and enforced.

### curl|bash Bootstrapping (No Local Checkout)

When users run ACFS via `curl … | bash`, there is **no local repository checkout**, so `SCRIPT_DIR` may be empty. In that mode, the orchestrator must:

1. Determine a local bootstrap directory (`mktemp -d`), and optionally mirror into `$ACFS_HOME/cache/bootstrap/<ref>/` for re-runs.
2. Download a **single repo archive** (tar.gz) for a single ref (tag/sha/branch) to guarantee a self-consistent set of files.
3. Extract only what the installer needs:
   - `scripts/lib/**`
   - `scripts/generated/**`
   - `acfs/**` (assets deployed to `~/.acfs/`)
   - `checksums.yaml`
   - `acfs.manifest.yaml` (for coherence checks)
4. Validate extracted shell scripts with `bash -n` before sourcing them.
5. `source` only **local files** from the extracted tree (never process substitution).

Generated scripts must assume they are being sourced from **local files** (either from a git checkout or from a bootstrap download directory).

#### Pinning to a Single Git Ref (Reliability)

If `ACFS_RAW` points at `.../main`, it is theoretically possible (rare, but real) to download a mismatched set of files if the branch updates during an install (e.g., install.sh from commit A, generated scripts from commit B). To make installs reproducible and avoid mid-run mismatches:

- Prefer a **tag** or **commit SHA** in `ACFS_RAW` (e.g., `.../<tag>/...` or `.../<sha>/...`).
- Optionally add an `ACFS_REF` variable (default: `main`) and set `ACFS_RAW="https://raw.githubusercontent.com/<owner>/<repo>/$ACFS_REF"`.

**Stronger reliability guarantee (recommended):** In `curl|bash` mode, prefer fetching a single GitHub archive for `ACFS_REF` over multiple raw-file requests. This guarantees all files come from the same commit snapshot, even if `main` advances during the install.

### Bootstrap Coherence Check (Prevents “mixed refs”)

After bootstrapping, compute:
- `MANIFEST_SHA256 := sha256(acfs.manifest.yaml)`

Then verify that each generated installer header contains the same manifest SHA. If mismatch is detected, abort early with a clear error:
- “Bootstrap mismatch: generated scripts do not match manifest (mixed ref or stale generated output).”

### Required Environment Variables

Generated scripts must be **sourceable without** these variables set.
These variables must be set by install.sh **before invoking any generated module function**:

```bash
# User context
TARGET_USER="ubuntu"              # User to install for
TARGET_HOME="/home/ubuntu"        # Home directory of target user
ACFS_HOME="/home/ubuntu/.acfs"    # ACFS configuration directory

# Execution context
MODE="vibe"                       # vibe | safe
DRY_RUN="false"                   # true | false
SUDO="sudo"                       # sudo command (empty if root)

# Repo identity (used for curl|bash bootstrap)
ACFS_REPO_OWNER="Dicklesworthstone"
ACFS_REPO_NAME="agentic_coding_flywheel_setup"
ACFS_REF="main"                   # branch | tag | sha

# Remote source location (optional if archive bootstrap is used)
ACFS_RAW="https://raw.githubusercontent.com/${ACFS_REPO_OWNER}/${ACFS_REPO_NAME}/${ACFS_REF}"

# Paths (local checkout vs curl|bash)
SCRIPT_DIR="/path/to/installer"         # Directory containing install.sh (may be empty under curl|bash)
ACFS_BOOTSTRAP_DIR="/tmp/acfs-bootstrap" # Local dir containing downloaded scripts when SCRIPT_DIR is empty (should be unique per run)
ACFS_LIB_DIR="$ACFS_BOOTSTRAP_DIR/scripts/lib"
ACFS_GENERATED_DIR="$ACFS_BOOTSTRAP_DIR/scripts/generated"
ACFS_ASSETS_DIR="$ACFS_BOOTSTRAP_DIR/acfs"
ACFS_CHECKSUMS_YAML="$ACFS_BOOTSTRAP_DIR/checksums.yaml"
ACFS_MANIFEST_YAML="$ACFS_BOOTSTRAP_DIR/acfs.manifest.yaml"
```

### Required Functions

Generated scripts expect these functions to be available (from scripts/lib/*.sh):

```bash
# Logging (from scripts/lib/logging.sh)
log_step "1/10" "Message"         # Phase progress
log_detail "Message"              # Indented detail
log_success "Message"             # Green success
log_warn "Message"                # Yellow warning
log_error "Message"               # Red error

# Execution (provided by install.sh or a small scripts/lib helper)
run_as_target <command>           # Run command as TARGET_USER
run_as_target_shell "<cmd>"       # Run a shell string as TARGET_USER (supports pipes/heredocs)
run_as_root_shell "<cmd>"         # Run a shell string as root (supports pipes/heredocs)
run_as_current_shell "<cmd>"      # Run a shell string as current user (supports pipes/heredocs)
command_exists_as_target <cmd>    # Check command exists in TARGET_USER environment
command_exists <cmd>              # Check if command is in PATH

# Module filtering (from scripts/lib/install_helpers.sh)
# (should_run_module is pure; it must not mutate global selection state)
should_run_module "<id>" "<phase>"

# Contract (from scripts/lib/contract.sh)
acfs_require_contract "<context>"   # Validate runtime vars + required functions; returns nonzero on violation

# Assets / fetching (from install.sh or scripts/lib/security.sh)
acfs_curl <args...>               # Curl wrapper enforcing HTTPS where possible
install_asset "<rel>" "<dest>"    # Copy from local checkout or download from ACFS_RAW

# Security (from scripts/lib/security.sh)
acfs_run_verified_upstream_script_as_target "<tool>" "<runner>" [args...]
acfs_run_verified_upstream_script_as_root "<tool>" "<runner>" [args...]
acfs_run_verified_upstream_script_as_current "<tool>" "<runner>" [args...]
```

### Contract Validation

Contract validation should be centralized in a shared lib so it is consistent across:
- install.sh orchestration
- generated scripts
- future doctor/update integrations

Add: `scripts/lib/contract.sh`:

```bash
acfs_require_contract() {
    local context="${1:-generated}"
    local missing=()
    [[ -z "${TARGET_USER:-}" ]] && missing+=("TARGET_USER")
    [[ -z "${TARGET_HOME:-}" ]] && missing+=("TARGET_HOME")
    [[ -z "${MODE:-}" ]] && missing+=("MODE")

    # Under curl|bash, install.sh must bootstrap a local tree (archive extract) and set ACFS_* paths.
    if [[ -z "${SCRIPT_DIR:-}" ]]; then
        [[ -z "${ACFS_BOOTSTRAP_DIR:-}" ]] && missing+=("ACFS_BOOTSTRAP_DIR")
        [[ -z "${ACFS_LIB_DIR:-}" ]] && missing+=("ACFS_LIB_DIR")
        [[ -z "${ACFS_GENERATED_DIR:-}" ]] && missing+=("ACFS_GENERATED_DIR")
        [[ -z "${ACFS_ASSETS_DIR:-}" ]] && missing+=("ACFS_ASSETS_DIR")
        [[ -z "${ACFS_CHECKSUMS_YAML:-}" ]] && missing+=("ACFS_CHECKSUMS_YAML")
        [[ -z "${ACFS_MANIFEST_YAML:-}" ]] && missing+=("ACFS_MANIFEST_YAML")
    fi

    if ! declare -f log_detail >/dev/null 2>&1; then
        missing+=("log_detail function")
    fi
    if ! declare -f run_as_target >/dev/null 2>&1; then
        missing+=("run_as_target function")
    fi
    if ! declare -f run_as_target_shell >/dev/null 2>&1; then
        missing+=("run_as_target_shell function")
    fi
    if ! declare -f run_as_root_shell >/dev/null 2>&1; then
        missing+=("run_as_root_shell function")
    fi
    if ! declare -f run_as_current_shell >/dev/null 2>&1; then
        missing+=("run_as_current_shell function")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: ACFS contract violation (${context})" >&2
        echo "Missing: ${missing[*]}" >&2
        echo "Fix: install.sh must source scripts/lib/*.sh, set required vars, and only then invoke generated module functions." >&2
        return 1
    fi
    return 0
}
```

Generated module functions must call:

```bash
acfs_require_contract "module:${module_id}" || return 1
```

...at the top of each function (not at source-time), so scripts remain sourceable for `--list-modules` and for early argument parsing.

---

## Description-Only Modules Strategy

Some manifest modules currently contain prose inside `install:`. This is ambiguous and brittle. Replace prose-in-install with **explicit fields**:
- `notes:` for human prose
- `generated: false` for orchestration-only modules

**Rule:** If `generated: true`, every `install:` entry must be executable shell (or `install: []` with `verified_installer`).

```yaml
# PROBLEM (legacy): prose mixed into install
- id: users.ubuntu
  install:
    - "Ensure user ubuntu exists with home /home/ubuntu"
    - "Write /etc/sudoers.d/90-ubuntu-acfs: ubuntu ALL=(ALL) NOPASSWD:ALL"
```

### Detection Heuristic

```typescript
// IMPORTANT: YAML quoting does NOT imply description. Commands are often quoted.
// Use heuristics ONLY for lint warnings (never for behavior).
function looksLikeProse(cmd: string): boolean {
  const trimmed = cmd.trim();

  // Explicit markers (recommended for temporary placeholders during migration)
  if (/^(TODO:|NOTE:)/.test(trimmed)) return true;

  // Contains prose-like patterns
  if (/\b(Ensure|Install|Create|Write|Copy|Add|Set up)\b/i.test(trimmed)) {
    // But not if it looks like a command
    if (!/^(sudo|apt|curl|git|chmod|chown|mkdir|cp|mv|ln|cat|echo)/.test(trimmed)) {
      return true;
    }
  }

  return false;
}
```

### Handling Options

| Strategy | When to Use | Example |
|----------|-------------|---------|
| Move prose to `notes:` | Human guidance, operator notes | users.ubuntu (notes) |
| `generated: false` | Orchestration handled by install.sh | users.ubuntu |
| Convert to commands | Simple actions that can be expressed as bash | base.filesystem |

**Important:** Heuristics are for **warnings only**. Generator behavior must be based on explicit manifest fields.

### Schema Addition

```yaml
- id: users.ubuntu
  description: User normalization
  generated: false  # NEW: Skip generation, handled by install.sh orchestration
  notes:
    - "Handled by install.sh: root→ubuntu normalization, SSH key migration, sudoers config"
  verify:
    - id ubuntu
```

### Generator Behavior

```typescript
function shouldGenerateModule(module: Module): boolean {
  // Explicit opt-out
  if (module.generated === false) return false;

  // Fail fast: a generated module must have either a verified installer OR executable install steps.
  //
  // NOTE: module.install may be empty when verified_installer is provided.
  const hasExecutableInstall =
    module.verified_installer != null ||
    module.install.length > 0;

  if (!hasExecutableInstall) {
    throw new Error(
      `Module ${module.id} has no executable install commands. ` +
      `Either provide real commands or set generated: false.`
    );
  }

  // Warn if any install step looks like prose (helps keep manifest clean)
  if (module.install.length > 0 && module.install.some(looksLikeProse)) {
    console.warn(
      `Warning: module ${module.id} contains prose-like install steps. ` +
      `Move prose to notes:, or mark generated: false.`
    );
  }

  return true;
}
```

---

## Function Name Collision Prevention

### The Problem

Module IDs are converted to function names:
- `lang.bun` → `install_lang_bun`
- `lang_bun` → `install_lang_bun` (COLLISION!)

### The Solution

Add validation in generator:

```typescript
function validateFunctionNames(modules: Module[]): void {
  const functionNames = new Map<string, string>(); // funcName -> moduleId

  for (const module of modules) {
    const funcName = toFunctionName(module.id);

    if (functionNames.has(funcName)) {
      const existingId = functionNames.get(funcName);
      throw new Error(
        `Function name collision: "${funcName}" generated by both ` +
        `"${existingId}" and "${module.id}". ` +
        `Rename one of these modules to avoid collision.`
      );
    }

    functionNames.set(funcName, module.id);
  }
}

function toFunctionName(moduleId: string): string {
  // Replace dots with underscores, ensure valid bash function name
  return `install_${moduleId.replace(/\./g, '_').replace(/[^a-z0-9_]/g, '')}`;
}
```

### Also Prevent Collisions With Orchestrator Functions

Generator must also validate that generated function names do not collide with a reserved list:
- `main`, `parse_args`, `normalize_user`, `finalize`, etc.
Fail fast with an actionable error message.

### Manifest Schema Validation

Also prevent collisions at schema level:

```typescript
// In parser.ts
function validateNoDuplicateFunctionNames(manifest: Manifest): ValidationResult {
  const errors: string[] = [];
  const funcNames = new Map<string, string>();

  for (const module of manifest.modules) {
    const funcName = toFunctionName(module.id);
    if (funcNames.has(funcName)) {
      errors.push(
        `Module "${module.id}" would generate function "${funcName}" ` +
        `which collides with module "${funcNames.get(funcName)}"`
      );
    }
    funcNames.set(funcName, module.id);
  }

  return errors.length > 0
    ? { success: false, errors }
    : { success: true };
}
```

---

## DRY_RUN Mode in Generated Scripts

Generated scripts must respect DRY_RUN mode for testing:

### Generated Function Pattern

```bash
install_lang_bun() {
    local module_id="lang.bun"
    acfs_require_contract "module:${module_id}" || return 1

    # Installed check (runs even in dry-run to show current state)
    if run_as_target_shell "command -v bun >/dev/null 2>&1"; then
        log_detail "$module_id already installed, skipping"
        return 0
    fi

    # DRY_RUN check
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_detail "dry-run: would install $module_id"
        log_detail "dry-run: would run: acfs_run_verified_upstream_script_as_target bun bash"
        return 0
    fi

    log_detail "Installing $module_id"

    # Actual installation
    if ! acfs_run_verified_upstream_script_as_target "bun" "bash"; then
        log_error "$module_id install failed"
        return 1
    fi

    # Verification
    if ! run_as_target_shell "bun --version >/dev/null 2>&1"; then
        log_error "$module_id verification failed"
        return 1
    fi

    log_success "$module_id installed"
}
```

### Generator Code

```typescript
function generateModuleFunction(module: Module): string {
  const lines: string[] = [];
  const funcName = toFunctionName(module.id);

  lines.push(`${funcName}() {`);
  lines.push(`    local module_id="${module.id}"`);
  lines.push(`    acfs_require_contract "module:${module.id}" || return 1`);

  // Installed check (always runs; run_as-aware)
  if (module.installed_check) {
    const check = module.installed_check;
    const checkRunner = check.run_as === 'target_user'
      ? 'run_as_target_shell'
      : check.run_as === 'root'
        ? 'run_as_root_shell'
        : 'run_as_current_shell';
    lines.push(`    if ${checkRunner} "${escapeBashForDoubleQuotes(check.command)} >/dev/null 2>&1"; then`);
    lines.push(`        log_detail "$module_id already installed, skipping"`);
    lines.push(`        return 0`);
    lines.push(`    fi`);
  }

  // DRY_RUN check
  lines.push(`    if [[ "\${DRY_RUN:-false}" == "true" ]]; then`);
  lines.push(`        log_detail "dry-run: would install $module_id"`);
  if (module.verified_installer) {
    lines.push(
      `        log_detail "dry-run: would run: acfs_run_verified_upstream_script_as_target ${module.verified_installer.tool} ${module.verified_installer.runner}"`
    );
  } else {
    for (const cmd of module.install) {
      if (!looksLikeProse(cmd)) {
        lines.push(`        log_detail "dry-run: would run: ${escapeBashForLog(cmd)}"`);
      }
    }
  }
  lines.push(`        return 0`);
  lines.push(`    fi`);

  // ... rest of installation
}
```

---

## Individual Module Testing

### New CLI Arguments for install.sh

```bash
# Install only specific module(s)
./install.sh --only lang.bun
./install.sh --only lang.bun,lang.uv,lang.rust

# Install only specific phase(s)
./install.sh --only-phase 6
./install.sh --only-phase 6,7,8

# Skip specific module(s)
./install.sh --skip stack.slb
./install.sh --skip stack.slb,stack.caam

# List available modules
./install.sh --list-modules

# Show what would be installed (combines with --only/--skip)
./install.sh --dry-run --only lang.bun

# Advanced: do NOT auto-run dependency closure (expert-only debugging)
./install.sh --only lang.bun --no-deps

# Print the effective execution plan (after filters + deps)
./install.sh --print-plan --only lang.bun
```

### Implementation in install.sh

```bash
# Selection resolution (done once) + cheap predicate during execution
#
# 1) parse args into ONLY_* / SKIP_*
# 2) compute EFFECTIVE set with dependency closure (unless --no-deps)
# 3) should_run_module becomes a simple membership test

ONLY_MODULES=()
ONLY_PHASES=()
SKIP_MODULES=()
NO_DEPS="false"
PRINT_PLAN="false"

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --only)
                IFS=',' read -ra ONLY_MODULES <<< "$2"
                shift 2
                ;;
            --only-phase)
                IFS=',' read -ra ONLY_PHASES <<< "$2"
                shift 2
                ;;
            --skip)
                IFS=',' read -ra SKIP_MODULES <<< "$2"
                shift 2
                ;;
            --no-deps)
                NO_DEPS="true"
                shift
                ;;
            --print-plan)
                PRINT_PLAN="true"
                shift
                ;;
            --list-modules)
                list_all_modules
                exit 0
                ;;
            # ... other args
        esac
    done
}

# Effective selection computed once after scripts/generated/manifest_index.sh is sourced
declare -A ACFS_EFFECTIVE_RUN=()

acfs_resolve_selection() {
    # Uses generated manifest index (module->phase, module->deps).
    # Expands ONLY_MODULES/ONLY_PHASES into a set, then adds dependency closure.
    # Errors if SKIP removes a required dependency.
    :
}

should_run_module() {
    local module_id="$1"
    [[ -n "${ACFS_EFFECTIVE_RUN[$module_id]:-}" ]] && return 0
    return 1
}
```

### Generated Module Functions Support

```bash
install_lang_bun() {
    local module_id="lang.bun"
    local module_phase="6"
    acfs_require_contract "module:${module_id}" || return 1

    # Check if this module should run
    if ! should_run_module "$module_id" "$module_phase"; then
        log_detail "$module_id skipped (filtered)"
        return 0
    fi

    # ... rest of function
}
```

---

## Selection Semantics (Detailed)

The goal of selection is to make filtering safe and predictable:

- `--only` should “just work” on a fresh machine by installing prerequisites automatically (dependency closure).
- `--skip` should never silently create a broken plan; skipping required prerequisites should fail early with an actionable message.
- Defaults should be explicit (`enabled_by_default`) so we can ship optional tools without forcing them on all users.

### Inputs

**User-facing flags (additive to existing flags):**
- `--only <id1,id2,...>`
- `--only-phase <p1,p2,...>`
- `--skip <id1,id2,...>`
- `--no-deps` (expert-only; disables dependency closure)
- `--print-plan` (prints the final resolved plan and exits; compatible with `--dry-run`)
- `--list-modules` (prints the manifest index with phases/tags/categories and exits)

**Legacy flags (must remain compatible):**
- Any existing `--skip-*` flags should be implemented as wrappers that map to:
  - skip explicit module IDs, and/or
  - skip tag/category sets
…so the “real” selection engine remains manifest-driven.

### Default Behavior (When No --only/--only-phase Provided)

When the user provides no filtering flags, selection should start from:
- all modules where `enabled_by_default: true`

This is critical for keeping installs stable for beginners while still allowing “extra” tools to exist in the manifest without surprising users.

### Dependency Closure

Unless `--no-deps` is provided:

1. Initialize a “wanted” set from:
   - `--only` module IDs (if provided), else `enabled_by_default` modules
2. If `--only-phase` is provided, filter wanted set to those phases.
3. Add dependencies recursively using `ACFS_MODULE_DEPS`:
   - Always include deps even if `enabled_by_default: false`
   - Reject manifest cycles at generation-time
4. Apply skips:
   - If a skipped module is required by any wanted module, **fail early**
   - Error must name the exact edge: “X depends on skipped Y”

### Deterministic Execution Order

Execution must be deterministic and explainable:
- Generator emits `ACFS_MODULES_IN_ORDER=(...)` in `scripts/generated/manifest_index.sh`
- Orchestrator filters this list to just the effective run set
- “Phase order” is implicit in the ordering list (phases 1→10, topo sort within each phase)

### `manifest_index.sh` Responsibilities

`scripts/generated/manifest_index.sh` is the “bridge” between Bash and the manifest:

- **Data**:
  - `ACFS_MANIFEST_SHA256="..."`
  - `declare -A ACFS_MODULE_PHASE=([id]=N ...)`
  - `declare -A ACFS_MODULE_DEPS=([id]="a,b,c" ...)`
  - `declare -A ACFS_MODULE_FUNC=([id]="install_x_y" ...)`
  - `declare -A ACFS_MODULE_TAGS=([id]="lang,runtime" ...)` (recommended)
  - `declare -A ACFS_MODULE_CATEGORY=([id]="lang" ...)` (recommended)
  - `declare -A ACFS_MODULE_DEFAULT=([id]="1|0" ...)` (recommended)
  - `ACFS_MODULES_IN_ORDER=(...)`
- **Helpers** (optional but recommended to keep install.sh small):
  - `acfs_manifest_list_modules`
  - `acfs_manifest_print_plan`

### `acfs_resolve_selection` Responsibilities

`scripts/lib/install_helpers.sh` (or equivalent) owns the runtime selection algorithm:

- Computes the effective set (`declare -A ACFS_EFFECTIVE_RUN=([id]=1 ...)`)
- Optionally builds a human-readable plan (for `--print-plan`)
- Provides `should_run_module` as a cheap membership predicate

### UX Expectations

- `--print-plan` must show:
  - execution order
  - why a module is included (default, only, dependency of X)
  - why a module is excluded (skip, disabled by default, filtered by phase)
- `--no-deps` must print a prominent warning because it is easy to foot-gun.
- Errors should be crisp and actionable ("Remove --skip base.system or add --no-deps if debugging").

---

## Golden Path CLI Stories (Phase 0 Spec)

These stories define the expected behavior for common use cases, ensuring the CLI matches user mental models.

### Story 1: Beginner Default Install (Wizard User)

**Persona:** First-time user following the website wizard.

**Command:**
```bash
curl -fsSL https://raw.githubusercontent.com/.../install.sh | bash -s -- --yes --mode vibe
```

**Expected behavior:**
1. Bootstrap downloads repo archive, validates scripts (`bash -n`)
2. Selection starts with all `enabled_by_default: true` modules
3. All phases (1-10) execute in order
4. `--yes` skips confirmation prompts
5. `--mode vibe` configures passwordless sudo, full agent permissions
6. No manual intervention required
7. Smoke test runs automatically at end

**Why this works:**
- The manifest defines sensible defaults (critical + recommended tools)
- PostgreSQL, Vault, Cloud CLIs are opt-out (`enabled_by_default: false`)
- Dependency closure is automatic; no orphan modules

**What the user sees:**
```
[1/10] Checking base dependencies...
[2/10] Normalizing user account...
...
[10/10] Finalizing installation...
 ACFS installation complete!
```

---

### Story 2: Install Only Bun (with automatic dependencies)

**Persona:** Developer who only needs Bun runtime.

**Command:**
```bash
./install.sh --only lang.bun
```

**Expected behavior:**
1. Selection starts with `lang.bun` only
2. Dependency closure adds `base.system` (apt packages for curl, git, build tools)
3. Final plan: `base.system` -> `lang.bun`
4. Phases 1 and 6 execute, others skipped
5. Total install completes in ~2 minutes

**What the user sees (with `--print-plan`):**
```bash
./install.sh --only lang.bun --print-plan
```
```
Effective plan (2 modules):
  [ok] base.system (phase 1) [dependency of lang.bun]
  [ok] lang.bun (phase 6) [explicitly requested]

Skipped phases: 2, 3, 4, 5, 7, 8, 9, 10
```

---

### Story 3: Install Agents Only (most common customization)

**Persona:** User who has base system set up, just wants the coding agents.

**Command:**
```bash
./install.sh --only agents.claude,agents.codex,agents.gemini
```

**Expected behavior:**
1. Selection includes the three agents
2. Dependency closure adds: `base.system`, `lang.bun` (required by codex/gemini)
3. Final plan: `base.system` -> `lang.bun` -> `agents.claude` -> `agents.codex` -> `agents.gemini`
4. Already-installed dependencies (idempotent check) are skipped quickly

**Why this matters:**
- Users upgrading from an older ACFS version
- CI/CD pipelines that only need agents
- Testing agent installs in isolation

---

### Story 4: Skip PostgreSQL (common wizard override)

**Persona:** Wizard user who unchecks PostgreSQL in the website UI.

**Command:**
```bash
curl -fsSL ... | bash -s -- --yes --mode vibe --skip-postgres
```

**Expected behavior:**
1. Legacy flag `--skip-postgres` maps to `--skip db.postgres18`
2. Selection computes default set minus `db.postgres18`
3. No dependency conflict (postgres is not a dependency of other modules)
4. Installation proceeds with all other modules

**Legacy flag mapping (in `parse_args`):**
```bash
--skip-postgres) SKIP_MODULES+=("db.postgres18") ;;
--skip-vault)    SKIP_MODULES+=("tools.vault") ;;
--skip-cloud)    SKIP_MODULES+=("cloud.wrangler" "cloud.supabase" "cloud.convex" "cloud.vercel") ;;
```

---

### Story 5: Phase-based Filtering (CI optimization)

**Persona:** CI pipeline that needs only language runtimes.

**Command:**
```bash
./install.sh --only-phase 6
```

**Expected behavior:**
1. Selection includes only modules in phase 6: `lang.bun`, `lang.uv`, `lang.rust`, `lang.go`, `tools.atuin`, `tools.zoxide`, `tools.ast_grep`
2. Dependency closure adds phase 1 (`base.system`) automatically
3. Final plan respects dependency order

**Use case:**
- Faster CI/CD builds
- Testing specific installer phases
- Modular VPS provisioning

---

## Expert Debugging Stories (Phase 0 Spec)

These stories document the `--no-deps` and `--print-plan` flags for advanced troubleshooting.

### Story D1: Inspect the Plan Without Executing

**Command:**
```bash
./install.sh --print-plan
```

**Output:**
```
ACFS Installation Plan
======================
Mode: vibe
Effective modules: 25 (5 disabled by default)
Phases: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10

Phase 1 (base):
  [ok] base.system [default]

Phase 2 (users):
  [ok] users.ubuntu [default] (orchestration-only)

Phase 3 (filesystem):
  [ok] base.filesystem [default]

Phase 4 (shell):
  [ok] shell.zsh [default]

Phase 5 (cli):
  [ok] cli.modern [default]

Phase 6 (lang):
  [ok] lang.bun [default]
  [ok] lang.uv [default]
  [ok] lang.rust [default]
  [ok] lang.go [default]
  [ok] tools.atuin [default]
  [ok] tools.zoxide [default]
  [ok] tools.ast_grep [default]

Phase 7 (agents):
  [ok] agents.claude [default]
  [ok] agents.codex [default]
  [ok] agents.gemini [default]

Phase 8 (cloud):
  [skip] db.postgres18 [disabled by default]
  [skip] tools.vault [disabled by default]
  [skip] cloud.wrangler [disabled by default]
  [skip] cloud.supabase [disabled by default]
  [skip] cloud.convex [disabled by default]
  [skip] cloud.vercel [disabled by default]

Phase 9 (stack):
  [ok] stack.ntm [default]
  [ok] stack.mcp_agent_mail [default]
  [ok] stack.ultimate_bug_scanner [default]
  [ok] stack.beads_viewer [default]
  [ok] stack.cass [default]
  [ok] stack.cm [default]
  [ok] stack.caam [default]
  [ok] stack.slb [default]

Phase 10 (acfs):
  [ok] acfs.onboard [default]
  [ok] acfs.doctor [default]

Legend: [ok] will install, [skip] skipped, [reason]
```

**Key insight:** `--print-plan` shows exactly what will happen before any changes are made.

---

### Story D2: Force Install Without Dependencies (Expert-Only)

**Command:**
```bash
./install.sh --only lang.bun --no-deps
```

**Output:**
```
WARNING: --no-deps disables automatic dependency expansion.
WARNING: Module lang.bun depends on: base.system
WARNING: These dependencies will NOT be installed automatically.
WARNING: Use --print-plan to verify the execution plan.

Effective plan (1 module):
  [ok] lang.bun (phase 6) [explicitly requested]

Proceed? [y/N]
```

**Use case:**
- Debugging dependency graph issues
- Testing module install in isolation (assumes deps already present)
- Understanding what a module actually installs

**Guardrails:**
- Prominent warning with dependency list
- Requires explicit confirmation (even with `--yes` in interactive terminals)
- `--print-plan` recommended before proceeding

---

### Story D3: Skip a Required Dependency (Error Case)

**Command:**
```bash
./install.sh --only agents.codex --skip lang.bun
```

**Output:**
```
ERROR: Cannot skip lang.bun

agents.codex depends on lang.bun.
Skipping a required dependency would leave the installation in a broken state.

Options:
  1. Remove --skip lang.bun to allow dependency installation
  2. Add --no-deps if you know lang.bun is already installed
  3. Skip agents.codex instead (--skip agents.codex)

For debugging: ./install.sh --only agents.codex --print-plan
```

**Why fail-fast matters:**
- Silent broken installs are worse than errors
- User gets actionable guidance
- Error names the exact dependency edge

---

### Story D4: List All Available Modules

**Command:**
```bash
./install.sh --list-modules
```

**Output:**
```
ACFS Modules (from acfs.manifest.yaml)
======================================

ID                           Phase  Category  Tags                      Default
---------------------------  -----  --------  ------------------------  -------
base.system                  1      base      critical                  [ok]
base.filesystem              3      base      critical                  [ok]
users.ubuntu                 2      users     orchestration             [ok]
shell.zsh                    4      shell     shell-ux, critical        [ok]
cli.modern                   5      cli       cli-modern                [ok]
lang.bun                     6      lang      runtime, critical         [ok]
lang.uv                      6      lang      runtime                   [ok]
lang.rust                    6      lang      runtime                   [ok]
lang.go                      6      lang      runtime                   [ok]
tools.atuin                  6      tools     shell-ux                  [ok]
tools.zoxide                 6      tools     shell-ux                  [ok]
tools.ast_grep               6      tools     cli-modern                [ok]
agents.claude                7      agents    agent                     [ok]
agents.codex                 7      agents    agent                     [ok]
agents.gemini                7      agents    agent                     [ok]
db.postgres18                8      cloud     database, optional        [skip]
tools.vault                  8      cloud     secrets, optional         [skip]
cloud.wrangler               8      cloud     cloud, optional           [skip]
cloud.supabase               8      cloud     cloud, optional           [skip]
cloud.convex                 8      cloud     cloud, optional           [skip]
cloud.vercel                 8      cloud     cloud, optional           [skip]
stack.ntm                    9      stack     agent                     [ok]
stack.mcp_agent_mail         9      stack     agent                     [ok]
stack.ultimate_bug_scanner   9      stack     agent                     [ok]
stack.beads_viewer           9      stack     agent                     [ok]
stack.cass                   9      stack     agent                     [ok]
stack.cm                     9      stack     agent                     [ok]
stack.caam                   9      stack     agent                     [ok]
stack.slb                    9      stack     agent                     [ok]
acfs.onboard                 10     acfs      orchestration             [ok]
acfs.doctor                  10     acfs      orchestration             [ok]

Total: 31 modules (25 enabled by default, 6 opt-in)

Filtering:
  --only <id1,id2,...>     Install specific modules + dependencies
  --only-phase <n,...>     Install all modules in phases
  --skip <id1,id2,...>     Skip specific modules
  --no-deps                Disable automatic dependency expansion
```

---

### Story D5: Combined Dry-Run Debugging

**Command:**
```bash
./install.sh --dry-run --only lang.bun,agents.claude --print-plan
```

**Output:**
```
Effective plan (3 modules):
  [ok] base.system (phase 1) [dependency of lang.bun]
  [ok] lang.bun (phase 6) [explicitly requested]
  [ok] agents.claude (phase 7) [explicitly requested]

[DRY-RUN] Would execute:
  Phase 1: base.system
    - sudo apt-get update -y
    - sudo apt-get install -y curl git ca-certificates ...
  Phase 6: lang.bun
    - acfs_run_verified_upstream_script_as_target bun bash
  Phase 7: agents.claude
    - acfs_run_verified_upstream_script_as_target claude bash

No changes made (dry-run mode).
```

**Why `--dry-run` with `--print-plan` is powerful:**
- Shows both the selection logic AND the commands
- Safe way to verify behavior before production runs
- CI pipeline validation

---

## Phase 1: Gap Analysis & Inventory

### 1.1 What install.sh Does That Manifest Doesn't Cover

| Capability | In install.sh | In Manifest | Gap |
|------------|---------------|-------------|-----|
| User normalization (root→ubuntu) | ✅ Full logic | ❌ Description only | LARGE |
| SSH key migration | ✅ Full logic | ❌ Not mentioned | LARGE |
| Sudoers configuration | ✅ Full logic | ❌ Description only | LARGE |
| Filesystem setup (/data/projects) | ✅ Full logic | ✅ Added | SMALL |
| Run as target user | ✅ `run_as_target` | ❌ No concept | LARGE |
| Verified upstream installers | ✅ `acfs_run_verified_upstream_script_as_target` | ❌ Just curl|bash | LARGE |
| Dry-run mode | ✅ Full support | ❌ No concept | MEDIUM |
| Mode (vibe vs safe) | ✅ Full support | ✅ In defaults | SMALL |
| Phase orchestration | ✅ 10 phases | ✅ Comments only | MEDIUM |
| Logging with gum | ✅ Full support | ❌ No concept | MEDIUM |
| Optional tool handling | ✅ `|| true` patterns | ⚠️ Implicit | SMALL |
| Checkpointing | ✅ `command_exists` checks | ❌ No concept | MEDIUM |

### 1.2 Tasks for Phase 1

- [ ] **1.1.1** Create detailed mapping of every install.sh function to manifest modules
- [ ] **1.1.2** Identify which install.sh functions are "orchestration" vs "module installation"
- [ ] **1.1.3** Document all `run_as_target` usages and which modules need it
- [ ] **1.1.4** Document all `acfs_run_verified_upstream_script_as_target` usages
- [ ] **1.1.5** Audit checksums.yaml for completeness against manifest modules
- [ ] **1.1.6** Identify all description-only modules and decide: `generated: false` or convert to commands
- [ ] **1.1.7** Inventory existing install.sh CLI flags used by the wizard/docs and map them to manifest-driven selection (tags/modules)
- [ ] **1.1.8** Inventory assets required at runtime (`acfs/**`, templates, onboarding lessons) so curl|bash bootstrap includes them

**Deliverable:** `docs/manifest-gap-analysis.md` with complete mapping

---

## Phase 2: Enhance Manifest Schema

### 2.1 New Schema Fields

```yaml
# Enhanced module schema
modules:
  - id: lang.bun
    description: Bun runtime for JS tooling
    category: lang                 # keep category explicit (for generated file layout)

    # NEW: Execution context
    run_as: target_user          # target_user | root | current

    # NEW: Verified installer reference
    verified_installer:
      tool: bun                  # Key in checksums.yaml
      runner: bash               # Executable (install.sh adds '-s --')
      args: []                   # Extra args passed to the upstream installer script

    # NEW: Installation behavior
    optional: false              # If true, failure is warning not error
    enabled_by_default: true     # NEW: allows manifest-driven defaults without removing modules
    installed_check:
      run_as: target_user
      command: "command -v bun"  # Skip if this succeeds (always runs, even in --dry-run)
    generated: true              # NEW: false to skip generation (orchestration-only)

    # NEW: Phase assignment (for ordering)
    phase: 6                     # Maps to install.sh phases 1-10

    # Install commands (shell strings).
    # Generator must execute these via run_as_*_shell (supports pipes/heredocs).
    install: []
    verify:
      - "bun --version"

    # NEW: Dependencies (for topological sort)
    dependencies:
      - base.system

    # NEW: Tags for higher-level CLI flags (wizard compatibility)
    tags: ["lang", "runtime"]
```

### 2.2 Schema Changes in Zod

```typescript
// packages/manifest/src/schema.ts additions

export const ModuleSchema = z.object({
  id: z.string().regex(/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$/),
  description: z.string(),

  category: z.string().optional(),

  // Execution context
  run_as: z.enum(['target_user', 'root', 'current']).default('target_user'),

  // Verified installer
  verified_installer: z.object({
    tool: z.string(),           // Key in checksums.yaml
    runner: z.string(),         // e.g., "bash", "sh" (install.sh supplies -s --)
    args: z.array(z.string()).default([]),
  }).optional(),

  // Installation behavior
  optional: z.boolean().default(false),
  enabled_by_default: z.boolean().default(true),
  installed_check: z.object({
    run_as: z.enum(['target_user', 'root', 'current']).default('target_user'),
    command: z.string(),
  }).optional(),
  generated: z.boolean().default(true),     // NEW: false to skip generation

  // Phase for ordering
  phase: z.number().int().min(1).max(10).optional(),

  // Install steps are shell strings (executed via run_as_*_shell).
  // Allow empty when verified_installer is provided.
  install: z.array(z.string()).default([]),
  verify: z.array(z.string()).min(1),
  dependencies: z.array(z.string()).optional(),
  notes: z.array(z.string()).optional(),
  tags: z.array(z.string()).optional(),
}).refine((m) => (m.generated === false) || (m.verified_installer != null) || (m.install.length > 0), {
  message: "Module must define verified_installer or install commands (or set generated: false).",
});

// Optional: enforce that orchestration-only modules do not contain install commands
// (keeps the manifest clean and avoids drift)
```

### 2.3 Phase + Dependency Ordering Rules

We have **two ordering concepts** and they must not conflict:

- **Phase** is the primary execution grouping: install.sh runs phases `1..10` in order.
- **Dependencies** are for ordering *within a phase* and for enforcing prerequisites across phases.

Rules:

1. A module may only depend on modules in the **same phase or an earlier phase**.
2. The generator must validate that all dependencies exist.
3. Within a phase, the generator must topologically sort modules using `dependencies` (stable by manifest order for ties).
4. If a dependency would require “future phase first” (dependency.phase > module.phase), that is a manifest error.

### 2.4 Manifest Index Generation (Enables Filtering + Dependency Closure in Bash)

Generator must also emit a small, sourceable index file:
`scripts/generated/manifest_index.sh` containing:
- `ACFS_MANIFEST_SHA256="..."`
- `declare -A ACFS_MODULE_PHASE=([lang.bun]=6 ...)`
- `declare -A ACFS_MODULE_DEPS=([lang.bun]="base.system,base.filesystem" ...)`
- `declare -A ACFS_MODULE_FUNC=([lang.bun]="install_lang_bun" ...)`
- `ACFS_MODULES_IN_ORDER=(base.system ... lang.bun ...)` (already topo-sorted within phase)

This index must have **no contract validation** and no side effects beyond declarations.

### 2.3 Tasks for Phase 2

- [ ] **2.1.1** Update `packages/manifest/src/schema.ts` with new fields
- [ ] **2.1.2** Update `packages/manifest/src/types.ts` with TypeScript types
- [ ] **2.1.3** Update `packages/manifest/src/parser.ts` to validate new fields
- [ ] **2.1.4** Add function name collision validation to parser
- [ ] **2.2.1** Migrate all 50+ modules in `acfs.manifest.yaml` to new schema
- [ ] **2.2.2** Add `verified_installer` to all curl|bash modules
- [ ] **2.2.3** Add `run_as: target_user` to user-space modules
- [ ] **2.2.4** Add `installed_check` to all modules (with correct run_as)
- [ ] **2.2.5** Assign `phase` numbers to all modules
- [ ] **2.2.6** Mark orchestration-only modules with `generated: false`
- [ ] **2.3.1** Validate dependency+phase rules (no future-phase deps, deps exist)
- [ ] **2.3.2** Validate manifest against checksums.yaml (all verified_installers have checksums)
- [ ] **2.4.1** Add manifest_index.sh generation and keep it deterministic
- [ ] **2.4.2** Add tags + enabled_by_default migration for existing “skip flags”

**Deliverable:** Enhanced manifest schema + fully migrated acfs.manifest.yaml

---

## Phase 3: Enhance Generator

### 3.1 Generated Script Structure

Each generated `install_<category>.sh` will contain:

```bash
# NOTE: This file is meant to be sourced. Shebang is allowed but ignored when sourced.
#!/usr/bin/env bash
# AUTO-GENERATED FROM acfs.manifest.yaml - DO NOT EDIT
# Regenerate: bun run --filter @acfs/manifest generate
# Manifest SHA256: <sha256-of-acfs.manifest.yaml>
# Generator: @acfs/manifest <version>

# ============================================================
# Module: lang.bun
# Phase: 6
# ============================================================
install_lang_bun() {
    local module_id="lang.bun"
    local module_phase="6"
    acfs_require_contract "module:${module_id}" || return 1

    # Check if this module should run (--only/--skip filtering)
    if ! should_run_module "$module_id" "$module_phase"; then
        log_detail "$module_id skipped (filtered)"
        return 0
    fi

    # Installed check (always runs; uses target user's PATH)
    if run_as_target_shell "command -v bun >/dev/null 2>&1"; then
        log_detail "$module_id already installed, skipping"
        return 0
    fi

    # Dry-run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_detail "dry-run: would install $module_id"
        log_detail "dry-run: would run: acfs_run_verified_upstream_script_as_target bun bash"
        return 0
    fi

    log_detail "Installing $module_id"

    # Verified upstream installer (install.sh supplies '-s --')
    if ! acfs_run_verified_upstream_script_as_target "bun" "bash"; then
        log_error "$module_id install failed"
        return 1
    fi

    # Verify installation
    if ! run_as_target_shell "bun --version >/dev/null 2>&1"; then
        log_error "$module_id verification failed"
        return 1
    fi

    log_success "$module_id installed"
}

# ... more modules ...

# Category installer (calls all modules in phase order)
install_lang() {
    install_lang_bun
    install_lang_uv
    install_lang_rust
    install_lang_go
}
```

### 3.2 Generator Enhancements

```typescript
// packages/manifest/src/generate.ts enhancements

function generateModuleFunction(module: Module): string {
  const lines: string[] = [];
  const funcName = toFunctionName(module.id);

  lines.push(`# Module: ${module.id}`);
  lines.push(`# Phase: ${module.phase ?? 'unassigned'}`);
  lines.push(`${funcName}() {`);
  lines.push(`    local module_id="${module.id}"`);
  lines.push(`    local module_phase="${module.phase ?? 0}"`);
  lines.push(`    acfs_require_contract "module:${module.id}" || return 1`);

  // Module filtering (--only/--skip)
  lines.push(`    if ! should_run_module "$module_id" "$module_phase"; then`);
  lines.push(`        log_detail "$module_id skipped (filtered)"`);
  lines.push(`        return 0`);
  lines.push(`    fi`);

  // Installed check (always runs, even in dry-run)
  if (module.installed_check) {
    const check = module.installed_check;
    const checkRunner = check.run_as === 'target_user'
      ? 'run_as_target_shell'
      : check.run_as === 'root'
        ? 'run_as_root_shell'
        : 'run_as_current_shell';
    lines.push(`    if ${checkRunner} "${escapeBashForDoubleQuotes(check.command)} >/dev/null 2>&1"; then`);
    lines.push(`        log_detail "$module_id already installed, skipping"`);
    lines.push(`        return 0`);
    lines.push(`    fi`);
  }

  // Dry-run mode
  lines.push(`    if [[ "\${DRY_RUN:-false}" == "true" ]]; then`);
  lines.push(`        log_detail "dry-run: would install $module_id"`);
  for (const cmd of module.install) {
    if (!looksLikeProse(cmd)) {
      lines.push(`        log_detail "dry-run: would run: ${escapeBashForLog(cmd)}"`);
    }
  }
  lines.push(`        return 0`);
  lines.push(`    fi`);

  lines.push(`    log_detail "Installing $module_id"`);

  // Handle verified installers
  if (module.verified_installer) {
    const { tool, runner, args } = module.verified_installer;

    // Runner must be validated/whitelisted (e.g., bash|sh) to prevent injection.
    if (module.run_as === 'target_user') {
      lines.push(`    if ! acfs_run_verified_upstream_script_as_target "${tool}" "${runner}" ${args.map(escapeForBash).join(' ')}`.trimEnd() + `; then`);
      lines.push(`        ${module.optional ? 'log_warn' : 'log_error'} "$module_id install failed"`);
      lines.push(`        ${module.optional ? 'return 0' : 'return 1'}`);
      lines.push(`    fi`);
    } else if (module.run_as === 'root') {
      lines.push(`    if ! acfs_run_verified_upstream_script_as_root "${tool}" "${runner}" ${args.map(escapeForBash).join(' ')}`.trimEnd() + `; then`);
      lines.push(`        ${module.optional ? 'log_warn' : 'log_error'} "$module_id install failed"`);
      lines.push(`        ${module.optional ? 'return 0' : 'return 1'}`);
      lines.push(`    fi`);
    } else {
      lines.push(`    if ! acfs_run_verified_upstream_script_as_current "${tool}" "${runner}" ${args.map(escapeForBash).join(' ')}`.trimEnd() + `; then`);
      lines.push(`        ${module.optional ? 'log_warn' : 'log_error'} "$module_id install failed"`);
      lines.push(`        ${module.optional ? 'return 0' : 'return 1'}`);
      lines.push(`    fi`);
    }
  } else {
    // Regular install commands
    for (const cmd of module.install) {
      if (looksLikeProse(cmd)) {
        lines.push(`    # NOTE: ${escapeBashForLog(cmd)}`);
        lines.push(`    # (move this to notes: or mark generated:false)`);
        continue;
      }

      if (module.run_as === 'target_user') {
        // Always execute install strings as shell commands (supports pipes/heredocs).
        lines.push(`    run_as_target_shell << 'ACFS_EOF_${module.id.replace(/[^a-z0-9]/gi, '_')}'`);
        lines.push(cmd);
        lines.push(`ACFS_EOF_${module.id.replace(/[^a-z0-9]/gi, '_')}`);
      } else if (module.run_as === 'root') {
        lines.push(`    run_as_root_shell << 'ACFS_EOF_${module.id.replace(/[^a-z0-9]/gi, '_')}'`);
        lines.push(cmd);
        lines.push(`ACFS_EOF_${module.id.replace(/[^a-z0-9]/gi, '_')}`);
      } else {
        lines.push(`    run_as_current_shell << 'ACFS_EOF_${module.id.replace(/[^a-z0-9]/gi, '_')}'`);
        lines.push(cmd);
        lines.push(`ACFS_EOF_${module.id.replace(/[^a-z0-9]/gi, '_')}`);
      }
    }
  }

  // Verification
  lines.push(`    # Verify`);
  for (const verify of module.verify) {
    const verifyRunner = module.run_as === 'target_user'
      ? 'run_as_target_shell'
      : module.run_as === 'root'
        ? 'run_as_root_shell'
        : 'run_as_current_shell';

    lines.push(`    if ! ${verifyRunner} ${escapeForBash(verify)}; then`);
    lines.push(`        ${module.optional ? 'log_warn' : 'log_error'} "$module_id verification failed"`);
    lines.push(`        ${module.optional ? 'return 0' : 'return 1'}`);
    lines.push(`    fi`);
  }

  lines.push(`    log_success "$module_id installed"`);
  lines.push(`}`);

  return lines.join('\n');
}
```

### 3.3 Tasks for Phase 3

- [ ] **3.1.1** Add `generateModuleFunction()` with run_as support
- [ ] **3.1.2** Add `generateVerifiedInstallerCall()` for checksummed installers
- [ ] **3.1.3** Add installed_check generation (run_as-aware)
- [ ] **3.1.4** Add optional module handling (warn vs error)
- [ ] **3.1.5** Add DRY_RUN mode support
- [ ] **3.1.6** Add module filtering support (--only/--skip)
- [ ] **3.2.1** Add `acfs_require_contract` calls in generated module functions
- [ ] **3.2.2** Generate module functions that use `run_as_target` correctly
- [ ] **3.2.3** Generate category functions that call modules in phase order
- [ ] **3.2.4** Skip modules with `generated: false`
- [ ] **3.3.1** Add function name collision detection (fail-fast)
- [ ] **3.3.2** Add `--validate` flag to generator (check manifest against checksums.yaml)
- [ ] **3.3.3** Add `--diff` flag to show what would change in generated scripts
- [ ] **3.3.4** Add deterministic metadata to generated file headers (manifest SHA256, generator version)
- [ ] **3.4.1** Generate `scripts/generated/manifest_index.sh` for dependency closure + module listing
- [ ] **3.4.2** Generate a machine-readable plan output (optional): `scripts/generated/manifest_index.json`

**Deliverable:** Enhanced generator that produces install.sh-compatible scripts

---

## Phase 4: Refactor install.sh

### 4.1 New install.sh Structure

**Critical:** install.sh must support both:

- **Local checkout:** `SCRIPT_DIR` points at a repo clone; `scripts/lib` and `scripts/generated` are available on disk.
- **curl|bash:** no checkout; install.sh must download a **single repo archive** for a single ref, extract the required files, validate them (`bash -n`), then `source` those local files.

```bash
#!/usr/bin/env bash
# ACFS Installer - Orchestration Layer
# Module installation logic is generated from acfs.manifest.yaml

set -euo pipefail

# SCRIPT_DIR is empty when running via curl|bash (stdin; no file on disk)
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

bootstrap_sources_if_needed() {
  if [[ -n "$SCRIPT_DIR" ]]; then
    export ACFS_LIB_DIR="$SCRIPT_DIR/scripts/lib"
    export ACFS_GENERATED_DIR="$SCRIPT_DIR/scripts/generated"
    export ACFS_ASSETS_DIR="$SCRIPT_DIR/acfs"
    export ACFS_CHECKSUMS_YAML="$SCRIPT_DIR/checksums.yaml"
    export ACFS_MANIFEST_YAML="$SCRIPT_DIR/acfs.manifest.yaml"
    return 0
  fi

  # curl|bash mode: prefer a single repo archive download for self-consistency.
  : "${ACFS_REPO_OWNER:?}"
  : "${ACFS_REPO_NAME:?}"
  : "${ACFS_REF:?}"

  ACFS_BOOTSTRAP_DIR="${ACFS_BOOTSTRAP_DIR:-$(mktemp -d /tmp/acfs-bootstrap-XXXXXX)}"
  export ACFS_LIB_DIR="$ACFS_BOOTSTRAP_DIR/scripts/lib"
  export ACFS_GENERATED_DIR="$ACFS_BOOTSTRAP_DIR/scripts/generated"
  export ACFS_ASSETS_DIR="$ACFS_BOOTSTRAP_DIR/acfs"
  export ACFS_CHECKSUMS_YAML="$ACFS_BOOTSTRAP_DIR/checksums.yaml"
  export ACFS_MANIFEST_YAML="$ACFS_BOOTSTRAP_DIR/acfs.manifest.yaml"

  # Download archive: https://github.com/<owner>/<repo>/archive/<ref>.tar.gz
  # Extract, validate, then source.
  #
  # MUST:
  # - download to temp file
  # - validate tarball exists + extract succeeds
  # - run bash -n scripts/lib/*.sh scripts/generated/*.sh before sourcing
  # - optional: trap cleanup unless ACFS_KEEP_BOOTSTRAP=1
}

bootstrap_sources_if_needed

# ============================================================
# Source libraries (order matters!)
# ============================================================
source "$ACFS_LIB_DIR/logging.sh"
source "$ACFS_LIB_DIR/security.sh"
source "$ACFS_LIB_DIR/contract.sh"
source "$ACFS_LIB_DIR/install_helpers.sh"  # NEW: filtering + run_as_*_shell helpers

# ============================================================
# Orchestration (NOT generated - hand-maintained)
# ============================================================

main() {
    parse_args "$@"
    detect_environment
    # Now that runtime vars exist, source generated installers + manifest index.
    source "$ACFS_GENERATED_DIR/manifest_index.sh"
    source "$ACFS_GENERATED_DIR/install_base.sh"
    source "$ACFS_GENERATED_DIR/install_shell.sh"
    source "$ACFS_GENERATED_DIR/install_cli.sh"
    source "$ACFS_GENERATED_DIR/install_lang.sh"
    source "$ACFS_GENERATED_DIR/install_agents.sh"
    source "$ACFS_GENERATED_DIR/install_cloud.sh"
    source "$ACFS_GENERATED_DIR/install_stack.sh"
    source "$ACFS_GENERATED_DIR/install_acfs.sh"

    # Compute effective selection once (deps + filters).
    acfs_resolve_selection

    # Phase 1: Base dependencies
    log_step "1/10" "Checking base dependencies..."
    install_base_system  # FROM GENERATED

    # Phase 2: User normalization (complex orchestration, stays here)
    log_step "2/10" "Normalizing user account..."
    normalize_user  # Hand-maintained (too complex for manifest)

    # Phase 3: Filesystem setup
    log_step "3/10" "Setting up filesystem..."
    install_base_filesystem  # FROM GENERATED

    # Phase 4: Shell setup
    log_step "4/10" "Setting up shell..."
    install_shell  # FROM GENERATED (shell.zsh, cli.modern)

    # Phase 5: CLI tools
    log_step "5/10" "Installing CLI tools..."
    install_cli  # FROM GENERATED

    # Phase 6: Language runtimes
    log_step "6/10" "Installing language runtimes..."
    install_lang  # FROM GENERATED (bun, uv, rust, go, atuin, zoxide)

    # Phase 7: Coding agents
    log_step "7/10" "Installing coding agents..."
    install_agents  # FROM GENERATED (claude, codex, gemini)

    # Phase 8: Cloud & database tools
    log_step "8/10" "Installing cloud & database tools..."
    install_cloud  # FROM GENERATED (vault, postgres, wrangler, supabase, convex, vercel)

    # Phase 9: Dicklesworthstone stack
    log_step "9/10" "Installing Dicklesworthstone stack..."
    install_stack  # FROM GENERATED (ntm, mcp_agent_mail, ubs, bv, cass, cm, caam, slb)

    # Phase 10: Finalization
    log_step "10/10" "Finalizing installation..."
    install_acfs  # FROM GENERATED (onboard, doctor)
    finalize      # Hand-maintained (tmux config, smoke test)
}
```

### 4.2 New scripts/lib/install_helpers.sh

```bash
#!/usr/bin/env bash
# Install helpers - module filtering and command execution helpers

# Module filtering arrays (set by parse_args)
ONLY_MODULES=()
ONLY_PHASES=()
SKIP_MODULES=()
NO_DEPS="false"
PRINT_PLAN="false"

# Run a shell string as the target user (supports pipes/heredocs)
run_as_target_shell() {
    local cmd="${1:-}"
    if [[ -n "$cmd" ]]; then
        # NOTE: Only safe for simple one-liners; generator should prefer heredocs for multi-line scripts.
        run_as_target bash -lc "set -euo pipefail; $cmd"
        return $?
    fi

    # stdin mode (for heredocs):
    # Prepend strict-mode settings inside the script we execute so pipes inside the script are covered.
    run_as_target bash -lc 'set -euo pipefail; (printf "%s\n" "set -euo pipefail"; cat) | bash -s'
}

# Run a shell string as root (install.sh usually ensures we're root already)
run_as_root_shell() {
    local cmd="${1:-}"
    if [[ -n "$cmd" ]]; then
        if [[ "$EUID" -eq 0 ]]; then
            bash -lc "set -euo pipefail; $cmd"
        else
            $SUDO bash -lc "set -euo pipefail; $cmd"
        fi
        return $?
    fi

    if [[ "$EUID" -eq 0 ]]; then
        bash -lc 'set -euo pipefail; (printf "%s\n" "set -euo pipefail"; cat) | bash -s'
    else
        $SUDO bash -lc 'set -euo pipefail; (printf "%s\n" "set -euo pipefail"; cat) | bash -s'
    fi
}

# Run a shell string as the current user
run_as_current_shell() {
    local cmd="${1:-}"
    if [[ -n "$cmd" ]]; then
        bash -lc "set -euo pipefail; $cmd"
        return $?
    fi

    bash -lc 'set -euo pipefail; (printf "%s\n" "set -euo pipefail"; cat) | bash -s'
}

# Check if a command exists in the target user's environment
command_exists_as_target() {
    local cmd="$1"
    run_as_target bash -lc "command -v '$cmd' >/dev/null 2>&1"
}

# Effective selection computed once after manifest_index is sourced
declare -A ACFS_EFFECTIVE_RUN=()

acfs_resolve_selection() {
    # Requires scripts/generated/manifest_index.sh to be sourced.
    # Populates ACFS_EFFECTIVE_RUN with the final module set.
    :
}

should_run_module() {
    local module_id="$1"
    [[ -n "${ACFS_EFFECTIVE_RUN[$module_id]:-}" ]] && return 0
    return 1
}

list_all_modules() {
    # Prefer generated manifest index output; never hardcode.
    acfs_manifest_list_modules
}
```

### 4.3 What Stays in install.sh (Hand-Maintained)

| Function | Reason |
|----------|--------|
| `parse_args` | CLI argument parsing |
| `detect_environment` | OS detection, variable setup |
| `normalize_user` | Complex root→ubuntu logic, SSH key migration |
| `finalize` | Tmux config, smoke test, final messaging |
| `run_as_target` | Utility function used by generated scripts |
| `acfs_run_verified_upstream_script_as_target` | Security wrapper |
| `install_gum_early` | Bootstrap UI before other tools |
| `bootstrap_sources_if_needed` | Archive download + extraction + coherence checks |
| `acfs_resolve_selection` | Computes final module set once (filters + deps) |

### 4.4 What Moves to Generated Scripts

All module installation logic:
- `install_bun`, `install_uv`, `install_rust`, `install_go`
- `install_claude`, `install_codex`, `install_gemini`
- `install_ntm`, `install_slb`, `install_ubs`, etc.
- `install_postgres`, `install_vault`
- `install_zsh`, `install_ohmyzsh`

### 4.5 Tasks for Phase 4

- [ ] **4.1.1** Extract shared functions to `scripts/lib/` (run_as_target, etc.)
- [ ] **4.1.2** Create `scripts/lib/install_helpers.sh` with module filtering
- [ ] **4.1.3** Add --only, --skip, --only-phase, --list-modules to parse_args
- [ ] **4.1.4** Add --no-deps and dependency-closure selection (powered by manifest_index)
- [ ] **4.1.5** Keep legacy flags working by mapping them to module/tags selection
- [ ] **4.1.6** Implement archive bootstrap with bash -n validation + coherence checks
- [ ] **4.2.1** Add `source` statements for generated scripts in install.sh
- [ ] **4.2.2** Replace inline module installation with calls to generated functions
- [ ] **4.2.3** Keep orchestration logic (phases, user normalization, finalization)
- [ ] **4.3.1** Test that sourcing works correctly
- [ ] **4.3.2** Ensure generated function names don't conflict with existing
- [ ] **4.4.1** Add CI check that generated scripts are up-to-date with manifest

**Deliverable:** Refactored install.sh that sources generated scripts

---

## Phase 5: Testing & Validation

### 5.1 Test Matrix

| Test | Method | Pass Criteria |
|------|--------|---------------|
| Generator produces valid bash | `shellcheck scripts/lib/*.sh scripts/generated/*.sh` | No errors |
| Generated scripts source correctly | `bash -c 'source scripts/generated/install_lang.sh'` (with mocked contract) | No strict-mode leaks, no top-level side effects |
| Contract validation works | Invoke a module function without env | Error message shown |
| DRY_RUN mode works | `./install.sh --dry-run` | No actual installation |
| --only filtering works | `./install.sh --only lang.bun` | Only bun installed |
| Dependency closure works | `./install.sh --only lang.bun` on fresh VPS | Base deps installed automatically |
| --no-deps works | `./install.sh --only lang.bun --no-deps` | Clear failure or clear warning |
| --skip filtering works | `./install.sh --skip stack.slb` | slb skipped |
| Skip-dep error | `./install.sh --only lang.bun --skip base.system` | Fails early with “skipped required dependency” |
| Full installation (Ubuntu 24.04) | Docker test | Smoke test passes |
| Full installation (Ubuntu 25.04) | Docker test | Smoke test passes |
| Idempotent re-run | Run installer twice | No errors, same result |
| Doctor checks align | `acfs doctor` | All checks pass |
| Manifest→Generated sync | CI check | Generated matches manifest |
| Simulated curl|bash bootstrap (offline) | `./tests/vm/test_curl_bash_simulation.sh` | Bootstraps + sources correctly |

### 5.2 CI Integration

```yaml
# .github/workflows/manifest-sync.yml
name: Manifest Sync Check

on: [push, pull_request]

jobs:
  check-generated:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v1

      - name: Install dependencies
        run: bun install --frozen-lockfile

      - name: Generate scripts from manifest
        run: bun run --filter @acfs/manifest generate

      - name: Check for uncommitted changes
        run: |
          git diff --exit-code -- scripts/generated/ || {
            echo "Generated scripts are out of sync with manifest!"
            echo "Run: bun run --filter @acfs/manifest generate"
            git diff -- scripts/generated/
            exit 1
          }

      - name: Run shellcheck on generated scripts
        run: |
          shellcheck scripts/lib/*.sh scripts/generated/*.sh

      - name: Validate bash syntax
        run: |
          for script in scripts/generated/*.sh; do
            bash -n "$script"
          done

      - name: Simulate curl|bash bootstrap (offline)
        run: |
          # Ensures the curl|bash code path stays healthy without requiring network.
          ./tests/vm/test_curl_bash_simulation.sh
```

### 5.3 Tasks for Phase 5

- [ ] **5.1.1** Run shellcheck on all generated scripts
- [ ] **5.1.2** Run `bash -n` on install.sh with sourced scripts
- [ ] **5.1.3** Test contract validation (source without environment)
- [ ] **5.1.4** Test DRY_RUN mode
- [ ] **5.1.5** Test --only and --skip filtering
- [ ] **5.2.1** Test full installation in Docker (Ubuntu 24.04)
- [ ] **5.2.2** Test full installation in Docker (Ubuntu 25.04)
- [ ] **5.2.3** Test idempotent re-run (installer twice)
- [ ] **5.3.1** Verify `acfs doctor` passes after installation
- [ ] **5.3.2** Verify doctor_checks.sh aligns with doctor.sh
- [ ] **5.4.1** Add CI workflow to check generated scripts are in sync
- [ ] **5.4.2** Add CI workflow to run shellcheck on generated scripts

**Deliverable:** Passing test suite + CI integration

---

## Phase 6: Documentation & Cleanup

### 6.1 Tasks

- [ ] **6.1.1** Update README.md to remove "does not invoke scripts/generated/* yet"
- [ ] **6.1.2** Document new manifest schema fields in README.md
- [ ] **6.1.3** Add `docs/manifest-schema.md` with full schema documentation
- [ ] **6.1.4** Document environment contract in README.md
- [ ] **6.1.5** Update AGENTS.md with manifest workflow
- [ ] **6.2.1** Remove any dead code from install.sh
- [ ] **6.2.2** Remove duplicate module definitions
- [ ] **6.3.1** Add pre-commit hook to regenerate scripts on manifest change
- [ ] **6.3.2** Add an internal maintainer guide for adding new modules (no outside contributors policy)
- [ ] **6.3.3** Update wizard/docs commands to prefer tagged releases (still allow main for bleeding edge)

**Deliverable:** Updated documentation, clean codebase

---

## Migration Strategy

### Incremental Approach (Recommended)

Rather than a big-bang migration, do it incrementally:

1. **Weeks 1-2:** Phase 1 (Gap analysis) + Phase 2 (Schema enhancement)
2. **Weeks 3-4:** Phase 3 (Generator enhancement)
3. **Weeks 5-6:** Phase 4 (Refactor install.sh) - ONE CATEGORY AT A TIME
   - Start with `install_lang` (easiest, most isolated)
   - Then `install_stack` (all use verified installers)
   - Then `install_agents`
   - Then `install_cloud`
   - Finally `install_shell` (most complex)
4. **Week 7:** Phase 5 (Testing)
5. **Week 8:** Phase 6 (Documentation) + buffer

### Rollback Plan

At each step, keep the old code behind a feature flag (no commented code).

Add one of:
- `--legacy` (forces old inline installers)
- `ACFS_USE_GENERATED=0/1` (global)
- `ACFS_USE_GENERATED_CATEGORIES="lang,stack"` (optional, for incremental rollout)

```bash
# Phase 6: Language runtimes
log_step "6/10" "Installing language runtimes..."

if [[ "${ACFS_USE_GENERATED_LANG:-1}" == "1" ]]; then
  install_lang        # generated
else
  install_lang_legacy # legacy
fi
```

### Category Migration Order

| Order | Category | Complexity | Notes |
|-------|----------|------------|-------|
| 1 | lang | Low | All use verified installers, isolated |
| 2 | stack | Low | All use verified installers |
| 3 | agents | Medium | Mixed installers (Claude may be native) |
| 4 | cloud | Medium | Mix of apt and bun |
| 5 | cli | Medium | Many apt packages |
| 6 | shell | High | Oh-my-zsh, plugins, complex config |
| 7 | base | Low | Simple apt install |
| 8 | acfs | Low | Just file copies |

---

## Success Criteria

| Metric | Target |
|--------|--------|
| install.sh line count | < 500 lines (from 1575) |
| Manifest coverage | 100% of installed modules defined |
| Generated script usage | 100% of module installations use generated scripts |
| CI checks | Manifest-to-generated sync enforced |
| Test coverage | Docker tests for Ubuntu 24.04 + 25.04 |
| Doctor alignment | doctor.sh checks match manifest verify commands |
| Contract validation | 100% of generated scripts validate environment |
| Filtering support | --only, --skip, --only-phase all work |
| Dependency safety | --only expands deps by default; skipping required deps fails early |
| curl|bash reliability | Single-archive bootstrap; no mixed-ref installs |

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking existing installations | High | Incremental migration, thorough testing |
| Generated scripts have bugs | High | Shellcheck, Docker testing, contract validation |
| Complex modules can't be generated | Medium | `generated: false` escape hatch |
| Developer forgets to regenerate | Medium | CI check, pre-commit hook |
| Performance regression | Low | Profile before/after |
| Function name collisions | Medium | Generator validates uniqueness |
| Environment contract violations | Medium | Runtime validation in generated scripts |
| Mixed-ref curl|bash installs | Medium | Archive bootstrap + coherence check |
| Optional module kills install under set -e | Medium | Explicit error handling in generated functions |
| Legacy flags drift from manifest | Medium | Map legacy flags to tags/modules from manifest_index |

---

## Timeline

| Week | Phase | Deliverable |
|------|-------|-------------|
| 1-2 | Gap Analysis + Schema | `docs/manifest-gap-analysis.md`, enhanced schema |
| 3-4 | Generator Enhancement | Updated generate.ts with all new features |
| 5-6 | install.sh Refactor | Sourcing generated scripts, one category at a time |
| 7 | Testing | Passing Docker tests, CI integration |
| 8 | Documentation + Buffer | Updated docs, pre-commit hooks |

**Total estimated effort:** 6-8 weeks

---

## Appendix A: Module Migration Checklist

For each module, verify:

- [ ] Has `verified_installer` if uses curl|bash
- [ ] Has `run_as: target_user` if installs to user home
- [ ] Has `installed_check` for skip-if-installed logic (with correct run_as)
- [ ] Has `phase` number assigned
- [ ] Has `optional: true` if failure is non-fatal
- [ ] Has `generated: false` if orchestration-only (description commands)
- [ ] Install commands are actual commands (not descriptions)
- [ ] Verify commands work as target user
- [ ] Entry in checksums.yaml (if verified installer)
- [ ] No function name collision with other modules

---

## Appendix B: Quick Reference

### Adding a New Module

1. Add to `acfs.manifest.yaml`:
```yaml
- id: tools.mytool
  description: My awesome tool
  phase: 6
  run_as: target_user
  installed_check:
    run_as: target_user
    command: "command -v mytool"
  verified_installer:
    tool: mytool
    runner: bash
    args: []
  install: []
  verify:
    - mytool --version
```

2. Add checksum to `checksums.yaml`:
```yaml
mytool:
  url: "https://example.com/install.sh"
  sha256: "abc123..."
```

3. Regenerate:
```bash
bun run --filter @acfs/manifest generate
```

4. Commit both manifest and generated changes.

### Testing a Single Module

```bash
# Dry run
./install.sh --dry-run --only tools.mytool

# Actual install
./install.sh --only tools.mytool

# Verify
mytool --version
```

---

## Appendix C: curl|bash Bootstrap Pseudocode (Atomic + Self-Consistent)

```bash
bootstrap_sources_if_needed() {
  # if local checkout: just set *_DIR variables and return
  # else:
  # 1) mktemp -d
  # 2) download archive to tmpfile
  # 3) extract
  # 4) bash -n scripts/lib/*.sh scripts/generated/*.sh
  # 5) verify manifest sha matches headers in generated scripts (optional but recommended)
  # 6) set ACFS_*_DIR variables pointing at extracted tree
  # 7) trap cleanup unless ACFS_KEEP_BOOTSTRAP=1
}
```
