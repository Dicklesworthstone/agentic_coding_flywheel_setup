// ============================================================
// AUTO-GENERATED FROM acfs.manifest.yaml - DO NOT EDIT DIRECTLY
// To regenerate: bun run --cwd packages/manifest generate
// ============================================================

export interface ManifestLessonLink {
  moduleId: string;
  lessonSlug: string;
  displayName: string;
}

export const manifestLessonLinks: ManifestLessonLink[] = [
  {
    moduleId: "stack.agent_settings_backup",
    lessonSlug: "asb",
    displayName: "Agent Settings Backup",
  },
  {
    moduleId: "stack.cross_agent_session_resumer",
    lessonSlug: "casr",
    displayName: "Cross-Agent Session Resumer",
  },
  {
    moduleId: "stack.doodlestein_self_releaser",
    lessonSlug: "dsr",
    displayName: "Doodlestein Self-Releaser",
  },
  {
    moduleId: "stack.eidetic_engine_cli",
    lessonSlug: "ee",
    displayName: "Eidetic Engine",
  },
  {
    moduleId: "stack.franken_markdown",
    lessonSlug: "fmd",
    displayName: "Franken Markdown",
  },
  {
    moduleId: "stack.frankensearch",
    lessonSlug: "fsfs",
    displayName: "FrankenSearch",
  },
  {
    moduleId: "stack.pcr",
    lessonSlug: "pcr",
    displayName: "Post-Compact Reminder",
  },
  {
    moduleId: "stack.pi_agent_rust",
    lessonSlug: "pi",
    displayName: "Pi Agent (Rust)",
  },
  {
    moduleId: "stack.power_failure_resumer",
    lessonSlug: "pfr",
    displayName: "Power Failure Resumer",
  },
  {
    moduleId: "stack.process_triage",
    lessonSlug: "pt",
    displayName: "Process Triage",
  },
  {
    moduleId: "stack.rch",
    lessonSlug: "rch",
    displayName: "Remote Compilation Helper",
  },
  {
    moduleId: "stack.storage_ballast_helper",
    lessonSlug: "sbh",
    displayName: "Storage Ballast Helper",
  },
];

/** Lookup lesson slug by module ID */
export const lessonSlugByModuleId: Record<string, string> = {
  "stack.agent_settings_backup": "asb",
  "stack.cross_agent_session_resumer": "casr",
  "stack.doodlestein_self_releaser": "dsr",
  "stack.eidetic_engine_cli": "ee",
  "stack.franken_markdown": "fmd",
  "stack.frankensearch": "fsfs",
  "stack.pcr": "pcr",
  "stack.pi_agent_rust": "pi",
  "stack.power_failure_resumer": "pfr",
  "stack.process_triage": "pt",
  "stack.rch": "rch",
  "stack.storage_ballast_helper": "sbh",
};
