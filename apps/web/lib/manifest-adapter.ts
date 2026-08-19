/**
 * Manifest Adapter
 *
 * Bridges generated manifest data (from acfs.manifest.yaml) with the
 * hand-maintained UI data files (flywheel.ts, tldr-content.ts, commands.ts).
 *
 * The manifest is the source of truth for basic metadata (names, taglines,
 * tech stacks, features, use cases, stars, hrefs). Rich UI-specific data
 * (deep descriptions, synergies, Tailwind gradient colors, workflow scenarios)
 * stays hand-maintained.
 */

import { manifestTools } from './generated/manifest-tools';
import { manifestTldrTools } from './generated/manifest-tldr';
import { manifestCommands } from './generated/manifest-commands';
import type { ManifestWebTool } from './generated/manifest-tools';
import type { ManifestTldrTool } from './generated/manifest-tldr';
import type { ManifestCommand } from './generated/manifest-commands';

/**
 * Maps short IDs used in hand-maintained UI files to canonical manifest module IDs.
 *
 * Hand-maintained files use short, memorable IDs ("mail", "bv", "br").
 * The manifest uses dotted module IDs ("stack.mcp_agent_mail", "stack.beads_viewer").
 */
export const shortIdToModuleId: Record<string, string> = {
  mail: 'stack.mcp_agent_mail',
  bv: 'stack.beads_viewer',
  br: 'stack.beads_rust',
  ntm: 'stack.ntm',
  cm: 'stack.cm',
  cass: 'stack.cass',
  slb: 'stack.slb',
  dcg: 'stack.dcg',
  ru: 'stack.ru',
  apr: 'stack.automated_plan_reviser',
  ms: 'stack.meta_skill',
  ubs: 'stack.ultimate_bug_scanner',
  pt: 'stack.process_triage',
  jfp: 'stack.jeffreysprompts',
  brenner: 'stack.brenner_bot',
  rch: 'stack.rch',
  wa: 'stack.wezterm_automata',
  srps: 'stack.srps',
  caam: 'stack.caam',
  xf: 'utils.xf',
  giil: 'utils.giil',
  csctf: 'utils.csctf',
  s2p: 'utils.s2p',
  tru: 'utils.toon_rust',
  rano: 'utils.rano',
  mdwb: 'utils.mdwb',
  rust_proxy: 'utils.rust_proxy',
  aadc: 'utils.aadc',
  caut: 'utils.caut',
  fsfs: 'stack.frankensearch',
  sbh: 'stack.storage_ballast_helper',
  casr: 'stack.cross_agent_session_resumer',
  dsr: 'stack.doodlestein_self_releaser',
  asb: 'stack.agent_settings_backup',
  pcr: 'stack.pcr',
  ee: 'stack.eidetic_engine_cli',
  fmd: 'stack.franken_markdown',
  pi: 'stack.pi_agent_rust',
  pfr: 'stack.power_failure_resumer',
};

// Lookup maps indexed by moduleId for O(1) access
const toolsByModuleId = new Map<string, ManifestWebTool>(
  manifestTools.map((t) => [t.moduleId, t]),
);
const tldrByModuleId = new Map<string, ManifestTldrTool>(
  manifestTldrTools.map((t) => [t.moduleId, t]),
);
const commandsByModuleId = new Map<string, ManifestCommand>(
  manifestCommands.map((c) => [c.moduleId, c]),
);

/** Look up a ManifestWebTool by the short ID used in flywheel.ts */
export function getManifestTool(shortId: string): ManifestWebTool | undefined {
  const moduleId = shortIdToModuleId[shortId];
  return moduleId ? toolsByModuleId.get(moduleId) : undefined;
}

/** Look up a ManifestTldrTool by the short ID used in tldr-content.ts */
export function getManifestTldr(shortId: string): ManifestTldrTool | undefined {
  const moduleId = shortIdToModuleId[shortId];
  return moduleId ? tldrByModuleId.get(moduleId) : undefined;
}

/** Look up a ManifestCommand by the short ID used in commands.ts */
export function getManifestCommand(shortId: string): ManifestCommand | undefined {
  const moduleId = shortIdToModuleId[shortId];
  return moduleId ? commandsByModuleId.get(moduleId) : undefined;
}

// Re-export generated data and types for convenience
export { manifestTools, manifestTldrTools, manifestCommands };
export type { ManifestWebTool, ManifestTldrTool, ManifestCommand };
