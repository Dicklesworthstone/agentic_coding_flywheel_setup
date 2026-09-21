"use client";

import { useQuery } from "@tanstack/react-query";
import {
  Check,
  Clock,
  Code,
  Download,
  ExternalLink,
  FileJson,
  FileText,
  Info,
  Pin,
  Rocket,
  ShieldCheck,
  Sparkles,
  Wifi,
} from "lucide-react";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { AlertCard, DetailsSection, OutputPreview } from "@/components/alert-card";
import { CommandCard, commandCompletionKeys } from "@/components/command-card";
import { Jargon } from "@/components/jargon";
import {
  GuideCaution,
  GuideExplain,
  GuideSection,
  GuideStep,
  GuideTip,
  SimplerGuide,
} from "@/components/simpler-guide";
import { TrackedLink } from "@/components/tracked-link";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import {
  buildHandoffRunbook,
  buildInstallCommandDetails,
  buildTeamProfile,
  formatHandoffRunbookMarkdown,
  formatSshTarget,
  formatTeamProfileReviewMarkdown,
  serializeHandoffRunbookJson,
  serializeTeamProfileJson,
} from "@/lib/commandBuilder";
import { manifestProvenance, manifestSelectionProfiles } from "@/lib/generated/manifest-modules";
import { useWizardAnalytics } from "@/lib/hooks/useWizardAnalytics";
import { createInstallerCheckpoint, installerCheckpointMatches } from "@/lib/installerCheckpoint";
import { resolveModuleSelection } from "@/lib/moduleSelection";
import {
  buildProviderProvisioningPacket,
  serializeProviderProvisioningPacketJson,
} from "@/lib/providerProvisioningPacket";
import {
  normalizeGitRef,
  useACFSRef,
  useInstallMode,
  useModuleProfile,
  useModuleSelection,
  useSSHUsername,
  useUserOS,
  useVPSIP,
  useVPSReadinessSelection,
  type VPSReadinessSelection,
} from "@/lib/userPreferences";
import { copyTextToClipboard, safeGetItem, withCurrentSearch } from "@/lib/utils";
import { ACFS_RECOMMENDED_UBUNTU } from "@/lib/vpsProviders";
import { useWizardInstallation } from "@/lib/wizardInstallation";
import {
  canAccessWizardStep,
  getCompletedSteps,
  getNextReachableWizardStep,
  markStepComplete,
  useWizardForwardNav,
} from "@/lib/wizardSteps";

const DEFAULT_VPS_READINESS_SELECTION: VPSReadinessSelection = {
  providerId: "other",
  planName: "custom plan",
  // A provisioning preference when no image was saved, not detected host state.
  ubuntuVersion: ACFS_RECOMMENDED_UBUNTU,
  region: "not-listed",
  targetAgents: 10,
  workloadId: "standard",
};

const VERIFIED_INSTALLER_CACHE_PATH = "/var/cache/acfs-installer-cache";

/**
 * Trigger a client-side download. Returns false when the browser could not
 * start one (no DOM, blocked navigation, etc.) so the caller can fall back to
 * copying the text. Object URLs are revoked on a timer: Safari and older
 * Firefox cancel a download whose URL is revoked before the navigation begins.
 */
function downloadTextFile(filename: string, contents: string, mimeType: string): boolean {
  if (typeof document === "undefined") return false;
  try {
    const link = document.createElement("a");
    link.download = filename;
    link.rel = "noopener";
    const canUseObjectUrl = typeof URL !== "undefined" && typeof URL.createObjectURL === "function";
    let objectUrl: string | null = null;
    if (canUseObjectUrl) {
      objectUrl = URL.createObjectURL(new Blob([contents], { type: mimeType }));
      link.href = objectUrl;
    } else {
      // Older WebViews / some privacy modes have no object URLs; a data: URL
      // still downloads (or opens) the text.
      link.href = `data:${mimeType};charset=utf-8,${encodeURIComponent(contents)}`;
    }
    document.body.appendChild(link);
    link.click();
    link.remove();
    if (objectUrl) {
      const url = objectUrl;
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    }
    return true;
  } catch {
    return false;
  }
}

export default function RunInstallerPage() {
  const router = useRouter();
  const [isNavigating, setIsNavigating] = useState(false);
  const [userOS, , userOSLoaded] = useUserOS();
  const [installMode, , installModeLoaded] = useInstallMode();
  const [moduleProfile, setModuleProfile, moduleProfileLoaded] = useModuleProfile();
  const [moduleSelection, moduleSelectionLoaded] = useModuleSelection();
  const installationSession = useWizardInstallation();
  const reviewedInstallation =
    installationSession?.status === "active" ? installationSession.installation : null;
  const [pinnedRef, setPinnedRef, acfsRefLoaded] = useACFSRef();
  const [vpsIP, , vpsIPLoaded] = useVPSIP();
  const [sshUsername, , sshUsernameLoaded] = useSSHUsername();
  const [vpsReadinessSelection, , vpsReadinessSelectionLoaded] = useVPSReadinessSelection();
  const [pinEditorOpen, setPinEditorOpen] = useState(false);
  const [refDraftOverride, setRefDraftOverride] = useState<string | null>(null);
  // Transient "Saved <file>" / "Download failed" message for the handoff buttons.
  const [downloadStatus, setDownloadStatus] = useState<string | null>(null);
  const downloadStatusTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const usePinnedRef = reviewedInstallation
    ? reviewedInstallation.ref !== null
    : pinEditorOpen || pinnedRef !== null;
  // A previously edited local draft cannot override the newly approved snapshot.
  const refDraft = reviewedInstallation
    ? (reviewedInstallation.ref ?? "main")
    : pinEditorOpen
      ? (refDraftOverride ?? pinnedRef ?? "main")
      : (pinnedRef ?? "main");
  const safePinnedRef = useMemo(() => normalizeGitRef(refDraft), [refDraft]);
  const hasRefError = usePinnedRef && !safePinnedRef;
  const ready =
    userOSLoaded &&
    installModeLoaded &&
    moduleProfileLoaded &&
    moduleSelectionLoaded &&
    acfsRefLoaded &&
    vpsIPLoaded &&
    sshUsernameLoaded &&
    vpsReadinessSelectionLoaded;
  const modulePlan = useMemo(() => resolveModuleSelection(moduleSelection), [moduleSelection]);
  const selectedProfile = manifestSelectionProfiles.find((profile) => profile.id === moduleProfile);
  const effectiveInstallMode = reviewedInstallation?.mode ?? selectedProfile?.mode ?? installMode;
  const canBuildInstall =
    ready && vpsIP !== null && !hasRefError && modulePlan.ok && modulePlan.selectedCount > 0;
  const effectiveRef = usePinnedRef ? safePinnedRef : null;
  const effectiveUserOS = userOS ?? "mac";
  const effectiveVpsIP = vpsIP ?? "";
  const effectiveSSHUsername = sshUsername.trim() || "ubuntu";
  const effectiveProviderSelection = useMemo(
    () =>
      reviewedInstallation
        ? {
            ...(vpsReadinessSelection ?? DEFAULT_VPS_READINESS_SELECTION),
            ubuntuVersion: reviewedInstallation.ubuntuVersion,
          }
        : (vpsReadinessSelection ?? DEFAULT_VPS_READINESS_SELECTION),
    [reviewedInstallation, vpsReadinessSelection],
  );
  const reconnectCommand = useMemo(
    () => `ssh -i ~/.ssh/acfs_ed25519 ${formatSshTarget(effectiveSSHUsername, effectiveVpsIP)}`,
    [effectiveSSHUsername, effectiveVpsIP],
  );
  const effectiveSourceRef = useMemo(
    () => (usePinnedRef && safePinnedRef ? safePinnedRef : "main"),
    [usePinnedRef, safePinnedRef],
  );

  const handlePinnedRefToggle = useCallback(
    (checked: boolean) => {
      if (reviewedInstallation) return;
      if (!checked) {
        setPinEditorOpen(false);
        setRefDraftOverride(null);
        setPinnedRef(null);
        return;
      }
      const nextRef = pinnedRef ?? "main";
      setRefDraftOverride(nextRef);
      setPinEditorOpen(true);
      if (!pinnedRef || !pinnedRef.trim()) {
        setPinnedRef("main");
      }
    },
    [pinnedRef, setPinnedRef, reviewedInstallation],
  );

  const handlePinnedRefChange = useCallback(
    (value: string) => {
      if (reviewedInstallation) return;
      setPinEditorOpen(true);
      setRefDraftOverride(value);

      const trimmed = value.trim();
      if (!trimmed) {
        setPinnedRef(null);
        return;
      }

      const normalized = normalizeGitRef(trimmed);
      if (normalized) {
        setPinnedRef(normalized);
      }
    },
    [setPinnedRef, reviewedInstallation],
  );

  // One validated selection drives every executable command and exported artifact.
  // Never turn an invalid draft into a default/full installation or a main ref.
  const installDetails = useMemo(
    () =>
      canBuildInstall
        ? buildInstallCommandDetails(
            effectiveInstallMode,
            effectiveRef,
            effectiveSSHUsername,
            moduleSelection,
          )
        : null,
    [canBuildInstall, effectiveInstallMode, effectiveRef, effectiveSSHUsername, moduleSelection],
  );
  const canGenerateInstall =
    canBuildInstall &&
    (!reviewedInstallation || installDetails?.command === reviewedInstallation.command);
  const installCommand = canGenerateInstall ? (installDetails?.command ?? null) : null;
  // The cache is consumed AFTER Ubuntu auto-upgrade. Preserve the original
  // provisioning image in exports, but cache for the actual command destination.
  const installerTargetUbuntuVersion = installDetails?.targetUbuntu;
  const checkpointInput = useMemo(
    () =>
      installCommand
        ? {
            command: installCommand,
            host: effectiveVpsIP,
            manifestSha256: manifestProvenance.manifestSha256,
            checksumsYamlSha256: manifestProvenance.checksumsYamlSha256,
          }
        : null,
    [
      installCommand,
      effectiveVpsIP,
      manifestProvenance.manifestSha256,
      manifestProvenance.checksumsYamlSha256,
    ],
  );
  const { data: checkpoint, isError: checkpointError } = useQuery({
    queryKey: ["installerCheckpoint", checkpointInput],
    queryFn: () => createInstallerCheckpoint(checkpointInput!),
    enabled: checkpointInput !== null,
    staleTime: Infinity,
    retry: false,
  });
  const currentCheckpoint = installerCheckpointMatches(checkpoint, checkpointInput)
    ? checkpoint
    : null;
  const completionKey = currentCheckpoint ? `acfs-command-${currentCheckpoint.persistKey}` : null;
  // No migration from the old unbound boolean: it cannot identify the host,
  // command or manifest the user acknowledged. Share the card's exact scoped key.
  const { data: installerAcknowledged = false } = useQuery({
    queryKey: commandCompletionKeys.completion(completionKey ?? "unbound-run-installer"),
    queryFn: () => completionKey !== null && safeGetItem(completionKey) === "true",
    enabled: completionKey !== null,
    placeholderData: false,
  });
  const canContinue =
    canGenerateInstall && currentCheckpoint !== null && installerAcknowledged && !isNavigating;
  const cacheTransferTarget = useMemo(
    () => formatSshTarget("root", effectiveVpsIP),
    [effectiveVpsIP],
  );
  const cachedInstallCommand = useMemo(
    () =>
      installCommand
        ? `${installCommand} --verified-installer-cache "${VERIFIED_INSTALLER_CACHE_PATH}"`
        : null,
    [installCommand],
  );
  const handoffRunbook = useMemo(
    () =>
      canGenerateInstall
        ? buildHandoffRunbook({
            ip: effectiveVpsIP,
            os: effectiveUserOS,
            username: effectiveSSHUsername,
            mode: effectiveInstallMode,
            ref: effectiveRef,
            moduleSelection,
          })
        : null,
    [
      canGenerateInstall,
      effectiveVpsIP,
      effectiveUserOS,
      effectiveSSHUsername,
      effectiveInstallMode,
      effectiveRef,
      moduleSelection,
    ],
  );
  const providerProvisioningPacket = useMemo(
    () =>
      canGenerateInstall
        ? buildProviderProvisioningPacket({
            ...effectiveProviderSelection,
            installMode: effectiveInstallMode,
            sourceRef: effectiveSourceRef,
            username: effectiveSSHUsername,
            targetHost: effectiveVpsIP,
            moduleSelection,
          })
        : null,
    [
      canGenerateInstall,
      effectiveInstallMode,
      effectiveSourceRef,
      effectiveSSHUsername,
      effectiveVpsIP,
      effectiveProviderSelection,
      moduleSelection,
    ],
  );
  const teamProfile = useMemo(
    () =>
      canGenerateInstall
        ? buildTeamProfile({
            ip: effectiveVpsIP,
            os: effectiveUserOS,
            username: effectiveSSHUsername,
            mode: effectiveInstallMode,
            ref: effectiveRef,
            providerSelection: effectiveProviderSelection,
            architecture: reviewedInstallation?.architecture,
            moduleSelection,
          })
        : null,
    [
      canGenerateInstall,
      effectiveVpsIP,
      effectiveUserOS,
      effectiveSSHUsername,
      effectiveInstallMode,
      effectiveRef,
      effectiveProviderSelection,
      reviewedInstallation,
      moduleSelection,
    ],
  );

  // Analytics tracking for this wizard step
  const { markComplete } = useWizardAnalytics({
    step: "run_installer",
    stepNumber: 9,
    stepTitle: "Run Installer",
  });

  useEffect(() => {
    if (!ready) return;

    const completedSteps = getCompletedSteps();
    if (!canAccessWizardStep(completedSteps, 9)) {
      const redirectStep = getNextReachableWizardStep(completedSteps);
      router.replace(withCurrentSearch(`/wizard/${redirectStep.slug}`));
      return;
    }

    if (vpsIP === null) {
      router.replace(withCurrentSearch("/wizard/create-vps"));
    }
  }, [ready, router, vpsIP]);

  const handleContinue = useCallback(() => {
    if (!canContinue) return;
    markComplete();
    markStepComplete(9);
    setIsNavigating(true);
    router.push(withCurrentSearch("/wizard/reconnect-ubuntu"));
  }, [canContinue, router, markComplete]);
  useEffect(() => {
    return () => {
      if (downloadStatusTimerRef.current) {
        clearTimeout(downloadStatusTimerRef.current);
      }
    };
  }, []);

  // Downloads a handoff artifact and announces the outcome in the role="status"
  // line under the buttons. When the browser cannot start a download, the text
  // is copied to the clipboard instead so nothing is silently lost.
  const saveArtifact = useCallback(async (filename: string, contents: string, mimeType: string) => {
    const downloaded = downloadTextFile(filename, contents, mimeType);
    let message: string;
    if (downloaded) {
      message = `Saved ${filename}`;
    } else {
      const copied = await copyTextToClipboard(contents);
      message = copied
        ? `Download failed — copied the contents of ${filename} to your clipboard instead`
        : `Download failed — copy the text instead (${filename})`;
    }
    setDownloadStatus(message);
    if (downloadStatusTimerRef.current) {
      clearTimeout(downloadStatusTimerRef.current);
    }
    downloadStatusTimerRef.current = setTimeout(() => {
      setDownloadStatus(null);
      downloadStatusTimerRef.current = null;
    }, 6000);
  }, []);
  const handleRunbookDownload = useCallback(
    (format: "json" | "markdown") => {
      if (!handoffRunbook) return;
      if (format === "json") {
        void saveArtifact(
          "acfs-handoff-runbook.json",
          serializeHandoffRunbookJson(handoffRunbook),
          "application/json",
        );
        return;
      }

      void saveArtifact(
        "acfs-handoff-runbook.md",
        formatHandoffRunbookMarkdown(handoffRunbook),
        "text/markdown",
      );
    },
    [handoffRunbook, saveArtifact],
  );
  const handleProviderPacketDownload = useCallback(() => {
    if (!providerProvisioningPacket) return;
    void saveArtifact(
      "acfs-provider-provisioning-packet.json",
      serializeProviderProvisioningPacketJson(providerProvisioningPacket),
      "application/json",
    );
  }, [providerProvisioningPacket, saveArtifact]);
  const handleTeamProfileDownload = useCallback(
    (format: "json" | "markdown") => {
      if (!teamProfile) return;
      if (format === "json") {
        void saveArtifact(
          "acfs-team-profile.json",
          serializeTeamProfileJson(teamProfile),
          "application/json",
        );
        return;
      }

      void saveArtifact(
        "acfs-team-profile-review.md",
        formatTeamProfileReviewMarkdown(teamProfile),
        "text/markdown",
      );
    },
    [teamProfile, saveArtifact],
  );

  const forwardCtaRef = useWizardForwardNav({
    onContinue: handleContinue,
    disabled: !canContinue,
    loading: isNavigating,
    label: "Installation finished",
  });

  if (!ready || vpsIP === null) {
    return (
      <div className="flex items-center justify-center py-12">
        <Rocket className="h-8 w-8 animate-pulse text-muted-foreground" />
      </div>
    );
  }

  return (
    <div className="space-y-8">
      {/* Header with sparkle */}
      <div className="space-y-2">
        <div className="flex items-center gap-3">
          <div className="relative flex h-12 w-12 items-center justify-center rounded-xl bg-gradient-to-br from-primary/30 to-magenta/30 shadow-lg shadow-primary/20">
            <Rocket className="h-6 w-6 text-primary" />
            <Sparkles className="absolute -right-1 -top-1 h-4 w-4 text-amber animate-pulse" />
          </div>
          <div>
            <h1 className="bg-gradient-to-r from-primary via-foreground to-magenta bg-clip-text text-2xl font-bold tracking-tight text-transparent sm:text-3xl">
              Run the Agent Flywheel installer
            </h1>
            <p className="text-sm text-muted-foreground">
              15–25 min (+30–60 min per Ubuntu upgrade hop)
            </p>
          </div>
        </div>
        <p className="text-lg text-muted-foreground">
          One command installs the profile you review below, including its required dependencies.
        </p>
      </div>

      {/* Connected user check */}
      <AlertCard variant="info" title="Confirm you're SSH'd into your VPS">
        <div className="space-y-2">
          <p>
            For a fresh VPS, your terminal prompt should look like{" "}
            <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">root@vps:~#</code>. Run
            this command from that root session; ACFS creates the{" "}
            <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">
              {effectiveSSHUsername}
            </code>{" "}
            user automatically during installation.
          </p>
          <p className="text-sm text-muted-foreground">
            If you are resuming after a partial install and the installer log explicitly tells you
            to continue as{" "}
            <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">
              {effectiveSSHUsername}
            </code>
            , reconnect as that user and run the resume command from the log. Otherwise, stay in the
            root session and re-run the command below; it is designed to resume safely.
          </p>
        </div>
      </AlertCard>

      {/* Warning */}
      <AlertCard variant="warning" title="Don't close the terminal">
        Stay connected during installation. If disconnected, <Jargon term="ssh">SSH</Jargon> back in
        and check if it&apos;s still running.
      </AlertCard>

      {/* SSH key behavior */}
      <AlertCard variant="info" title="SSH keys are handled automatically">
        <div className="space-y-3">
          <p>
            If you connected to root with a password and root has no SSH key yet, the installer may
            ask you to paste the public key you generated earlier. Paste the single line from{" "}
            <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">
              ~/.ssh/acfs_ed25519.pub
            </code>{" "}
            and press Enter.
          </p>
          <p>
            If your root account already has SSH keys, ACFS copies them to the{" "}
            <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">
              {effectiveSSHUsername}
            </code>{" "}
            user it creates.
          </p>
          <p className="text-sm text-muted-foreground">
            If you press Enter to skip the key prompt, finish the install and follow the red SSH-key
            command in the final summary before trying to reconnect as{" "}
            <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">
              {effectiveSSHUsername}
            </code>
            . If the same public key appears more than once from earlier setup attempts, ACFS keeps
            exact duplicates from being copied again.
          </p>
        </div>
      </AlertCard>

      {/* The command */}
      <div className="space-y-4">
        <h2 className="text-xl font-semibold">Paste this command in your SSH session</h2>

        <div className="space-y-3 rounded-lg border border-border/50 bg-card/50 p-4">
          <label htmlFor="installer-profile" className="block text-sm font-medium">
            Installation profile
          </label>
          <select
            id="installer-profile"
            value={moduleProfile}
            disabled={reviewedInstallation !== null}
            onChange={(event) => {
              if (reviewedInstallation) return;
              const profile = manifestSelectionProfiles.find(
                (item) => item.id === event.target.value,
              );
              if (profile) setModuleProfile(profile.id);
            }}
            aria-describedby="installer-profile-summary"
            className="min-h-11 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
          >
            {manifestSelectionProfiles.map((profile) => (
              <option key={profile.id} value={profile.id}>
                {profile.label}
              </option>
            ))}
          </select>
          <p id="installer-profile-summary" role="status" className="text-sm text-muted-foreground">
            {modulePlan.ok
              ? `${modulePlan.selectedCount} of ${modulePlan.availableCount} modules selected. Install mode: ${effectiveInstallMode}.`
              : "This profile cannot produce an executable installation plan."}{" "}
            The installer, cached command, runbook, provider packet, and team profile use this same
            selection.
            {reviewedInstallation &&
              " Exact module and skip overrides from the reviewed file remain active. Discard the reviewed installation before changing its choices."}
          </p>
          {modulePlan.warnings.map((warning, index) => (
            <p key={index} className="text-xs text-muted-foreground">
              {warning}
            </p>
          ))}
        </div>

        {/* Pinned ref toggle (bd-31ps.8.2) */}
        <div className="rounded-lg border border-border/50 bg-card/50 p-4 space-y-3">
          {/* The whole row is the label so the 16px box gets a 44px tap target. */}
          <label htmlFor="pin-ref" className="flex min-h-11 cursor-pointer items-start gap-3 py-2">
            <Checkbox
              id="pin-ref"
              checked={usePinnedRef}
              disabled={reviewedInstallation !== null}
              onCheckedChange={(checked) =>
                handlePinnedRefToggle(checked ? checked !== "indeterminate" : false)
              }
              className="mt-0.5"
            />
            <span className="flex-1 space-y-1">
              <span className="flex items-center gap-2 text-sm font-medium">
                <Pin className="h-4 w-4 text-muted-foreground" />
                Pin to specific version
              </span>
              <span className="block text-xs text-muted-foreground">
                Use a specific commit or tag for reproducible installs across multiple machines.
              </span>
            </span>
          </label>

          {usePinnedRef && (
            <div className="ml-7 space-y-2">
              <div className="flex items-center gap-2">
                <input
                  type="text"
                  value={refDraft}
                  disabled={reviewedInstallation !== null}
                  onChange={(e) => handlePinnedRefChange(e.target.value)}
                  placeholder="main, v1.0.0, or commit SHA"
                  aria-label="Git ref to pin the installer to"
                  aria-invalid={hasRefError || undefined}
                  aria-describedby={hasRefError ? "pin-ref-error" : undefined}
                  autoComplete="off"
                  spellCheck={false}
                  className="flex-1 rounded-md border border-input bg-background px-3 py-1.5 text-sm font-mono placeholder:text-muted-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary aria-invalid:border-destructive aria-invalid:ring-destructive/30"
                />
              </div>
              <div className="flex items-start gap-1.5 text-xs text-muted-foreground">
                <Info className="h-3.5 w-3.5 mt-0.5 shrink-0" />
                <span>
                  Use <code className="rounded bg-muted px-1 py-0.5">main</code> for latest, a tag
                  like <code className="rounded bg-muted px-1 py-0.5">v1.0.0</code> for stable
                  releases, or a full SHA for exact reproducibility.
                </span>
              </div>
              {hasRefError && (
                <p id="pin-ref-error" role="alert" className="text-xs text-destructive">
                  Invalid ref format. Allowed characters: letters, numbers,{" "}
                  <code className="rounded bg-muted px-1 py-0.5">.</code>,
                  <code className="rounded bg-muted px-1 py-0.5">_</code>,{" "}
                  <code className="rounded bg-muted px-1 py-0.5">-</code>, and{" "}
                  <code className="rounded bg-muted px-1 py-0.5">/</code>. Enter a valid ref or turn
                  off pinning; no installer command or handoff artifact is available until then.
                </p>
              )}
            </div>
          )}
        </div>

        {installCommand ? (
          <CommandCard
            key={currentCheckpoint?.persistKey ?? "preparing-installer-checkpoint"}
            command={installCommand}
            description="Agent Flywheel installer one-liner"
            runLocation="vps"
            showCheckbox={currentCheckpoint !== null}
            persistKey={currentCheckpoint?.persistKey}
            className="border-2 border-primary/20"
          />
        ) : (
          <div
            role="alert"
            className="rounded-lg border border-destructive/40 bg-destructive/10 p-4 text-sm"
          >
            <p className="font-semibold">Installation command blocked</p>
            {hasRefError && (
              <p>Fix the pinned ref before copying commands or exporting artifacts.</p>
            )}
            {modulePlan.errors.map((error, index) => (
              <p key={index}>{error}</p>
            ))}
            {modulePlan.ok && modulePlan.selectedCount === 0 && (
              <p>Select a profile with at least one module.</p>
            )}
          </div>
        )}
        {installCommand && !currentCheckpoint && (
          <p role={checkpointError ? "alert" : "status"} className="text-sm text-muted-foreground">
            {checkpointError
              ? "This browser could not prepare the installation acknowledgement. Reload the wizard over HTTPS in a browser with secure hashing support. No earlier acknowledgement will be reused."
              : "Preparing the acknowledgement for this host and installer command..."}
          </p>
        )}
        {installCommand && currentCheckpoint && (
          <p className="text-xs text-muted-foreground">
            Acknowledge only after this command finishes on this VPS. Changing the profile, mode,
            pinned ref, username, or host requires an acknowledgement for that context.
          </p>
        )}
      </div>

      <AlertCard variant="info" icon={Download} title="Save handoff artifacts">
        <div className="space-y-3">
          <p className="text-sm">
            Download local artifacts with the exact installer command, redacted SSH recovery
            commands, provider readiness choices, team profile defaults, and support-bundle
            reference.
          </p>
          {/* Three columns max: five columns in the 672px wizard column
              truncated every label ("Runbook J", "Team Prof"). */}
          <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
            <Button
              type="button"
              variant="outline"
              className="justify-start gap-2"
              onClick={() => handleRunbookDownload("json")}
              disabled={!handoffRunbook}
              aria-label="Runbook JSON — download JSON handoff runbook"
            >
              <FileJson className="h-4 w-4" />
              Runbook JSON
            </Button>
            <Button
              type="button"
              variant="outline"
              className="justify-start gap-2"
              onClick={() => handleRunbookDownload("markdown")}
              disabled={!handoffRunbook}
              aria-label="Runbook Markdown — download Markdown handoff runbook"
            >
              <FileText className="h-4 w-4" />
              Runbook Markdown
            </Button>
            <Button
              type="button"
              variant="outline"
              className="justify-start gap-2"
              onClick={handleProviderPacketDownload}
              disabled={!providerProvisioningPacket}
              aria-label="Provider Packet — download the provider provisioning packet as JSON"
            >
              <FileJson className="h-4 w-4" />
              Provider Packet
            </Button>
            <Button
              type="button"
              variant="outline"
              className="justify-start gap-2"
              onClick={() => handleTeamProfileDownload("json")}
              disabled={!teamProfile}
              aria-label="Team Profile — download the redacted team profile as JSON"
            >
              <FileJson className="h-4 w-4" />
              Team Profile
            </Button>
            <Button
              type="button"
              variant="outline"
              className="justify-start gap-2"
              onClick={() => handleTeamProfileDownload("markdown")}
              disabled={!teamProfile}
              aria-label="Profile Review — download the team profile review as Markdown"
            >
              <FileText className="h-4 w-4" />
              Profile Review
            </Button>
          </div>
          {/* Always rendered so the live region exists before its first message. */}
          <p
            role="status"
            aria-live="polite"
            className={downloadStatus ? "text-xs font-medium text-foreground" : "sr-only"}
          >
            {downloadStatus ?? ""}
          </p>
          <p className="text-xs text-muted-foreground">
            Host addresses and provider credentials are redacted; keep the real values in your
            provider console or password manager.
          </p>
        </div>
      </AlertCard>

      {/* Connection drop reassurance */}
      <AlertCard variant="info" icon={Wifi} title="What if my connection drops?">
        <div className="space-y-2">
          <p>
            <strong>Don&apos;t panic!</strong> If your SSH connection drops during installation:
          </p>
          <ol className="list-decimal list-inside space-y-1 text-sm">
            <li>SSH back into the VPS</li>
            <li>Check the latest ACFS log to see whether installation is still active</li>
            <li>
              If it stopped, run the same installer command again so the checkpointed install can
              resume
            </li>
          </ol>
          <p className="text-sm text-muted-foreground">
            The installer is designed to be run multiple times safely. If anything fails, you can
            always re-run it.
          </p>
        </div>
      </AlertCard>

      {/* Transparency & trust */}
      <div className="flex gap-3 rounded-xl border border-green/25 bg-green/5 p-3 sm:p-4">
        <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-green/15 sm:h-9 sm:w-9">
          <ShieldCheck className="h-4 w-4 text-green sm:h-5 sm:w-5" />
        </div>
        <div className="min-w-0 space-y-2">
          <p className="text-[13px] font-medium leading-tight text-green sm:text-sm">
            Fully transparent &amp; open source
          </p>
          <p className="text-[12px] leading-relaxed text-muted-foreground sm:text-[13px]">
            This script only runs on <strong className="text-foreground/80">your VPS</strong>, not
            your local computer. You can inspect every line before running it:
          </p>
          <div className="flex flex-wrap gap-2">
            <TrackedLink
              href={`https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/blob/${effectiveSourceRef}/install.sh`}
              trackingId="install-sh-source"
              className="inline-flex items-center gap-1.5 rounded-lg border border-primary/30 bg-primary/10 px-2.5 py-1.5 text-xs font-medium text-primary transition-colors hover:bg-primary/20"
            >
              <Code className="h-3 w-3" />
              View install.sh source
              <ExternalLink className="h-2.5 w-2.5" />
            </TrackedLink>
            <TrackedLink
              href="https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup"
              trackingId="github-repo"
              className="inline-flex items-center gap-1.5 rounded-lg border border-border/50 bg-card/50 px-2.5 py-1.5 text-xs font-medium text-muted-foreground transition-colors hover:border-primary/30 hover:text-foreground"
            >
              Full repository
              <ExternalLink className="h-2.5 w-2.5" />
            </TrackedLink>
          </div>
        </div>
      </div>

      {/* Time estimate */}
      <div className="flex items-center gap-2 text-muted-foreground">
        <Clock className="h-5 w-5" />
        <span>
          Takes 15–25 minutes on a current Ubuntu; if your VPS started on an older Ubuntu the
          installer upgrades it first (30–60 minutes per version hop, with reboots)
        </span>
      </div>

      {/* Command breakdown for curious users */}
      <DetailsSection summary="What does this command actually do? (technical breakdown)">
        <div className="space-y-3 text-sm">
          <p className="text-muted-foreground">Here&apos;s what each part of the command means:</p>
          <div className="space-y-4 font-mono text-xs">
            <div>
              <code className="text-primary">curl -fsSL &quot;https://...&quot;</code>
              <p className="mt-1 font-sans text-muted-foreground">
                Downloads the script from GitHub. <code className="text-foreground/80">-f</code> =
                fail on HTTP errors, <code className="text-foreground/80">-s</code> = silent mode,{" "}
                <code className="text-foreground/80">-S</code> = show errors,{" "}
                <code className="text-foreground/80">-L</code> = follow redirects.
              </p>
            </div>
            <div>
              <code className="text-primary">| bash</code>
              <p className="mt-1 font-sans text-muted-foreground">
                Pipes the downloaded script to bash (the shell) to run it.
              </p>
            </div>
            <div>
              <code className="text-primary">-s -- --yes</code>
              <p className="mt-1 font-sans text-muted-foreground">
                Passes <code className="text-foreground/80">--yes</code> to the script, meaning
                &quot;don&apos;t ask for confirmation, just install.&quot;
              </p>
            </div>
            <div>
              <code className="text-primary">--mode {effectiveInstallMode}</code>
              <p className="mt-1 font-sans text-muted-foreground">
                Tells the installer which mode to use based on your wizard selection.
              </p>
            </div>
            {usePinnedRef && safePinnedRef && (
              <div>
                <code className="text-primary">--ref &quot;{safePinnedRef}&quot;</code>
                <p className="mt-1 font-sans text-muted-foreground">
                  Keeps downloaded installer files pinned to{" "}
                  <code className="text-foreground/80">{safePinnedRef}</code>.
                </p>
              </div>
            )}
          </div>
          <AlertCard variant="info" title="Is curl | bash safe?">
            <p className="text-sm">
              You&apos;re right to be cautious! Piping scripts directly to bash is only safe when
              you trust the source. This script is <strong>fully open source</strong> — you can read
              every line before running it. It only runs on your VPS, not your local computer.
            </p>
          </AlertCard>
        </div>
      </DetailsSection>

      {/* Poor-network & Pre-cached Install (Verified Installer Cache) */}
      <DetailsSection summary="Poor connection or slow network? Use a pre-cached installer">
        <div className="space-y-4 text-sm">
          <p className="text-muted-foreground">
            If your VPS has a flaky or slow connection to upstream script hosts, you can pre-build a
            verified installer entrypoint cache on a fast machine and transfer it to the VPS:
          </p>

          {cachedInstallCommand ? (
            <div className="space-y-3">
              <div className="space-y-2">
                <p className="font-semibold text-foreground">
                  1. Build cache on your local/connected machine:
                </p>
                <CommandCard
                  command={`acfs installer-cache build --arch ${reviewedInstallation?.architecture ?? "x86_64"} --ubuntu-version ${installerTargetUbuntuVersion} --output /tmp/acfs-cache`}
                  description="Build the verified installer cache"
                  runLocation="local"
                />
                <p className="text-xs text-muted-foreground">
                  If your VPS uses ARM64, replace{" "}
                  <code className="rounded bg-muted px-1 py-0.5">x86_64</code> with{" "}
                  <code className="rounded bg-muted px-1 py-0.5">aarch64</code>. The cache targets
                  Ubuntu {installerTargetUbuntuVersion}, the installer&apos;s destination after any
                  upgrade, not the older image originally provisioned.
                </p>
              </div>

              <div className="space-y-2">
                <p className="font-semibold text-foreground">
                  2. Transfer cache to your VPS via SCP:
                </p>
                <CommandCard
                  command={`ssh ${cacheTransferTarget} 'install -d -m 700 ${VERIFIED_INSTALLER_CACHE_PATH}'`}
                  description="Create the cache directory on the VPS"
                  runLocation="local"
                />
                <CommandCard
                  command={`scp -r /tmp/acfs-cache/acfs-installer-cache/. ${cacheTransferTarget}:${VERIFIED_INSTALLER_CACHE_PATH}/`}
                  description="Copy the cache to the VPS"
                  runLocation="local"
                />
              </div>

              <div className="space-y-2">
                <p className="font-semibold text-foreground">
                  3. Run installer with cache flag on VPS:
                </p>
                <CommandCard
                  command={cachedInstallCommand}
                  description="Installer one-liner using the local cache"
                  runLocation="vps"
                />
              </div>
            </div>
          ) : (
            <p className="text-destructive">
              Resolve the blocked installation plan above before preparing or using a cache.
            </p>
          )}

          <AlertCard variant="info" title="Cache Boundaries &amp; Requirements">
            <ul className="list-disc list-inside space-y-1 text-xs text-muted-foreground">
              <li>
                <strong>Third-party Entrypoint Protection:</strong> The cache verifies and loads
                SHA-256-approved tool installer scripts locally. The ACFS bootstrap command itself
                is still downloaded from the selected source ref.
              </li>
              <li>
                <strong>Network Still Required:</strong> The VPS still needs basic internet
                connectivity for standard APT packages, Cargo crates, and language registries.
              </li>
              <li>
                <strong>No Secrets or Keys:</strong> The cache contains only public installer
                scripts—credentials, API keys, and tokens are never bundled.
              </li>
            </ul>
          </AlertCard>
        </div>
      </DetailsSection>

      {/* What it installs - collapsible */}
      <DetailsSection summary="What this command installs">
        <p className="mb-3 text-sm text-muted-foreground">
          This is the resolved module list for {selectedProfile?.label ?? "the selected profile"},
          including dependency closure. Tools outside this list are not requested.
        </p>
        <ol className="space-y-2 text-sm">
          {modulePlan.included.map((entry) => (
            <li key={entry.id} className="flex items-start gap-2">
              <Check className="mt-0.5 h-3 w-3 shrink-0 text-green" />
              <div>
                <span className="font-mono">
                  [Phase {entry.phase}] {entry.id}
                </span>
                <p className="text-muted-foreground">
                  {entry.description} — {entry.reason}
                </p>
              </div>
            </li>
          ))}
        </ol>
      </DetailsSection>

      {/* View source */}
      <div className="flex items-center gap-2 text-sm">
        <span className="text-muted-foreground">Want to see exactly what it does?</span>
        <TrackedLink
          href={`https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/blob/${effectiveSourceRef}/install.sh`}
          trackingId="install-sh-source-inline"
          className="inline-flex items-center gap-1 font-medium text-primary hover:underline"
        >
          View install.sh source
          <ExternalLink className="h-3 w-3" />
        </TrackedLink>
      </div>

      {/* Installation output guide */}
      <AlertCard variant="info" title="Understanding the installation output">
        <div className="space-y-2 text-sm">
          <p>You&apos;ll see lots of text scrolling by. Here&apos;s what to look for:</p>
          <ul className="list-inside list-disc space-y-1">
            <li>
              <span className="text-green font-medium">✔ Green checkmarks</span> = Step completed
              successfully
            </li>
            <li>
              <span className="text-amber font-medium">⚠ Yellow warnings</span> = Non-critical
              issue, installer continues
            </li>
            <li>
              <span className="text-destructive font-medium">✖ Red X</span> = Something failed, but
              installer will retry or skip
            </li>
          </ul>
          <p className="text-muted-foreground">
            Just wait for the final &quot;Installation complete&quot; message. If you see errors,
            you can always re-run the installer—it will retry failed steps.
          </p>
        </div>
      </AlertCard>

      {/* Success signs */}
      <OutputPreview title="Expected output (example)">
        <p className="text-green">✔ Agent Flywheel installation complete!</p>
        <p className="text-muted-foreground">Please reconnect as: {reconnectCommand}</p>
      </OutputPreview>

      {/* Beginner Guide */}
      <SimplerGuide>
        <div className="space-y-6">
          <GuideExplain term="What is this command doing?">
            This command downloads and runs a setup script that automatically installs the selected
            profile and its dependencies on your VPS. Review the exact module list above before
            running it; a narrow profile does not install every tool.
            <br />
            <br />
            The script is <Jargon term="idempotent">&quot;idempotent&quot;</Jargon> which means
            it&apos;s safe to run multiple times. If something fails, you can just run it again.
          </GuideExplain>

          <GuideSection title="Step-by-Step">
            <div className="space-y-4">
              <GuideStep number={1} title="Make sure you're in the root shell on your VPS">
                Your <Jargon term="terminal">terminal</Jargon> should show something like{" "}
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">root@vps:~#</code>,
                and the prompt should end with{" "}
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">#</code> before you
                paste the installer.
                <br />
                <br />
                If it shows{" "}
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">
                  ubuntu@vps:~$
                </code>
                , run{" "}
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">sudo -i</code>{" "}
                first. Wait for the prompt to change to{" "}
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">root@vps:~#</code>{" "}
                before running the command. If sudo asks for a password, it wants the ubuntu Linux
                account password, not the VPS root password or your provider website password. If
                you only have the VPS root password, use root SSH or the provider console instead of
                retrying sudo.
                <br />
                <br />
                If it shows your regular computer name, you need to SSH in first!
              </GuideStep>

              <GuideStep number={2} title="Copy the install command">
                Click the copy button on the purple command box above. The command is quite long, so
                make sure you copy the whole thing!
              </GuideStep>

              <GuideStep number={3} title="Paste and run">
                In your SSH terminal (where you&apos;re connected to the VPS), paste the command and
                press <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Enter</kbd>.
                <br />
                <br />
                You&apos;ll see lots of text scrolling by. This is normal!
              </GuideStep>

              <GuideStep number={4} title="Wait patiently (15–25 minutes)">
                The installation takes time because it&apos;s downloading and installing many tools.
                If your VPS started on an older Ubuntu, the installer upgrades it first, which adds
                30–60 minutes per version hop and reboots the VPS. You&apos;ll see progress messages
                scroll by:
                <OutputPreview title="What you'll see" className="mt-3">
                  <p className="text-green">[1/8] Installing zsh + oh-my-zsh...</p>
                  <p className="text-green">[2/8] Installing bun...</p>
                  <p className="text-green">[3/8] Installing development tools...</p>
                  <p className="text-muted-foreground">... lots of download output ...</p>
                  <p className="text-green">[8/8] Installing AI coding agents...</p>
                  <p className="text-green font-medium mt-1">
                    ✔ Agent Flywheel installation complete!
                  </p>
                </OutputPreview>
                <p className="mt-3">
                  <strong>Don&apos;t close the terminal!</strong> Let it run until you see the green
                  &quot;Installation complete&quot; message.
                </p>
              </GuideStep>
            </div>
          </GuideSection>

          <GuideSection title="What gets installed?">
            <p className="mb-3">
              The selected profile requests {modulePlan.selectedCount} modules. Open &ldquo;What
              this command installs&rdquo; above for the exact list and the dependencies added
              automatically. Changing the profile also changes all installer commands and handoff
              exports on this page.
            </p>
          </GuideSection>

          <GuideTip>
            If your internet connection drops during installation, just SSH back in and run the
            command again. The installer will pick up where it left off!
          </GuideTip>

          <GuideCaution>
            <strong>Don&apos;t close the terminal window</strong> while the installation is running.
            If you accidentally close it, SSH back in and run the command again. It will resume from
            where it stopped.
          </GuideCaution>

          <GuideSection title="If Installation Seems Stuck">
            <p className="mb-3">
              Installation can look &quot;stuck&quot; at certain points. Here&apos;s what&apos;s
              actually happening:
            </p>
            <ul className="space-y-3">
              <li>
                <strong>Stuck on &quot;Installing Rust...&quot;</strong> — Rust is a large download
                (~300MB). This step can take 2-5 minutes depending on your VPS speed. Just wait.
              </li>
              <li>
                <strong>Stuck on &quot;Setting up oh-my-zsh...&quot;</strong> — This step downloads
                plugins from GitHub. If GitHub is slow, it can take a minute. Wait it out.
              </li>
              <li>
                <strong>No output for 2+ minutes</strong> — Some steps don&apos;t show progress. If
                the terminal cursor is still blinking, it&apos;s still running. Wait.
              </li>
              <li>
                <strong>Actual error message appears</strong> — If you see red error text or
                &quot;Failed&quot;, SSH back in and run the install command again. The installer
                will skip completed steps and retry the failed one.
              </li>
            </ul>
            <GuideTip className="mt-4">
              If your VPS started on an older Ubuntu, the installer upgrades it first — that phase
              alone takes 30–60 minutes and reboots the VPS; do not re-run during it. To check
              whether it is still working, SSH back in and run{" "}
              <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">
                tail -f ~/.acfs/logs/install-*.log
              </code>{" "}
              (or{" "}
              <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">
                /var/lib/acfs/check_status.sh
              </code>{" "}
              during an upgrade). Re-run the same install command only once the log has stopped for
              10+ minutes; it resumes from the last completed phase.
            </GuideTip>
          </GuideSection>
        </div>
      </SimplerGuide>

      {/* Continue button — unlocked by the installer card's "I ran this
          command" checkbox (mirrors the doctor gate on the status-check step). */}
      <div className="flex flex-col items-end gap-2 pt-4">
        {!installerAcknowledged && (
          <p id="run-installer-continue-hint" className="text-sm text-muted-foreground">
            Tick{" "}
            <span className="font-medium text-foreground">&ldquo;I ran this command&rdquo;</span>{" "}
            under the installer command above to unlock the next step.
          </p>
        )}
        <Button
          ref={forwardCtaRef}
          data-wizard-primary-cta
          onClick={handleContinue}
          disabled={!canContinue}
          aria-describedby={!installerAcknowledged ? "run-installer-continue-hint" : undefined}
          size="lg"
          disableMotion
        >
          {isNavigating ? "Loading..." : "Installation finished"}
        </Button>
      </div>
    </div>
  );
}
