/** Selection verification is generated from the same check IDs as MANIFEST_CHECKS. */
export interface SelectedDoctorModule {
  id: string;
  checks: ReadonlyArray<{ id: string; soft: boolean }>;
}

export function renderSelectedManifestChecks(modules: readonly SelectedDoctorModule[]): string {
  const owners: string[] = [];
  const softness: string[] = [];
  const counts: string[] = [];
  const moduleIds = new Set<string>();
  const checkIds = new Set<string>();
  for (const module of modules) {
    if (!/^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$/.test(module.id) || moduleIds.has(module.id)) {
      throw new Error("Invalid or duplicate doctor module identity");
    }
    moduleIds.add(module.id);
    counts.push(`  ['${module.id}']='${module.checks.length}'`);
    for (const check of module.checks) {
      if (!/^[a-z][a-z0-9_]*(?:\.[a-z0-9_]+)*$/.test(check.id) || checkIds.has(check.id)
          || typeof check.soft !== "boolean") {
        throw new Error("Invalid or duplicate doctor check identity");
      }
      checkIds.add(check.id);
      owners.push(`  ['${check.id}']='${module.id}'`);
      softness.push(`  ['${check.id}']='${check.soft ? 1 : 0}'`);
    }
  }
  return [
    "# Exact ownership and expected coverage, authored only in acfs.manifest.yaml.",
    "declare -gA ACFS_DOCTOR_CHECK_MODULE=(", ...owners, ")",
    "declare -gA ACFS_DOCTOR_CHECK_SOFT=(", ...softness, ")",
    "declare -gA ACFS_DOCTOR_MODULE_CHECK_COUNT=(", ...counts, ")",
    SELECTED_RUNNER,
  ].join("\n");
}

const SELECTED_RUNNER = [
  "# Verify a resolved selection, never an implicit default/full install.",
  "# --require-module promotes an optional MODULE, not a deliberately soft check.",
  "# All records and coverage are validated before the first command is executed.",
  "run_selected_manifest_checks() {",
  "    local -A required=() selected=() records=() counts=() seen=()",
  "    local module='' id='' row='' desc='' cmd='' policy='' run_as='' extra=''",
  "    local -a order=()",
  "    local separator=false",
  "    while [[ $# -gt 0 ]]; do",
  "        case \"$1\" in",
  "            --require-module)",
  "                [[ $# -ge 2 ]] || { echo 'Selected checks: --require-module needs an ID' >&2; return 2; }",
  "                module=\"$2\"",
  "                [[ \"$module\" =~ ^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)+$ ]] || return 2",
  "                [[ -z \"${required[$module]+present}\" ]] || return 2",
  "                required[\"$module\"]=1",
  "                shift 2",
  "                ;;",
  "            --) shift; separator=true; break ;;",
  "            *) echo 'Selected checks: explicit -- separator required' >&2; return 2 ;;",
  "        esac",
  "    done",
  "    if [[ \"$separator\" != true || $# -eq 0 || $# -gt 1024 ]]; then",
  "        echo 'Selected checks: select one or more exact module IDs' >&2",
  "        return 2",
  "    fi",
  "    for module in \"$@\"; do",
  "        if [[ ! \"$module\" =~ ^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)+$ ]] \\",
  "            || [[ -z \"${ACFS_DOCTOR_MODULE_CHECK_COUNT[$module]+present}\" ]] \\",
  "            || [[ -n \"${selected[$module]+present}\" ]]; then",
  "            echo 'Selected checks: unknown, duplicate, or invalid module' >&2",
  "            return 2",
  "        fi",
  "        selected[\"$module\"]=1",
  "        counts[\"$module\"]=0",
  "        order+=(\"$module\")",
  "    done",
  "    for module in \"${!required[@]}\"; do",
  "        [[ -n \"${selected[$module]+present}\" ]] || {",
  "            echo 'Selected checks: required module is not selected' >&2; return 2;",
  "        }",
  "    done",
  "    if ! declare -F run_manifest_check_command >/dev/null \\",
  "        || ! acfs_generated_system_binary_path timeout >/dev/null; then",
  "        echo 'Selected checks: bounded execution machinery is unavailable' >&2",
  "        return 2",
  "    fi",
  "    for row in \"${MANIFEST_CHECKS[@]}\"; do",
  "        id=''; desc=''; cmd=''; policy=''; run_as=''; extra=''",
  "        IFS=$'\\t' read -r id desc cmd policy run_as extra <<< \"$row\"",
  "        if [[ ! \"$id\" =~ ^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)*$ ]] \\",
  "            || [[ -z \"$desc\" || -z \"$cmd\" || -n \"$extra\" ]] \\",
  "            || [[ \"$policy\" != required && \"$policy\" != optional ]] \\",
  "            || [[ \"$run_as\" != root && \"$run_as\" != target_user && \"$run_as\" != current ]] \\",
  "            || [[ -z \"${ACFS_DOCTOR_CHECK_MODULE[$id]+present}\" ]] \\",
  "            || [[ -n \"${seen[$id]+present}\" ]]; then",
  "            echo 'Selected checks: malformed or duplicate manifest check record' >&2",
  "            return 2",
  "        fi",
  "        seen[\"$id\"]=1",
  "        module=\"${ACFS_DOCTOR_CHECK_MODULE[$id]}\"",
  "        if [[ -n \"${selected[$module]+present}\" ]]; then",
  "            records[\"$id\"]=\"$row\"",
  "            counts[\"$module\"]=$(( ${counts[$module]} + 1 ))",
  "        fi",
  "    done",
  "    for module in \"${order[@]}\"; do",
  "        if [[ \"${counts[$module]}\" != \"${ACFS_DOCTOR_MODULE_CHECK_COUNT[$module]}\" ]] \\",
  "            || [[ \"${counts[$module]}\" == 0 ]]; then",
  "            printf 'Selected checks: incomplete verification coverage for %s\\n' \"$module\" >&2",
  "            return 2",
  "        fi",
  "        # Do not interpret an absent distro identity as a successful family skip.",
  "        if [[ -n \"${ACFS_MODULE_FAMILIES[$module]:-}\" && -z \"${ACFS_DISTRO_FAMILY:-}\" ]]; then",
  "            echo 'Selected checks: distro family is required by this selection' >&2",
  "            return 2",
  "        fi",
  "    done",
  "    local passed=0 failed=0 warnings=0 skipped=0 rc=0 soft=false family='' applies=false",
  "    for row in \"${MANIFEST_CHECKS[@]}\"; do",
  "        IFS=$'\\t' read -r id desc cmd policy run_as <<< \"$row\"",
  "        [[ -n \"${records[$id]+present}\" ]] || continue",
  "        module=\"${ACFS_DOCTOR_CHECK_MODULE[$id]}\"",
  "        if [[ -n \"${ACFS_MODULE_FAMILIES[$module]:-}\" ]]; then",
  "            applies=false",
  "            for family in ${ACFS_MODULE_FAMILIES[$module]}; do",
  "                [[ \"$family\" != \"$ACFS_DISTRO_FAMILY\" ]] || applies=true",
  "            done",
  "            if [[ \"$applies\" != true ]]; then",
  "                printf '[skip] %s (not applicable on %s)\\n' \"$id\" \"$ACFS_DISTRO_FAMILY\" >&2",
  "                ((skipped += 1))",
  "                continue",
  "            fi",
  "        fi",
  "        soft=false",
  "        if [[ \"${ACFS_DOCTOR_CHECK_SOFT[$id]}\" == 1 ]] \\",
  "            || { [[ \"$policy\" == optional ]] && [[ -z \"${required[$module]+present}\" ]]; }; then",
  "            soft=true",
  "        fi",
  "        cmd=\"$(printf '%b' \"$cmd\")\"",
  "        rc=0",
  "        run_manifest_check_command \"$run_as\" \"$cmd\" 30 </dev/null >/dev/null 2>&1 || rc=$?",
  "        if [[ $rc -eq 0 ]]; then",
  "            printf '[ok] %s\\n' \"$id\" >&2",
  "            ((passed += 1))",
  "        elif [[ \"$soft\" == true ]]; then",
  "            printf '[warn] %s (verification exit %s)\\n' \"$id\" \"$rc\" >&2",
  "            ((warnings += 1))",
  "        else",
  "            printf '[fail] %s (verification exit %s)\\n' \"$id\" \"$rc\" >&2",
  "            ((failed += 1))",
  "        fi",
  "    done",
  "    printf 'Selected checks: %s passed, %s failed, %s warnings, %s not applicable\\n' \\",
  "        \"$passed\" \"$failed\" \"$warnings\" \"$skipped\" >&2",
  "    [[ $failed -eq 0 ]]",
  "}",
].join("\n");
