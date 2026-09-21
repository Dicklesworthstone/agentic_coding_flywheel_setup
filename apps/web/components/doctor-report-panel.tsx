"use client";

import Link from "next/link";
import { useEffect, useId, useRef, useState } from "react";
import { CommandCard } from "@/components/command-card";
import { Button } from "@/components/ui/button";
import {
  type DoctorReportContext,
  type DoctorReportCounts,
  DoctorReportError,
  type DoctorReportModuleStatus,
  type DoctorReportReview,
  doctorReportMatches,
  reviewDoctorReportFile,
} from "@/lib/doctorReport";
import { manifestModules, manifestProvenance } from "@/lib/generated/manifest-modules";
import { useInstallationHealth } from "@/lib/hooks/useInstallationHealth";
import { useInstallMode } from "@/lib/userPreferences";
import { withCurrentSearch } from "@/lib/utils";
import { ACFS_RECOMMENDED_UBUNTU } from "@/lib/vpsProviders";

const STATUS_LABELS: Record<DoctorReportModuleStatus, string> = {
  pass: "Reported checks passed",
  fail: "Reported failure",
  warn: "Reported warning",
  timeout: "Check timed out",
  skip: "Check skipped",
  unreported: "No mapped checks",
};
function CountSummary({ value }: { value: Readonly<DoctorReportCounts> }) {
  return (
    <p className="text-sm">
      {value.pass} passed · {value.fail} failed · {value.warn} warnings · {value.timeout} timed out
      · {value.skip} skipped
    </p>
  );
}

/** Keyed by the entire effective context: changed targets unmount pending readers. */
function DoctorReportContent({ context }: { context: DoctorReportContext }) {
  const [review, setReview] = useState<DoctorReportReview | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const generation = useRef(0);
  const mounted = useRef(false);
  const id = useId();
  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
      generation.current++;
    };
  }, []);
  const current = doctorReportMatches(review, context) ? review : null;

  function clear(): void {
    if (!mounted.current) return;
    generation.current++;
    setReview(null);
    setError(null);
    setBusy(false);
  }
  async function read(file: File | undefined): Promise<void> {
    if (!file || !mounted.current) return;
    const request = ++generation.current;
    setReview(null);
    setError(null);
    setBusy(true);
    try {
      const next = await reviewDoctorReportFile(file, context);
      if (mounted.current && request === generation.current) setReview(next);
    } catch (failure) {
      if (mounted.current && request === generation.current) {
        setError(
          failure instanceof DoctorReportError
            ? failure.message
            : "The report could not be reviewed. No commands, preferences or completion state were changed.",
        );
      }
    } finally {
      if (mounted.current && request === generation.current) setBusy(false);
    }
  }
  const destinationDiffers =
    current &&
    (current.reportedOS.id !== "ubuntu" || current.reportedOS.version !== ACFS_RECOMMENDED_UBUNTU);
  const selectedFailures = current?.modules.filter((module) => module.status === "fail") ?? [];

  return (
    <details className="rounded-xl border border-border/50 bg-card/30 p-4">
      <summary className="min-h-11 cursor-pointer py-2 text-base font-semibold">
        Diagnose a doctor JSON report locally
      </summary>
      <div className="mt-3 space-y-4">
        <p className="text-sm text-muted-foreground">
          Compare an actual report with your selected installation. Run the command on the intended
          VPS as the configured account, save its JSON output to a local file, then choose that file
          below. Failed checks can still produce a useful report. Do not include terminal prompts or
          other output.
        </p>
        <CommandCard
          command="acfs doctor --json"
          description="Capture a doctor report on the VPS"
          runLocation="vps"
        />
        <p className="text-sm text-muted-foreground">
          Reports can contain private paths or credentials. This reader does not upload or persist
          the file, display raw details or suggested shell fixes, run commands, or mark the doctor
          checkbox complete. The report cannot prove which host or installation produced it; confirm
          its origin yourself.
        </p>
        <label htmlFor={`${id}-report`} className="block space-y-2 text-sm">
          <span>Doctor JSON report (maximum 1 MiB)</span>
          <input
            id={`${id}-report`}
            type="file"
            accept=".json,application/json"
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
            Reading and comparing the local doctor report...
          </p>
        )}
        {error && (
          <p role="alert" className="text-sm text-destructive">
            {error}
          </p>
        )}
        {(busy || review || error) && (
          <Button type="button" variant="outline" onClick={clear}>
            Clear doctor report
          </Button>
        )}
        {current && (
          <div className="space-y-4 border-t border-border/50 pt-4">
            <h2 className="text-lg font-semibold">Reported findings for your selection</h2>
            <p role="status" className="text-sm">
              {current.needsAttention || destinationDiffers
                ? "Findings, coverage gaps or context differences need review."
                : "Mapped checks report passes. This is not a complete or authenticated verification of the installation."}
            </p>
            <p className="break-all font-mono text-xs">Report SHA-256: {current.sourceSha256}</p>
            <p className="text-sm text-muted-foreground">
              Report timestamp: {current.reportedAt}. Reported OS: {current.reportedOS.id}{" "}
              {current.reportedOS.version}. Host identity and installation provenance are not
              verified.
            </p>
            {!current.userMatches && (
              <p role="alert" className="text-sm text-destructive">
                The reported account does not match the configured installation account. Capture a
                report as the intended user.
              </p>
            )}
            {!current.modeMatches && (
              <p role="alert" className="text-sm text-destructive">
                The reported installation mode differs from your current selection. Check the source
                report and installer state.
              </p>
            )}
            {current.freshnessAtRead !== "recent" && (
              <p role="alert" className="text-sm text-destructive">
                {current.freshnessAtRead === "stale"
                  ? "This report was over 24 hours old when read. Capture a fresh report before making recovery decisions."
                  : "This report was more than five minutes in the future when read. Check both clocks and capture a fresh report."}
              </p>
            )}
            {destinationDiffers && (
              <p role="alert" className="text-sm text-destructive">
                The reported OS differs from the recommended Ubuntu {ACFS_RECOMMENDED_UBUNTU}{" "}
                destination. Inspect upgrade/resume state; this is not an instruction to start
                another upgrade.
              </p>
            )}
            <div className="space-y-2">
              <h3 className="text-sm font-semibold">All checks in the report</h3>
              <CountSummary value={current.totals} />
            </div>
            <p className="text-sm text-muted-foreground">
              Each row aggregates only checks mapped to that module. A pass does not establish that
              every required check ran. Skipped, timed-out and absent checks remain unverified;
              unmapped checks may include important system or authentication findings. Inspect the
              original report privately for details.
            </p>
            <div
              className="max-h-96 overflow-auto rounded-lg border border-border/50"
              tabIndex={0}
              role="region"
              aria-label="Selected module report results"
            >
              <table className="w-full text-left text-sm">
                <caption className="px-3 py-2 text-left">
                  Selected modules, including dependencies
                </caption>
                <thead>
                  <tr>
                    <th scope="col" className="px-3 py-2">
                      Module
                    </th>
                    <th scope="col" className="px-3 py-2">
                      Reported result
                    </th>
                    <th scope="col" className="px-3 py-2">
                      Checks
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {current.modules.map((module) => (
                    <tr key={module.id} className="border-t border-border/30">
                      <th scope="row" className="break-all px-3 py-2 font-mono text-xs font-normal">
                        {module.id}
                      </th>
                      <td className="px-3 py-2">{STATUS_LABELS[module.status]}</td>
                      <td className="px-3 py-2">{module.checkCount}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="space-y-3">
              <div>
                <h3 className="text-sm font-semibold">Known modules outside your selection</h3>
                <CountSummary value={current.outsideSelection} />
              </div>
              <div>
                <h3 className="text-sm font-semibold">Unmapped / system checks</h3>
                <CountSummary value={current.unmapped} />
              </div>
              <p className="text-sm text-muted-foreground">
                Outside-selection findings do not authorize installing excluded modules. Unmapped
                failures are not ignored or treated as successes. This comparison never executes a
                report&apos;s fix field.
              </p>
            </div>
            {selectedFailures.length > 0 && (
              <div className="space-y-2 rounded-lg border border-border/50 p-3">
                <h3 className="text-sm font-semibold">
                  Review recovery for {selectedFailures.length} selected modules
                </h3>
                <p className="break-words font-mono text-xs">
                  {selectedFailures.map((module) => module.id).join(", ")}
                </p>
                <p className="text-sm text-muted-foreground">
                  Inspect the private report and installation logs first. Wait for any active
                  install or upgrade to finish. The existing retry on this page preserves your exact
                  selected installation; a report alone is not permission to replay an installer or
                  broaden the selection.
                </p>
                <Link
                  href={withCurrentSearch("/wizard/run-installer")}
                  className="inline-flex min-h-11 items-center underline"
                >
                  Review the exact installation and recovery instructions
                </Link>
              </div>
            )}
          </div>
        )}
      </div>
    </details>
  );
}

/** The ordinary health workflow remains independent; file review never sets acknowledgements. */
export function DoctorReportPanel() {
  const health = useInstallationHealth();
  const [mode, , modeLoaded] = useInstallMode();
  if (!health.ready || !modeLoaded) {
    return (
      <p role="status" className="text-sm text-muted-foreground">
        Loading installation context for local report review...
      </p>
    );
  }
  if (!health.vpsIP || !health.reinstallCommand || !health.selectedPlan?.ok) {
    return (
      <p role="status" className="text-sm text-muted-foreground">
        Review the target and selected installation before loading a doctor report. No report is
        read while the plan is blocked.
      </p>
    );
  }
  const context: DoctorReportContext = {
    host: health.vpsIP,
    username: health.sshUsername,
    mode,
    installerCommand: health.reinstallCommand,
    manifestSha256: manifestProvenance.manifestSha256,
    checksumsYamlSha256: manifestProvenance.checksumsYamlSha256,
    selectedModuleIds: health.selectedPlan.included.map((module) => module.id).sort(),
    knownModuleIds: manifestModules.map((module) => module.id).sort(),
  };
  // This key stays in React memory only. A change, including A -> B -> A, destroys
  // the old reader instead of letting a delayed result or previous review revive.
  return <DoctorReportContent key={JSON.stringify(context)} context={context} />;
}
