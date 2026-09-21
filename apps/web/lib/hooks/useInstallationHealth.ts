"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useMemo, useState } from "react";
import { COMMAND_COMPLETION_CHANGED_EVENT, commandCompletionKeys } from "@/components/command-card";
import { buildInstallCommand } from "@/lib/commandBuilder";
import { manifestProvenance } from "@/lib/generated/manifest-modules";
import { isValidIP, normalizeGitRef, normalizeSSHUsername } from "@/lib/inputValidation";
import {
  createDoctorCheckpoint,
  type DoctorCheckpoint,
  type DoctorCheckpointInput,
  doctorCheckpointMatches,
} from "@/lib/installerCheckpoint";
import { resolveModuleSelection } from "@/lib/moduleSelection";
import {
  useACFSRef,
  useInstallMode,
  useModuleSelection,
  useSSHUsername,
  useVPSIP,
} from "@/lib/userPreferences";
import { safeGetItem } from "@/lib/utils";
import { useWizardInstallation } from "@/lib/wizardInstallation";

export const DOCTOR_COMMAND = "acfs doctor";

/**
 * Rebuild the same health context on Status Check and Onboarding. Only opaque
 * acknowledgement keys enter Query/storage; raw host/command/hash inputs and
 * asynchronous checkpoint results remain local component state.
 */
export function useInstallationHealth() {
  const queryClient = useQueryClient();
  const [vpsIP, , vpsIPLoaded] = useVPSIP();
  const [sshUsername, , sshUsernameLoaded] = useSSHUsername();
  const [installMode, , installModeLoaded] = useInstallMode();
  const [acfsRef, , acfsRefLoaded] = useACFSRef();
  const [moduleSelection, moduleSelectionLoaded] = useModuleSelection();
  const session = useWizardInstallation();
  const { manifestSha256, checksumsYamlSha256 } = manifestProvenance;
  const ready =
    vpsIPLoaded &&
    sshUsernameLoaded &&
    installModeLoaded &&
    acfsRefLoaded &&
    moduleSelectionLoaded &&
    (!session || session.status === "saved" || session.status === "active");
  const selectedPlan = useMemo(
    () => (ready ? resolveModuleSelection(moduleSelection) : null),
    [ready, moduleSelection],
  );
  const reinstallCommand = useMemo(() => {
    if (
      !ready ||
      !selectedPlan?.ok ||
      !isValidIP(vpsIP ?? "") ||
      normalizeSSHUsername(sshUsername) !== sshUsername ||
      !["safe", "vibe"].includes(installMode) ||
      (acfsRef !== null && normalizeGitRef(acfsRef) !== acfsRef)
    )
      return null;
    try {
      const command = buildInstallCommand(installMode, acfsRef, sshUsername, moduleSelection);
      if (
        session?.status === "active" &&
        (!session.installation || command !== session.installation.command)
      )
        return null;
      return command;
    } catch {
      return null;
    }
  }, [ready, selectedPlan, vpsIP, sshUsername, installMode, acfsRef, moduleSelection, session]);
  const checkpointInput = useMemo<DoctorCheckpointInput | null>(
    () =>
      reinstallCommand && vpsIP
        ? {
            command: reinstallCommand,
            doctorCommand: DOCTOR_COMMAND,
            host: vpsIP,
            manifestSha256,
            checksumsYamlSha256,
          }
        : null,
    [reinstallCommand, vpsIP, manifestSha256, checksumsYamlSha256],
  );
  const [checkpoint, setCheckpoint] = useState<DoctorCheckpoint>();
  const [hashFailure, setHashFailure] = useState<DoctorCheckpointInput | null>(null);
  useEffect(() => {
    let current = true;
    if (checkpointInput) {
      void createDoctorCheckpoint(checkpointInput)
        .then((value) => {
          if (current) {
            setCheckpoint(value);
            setHashFailure(null);
          }
        })
        .catch(() => {
          if (current) setHashFailure(checkpointInput);
        });
    }
    return () => {
      current = false;
    };
  }, [checkpointInput]);
  const activeCheckpoint = doctorCheckpointMatches(checkpoint, checkpointInput) ? checkpoint : null;
  const hashFailed = Boolean(checkpointInput) && hashFailure === checkpointInput;
  const completionKey = activeCheckpoint ? `acfs-command-${activeCheckpoint.persistKey}` : null;
  const { data: acknowledged = false, status: acknowledgementStatus } = useQuery({
    queryKey: completionKey
      ? commandCompletionKeys.completion(completionKey)
      : ["doctor-checkpoint-pending"],
    queryFn: () => (completionKey ? safeGetItem(completionKey) === "true" : false),
    enabled: completionKey !== null,
    staleTime: Infinity,
    gcTime: Infinity,
  });
  // The acknowledging card unmounts on navigation. Keep revocations live on
  // Onboarding too, including localStorage.clear() and same-tab unchecking.
  useEffect(() => {
    if (!completionKey || typeof window === "undefined") return;
    const key = commandCompletionKeys.completion(completionKey);
    const storageChanged = (event: StorageEvent) => {
      if (event.key === null || event.key === completionKey) {
        queryClient.setQueryData(key, safeGetItem(completionKey) === "true");
      }
    };
    const completionChanged = (event: Event) => {
      const detail = (event as CustomEvent<{ key?: string; completed?: unknown }>).detail;
      if (detail?.key === completionKey && typeof detail.completed === "boolean") {
        queryClient.setQueryData(key, detail.completed);
      }
    };
    window.addEventListener("storage", storageChanged);
    window.addEventListener(COMMAND_COMPLETION_CHANGED_EVENT, completionChanged);
    return () => {
      window.removeEventListener("storage", storageChanged);
      window.removeEventListener(COMMAND_COMPLETION_CHANGED_EVENT, completionChanged);
    };
  }, [completionKey, queryClient]);
  const doctorConfirmed =
    Boolean(activeCheckpoint) && acknowledgementStatus === "success" && acknowledged === true;
  const loading =
    !ready ||
    Boolean(checkpointInput && !activeCheckpoint && !hashFailed) ||
    Boolean(activeCheckpoint && acknowledgementStatus === "pending");
  return {
    ready,
    loading,
    vpsIP,
    sshUsername,
    selectedPlan,
    reinstallCommand,
    activeCheckpoint,
    hashFailed,
    completionKey,
    doctorConfirmed,
  };
}
