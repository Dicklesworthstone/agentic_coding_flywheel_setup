import { ExternalLink } from "lucide-react";

import { cn } from "@/lib/utils";
import {
  manifestAgents,
  type ManifestAgent,
  type ManifestAgentStatus,
} from "@/lib/generated/manifest-web-index";

/**
 * "Compatible Agents" roster (#392).
 *
 * Rows come straight from the generated manifest data, so this table, the
 * README block, and what `install.sh` actually installs cannot drift apart.
 * Adding an agent module with `agent:` metadata to acfs.manifest.yaml is the
 * only edit needed to make it appear here.
 */

/** `glass` matches the dark Learning Hub surfaces; `surface` matches the themed wizard cards. */
export type AgentRosterVariant = "glass" | "surface";

const STATUS_LABEL: Record<ManifestAgentStatus, string> = {
  default: "Default",
  optional: "Optional",
  legacy: "Legacy",
};

const STATUS_HINT: Record<ManifestAgentStatus, string> = {
  default: "Installed unless you pass --skip",
  optional: "Install it with --only",
  legacy: "Retired upstream; off by default",
};

const STATUS_BADGE: Record<ManifestAgentStatus, string> = {
  default: "border-green/40 bg-green/10 text-green",
  optional: "border-primary/40 bg-primary/10 text-primary",
  legacy: "border-amber/40 bg-amber/10 text-amber",
};

const VARIANT_STYLES: Record<
  AgentRosterVariant,
  {
    container: string;
    head: string;
    row: string;
    name: string;
    muted: string;
    code: string;
    link: string;
  }
> = {
  glass: {
    container: "border-white/[0.08] bg-white/[0.02]",
    head: "border-white/[0.08] text-white/50",
    row: "border-white/[0.06]",
    name: "text-white",
    muted: "text-white/50",
    code: "bg-white/[0.06] text-white/80",
    link: "text-primary hover:text-primary/80",
  },
  surface: {
    container: "border-border/50 bg-card/50",
    head: "border-border/50 text-muted-foreground",
    row: "border-border/40",
    name: "text-foreground",
    muted: "text-muted-foreground",
    code: "bg-muted text-foreground",
    link: "text-primary hover:text-primary/80",
  },
};

function Code({ children, className }: { children: string; className: string }) {
  return (
    <code className={cn("rounded px-1.5 py-0.5 font-mono text-xs", className)}>
      {children}
    </code>
  );
}

export interface AgentRosterProps {
  variant?: AgentRosterVariant;
  /** Override the rows; defaults to every agent module in the manifest. */
  agents?: ManifestAgent[];
  className?: string;
}

export function AgentRoster({
  variant = "surface",
  agents = manifestAgents,
  className,
}: AgentRosterProps) {
  const styles = VARIANT_STYLES[variant];
  // Derive the flag examples from the roster so they cannot name a module that
  // the manifest no longer ships.
  const onlyExample = agents.find((agent) => agent.status !== "default") ?? agents[0];
  const skipExample = agents.find((agent) => agent.status === "default") ?? agents[0];

  return (
    <div className={cn("overflow-hidden rounded-xl border", styles.container, className)}>
      {/* Wide table: scrolls inside its own box so the page never scrolls
          sideways. A scrollable region needs a name and keyboard focus, or a
          keyboard-only visitor cannot reach the right-hand columns. */}
      <div
        role="region"
        aria-label="Compatible agents"
        tabIndex={0}
        className="overflow-x-auto focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/60"
      >
        <table className="w-full min-w-[46rem] border-collapse text-left text-sm">
          <caption className="sr-only">
            Coding agents ACFS can install, with the CLI, install status, module id, and sign-in
            command for each.
          </caption>
          <thead>
            <tr className={cn("border-b text-xs uppercase tracking-wide", styles.head)}>
              <th scope="col" className="px-4 py-3 font-medium">
                Agent
              </th>
              <th scope="col" className="px-4 py-3 font-medium">
                CLI
              </th>
              <th scope="col" className="px-4 py-3 font-medium">
                Install
              </th>
              <th scope="col" className="px-4 py-3 font-medium">
                Module
              </th>
              <th scope="col" className="px-4 py-3 font-medium">
                Sign in
              </th>
              <th scope="col" className="px-4 py-3 font-medium">
                Docs
              </th>
            </tr>
          </thead>
          <tbody>
            {agents.map((agent) => (
              <tr key={agent.moduleId} className={cn("border-b last:border-b-0", styles.row)}>
                <th scope="row" className="max-w-[18rem] px-4 py-3 font-normal align-top">
                  <span className={cn("font-semibold", styles.name)}>{agent.displayName}</span>
                  {agent.vendor && (
                    <span className={cn("ml-2 text-xs", styles.muted)}>{agent.vendor}</span>
                  )}
                  <p className={cn("mt-1 text-xs font-normal", styles.muted)}>{agent.summary}</p>
                </th>
                <td className="px-4 py-3 align-top">
                  <Code className={styles.code}>{agent.cli}</Code>
                  {agent.aliases.length > 0 && (
                    <p className={cn("mt-1 text-xs", styles.muted)}>
                      alias{agent.aliases.length > 1 ? "es" : ""}: {agent.aliases.join(", ")}
                    </p>
                  )}
                </td>
                <td className="px-4 py-3 align-top">
                  <span
                    className={cn(
                      "inline-block whitespace-nowrap rounded-full border px-2 py-0.5 text-xs font-medium",
                      STATUS_BADGE[agent.status],
                    )}
                  >
                    {STATUS_LABEL[agent.status]}
                  </span>
                  <p className={cn("mt-1 text-xs", styles.muted)}>{STATUS_HINT[agent.status]}</p>
                </td>
                <td className="px-4 py-3 align-top">
                  <Code className={styles.code}>{agent.moduleId}</Code>
                </td>
                <td className="px-4 py-3 align-top">
                  <Code className={styles.code}>{agent.auth}</Code>
                </td>
                <td className="px-4 py-3 align-top">
                  <a
                    href={agent.docsUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                    className={cn("inline-flex items-center gap-1 text-xs font-medium", styles.link)}
                  >
                    Docs
                    <ExternalLink className="h-3 w-3" aria-hidden="true" />
                    <span className="sr-only">for {agent.displayName} (opens in a new tab)</span>
                  </a>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {onlyExample && skipExample && (
        <p className={cn("border-t px-4 py-3 text-xs", styles.head)}>
          Turn any agent on or off at install time with its module id:{" "}
          <Code className={styles.code}>{`--only ${onlyExample.moduleId}`}</Code> installs one plus
          its dependencies,{" "}
          <Code className={styles.code}>{`--skip ${skipExample.moduleId}`}</Code> leaves one out.
        </p>
      )}
    </div>
  );
}
