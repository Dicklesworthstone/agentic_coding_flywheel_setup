#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# AUTO-GENERATED FROM acfs.manifest.yaml - DO NOT EDIT
# Regenerate: bun run generate (from packages/manifest)
# ============================================================

set -euo pipefail

# Ensure logging functions available
ACFS_GENERATED_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# When running a generated installer directly (not sourced by install.sh),
# set sane defaults and derive ACFS paths from the script location so
# contract validation passes and local assets are discoverable.
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    # Match install.sh defaults
    if [[ -z "${TARGET_USER:-}" ]]; then
        if [[ $EUID -eq 0 ]] && [[ -z "${SUDO_USER:-}" ]]; then
            _ACFS_DETECTED_USER="ubuntu"
        else
            _ACFS_DETECTED_USER="${SUDO_USER:-$(whoami)}"
        fi
        TARGET_USER="$_ACFS_DETECTED_USER"
    fi
    unset _ACFS_DETECTED_USER
    MODE="${MODE:-vibe}"

    if [[ -z "${TARGET_HOME:-}" ]]; then
        if [[ "${TARGET_USER}" == "root" ]]; then
            TARGET_HOME="/root"
        elif [[ "$(whoami 2>/dev/null || true)" == "${TARGET_USER}" ]]; then
            TARGET_HOME="${HOME}"
        else
            TARGET_HOME="/home/${TARGET_USER}"
        fi
    fi

    # Derive "bootstrap" paths from the repo layout (scripts/generated/.. -> repo root).
    if [[ -z "${ACFS_BOOTSTRAP_DIR:-}" ]]; then
        ACFS_BOOTSTRAP_DIR="$(cd "$ACFS_GENERATED_SCRIPT_DIR/../.." && pwd)"
    fi

    ACFS_LIB_DIR="${ACFS_LIB_DIR:-$ACFS_BOOTSTRAP_DIR/scripts/lib}"
    ACFS_GENERATED_DIR="${ACFS_GENERATED_DIR:-$ACFS_BOOTSTRAP_DIR/scripts/generated}"
    ACFS_ASSETS_DIR="${ACFS_ASSETS_DIR:-$ACFS_BOOTSTRAP_DIR/acfs}"
    ACFS_CHECKSUMS_YAML="${ACFS_CHECKSUMS_YAML:-$ACFS_BOOTSTRAP_DIR/checksums.yaml}"
    ACFS_MANIFEST_YAML="${ACFS_MANIFEST_YAML:-$ACFS_BOOTSTRAP_DIR/acfs.manifest.yaml}"

    export TARGET_USER TARGET_HOME MODE
    export ACFS_BOOTSTRAP_DIR ACFS_LIB_DIR ACFS_GENERATED_DIR ACFS_ASSETS_DIR ACFS_CHECKSUMS_YAML ACFS_MANIFEST_YAML
fi
if [[ -f "$ACFS_GENERATED_SCRIPT_DIR/../lib/logging.sh" ]]; then
    source "$ACFS_GENERATED_SCRIPT_DIR/../lib/logging.sh"
else
    # Fallback logging functions if logging.sh not found
    # Progress/status output should go to stderr so stdout stays clean for piping.
    log_step() { echo "[*] $*" >&2; }
    log_section() { echo "" >&2; echo "=== $* ===" >&2; }
    log_success() { echo "[OK] $*" >&2; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_info() { echo "    $*" >&2; }
fi

# Source install helpers (run_as_*_shell, selection helpers)
if [[ -f "$ACFS_GENERATED_SCRIPT_DIR/../lib/install_helpers.sh" ]]; then
    source "$ACFS_GENERATED_SCRIPT_DIR/../lib/install_helpers.sh"
fi

# Source contract validation
if [[ -f "$ACFS_GENERATED_SCRIPT_DIR/../lib/contract.sh" ]]; then
    source "$ACFS_GENERATED_SCRIPT_DIR/../lib/contract.sh"
fi

# Optional security verification for upstream installer scripts.
# Scripts that need it should call: acfs_security_init
ACFS_SECURITY_READY=false
acfs_security_init() {
    if [[ "${ACFS_SECURITY_READY}" = "true" ]]; then
        return 0
    fi

    local security_lib="$ACFS_GENERATED_SCRIPT_DIR/../lib/security.sh"
    if [[ ! -f "$security_lib" ]]; then
        log_error "Security library not found: $security_lib"
        return 1
    fi

    # Use ACFS_CHECKSUMS_YAML if set by install.sh bootstrap (overrides security.sh default)
    if [[ -n "${ACFS_CHECKSUMS_YAML:-}" ]]; then
        export CHECKSUMS_FILE="${ACFS_CHECKSUMS_YAML}"
    fi

    # shellcheck source=../lib/security.sh
    # shellcheck disable=SC1091  # runtime relative source
    source "$security_lib"
    load_checksums || { log_error "Failed to load checksums.yaml"; return 1; }
    ACFS_SECURITY_READY=true
    return 0
}

# Category: cloud
# Modules: 3

# Cloudflare Wrangler CLI
install_cloud_wrangler() {
    local module_id="cloud.wrangler"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing cloud.wrangler"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: ~/.bun/bin/bun install -g --trust wrangler (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_CLOUD_WRANGLER'
~/.bun/bin/bun install -g --trust wrangler
INSTALL_CLOUD_WRANGLER
        then
            log_warn "cloud.wrangler: install command failed: ~/.bun/bin/bun install -g --trust wrangler"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "cloud.wrangler" "install command failed: ~/.bun/bin/bun install -g --trust wrangler"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "cloud.wrangler"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: wrangler --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_CLOUD_WRANGLER'
wrangler --version
INSTALL_CLOUD_WRANGLER
        then
            log_warn "cloud.wrangler: verify failed: wrangler --version"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "cloud.wrangler" "verify failed: wrangler --version"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "cloud.wrangler"
            fi
            return 0
        fi
    fi

    log_success "cloud.wrangler installed"
}

# Supabase CLI
install_cloud_supabase() {
    local module_id="cloud.supabase"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing cloud.supabase"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: case \"\$(uname -m)\" in (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_CLOUD_SUPABASE'
# Install Supabase CLI from GitHub release (verified via sha256 checksums)
arch=""
case "$(uname -m)" in
  x86_64) arch="amd64" ;;
  aarch64|arm64) arch="arm64" ;;
  *)
    echo "Supabase CLI: unsupported architecture ($(uname -m))" >&2
    exit 1
    ;;
esac

CURL_ARGS=(-fsSL)
if command -v curl >/dev/null 2>&1 && curl --help all 2>/dev/null | grep -q -- '--proto'; then
  CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
fi

release_url="$(curl "${CURL_ARGS[@]}" -o /dev/null -w '%{url_effective}\n' "https://github.com/supabase/cli/releases/latest" 2>/dev/null | tail -n1)" || true
tag="${release_url##*/}"
if [[ -z "$tag" ]] || [[ "$tag" != v* ]]; then
  echo "Supabase CLI: failed to resolve latest release tag" >&2
  exit 1
fi

version="${tag#v}"
base_url="https://github.com/supabase/cli/releases/download/${tag}"
tarball="supabase_linux_${arch}.tar.gz"
checksums="supabase_${version}_checksums.txt"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/acfs-supabase.XXXXXX" 2>/dev/null)" || tmp_dir=""
tmp_tgz="$(mktemp "${TMPDIR:-/tmp}/acfs-supabase.tgz.XXXXXX" 2>/dev/null)" || tmp_tgz=""
tmp_checksums="$(mktemp "${TMPDIR:-/tmp}/acfs-supabase.sha.XXXXXX" 2>/dev/null)" || tmp_checksums=""

if [[ -z "$tmp_dir" ]] || [[ -z "$tmp_tgz" ]] || [[ -z "$tmp_checksums" ]]; then
  echo "Supabase CLI: failed to create temp files" >&2
  exit 1
fi

curl "${CURL_ARGS[@]}" -o "$tmp_tgz" "${base_url}/${tarball}"
curl "${CURL_ARGS[@]}" -o "$tmp_checksums" "${base_url}/${checksums}"

expected_sha="$(awk -v tb="$tarball" '$2 == tb {print $1; exit}' "$tmp_checksums" 2>/dev/null)"
if [[ -z "$expected_sha" ]]; then
  echo "Supabase CLI: checksum entry not found for ${tarball}" >&2
  exit 1
fi

actual_sha=""
if command -v sha256sum >/dev/null 2>&1; then
  actual_sha="$(sha256sum "$tmp_tgz" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
  actual_sha="$(shasum -a 256 "$tmp_tgz" | awk '{print $1}')"
else
  echo "Supabase CLI: no SHA256 tool available (need sha256sum or shasum)" >&2
  exit 1
fi

if [[ -z "$actual_sha" ]] || [[ "$actual_sha" != "$expected_sha" ]]; then
  echo "Supabase CLI: checksum mismatch" >&2
  echo "  Expected: $expected_sha" >&2
  echo "  Actual:   ${actual_sha:-<missing>}" >&2
  exit 1
fi

if ! tar -xzf "$tmp_tgz" -C "$tmp_dir" --no-same-owner --no-same-permissions supabase 2>/dev/null; then
  tar -xzf "$tmp_tgz" -C "$tmp_dir" --no-same-owner --no-same-permissions 2>/dev/null || {
    echo "Supabase CLI: failed to extract tarball" >&2
    exit 1
  }
fi

extracted_bin="$tmp_dir/supabase"
if [[ ! -f "$extracted_bin" ]]; then
  extracted_bin="$(find "$tmp_dir" -maxdepth 2 -type f -name supabase -print -quit 2>/dev/null || true)"
fi
if [[ -z "$extracted_bin" ]] || [[ ! -f "$extracted_bin" ]]; then
  echo "Supabase CLI: binary not found after extract" >&2
  exit 1
fi

mkdir -p "$HOME/.local/bin"
install -m 0755 "$extracted_bin" "$HOME/.local/bin/supabase"

if command -v timeout >/dev/null 2>&1; then
  timeout 5 "$HOME/.local/bin/supabase" --version >/dev/null 2>&1 || {
    echo "Supabase CLI: installed but failed to run" >&2
    exit 1
  }
else
  "$HOME/.local/bin/supabase" --version >/dev/null 2>&1 || {
    echo "Supabase CLI: installed but failed to run" >&2
    exit 1
  }
fi

# Best-effort cleanup
rm -f "$tmp_tgz" "$tmp_checksums" "$extracted_bin" 2>/dev/null || true
rmdir "$tmp_dir" 2>/dev/null || true
INSTALL_CLOUD_SUPABASE
        then
            log_warn "cloud.supabase: install command failed: case \"\$(uname -m)\" in"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "cloud.supabase" "install command failed: case \"\$(uname -m)\" in"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "cloud.supabase"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: supabase --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_CLOUD_SUPABASE'
supabase --version
INSTALL_CLOUD_SUPABASE
        then
            log_warn "cloud.supabase: verify failed: supabase --version"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "cloud.supabase" "verify failed: supabase --version"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "cloud.supabase"
            fi
            return 0
        fi
    fi

    log_success "cloud.supabase installed"
}

# Vercel CLI
install_cloud_vercel() {
    local module_id="cloud.vercel"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing cloud.vercel"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: ~/.bun/bin/bun install -g --trust vercel (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_CLOUD_VERCEL'
~/.bun/bin/bun install -g --trust vercel
INSTALL_CLOUD_VERCEL
        then
            log_warn "cloud.vercel: install command failed: ~/.bun/bin/bun install -g --trust vercel"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "cloud.vercel" "install command failed: ~/.bun/bin/bun install -g --trust vercel"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "cloud.vercel"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: vercel --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_CLOUD_VERCEL'
vercel --version
INSTALL_CLOUD_VERCEL
        then
            log_warn "cloud.vercel: verify failed: vercel --version"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "cloud.vercel" "verify failed: vercel --version"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "cloud.vercel"
            fi
            return 0
        fi
    fi

    log_success "cloud.vercel installed"
}

# Install all cloud modules
install_cloud() {
    log_section "Installing cloud modules"
    install_cloud_wrangler
    install_cloud_supabase
    install_cloud_vercel
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    install_cloud
fi
