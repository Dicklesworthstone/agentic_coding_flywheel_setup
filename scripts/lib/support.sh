#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Support Bundle - Collect diagnostic data for troubleshooting
# Usage: acfs support-bundle [--verbose] [--output DIR]
# Output: ~/.acfs/support/<timestamp>/ + .tar.gz archive
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACFS_HOME="${ACFS_HOME:-$HOME/.acfs}"

# Source logging utilities
if [[ -f "$SCRIPT_DIR/logging.sh" ]]; then
    source "$SCRIPT_DIR/logging.sh"
fi

# Fallback log functions if logging.sh not available
if ! declare -f log_step >/dev/null 2>&1; then
    log_step()    { echo "[*] $*" >&2; }
    log_section() { echo "" >&2; echo "=== $* ===" >&2; }
    log_detail()  { echo "    $*" >&2; }
    log_success() { echo "[OK] $*" >&2; }
    log_warn()    { echo "[WARN] $*" >&2; }
    log_error()   { echo "[ERR] $*" >&2; }
fi

# ============================================================
# Configuration
# ============================================================
VERBOSE=false
REDACT=true
OUTPUT_BASE="${ACFS_HOME}/support"
REDACTION_COUNT=0
DOCTOR_TIMEOUT="${SUPPORT_BUNDLE_DOCTOR_TIMEOUT:-120}"

# ============================================================
# Parse arguments
# ============================================================
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --output|-o)
            if [[ -z "${2:-}" || "$2" == -* ]]; then
                log_error "--output requires a directory path"
                exit 1
            fi
            OUTPUT_BASE="$2"
            shift 2
            ;;
        --no-redact)
            REDACT=false
            shift
            ;;
        --help|-h)
            echo "Usage: acfs support-bundle [options]"
            echo ""
            echo "Collect diagnostic data into a tarball for troubleshooting."
            echo "Sensitive data (API keys, tokens, secrets) is redacted by default."
            echo ""
            echo "Options:"
            echo "  --verbose, -v    Show detailed output during collection"
            echo "  --output, -o DIR Output directory (default: ~/.acfs/support)"
            echo "  --no-redact      Disable secret redaction (WARNING: bundle may contain secrets)"
            echo "  --help, -h       Show this help"
            echo ""
            echo "Output:"
            echo "  ~/.acfs/support/<timestamp>/          Unpacked bundle directory"
            echo "  ~/.acfs/support/<timestamp>.tar.gz    Compressed archive"
            echo "  ~/.acfs/support/<timestamp>/manifest.json  Bundle manifest"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Try 'acfs support-bundle --help' for usage." >&2
            exit 1
            ;;
    esac
done

# ============================================================
# Bundle collection functions
# ============================================================

# Safely copy a file into the bundle, logging the result.
# Usage: collect_file <source_path> <bundle_subdir> [display_name]
collect_file() {
    local src="$1"
    local dest_dir="$2"
    local display="${3:-$(basename "$src")}"

    if [[ -f "$src" ]]; then
        mkdir -p "$dest_dir"
        cp "$src" "$dest_dir/" 2>/dev/null || {
            log_warn "Could not copy: $display"
            return 1
        }
        [[ "$VERBOSE" == "true" ]] && log_detail "Collected: $display"
        BUNDLE_FILES+=("$display")
        return 0
    else
        [[ "$VERBOSE" == "true" ]] && log_detail "Not found: $display"
        return 1
    fi
}

# Capture doctor JSON output.
# Usage: capture_doctor_json <bundle_dir>
capture_doctor_json() {
    local bundle_dir="$1"

    local doctor_script=""
    if [[ -f "$ACFS_HOME/scripts/lib/doctor.sh" ]]; then
        doctor_script="$ACFS_HOME/scripts/lib/doctor.sh"
    elif [[ -f "$SCRIPT_DIR/doctor.sh" ]]; then
        doctor_script="$SCRIPT_DIR/doctor.sh"
    fi

    if [[ -n "$doctor_script" ]]; then
        log_detail "Running acfs doctor --json ..."
        if timeout "$DOCTOR_TIMEOUT" bash "$doctor_script" doctor --json > "$bundle_dir/doctor.json" 2>/dev/null; then
            BUNDLE_FILES+=("doctor.json")
            return 0
        else
            log_warn "Doctor check timed out or failed"
            # Write partial output marker
            echo '{"error": "doctor check failed or timed out"}' > "$bundle_dir/doctor.json"
            BUNDLE_FILES+=("doctor.json (partial)")
            return 1
        fi
    else
        log_warn "doctor.sh not found, skipping doctor output"
        return 1
    fi
}

# Capture tool versions.
# Usage: capture_versions <bundle_dir>
capture_versions() {
    local bundle_dir="$1"
    local versions_file="$bundle_dir/versions.json"

    if ! command -v jq &>/dev/null; then
        log_warn "jq not available, skipping versions capture"
        return 1
    fi

    local versions="{}"

    # Helper to safely get a version string
    _ver() {
        local cmd="$1"
        local args="${2:---version}"
        if command -v "$cmd" &>/dev/null; then
            timeout 5 "$cmd" $args 2>/dev/null | head -1 || echo "error"
        else
            echo "not installed"
        fi
    }

    versions=$(jq -n \
        --arg bash_ver "${BASH_VERSION:-unknown}" \
        --arg zsh_ver "$(_ver zsh --version)" \
        --arg node_ver "$(_ver node -v)" \
        --arg bun_ver "$(_ver bun --version)" \
        --arg cargo_ver "$(_ver cargo --version)" \
        --arg go_ver "$(_ver go version)" \
        --arg python_ver "$(_ver python3 --version)" \
        --arg uv_ver "$(_ver uv --version)" \
        --arg git_ver "$(_ver git --version)" \
        --arg claude_ver "$(_ver claude --version)" \
        --arg gh_ver "$(_ver gh --version)" \
        --arg jq_ver "$(_ver jq --version)" \
        --arg tmux_ver "$(_ver tmux -V)" \
        --arg rg_ver "$(_ver rg --version)" \
        '{
            bash: $bash_ver,
            zsh: $zsh_ver,
            node: $node_ver,
            bun: $bun_ver,
            cargo: $cargo_ver,
            go: $go_ver,
            python3: $python_ver,
            uv: $uv_ver,
            git: $git_ver,
            claude: $claude_ver,
            gh: $gh_ver,
            jq: $jq_ver,
            tmux: $tmux_ver,
            ripgrep: $rg_ver
        }') || versions='{"error": "failed to collect versions"}'

    echo "$versions" > "$versions_file"
    BUNDLE_FILES+=("versions.json")
}

# Capture environment summary.
# Usage: capture_env_summary <bundle_dir>
capture_env_summary() {
    local bundle_dir="$1"
    local env_file="$bundle_dir/environment.json"

    if ! command -v jq &>/dev/null; then
        log_warn "jq not available, skipping environment capture"
        return 1
    fi

    local os_id="unknown"
    local os_version="unknown"
    local os_codename="unknown"
    if [[ -f /etc/os-release ]]; then
        os_id=$(. /etc/os-release && echo "${ID:-unknown}")
        os_version=$(. /etc/os-release && echo "${VERSION_ID:-unknown}")
        os_codename=$(. /etc/os-release && echo "${VERSION_CODENAME:-unknown}")
    fi

    local acfs_version="unknown"
    if [[ -f "$ACFS_HOME/VERSION" ]]; then
        acfs_version=$(cat "$ACFS_HOME/VERSION" 2>/dev/null) || acfs_version="unknown"
    fi

    jq -n \
        --arg hostname "$(hostname 2>/dev/null || echo unknown)" \
        --arg kernel "$(uname -r 2>/dev/null || echo unknown)" \
        --arg arch "$(uname -m 2>/dev/null || echo unknown)" \
        --arg os_id "$os_id" \
        --arg os_version "$os_version" \
        --arg os_codename "$os_codename" \
        --arg user "$(whoami 2>/dev/null || echo unknown)" \
        --arg home "$HOME" \
        --arg acfs_home "$ACFS_HOME" \
        --arg acfs_version "$acfs_version" \
        --arg shell "$SHELL" \
        --argjson uptime_seconds "$(cat /proc/uptime 2>/dev/null | awk '{printf "%d", $1}' || echo 0)" \
        --argjson mem_total_kb "$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)" \
        --argjson mem_available_kb "$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)" \
        --argjson disk_total_kb "$(df -k "$HOME" 2>/dev/null | tail -1 | awk '{print $2}' || echo 0)" \
        --argjson disk_available_kb "$(df -k "$HOME" 2>/dev/null | tail -1 | awk '{print $4}' || echo 0)" \
        '{
            hostname: $hostname,
            kernel: $kernel,
            arch: $arch,
            os: {id: $os_id, version: $os_version, codename: $os_codename},
            user: $user,
            home: $home,
            acfs_home: $acfs_home,
            acfs_version: $acfs_version,
            shell: $shell,
            uptime_seconds: $uptime_seconds,
            memory: {total_kb: $mem_total_kb, available_kb: $mem_available_kb},
            disk: {total_kb: $disk_total_kb, available_kb: $disk_available_kb}
        }' > "$env_file" 2>/dev/null || {
        log_warn "Failed to capture environment"
        return 1
    }

    BUNDLE_FILES+=("environment.json")
}

# Write a manifest JSON describing the bundle contents.
# Usage: write_manifest <bundle_dir>
write_manifest() {
    local bundle_dir="$1"
    local manifest_file="$bundle_dir/manifest.json"

    if ! command -v jq &>/dev/null; then
        # Fallback: write a simple text manifest
        printf '%s\n' "${BUNDLE_FILES[@]}" > "$bundle_dir/manifest.txt"
        return 0
    fi

    local acfs_version="unknown"
    if [[ -f "$ACFS_HOME/VERSION" ]]; then
        acfs_version=$(cat "$ACFS_HOME/VERSION" 2>/dev/null) || acfs_version="unknown"
    fi

    # Build files array from BUNDLE_FILES
    local files_json
    files_json=$(printf '%s\n' "${BUNDLE_FILES[@]}" | jq -R . | jq -s .) || files_json="[]"

    jq -n \
        --argjson schema_version 1 \
        --arg created_at "$(date -Iseconds)" \
        --arg created_by "acfs support-bundle" \
        --arg acfs_version "$acfs_version" \
        --arg bundle_dir "$(basename "$bundle_dir")" \
        --argjson files "$files_json" \
        --argjson file_count "${#BUNDLE_FILES[@]}" \
        --argjson redaction_enabled "$( [[ "$REDACT" == "true" ]] && echo true || echo false )" \
        --argjson redaction_files_modified "$REDACTION_COUNT" \
        '{
            schema_version: $schema_version,
            created_at: $created_at,
            created_by: $created_by,
            acfs_version: $acfs_version,
            bundle_id: $bundle_dir,
            file_count: $file_count,
            files: $files,
            redaction: {
                enabled: $redaction_enabled,
                files_modified: $redaction_files_modified,
                patterns: ["api_key", "aws_key", "github_token", "github_pat", "vault_token", "slack_token", "bearer", "jwt", "password", "generic_secret"]
            }
        }' > "$manifest_file" 2>/dev/null || return 1
}

# ============================================================
# Redaction
# ============================================================

# Redact sensitive values from a single text file in-place.
# Increments REDACTION_COUNT for each substitution made.
# Usage: redact_file <file_path>
redact_file() {
    local file="$1"

    # Skip binary files (check first 512 bytes for null bytes)
    # -a forces grep to treat input as text (otherwise it silently skips binary data)
    if head -c 512 "$file" 2>/dev/null | grep -qaP '\x00'; then
        return 0
    fi

    # Count lines before redaction for diff
    local before_hash
    before_hash=$(md5sum "$file" 2>/dev/null | awk '{print $1}') || return 0

    # Apply redaction patterns using sed -E (extended regex)
    # Order: specific patterns first, then generic catch-alls
    sed -E -i \
        -e 's/sk-[a-zA-Z0-9_-]{20,}/<REDACTED:api_key>/g' \
        -e 's/AKIA[A-Z0-9]{16}/<REDACTED:aws_key>/g' \
        -e 's/ghp_[a-zA-Z0-9]{36,}/<REDACTED:github_token>/g' \
        -e 's/ghs_[a-zA-Z0-9]{36,}/<REDACTED:github_token>/g' \
        -e 's/github_pat_[a-zA-Z0-9_]{22,}/<REDACTED:github_pat>/g' \
        -e 's/hvs\.[a-zA-Z0-9]{20,}/<REDACTED:vault_token>/g' \
        -e 's/xox[bpsar]-[a-zA-Z0-9-]{10,}/<REDACTED:slack_token>/g' \
        -e 's/Bearer [a-zA-Z0-9._\/-]{10,}/Bearer <REDACTED:bearer>/g' \
        -e 's/eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}/<REDACTED:jwt>/g' \
        "$file" 2>/dev/null || return 0

    # JSON-style secrets: "key_name": "value"
    sed -E -i \
        -e 's/"(api_key|API_KEY|ApiKey|api_secret|API_SECRET|secret_key|SECRET_KEY|access_token|ACCESS_TOKEN|refresh_token|REFRESH_TOKEN|auth_token|AUTH_TOKEN|client_secret|CLIENT_SECRET|private_key|PRIVATE_KEY)"[ ]*:[ ]*"([^"]{8,})"/"\1": "<REDACTED:\1>"/g' \
        -e 's/"(password|PASSWORD|passwd|PASSWD)"[ ]*:[ ]*"([^"]{4,})"/"\1": "<REDACTED:password>"/g' \
        "$file" 2>/dev/null || return 0

    # Generic key=value secrets (case-insensitive would need per-line processing;
    # instead match common casings)
    sed -E -i \
        -e 's/(api_key|API_KEY|ApiKey|api_secret|API_SECRET|secret_key|SECRET_KEY|access_token|ACCESS_TOKEN|refresh_token|REFRESH_TOKEN|auth_token|AUTH_TOKEN|client_secret|CLIENT_SECRET|private_key|PRIVATE_KEY)([=:]["'"'"']?)([^ "'"'"'\n]{8,})/\1\2<REDACTED:\1>/g' \
        -e 's/(password|PASSWORD|passwd|PASSWD)([=:]["'"'"']?)([^ "'"'"'\n]{4,})/\1\2<REDACTED:password>/g' \
        "$file" 2>/dev/null || return 0

    # Check if file changed
    local after_hash
    after_hash=$(md5sum "$file" 2>/dev/null | awk '{print $1}') || return 0
    if [[ "$before_hash" != "$after_hash" ]]; then
        REDACTION_COUNT=$((REDACTION_COUNT + 1))
    fi
}

# Walk all files in the bundle directory and apply redaction.
# Usage: redact_bundle <bundle_dir>
redact_bundle() {
    local bundle_dir="$1"

    if [[ "$REDACT" != "true" ]]; then
        log_warn "Redaction disabled (--no-redact). Bundle may contain secrets."
        return 0
    fi

    log_detail "Redacting sensitive data..."

    local file_count=0
    while IFS= read -r file; do
        redact_file "$file"
        file_count=$((file_count + 1))
    done < <(find "$bundle_dir" -type f \( \
        -name '*.json' -o -name '*.log' -o -name '*.txt' \
        -o -name '*.yaml' -o -name '*.yml' -o -name '*.sh' \
        -o -name '*.zshrc' -o -name '.zshrc' \
        -o -name 'os-release' -o -name 'VERSION' \
        \) 2>/dev/null)

    if [[ "$VERBOSE" == "true" ]]; then
        log_detail "Scanned $file_count files, redacted $REDACTION_COUNT"
    fi
}

# ============================================================
# Main bundle collection
# ============================================================
main() {
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)

    local bundle_dir="${OUTPUT_BASE}/${timestamp}"
    local archive_path="${OUTPUT_BASE}/${timestamp}.tar.gz"

    # Track collected files for manifest
    BUNDLE_FILES=()

    log_section "ACFS Support Bundle"
    log_step "Collecting diagnostic data..."

    # Create bundle directory
    mkdir -p "$bundle_dir" || {
        log_error "Cannot create bundle directory: $bundle_dir"
        exit 1
    }

    # --- Collect ACFS state files ---
    log_detail "Collecting ACFS state files..."
    collect_file "$ACFS_HOME/state.json" "$bundle_dir" "state.json" || true
    collect_file "$ACFS_HOME/VERSION" "$bundle_dir" "VERSION" || true
    collect_file "$ACFS_HOME/checksums.yaml" "$bundle_dir" "checksums.yaml" || true

    # --- Collect install logs ---
    log_detail "Collecting install logs..."
    local logs_dir="$ACFS_HOME/logs"
    if [[ -d "$logs_dir" ]]; then
        mkdir -p "$bundle_dir/logs"
        # Collect recent install logs (last 5)
        local log_count=0
        while IFS= read -r logfile; do
            cp "$logfile" "$bundle_dir/logs/" 2>/dev/null && {
                BUNDLE_FILES+=("logs/$(basename "$logfile")")
                log_count=$((log_count + 1))
            }
        done < <(find "$logs_dir" -name 'install-*.log' -o -name 'install_summary_*.json' 2>/dev/null | sort -r | head -10)
        [[ "$VERBOSE" == "true" ]] && log_detail "Collected $log_count log files"
    fi

    # --- Collect install summary JSONs ---
    if [[ -d "$logs_dir" ]]; then
        while IFS= read -r summary; do
            cp "$summary" "$bundle_dir/logs/" 2>/dev/null && {
                BUNDLE_FILES+=("logs/$(basename "$summary")")
            }
        done < <(find "$logs_dir" -name 'install_summary_*.json' 2>/dev/null | sort -r | head -5)
    fi

    # --- Capture doctor JSON ---
    log_detail "Running health checks..."
    capture_doctor_json "$bundle_dir" || true

    # --- Capture versions ---
    log_detail "Collecting tool versions..."
    capture_versions "$bundle_dir" || true

    # --- Capture environment ---
    log_detail "Collecting environment info..."
    capture_env_summary "$bundle_dir" || true

    # --- Collect system info ---
    log_detail "Collecting system info..."
    if [[ -f /etc/os-release ]]; then
        collect_file "/etc/os-release" "$bundle_dir" "os-release"
    fi

    # Systemd journal (last 100 acfs-related lines)
    if command -v journalctl &>/dev/null; then
        journalctl --no-pager -n 100 -u 'acfs*' > "$bundle_dir/journal-acfs.log" 2>/dev/null && {
            BUNDLE_FILES+=("journal-acfs.log")
        } || true
    fi

    # --- Collect configuration ---
    log_detail "Collecting configuration..."
    collect_file "$HOME/.zshrc" "$bundle_dir/config" ".zshrc" || true
    collect_file "$ACFS_HOME/acfs.manifest.yaml" "$bundle_dir/config" "acfs.manifest.yaml" || true

    # --- Redact sensitive data ---
    redact_bundle "$bundle_dir"

    # --- Write manifest ---
    log_detail "Writing manifest..."
    write_manifest "$bundle_dir"

    # --- Create tar archive ---
    log_detail "Creating archive..."
    if tar -czf "$archive_path" -C "$OUTPUT_BASE" "$timestamp" 2>/dev/null; then
        log_success "Bundle created: $archive_path"
    else
        log_warn "Could not create tar archive, bundle available at: $bundle_dir"
    fi

    # Print summary to stdout (clean for piping)
    echo "$archive_path"
}

main "$@"
