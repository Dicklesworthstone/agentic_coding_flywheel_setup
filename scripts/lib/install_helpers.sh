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

# Source progress bar library (bd-21kh)
if [[ -z "${ACFS_PROGRESS_TOTAL:-}" ]]; then
    # shellcheck source=progress.sh
    source "$INSTALL_HELPERS_DIR/progress.sh" 2>/dev/null || true
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

    if [[ "${#ONLY_MODULES[@]}" -gt 0 ]]; then
        for module in "${ONLY_MODULES[@]}"; do
            [[ -n "$module" ]] || continue
            if [[ -n "${skip_set[$module]:-}" ]]; then
                log_error "Selection error: $module was requested with --only and excluded by ${skip_reason[$module]}"
                log_error "Remove the skip selector or omit --only $module."
                return 1
            fi
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

    # 3) Default: generated for migrated categories...
    if _acfs_category_is_migrated "$category"; then
        return 0
    fi

    # 3b) Selection-filtered runs must use generated dispatch for every category.
    # The top-level installer still enters every phase; legacy phase bodies are
    # coarse category installers and do not know ACFS_EFFECTIVE_PLAN. Generated
    # category dispatch is module-aware and no-ops when a category/phase has no
    # selected modules, so it is the only safe path for --only/--only-phase/--skip.
    if acfs_selection_filters_active; then
        return 0
    fi

    return 1
}

acfs_selection_filters_active() {
    [[ "${ONLY_MODULES+x}" == "x" && ${#ONLY_MODULES[@]} -gt 0 ]] && return 0
    [[ "${ONLY_PHASES+x}" == "x" && ${#ONLY_PHASES[@]} -gt 0 ]] && return 0
    [[ "${SKIP_MODULES+x}" == "x" && ${#SKIP_MODULES[@]} -gt 0 ]] && return 0
    [[ "${SKIP_TAGS+x}" == "x" && ${#SKIP_TAGS[@]} -gt 0 ]] && return 0
    [[ "${SKIP_CATEGORIES+x}" == "x" && ${#SKIP_CATEGORIES[@]} -gt 0 ]] && return 0
    return 1
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

# Shell source for adding common user-installed tool paths at execution time.
# HOME and ACFS_BIN_DIR are expanded by the target shell from env data, so
# poisoned values stay inert while home-relative paths resolve correctly.
_acfs_user_path_export_source() {
    printf '%s\n' '_acfs_primary_bin="${ACFS_BIN_DIR:-$HOME/.local/bin}"; export PATH="${_acfs_primary_bin}:$HOME/.local/bin:$HOME/.acfs/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$HOME/go/bin:$PATH"'
}

_run_shell_with_strict_mode() {
    local cmd="$1"
    local path_export_source
    local env_bin=""
    local bash_bin=""
    path_export_source="$(_acfs_user_path_export_source)"

    env_bin="$(_acfs_system_binary_path env 2>/dev/null || true)"
    [[ -n "$env_bin" ]] || {
        log_error "Unable to locate env for strict shell execution"
        return 1
    }
    bash_bin="$(_acfs_system_binary_path bash 2>/dev/null || true)"
    [[ -n "$bash_bin" ]] || {
        log_error "Unable to locate bash for strict shell execution"
        return 1
    }

    # Keep path values in env data. The fixed shell wrapper expands HOME and
    # ACFS_BIN_DIR at runtime without re-parsing their contents.
    local -a shell_env=("ACFS_BASH_BIN=$bash_bin" "UV_NO_CONFIG=1")

    if [[ -n "$cmd" ]]; then
        # IMPORTANT: Avoid `bash -l` (login shell). Third-party installers can
        # leave broken profile files that would break non-interactive runs.
        "$env_bin" "${shell_env[@]}" "$bash_bin" -c "$path_export_source; set -euo pipefail; eval \"\$1\"" _ "$cmd"
        return $?
    fi

    # stdin mode (supports heredocs/pipes)
    "$env_bin" "${shell_env[@]}" "$bash_bin" -c "$path_export_source; set -euo pipefail; (printf \"%s\\n\" \"set -euo pipefail\"; cat) | \"\$ACFS_BASH_BIN\" -s"
}

# Resolve a target user's home via NSS/getent with safe fallbacks.
if ! declare -f _acfs_valid_target_username >/dev/null 2>&1; then
    _acfs_valid_target_username() {
        local user="${1:-}"
        [[ -n "$user" ]] || return 1
        [[ "$user" =~ ^[a-z_][a-z0-9._-]*$ ]]
    }
fi

if ! declare -f _acfs_validate_target_user >/dev/null 2>&1; then
    _acfs_validate_target_user() {
        local user="${1:-${TARGET_USER:-}}"
        local label="${2:-TARGET_USER}"
        local display="${user:-<empty>}"

        if _acfs_valid_target_username "$user"; then
            return 0
        fi

        if declare -f log_error >/dev/null 2>&1; then
            log_error "Invalid ${label} '$display' (expected: lowercase user name like 'ubuntu')"
        else
            printf "ERROR: Invalid %s '%s' (expected: lowercase user name like 'ubuntu')\n" "$label" "$display" >&2
        fi
        return 1
    }
fi

if ! declare -f _acfs_system_binary_path >/dev/null 2>&1; then
    _acfs_system_binary_path() {
        local name="${1:-}"
        local candidate=""

        [[ -n "$name" ]] || return 1
        case "$name" in
            .|..)
                return 1
                ;;
            *[!A-Za-z0-9._+-]*)
                return 1
                ;;
        esac

        for candidate in \
            "/usr/bin/$name" \
            "/bin/$name" \
            "/usr/local/bin/$name" \
            "/usr/local/sbin/$name" \
            "/usr/sbin/$name" \
            "/sbin/$name"
        do
            [[ -x "$candidate" ]] || continue
            printf '%s\n' "$candidate"
            return 0
        done

        return 1
    }
fi

if ! declare -f _acfs_resolve_current_user >/dev/null 2>&1; then
    _acfs_resolve_current_user() {
        local current_user=""
        local id_bin=""
        local whoami_bin=""

        id_bin="$(_acfs_system_binary_path id 2>/dev/null || true)"
        if [[ -n "$id_bin" ]]; then
            current_user="$("$id_bin" -un 2>/dev/null || true)"
        fi

        if [[ -z "$current_user" ]]; then
            whoami_bin="$(_acfs_system_binary_path whoami 2>/dev/null || true)"
            if [[ -n "$whoami_bin" ]]; then
                current_user="$("$whoami_bin" 2>/dev/null || true)"
            fi
        fi

        [[ -n "$current_user" ]] || return 1
        printf '%s\n' "$current_user"
    }
fi

if ! declare -f _acfs_getent_passwd_entry >/dev/null 2>&1; then
    _acfs_getent_passwd_entry() {
        local user="${1:-}"
        local getent_bin=""
        local passwd_entry=""
        local passwd_line=""

        [[ -n "$user" ]] || return 1
        getent_bin="$(_acfs_system_binary_path getent 2>/dev/null || true)"
        if [[ -n "$getent_bin" ]]; then
            passwd_entry="$("$getent_bin" passwd "$user" 2>/dev/null || true)"
        fi

        if [[ -z "$passwd_entry" ]] && [[ -r /etc/passwd ]]; then
            while IFS= read -r passwd_line; do
                [[ "${passwd_line%%:*}" == "$user" ]] || continue
                passwd_entry="$passwd_line"
                break
            done < /etc/passwd
        fi

        [[ -n "$passwd_entry" ]] || return 1
        printf '%s\n' "$passwd_entry"
    }
fi

if ! declare -f _acfs_passwd_home_from_entry >/dev/null 2>&1; then
    _acfs_passwd_home_from_entry() {
        local passwd_entry="${1:-}"
        local _passwd_user=""
        local _passwd_pw=""
        local _passwd_uid=""
        local _passwd_gid=""
        local _passwd_gecos=""
        local passwd_home=""
        local _passwd_shell=""

        [[ -n "$passwd_entry" ]] || return 1
        IFS=':' read -r _passwd_user _passwd_pw _passwd_uid _passwd_gid _passwd_gecos passwd_home _passwd_shell <<< "$passwd_entry"
        [[ -n "$passwd_home" ]] || return 1
        [[ "$passwd_home" == /* ]] || return 1
        [[ "$passwd_home" != / ]] || return 1
        printf '%s\n' "${passwd_home%/}"
    }
fi

if ! declare -f _acfs_resolve_target_home >/dev/null 2>&1; then
    _acfs_resolve_target_home() {
        local user="${1:-ubuntu}"
        local expected_home="${2:-}"
        local passwd_entry=""
        local current_user=""
        local current_home=""

        if [[ -n "$expected_home" ]] && [[ "$expected_home" == /* ]] && [[ "$expected_home" != / ]]; then
            expected_home="${expected_home%/}"
        else
            expected_home=""
        fi

        if [[ "$user" == "root" ]]; then
            printf '/root\n'
            return 0
        fi

        passwd_entry="$(_acfs_getent_passwd_entry "$user" 2>/dev/null || true)"
        if [[ -n "$passwd_entry" ]]; then
            passwd_entry="$(_acfs_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
            if [[ -n "$passwd_entry" ]]; then
                printf '%s\n' "$passwd_entry"
                return 0
            fi
        fi

        current_user="$(_acfs_resolve_current_user 2>/dev/null || true)"
        if [[ "$current_user" == "$user" ]] && [[ -n "${HOME:-}" ]] && [[ "${HOME}" == /* ]] && [[ "${HOME}" != / ]]; then
            current_home="${HOME%/}"
            if [[ -z "$expected_home" ]] || [[ "$current_home" == "$expected_home" ]]; then
                printf '%s\n' "$current_home"
                return 0
            fi
        fi

        return 1
    }
fi

if ! declare -f run_as_target >/dev/null 2>&1; then
    run_as_target() {
        local user="${TARGET_USER:-ubuntu}"
        local explicit_user_home="${TARGET_HOME:-}"
        local explicit_user_home_for_repair=""
        local invalid_explicit_user_home=""
        local user_home=""
        local passwd_entry=""
        local primary_bin_dir=""
        local acfs_home_for_target=""
        local env_bin=""
        local bash_bin=""
        local sh_bin=""
        local sudo_bin=""
        local runuser_bin=""
        local su_bin=""
        local -a command_argv=()

        _acfs_validate_target_user "$user" "TARGET_USER" || return 1
        env_bin="$(_acfs_system_binary_path env 2>/dev/null || true)"
        [[ -n "$env_bin" ]] || {
            log_error "Unable to locate env for target-user command"
            return 1
        }
        bash_bin="$(_acfs_system_binary_path bash 2>/dev/null || true)"
        [[ -n "$bash_bin" ]] || {
            log_error "Unable to locate bash for target-user command"
            return 1
        }
        sh_bin="$(_acfs_system_binary_path sh 2>/dev/null || true)"
        [[ -n "$sh_bin" ]] || {
            log_error "Unable to locate sh for target-user command"
            return 1
        }

        if [[ "$user" == "root" ]]; then
            user_home="/root"
        else
            passwd_entry="$(_acfs_getent_passwd_entry "$user" 2>/dev/null || true)"
            if [[ -n "$passwd_entry" ]]; then
                user_home="$(_acfs_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
            fi
        fi

        if [[ "$explicit_user_home" == /* ]] && [[ "$explicit_user_home" != "/" ]]; then
            explicit_user_home_for_repair="${explicit_user_home%/}"
            [[ "$explicit_user_home_for_repair" != "/" ]] || explicit_user_home_for_repair=""
        elif [[ -n "$explicit_user_home" ]]; then
            invalid_explicit_user_home="$explicit_user_home"
        fi

        if [[ -z "$user_home" ]]; then
            user_home="$(_acfs_resolve_target_home "$user" "$explicit_user_home_for_repair" || true)"
        fi

        if [[ -z "$user_home" ]] || [[ "$user_home" == "/" ]] || [[ "$user_home" != /* ]]; then
            local displayed_user_home="${user_home:-}"
            [[ -n "$displayed_user_home" ]] || displayed_user_home="$invalid_explicit_user_home"
            log_error "Invalid TARGET_HOME for '$user': ${displayed_user_home:-<empty>} (must be an absolute path and cannot be '/')"
            return 1
        fi

        primary_bin_dir="${ACFS_BIN_DIR:-$user_home/.local/bin}"
        if [[ -n "$explicit_user_home_for_repair" ]] && [[ "$explicit_user_home_for_repair" != "$user_home" ]]; then
            case "$primary_bin_dir" in
                "$explicit_user_home_for_repair"|"$explicit_user_home_for_repair"/*)
                    primary_bin_dir="$user_home/.local/bin"
                    ;;
            esac
        fi
        acfs_home_for_target="${ACFS_HOME:-}"
        if [[ -n "$explicit_user_home_for_repair" ]] && [[ "$explicit_user_home_for_repair" != "$user_home" ]]; then
            case "$acfs_home_for_target" in
                "$explicit_user_home_for_repair"|"$explicit_user_home_for_repair"/*)
                    acfs_home_for_target="$user_home/.acfs"
                    ;;
            esac
        fi

        local target_path_prefix="$primary_bin_dir:$user_home/.local/bin:$user_home/.acfs/bin:$user_home/.cargo/bin:$user_home/.bun/bin:$user_home/.atuin/bin:$user_home/go/bin"
        local current_path="${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"

        # UV_NO_CONFIG prevents uv from looking for config in /root when running via sudo/runuser.
        # HOME is set explicitly for consistent tool installs and path resolution.
        # PATH must include user-local ACFS bins because we deliberately avoid
        # login shells and therefore cannot depend on profile files.
        local -a env_args=("UV_NO_CONFIG=1" "HOME=$user_home" "PATH=$target_path_prefix:$current_path")

        # Pass core ACFS variables to the target user environment
        env_args+=("TARGET_USER=$user" "TARGET_HOME=$user_home")
        [[ -n "$acfs_home_for_target" ]] && env_args+=("ACFS_HOME=$acfs_home_for_target")
        [[ -n "${ACFS_BIN_DIR:-}" ]] && env_args+=("ACFS_BIN_DIR=$primary_bin_dir")

        # Pass ACFS context variables to the target user environment when available.
        [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]] && env_args+=("ACFS_BOOTSTRAP_DIR=$ACFS_BOOTSTRAP_DIR")
        [[ -n "${ACFS_LIB_DIR:-}" ]] && env_args+=("ACFS_LIB_DIR=$ACFS_LIB_DIR")
        [[ -n "${ACFS_GENERATED_DIR:-}" ]] && env_args+=("ACFS_GENERATED_DIR=$ACFS_GENERATED_DIR")
        [[ -n "${ACFS_ASSETS_DIR:-}" ]] && env_args+=("ACFS_ASSETS_DIR=$ACFS_ASSETS_DIR")
        [[ -n "${ACFS_CHECKSUMS_YAML:-}" ]] && env_args+=("ACFS_CHECKSUMS_YAML=$ACFS_CHECKSUMS_YAML")
        [[ -n "${ACFS_MANIFEST_YAML:-}" ]] && env_args+=("ACFS_MANIFEST_YAML=$ACFS_MANIFEST_YAML")
        [[ -n "${CHECKSUMS_FILE:-}" ]] && env_args+=("CHECKSUMS_FILE=$CHECKSUMS_FILE")
        [[ -n "${SCRIPT_DIR:-}" ]] && env_args+=("SCRIPT_DIR=$SCRIPT_DIR")
        [[ -n "${ACFS_RAW:-}" ]] && env_args+=("ACFS_RAW=$ACFS_RAW")
        [[ -n "${ACFS_VERSION:-}" ]] && env_args+=("ACFS_VERSION=$ACFS_VERSION")
        [[ -n "${ACFS_REF:-}" ]] && env_args+=("ACFS_REF=$ACFS_REF")

        command_argv=("$@")
        if [[ ${#command_argv[@]} -gt 0 ]]; then
            case "${command_argv[0]}" in
                env)
                    command_argv[0]="$env_bin"
                    local env_command_index=1
                    while [[ "$env_command_index" -lt "${#command_argv[@]}" ]]; do
                        case "${command_argv[env_command_index]}" in
                            *=*) ((env_command_index += 1)) ;;
                            --) ((env_command_index += 1)); break ;;
                            -*) break ;;
                            *) break ;;
                        esac
                    done
                    if [[ "$env_command_index" -lt "${#command_argv[@]}" ]]; then
                        case "${command_argv[env_command_index]}" in
                            env) command_argv[env_command_index]="$env_bin" ;;
                            bash) command_argv[env_command_index]="$bash_bin" ;;
                            sh) command_argv[env_command_index]="$sh_bin" ;;
                        esac
                    fi
                    ;;
                bash) command_argv[0]="$bash_bin" ;;
                sh) command_argv[0]="$sh_bin" ;;
            esac
        fi

        # Already the target user
        if [[ "$(_acfs_resolve_current_user 2>/dev/null || true)" == "$user" ]]; then
            # Use explicit home path to avoid ambiguity if $HOME was mutated.
            (
                if ! cd "$user_home"; then
                    log_error "Unable to enter target home for '$user': $user_home"
                    exit 1
                fi
                "$env_bin" "${env_args[@]}" "${command_argv[@]}"
            )
            return $?
        fi

        # Prefer noninteractive sudo (non-login) when available.
        sudo_bin="$(_acfs_system_binary_path sudo 2>/dev/null || true)"
        if [[ -n "$sudo_bin" ]]; then
            # shellcheck disable=SC2016  # $HOME/$@ expand inside sh -c
            # Use sh -c to ensure the cd happens as the target user.
            "$sudo_bin" -n -u "$user" "$env_bin" "${env_args[@]}" "$sh_bin" -c 'cd "$HOME" || exit 1; exec "$@"' _ "${command_argv[@]}"
            return $?
        fi

        # Root-only fallbacks.
        runuser_bin="$(_acfs_system_binary_path runuser 2>/dev/null || true)"
        if [[ -n "$runuser_bin" ]]; then
            # shellcheck disable=SC2016  # $HOME/$@ expand inside sh -c
            "$runuser_bin" -u "$user" -- "$env_bin" "${env_args[@]}" "$sh_bin" -c 'cd "$HOME" || exit 1; exec "$@"' _ "${command_argv[@]}"
            return $?
        fi

        su_bin="$(_acfs_system_binary_path su 2>/dev/null || true)"
        [[ -n "$su_bin" ]] || {
            log_error "Unable to locate sudo, runuser, or su for target-user command"
            return 1
        }

        # su without login (-) to avoid sourcing profile files.
        local env_assignments=""
        local kv=""
        for kv in "${env_args[@]}"; do
            env_assignments+=" $(printf '%q' "$kv")"
        done
        env_assignments="${env_assignments# }"
        local user_home_q
        local env_bin_q
        user_home_q="$(printf '%q' "$user_home")"
        env_bin_q="$(printf '%q' "$env_bin")"
        "$su_bin" "$user" -c "cd $user_home_q || exit 1; $env_bin_q $env_assignments $(printf '%q ' "${command_argv[@]}")"
    }
fi

acfs_validate_primary_bin_dir() {
    local primary_bin_dir="${ACFS_BIN_DIR:-}"

    if [[ -z "$primary_bin_dir" ]] || [[ "$primary_bin_dir" == "/" ]] || [[ "$primary_bin_dir" != /* ]]; then
        log_error "ACFS_BIN_DIR must be an absolute path and cannot be '/' (got: ${primary_bin_dir:-<empty>})"
        return 1
    fi
}

acfs_primary_bin_dir_uses_root() {
    acfs_validate_primary_bin_dir >/dev/null || return 1
    [[ -n "${ACFS_BIN_DIR:-}" ]] || return 1
    [[ -n "${TARGET_HOME:-}" ]] || return 1

    case "$ACFS_BIN_DIR" in
        "$TARGET_HOME"|"$TARGET_HOME"/*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

_acfs_run_root_bin_command() {
    local sudo_bin=""

    if [[ -z "${1:-}" || "${1:-}" != /* ]]; then
        log_error "Root primary bin command must be an absolute trusted path (got: ${1:-<empty>})"
        return 1
    fi

    if [[ $EUID -eq 0 ]]; then
        "$@"
        return $?
    fi

    sudo_bin="$(_acfs_system_binary_path sudo 2>/dev/null || true)"
    if [[ -n "$sudo_bin" ]]; then
        "$sudo_bin" -n "$@"
        return $?
    fi

    log_error "Primary bin dir requires root, but sudo is unavailable: ${ACFS_BIN_DIR:-<unset>}"
    return 1
}

_acfs_primary_bin_tool_path() {
    local name="${1:-}"
    local tool_path=""

    tool_path="$(_acfs_system_binary_path "$name" 2>/dev/null || true)"
    if [[ -z "$tool_path" ]]; then
        log_error "Unable to locate trusted $name for primary bin operation"
        return 1
    fi

    printf '%s\n' "$tool_path"
}

acfs_ensure_primary_bin_dir() {
    local mkdir_bin=""

    acfs_validate_primary_bin_dir || return 1
    mkdir_bin="$(_acfs_primary_bin_tool_path mkdir)" || return 1

    if acfs_primary_bin_dir_uses_root; then
        _acfs_run_root_bin_command "$mkdir_bin" -p "$ACFS_BIN_DIR"
        return $?
    fi

    run_as_target "$mkdir_bin" -p "$ACFS_BIN_DIR"
}

acfs_link_primary_bin_command() {
    local source_path="$1"
    local command_name="$2"
    local dest_path=""
    local ln_bin=""

    acfs_ensure_primary_bin_dir || return 1
    ln_bin="$(_acfs_primary_bin_tool_path ln)" || return 1
    dest_path="$ACFS_BIN_DIR/$command_name"

    if acfs_primary_bin_dir_uses_root; then
        _acfs_run_root_bin_command "$ln_bin" -sf "$source_path" "$dest_path"
        return $?
    fi

    run_as_target "$ln_bin" -sf "$source_path" "$dest_path"
}

acfs_install_executable_into_primary_bin() {
    local src_path="$1"
    local command_name="$2"
    local dest_path=""
    local install_bin=""

    acfs_ensure_primary_bin_dir || return 1
    install_bin="$(_acfs_primary_bin_tool_path install)" || return 1
    dest_path="$ACFS_BIN_DIR/$command_name"

    if acfs_primary_bin_dir_uses_root; then
        _acfs_run_root_bin_command "$install_bin" -m 0755 "$src_path" "$dest_path"
        return $?
    fi

    run_as_target "$install_bin" -m 0755 "$src_path" "$dest_path"
}

# Run a shell string (or stdin) as TARGET_USER
run_as_target_shell() {
    local cmd="${1:-}"
    local path_export_source
    local env_bin=""
    local bash_bin=""
    path_export_source="$(_acfs_user_path_export_source)"

    if ! declare -f run_as_target >/dev/null 2>&1; then
        log_error "run_as_target_shell requires run_as_target"
        return 1
    fi
    env_bin="$(_acfs_system_binary_path env 2>/dev/null || true)"
    [[ -n "$env_bin" ]] || {
        log_error "Unable to locate env for target-user shell command"
        return 1
    }
    bash_bin="$(_acfs_system_binary_path bash 2>/dev/null || true)"
    [[ -n "$bash_bin" ]] || {
        log_error "Unable to locate bash for target-user shell command"
        return 1
    }

    # Keep user-provided path values in env data. The fixed shell wrapper
    # expands HOME/ACFS_BIN_DIR at runtime without re-parsing their contents.
    local -a shell_env=("ACFS_BASH_BIN=$bash_bin" "UV_NO_CONFIG=1")

    if [[ -n "$cmd" ]]; then
        # IMPORTANT: Avoid `bash -l` (login shell). Profile files are not a stable API.
        run_as_target "$env_bin" "${shell_env[@]}" "$bash_bin" -c "$path_export_source; set -euo pipefail; eval \"\$1\"" _ "$cmd"
        return $?
    fi

    # stdin mode
    run_as_target "$env_bin" "${shell_env[@]}" "$bash_bin" -c "$path_export_source; set -euo pipefail; (printf \"%s\\n\" \"set -euo pipefail\"; cat) | \"\$ACFS_BASH_BIN\" -s"
}

# Run a command as TARGET_USER while preserving stdin for the final runner.
# Typical usage: echo script | run_as_target_runner "bash" "-s" "--" "arg1"
# Env-prefixed usage is also supported: echo script | run_as_target_runner "env" "FOO=bar" "bash" "-s"
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
    local path_export_source=""
    local env_bin=""
    local bash_bin=""
    local sudo_bin=""

    if [[ "$EUID" -eq 0 ]]; then
        _run_shell_with_strict_mode "$cmd"
        return $?
    fi
    env_bin="$(_acfs_system_binary_path env 2>/dev/null || true)"
    [[ -n "$env_bin" ]] || {
        log_error "Unable to locate env for root shell command"
        return 1
    }
    bash_bin="$(_acfs_system_binary_path bash 2>/dev/null || true)"
    [[ -n "$bash_bin" ]] || {
        log_error "Unable to locate bash for root shell command"
        return 1
    }
    path_export_source="$(_acfs_user_path_export_source)"

    # Build env args for passing through sudo
    local -a env_cmd=()
    local -a env_args=()
    [[ -n "${TARGET_USER:-}" ]] && env_args+=("TARGET_USER=$TARGET_USER")
    [[ -n "${TARGET_HOME:-}" ]] && env_args+=("TARGET_HOME=$TARGET_HOME")
    [[ -n "${ACFS_HOME:-}" ]] && env_args+=("ACFS_HOME=$ACFS_HOME")
    [[ -n "${ACFS_BIN_DIR:-}" ]] && env_args+=("ACFS_BIN_DIR=$ACFS_BIN_DIR")
    [[ -n "${ACFS_BOOTSTRAP_DIR:-}" ]] && env_args+=("ACFS_BOOTSTRAP_DIR=$ACFS_BOOTSTRAP_DIR")
    [[ -n "${ACFS_LIB_DIR:-}" ]] && env_args+=("ACFS_LIB_DIR=$ACFS_LIB_DIR")
    [[ -n "${ACFS_GENERATED_DIR:-}" ]] && env_args+=("ACFS_GENERATED_DIR=$ACFS_GENERATED_DIR")
    [[ -n "${ACFS_ASSETS_DIR:-}" ]] && env_args+=("ACFS_ASSETS_DIR=$ACFS_ASSETS_DIR")
    [[ -n "${ACFS_CHECKSUMS_YAML:-}" ]] && env_args+=("ACFS_CHECKSUMS_YAML=$ACFS_CHECKSUMS_YAML")
    [[ -n "${ACFS_MANIFEST_YAML:-}" ]] && env_args+=("ACFS_MANIFEST_YAML=$ACFS_MANIFEST_YAML")
    [[ -n "${CHECKSUMS_FILE:-}" ]] && env_args+=("CHECKSUMS_FILE=$CHECKSUMS_FILE")
    [[ -n "${SCRIPT_DIR:-}" ]] && env_args+=("SCRIPT_DIR=$SCRIPT_DIR")
    [[ -n "${ACFS_RAW:-}" ]] && env_args+=("ACFS_RAW=$ACFS_RAW")
    [[ -n "${ACFS_VERSION:-}" ]] && env_args+=("ACFS_VERSION=$ACFS_VERSION")
    [[ -n "${ACFS_REF:-}" ]] && env_args+=("ACFS_REF=$ACFS_REF")

    env_cmd=("$env_bin" "${env_args[@]}" "ACFS_BASH_BIN=$bash_bin" "UV_NO_CONFIG=1")

    if [[ -n "${SUDO:-}" ]]; then
        if [[ "$SUDO" == /* && -x "$SUDO" ]]; then
            sudo_bin="$SUDO"
        else
            sudo_bin="$(_acfs_system_binary_path sudo 2>/dev/null || true)"
        fi
        [[ -n "$sudo_bin" ]] || {
            log_error "run_as_root_shell requires root or sudo"
            return 1
        }
        if [[ -n "$cmd" ]]; then
            "$sudo_bin" -n "${env_cmd[@]}" "$bash_bin" -c "$path_export_source; set -euo pipefail; eval \"\$1\"" _ "$cmd"
            return $?
        fi
        "$sudo_bin" -n "${env_cmd[@]}" "$bash_bin" -c "$path_export_source; set -euo pipefail; (printf \"%s\\n\" \"set -euo pipefail\"; cat) | \"\$ACFS_BASH_BIN\" -s"
        return $?
    fi

    sudo_bin="$(_acfs_system_binary_path sudo 2>/dev/null || true)"
    if [[ -n "$sudo_bin" ]]; then
        if [[ -n "$cmd" ]]; then
            "$sudo_bin" -n "${env_cmd[@]}" "$bash_bin" -c "$path_export_source; set -euo pipefail; eval \"\$1\"" _ "$cmd"
            return $?
        fi
        "$sudo_bin" -n "${env_cmd[@]}" "$bash_bin" -c "$path_export_source; set -euo pipefail; (printf \"%s\\n\" \"set -euo pipefail\"; cat) | \"\$ACFS_BASH_BIN\" -s"
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
# Skip-if-installed logic (bd-1eop)
# ------------------------------------------------------------
# These functions check whether a module is already installed
# using the installed_check field from the manifest.
#
# Set ACFS_FORCE_REINSTALL=true (or 1) to bypass these checks.
# The install.sh --force-reinstall flag sets this.
# ------------------------------------------------------------

: "${ACFS_FORCE_REINSTALL:=false}"

# Helper to check if force reinstall is enabled (handles true/1/yes)
_acfs_force_reinstall_enabled() {
    case "${ACFS_FORCE_REINSTALL:-false}" in
        true|1|yes|on) return 0 ;;
        *) return 1 ;;
    esac
}

# Check if a module is already installed
# Returns 0 (true) if installed, 1 (false) if not installed or check fails
acfs_module_is_installed() {
    local module_id="$1"
    local env_bin=""
    local bash_bin=""

    # If force reinstall is enabled, always return "not installed"
    if _acfs_force_reinstall_enabled; then
        return 1
    fi

    # Check if manifest index is loaded
    if [[ "${ACFS_MANIFEST_INDEX_LOADED:-false}" != "true" ]]; then
        return 1
    fi

    # Get the installed_check command for this module
    local check_cmd="${ACFS_MODULE_INSTALLED_CHECK[$module_id]:-}"
    if [[ -z "$check_cmd" ]]; then
        # No check defined - assume not installed
        return 1
    fi

    # Get execution context (default: current)
    local run_as="${ACFS_MODULE_INSTALLED_CHECK_RUN_AS[$module_id]:-current}"

    # Run the check in the appropriate context
    case "$run_as" in
        target_user|target)
            local path_export_source=""
            path_export_source="$(_acfs_user_path_export_source)"
            if declare -f run_as_target >/dev/null 2>&1; then
                env_bin="$(_acfs_system_binary_path env 2>/dev/null || true)"
                bash_bin="$(_acfs_system_binary_path bash 2>/dev/null || true)"
                [[ -n "$env_bin" && -n "$bash_bin" ]] || return 1
                run_as_target "$env_bin" "$bash_bin" -c \
                    "$path_export_source; set -euo pipefail; eval \"\$1\"" \
                    _ "$check_cmd" >/dev/null 2>&1
                return $?
            fi
            # Target-user checks must fail closed when we cannot execute in the
            # target context. Falling back to the current shell can incorrectly
            # mark a tool as installed based on host-only PATH entries.
            return 1
            ;;
        root)
            if declare -f run_as_root_shell >/dev/null 2>&1; then
                run_as_root_shell "$check_cmd" >/dev/null 2>&1
                return $?
            fi
            # Root checks must fail closed when sudo is unavailable. Falling
            # back to the current shell can incorrectly treat user-only tools
            # as root-installed.
            return 1
            ;;
        current|*)
            _run_shell_with_strict_mode "$check_cmd" >/dev/null 2>&1
            return $?
            ;;
    esac
}

# Check if a module should be skipped (already installed)
# Returns 0 (true) if should skip, 1 (false) if should install
acfs_should_skip_module() {
    local module_id="$1"

    # If force reinstall, don't skip
    if _acfs_force_reinstall_enabled; then
        return 1
    fi

    # Check if installed
    if acfs_module_is_installed "$module_id"; then
        return 0
    fi

    return 1
}

# ------------------------------------------------------------
# Command existence helpers
# ------------------------------------------------------------

command_exists() {
    local cmd="${1:-}"

    [[ -n "$cmd" ]] || return 1
    case "$cmd" in
        .|..) return 1 ;;
        *[!A-Za-z0-9._+-]*) return 1 ;;
    esac

    command -v "$cmd" >/dev/null 2>&1
}

command_exists_as_target() {
    local cmd="${1:-}"
    local path_export_source
    local env_bin=""
    local bash_bin=""

    [[ -n "$cmd" ]] || return 1
    case "$cmd" in
        .|..) return 1 ;;
        *[!A-Za-z0-9._+-]*) return 1 ;;
    esac

    if ! declare -f run_as_target >/dev/null 2>&1; then
        return 1
    fi

    path_export_source="$(_acfs_user_path_export_source)"
    env_bin="$(_acfs_system_binary_path env 2>/dev/null || true)"
    bash_bin="$(_acfs_system_binary_path bash 2>/dev/null || true)"
    [[ -n "$env_bin" && -n "$bash_bin" ]] || return 1

    # NOTE: We intentionally avoid embedding $cmd into the shell string.
    # Passing as $1 avoids quoting bugs when cmd contains special chars.
    #
    # Also, extend PATH with common user install locations so we can detect
    # tools installed under the configured user bin dir, cargo, bun, etc.
    run_as_target "$env_bin" "$bash_bin" -c \
        "$path_export_source; command -v -- \"\$1\" >/dev/null 2>&1" \
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
    local desc=""
    local ran_any=false

    # Count modules for progress tracking (bd-21kh)
    local module_count=0
    if declare -f progress_count_modules >/dev/null 2>&1; then
        module_count=$(progress_count_modules "$category" "$phase")
    fi

    # Initialize progress bar if we have modules
    if [[ "$module_count" -gt 0 ]] && declare -f progress_init >/dev/null 2>&1; then
        progress_init "$module_count"
    fi

    for module in "${ACFS_EFFECTIVE_PLAN[@]}"; do
        key="$module"
        if [[ "${ACFS_MODULE_CATEGORY[$key]:-}" != "$category" ]]; then
            continue
        fi
        if [[ "${ACFS_MODULE_PHASE[$key]:-}" != "$phase" ]]; then
            continue
        fi
        func="${ACFS_MODULE_FUNC[$key]:-}"
        desc="${ACFS_MODULE_DESC[$key]:-$module}"
        if [[ -z "$func" ]]; then
            log_error "Missing generated function for $module"
            if declare -f progress_finish >/dev/null 2>&1; then progress_finish; fi
            return 1
        fi
        if ! declare -f "$func" >/dev/null 2>&1; then
            log_error "Generated function not found: $func (module $module)"
            if declare -f progress_finish >/dev/null 2>&1; then progress_finish; fi
            return 1
        fi

        # Skip-if-installed check (bd-1eop)
        if acfs_should_skip_module "$module"; then
            log_info "Skipping $module (already installed)"
            # Still update progress bar to show skip
            if declare -f progress_update >/dev/null 2>&1; then
                progress_update "$module" "$desc [skipped]"
            fi
            ran_any=true
            continue
        fi

        # Update progress bar before installing (bd-21kh)
        if declare -f progress_update >/dev/null 2>&1; then
            progress_update "$module" "$desc"
        fi

        if ! "$func"; then
            log_error "Generated module failed: $module"
            if declare -f progress_finish >/dev/null 2>&1; then progress_finish; fi
            return 1
        fi
        ran_any=true
    done

    # Finish progress bar
    if [[ "$module_count" -gt 0 ]] && declare -f progress_finish >/dev/null 2>&1; then
        progress_finish
    fi

    if [[ "$ran_any" != "true" ]]; then
        log_detail "No generated modules selected for $category (phase $phase)"
    fi

    return 0
}
