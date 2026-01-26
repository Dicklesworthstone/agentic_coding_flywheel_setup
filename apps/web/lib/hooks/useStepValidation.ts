/**
 * Step Validation Hook
 *
 * Provides validation UI state for the wizard layout. Delegates to each
 * WizardStep's optional `validate()` function (defined in wizardSteps.ts).
 * Steps without validators are always considered valid.
 *
 * @see bd-2gys for the full spec
 */

import { useCallback, useState } from "react";
import { WIZARD_STEPS, type ValidationResult } from "../wizardSteps";

const VALID: ValidationResult = { valid: true, errors: [] };
const ERROR_DISPLAY_MS = 4000;

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

  const clearErrors = useCallback(() => {
    setValidationErrors([]);
  }, []);

  const validate = useCallback(
    (stepId: number): ValidationResult => {
      const step = WIZARD_STEPS.find((s) => s.id === stepId);
      if (!step?.validate) {
        setValidationErrors([]);
        return VALID;
      }

      const result = step.validate();

      if (!result.valid) {
        setValidationErrors(result.errors);

        // Auto-dismiss after timeout
        setTimeout(() => setValidationErrors([]), ERROR_DISPLAY_MS);

        // Scroll to and focus the relevant element
        if (result.focusSelector) {
          const el = document.querySelector(result.focusSelector);
          if (el) {
            el.scrollIntoView({ behavior: "smooth", block: "center" });
            if (el instanceof HTMLElement) el.focus();
          }
        }
      } else {
        setValidationErrors([]);
      }

      return result;
    },
    [],
  );

  return { validate, validationErrors, clearErrors } as const;
}
