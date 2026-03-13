/**
 * Wizard Steps Configuration
 *
 * Defines the steps of the Agent Flywheel setup wizard.
 * The actual count is derived from the WIZARD_STEPS array (see TOTAL_STEPS).
 * Each step guides beginners from "I have a laptop" to "fully configured VPS".
 * Uses TanStack Query for React state management with localStorage persistence.
 */

import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useCallback, useEffect } from "react";
import { safeGetJSON, safeGetItem, safeSetJSON } from "./utils";
import { getUserOS, getVPSIP, detectOS, setUserOS } from "./userPreferences";

export interface ValidationResult {
  valid: boolean;
  errors: string[];
  /** CSS selector to scroll-to and focus on failure */
  focusSelector?: string;
}

export interface WizardStep {
  /** Step number (1..TOTAL_STEPS) */
  id: number;
  /** Short title for the step */
  title: string;
  /** Longer description of what happens in this step */
  description: string;
  /** URL slug for this step (e.g., "os-selection") */
  slug: string;
  /** Optional validation; called before forward navigation from this step */
  validate?: () => ValidationResult;
}

// --- Step validation functions ---

function validateOSSelection(): ValidationResult {
  // Try auto-detection as a last resort before failing
  if (!getUserOS()) {
    const detected = detectOS();
    if (detected) setUserOS(detected);
  }
  return getUserOS()
    ? { valid: true, errors: [] }
    : {
        valid: false,
        errors: ["Select your operating system to continue"],
        focusSelector: "[data-os-selection]",
      };
}

function validateVPSCreation(): ValidationResult {
  return getVPSIP()
    ? { valid: true, errors: [] }
    : {
        valid: false,
        errors: ["Enter your VPS IP address to continue"],
        focusSelector: "[data-vps-ip-input]",
    };
}

const COMMAND_COMPLETION_KEY_PREFIX = "acfs-command-";

function isCommandMarkedComplete(persistKey: string): boolean {
  if (safeGetItem(`${COMMAND_COMPLETION_KEY_PREFIX}${persistKey}`) === "true") {
    return true;
  }

  if (typeof document === "undefined") {
    return false;
  }

  const checkbox = document.getElementById(persistKey);
  if (!checkbox) {
    return false;
  }

  return (
    checkbox.getAttribute("data-state") === "checked" ||
    (checkbox instanceof HTMLInputElement && checkbox.checked)
  );
}

function validateStatusCheck(): ValidationResult {
  return isCommandMarkedComplete("flywheel-doctor")
    ? { valid: true, errors: [] }
    : {
        valid: false,
        errors: ["Run the doctor command and mark it complete before continuing"],
        focusSelector: "#flywheel-doctor",
      };
}

export const WIZARD_STEPS: WizardStep[] = [
  {
    id: 1,
    title: "Choose Your OS",
    description: "Select whether you're using Mac, Windows, or Linux",
    slug: "os-selection",
    validate: validateOSSelection,
  },
  {
    id: 2,
    title: "Install Terminal",
    description: "Get a proper terminal application set up",
    slug: "install-terminal",
  },
  {
    id: 3,
    title: "Generate SSH Key",
    description: "Create your SSH key pair for secure VPS access",
    slug: "generate-ssh-key",
  },
  {
    id: 4,
    title: "Rent a VPS",
    description: "Choose and sign up for a VPS provider",
    slug: "rent-vps",
  },
  {
    id: 5,
    title: "Create VPS Instance",
    description: "Launch your VPS with password authentication",
    slug: "create-vps",
    validate: validateVPSCreation,
  },
  {
    id: 6,
    title: "SSH Into Your VPS",
    description: "Connect to your VPS for the first time",
    slug: "ssh-connect",
  },
  {
    id: 7,
    title: "Set Up Accounts",
    description: "Create accounts for the services you'll use",
    slug: "accounts",
  },
  {
    id: 8,
    title: "Pre-Flight Check",
    description: "Verify your VPS is ready before installing",
    slug: "preflight-check",
  },
  {
    id: 9,
    title: "Run Installer",
    description: "Paste and run the one-liner to install everything",
    slug: "run-installer",
  },
  {
    id: 10,
    title: "Reconnect as Ubuntu",
    description: "Switch from root to your ubuntu user",
    slug: "reconnect-ubuntu",
  },
  {
    id: 11,
    title: "Verify Key Connection",
    description: "Reconnect using your SSH key and confirm it works",
    slug: "verify-key-connection",
  },
  {
    id: 12,
    title: "Status Check",
    description: "Verify everything installed correctly",
    slug: "status-check",
    validate: validateStatusCheck,
  },
  {
    id: 13,
    title: "Launch Onboarding",
    description: "Start the interactive tutorial",
    slug: "launch-onboarding",
  },
];

/** Total number of wizard steps */
export const TOTAL_STEPS = WIZARD_STEPS.length;

/** Get a step by its ID (1-indexed) */
export function getStepById(id: number): WizardStep | undefined {
  return WIZARD_STEPS.find((step) => step.id === id);
}

/** Get a step by its URL slug */
export function getStepBySlug(slug: string): WizardStep | undefined {
  // Some pages under `/wizard/*` are optional "bonus" routes that should still
  // highlight a canonical step in the sidebar.
  const canonicalSlug =
    slug === "windows-terminal-setup" ? "verify-key-connection" : slug;
  return WIZARD_STEPS.find((step) => step.slug === canonicalSlug);
}

export function validateStep(stepId: number): ValidationResult {
  const step = getStepById(stepId);
  if (!step?.validate) {
    return { valid: true, errors: [] };
  }

  return step.validate();
}

/** localStorage key for storing completed steps */
export const COMPLETED_STEPS_KEY = "agent-flywheel-wizard-completed-steps";

export const COMPLETED_STEPS_CHANGED_EVENT =
  "acfs:wizard:completed-steps-changed";

// Query keys for TanStack Query
export const wizardStepsKeys = {
  completedSteps: ["wizardSteps", "completed"] as const,
};

type CompletedStepsChangedDetail = {
  steps: number[];
};

function normalizeCompletedSteps(steps: unknown[]): number[] {
  const validSteps = steps.filter(
    (n): n is number => typeof n === "number" && n >= 1 && n <= TOTAL_STEPS
  );
  return Array.from(new Set(validSteps)).sort((a, b) => a - b);
}

export function getHighestContiguousCompletedStep(steps: number[]): number {
  const normalized = normalizeCompletedSteps(steps);
  let highestContiguous = 0;

  for (const step of normalized) {
    if (step !== highestContiguous + 1) {
      break;
    }
    highestContiguous = step;
  }

  return highestContiguous;
}

function emitCompletedStepsChanged(steps: number[]): void {
  if (typeof window === "undefined") return;
  window.dispatchEvent(
    new CustomEvent<CompletedStepsChangedDetail>(COMPLETED_STEPS_CHANGED_EVENT, {
      detail: { steps },
    })
  );
}

/** Get completed steps from localStorage */
export function getCompletedSteps(): number[] {
  const parsed = safeGetJSON<unknown[]>(COMPLETED_STEPS_KEY);
  if (Array.isArray(parsed)) {
    return normalizeCompletedSteps(parsed);
  }
  return [];
}

/** Save completed steps to localStorage */
export function setCompletedSteps(steps: number[]): boolean {
  const normalized = normalizeCompletedSteps(steps);
  const didPersist = safeSetJSON(COMPLETED_STEPS_KEY, normalized);
  if (didPersist) {
    emitCompletedStepsChanged(normalized);
  }
  return didPersist;
}

/** Mark a step as completed (pure function, returns new array) */
export function addCompletedStep(currentSteps: number[], stepId: number): number[] {
  if (
    !Number.isInteger(stepId) ||
    stepId < 1 ||
    stepId > TOTAL_STEPS ||
    currentSteps.includes(stepId)
  ) {
    return currentSteps;
  }
  const newSteps = [...currentSteps, stepId];
  newSteps.sort((a, b) => a - b);
  return newSteps;
}

// --- React Hooks using TanStack Query ---

/**
 * Hook to get and manage completed wizard steps.
 * Uses TanStack Query for state management with localStorage persistence.
 */
export function useCompletedSteps(): [number[], (stepId: number) => void] {
  const queryClient = useQueryClient();

  useEffect(() => {
    if (typeof window === "undefined") return;

    const handleCompletedStepsChanged = (event: Event) => {
      const customEvent = event as CustomEvent<CompletedStepsChangedDetail>;
      const nextSteps = customEvent.detail?.steps ?? getCompletedSteps();
      queryClient.setQueryData(wizardStepsKeys.completedSteps, nextSteps);
    };

    const handleStorage = (event: StorageEvent) => {
      if (event.key !== COMPLETED_STEPS_KEY) return;
      queryClient.setQueryData(wizardStepsKeys.completedSteps, getCompletedSteps());
    };

    window.addEventListener(
      COMPLETED_STEPS_CHANGED_EVENT,
      handleCompletedStepsChanged as EventListener
    );
    window.addEventListener("storage", handleStorage);

    return () => {
      window.removeEventListener(
        COMPLETED_STEPS_CHANGED_EVENT,
        handleCompletedStepsChanged as EventListener
      );
      window.removeEventListener("storage", handleStorage);
    };
  }, [queryClient]);

  const { data: steps } = useQuery({
    queryKey: wizardStepsKeys.completedSteps,
    queryFn: getCompletedSteps,
    // The stepper lives in a persistent Next.js layout, so it won't remount
    // between steps. We keep this query in sync by listening for:
    // - `COMPLETED_STEPS_CHANGED_EVENT` (same-tab writes)
    // - `storage` events (cross-tab writes)
    staleTime: 0,
    gcTime: Infinity,
  });

  const mutation = useMutation({
    mutationFn: async (stepId: number) => {
      // Use query cache as source of truth to avoid race conditions when
      // markComplete is called rapidly multiple times. Falls back to
      // localStorage for initial hydration.
      const currentSteps =
        queryClient.getQueryData<number[]>(wizardStepsKeys.completedSteps) ??
        getCompletedSteps();
      const newSteps = addCompletedStep(currentSteps, stepId);
      if (newSteps === currentSteps) {
        return currentSteps;
      }
      if (!setCompletedSteps(newSteps)) {
        throw new Error("Unable to persist completed steps.");
      }
      return newSteps;
    },
    onMutate: async (stepId) => {
      // Cancel any outgoing refetches to prevent overwrites
      await queryClient.cancelQueries({
        queryKey: wizardStepsKeys.completedSteps,
      });

      // Snapshot previous value for rollback
      const cachedSteps = queryClient.getQueryData<number[]>(
        wizardStepsKeys.completedSteps
      );

      // Optimistically update cache immediately (synchronous) so subsequent
      // rapid mutations see the updated value
      // Important: fall back to localStorage when cache is empty to avoid
      // overwriting existing progress on first mutation before hydration.
      const baseSteps = cachedSteps ?? getCompletedSteps();
      const newSteps = addCompletedStep(baseSteps, stepId);
      queryClient.setQueryData(wizardStepsKeys.completedSteps, newSteps);

      return { previousSteps: cachedSteps };
    },
    onError: (_err, _stepId, context) => {
      // Rollback to previous value on error
      if (context?.previousSteps !== undefined) {
        queryClient.setQueryData(
          wizardStepsKeys.completedSteps,
          context.previousSteps
        );
      } else {
        queryClient.invalidateQueries({
          queryKey: wizardStepsKeys.completedSteps,
        });
      }
    },
    onSettled: () => {
      // Refetch to ensure cache is in sync with localStorage
      queryClient.invalidateQueries({
        queryKey: wizardStepsKeys.completedSteps,
      });
    },
  });

  const { mutate } = mutation;
  const markComplete = useCallback(
    (stepId: number) => {
      mutate(stepId);
    },
    [mutate]
  );

  return [steps ?? [], markComplete];
}

/**
 * Imperatively mark a step as complete (for use outside React components).
 * This writes to localStorage and notifies any mounted `useCompletedSteps()`
 * hooks (e.g., the Stepper in the wizard layout) via a DOM event.
 */
export function markStepComplete(stepId: number): number[] {
  const completed = getCompletedSteps();
  const newSteps = addCompletedStep(completed, stepId);
  if (newSteps !== completed) {
    if (!setCompletedSteps(newSteps)) {
      return getCompletedSteps();
    }
  }
  return newSteps;
}
