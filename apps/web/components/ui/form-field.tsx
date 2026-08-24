"use client";

import * as React from "react";
import { AnimatePresence, motion as m } from "@/components/motion";
import { cn } from "@/lib/utils";
import { useReducedMotion } from "@/lib/hooks/useReducedMotion";

export interface FormFieldProps {
  /** Input name for form submission */
  name: string;
  /** Label text (becomes floating label) */
  label: string;
  /** Input type (text, email, password, etc.) */
  type?: "text" | "email" | "password" | "url" | "tel" | "number";
  /** Current value (controlled) */
  value: string;
  /** Change handler */
  onChange: (value: string) => void;
  /** Blur handler */
  onBlur?: () => void;
  /** Error message (shows error state when truthy) */
  error?: string;
  /** Helper text (shown below input when no error) */
  helperText?: string;
  /** Whether field is required */
  required?: boolean;
  /** Whether field is disabled */
  disabled?: boolean;
  /** Placeholder (optional, label acts as placeholder when empty) */
  placeholder?: string;
  /** Character count limit (shows counter when set) */
  maxLength?: number;
  /** Additional className */
  className?: string;
  /** Input ref for focus management */
  inputRef?: React.Ref<HTMLInputElement>;
}

export function FormField({
  name,
  label,
  type = "text",
  value,
  onChange,
  onBlur,
  error,
  helperText,
  required,
  disabled,
  placeholder,
  maxLength,
  className,
  inputRef,
}: FormFieldProps) {
  const id = React.useId();
  const [isFocused, setIsFocused] = React.useState(false);
  const prefersReducedMotion = useReducedMotion();

  const hasValue = value.length > 0;
  const isFloating = isFocused || hasValue;
  const showError = Boolean(error);

  const handleFocus = () => setIsFocused(true);
  const handleBlur = () => {
    setIsFocused(false);
    onBlur?.();
  };

  const motionTransition = prefersReducedMotion
    ? { duration: 0 }
    : { duration: 0.15, ease: "easeOut" as const };

  return (
    <div className={cn("relative", className)}>
      <div
        className={cn(
          "relative rounded-xl border-2 transition-colors duration-200",
          isFocused && !showError && "border-primary",
          showError && "border-destructive",
          !isFocused && !showError && "border-border/50 hover:border-border",
          disabled && "cursor-not-allowed opacity-60"
        )}
      >
        <m.label
          htmlFor={id}
          className={cn(
            "absolute left-4 pointer-events-none origin-left",
            "transition-colors duration-200",
            isFloating ? "text-xs font-medium" : "text-base text-muted-foreground",
            isFocused && !showError && "text-primary",
            showError && "text-destructive",
            !isFocused && !showError && isFloating && "text-muted-foreground"
          )}
          animate={
            prefersReducedMotion
              ? {}
              : {
                  y: isFloating ? -10 : 14,
                  scale: isFloating ? 0.85 : 1,
                }
          }
          transition={motionTransition}
          style={{
            top: isFloating ? "8px" : "50%",
            transform: isFloating ? undefined : "translateY(-50%)",
          }}
        >
          {label}
          {required && <span className="ml-0.5 text-destructive">*</span>}
        </m.label>

        <input
          ref={inputRef}
          id={id}
          name={name}
          type={type}
          value={value}
          onChange={(event) => onChange(event.target.value)}
          onFocus={handleFocus}
          onBlur={handleBlur}
          disabled={disabled}
          required={required}
          maxLength={maxLength}
          placeholder={isFloating ? placeholder : undefined}
          aria-invalid={showError}
          aria-describedby={
            error ? `${id}-error` : helperText ? `${id}-helper` : undefined
          }
          className={cn(
            "w-full bg-transparent px-4 pt-6 pb-2 text-base",
            "rounded-xl outline-none",
            "placeholder:text-muted-foreground/50",
            disabled && "cursor-not-allowed"
          )}
        />
      </div>

      <div className="mt-1.5 flex items-start justify-between px-1">
        <AnimatePresence mode="wait">
          {showError ? (
            <m.p
              key="error"
              id={`${id}-error`}
              initial={prefersReducedMotion ? {} : { opacity: 0, y: -5 }}
              animate={{ opacity: 1, y: 0 }}
              exit={prefersReducedMotion ? {} : { opacity: 0, y: -5 }}
              transition={motionTransition}
              className="text-sm text-destructive"
              role="alert"
            >
              {error}
            </m.p>
          ) : helperText ? (
            <m.p
              key="helper"
              id={`${id}-helper`}
              initial={prefersReducedMotion ? {} : { opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={prefersReducedMotion ? {} : { opacity: 0 }}
              transition={motionTransition}
              className="text-sm text-muted-foreground"
            >
              {helperText}
            </m.p>
          ) : (
            <span />
          )}
        </AnimatePresence>

        {maxLength ? (
          <span
            className={cn(
              "text-sm tabular-nums",
              value.length >= maxLength ? "text-destructive" : "text-muted-foreground"
            )}
          >
            {value.length}/{maxLength}
          </span>
        ) : (
          <span />
        )}
      </div>
    </div>
  );
}
