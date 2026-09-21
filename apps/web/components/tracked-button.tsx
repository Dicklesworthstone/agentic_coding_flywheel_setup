"use client";

import { type ComponentProps, forwardRef } from "react";
import { Button } from "@/components/ui/button";
import { sendEvent, trackInteraction } from "@/lib/analytics";

type ButtonProps = ComponentProps<typeof Button>;

interface TrackedButtonProps extends ButtonProps {
  trackingId: string;
  trackingCategory?: string;
  trackingLabel?: string;
  trackingValue?: number;
}

/**
 * Button component with built-in click tracking
 */
export const TrackedButton = forwardRef<HTMLButtonElement, TrackedButtonProps>(
  (
    {
      trackingId,
      trackingCategory = "button",
      trackingLabel,
      trackingValue,
      onClick,
      children,
      ...props
    },
    ref,
  ) => {
    const handleClick = (e: React.MouseEvent<HTMLButtonElement>) => {
      // Track the click
      trackInteraction("click", trackingId, trackingCategory, {
        label: trackingLabel || (typeof children === "string" ? children : trackingId),
        value: trackingValue,
      });

      // Also send as a named event for easier filtering
      sendEvent(`${trackingCategory}_click`, {
        button_id: trackingId,
        button_label: trackingLabel || (typeof children === "string" ? children : trackingId),
      });

      // Call original onClick if provided
      onClick?.(e);
    };

    return (
      <Button ref={ref} onClick={handleClick} {...props}>
        {children}
      </Button>
    );
  },
);

TrackedButton.displayName = "TrackedButton";

export default TrackedButton;
