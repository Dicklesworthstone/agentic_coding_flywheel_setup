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
import { validateStep, type ValidationResult } from "../wizardSteps";

const VALID: ValidationResult = { valid: true, errors: [] };

const FOCUSABLE_DESCENDANT =
  'input:not([disabled]), button:not([disabled]), select:not([disabled]), textarea:not([disabled]), a[href], [tabindex]:not([tabindex="-1"])';

/**
 * Scroll a validation target into view and move focus to it. The target may
 * be a plain wrapper `<div>` with no tabIndex (focus() is then a no-op), so
 * fall back to its first focusable descendant — the checkbox or input the
 * person actually needs to fix.
 */
function scrollAndFocus(selector: string): void {
  const el = document.querySelector(selector);
  if (!el) return;
  el.scrollIntoView({ behavior: "smooth", block: "center" });

  if (el instanceof HTMLElement) {
    el.focus({ preventScroll: true });
    if (document.activeElement === el) return;
  }
  const inner = el.querySelector<HTMLElement>(FOCUSABLE_DESCENDANT);
  inner?.focus({ preventScroll: true });
}

/**
 * Hook that provides step validation for the wizard layout.
 *
 * Returns:
 * - `validate(stepId)` — run validation, scroll to target on failure, returns result
 * - `showErrors(messages)` — surface arbitrary messages in the same banner
 *   (e.g. "finish the steps in order" for a locked sidebar step)
 * - `validationErrors` — current error messages. They persist until the
 *   route changes, a later validation passes, or `clearErrors()` runs — no
 *   auto-dismiss timer, so the text cannot vanish before it has been read.
 * - `clearErrors()` — manually dismiss errors
 */
export function useStepValidation() {
  const [validationErrors, setValidationErrors] = useState<string[]>([]);

  const clearErrors = useCallback(() => {
    setValidationErrors([]);
  }, []);

  const showErrors = useCallback((messages: string[]) => {
    setValidationErrors(messages);
  }, []);

  const validate = useCallback(
    (stepId: number): ValidationResult => {
      const result = validateStep(stepId);

      if (result.valid) {
        clearErrors();
        return VALID;
      }

      setValidationErrors(result.errors);

      // Scroll to and focus the relevant element
      if (result.focusSelector) {
        scrollAndFocus(result.focusSelector);
      }

      return result;
    },
    [clearErrors],
  );

  return { validate, showErrors, validationErrors, clearErrors } as const;
}
