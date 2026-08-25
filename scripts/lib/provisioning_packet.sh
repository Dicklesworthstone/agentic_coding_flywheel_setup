#!/usr/bin/env bash
# ============================================================
# ACFS Provider Provisioning Packet - read-only validator/renderer
#
# Validates acfs.provider-provisioning-packet.v1 JSON artifacts and prints
# support-safe human or JSON output. This command never contacts provider APIs.
# ============================================================

set -euo pipefail

PROVISIONING_PACKET_CHECK_SCHEMA="acfs.provider-provisioning-packet-check.v1"
PROVISIONING_PACKET_SCHEMA="acfs.provider-provisioning-packet.v1"
PROVISIONING_PACKET_FORMAT="markdown"
PROVISIONING_PACKET_FILE=""
PROVISIONING_PACKET_ERRORS=()
PROVISIONING_PACKET_WARNINGS=()

provisioning_packet_usage() {
    cat <<'EOF'
Usage: acfs provisioning-packet --file FILE [OPTIONS]

Options:
  --file FILE       Provider provisioning packet JSON file
  --packet FILE     Alias for --file
  --json            Emit machine-readable validation JSON
  --markdown        Emit human-readable validation output (default)
  --help, -h        Show this help

The command is read-only. It validates packet structure, redaction boundaries,
provider readiness status, OS assumptions, username assumptions, SSH key safety,
and install command coherence without contacting a provider API.
EOF
}

provisioning_packet_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                PROVISIONING_PACKET_FORMAT="json"
                shift
                ;;
            --markdown)
                PROVISIONING_PACKET_FORMAT="markdown"
                shift
                ;;
            --file|--packet)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: $1 requires a packet JSON path" >&2
                    return 2
                fi
                PROVISIONING_PACKET_FILE="$2"
                shift 2
                ;;
            --help|-h)
                provisioning_packet_usage
                return 100
                ;;
            *)
                echo "Error: unknown option: $1" >&2
                echo "Run 'acfs provisioning-packet --help' for usage." >&2
                return 2
                ;;
        esac
    done

    if [[ -z "$PROVISIONING_PACKET_FILE" ]]; then
        echo "Error: --file is required" >&2
        return 2
    fi
    if [[ ! -f "$PROVISIONING_PACKET_FILE" ]]; then
        echo "Error: packet file not found: $PROVISIONING_PACKET_FILE" >&2
        return 2
    fi
}

provisioning_packet_require_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: jq is required for provisioning packet validation" >&2
        return 2
    fi
}

provisioning_packet_add_error() {
    PROVISIONING_PACKET_ERRORS+=("$1")
}

provisioning_packet_add_warning() {
    PROVISIONING_PACKET_WARNINGS+=("$1")
}

provisioning_packet_scalar() {
    local path_value="$1"
    jq -r --arg path "$path_value" 'getpath($path | split(".")) // ""' "$PROVISIONING_PACKET_FILE"
}

provisioning_packet_bool_is() {
    local path_value="$1"
    local expected="$2"
    jq -e --arg path "$path_value" --argjson expected "$expected" \
        'getpath($path | split(".")) == $expected' "$PROVISIONING_PACKET_FILE" >/dev/null
}

provisioning_packet_has_path() {
    local path_value="$1"
    jq -e --arg path "$path_value" 'getpath($path | split(".")) != null' "$PROVISIONING_PACKET_FILE" >/dev/null
}

provisioning_packet_validate_required_fields() {
    local required_paths=(
        "schema"
        "schemaVersion"
        "stage"
        "privacy.supportBundleSafe"
        "privacy.rawProviderCredentialsIncluded"
        "privacy.rawTargetHostIncluded"
        "privacy.rawPrivateKeyIncluded"
        "privacy.rawCloudInitIncludedInSupportBundle"
        "provenance.sourceRef"
        "provider.id"
        "provider.name"
        "provider.automationLevel"
        "region.id"
        "region.readinessStatus"
        "size.planName"
        "osImage.distribution"
        "osImage.version"
        "osImage.readinessStatus"
        "access.username"
        "access.sshPrivateKeyIncluded"
        "access.sshPrivateKeyPathIncluded"
        "cloudInit.mode"
        "install.mode"
        "install.sourceRef"
        "install.command"
        "install.commandRunLocation"
        "compatibility.workloadId"
        "compatibility.targetAgents"
        "compatibility.readinessStatus"
        "verificationCommands"
        "expectedArtifacts"
    )
    local path_value=""

    for path_value in "${required_paths[@]}"; do
        if ! provisioning_packet_has_path "$path_value"; then
            provisioning_packet_add_error "Missing required field: $path_value"
        fi
    done
}

provisioning_packet_validate_enums() {
    local schema=""
    local schema_version=""
    local stage=""
    local provider_level=""
    local readiness_status=""
    local os_status=""
    local os_distribution=""

    schema="$(provisioning_packet_scalar "schema")"
    schema_version="$(provisioning_packet_scalar "schemaVersion")"
    stage="$(provisioning_packet_scalar "stage")"
    provider_level="$(provisioning_packet_scalar "provider.automationLevel")"
    readiness_status="$(provisioning_packet_scalar "compatibility.readinessStatus")"
    os_status="$(provisioning_packet_scalar "osImage.readinessStatus")"
    os_distribution="$(provisioning_packet_scalar "osImage.distribution")"

    [[ "$schema" == "$PROVISIONING_PACKET_SCHEMA" ]] || \
        provisioning_packet_add_error "Unsupported or missing packet schema."
    [[ "$schema_version" == "1" ]] || \
        provisioning_packet_add_error "Unsupported or missing packet schemaVersion."

    case "$stage" in
        draft|ready_for_manual_provider_checkout|ready_for_api_provisioning|provider_server_created|installer_ready|verified|blocked) ;;
        *) provisioning_packet_add_error "Unsupported or missing packet stage." ;;
    esac

    case "$provider_level" in
        manual|cloud_init_only|api_supported) ;;
        *) provisioning_packet_add_error "Unsupported or missing provider automationLevel." ;;
    esac

    case "$readiness_status" in
        supported|borderline) ;;
        unknown) provisioning_packet_add_warning "Provider readiness is unknown; verify provider, plan, OS, region, and SSH access manually." ;;
        unsupported) provisioning_packet_add_error "Provider readiness is unsupported; do not provision until packet choices are fixed." ;;
        *) provisioning_packet_add_error "Unsupported or missing compatibility readinessStatus." ;;
    esac

    case "$os_status" in
        supported|borderline|unknown) ;;
        unsupported) provisioning_packet_add_error "Ubuntu image readiness is unsupported." ;;
        *) provisioning_packet_add_error "Unsupported or missing OS readinessStatus." ;;
    esac

    [[ "$os_distribution" == "ubuntu" ]] || \
        provisioning_packet_add_error "osImage.distribution must be ubuntu."
}

provisioning_packet_validate_redaction_flags() {
    local false_paths=(
        "privacy.rawProviderCredentialsIncluded"
        "privacy.rawTargetHostIncluded"
        "privacy.rawPrivateKeyIncluded"
        "privacy.rawPrivateKeyPathIncluded"
        "privacy.rawCloudInitIncludedInSupportBundle"
        "access.sshPrivateKeyIncluded"
        "access.sshPrivateKeyPathIncluded"
    )
    local path_value=""

    provisioning_packet_bool_is "privacy.supportBundleSafe" true || \
        provisioning_packet_add_error "privacy.supportBundleSafe must be true."

    for path_value in "${false_paths[@]}"; do
        provisioning_packet_bool_is "$path_value" false || \
            provisioning_packet_add_error "$path_value must be false."
    done
}

provisioning_packet_validate_username() {
    local username=""
    username="$(provisioning_packet_scalar "access.username")"

    if [[ ${#username} -gt 32 || ! "$username" =~ ^[a-z_][a-z0-9._-]*$ || "$username" == "root" ]]; then
        provisioning_packet_add_error "access.username is not a valid Linux username or is root."
    fi
}

provisioning_packet_validate_shapes() {
    if ! jq -e '
        (.schemaVersion | type == "number" and floor == .)
        and (.privacy | type == "object")
        and (.provider | type == "object")
        and (.provider.manualStepsRemaining | type == "array" and all(.[]; type == "string"))
        and (.region | type == "object")
        and (.size | type == "object")
        and (.osImage | type == "object")
        and (.osImage.distribution | type == "string")
        and (.osImage.version | type == "string" and test("^[0-9]{2}\\.[0-9]{2}$"))
        and (.osImage.readinessStatus | type == "string")
        and (.access | type == "object")
        and (.access.username | type == "string")
        and (.cloudInit | type == "object")
        and (.install | type == "object")
        and (.install.mode | type == "string")
        and (.install.sourceRef | type == "string")
        and (.install.command | type == "string")
        and (.install.commandRunLocation | type == "string")
        and (.compatibility | type == "object")
        and (.compatibility.targetAgents | type == "number" and floor == . and . >= 1)
        and (.verificationCommands | type == "array" and all(.[];
          type == "object"
          and (.id | type == "string")
          and (.label | type == "string")
          and (.command | type == "string")
          and (.runLocation | type == "string")
          and (.expectedStatus | type == "string")
          and (.supportBundleSafe | type == "boolean")
        ))
        and (.expectedArtifacts | type == "array" and all(.[];
          type == "object"
          and (.id | type == "string")
          and (.pathPattern | type == "string")
          and (.producedBy | type == "string")
          and (.supportBundleSafe | type == "boolean")
          and (.redactionRequired | type == "boolean")
        ))
        and (
          (.install.moduleSelection // {}) as $selection
          | ($selection | type == "object")
          and (($selection.profile // "") | type == "string" and test("^[a-z0-9][a-z0-9._-]{0,79}$") or . == "")
          and (($selection.onlyModules // []) | type == "array" and all(.[]; type == "string" and test("^[a-z0-9][a-z0-9._-]{0,127}$")))
          and (($selection.onlyPhases // []) | type == "array" and all(.[]; type == "string" and test("^[a-z0-9][a-z0-9._-]{0,127}$")))
          and (($selection.skipModules // []) | type == "array" and all(.[]; type == "string" and test("^[a-z0-9][a-z0-9._-]{0,127}$")))
          and (($selection.skipTags // []) | type == "array" and length == 0)
          and (($selection.skipCategories // []) | type == "array" and length == 0)
          and (($selection.noDeps // false) | type == "boolean")
        )
    ' "$PROVISIONING_PACKET_FILE" >/dev/null 2>&1; then
        provisioning_packet_add_error "Packet fields do not match the v1 structural contract."
    fi
}

provisioning_packet_validate_install_command() {
    local command_text=""
    local install_mode=""
    local command_location=""
    local source_ref=""
    local username=""

    command_text="$(provisioning_packet_scalar "install.command")"
    install_mode="$(provisioning_packet_scalar "install.mode")"
    command_location="$(provisioning_packet_scalar "install.commandRunLocation")"
    source_ref="$(provisioning_packet_scalar "install.sourceRef")"
    username="$(provisioning_packet_scalar "access.username")"

    [[ -n "$command_text" ]] || {
        provisioning_packet_add_error "install.command is empty."
        return
    }

    case "$install_mode" in
        vibe|safe) ;;
        *) provisioning_packet_add_error "install.mode must be vibe or safe." ;;
    esac

    case "$command_location" in
        vps-root-shell|cloud-init|provider-api) ;;
        *) provisioning_packet_add_error "Unsupported or missing install.commandRunLocation." ;;
    esac

    if [[ ! "$source_ref" =~ ^[A-Za-z0-9_][A-Za-z0-9._/-]{0,119}$ ]] \
        || [[ "$source_ref" == *".."* \
            || "$source_ref" == *"//"* \
            || "$source_ref" == *"/."* \
            || "$source_ref" == *.lock \
            || "$source_ref" == *. \
            || "$source_ref" == */ ]]; then
        provisioning_packet_add_error "install.sourceRef is not a safe Git ref."
        return
    fi

    if [[ "$(provisioning_packet_scalar "provenance.sourceRef")" != "$source_ref" ]]; then
        provisioning_packet_add_error "provenance.sourceRef must match install.sourceRef."
    fi

    if [[ "$command_text" =~ rm[[:space:]]+-rf|git[[:space:]]+reset|git[[:space:]]+clean ]] \
        || [[ "$command_text" =~ (^|[[:space:]])(npm|yarn|pnpm)($|[[:space:]]) ]]; then
        provisioning_packet_add_error "install.command contains a forbidden destructive or wrong-package-manager command."
    fi

    [[ "$command_text" == *"--mode ${install_mode}"* ]] || \
        provisioning_packet_add_error "install.command does not use the declared install.mode."

    if [[ "$source_ref" == "main" ]]; then
        [[ "$command_text" == *"/main/install.sh"* ]] || \
            provisioning_packet_add_error "install.command does not fetch the declared main sourceRef."
    else
        [[ "$command_text" == *"/${source_ref}/install.sh"* ]] || \
            provisioning_packet_add_error "install.command does not fetch the declared sourceRef."
        [[ "$command_text" == *"--ref \"${source_ref}\""* ]] || \
            provisioning_packet_add_error "install.command is missing the declared --ref."
    fi

    if [[ "$username" != "ubuntu" ]]; then
        [[ "$command_text" == *"TARGET_USER=\"${username}\""* ]] || \
            provisioning_packet_add_error "install.command does not set TARGET_USER for access.username."
    fi

    while IFS=$'\t' read -r selector_kind selector_value; do
        [[ -n "$selector_kind" && -n "$selector_value" ]] || continue
        case "$selector_kind" in
            profile)
                if [[ "$selector_value" != "$install_mode" && "$selector_value" != "full" ]]; then
                    [[ "$command_text" == *"--profile \"${selector_value}\""* ]] || \
                        provisioning_packet_add_error "install.command is missing a declared profile selector."
                fi
                ;;
            onlyModules)
                [[ "$command_text" == *"--only \"${selector_value}\""* ]] || \
                    provisioning_packet_add_error "install.command is missing declared module selector."
                ;;
            onlyPhases)
                [[ "$command_text" == *"--only-phase \"${selector_value}\""* ]] || \
                    provisioning_packet_add_error "install.command is missing declared phase selector."
                ;;
            skipModules)
                [[ "$command_text" == *"--skip \"${selector_value}\""* ]] || \
                    provisioning_packet_add_error "install.command is missing declared skip selector."
                ;;
        esac
    done < <(jq -r '
      (.install.moduleSelection // {}) as $selection
      | ([if ($selection.profile // "") != "" then ["profile", $selection.profile] else empty end]
        + [($selection.onlyModules // [])[] | ["onlyModules", .]]
        + [($selection.onlyPhases // [])[] | ["onlyPhases", .]]
        + [($selection.skipModules // [])[] | ["skipModules", .]])[]?
      | @tsv
    ' "$PROVISIONING_PACKET_FILE")

    if provisioning_packet_bool_is "install.moduleSelection.noDeps" true; then
        [[ "$command_text" == *"--no-deps"* ]] || \
            provisioning_packet_add_error "install.command is missing declared --no-deps selector."
    fi
}

provisioning_packet_scan_secret_values() {
    local secret_pattern='(BEGIN (OPENSSH|RSA|DSA|EC) PRIVATE KEY|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9]{20,})'
    local ipv4_pattern='(^|[^0-9])([0-9]{1,3}\.){3}[0-9]{1,3}([^0-9]|$)'
    local path_value=""
    local value=""
    local lower_path=""
    local lower_value=""

    while IFS=$'\t' read -r path_value value; do
        lower_path="${path_value,,}"
        lower_value="${value,,}"

        case "$lower_path" in
            privacy.forbiddenfieldnames.*|privacy.redactedfieldpaths.*)
                continue
                ;;
            targethost.*|provider.accountid|provider.orderid|provider.projectid|provider.dashboardsession|access.sshprivatekey|access.sshprivatekeypath|access.providertoken|cloudinit.rawuserdata|cloudinit.rawrenderedtemplate|install.environment*|provenance.operatorlocalpath)
                if [[ -n "$value" && "$lower_value" != "false" && "$lower_value" != "null" ]]; then
                    provisioning_packet_add_error "Forbidden support-unsafe field has a value at $path_value."
                fi
                ;;
        esac

        if [[ "$value" =~ $secret_pattern ]]; then
            provisioning_packet_add_error "Secret-looking value refused at $path_value."
        fi

        if [[ "$value" =~ $ipv4_pattern ]]; then
            provisioning_packet_add_error "Raw IPv4-looking value refused at $path_value."
        fi

        if [[ "$lower_path" =~ (^|\.)(password|token|secret|authorization|credential|provider_api_key|api_key|apitoken|dashboardcookie|hostname|ip|sshprivatekey|privatekey|private_key|sshkeypath)$ ]] && \
           [[ -n "$value" && "$lower_value" != "false" && "$lower_value" != "null" ]]; then
            provisioning_packet_add_error "Forbidden sensitive field has a value at $path_value."
        fi
    done < <(
        jq -r '
          paths(scalars) as $path
          | [($path | map(tostring) | join(".")), (getpath($path) | tostring)]
          | @tsv
        ' "$PROVISIONING_PACKET_FILE"
    )
}

provisioning_packet_validate_packet() {
    provisioning_packet_validate_required_fields
    provisioning_packet_validate_shapes
    provisioning_packet_validate_enums
    provisioning_packet_validate_redaction_flags
    provisioning_packet_validate_username
    provisioning_packet_validate_install_command
    provisioning_packet_scan_secret_values
}

provisioning_packet_status() {
    if (( ${#PROVISIONING_PACKET_ERRORS[@]} > 0 )); then
        printf 'fail\n'
    elif (( ${#PROVISIONING_PACKET_WARNINGS[@]} > 0 )); then
        printf 'warn\n'
    else
        printf 'pass\n'
    fi
}

provisioning_packet_emit_error_json() {
    local message="$1"
    local status="$2"
    jq -n \
        --arg schema "$PROVISIONING_PACKET_CHECK_SCHEMA" \
        --arg status "$status" \
        --arg message "$message" \
        '{schema: $schema, status: $status, validation: {errors: [$message], warnings: []}}'
}

provisioning_packet_emit_json() {
    local status=""
    local manual_steps=""
    local verification_commands=""
    local target_agents=""

    status="$(provisioning_packet_status)"
    if [[ "$status" == "fail" ]]; then
        jq -n \
            --arg schema "$PROVISIONING_PACKET_CHECK_SCHEMA" \
            --arg status "$status" \
            --slurpfile errors <(provisioning_packet_json_string_lines "${PROVISIONING_PACKET_ERRORS[@]}" | jq -R . | jq -s .) \
            --slurpfile warnings <(provisioning_packet_json_string_lines "${PROVISIONING_PACKET_WARNINGS[@]}" | jq -R . | jq -s .) \
            '{schema: $schema, status: $status, validation: {errors: $errors[0], warnings: $warnings[0]}}'
        return
    fi

    manual_steps="$(jq -c '.provider.manualStepsRemaining // []' "$PROVISIONING_PACKET_FILE")"
    verification_commands="$(jq -c '[.verificationCommands[]? | {
      id: .id,
      label: .label,
      runLocation: .runLocation,
      expectedStatus: .expectedStatus,
      supportBundleSafe: .supportBundleSafe
    }]' "$PROVISIONING_PACKET_FILE")"
    target_agents="$(provisioning_packet_scalar "compatibility.targetAgents")"
    if [[ ! "$target_agents" =~ ^[0-9]+$ ]]; then
        target_agents=0
    fi

    jq -n \
        --arg schema "$PROVISIONING_PACKET_CHECK_SCHEMA" \
        --arg status "$status" \
        --arg packet_schema "$(provisioning_packet_scalar "schema")" \
        --arg stage "$(provisioning_packet_scalar "stage")" \
        --arg provider_id "$(provisioning_packet_scalar "provider.id")" \
        --arg provider_name "$(provisioning_packet_scalar "provider.name")" \
        --arg provider_automation "$(provisioning_packet_scalar "provider.automationLevel")" \
        --arg region_id "$(provisioning_packet_scalar "region.id")" \
        --arg os_version "$(provisioning_packet_scalar "osImage.version")" \
        --arg os_status "$(provisioning_packet_scalar "osImage.readinessStatus")" \
        --arg source_ref "$(provisioning_packet_scalar "install.sourceRef")" \
        --arg command_location "$(provisioning_packet_scalar "install.commandRunLocation")" \
        --arg readiness_status "$(provisioning_packet_scalar "compatibility.readinessStatus")" \
        --argjson target_agents "$target_agents" \
        --argjson manual_steps "$manual_steps" \
        --argjson verification_commands "$verification_commands" \
        --slurpfile errors <(provisioning_packet_json_string_lines "${PROVISIONING_PACKET_ERRORS[@]}" | jq -R . | jq -s .) \
        --slurpfile warnings <(provisioning_packet_json_string_lines "${PROVISIONING_PACKET_WARNINGS[@]}" | jq -R . | jq -s .) \
        '{
          schema: $schema,
          status: $status,
          packet: {
            schema: $packet_schema,
            stage: $stage,
            provider: {id: $provider_id, name: $provider_name, automationLevel: $provider_automation},
            region: {id: $region_id},
            osImage: {distribution: "ubuntu", version: $os_version, readinessStatus: $os_status},
            install: {sourceRef: $source_ref, commandRunLocation: $command_location},
            compatibility: {targetAgents: $target_agents, readinessStatus: $readiness_status}
          },
          validation: {
            errors: $errors[0],
            warnings: $warnings[0],
            manualSteps: $manual_steps,
            verificationCommands: $verification_commands
          }
        }'
}

provisioning_packet_json_string_lines() {
    if (( $# == 0 )); then
        return 0
    fi
    printf '%s\n' "$@"
}

provisioning_packet_print_array() {
    local label="$1"
    shift
    local items=("$@")
    local item=""

    if (( ${#items[@]} == 0 )); then
        return 0
    fi

    printf '%s\n' "$label"
    for item in "${items[@]}"; do
        printf '  - %s\n' "$item"
    done
}

provisioning_packet_emit_markdown() {
    local status=""
    local index=1
    local step=""
    local command_id=""
    local command_label=""
    local command_location=""

    status="$(provisioning_packet_status)"
    printf 'ACFS Provider Provisioning Packet Check\n'
    printf 'Status: %s\n' "$status"
    if [[ "$status" == "fail" ]]; then
        provisioning_packet_print_array "Errors:" "${PROVISIONING_PACKET_ERRORS[@]}"
        provisioning_packet_print_array "Warnings:" "${PROVISIONING_PACKET_WARNINGS[@]}"
        return
    fi

    printf 'Schema: %s\n' "$(provisioning_packet_scalar "schema")"
    printf 'Stage: %s\n' "$(provisioning_packet_scalar "stage")"
    printf 'Provider: %s (%s)\n' \
        "$(provisioning_packet_scalar "provider.name")" \
        "$(provisioning_packet_scalar "provider.automationLevel")"
    printf 'Region: %s (%s)\n' \
        "$(provisioning_packet_scalar "region.id")" \
        "$(provisioning_packet_scalar "region.readinessStatus")"
    printf 'OS: Ubuntu %s (%s)\n' \
        "$(provisioning_packet_scalar "osImage.version")" \
        "$(provisioning_packet_scalar "osImage.readinessStatus")"
    printf 'Target agents: %s\n' "$(provisioning_packet_scalar "compatibility.targetAgents")"
    printf 'Readiness: %s\n' "$(provisioning_packet_scalar "compatibility.readinessStatus")"
    printf 'Install source ref: %s\n' "$(provisioning_packet_scalar "install.sourceRef")"
    printf 'Install run location: %s\n' "$(provisioning_packet_scalar "install.commandRunLocation")"
    printf '\n'

    provisioning_packet_print_array "Errors:" "${PROVISIONING_PACKET_ERRORS[@]}"
    provisioning_packet_print_array "Warnings:" "${PROVISIONING_PACKET_WARNINGS[@]}"
    if (( ${#PROVISIONING_PACKET_ERRORS[@]} > 0 || ${#PROVISIONING_PACKET_WARNINGS[@]} > 0 )); then
        printf '\n'
    fi

    printf 'Manual provider steps:\n'
    while IFS= read -r step; do
        [[ -n "$step" ]] || continue
        printf '  %d. %s\n' "$index" "$step"
        index=$((index + 1))
    done < <(jq -r '.provider.manualStepsRemaining[]? // empty' "$PROVISIONING_PACKET_FILE")
    if (( index == 1 )); then
        printf '  - No manual steps listed.\n'
    fi

    printf '\nVerification checklist:\n'
    while IFS=$'\t' read -r command_id command_label command_location; do
        [[ -n "$command_id" ]] || continue
        printf '  - [%s] %s (run on %s)\n' "$command_id" "$command_label" "$command_location"
    done < <(
        jq -r '.verificationCommands[]? | [.id, .label, .runLocation] | @tsv' "$PROVISIONING_PACKET_FILE"
    )
}

provisioning_packet_main() {
    local parse_status=0

    provisioning_packet_parse_args "$@" || {
        parse_status=$?
        if [[ "$parse_status" -eq 100 ]]; then
            return 0
        fi
        return "$parse_status"
    }

    provisioning_packet_require_jq

    if ! jq empty "$PROVISIONING_PACKET_FILE" >/dev/null 2>&1; then
        if [[ "$PROVISIONING_PACKET_FORMAT" == "json" ]]; then
            provisioning_packet_emit_error_json "Malformed JSON packet." "fail"
        else
            echo "ACFS Provider Provisioning Packet Check"
            echo "Status: fail"
            echo "Errors:"
            echo "  - Malformed JSON packet."
        fi
        return 2
    fi

    provisioning_packet_validate_packet
    if [[ "$PROVISIONING_PACKET_FORMAT" == "json" ]]; then
        provisioning_packet_emit_json
    else
        provisioning_packet_emit_markdown
    fi

    if (( ${#PROVISIONING_PACKET_ERRORS[@]} > 0 )); then
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    provisioning_packet_main "$@"
fi
