"use client";

import { useEffect, useId, useMemo, useRef, useState } from "react";
import { CommandCard } from "@/components/command-card";
import { Button } from "@/components/ui/button";
import type { TeamProfileImportChange } from "@/lib/commandBuilder";
import {
  type ApprovedTeamProfileCommand,
  approveTeamProfileReview,
  reviewTeamProfileFile,
  type TeamProfileFileReview,
  TeamProfileImportError,
  type TeamProfileReviewContext,
  teamProfileReviewMatches,
} from "@/lib/teamProfileImport";
import {
  useSavedACFSRef as useACFSRef,
  useSavedInstallMode as useInstallMode,
  useSavedModuleProfile as useModuleProfile,
  useSavedSSHUsername as useSSHUsername,
  useVPSIP,
  useVPSReadinessSelection,
} from "@/lib/userPreferences";
import { VPS_UBUNTU_IMAGE_OPTIONS } from "@/lib/vpsProviders";
import { useWizardInstallation } from "@/lib/wizardInstallation";

function Changes({ title, changes }: { title: string; changes: TeamProfileImportChange[] }) {
  return (
    <div className="space-y-2">
      <h3 className="text-sm font-semibold">{title}</h3>
      {changes.length === 0 ? (
        <p className="text-sm text-muted-foreground">No changes.</p>
      ) : (
        <dl className="space-y-2 text-sm">
          {changes.map((change) => (
            <div key={change.field}>
              <dt className="break-words font-mono text-xs">{change.field}</dt>
              <dd className="break-words text-muted-foreground">
                {JSON.stringify(change.current)} → {JSON.stringify(change.next)}
              </dd>
            </div>
          ))}
        </dl>
      )}
    </div>
  );
}

/** Review compares saved preferences; adopting a review never writes those preferences. */
export function TeamProfileImportPanel() {
  const installationSession = useWizardInstallation();
  const [mode, , modeLoaded] = useInstallMode();
  const [profile, , profileLoaded] = useModuleProfile();
  const [ref, , refLoaded] = useACFSRef();
  const [username, , usernameLoaded] = useSSHUsername();
  const [host, , hostLoaded] = useVPSIP();
  const [provider, , providerLoaded] = useVPSReadinessSelection();
  const [architecture, setArchitecture] = useState<"" | "x86_64" | "aarch64">("");
  const [imageOverride, setImageOverride] = useState("");
  const [review, setReview] = useState<TeamProfileFileReview | null>(null);
  const [approval, setApproval] = useState<{
    review: TeamProfileFileReview;
    value: ApprovedTeamProfileCommand;
  } | null>(null);
  const [confirmed, setConfirmed] = useState(false);
  const [adoptionConfirmed, setAdoptionConfirmed] = useState(false);
  const [reviewGeneration, setReviewGeneration] = useState(0);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const request = useRef(0);
  const id = useId();
  const ready =
    modeLoaded && profileLoaded && refLoaded && usernameLoaded && hostLoaded && providerLoaded;
  const ubuntuVersion = imageOverride || provider?.ubuntuVersion || "";
  const imageSupported = VPS_UBUNTU_IMAGE_OPTIONS.some((value) => value === ubuntuVersion);
  const context = useMemo<TeamProfileReviewContext | null>(() => {
    if (!ready || !host || !architecture || !imageSupported) return null;
    return {
      targetHost: host,
      current: {
        providerSelection: provider,
        installMode: mode,
        ref,
        username,
        architecture,
        ubuntuVersion,
        moduleSelection: { profile },
      },
    };
  }, [
    ready,
    host,
    architecture,
    imageSupported,
    provider,
    mode,
    ref,
    username,
    ubuntuVersion,
    profile,
  ]);
  const [previousContext, setPreviousContext] = useState(context);
  const activeReview = teamProfileReviewMatches(review, context) ? review : null;
  const approved = activeReview && approval?.review === activeReview ? approval.value : null;

  // Reset this component's state before committing a changed target's UI, not
  // in an effect after painting a stale loading/confirmation state.
  if (previousContext !== context) {
    setPreviousContext(context);
    setReview(null);
    setApproval(null);
    setConfirmed(false);
    setBusy(false);
    setError(null);
    setAdoptionConfirmed(false);
  }
  useEffect(() => {
    request.current++;
    return () => {
      request.current++;
    };
  }, [context]);

  function clear(): void {
    request.current++;
    setReview(null);
    setApproval(null);
    setConfirmed(false);
    setBusy(false);
    setError(null);
    setAdoptionConfirmed(false);
  }
  function failure(value: unknown): void {
    setError(
      value instanceof TeamProfileImportError
        ? [value.message, ...value.findingCodes].join(" ")
        : "The profile could not be reviewed. No command or settings were changed.",
    );
  }
  async function read(file: File | undefined): Promise<void> {
    if (!context || !file) return;
    const generation = ++request.current;
    setReview(null);
    setApproval(null);
    setConfirmed(false);
    setError(null);
    setBusy(true);
    setAdoptionConfirmed(false);
    try {
      const next = await reviewTeamProfileFile(file, context);
      if (generation === request.current) {
        setReview(next);
        setReviewGeneration(generation);
      }
    } catch (value) {
      if (generation === request.current) failure(value);
    } finally {
      if (generation === request.current) setBusy(false);
    }
  }
  function approve(): void {
    if (!activeReview || !context || !confirmed || busy || reviewGeneration !== request.current)
      return;
    setReviewGeneration(++request.current);
    try {
      const value = approveTeamProfileReview(activeReview, context, confirmed);
      setApproval({ review: activeReview, value });
      setError(null);
    } catch (value) {
      setApproval(null);
      setConfirmed(false);
      failure(value);
    }
  }
  function adopt(): void {
    if (
      !installationSession ||
      !activeReview ||
      !context ||
      !adoptionConfirmed ||
      busy ||
      reviewGeneration !== request.current
    )
      return;
    setReviewGeneration(++request.current);
    try {
      installationSession.activate(activeReview, context, adoptionConfirmed);
      setApproval(null);
      setError(null);
      setAdoptionConfirmed(false);
    } catch (value) {
      setAdoptionConfirmed(false);
      failure(value);
    }
  }

  return (
    <details className="rounded-xl border border-border/50 bg-card/30 p-4">
      <summary className="min-h-11 cursor-pointer py-2 text-base font-semibold">
        Have a shared team profile? Review it locally
      </summary>
      <div className="mt-3 space-y-4">
        <p className="text-sm text-muted-foreground">
          Load a team-profile JSON file, review its differences from your saved wizard profile, then
          approve a separate manual command or explicitly use the complete reviewed installation in
          this wizard tab. Neither choice provisions a server, runs commands, or marks installation
          complete. Saved wizard preferences are never overwritten. The file stays in browser
          memory: it is not uploaded or saved to local storage.
        </p>
        <p className="text-sm text-muted-foreground">
          Confirm the intended VPS image and architecture below. These are your declarations, not
          detected host facts. An older LTS image may still be upgraded by the installer.
        </p>
        <div className="grid gap-3 sm:grid-cols-2">
          <label className="space-y-1 text-sm" htmlFor={`${id}-image`}>
            <span>VPS Ubuntu image before installation</span>
            <select
              id={`${id}-image`}
              value={imageSupported ? ubuntuVersion : ""}
              disabled={!ready}
              onChange={(event) => setImageOverride(event.target.value)}
              className="min-h-11 w-full rounded-md border bg-background px-3"
            >
              <option value="">Choose the VPS image</option>
              {VPS_UBUNTU_IMAGE_OPTIONS.map((version) => (
                <option key={version} value={version}>
                  Ubuntu {version}
                </option>
              ))}
            </select>
          </label>
          <label className="space-y-1 text-sm" htmlFor={`${id}-arch`}>
            <span>VPS architecture</span>
            <select
              id={`${id}-arch`}
              value={architecture}
              disabled={!ready}
              onChange={(event) => {
                const value = event.target.value;
                if (value === "" || value === "x86_64" || value === "aarch64")
                  setArchitecture(value);
              }}
              className="min-h-11 w-full rounded-md border bg-background px-3"
            >
              <option value="">Choose the VPS architecture</option>
              <option value="x86_64">x86-64 (Intel / AMD)</option>
              <option value="aarch64">ARM64</option>
            </select>
          </label>
        </div>
        {!context && (
          <p role="status" className="text-sm text-muted-foreground">
            {!ready
              ? "Loading your saved wizard settings..."
              : !host
                ? "Record the target VPS address in the wizard first."
                : "Confirm the VPS image and architecture before choosing a profile."}
          </p>
        )}
        <label className="block space-y-2 text-sm" htmlFor={`${id}-file`}>
          <span>Team-profile JSON (maximum 256 KiB)</span>
          <input
            id={`${id}-file`}
            type="file"
            accept=".json,application/json"
            disabled={!context || busy}
            onChange={(event) => {
              const file = event.currentTarget.files?.[0];
              event.currentTarget.value = "";
              void read(file);
            }}
            className="block min-h-11 w-full text-sm"
          />
        </label>
        {busy && (
          <p role="status" className="text-sm">
            Reading and validating the local profile...
          </p>
        )}
        {error && (
          <p role="alert" className="break-words text-sm text-destructive">
            {error}
          </p>
        )}
        {(busy || review || error) && (
          <Button type="button" variant="outline" onClick={clear}>
            Clear imported profile
          </Button>
        )}
        {activeReview && (
          <div className="space-y-4 border-t border-border/50 pt-4">
            <h2 className="text-lg font-semibold">
              Review {activeReview.diff.profile?.displayName}
            </h2>
            <p className="break-all font-mono text-xs">File SHA-256: {activeReview.sourceSha256}</p>
            <Changes
              title="Provider and access defaults (not applied)"
              changes={activeReview.diff.safeDefaults.changes}
            />
            <Changes
              title="Installer and module-selection changes"
              changes={activeReview.diff.installerCommand.changes}
            />
            <div className="space-y-2 text-sm">
              <h3 className="font-semibold">Required dependencies added by the resolver</h3>
              <p className="break-words font-mono text-xs">
                {activeReview.diff.dependencyClosure.join(", ") || "None."}
              </p>
              <h3 className="font-semibold">Explicitly skipped modules</h3>
              <p className="break-words font-mono text-xs">
                {activeReview.diff.skips.requested.join(", ") || "None."}
              </p>
              <h3 className="font-semibold">Required sign-ins / secret slots</h3>
              <p className="break-words font-mono text-xs">
                {activeReview.diff.secretSlots.required.join(", ") || "None declared."}
              </p>
              <h3 className="font-semibold">Optional sign-ins / secret slots</h3>
              <p className="break-words font-mono text-xs">
                {activeReview.diff.secretSlots.optional.join(", ") || "None declared."}
              </p>
              <p className="text-muted-foreground">
                Supply credentials only through the normal provider or CLI login. Never paste them
                into a profile.
              </p>
              {activeReview.diff.skips.warnings.map((warning, index) => (
                <p key={index} className="text-muted-foreground">
                  {warning}
                </p>
              ))}
            </div>
            <label
              htmlFor={`${id}-confirm`}
              className="flex min-h-11 items-start gap-3 py-2 text-sm"
            >
              <input
                id={`${id}-confirm`}
                type="checkbox"
                checked={confirmed}
                className="mt-1"
                onChange={(event) => {
                  setReviewGeneration(++request.current);
                  setConfirmed(event.target.checked);
                  setApproval(null);
                }}
              />
              <span>
                I reviewed these changes and trust this profile&apos;s source. Generate its manual
                command only; leave my wizard settings and completion state unchanged.
              </span>
            </label>
            <Button type="button" disabled={!confirmed || busy} onClick={approve}>
              Approve profile command
            </Button>
            {installationSession && (
              <div className="space-y-3 rounded-lg border border-primary/30 p-3">
                <label
                  htmlFor={`${id}-adopt`}
                  className="flex min-h-11 items-start gap-3 py-2 text-sm"
                >
                  <input
                    id={`${id}-adopt`}
                    type="checkbox"
                    checked={adoptionConfirmed}
                    className="mt-1"
                    onChange={(event) => {
                      setReviewGeneration(++request.current);
                      setAdoptionConfirmed(event.target.checked);
                    }}
                  />
                  <span>
                    I reviewed these changes and trust the source. Use its exact mode, ref, username
                    and module selections throughout this wizard tab, including installer, handoff,
                    reconnection and retry commands. Do not run anything or mark it complete.
                  </span>
                </label>
                <Button type="button" disabled={!adoptionConfirmed || busy} onClick={adopt}>
                  Use reviewed installation in this wizard
                </Button>
                <p className="text-xs text-muted-foreground">
                  Reloading requires a new review or explicit discard. Only a constant reload guard
                  is saved in this tab; the profile, target and approval remain in memory. Clearing
                  this file review does not discard an already active installation.
                </p>
              </div>
            )}
            {approved && (
              <div className="space-y-2">
                <p role="status" className="text-sm">
                  Separate manual command approved. Run it only in the intended VPS root shell,
                  instead of the wizard&apos;s default command. No installation has been performed.
                </p>
                <CommandCard
                  command={approved.command}
                  description="Approved team-profile installer"
                  runLocation="vps"
                />
              </div>
            )}
          </div>
        )}
      </div>
    </details>
  );
}
