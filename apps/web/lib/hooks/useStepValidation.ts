/**
 * Step Validation Hook
 *
 * Provides validation UI state for the wizard layout. Delegates to each
 * WizardStep's optional `validate()` function (defined in wizardSteps.ts).
 * Steps without validators are always considered valid.
 *
 * @see bd-2gys for the full spec
 */

import { useCallback, useEffect, useRef, useState } from "react";
import { validateStep, type ValidationResult } from "../wizardSteps";

const VALID: ValidationResult = { valid: true, errors: [] };
// Long enough to read twice; the field is also scrolled into view and
// focused, and its inline hint stays until the problem is fixed.
const ERROR_DISPLAY_MS = 10000;

/**
 * Hook that provides step validation for the wizard layout.
 *
 * Returns:
 * - `validate(stepId)` — run validation, scroll to target on failure, returns result
 * - `validationErrors` — current error messages (auto-cleared after timeout)
 * - `clearErrors()` — manually dismiss errors
 */
export function useStepValidation() {
  const [validationErrors, setValidationErrors] = useState<string[]>([]);
  const clearTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const cancelPendingClear = useCallback(() => {
    if (clearTimerRef.current !== null) {
      clearTimeout(clearTimerRef.current);
      clearTimerRef.current = null;
    }
  }, []);

  useEffect(() => cancelPendingClear, [cancelPendingClear]);

  const clearErrors = useCallback(() => {
    cancelPendingClear();
    setValidationErrors([]);
  }, [cancelPendingClear]);

  const validate = useCallback(
    (stepId: number): ValidationResult => {
      const result = validateStep(stepId);

      if (result.valid) {
        clearErrors();
        return VALID;
      }

      cancelPendingClear();
      setValidationErrors(result.errors);

      // Auto-dismiss after timeout. Cancel any older timer first so stale
      // timeouts cannot clear a newer validation error.
      clearTimerRef.current = setTimeout(() => {
        clearTimerRef.current = null;
        setValidationErrors([]);
      }, ERROR_DISPLAY_MS);

      // Scroll to and focus the relevant element
      if (result.focusSelector) {
        const el = document.querySelector(result.focusSelector);
        if (el) {
          el.scrollIntoView({ behavior: "smooth", block: "center" });
          if (el instanceof HTMLElement) el.focus();
        }
      }

      return result;
    },
    [cancelPendingClear, clearErrors],
  );

  return { validate, validationErrors, clearErrors } as const;
}
