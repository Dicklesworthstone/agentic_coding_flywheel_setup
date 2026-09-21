"use client";

import { createContext, useCallback, useContext } from "react";
import type {
  ApprovedTeamProfileInstallation,
  TeamProfileFileReview,
  TeamProfileReviewContext,
} from "./teamProfileImport";

/** This context is deliberately outside TanStack Query and its persistence. */
export interface WizardInstallationSession {
  status: "loading" | "saved" | "active" | "review_required" | "unavailable";
  installation: ApprovedTeamProfileInstallation | null;
  activate: (
    review: TeamProfileFileReview,
    context: TeamProfileReviewContext,
    confirmed: boolean,
  ) => void;
  discard: () => void;
  blockEdit: () => void;
}

export const WizardInstallationContext = createContext<WizardInstallationSession | null>(null);

export function useWizardInstallation(): WizardInstallationSession | null {
  return useContext(WizardInstallationContext);
}

/**
 * Overlay only the hook result. Never put imported values in the saved query,
 * localStorage, URLs, or sequential preference writes. Existing settings screens
 * cannot partially edit an active installation: explicit discard comes first.
 */
export function useInstallationPreference<T, S>(
  saved: [T, (value: S) => void, boolean],
  select: (installation: ApprovedTeamProfileInstallation) => T,
): [T, (value: S) => void, boolean] {
  const session = useWizardInstallation();
  const [value, setValue, loaded] = saved;
  const guardedSetter = useCallback(
    (next: S) => {
      if (session && session.status !== "saved") {
        session.blockEdit();
        return;
      }
      setValue(next);
    },
    [session, setValue],
  );
  const active = session?.status === "active" ? session.installation : null;
  return [
    active ? select(active) : value,
    guardedSetter,
    loaded && (!session || session.status === "saved" || session.status === "active"),
  ];
}
