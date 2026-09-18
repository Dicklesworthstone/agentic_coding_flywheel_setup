"use client";

import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { usePathname } from "next/navigation";
import { Button } from "@/components/ui/button";
import { TeamProfileImportPanel } from "@/components/team-profile-import-panel";
import { buildInstallCommand } from "@/lib/commandBuilder";
import {
  getACFSRef, getInstallMode, getModuleProfile, getSSHUsername, getVPSIP, getVPSReadinessSelection,
  useSavedACFSRef, useSavedInstallMode, useSavedModuleProfile, useSavedSSHUsername,
  useVPSIP, useVPSReadinessSelection,
} from "@/lib/userPreferences";
import {
  activateTeamProfileInstallation, discardTeamProfileInstallation, readTeamProfileSessionGuard,
  teamProfileInstallationMatches, teamProfileReviewMatches, TeamProfileImportError,
  type ApprovedTeamProfileInstallation, type TeamProfileFileReview, type TeamProfileReviewContext,
} from "@/lib/teamProfileImport";
import { WizardInstallationContext, type WizardInstallationSession } from "@/lib/wizardInstallation";

type Active = { installation: ApprovedTeamProfileInstallation; context: TeamProfileReviewContext };
type Guard = ReturnType<typeof readTeamProfileSessionGuard>;
const INITIALIZING = "loading" as const;

function guard(): Guard {
  try { return readTeamProfileSessionGuard(window.sessionStorage); }
  catch { return "unavailable"; }
}

/** Read saved facts, not the hook overlays we expose to installation consumers. */
function currentContext(reviewed: TeamProfileReviewContext): TeamProfileReviewContext {
  return { targetHost: getVPSIP() ?? "", current: {
    providerSelection: getVPSReadinessSelection(), installMode: getInstallMode(),
    ref: getACFSRef(), username: getSSHUsername(),
    architecture: reviewed.current.architecture, ubuntuVersion: reviewed.current.ubuntuVersion,
    moduleSelection: { profile: getModuleProfile() },
  } };
}

/** Root-mounted so client-side wizard navigation never drops the approved choice. */
export function WizardInstallationProvider({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const inWizard = pathname === null || pathname === "/wizard" || pathname?.startsWith("/wizard/") === true;
  const [, , modeReady] = useSavedInstallMode();
  const [, , profileReady] = useSavedModuleProfile();
  const [, , refReady] = useSavedACFSRef();
  const [, , userReady] = useSavedSSHUsername();
  const [, , hostReady] = useVPSIP();
  const [, , providerReady] = useVPSReadinessSelection();
  const ready = modeReady && profileReady && refReady && userReady && hostReady && providerReady;
  const [hydrated, setHydrated] = useState(false);
  const [active, setActive] = useState<Active | null>(null);
  const [reviewRequired, setReviewRequired] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [, refresh] = useState(0);
  const mounted = useRef(false);

  useEffect(() => {
    mounted.current = true;
    // eslint-disable-next-line react-hooks/set-state-in-effect -- browser session hydration
    setHydrated(true);
    const changed = () => refresh((revision) => revision + 1);
    const events = ["storage", "popstate", "pageshow", "focus", "acfs:user-preferences-updated"];
    for (const event of events) window.addEventListener(event, changed);
    return () => {
      mounted.current = false;
      for (const event of events) window.removeEventListener(event, changed);
    };
  }, []);

  // Check synchronously on render (including navigation), before children can
  // expose commands. Events also catch raw preference writes and bfcache return.
  const storedGuard = hydrated ? guard() : INITIALIZING;
  let activeMatches = false;
  if (active && ready && storedGuard === "review_required") {
    try {
      const value = active.installation;
      activeMatches = teamProfileInstallationMatches(value, currentContext(active.context))
        && buildInstallCommand(value.mode, value.ref, value.username, value.moduleSelection) === value.command;
    } catch { activeMatches = false; }
  }
  if (active && hydrated && ready && !activeMatches) {
    // Conditional render-time adjustment prevents even one committed frame of
    // stale commands, and latches invalidation if old preferences are restored.
    setActive(null);
    setReviewRequired(true);
  }
  const status: WizardInstallationSession["status"] = pathname === null || !hydrated || !ready ? "loading"
    : storedGuard === "unavailable" ? "unavailable"
      : active && activeMatches ? "active"
        : reviewRequired || active !== null || storedGuard === "review_required" ? "review_required" : "saved";
  const installation = status === "active" ? active!.installation : null;

  const activate = useCallback((review: TeamProfileFileReview, reviewed: TeamProfileReviewContext, confirmed: boolean) => {
    if (!mounted.current || !ready || !inWizard || pathname === null) {
      throw new TeamProfileImportError("team_profile_context_required", "Wait for the current wizard settings before selecting an installation.");
    }
    const current = currentContext(reviewed);
    if (!teamProfileReviewMatches(review, current)) {
      throw new TeamProfileImportError("team_profile_review_changed", "Saved settings or the target changed. Review the profile again.");
    }
    try {
      const value = activateTeamProfileInstallation(review, current, confirmed, window.sessionStorage);
      if (buildInstallCommand(value.mode, value.ref, value.username, value.moduleSelection) !== value.command) {
        throw new TeamProfileImportError("team_profile_review_changed", "The installation command changed. Review the profile again.");
      }
      setActive({ installation: value, context: current });
      setReviewRequired(false);
      setMessage(null);
    } catch (error) {
      // A failed storage readback may already have written the guard. Never
      // let that failure restore a prior/default executable installation.
      if (guard() !== "clear") { setActive(null); setReviewRequired(true); }
      throw error;
    }
  }, [ready, inWizard, pathname]);

  const discard = useCallback(() => {
    if (!mounted.current) return;
    try {
      discardTeamProfileInstallation(window.sessionStorage);
      setActive(null); setReviewRequired(false); setMessage(null); refresh((revision) => revision + 1);
    } catch {
      setMessage("The pending-profile guard could not be cleared. No saved/default installation has been selected.");
    }
  }, []);
  const blockEdit = useCallback(() => {
    setMessage("Discard the reviewed installation explicitly before editing individual saved settings. Its approved choices have not changed.");
  }, []);
  const session = useMemo<WizardInstallationSession>(() => ({ status, installation, activate, discard, blockEdit }),
    [status, installation, activate, discard, blockEdit]);

  // Public/non-wizard routes keep their original behavior. The root provider
  // still retains an in-memory installation for a later client-side return.
  if (!inWizard) return <>{children}</>;
  const blocked = status === "review_required" || status === "unavailable";
  return <WizardInstallationContext.Provider value={session}>
    {status === "loading" ? <main id="main-content" className="mx-auto max-w-2xl p-8" role="status">
      Loading installation choices...
    </main> : blocked ? <main id="main-content" className="mx-auto max-w-2xl space-y-6 p-8">
      <section role="alert" className="space-y-3 rounded-lg border border-destructive/40 p-4">
        <h1 className="text-xl font-semibold">Review the pending team installation</h1>
        <p>{status === "unavailable"
          ? "The browser session guard cannot be read. Default installation commands are withheld."
          : "This tab has a pending or changed team installation. Reloading never restores approval or silently selects the default installation."}</p>
        <p>Review the file again below, or explicitly discard it to return to your saved wizard settings.</p>
        <Button type="button" variant="outline" onClick={discard}>Discard reviewed installation and use saved settings</Button>
        {message && <p>{message}</p>}
      </section>
      <TeamProfileImportPanel />
    </main> : <>
      {installation && <aside className="mx-auto max-w-3xl space-y-2 border-b border-primary/30 p-4" aria-label="Active reviewed installation">
        <p className="font-semibold">Using reviewed team profile: {installation.displayName}</p>
        <p className="text-sm">The exact reviewed mode, ref, username and module selections apply throughout this wizard tab. Saved preferences are unchanged.</p>
        <Button type="button" variant="outline" onClick={discard}>Discard reviewed installation and use saved settings</Button>
        {message && <p role="alert" className="text-sm">{message}</p>}
      </aside>}
      {children}
    </>}
  </WizardInstallationContext.Provider>;
}
