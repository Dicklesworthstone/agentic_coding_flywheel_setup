#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Installer - Install Helpers
# Shared helpers for module execution and selection.
# ============================================================

# NOTE: Do not enable strict mode here. This file is sourced by
# installers and generated scripts and must not leak set -euo pipefail.

INSTALL_HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure logging functions are available (best effort)
if [[ -z "${ACFS_BLUE:-}" ]]; then
    # shellcheck source=logging.sh
    source "$INSTALL_HELPERS_DIR/logging.sh" 2>/dev/null || true
fi

# ------------------------------------------------------------
# Selection state (populated by parse_args or manifest selection)
# ------------------------------------------------------------
if [[ "${ONLY_MODULES+x}" != "x" ]]; then
    ONLY_MODULES=()
fi
if [[ "${ONLY_PHASES+x}" != "x" ]]; then
    ONLY_PHASES=()
fi
if [[ "${SKIP_MODULES+x}" != "x" ]]; then
    SKIP_MODULES=()
fi
: "${NO_DEPS:=false}"
: "${PRINT_PLAN:=false}"

# ------------------------------------------------------------
# Feature flags: generated vs legacy installers (mjt.5.6)
# ------------------------------------------------------------
# These flags let maintainers roll out the manifest-driven, generated installers
# category-by-category while keeping a fast rollback path.
#
# Precedence:
#   1) ACFS_USE_GENERATED_<CATEGORY> (if set)
#   2) ACFS_USE_GENERATED            (if set)
#   3) Default for migrated categories (see ACFS_GENERATED_MIGRATED_CATEGORIES)
#
# Valid values: 0/1, true/false, yes/no, on/off (case-insensitive)
#
# Categories are the manifest "category" values (e.g., base, shell, cli, lang, tools, agents, db, cloud, stack, acfs).
#
# Note: The orchestrator (install.sh) remains responsible for state/resume framing.

# Default categories array. Set via ACFS_GENERATED_DEFAULT_CATEGORIES in code,
# or override at runtime with ACFS_GENERATED_MIGRATED_CATEGORIES env var (comma-separated).
ACFS_GENERATED_DEFAULT_CATEGORIES=() # Empty until categories are explicitly migrated.

_acfs_upper() {
    local s="${1:-}"
    # Bash 4+: ${var^^}
    echo "${s^^}"
}

_acfs_normalize_bool() {
    local raw="${1:-}"
    case "${raw,,}" in
        1|true|yes|on) echo "1" ;;
        0|false|no|off) echo "0" ;;
        *) return 1 ;;
    esac
}

acfs_flag_bool() {
    local var_name="$1"
    local raw="${!var_name:-}"

    if [[ -z "${raw:-}" ]]; then
        echo ""
        return 0
    fi

    local normalized=""
    if normalized="$(_acfs_normalize_bool "$raw")"; then
        echo "$normalized"
        return 0
    fi

    if declare -f log_warn >/dev/null 2>&1; then
        log_warn "Ignoring invalid ${var_name}=${raw} (expected 0/1 or true/false)"
    else
        echo "WARN: Ignoring invalid ${var_name}=${raw} (expected 0/1 or true/false)" >&2
    fi

    echo ""
    return 0
}

# ------------------------------------------------------------
# Effective selection (computed once after manifest_index)
# Uses -g for global scope when sourced inside a function
# ------------------------------------------------------------
declare -gA ACFS_EFFECTIVE_RUN=()
declare -gA ACFS_PLAN_REASON=()
declare -gA ACFS_PLAN_EXCLUDE_REASON=()
declare -ga ACFS_EFFECTIVE_PLAN=()

acfs_normalize_only_phases() {
    if [[ "${#ONLY_PHASES[@]}" -eq 0 ]]; then
        return 0
    fi

    local -a normalized=()
    local phase=""
    local lower=""

    for phase in "${ONLY_PHASES[@]}"; do
        [[ -n "$phase" ]] || continue
        lower="${phase,,}"

        if [[ "$lower" =~ ^[0-9]+$ ]]; then
            normalized+=("$lower")
            continue
        fi

        case "$lower" in
            base|base_deps|system) normalized+=("1") ;;
            user_setup|user|users) normalized+=("2") ;;
            filesystem|fs) normalized+=("3") ;;
            shell_setup|shell) normalized+=("4") ;;
            cli_tools|cli) normalized+=("5") ;;
            languages|language|lang) normalized+=("6") ;;
            agents|agent) normalized+=("7") ;;
            cloud_db|cloud-db) normalized+=("8") ;;
            stack) normalized+=("9") ;;
            finalize|final) normalized+=("10") ;;
            *) normalized+=("$phase") ;;
        esac
    done

    ONLY_PHASES=("${normalized[@]}")
    return 0
}

acfs_resolve_selection() {
    if [[ "${ACFS_MANIFEST_INDEX_LOADED:-false}" != "true" ]]; then
        log_error "Manifest index not loaded. Cannot resolve selection."
        return 1
    fi

    # Clear arrays while preserving their types
    # Re-declare with -gA to ensure they remain global associative arrays
    declare -gA ACFS_EFFECTIVE_RUN=()
    declare -gA ACFS_PLAN_REASON=()
    declare -gA ACFS_PLAN_EXCLUDE_REASON=()
    ACFS_EFFECTIVE_PLAN=()

    # Normalize named phases like "agents" to manifest phase numbers
    acfs_normalize_only_phases

    local -A module_exists=()
    local -A phase_exists=()
    local module=""
    local phase=""
    for module in "${ACFS_MODULES_IN_ORDER[@]}"; do
        module_exists["$module"]=1
        phase="${ACFS_MODULE_PHASE["$module"]:-}"
        if [[ -n "$phase" ]]; then
            phase_exists["$phase"]=1
        fi
    done

    local -A desired=()
    local -A start_reason=()

    if [[ "${#ONLY_MODULES[@]}" -gt 0 ]]; then
        for module in "${ONLY_MODULES[@]}"; do
            [[ -n "$module" ]] || continue
            if [[ -z "${module_exists[$module]:-}" ]]; then
                log_error "Unknown module id in --only: $module"
                return 1
            fi
            desired["$module"]=1
            start_reason["$module"]="explicitly requested"
        done
    elif [[ "${#ONLY_PHASES[@]}" -gt 0 ]]; then
        for phase in "${ONLY_PHASES[@]}"; do
            [[ -n "$phase" ]] || continue
            if [[ -z "${phase_exists[$phase]:-}" ]]; then
                log_error "Unknown phase in --only-phase: $phase"
                return 1
            fi
        done
        for module in "${ACFS_MODULES_IN_ORDER[@]}"; do
            phase="${ACFS_MODULE_PHASE["$module"]:-}"
            for target_phase in "${ONLY_PHASES[@]}"; do
                if [[ "$phase" == "$target_phase" ]]; then
                    desired["$module"]=1
                    start_reason["$module"]="phase $phase"
                    break
                fi
            done
        done
    else
        for module in "${ACFS_MODULES_IN_ORDER[@]}"; do
            local enabled="${ACFS_MODULE_DEFAULT["$module"]:-1}"
            if [[ "$enabled" == "1" || "$enabled" == "true" ]]; then
                desired["$module"]=1
                start_reason["$module"]="default"
            else
                ACFS_PLAN_EXCLUDE_REASON["$module"]="disabled by default"
            fi
        done
    fi

    local -A skip_set=()
    local -A skip_reason=()

    for module in "${SKIP_MODULES[@]}"; do
        [[ -n "$module" ]] || continue
        if [[ -z "${module_exists[$module]:-}" ]]; then
            log_error "Unknown module id in --skip: $module"
            return 1
        fi
        skip_set["$module"]=1
        skip_reason["$module"]="explicitly skipped"
    done

    if [[ "${SKIP_TAGS+x}" == "x" ]] && [[ "${#SKIP_TAGS[@]}" -gt 0 ]]; then
        local tag=""
        for tag in "${SKIP_TAGS[@]}"; do
            [[ -n "$tag" ]] || continue
            for module in "${ACFS_MODULES_IN_ORDER[@]}"; do
                local tags="${ACFS_MODULE_TAGS["$module"]:-}"
                [[ -n "$tags" ]] || continue
                IFS=',' read -ra _tags <<< "$tags"
                local _tag=""
                for _tag in "${_tags[@]}"; do
                    if [[ "$_tag" == "$tag" ]]; then
                        skip_set["$module"]=1
                        if [[ -z "${skip_reason[$module]:-}" ]]; then
                            skip_reason["$module"]="skipped tag $tag"
                        fi
                        break
                    fi
                done
            done
        done
    fi

    if [[ "${SKIP_CATEGORIES+x}" == "x" ]] && [[ "${#SKIP_CATEGORIES[@]}" -gt 0 ]]; then
        local category=""
        for category in "${SKIP_CATEGORIES[@]}"; do
            [[ -n "$category" ]] || continue
            for module in "${ACFS_MODULES_IN_ORDER[@]}"; do
                if [[ "${ACFS_MODULE_CATEGORY["$module"]:-}" == "$category" ]]; then
                    skip_set["$module"]=1
                    if [[ -z "${skip_reason[$module]:-}" ]]; then
                        skip_reason["$module"]="skipped category $category"
                    fi
                fi
            done
        done
    fi

    for module in "${!skip_set[@]}"; do
        if [[ -n "${desired[$module]:-}" ]]; then
            unset "desired[$module]"
            ACFS_PLAN_EXCLUDE_REASON["$module"]="${skip_reason[$module]}"
        elif [[ -z "${ACFS_PLAN_EXCLUDE_REASON[$module]:-}" ]]; then
            ACFS_PLAN_EXCLUDE_REASON["$module"]="${skip_reason[$module]}"
        fi
    done

    # When --no-deps is enabled, the user is explicitly asking to bypass dependency
    # closure. In that mode we allow "unsafe" selections (including skipping deps)
    # and rely on the warning printed below.
    if [[ "${NO_DEPS:-false}" != "true" ]]; then
        local found_dep=""
        local found_chain=""
        _acfs_find_skipped_dep() {
            local current="$1"
            local path="$2"
            local deps="${ACFS_MODULE_DEPS["$current"]:-}"
            [[ -n "$deps" ]] || return 1
            IFS=',' read -ra _deps <<< "$deps"
            local dep=""
            for dep in "${_deps[@]}"; do
                [[ -n "$dep" ]] || continue
                if [[ -n "${skip_set[$dep]:-}" ]]; then
                    found_dep="$dep"
                    found_chain="$path -> $dep"
                    return 0
                fi
                if [[ -n "${visited[$dep]:-}" ]]; then
                    continue
                fi
                visited["$dep"]=1
                if _acfs_find_skipped_dep "$dep" "$path -> $dep"; then
                    return 0
                fi
            done
            return 1
        }

        for module in "${!desired[@]}"; do
            local -A visited=()
            visited["$module"]=1
            found_dep=""
            found_chain=""
            if _acfs_find_skipped_dep "$module" "$module"; then
                log_error "Selection error: $module depends on skipped $found_dep"
                log_error "Dependency chain: $found_chain"
                log_error "Remove --skip $found_dep or omit $module."
                return 1
            fi
        done
    fi

    if [[ "${NO_DEPS:-false}" == "true" ]]; then
        log_warn "WARNING: --no-deps disables dependency closure; install may be incomplete."
    else
        local -a queue=()
        local idx=0
        for module in "${!desired[@]}"; do
            queue+=("$module")
        done
        while [[ $idx -lt ${#queue[@]} ]]; do
            local current="${queue[$idx]}"
            idx=$((idx + 1))
            local deps="${ACFS_MODULE_DEPS["$current"]:-}"
            [[ -n "$deps" ]] || continue
            IFS=',' read -ra _deps <<< "$deps"
            local dep=""
            for dep in "${_deps[@]}"; do
                [[ -n "$dep" ]] || continue
                if [[ -n "${skip_set[$dep]:-}" ]]; then
                    log_error "Selection error: $current depends on skipped $dep"
                    log_error "Remove --skip $dep or add --no-deps if debugging."
                    return 1
                fi
                if [[ -z "${module_exists[$dep]:-}" ]]; then
                    log_error "Manifest error: $current depends on unknown module $dep"
                    return 1
                fi
                if [[ -z "${desired[$dep]:-}" ]]; then
                    desired["$dep"]=1
                    if [[ -z "${start_reason[$dep]:-}" ]]; then
                        start_reason["$dep"]="dependency of $current"
                    fi
                    queue+=("$dep")
                fi
            done
        done
    fi

    for module in "${ACFS_MODULES_IN_ORDER[@]}"; do
        if [[ -n "${desired[$module]:-}" ]]; then
            unset "ACFS_PLAN_EXCLUDE_REASON[$module]"
            ACFS_EFFECTIVE_RUN["$module"]=1
            ACFS_EFFECTIVE_PLAN+=("$module")
            if [[ -n "${start_reason[$module]:-}" ]]; then
                # shellcheck disable=SC2034  # consumed by print_execution_plan
                ACFS_PLAN_REASON["$module"]="${start_reason[$module]}"
            else
                # shellcheck disable=SC2034  # consumed by print_execution_plan
                ACFS_PLAN_REASON["$module"]="included"
            fi
        else
            if [[ -n "${ACFS_PLAN_EXCLUDE_REASON[$module]:-}" ]]; then
                continue
            fi
            if [[ "${#ONLY_MODULES[@]}" -gt 0 ]]; then
                ACFS_PLAN_EXCLUDE_REASON["$module"]="not selected"
            elif [[ "${#ONLY_PHASES[@]}" -gt 0 ]]; then
                ACFS_PLAN_EXCLUDE_REASON["$module"]="filtered by phase"
            else
                ACFS_PLAN_EXCLUDE_REASON["$module"]="not selected"
            fi
        fi
    done
}

should_run_module() {
    local module_id="$1"
    [[ -n "${ACFS_EFFECTIVE_RUN[$module_id]:-}" ]]
}

# ------------------------------------------------------------
# Feature flags for incremental category rollout (mjt.5.6)
#
# Goal: allow safe, reversible migration from legacy install.sh implementations
# to manifest-driven generated installers, category-by-category.
#
# Global switch:
#   ACFS_USE_GENERATED=0|1
#     - 0: force legacy for all categories (except per-category overrides)
#     - 1: enable generated for categories that are migrated by default
#
# Per-category overrides (override global):
#   ACFS_USE_GENERATED_<CATEGORY>=0|1
#
# Default behavior when per-category overrides are unset:
#   - generated for migrated categories
#   - legacy for unmigrated categories
#
# Configure migrated categories via:
#   - ACFS_GENERATED_MIGRATED_CATEGORIES="base,lang,agents"   (comma-separated), OR
#   - ACFS_GENERATED_DEFAULT_CATEGORIES (array in this file)
# ------------------------------------------------------------

: "${ACFS_USE_GENERATED:=1}" # Default to "enabled", but only affects migrated categories.

_acfs_category_is_migrated() {
    local category="${1:-}"
    [[ -n "$category" ]] || return 1

    local migrated_categories=()
    if [[ -n "${ACFS_GENERATED_MIGRATED_CATEGORIES:-}" ]]; then
        # Runtime override via env var (comma-separated)
        IFS=',' read -ra migrated_categories <<< "${ACFS_GENERATED_MIGRATED_CATEGORIES}"
    else
        # Code-defined defaults
        migrated_categories=("${ACFS_GENERATED_DEFAULT_CATEGORIES[@]}")
    fi

    local c=""
    for c in "${migrated_categories[@]}"; do
        # Trim leading/trailing whitespace
        c="${c#"${c%%[![:space:]]*}"}"
        c="${c%"${c##*[![:space:]]}"}"
        [[ -n "$c" ]] || continue
        if [[ "${c,,}" == "${category,,}" ]]; then
            return 0
        fi
    done

    return 1
}

# Returns 0 (true) if generated should be used, 1 (false) for legacy.
acfs_use_generated_for_category() {
    local category="${1:-}"
    [[ -n "$category" ]] || return 1

    # Users is orchestration-only today: the install.sh orchestrator owns user creation,
    # SSH key migration, and sudo policy. The manifest module `users.ubuntu` is marked
    # `generated: false` with an empty install list, so enabling generated users would
    # effectively skip user creation and fail verification.
    #
    # Guardrail: force legacy for users even if someone sets ACFS_USE_GENERATED_USERS=1.
    if [[ "${category,,}" == "users" ]]; then
        local users_flag
        users_flag="$(acfs_flag_bool "ACFS_USE_GENERATED_USERS")"
        if [[ "$users_flag" == "1" ]]; then
            if declare -f log_warn >/dev/null 2>&1; then
                log_warn "ACFS_USE_GENERATED_USERS=1 is not supported yet (users is orchestration-only); using legacy user normalization"
            else
                echo "WARN: ACFS_USE_GENERATED_USERS=1 is not supported yet (users is orchestration-only); using legacy user normalization" >&2
            fi
        fi
        return 1
    fi

    # 1) Per-category override
    local category_upper
    category_upper="$(_acfs_upper "$category")"
    local category_var="ACFS_USE_GENERATED_${category_upper}"
    local category_value
    category_value="$(acfs_flag_bool "$category_var")"
    if [[ "$category_value" == "1" ]]; then
        return 0
    elif [[ "$category_value" == "0" ]]; then
        return 1
    fi

    # 2) Global kill switch (0 forces legacy)
    local global_value
    global_value="$(acfs_flag_bool "ACFS_USE_GENERATED")"
    if [[ -z "$global_value" ]]; then
        global_value="1"
    fi
    if [[ "$global_value" == "0" ]]; then
        return 1
    fi

    # 3) Default: generated only for migrated categories
    _acfs_category_is_migrated "$category"
}

# Determines category from module ID (e.g., "lang.bun" -> "lang").
acfs_use_generated_for_module() {
    local module_id="${1:-}"
    [[ -n "$module_id" ]] || return 1

    local category="${module_id%%.*}"
    acfs_use_generated_for_category "$category"
}

# Returns generated function name (from manifest_index) if enabled, else empty string.
acfs_get_module_installer() {
    local module_id="${1:-}"
    [[ -n "$module_id" ]] || { echo ""; return 0; }

    if acfs_use_generated_for_module "$module_id"; then
        echo "${ACFS_MODULE_FUNC[$module_id]:-}"
        return 0
    fi

    echo ""
    return 0
}

# Log current feature flag state (for debugging).
acfs_log_feature_flags() {
    local categories=("base" "users" "shell" "cli" "lang" "tools" "agents" "db" "cloud" "stack" "acfs")

    if declare -f log_detail >/dev/null 2>&1; then
        log_detail "Feature flags:"
        log_detail "  ACFS_USE_GENERATED=${ACFS_USE_GENERATED:-1}"
        log_detail "  ACFS_GENERATED_MIGRATED_CATEGORIES=${ACFS_GENERATED_MIGRATED_CATEGORIES:-<default>}"
    else
        echo "Feature flags:" >&2
        echo "  ACFS_USE_GENERATED=${ACFS_USE_GENERATED:-1}" >&2
        echo "  ACFS_GENERATED_MIGRATED_CATEGORIES=${ACFS_GENERATED_MIGRATED_CATEGORIES:-<default>}" >&2
    fi

    local cat=""
    for cat in "${categories[@]}"; do
        local upper_cat
        upper_cat="$(_acfs_upper "$cat")"
        local flag_name="ACFS_USE_GENERATED_${upper_cat}"
        local flag_value="${!flag_name:-}"
        if [[ -n "$flag_value" ]]; then
            if declare -f log_detail >/dev/null 2>&1; then
                log_detail "  ${flag_name}=${flag_value}"
            else
                echo "  ${flag_name}=${flag_value}" >&2
            fi
        fi
    done
}

# ------------------------------------------------------------
# Legacy flag mapping (mjt.5.5)
# Maps old-style --skip-* flags to SKIP_MODULES array
# ------------------------------------------------------------
acfs_apply_legacy_skips() {
    # Map legacy flags to module skips
    # These globals are set by parse_args in install.sh

    if [[ "${SKIP_POSTGRES:-false}" == "true" ]]; then
        SKIP_MODULES+=("db.postgres18")
    fi

    if [[ "${SKIP_VAULT:-false}" == "true" ]]; then
        SKIP_MODULES+=("tools.vault")
    fi

    if [[ "${SKIP_CLOUD:-false}" == "true" ]]; then
        SKIP_MODULES+=("cloud.wrangler" "cloud.supabase" "cloud.vercel")
    fi
}

# ------------------------------------------------------------
# Command execution helpers (heredoc-friendly)
# ------------------------------------------------------------

# Common paths for user-installed tools (added to PATH for verification)
# This ensures tools installed in user directories are findable
_acfs_user_paths() {
    echo "\$HOME/.local/bin:\$HOME/.cargo/bin:\$HOME/.bun/bin:\$HOME/.atuin/bin:\$HOME/go/bin"
}

_run_shell_with_strict_mode() {
    local cmd="$1"
    local path_prefix
    path_prefix="$(_acfs_user_paths)"

    # UV_NO_CONFIG prevents uv from looking for config in /root when running via sudo
    local env_setup="export PATH=\"$path_prefix:\$PATH\" UV_NO_CONFIG=1"

    if [[ -n "$cmd" ]]; then
        # IMPORTANT: Avoid `bash -l` (login shell). Third-party installers can
        # leave broken profile files that would break non-interactive runs.
        bash -c "$env_setup; set -euo pipefail; $cmd"
        return $?
    fi

    # stdin mode (supports heredocs/pipes)
    bash -c "$env_setup; set -euo pipefail; (printf '%s\n' 'set -euo pipefail'; cat) | bash -s"
}

# Provide a default run_as_target implementation for generated scripts (and other callers)
# when the orchestrator (install.sh) isn't in scope.
#
# IMPORTANT:
# - Avoid `sudo -i` / login shells (they source profile files, which are not a stable API).
# - Preserve stdin for heredocs/pipes.
if ! declare -f run_as_target >/dev/null 2>&1; then
    run_as_target() {
        local user="${TARGET_USER:-ubuntu}"
        local user_home="${TARGET_HOME:-/home/$user}"

        # UV_NO_CONFIG prevents uv from looking for config in /root when running via sudo/runuser.
        # HOME is set explicitly for consistent tool installs and path resolution.
        local -a env_args=("UV_NO_CONFIG=1" "HOME=$user_home")

        # Pass ACFS context variables to the target user environment when available.
        [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]] && env_args+=("ACFS_BOOTSTRAP_DIR=$ACFS_BOOTSTRAP_DIR")
        [[ -n "${SCRIPT_DIR:-}" ]] && env_args+=("SCRIPT_DIR=$SCRIPT_DIR")
        [[ -n "${ACFS_RAW:-}" ]] && env_args+=("ACFS_RAW=$ACFS_RAW")
        [[ -n "${ACFS_VERSION:-}" ]] && env_args+=("ACFS_VERSION=$ACFS_VERSION")

        # Already the target user
        if [[ "$(whoami)" == "$user" ]]; then
            cd "$user_home" 2>/dev/null || true
            env "${env_args[@]}" "$@"
            return $?
        fi

        # Prefer sudo (non-login) when available.
        if command_exists sudo; then
            # shellcheck disable=SC2016  # $HOME/$@ expand inside sh -c
            sudo -u "$user" env "${env_args[@]}" sh -c 'cd "$HOME" 2>/dev/null; exec "$@"' _ "$@"
            return $?
        fi

        # Root-only fallbacks.
        if command_exists runuser; then
            # shellcheck disable=SC2016  # $HOME/$@ expand inside sh -c
            runuser -u "$user" -- env "${env_args[@]}" sh -c 'cd "$HOME" 2>/dev/null; exec "$@"' _ "$@"
            return $?
        fi

        # su without login (-) to avoid sourcing profile files.
        local env_assignments=""
        local kv=""
        for kv in "${env_args[@]}"; do
            env_assignments+=" $(printf '%q' "$kv")"
        done
        env_assignments="${env_assignments# }"
        local user_home_q
        user_home_q="$(printf '%q' "$user_home")"
        su "$user" -c "cd $user_home_q 2>/dev/null; env $env_assignments $(printf '%q ' "$@")"
    }
fi

# Run a shell string (or stdin) as TARGET_USER
run_as_target_shell() {
    local cmd="${1:-}"
    local path_prefix
    path_prefix="$(_acfs_user_paths)"

    if ! declare -f run_as_target >/dev/null 2>&1; then
        log_error "run_as_target_shell requires run_as_target"
        return 1
    fi

    # UV_NO_CONFIG prevents uv from looking for config in /root when running via sudo
    local env_setup="export PATH=\"$path_prefix:\$PATH\" UV_NO_CONFIG=1"

    if [[ -n "$cmd" ]]; then
        # IMPORTANT: Avoid `bash -l` (login shell). Profile files are not a stable API.
        run_as_target bash -c "$env_setup; set -euo pipefail; $cmd"
        return $?
    fi

    # stdin mode
    run_as_target bash -c "$env_setup; set -euo pipefail; (printf '%s\n' 'set -euo pipefail'; cat) | bash -s"
}

# Run a runner (bash, sh) with args as TARGET_USER, passing stdin
# Usage: echo script | run_as_target_runner "bash" "-s" "--" "arg1"
run_as_target_runner() {
    local runner="$1"
    shift
    
    if ! declare -f run_as_target >/dev/null 2>&1; then
        log_error "run_as_target_runner requires run_as_target"
        return 1
    fi

    # Pass args directly to run_as_target, which handles quoting
    # Note: run_as_target falls back to `su user -c` (non-login) to avoid profile-sourced failures.
    # stdin is passed through su to the runner
    run_as_target "$runner" "$@"
}

# Run a shell string (or stdin) as root
run_as_root_shell() {
    local cmd="${1:-}"

    if [[ "$EUID" -eq 0 ]]; then
        _run_shell_with_strict_mode "$cmd"
        return $?
    fi

    if [[ -n "${SUDO:-}" ]]; then
        if [[ -n "$cmd" ]]; then
            $SUDO bash -c "set -euo pipefail; $cmd"
            return $?
        fi
        $SUDO bash -c 'set -euo pipefail; (printf "%s\n" "set -euo pipefail"; cat) | bash -s'
        return $?
    fi

    if command -v sudo >/dev/null 2>&1; then
        if [[ -n "$cmd" ]]; then
            sudo bash -c "set -euo pipefail; $cmd"
            return $?
        fi
        sudo bash -c 'set -euo pipefail; (printf "%s\n" "set -euo pipefail"; cat) | bash -s'
        return $?
    fi

    log_error "run_as_root_shell requires root or sudo"
    return 1
}

# Run a shell string (or stdin) as current user
run_as_current_shell() {
    local cmd="${1:-}"
    _run_shell_with_strict_mode "$cmd"
}

# ------------------------------------------------------------
# Command existence helpers
# ------------------------------------------------------------

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

command_exists_as_target() {
    local cmd="$1"
    if ! declare -f run_as_target >/dev/null 2>&1; then
        return 1
    fi

    # NOTE: We intentionally avoid embedding $cmd into the shell string.
    # Passing as $1 avoids quoting bugs when cmd contains special chars.
    #
    # Also, extend PATH with common user install locations so we can detect
    # tools installed under $HOME (bun, cargo, etc.) when running via sudo/runuser.
    # shellcheck disable=SC2016  # $HOME/$PATH expand inside the target user's bash -c
    run_as_target bash -c \
        'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$HOME/go/bin:$PATH"; command -v -- "$1" >/dev/null 2>&1' \
        _ "$cmd"
}

# ------------------------------------------------------------
# Alias for backwards compatibility with install.sh
# The canonical implementation is acfs_use_generated_for_category() above.
# ------------------------------------------------------------
acfs_use_generated_category() {
    acfs_use_generated_for_category "$@"
}

acfs_run_generated_category_phase() {
    local category="$1"
    local phase="$2"

    if [[ "${ACFS_MANIFEST_INDEX_LOADED:-false}" != "true" ]]; then
        log_error "Manifest index not loaded; cannot run generated category: $category"
        return 1
    fi
    if [[ "${ACFS_GENERATED_SOURCED:-false}" != "true" ]]; then
        log_error "Generated installers not sourced; cannot run generated category: $category"
        return 1
    fi

    local module=""
    local key=""
    local func=""
    local ran_any=false

    for module in "${ACFS_EFFECTIVE_PLAN[@]}"; do
        key="$module"
        if [[ "${ACFS_MODULE_CATEGORY[$key]:-}" != "$category" ]]; then
            continue
        fi
        if [[ "${ACFS_MODULE_PHASE[$key]:-}" != "$phase" ]]; then
            continue
        fi
        func="${ACFS_MODULE_FUNC[$key]:-}"
        if [[ -z "$func" ]]; then
            log_error "Missing generated function for $module"
            return 1
        fi
        if ! declare -f "$func" >/dev/null 2>&1; then
            log_error "Generated function not found: $func (module $module)"
            return 1
        fi
        if ! "$func"; then
            log_error "Generated module failed: $module"
            return 1
        fi
        ran_any=true
    done

    if [[ "$ran_any" != "true" ]]; then
        log_detail "No generated modules selected for $category (phase $phase)"
    fi

    return 0
}
