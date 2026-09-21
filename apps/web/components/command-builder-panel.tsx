"use client";

import {
  Boxes,
  Check,
  ChevronDown,
  Copy,
  Link2,
  Monitor,
  Server,
  Settings2,
  Terminal,
} from "lucide-react";
import { useCallback, useEffect, useId, useMemo, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { CopyStatus } from "@/components/ui/code-block";
import { buildCommands, buildShareURL } from "@/lib/commandBuilder";
import { manifestModules, manifestSelectionProfiles } from "@/lib/generated/manifest-modules";
import { useCopyFeedback } from "@/lib/hooks/useCopyFeedback";
import { resolveModuleSelection } from "@/lib/moduleSelection";
import type { ApprovedTeamProfileInstallation } from "@/lib/teamProfileImport";
import {
  type InstallMode,
  isValidIP,
  type ModuleSelectionProfileId,
  normalizeGitRef,
  normalizeSSHUsername,
  useACFSRef,
  useInstallMode,
  useModuleProfile,
  useSSHUsername,
  useUserOS,
  useVPSIP,
} from "@/lib/userPreferences";
import { cn } from "@/lib/utils";
import { useWizardInstallation } from "@/lib/wizardInstallation";

function LocationBadge({ location }: { location: "local" | "vps" }) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium uppercase tracking-wider",
        location === "vps" ? "bg-green/15 text-green" : "bg-primary/15 text-primary",
      )}
    >
      {location === "vps" ? (
        <Server className="h-2.5 w-2.5" />
      ) : (
        <Monitor className="h-2.5 w-2.5" />
      )}
      {location === "vps" ? "VPS" : "Local"}
    </span>
  );
}

function CommandRow({
  label,
  description,
  command,
  runLocation,
}: {
  label: string;
  description: string;
  command: string;
  runLocation: "local" | "vps";
}) {
  const { state: copyState, copy } = useCopyFeedback();
  const copied = copyState === "copied";
  const codeRef = useRef<HTMLElement | null>(null);

  const handleCopy = useCallback(() => {
    void copy(command, { selectOnFailure: codeRef.current });
  }, [command, copy]);

  return (
    <div className="group rounded-lg border border-border/50 bg-card/50 p-3 transition-colors hover:border-border">
      <div className="mb-2 flex items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <span className="text-sm font-medium text-foreground">{label}</span>
          <LocationBadge location={runLocation} />
        </div>
        <span className="text-xs text-muted-foreground">{description}</span>
      </div>
      <div className="flex items-center gap-2">
        {/* Focusable scroll region so keyboard users can pan a long command
            (WCAG 2.1.1); the sibling copy button is the default 44px icon size. */}
        <code
          ref={codeRef}
          tabIndex={0}
          role="region"
          aria-label={`${label} command`}
          className="flex-1 overflow-x-auto rounded-md bg-muted/60 px-3 py-2 font-mono text-sm text-foreground outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring"
        >
          {command}
        </code>
        <Button
          variant="ghost"
          size="icon"
          className="shrink-0"
          onClick={handleCopy}
          aria-label={`Copy ${label} command`}
        >
          {copied ? (
            <Check className="h-4 w-4 text-green" />
          ) : (
            <Copy className="h-4 w-4 text-muted-foreground" />
          )}
        </Button>
      </div>
      <CopyStatus state={copyState} className="mt-2" />
    </div>
  );
}

function SettingsToggle({
  label,
  options,
  value,
  onChange,
}: {
  label: string;
  options: { value: string; label: string }[];
  value: string;
  onChange: (value: string) => void;
}) {
  return (
    <div className="flex items-center gap-2">
      <span className="text-xs text-muted-foreground">{label}:</span>
      <div
        className="flex flex-wrap rounded-lg border border-border/50 bg-muted/30 p-0.5"
        role="group"
        aria-label={`${label} selection`}
      >
        {options.map((opt) => (
          <button
            key={opt.value}
            type="button"
            onClick={() => onChange(opt.value)}
            aria-pressed={value === opt.value}
            className={cn(
              "min-h-11 rounded-md px-2.5 py-1 text-xs font-medium transition-colors",
              value === opt.value
                ? "bg-primary text-primary-foreground shadow-sm"
                : "text-muted-foreground hover:text-foreground",
            )}
          >
            {opt.label}
          </button>
        ))}
      </div>
    </div>
  );
}

function ExclusionPicker({
  kind,
  options,
  selected,
  onChange,
}: {
  kind: "category" | "tag";
  options: { value: string; count: number }[];
  selected: string[];
  onChange: (values: string[]) => void;
}) {
  const id = useId();
  return (
    <div className="space-y-2">
      <label htmlFor={id} className="text-xs font-medium text-foreground">
        Exclude {kind}
      </label>
      <select
        id={id}
        value=""
        onChange={(event) => {
          const value = event.target.value;
          if (options.some((option) => option.value === value) && !selected.includes(value)) {
            onChange([...selected, value]);
          }
        }}
        className="min-h-11 w-full rounded-md border border-border/50 bg-background px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/40"
      >
        <option value="">Choose a {kind} to exclude</option>
        {options
          .filter((option) => !selected.includes(option.value))
          .map((option) => (
            <option key={option.value} value={option.value}>
              {option.value} ({option.count} modules)
            </option>
          ))}
      </select>
      <div className="flex flex-wrap gap-2">
        {selected.map((value) => (
          <Button
            key={value}
            type="button"
            variant="outline"
            size="sm"
            className="min-h-11 text-xs"
            aria-label={`Remove excluded ${kind} ${value}`}
            onClick={() => onChange(selected.filter((entry) => entry !== value))}
          >
            {value} <span aria-hidden="true">×</span>
          </Button>
        ))}
      </div>
    </div>
  );
}

export function CommandBuilderPanel() {
  const session = useWizardInstallation();
  if (session?.status === "active" && session.installation) {
    return <ReviewedCommandBuilderPanel installation={session.installation} />;
  }
  if (session && session.status !== "saved") {
    return (
      <p role="status">Review or discard the pending installation before generating commands.</p>
    );
  }
  return <SavedCommandBuilderPanel />;
}

/** Active approval is immutable; editable drafts and lossy links are separate. */
function ReviewedCommandBuilderPanel({
  installation,
}: {
  installation: ApprovedTeamProfileInstallation;
}) {
  const [host, , hostLoaded] = useVPSIP();
  const [os, , osLoaded] = useUserOS();
  const commands = useMemo(() => {
    if (!hostLoaded || !osLoaded || !host) return null;
    try {
      const next = buildCommands({
        ip: host,
        os: os ?? "mac",
        username: installation.username,
        mode: installation.mode,
        ref: installation.ref,
        moduleSelection: installation.moduleSelection,
      });
      return next.find((entry) => entry.id === "installer")?.command === installation.command
        ? next
        : null;
    } catch {
      return null;
    }
  }, [host, os, hostLoaded, osLoaded, installation]);
  return (
    <section className="space-y-4 rounded-xl border border-primary/30 bg-card/30 p-5">
      <h2 className="text-sm font-semibold">Your reviewed installation commands</h2>
      <p className="text-sm text-muted-foreground">
        These commands retain the exact reviewed selection. Discard the active installation using
        the banner before editing saved defaults or creating a different command. Sharing an
        approval through a URL is not supported.
      </p>
      {commands ? (
        commands.map((command) => (
          <CommandRow
            key={command.id}
            label={command.label}
            description={command.description}
            runLocation={command.runLocation}
            command={
              os === "windows" && command.windowsCommand ? command.windowsCommand : command.command
            }
          />
        ))
      ) : (
        <p role="alert">
          Reviewed commands are unavailable or changed. Review the installation again before
          continuing.
        </p>
      )}
    </section>
  );
}

function SavedCommandBuilderPanel() {
  const [vpsIP, setVPSIP] = useVPSIP();
  const [os] = useUserOS();
  const [mode, setMode] = useInstallMode();
  const [username, setUsername] = useSSHUsername();
  const [ref, setRef] = useACFSRef();
  const [profile, setProfile] = useModuleProfile();
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [showPlan, setShowPlan] = useState(false);
  // These are local command customizations, not silently lossy profile exports.
  const [skipTags, setSkipTags] = useState<string[]>([]);
  const [skipCategories, setSkipCategories] = useState<string[]>([]);
  const { state: shareCopyState, copy: copyShareLink } = useCopyFeedback();
  const shareCopied = shareCopyState === "copied";
  const [localIP, setLocalIP] = useState("");
  const [ipError, setIpError] = useState<string | null>(null);
  const [usernameDraft, setUsernameDraft] = useState(username);
  const [refDraft, setRefDraft] = useState(ref ?? "");
  const panelId = useId();
  const advancedPanelId = `${panelId}-advanced`;
  const planPanelId = `${panelId}-plan`;
  const ipErrorId = `${panelId}-ip-error`;
  const usernameErrorId = `${panelId}-user-error`;
  const refErrorId = `${panelId}-ref-error`;

  useEffect(() => {
    setUsernameDraft(username);
  }, [username]);

  useEffect(() => {
    setRefDraft(ref ?? "");
  }, [ref]);

  const effectiveIP = vpsIP || (isValidIP(localIP) ? localIP : "");
  const effectiveOS = os || "mac";
  const usernameError = useMemo(() => {
    const trimmed = usernameDraft.trim();
    if (!trimmed) return "Enter a Linux username such as ubuntu or devuser.";
    if (trimmed === "root")
      return "Use ubuntu or another non-root Linux user; root is only for the first SSH login.";
    if (normalizeSSHUsername(trimmed)) return null;
    return "Use lowercase letters, numbers, dots, underscores, or hyphens, and start with a lowercase letter or underscore.";
  }, [usernameDraft]);
  const effectiveUsername = useMemo(() => {
    const trimmed = usernameDraft.trim();
    if (!trimmed || usernameError) {
      return username;
    }
    return trimmed;
  }, [username, usernameDraft, usernameError]);
  const normalizedRefDraft = useMemo(() => {
    const trimmed = refDraft.trim();
    if (!trimmed) return null;
    return normalizeGitRef(trimmed);
  }, [refDraft]);
  const effectiveRef = useMemo(() => {
    const trimmed = refDraft.trim();
    if (!trimmed) return null;
    return normalizedRefDraft;
  }, [normalizedRefDraft, refDraft]);

  const moduleSelection = useMemo(
    () => ({ profile, skipTags, skipCategories }),
    [profile, skipTags, skipCategories],
  );
  const hasExclusions = skipTags.length > 0 || skipCategories.length > 0;
  const exclusionOptions = useMemo(() => {
    const categories = new Map<string, number>();
    const tags = new Map<string, number>();
    for (const module of manifestModules) {
      categories.set(module.category, (categories.get(module.category) ?? 0) + 1);
      for (const tag of new Set(module.tags)) tags.set(tag, (tags.get(tag) ?? 0) + 1);
    }
    const options = (counts: Map<string, number>) =>
      [...counts.keys()].sort().map((value) => ({ value, count: counts.get(value)! }));
    return { categories: options(categories), tags: options(tags) };
  }, []);

  const plan = useMemo(() => {
    return resolveModuleSelection(moduleSelection);
  }, [moduleSelection]);

  const commands = useMemo(() => {
    if (!effectiveIP || !plan.ok) return null;
    return buildCommands({
      ip: effectiveIP,
      os: effectiveOS,
      username: effectiveUsername,
      mode,
      ref: effectiveRef,
      moduleSelection,
    });
  }, [effectiveIP, effectiveOS, effectiveUsername, mode, effectiveRef, moduleSelection, plan.ok]);

  const refError = useMemo(() => {
    const value = refDraft.trim();
    if (!value || normalizedRefDraft) return null;
    return "Invalid git ref format. Command generation falls back to main.";
  }, [normalizedRefDraft, refDraft]);

  const handleShare = useCallback(() => {
    if (!effectiveIP || !plan.ok || hasExclusions) return;
    const url = buildShareURL({
      ip: effectiveIP,
      os: effectiveOS,
      username: effectiveUsername,
      mode,
      ref: effectiveRef,
      moduleSelection,
    });
    void copyShareLink(url);
  }, [
    copyShareLink,
    effectiveIP,
    effectiveOS,
    effectiveUsername,
    mode,
    effectiveRef,
    moduleSelection,
    plan.ok,
    hasExclusions,
  ]);

  const handleIPChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const val = e.target.value.trim();
    setLocalIP(val);
    if (val && !isValidIP(val)) {
      setIpError("Enter a valid IP (e.g., 203.0.113.42)");
    } else {
      setIpError(null);
    }
  }, []);

  // Persist a valid inline IP so the rest of the page (which reads the stored
  // VPS IP) stops saying YOUR_VPS_IP. Committed on blur/Enter rather than per
  // keystroke: "203.0.113.4" is a valid IP halfway through typing
  // "203.0.113.42", and persisting it would lock in the wrong host.
  const commitLocalIP = useCallback(() => {
    if (localIP && isValidIP(localIP)) {
      setVPSIP(localIP);
    }
  }, [localIP, setVPSIP]);

  const handleUsernameChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    setUsernameDraft(e.target.value);
  }, []);

  const commitUsernameDraft = useCallback(() => {
    const trimmed = usernameDraft.trim();
    const normalized = normalizeSSHUsername(trimmed);
    if (!normalized) {
      setUsernameDraft(username);
      return;
    }

    setUsernameDraft(normalized);
    if (normalized !== username) {
      setUsername(normalized);
    }
  }, [username, usernameDraft, setUsername]);

  const handleRefChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    setRefDraft(e.target.value);
  }, []);

  const commitRefDraft = useCallback(() => {
    const trimmed = refDraft.trim();
    if (!trimmed) {
      setRefDraft("");
      if (ref !== null) {
        setRef(null);
      }
      return;
    }

    if (!normalizedRefDraft) {
      return;
    }

    setRefDraft(normalizedRefDraft);
    if (normalizedRefDraft !== ref) {
      setRef(normalizedRefDraft);
    }
  }, [normalizedRefDraft, ref, refDraft, setRef]);

  const profileOptions = useMemo(() => {
    return manifestSelectionProfiles
      .filter((p) => !p.mode)
      .map((p) => ({
        value: p.id,
        label: p.label,
      }));
  }, []);

  return (
    <div className="space-y-4 rounded-xl border border-border/50 bg-card/30 p-5">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Terminal className="h-4 w-4 text-primary" />
          {/* h2: the panel is mounted directly under the page's h1 on
              launch-onboarding, so an h3 here skipped a level. */}
          <h2 className="text-sm font-semibold text-foreground">Your Commands</h2>
        </div>
        {effectiveIP && (
          <Button
            variant="ghost"
            size="sm"
            onClick={handleShare}
            disabled={!plan.ok || hasExclusions}
            title={
              hasExclusions
                ? "Copy the exact command below; shared links cannot preserve exclusions."
                : undefined
            }
            className="gap-1.5 text-xs text-muted-foreground"
          >
            {shareCopied ? <Check className="h-3 w-3 text-green" /> : <Link2 className="h-3 w-3" />}
            {shareCopied ? "Copied!" : "Share link"}
          </Button>
        )}
      </div>
      <CopyStatus state={shareCopyState} />

      {/* IP input (only if no IP stored from wizard) */}
      {!vpsIP && (
        <div>
          <label className="text-xs text-muted-foreground" htmlFor="cb-ip">
            VPS IP address
          </label>
          <input
            id="cb-ip"
            type="text"
            autoComplete="off"
            value={localIP}
            onChange={handleIPChange}
            onBlur={commitLocalIP}
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                e.currentTarget.blur();
              }
            }}
            placeholder="203.0.113.42"
            aria-invalid={ipError ? "true" : "false"}
            aria-describedby={ipError ? ipErrorId : undefined}
            className={cn(
              "mt-1 w-full rounded-lg border bg-muted/40 px-3 py-2 font-mono text-sm text-foreground placeholder:text-muted-foreground/50 focus:outline-none focus:ring-2 focus:ring-primary/40",
              ipError ? "border-destructive" : "border-border/50",
            )}
          />
          {ipError && (
            <p id={ipErrorId} role="alert" className="mt-1 text-xs text-destructive">
              {ipError}
            </p>
          )}
        </div>
      )}

      {/* Controls: Mode & Profile */}
      <div className="space-y-3">
        <div className="flex flex-wrap items-center gap-4">
          <SettingsToggle
            label="Mode"
            options={[
              { value: "vibe", label: "Vibe" },
              { value: "safe", label: "Safe" },
            ]}
            value={mode}
            onChange={(v) => setMode(v as InstallMode)}
          />

          <button
            type="button"
            onClick={() => setShowAdvanced(!showAdvanced)}
            aria-expanded={showAdvanced}
            aria-controls={advancedPanelId}
            className="flex items-center gap-1 rounded-md px-2 py-2 text-xs text-muted-foreground hover:text-foreground transition-colors"
          >
            <Settings2 className="h-3 w-3" />
            Advanced
            <ChevronDown
              className={cn("h-3 w-3 transition-transform", showAdvanced && "rotate-180")}
            />
          </button>
        </div>

        {/* Profile Selector */}
        <SettingsToggle
          label="Profile"
          options={profileOptions}
          value={profile}
          onChange={(v) => setProfile(v as ModuleSelectionProfileId)}
        />
      </div>

      <fieldset className="space-y-3 rounded-lg border border-border/40 p-3">
        <legend className="px-1 text-sm font-medium text-foreground">Customize exclusions</legend>
        <p className="text-xs text-muted-foreground">
          Exclude groups from this panel&apos;s commands. Required dependency conflicts block
          command generation; nothing is installed from this page.
        </p>
        <div className="grid gap-4 sm:grid-cols-2">
          <ExclusionPicker
            kind="category"
            options={exclusionOptions.categories}
            selected={skipCategories}
            onChange={setSkipCategories}
          />
          <ExclusionPicker
            kind="tag"
            options={exclusionOptions.tags}
            selected={skipTags}
            onChange={setSkipTags}
          />
        </div>
        {hasExclusions && (
          <div className="space-y-2">
            <p className="text-xs text-muted-foreground" role="status">
              These exclusions apply only to this panel and stay selected when switching profiles.
              They are not saved in shared links, saved profiles, or other wizard commands. Copy the
              exact installer command below for handoff.
            </p>
            <Button
              type="button"
              variant="outline"
              size="sm"
              className="min-h-11"
              onClick={() => {
                setSkipTags([]);
                setSkipCategories([]);
              }}
            >
              Clear all exclusions
            </Button>
          </div>
        )}
      </fieldset>

      {!plan.ok && (
        <div
          role="alert"
          className="space-y-1 rounded-lg border border-destructive/40 bg-destructive/10 p-3 text-sm text-destructive"
        >
          <p className="font-semibold">Install plan blocked</p>
          {plan.errors.map((error, index) => (
            <p key={index}>{error}</p>
          ))}
          <p>
            Remove the conflicting exclusion or choose another profile. No runnable command is
            shown.
          </p>
        </div>
      )}

      {/* Plan Summary Toggle & Review */}
      <div className="rounded-lg border border-border/40 bg-muted/15 p-3">
        <button
          type="button"
          onClick={() => setShowPlan(!showPlan)}
          className="flex w-full items-center justify-between rounded-md px-2 py-2 text-xs font-medium text-foreground hover:text-primary transition-colors"
          aria-expanded={showPlan}
          aria-controls={planPanelId}
        >
          <div className="flex items-center gap-1.5">
            <Boxes className="h-3.5 w-3.5 text-primary" />
            <span>
              {plan.ok
                ? `Install Plan: ${plan.selectedCount} of ${plan.availableCount} modules`
                : "Install Plan: blocked"}
              {plan.ok && plan.availableCount > plan.selectedCount
                ? ` (${plan.availableCount - plan.selectedCount} skipped)`
                : ""}
            </span>
          </div>
          <ChevronDown
            className={cn("h-3.5 w-3.5 transition-transform", showPlan && "rotate-180")}
          />
        </button>

        {showPlan && (
          <div id={planPanelId} className="mt-3 space-y-3 border-t border-border/30 pt-3 text-xs">
            <div>
              <span className="font-semibold text-muted-foreground">
                Included Modules ({plan.included.length}):
              </span>
              <div className="mt-1.5 max-h-48 space-y-1 overflow-y-auto rounded-md bg-background/50 p-2 font-mono text-xs">
                {plan.included.map((item) => (
                  <div key={item.id} className="flex items-center justify-between gap-2 py-0.5">
                    <span className="truncate text-foreground">
                      <span className="text-muted-foreground">[P{item.phase}]</span> {item.id}
                    </span>
                    <span className="shrink-0 text-xs text-muted-foreground">
                      {item.reason === "default" || item.reason === "explicitly requested"
                        ? "included"
                        : item.reason}
                    </span>
                  </div>
                ))}
              </div>
            </div>

            {plan.excluded.length > 0 && (
              <div>
                <span className="font-semibold text-muted-foreground">
                  Skipped Modules ({plan.excluded.length}):
                </span>
                <div className="mt-1.5 max-h-32 space-y-1 overflow-y-auto rounded-md bg-background/30 p-2 font-mono text-xs">
                  {plan.excluded.map((item) => (
                    <div
                      key={item.id}
                      className="flex items-center justify-between gap-2 py-0.5 text-muted-foreground"
                    >
                      <span className="truncate">✕ {item.id}</span>
                      <span className="shrink-0 text-xs">{item.reason}</span>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Advanced settings */}
      {showAdvanced && (
        <div
          id={advancedPanelId}
          className="space-y-3 rounded-lg border border-border/30 bg-muted/20 p-3"
        >
          <div>
            <label className="text-xs text-muted-foreground" htmlFor="cb-user">
              SSH username
            </label>
            <input
              id="cb-user"
              type="text"
              value={usernameDraft}
              onChange={handleUsernameChange}
              onBlur={commitUsernameDraft}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.currentTarget.blur();
                }
              }}
              placeholder="ubuntu"
              aria-invalid={usernameError ? "true" : "false"}
              aria-describedby={usernameError ? usernameErrorId : undefined}
              className={cn(
                "mt-1 w-full rounded-md border bg-muted/40 px-3 py-1.5 font-mono text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/40",
                usernameError ? "border-destructive" : "border-border/50",
              )}
            />
            {usernameError && (
              <p id={usernameErrorId} role="alert" className="mt-1 text-xs text-destructive">
                {usernameError}
              </p>
            )}
          </div>
          <div>
            <label className="text-xs text-muted-foreground" htmlFor="cb-ref">
              Pin to git ref <span className="text-muted-foreground">(optional)</span>
            </label>
            <input
              id="cb-ref"
              type="text"
              value={refDraft}
              onChange={handleRefChange}
              onBlur={commitRefDraft}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.currentTarget.blur();
                }
              }}
              placeholder="main"
              aria-invalid={refError ? "true" : "false"}
              aria-describedby={refError ? refErrorId : undefined}
              className={cn(
                "mt-1 w-full rounded-md border bg-muted/40 px-3 py-1.5 font-mono text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/40",
                refError ? "border-destructive" : "border-border/50",
              )}
            />
            {refError && (
              <p id={refErrorId} role="alert" className="mt-1 text-xs text-destructive">
                {refError}
              </p>
            )}
          </div>
        </div>
      )}

      {/* Commands list */}
      {commands ? (
        <div className="space-y-2">
          {commands.map((cmd) => (
            <CommandRow
              key={cmd.id}
              label={cmd.label}
              description={cmd.description}
              command={
                effectiveOS === "windows" && cmd.windowsCommand ? cmd.windowsCommand : cmd.command
              }
              runLocation={cmd.runLocation}
            />
          ))}
        </div>
      ) : !plan.ok ? (
        <p className="py-4 text-center text-sm text-muted-foreground">
          Resolve the install plan conflict above to generate commands.
        </p>
      ) : (
        <p className="py-4 text-center text-sm text-muted-foreground">
          Enter your VPS IP to generate personalized commands.
        </p>
      )}
    </div>
  );
}
