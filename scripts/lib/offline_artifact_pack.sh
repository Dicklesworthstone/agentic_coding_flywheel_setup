#!/usr/bin/env bash
# ============================================================
# ACFS Offline Artifact Pack Builder
#
# Prepares an inspectable offline pack from acfs.manifest.yaml verified
# installer entries and checksums.yaml approved source URLs.
# ============================================================

set -euo pipefail

OFFLINE_PACK_BUILD_SCHEMA="acfs.offline-artifact-pack-build.v1"
OFFLINE_PACK_SCHEMA="acfs.offline-artifact-pack.v1"
OFFLINE_PACK_FORMAT="markdown"
OFFLINE_PACK_DRY_RUN=false
OFFLINE_PACK_BEST_EFFORT=false
OFFLINE_PACK_OUTPUT_DIR=""
OFFLINE_PACK_SOURCE_ROOT=""
OFFLINE_PACK_CHECKSUMS_FILE=""
OFFLINE_PACK_MANIFEST_FILE=""
OFFLINE_PACK_TIMEOUT_SECONDS=60
OFFLINE_PACK_EXPIRES_DAYS=30
OFFLINE_PACK_ARCH="${ACFS_OFFLINE_PACK_ARCH:-}"
OFFLINE_PACK_UBUNTU_VERSION="${ACFS_OFFLINE_PACK_UBUNTU_VERSION:-25.10}"
OFFLINE_PACK_MODULE_ARGS=()
OFFLINE_PACK_SELECTED_MODULES=()
OFFLINE_PACK_ERRORS=()
OFFLINE_PACK_WARNINGS=()
OFFLINE_PACK_MODULES_JSON="[]"
OFFLINE_PACK_ARTIFACTS_JSON="[]"
OFFLINE_PACK_FAILURES_JSON="[]"
OFFLINE_PACK_JQ_BIN=""
OFFLINE_PACK_HASH_SPEC=""
OFFLINE_PACK_AWK_BIN=""

declare -gA OFFLINE_PACK_INSTALLER_URL=()
declare -gA OFFLINE_PACK_INSTALLER_SHA=()
declare -gA OFFLINE_PACK_MODULE_KNOWN=()
declare -gA OFFLINE_PACK_MODULE_TOOL=()
declare -gA OFFLINE_PACK_MODULE_RUNNER=()
declare -gA OFFLINE_PACK_MODULE_ARGS_RAW=()
declare -ga OFFLINE_PACK_VERIFIED_MODULES=()

offline_pack_usage() {
    cat <<'EOF'
Usage: acfs offline-pack build [OPTIONS]

Options:
  --output DIR          Directory that will receive acfs-offline-pack/
  --module ID          Include one manifest module (repeatable; default: all verified installers)
  --dry-run            Print the resolved pack plan without writing files
  --best-effort        Write a diagnostic pack even when some downloads fail
  --json               Emit machine-readable JSON
  --markdown           Emit human-readable output (default)
  --source-root DIR    ACFS source root (default: inferred from this script)
  --manifest-file FILE Manifest YAML (default: SOURCE_ROOT/acfs.manifest.yaml)
  --checksums-file FILE checksums.yaml (default: SOURCE_ROOT/checksums.yaml)
  --arch ARCH          Target architecture (default: uname -m)
  --ubuntu-version VER Target Ubuntu version metadata (default: 25.10)
  --timeout SECONDS    Per-download timeout for HTTPS sources (default: 60)
  --expires-days DAYS  Expiry window recorded in manifest.json (default: 30)
  --help, -h           Show this help

The builder only bundles modules that use verified_installer metadata and whose
installer URL and SHA256 are present in checksums.yaml. It refuses partial packs
unless --best-effort is set, in which case manifest.json is marked diagnostic.
EOF
}

offline_pack_add_error() {
    OFFLINE_PACK_ERRORS+=("$1")
}

offline_pack_add_warning() {
    OFFLINE_PACK_WARNINGS+=("$1")
}

offline_pack_json_lines() {
    if (( $# == 0 )); then
        return 0
    fi
    printf '%s\n' "$@"
}

offline_pack_append_failure() {
    local code="$1"
    local module_id="$2"
    local tool="$3"
    local message="$4"

    OFFLINE_PACK_FAILURES_JSON="$(
        offline_pack_jq -c \
            --arg code "$code" \
            --arg moduleId "$module_id" \
            --arg tool "$tool" \
            --arg message "$message" \
            '. + [{code: $code, moduleId: $moduleId, verifiedInstallerKey: $tool, message: $message}]' \
            <<<"$OFFLINE_PACK_FAILURES_JSON"
    )"
}

offline_pack_status() {
    if (( ${#OFFLINE_PACK_ERRORS[@]} > 0 )); then
        if [[ "$OFFLINE_PACK_BEST_EFFORT" == "true" ]]; then
            printf 'warn\n'
        else
            printf 'fail\n'
        fi
    elif (( ${#OFFLINE_PACK_WARNINGS[@]} > 0 )); then
        printf 'warn\n'
    else
        printf 'pass\n'
    fi
}

offline_pack_script_root() {
    local source_path="${BASH_SOURCE[0]}"
    local source_dir="."

    case "$source_path" in
        */*) source_dir="${source_path%/*}" ;;
    esac

    cd "$source_dir/../.." && pwd -P
}

offline_pack_abs_file() {
    local path="$1"
    local dir=""
    local base=""

    [[ -n "$path" ]] || return 1
    case "$path" in
        /*) ;;
        *) path="$PWD/$path" ;;
    esac

    dir="${path%/*}"
    base="${path##*/}"
    [[ -d "$dir" ]] || return 1
    printf '%s/%s\n' "$(cd "$dir" && pwd -P)" "$base"
}

offline_pack_abs_dir() {
    local path="$1"

    [[ -n "$path" ]] || return 1
    offline_pack_mkdir_p "$path"
    cd "$path" && pwd -P
}

offline_pack_system_binary_path() {
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
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

offline_pack_required_binary_path() {
    local name="${1:-}"
    local path=""

    path="$(offline_pack_system_binary_path "$name" 2>/dev/null || true)"
    [[ -n "$path" ]] || return 127
    printf '%s\n' "$path"
}

offline_pack_require_jq() {
    OFFLINE_PACK_JQ_BIN="$(offline_pack_required_binary_path jq 2>/dev/null || true)"
    if [[ -z "$OFFLINE_PACK_JQ_BIN" ]]; then
        echo "Error: jq is required for offline artifact pack building" >&2
        return 2
    fi
}

offline_pack_jq() {
    local jq_bin="${OFFLINE_PACK_JQ_BIN:-}"

    if [[ -z "$jq_bin" || ! -x "$jq_bin" ]]; then
        jq_bin="$(offline_pack_required_binary_path jq)" || return $?
        OFFLINE_PACK_JQ_BIN="$jq_bin"
    fi

    "$jq_bin" "$@"
}

offline_pack_awk() {
    local awk_bin="${OFFLINE_PACK_AWK_BIN:-}"

    if [[ -z "$awk_bin" || ! -x "$awk_bin" ]]; then
        awk_bin="$(offline_pack_required_binary_path awk)" || return $?
        OFFLINE_PACK_AWK_BIN="$awk_bin"
    fi

    "$awk_bin" "$@"
}

offline_pack_mkdir_p() {
    local mkdir_bin=""

    mkdir_bin="$(offline_pack_required_binary_path mkdir)" || return $?
    "$mkdir_bin" -p "$@"
}

offline_pack_cp() {
    local cp_bin=""

    cp_bin="$(offline_pack_required_binary_path cp)" || return $?
    "$cp_bin" "$@"
}

offline_pack_find() {
    local find_bin=""

    find_bin="$(offline_pack_required_binary_path find)" || return $?
    "$find_bin" "$@"
}

offline_pack_date() {
    local date_bin=""

    date_bin="$(offline_pack_required_binary_path date)" || return $?
    "$date_bin" "$@"
}

offline_pack_uname() {
    local uname_bin=""

    uname_bin="$(offline_pack_required_binary_path uname)" || return $?
    "$uname_bin" "$@"
}

offline_pack_git() {
    local git_bin=""

    git_bin="$(offline_pack_system_binary_path git 2>/dev/null || true)"
    [[ -n "$git_bin" ]] || return 127
    "$git_bin" "$@"
}

offline_pack_curl_binary_path() {
    local override="${ACFS_OFFLINE_PACK_CURL_BIN:-}"

    if [[ -n "$override" ]]; then
        case "$override" in
            /*)
                [[ -x "$override" ]] || return 127
                printf '%s\n' "$override"
                return 0
                ;;
            *)
                return 127
                ;;
        esac
    fi

    offline_pack_required_binary_path curl
}

offline_pack_hash_tool() {
    local sha256sum_bin=""
    local shasum_bin=""

    if [[ -n "$OFFLINE_PACK_HASH_SPEC" ]]; then
        printf '%s\n' "$OFFLINE_PACK_HASH_SPEC"
        return 0
    fi

    sha256sum_bin="$(offline_pack_system_binary_path sha256sum 2>/dev/null || true)"
    if [[ -n "$sha256sum_bin" ]]; then
        OFFLINE_PACK_HASH_SPEC="sha256sum:$sha256sum_bin"
        printf '%s\n' "$OFFLINE_PACK_HASH_SPEC"
        return 0
    fi

    shasum_bin="$(offline_pack_system_binary_path shasum 2>/dev/null || true)"
    if [[ -n "$shasum_bin" ]]; then
        OFFLINE_PACK_HASH_SPEC="shasum:$shasum_bin"
        printf '%s\n' "$OFFLINE_PACK_HASH_SPEC"
        return 0
    fi

    return 1
}

offline_pack_sha256() {
    local file="$1"
    local hash_spec=""
    local hash_tool=""
    local hash_bin=""
    local output=""
    local hash=""

    hash_spec="$(offline_pack_hash_tool)" || {
        echo "Error: no trusted SHA256 tool found" >&2
        return 2
    }
    hash_tool="${hash_spec%%:*}"
    hash_bin="${hash_spec#*:}"

    case "$hash_tool" in
        sha256sum) output="$("$hash_bin" "$file")" || return 1 ;;
        shasum) output="$("$hash_bin" -a 256 "$file")" || return 1 ;;
        *)
            echo "Error: unsupported SHA256 tool: $hash_tool" >&2
            return 2
            ;;
    esac

    read -r hash _ <<<"$output"
    [[ -n "$hash" ]] || return 1
    printf '%s\n' "$hash"
}

offline_pack_file_size() {
    local file="$1"
    local wc_bin=""
    local output=""

    wc_bin="$(offline_pack_required_binary_path wc)" || return $?
    output="$("$wc_bin" -c < "$file")" || return 1
    output="${output//[[:space:]]/}"
    [[ -n "$output" ]] || return 1
    printf '%s\n' "$output"
}

offline_pack_parse_positive_int() {
    local value="$1"
    local label="$2"

    if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: $label must be a positive integer" >&2
        return 2
    fi
}

offline_pack_parse_args() {
    if [[ "${1:-}" == "build" ]]; then
        shift
    elif [[ "${1:-}" == "help" || "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        offline_pack_usage
        return 100
    elif [[ -n "${1:-}" && "${1:-}" != -* ]]; then
        echo "Error: unknown offline-pack subcommand: $1" >&2
        echo "Run 'acfs offline-pack --help' for usage." >&2
        return 2
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                OFFLINE_PACK_FORMAT="json"
                shift
                ;;
            --markdown)
                OFFLINE_PACK_FORMAT="markdown"
                shift
                ;;
            --dry-run)
                OFFLINE_PACK_DRY_RUN=true
                shift
                ;;
            --best-effort)
                OFFLINE_PACK_BEST_EFFORT=true
                shift
                ;;
            --output)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --output requires a directory" >&2
                    return 2
                fi
                OFFLINE_PACK_OUTPUT_DIR="$2"
                shift 2
                ;;
            --module)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --module requires a module id" >&2
                    return 2
                fi
                OFFLINE_PACK_MODULE_ARGS+=("$2")
                shift 2
                ;;
            --source-root)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --source-root requires a directory" >&2
                    return 2
                fi
                OFFLINE_PACK_SOURCE_ROOT="$2"
                shift 2
                ;;
            --manifest-file)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --manifest-file requires a file" >&2
                    return 2
                fi
                OFFLINE_PACK_MANIFEST_FILE="$2"
                shift 2
                ;;
            --checksums-file)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --checksums-file requires a file" >&2
                    return 2
                fi
                OFFLINE_PACK_CHECKSUMS_FILE="$2"
                shift 2
                ;;
            --arch)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --arch requires a value" >&2
                    return 2
                fi
                OFFLINE_PACK_ARCH="$2"
                shift 2
                ;;
            --ubuntu-version)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --ubuntu-version requires a value" >&2
                    return 2
                fi
                OFFLINE_PACK_UBUNTU_VERSION="$2"
                shift 2
                ;;
            --timeout)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --timeout requires seconds" >&2
                    return 2
                fi
                offline_pack_parse_positive_int "$2" "--timeout" || return 2
                OFFLINE_PACK_TIMEOUT_SECONDS="$2"
                shift 2
                ;;
            --expires-days)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --expires-days requires days" >&2
                    return 2
                fi
                offline_pack_parse_positive_int "$2" "--expires-days" || return 2
                OFFLINE_PACK_EXPIRES_DAYS="$2"
                shift 2
                ;;
            --help|-h)
                offline_pack_usage
                return 100
                ;;
            *)
                echo "Error: unknown option: $1" >&2
                echo "Run 'acfs offline-pack --help' for usage." >&2
                return 2
                ;;
        esac
    done
}

offline_pack_resolve_inputs() {
    if [[ -z "$OFFLINE_PACK_SOURCE_ROOT" ]]; then
        OFFLINE_PACK_SOURCE_ROOT="$(offline_pack_script_root)"
    else
        OFFLINE_PACK_SOURCE_ROOT="$(cd "$OFFLINE_PACK_SOURCE_ROOT" && pwd -P)"
    fi

    if [[ -z "$OFFLINE_PACK_CHECKSUMS_FILE" ]]; then
        OFFLINE_PACK_CHECKSUMS_FILE="$OFFLINE_PACK_SOURCE_ROOT/checksums.yaml"
    fi
    if [[ -z "$OFFLINE_PACK_MANIFEST_FILE" ]]; then
        OFFLINE_PACK_MANIFEST_FILE="$OFFLINE_PACK_SOURCE_ROOT/acfs.manifest.yaml"
    fi
    if [[ -z "$OFFLINE_PACK_ARCH" ]]; then
        OFFLINE_PACK_ARCH="$(offline_pack_uname -m)"
    fi

    OFFLINE_PACK_CHECKSUMS_FILE="$(offline_pack_abs_file "$OFFLINE_PACK_CHECKSUMS_FILE")" || {
        offline_pack_add_error "pack_checksums_mismatch: checksums.yaml not found"
        return 1
    }
    OFFLINE_PACK_MANIFEST_FILE="$(offline_pack_abs_file "$OFFLINE_PACK_MANIFEST_FILE")" || {
        offline_pack_add_error "pack_missing_manifest: acfs.manifest.yaml not found"
        return 1
    }

    case "$OFFLINE_PACK_ARCH" in
        amd64) OFFLINE_PACK_ARCH="x86_64" ;;
        arm64) OFFLINE_PACK_ARCH="aarch64" ;;
    esac

    case "$OFFLINE_PACK_ARCH" in
        x86_64|aarch64) ;;
        *)
            offline_pack_add_error "pack_arch_unsupported: unsupported architecture $OFFLINE_PACK_ARCH"
            return 1
            ;;
    esac

    if [[ "$OFFLINE_PACK_DRY_RUN" != "true" && -z "$OFFLINE_PACK_OUTPUT_DIR" ]]; then
        offline_pack_add_error "pack_output_required: --output is required unless --dry-run is set"
        return 1
    fi
}

offline_pack_trim_yaml_scalar() {
    local value="$1"

    value="${value%%#*}"
    value="${value%"${value##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"
    printf '%s\n' "$value"
}

offline_pack_module_id_is_valid() {
    local module_id="${1:-}"
    [[ "$module_id" =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$ ]]
}

offline_pack_installer_key_is_valid() {
    local tool="${1:-}"
    [[ "$tool" =~ ^[a-z][a-z0-9_]*$ ]]
}

offline_pack_installer_runner_is_valid() {
    case "${1:-}" in
        bash|sh) return 0 ;;
        *) return 1 ;;
    esac
}

offline_pack_load_checksums() {
    local file="$1"
    local line=""
    local current_tool=""
    local in_installers=false
    local installers_indent=0
    local tool_indent=""
    local indent=""
    local indent_len=0
    local value=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line//[[:space:]]/}" ]] && continue

        indent="${line%%[^ ]*}"
        indent_len="${#indent}"

        if [[ "$in_installers" == "false" ]]; then
            if [[ "$line" =~ ^[[:space:]]*installers:[[:space:]]*$ ]]; then
                in_installers=true
                installers_indent="$indent_len"
                tool_indent=""
                current_tool=""
            fi
            continue
        fi

        if (( indent_len <= installers_indent )); then
            in_installers=false
            tool_indent=""
            current_tool=""
            continue
        fi

        if [[ "$line" =~ ^[[:space:]]*([[:alnum:]_-]+):[[:space:]]*$ ]]; then
            if [[ -z "$tool_indent" ]]; then
                tool_indent="$indent_len"
            fi
            if (( indent_len == tool_indent )); then
                current_tool="${BASH_REMATCH[1]}"
                continue
            fi
        fi

        if [[ -n "$current_tool" && "$line" =~ ^[[:space:]]*url:[[:space:]]*(.*)$ ]]; then
            value="$(offline_pack_trim_yaml_scalar "${BASH_REMATCH[1]}")"
            OFFLINE_PACK_INSTALLER_URL["$current_tool"]="$value"
            continue
        fi

        if [[ -n "$current_tool" && "$line" =~ ^[[:space:]]*sha256:[[:space:]]*(.*)$ ]]; then
            value="$(offline_pack_trim_yaml_scalar "${BASH_REMATCH[1]}")"
            if [[ "$value" =~ ^[0-9A-Fa-f]{64}$ ]]; then
                OFFLINE_PACK_INSTALLER_SHA["$current_tool"]="${value,,}"
            fi
        fi
    done < "$file"

    if (( ${#OFFLINE_PACK_INSTALLER_SHA[@]} == 0 )); then
        offline_pack_add_error "pack_checksums_mismatch: no installer checksums found"
        return 1
    fi
}

offline_pack_load_manifest_modules() {
    local file="$1"
    local module_id=""
    local tool=""
    local runner=""
    local args_raw=""

    while IFS=$'\t' read -r module_id tool runner args_raw; do
        [[ -n "$module_id" ]] || continue

        # Keep the standalone Bash reader on the same security boundary as the
        # canonical TypeScript manifest schema. Module IDs become directory
        # components below, so accepting a schema-invalid ID here would turn a
        # malformed --manifest-file into a path traversal primitive.
        if ! offline_pack_module_id_is_valid "$module_id"; then
            offline_pack_add_error "pack_malformed_manifest: invalid module id $module_id"
            continue
        fi
        if [[ -n "${OFFLINE_PACK_MODULE_KNOWN[$module_id]:-}" ]]; then
            offline_pack_add_error "pack_malformed_manifest: duplicate module id $module_id"
            continue
        fi

        OFFLINE_PACK_MODULE_KNOWN["$module_id"]=1
        if [[ -n "$tool" ]]; then
            if ! offline_pack_installer_key_is_valid "$tool"; then
                offline_pack_add_error "pack_malformed_manifest: invalid verified_installer tool for $module_id"
                continue
            fi
            if ! offline_pack_installer_runner_is_valid "$runner"; then
                offline_pack_add_error "pack_malformed_manifest: invalid verified_installer runner for $module_id"
                continue
            fi
            OFFLINE_PACK_MODULE_TOOL["$module_id"]="$tool"
            OFFLINE_PACK_MODULE_RUNNER["$module_id"]="$runner"
            OFFLINE_PACK_MODULE_ARGS_RAW["$module_id"]="$args_raw"
            OFFLINE_PACK_VERIFIED_MODULES+=("$module_id")
        fi
    done < <(
        offline_pack_awk '
            function trim(value) {
                sub(/#.*/, "", value)
                gsub(/^[ \t]+|[ \t]+$/, "", value)
                gsub(/^"|"$/, "", value)
                gsub(/^'\''|'\''$/, "", value)
                return value
            }
            function emit() {
                if (id != "") {
                    print id "\t" tool "\t" runner "\t" args
                }
            }
            /^  - id:[ \t]*/ {
                emit()
                id = trim(substr($0, index($0, ":") + 1))
                tool = ""
                runner = ""
                args = ""
                in_vi = 0
                next
            }
            id != "" && /^    verified_installer:[ \t]*$/ {
                in_vi = 1
                next
            }
            in_vi && /^      tool:[ \t]*/ {
                tool = trim(substr($0, index($0, ":") + 1))
                next
            }
            in_vi && /^      runner:[ \t]*/ {
                runner = trim(substr($0, index($0, ":") + 1))
                next
            }
            in_vi && /^      args:[ \t]*/ {
                args = trim(substr($0, index($0, ":") + 1))
                next
            }
            END { emit() }
        ' "$file"
    )

    if (( ${#OFFLINE_PACK_MODULE_KNOWN[@]} == 0 )); then
        offline_pack_add_error "pack_malformed_manifest: no manifest modules found"
        return 1
    fi
}

offline_pack_select_modules() {
    local module_id=""
    local tool=""
    local url=""

    if (( ${#OFFLINE_PACK_MODULE_ARGS[@]} == 0 )); then
        OFFLINE_PACK_SELECTED_MODULES=("${OFFLINE_PACK_VERIFIED_MODULES[@]}")
    else
        OFFLINE_PACK_SELECTED_MODULES=("${OFFLINE_PACK_MODULE_ARGS[@]}")
    fi

    for module_id in "${OFFLINE_PACK_SELECTED_MODULES[@]}"; do
        if ! offline_pack_module_id_is_valid "$module_id"; then
            offline_pack_add_error "pack_malformed_manifest: invalid module id $module_id"
            continue
        fi
        if [[ -z "${OFFLINE_PACK_MODULE_KNOWN[$module_id]:-}" ]]; then
            offline_pack_add_error "pack_unknown_module: $module_id"
            continue
        fi

        tool="${OFFLINE_PACK_MODULE_TOOL[$module_id]:-}"
        if [[ -z "$tool" ]]; then
            offline_pack_add_error "pack_unbundled_required_module: $module_id has no verified_installer"
            continue
        fi

        url="${OFFLINE_PACK_INSTALLER_URL[$tool]:-}"
        if [[ -z "$url" || -z "${OFFLINE_PACK_INSTALLER_SHA[$tool]:-}" ]]; then
            offline_pack_add_error "pack_checksums_mismatch: installer key $tool missing from checksums.yaml"
            continue
        fi

        case "$url" in
            https://*) ;;
            *)
                offline_pack_add_error "pack_non_https_source: installer key $tool must use an HTTPS source URL"
                ;;
        esac
    done
}

offline_pack_iso_now() {
    offline_pack_date -u +%Y-%m-%dT%H:%M:%SZ
}

offline_pack_iso_expires() {
    offline_pack_date -u -d "$OFFLINE_PACK_EXPIRES_DAYS days" +%Y-%m-%dT%H:%M:%SZ
}

offline_pack_output_dir_is_empty() {
    local dir="$1"
    local found=""

    [[ -d "$dir" ]] || return 0
    found="$(offline_pack_find "$dir" -mindepth 1 -maxdepth 1 -print -quit)"
    [[ -z "$found" ]]
}

offline_pack_prepare_layout() {
    local output_dir="$1"
    local pack_root="$2"
    local rel=""

    if [[ -e "$pack_root" ]]; then
        offline_pack_add_error "pack_output_not_empty: $pack_root already exists"
        return 1
    fi

    if ! offline_pack_output_dir_is_empty "$output_dir"; then
        offline_pack_add_error "pack_output_not_empty: $output_dir is not empty"
        return 1
    fi

    offline_pack_mkdir_p "$pack_root/scripts" "$pack_root/provenance" "$pack_root/artifacts"

    for rel in VERSION acfs.manifest.yaml checksums.yaml; do
        case "$rel" in
            VERSION)
                [[ -f "$OFFLINE_PACK_SOURCE_ROOT/$rel" ]] || {
                    offline_pack_add_error "pack_source_missing: $rel"
                    return 1
                }
                offline_pack_cp "$OFFLINE_PACK_SOURCE_ROOT/$rel" "$pack_root/$rel"
                ;;
            acfs.manifest.yaml)
                offline_pack_cp "$OFFLINE_PACK_MANIFEST_FILE" "$pack_root/$rel"
                ;;
            checksums.yaml)
                offline_pack_cp "$OFFLINE_PACK_CHECKSUMS_FILE" "$pack_root/$rel"
                ;;
        esac
    done

    for rel in scripts/lib scripts/generated acfs; do
        [[ -e "$OFFLINE_PACK_SOURCE_ROOT/$rel" ]] || {
            offline_pack_add_error "pack_source_missing: $rel"
            return 1
        }
    done

    offline_pack_cp -R "$OFFLINE_PACK_SOURCE_ROOT/scripts/lib" "$pack_root/scripts/lib"
    offline_pack_cp -R "$OFFLINE_PACK_SOURCE_ROOT/scripts/generated" "$pack_root/scripts/generated"
    offline_pack_cp -R "$OFFLINE_PACK_SOURCE_ROOT/acfs" "$pack_root/acfs"
}

offline_pack_fetch_url() {
    local url="$1"
    local destination="$2"
    local curl_args=()
    local curl_bin=""

    offline_pack_mkdir_p "${destination%/*}"

    case "$url" in
        https://*)
            curl_bin="$(offline_pack_curl_binary_path)" || return 1
            curl_args=(--proto '=https' --proto-redir '=https' -fsSL --connect-timeout 10 --max-time "$OFFLINE_PACK_TIMEOUT_SECONDS" -o "$destination" "$url")
            "$curl_bin" "${curl_args[@]}"
            ;;
        *)
            return 2
            ;;
    esac
}

offline_pack_append_module_json() {
    local module_id="$1"
    local tool="$2"
    local runner="$3"
    local args_raw="$4"

    OFFLINE_PACK_MODULES_JSON="$(
        offline_pack_jq -c \
            --arg id "$module_id" \
            --arg policy "bundled" \
            --arg tool "$tool" \
            --arg runner "$runner" \
            --arg argsRaw "$args_raw" \
            '. + [{
                id: $id,
                bundlingPolicy: $policy,
                verifiedInstallerKey: $tool,
                verifiedInstallerRunner: $runner,
                verifiedInstallerArgsRaw: $argsRaw
            }]' \
            <<<"$OFFLINE_PACK_MODULES_JSON"
    )"
}

offline_pack_append_artifact_json() {
    local module_id="$1"
    local tool="$2"
    local rel_path="$3"
    local source_url="$4"
    local sha256="$5"
    local size_bytes="$6"

    OFFLINE_PACK_ARTIFACTS_JSON="$(
        offline_pack_jq -c \
            --arg id "$module_id:$tool" \
            --arg moduleId "$module_id" \
            --arg key "$tool" \
            --arg path "$rel_path" \
            --arg sourceUrl "$source_url" \
            --arg sha256 "$sha256" \
            --arg arch "$OFFLINE_PACK_ARCH" \
            --argjson sizeBytes "$size_bytes" \
            '. + [{
                id: $id,
                moduleId: $moduleId,
                kind: "verified_installer",
                verifiedInstallerKey: $key,
                path: $path,
                sourceUrl: $sourceUrl,
                sha256: $sha256,
                sizeBytes: $sizeBytes,
                architecture: $arch
            }]' \
            <<<"$OFFLINE_PACK_ARTIFACTS_JSON"
    )"
}

offline_pack_download_artifacts() {
    local pack_root="$1"
    local module_id=""
    local tool=""
    local url=""
    local expected=""
    local rel_path=""
    local artifact_path=""
    local actual=""
    local size_bytes=""
    local runner=""
    local args_raw=""
    local message=""
    local fetch_status=0

    for module_id in "${OFFLINE_PACK_SELECTED_MODULES[@]}"; do
        if ! offline_pack_module_id_is_valid "$module_id"; then
            offline_pack_add_error "pack_malformed_manifest: invalid module id $module_id"
            return 1
        fi
        tool="${OFFLINE_PACK_MODULE_TOOL[$module_id]:-}"
        [[ -n "$tool" ]] || continue
        url="${OFFLINE_PACK_INSTALLER_URL[$tool]:-}"
        expected="${OFFLINE_PACK_INSTALLER_SHA[$tool]:-}"
        runner="${OFFLINE_PACK_MODULE_RUNNER[$module_id]:-}"
        args_raw="${OFFLINE_PACK_MODULE_ARGS_RAW[$module_id]:-}"
        rel_path="artifacts/$module_id/${tool}-install.sh"
        artifact_path="$pack_root/$rel_path"

        fetch_status=0
        offline_pack_fetch_url "$url" "$artifact_path" || fetch_status=$?
        if (( fetch_status != 0 )); then
            message="pack_download_failed: $module_id from $url"
            offline_pack_add_error "$message"
            offline_pack_append_failure "pack_download_failed" "$module_id" "$tool" "$message"
            if [[ "$OFFLINE_PACK_BEST_EFFORT" != "true" ]]; then
                return 1
            fi
            continue
        fi

        actual="$(offline_pack_sha256 "$artifact_path")"
        if [[ "$actual" != "$expected" ]]; then
            message="pack_hash_mismatch: $module_id expected $expected got $actual"
            offline_pack_add_error "$message"
            offline_pack_append_failure "pack_hash_mismatch" "$module_id" "$tool" "$message"
            if [[ "$OFFLINE_PACK_BEST_EFFORT" != "true" ]]; then
                return 1
            fi
            continue
        fi

        size_bytes="$(offline_pack_file_size "$artifact_path")"
        offline_pack_append_module_json "$module_id" "$tool" "$runner" "$args_raw"
        offline_pack_append_artifact_json "$module_id" "$tool" "$rel_path" "$url" "$actual" "$size_bytes"
    done
}

offline_pack_plan_json() {
    local generated_at="$1"
    local expires_at="$2"
    local selected_json="[]"
    local module_id=""
    local tool=""
    local url=""

    for module_id in "${OFFLINE_PACK_SELECTED_MODULES[@]}"; do
        tool="${OFFLINE_PACK_MODULE_TOOL[$module_id]:-}"
        if [[ -n "$tool" ]]; then
            url="${OFFLINE_PACK_INSTALLER_URL[$tool]:-}"
        else
            url=""
        fi
        selected_json="$(
            offline_pack_jq -c \
                --arg moduleId "$module_id" \
                --arg tool "$tool" \
                --arg url "$url" \
                '. + [{moduleId: $moduleId, verifiedInstallerKey: $tool, sourceUrl: $url}]' \
                <<<"$selected_json"
        )"
    done

    offline_pack_jq -n \
        --arg schema "$OFFLINE_PACK_BUILD_SCHEMA" \
        --arg status "$(offline_pack_status)" \
        --arg mode "dry-run" \
        --arg packSchema "$OFFLINE_PACK_SCHEMA" \
        --arg generatedAt "$generated_at" \
        --arg expiresAt "$expires_at" \
        --arg arch "$OFFLINE_PACK_ARCH" \
        --arg ubuntuVersion "$OFFLINE_PACK_UBUNTU_VERSION" \
        --argjson staleAfterDays "$OFFLINE_PACK_EXPIRES_DAYS" \
        --argjson downloadTimeoutSeconds "$OFFLINE_PACK_TIMEOUT_SECONDS" \
        --argjson modules "$selected_json" \
        --slurpfile errors <(offline_pack_json_lines "${OFFLINE_PACK_ERRORS[@]}" | offline_pack_jq -R . | offline_pack_jq -s .) \
        --slurpfile warnings <(offline_pack_json_lines "${OFFLINE_PACK_WARNINGS[@]}" | offline_pack_jq -R . | offline_pack_jq -s .) \
        '{
          schema: $schema,
          status: $status,
          mode: $mode,
          pack: {
            schema: $packSchema,
            generatedAt: $generatedAt,
            expiresAt: $expiresAt,
            staleAfterDays: $staleAfterDays,
            targets: [{os: "ubuntu", version: $ubuntuVersion, architecture: $arch}],
            downloadTimeoutSeconds: $downloadTimeoutSeconds,
            modules: $modules
          },
          validation: {errors: $errors[0], warnings: $warnings[0]}
        }'
}

offline_pack_write_manifest() {
    local pack_root="$1"
    local generated_at="$2"
    local expires_at="$3"
    local version="unknown"
    local source_ref="unknown"
    local source_commit="unknown"
    local manifest_sha=""
    local checksums_sha=""
    local pack_mode="complete"

    [[ "$OFFLINE_PACK_BEST_EFFORT" == "true" && ${#OFFLINE_PACK_ERRORS[@]} -gt 0 ]] && pack_mode="diagnostic"
    if [[ -f "$OFFLINE_PACK_SOURCE_ROOT/VERSION" ]]; then
        version="$(< "$OFFLINE_PACK_SOURCE_ROOT/VERSION")"
        version="${version//[[:space:]]/}"
    fi
    source_ref="$(offline_pack_git -C "$OFFLINE_PACK_SOURCE_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'unknown')"
    source_commit="$(offline_pack_git -C "$OFFLINE_PACK_SOURCE_ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown')"
    manifest_sha="$(offline_pack_sha256 "$OFFLINE_PACK_MANIFEST_FILE")"
    checksums_sha="$(offline_pack_sha256 "$OFFLINE_PACK_CHECKSUMS_FILE")"

    offline_pack_jq -n \
        --arg schema "$OFFLINE_PACK_SCHEMA" \
        --argjson schemaVersion 1 \
        --arg generatedBy "acfs offline-pack build" \
        --arg generatedAt "$generated_at" \
        --arg expiresAt "$expires_at" \
        --argjson staleAfterDays "$OFFLINE_PACK_EXPIRES_DAYS" \
        --arg packMode "$pack_mode" \
        --arg acfsVersion "$version" \
        --arg sourceRef "$source_ref" \
        --arg sourceCommit "$source_commit" \
        --arg manifestSha "$manifest_sha" \
        --arg checksumsSha "$checksums_sha" \
        --arg arch "$OFFLINE_PACK_ARCH" \
        --arg ubuntuVersion "$OFFLINE_PACK_UBUNTU_VERSION" \
        --argjson modules "$OFFLINE_PACK_MODULES_JSON" \
        --argjson artifacts "$OFFLINE_PACK_ARTIFACTS_JSON" \
        --argjson failures "$OFFLINE_PACK_FAILURES_JSON" \
        '{
          schema: $schema,
          schemaVersion: $schemaVersion,
          generatedBy: $generatedBy,
          generatedAt: $generatedAt,
          expiresAt: $expiresAt,
          staleAfterDays: $staleAfterDays,
          packMode: $packMode,
          acfs: {
            version: $acfsVersion,
            sourceRef: $sourceRef,
            sourceCommit: $sourceCommit,
            manifestSha256: $manifestSha,
            checksumsYamlSha256: $checksumsSha
          },
          targets: [{os: "ubuntu", version: $ubuntuVersion, architecture: $arch}],
          modules: $modules,
          artifacts: $artifacts,
          failures: $failures,
          policy: {
            networkMode: "offline",
            verifiedInstallerPolicy: "must_match_checksums_yaml",
            partialPackPolicy: "refuse_unless_best_effort_diagnostic"
          }
        }' > "$pack_root/manifest.json"

    offline_pack_jq -n \
        --arg generatedAt "$generated_at" \
        --arg sourceRef "$source_ref" \
        --arg sourceCommit "$source_commit" \
        --arg arch "$OFFLINE_PACK_ARCH" \
        --arg ubuntuVersion "$OFFLINE_PACK_UBUNTU_VERSION" \
        '{generatedAt: $generatedAt, sourceRef: $sourceRef, sourceCommit: $sourceCommit, target: {os: "ubuntu", version: $ubuntuVersion, architecture: $arch}}' \
        > "$pack_root/provenance/builder-env.json"

    offline_pack_jq -n \
        --argjson artifacts "$OFFLINE_PACK_ARTIFACTS_JSON" \
        '{artifacts: $artifacts}' \
        > "$pack_root/provenance/source-index.json"
}

offline_pack_result_json() {
    local pack_root="$1"
    local generated_at="$2"
    local manifest_path=""
    local pack_mode="complete"

    [[ -n "$pack_root" ]] && manifest_path="$pack_root/manifest.json"
    [[ "$OFFLINE_PACK_BEST_EFFORT" == "true" && ${#OFFLINE_PACK_ERRORS[@]} -gt 0 ]] && pack_mode="diagnostic"

    offline_pack_jq -n \
        --arg schema "$OFFLINE_PACK_BUILD_SCHEMA" \
        --arg status "$(offline_pack_status)" \
        --arg generatedAt "$generated_at" \
        --arg outputDir "$OFFLINE_PACK_OUTPUT_DIR" \
        --arg packRoot "$pack_root" \
        --arg manifestPath "$manifest_path" \
        --arg packMode "$pack_mode" \
        --argjson modules "$OFFLINE_PACK_MODULES_JSON" \
        --argjson artifacts "$OFFLINE_PACK_ARTIFACTS_JSON" \
        --argjson failures "$OFFLINE_PACK_FAILURES_JSON" \
        --slurpfile errors <(offline_pack_json_lines "${OFFLINE_PACK_ERRORS[@]}" | offline_pack_jq -R . | offline_pack_jq -s .) \
        --slurpfile warnings <(offline_pack_json_lines "${OFFLINE_PACK_WARNINGS[@]}" | offline_pack_jq -R . | offline_pack_jq -s .) \
        '{
          schema: $schema,
          status: $status,
          generatedAt: $generatedAt,
          output: {directory: $outputDir, packRoot: $packRoot, manifestPath: $manifestPath, packMode: $packMode},
          pack: {modules: $modules, artifacts: $artifacts, failures: $failures},
          validation: {errors: $errors[0], warnings: $warnings[0]}
        }'
}

offline_pack_print_array() {
    local label="$1"
    shift
    local item=""

    if (( $# == 0 )); then
        return 0
    fi

    printf '%s\n' "$label"
    for item in "$@"; do
        printf '  - %s\n' "$item"
    done
}

offline_pack_emit_markdown() {
    local pack_root="$1"
    local status=""
    local module_id=""
    local tool=""
    local url=""

    status="$(offline_pack_status)"
    printf 'ACFS Offline Artifact Pack Build\n'
    printf 'Status: %s\n' "$status"
    printf 'Mode: %s\n' "$([[ "$OFFLINE_PACK_DRY_RUN" == "true" ]] && printf 'dry-run' || printf 'build')"
    printf 'Target: Ubuntu %s on %s\n' "$OFFLINE_PACK_UBUNTU_VERSION" "$OFFLINE_PACK_ARCH"
    if [[ -n "$pack_root" ]]; then
        printf 'Pack root: %s\n' "$pack_root"
    fi
    printf '\n'

    offline_pack_print_array "Errors:" "${OFFLINE_PACK_ERRORS[@]}"
    offline_pack_print_array "Warnings:" "${OFFLINE_PACK_WARNINGS[@]}"
    if (( ${#OFFLINE_PACK_ERRORS[@]} > 0 || ${#OFFLINE_PACK_WARNINGS[@]} > 0 )); then
        printf '\n'
    fi

    printf 'Modules:\n'
    if (( ${#OFFLINE_PACK_SELECTED_MODULES[@]} == 0 )); then
        printf '  - No modules selected.\n'
        return 0
    fi

    for module_id in "${OFFLINE_PACK_SELECTED_MODULES[@]}"; do
        tool="${OFFLINE_PACK_MODULE_TOOL[$module_id]:-}"
        url="${OFFLINE_PACK_INSTALLER_URL[$tool]:-}"
        printf '  - %s (%s) %s\n' "$module_id" "${tool:-no verified installer}" "${url:-no approved URL}"
    done
}

offline_pack_emit_result() {
    local pack_root="$1"
    local generated_at="$2"

    if [[ "$OFFLINE_PACK_FORMAT" == "json" ]]; then
        offline_pack_result_json "$pack_root" "$generated_at"
    else
        offline_pack_emit_markdown "$pack_root"
    fi
}

offline_pack_main() {
    local parse_status=0
    local generated_at=""
    local expires_at=""
    local output_dir=""
    local pack_root=""

    offline_pack_parse_args "$@" || {
        parse_status=$?
        if [[ "$parse_status" -eq 100 ]]; then
            return 0
        fi
        return "$parse_status"
    }

    offline_pack_require_jq
    generated_at="$(offline_pack_iso_now)"
    expires_at="$(offline_pack_iso_expires)"

    offline_pack_resolve_inputs || true
    if (( ${#OFFLINE_PACK_ERRORS[@]} == 0 )); then
        offline_pack_load_checksums "$OFFLINE_PACK_CHECKSUMS_FILE" || true
        offline_pack_load_manifest_modules "$OFFLINE_PACK_MANIFEST_FILE" || true
        offline_pack_select_modules
    fi

    if [[ "$OFFLINE_PACK_DRY_RUN" == "true" ]]; then
        if [[ "$OFFLINE_PACK_FORMAT" == "json" ]]; then
            offline_pack_plan_json "$generated_at" "$expires_at"
        else
            offline_pack_emit_markdown ""
        fi
        [[ "$(offline_pack_status)" != "fail" ]]
        return
    fi

    if (( ${#OFFLINE_PACK_ERRORS[@]} > 0 )); then
        offline_pack_emit_result "" "$generated_at"
        return 1
    fi

    output_dir="$(offline_pack_abs_dir "$OFFLINE_PACK_OUTPUT_DIR")"
    OFFLINE_PACK_OUTPUT_DIR="$output_dir"
    pack_root="$output_dir/acfs-offline-pack"

    if ! offline_pack_prepare_layout "$output_dir" "$pack_root"; then
        offline_pack_emit_result "$pack_root" "$generated_at"
        return 1
    fi

    if ! offline_pack_download_artifacts "$pack_root"; then
        offline_pack_emit_result "$pack_root" "$generated_at"
        return 1
    fi

    offline_pack_write_manifest "$pack_root" "$generated_at" "$expires_at"
    offline_pack_emit_result "$pack_root" "$generated_at"

    if [[ "$(offline_pack_status)" == "fail" ]]; then
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    offline_pack_main "$@"
fi
