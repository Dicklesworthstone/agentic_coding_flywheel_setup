"use client";

import * as React from "react";
import { Slot } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";
import { m, type HTMLMotionProps } from "framer-motion";
import { Loader2 } from "lucide-react";
import { cn } from "@/lib/utils";
import { springs } from "@/components/motion";
import { useReducedMotion } from "@/lib/hooks/useReducedMotion";

/**
 * Button variants with Apple HIG compliant sizing:
 * - default: 44px (minimum touch target)
 * - sm: 36px (for compact contexts)
 * - lg: 48px (comfortable touch)
 * - xl: 56px (hero CTAs)
 */
const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-xl text-sm font-medium transition-colors disabled:pointer-events-none disabled:opacity-50 [&_svg]:pointer-events-none [&_svg:not([class*='size-'])]:size-4 shrink-0 [&_svg]:shrink-0 outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background",
  {
    variants: {
      variant: {
        default:
          "bg-primary text-primary-foreground shadow-md shadow-primary/20 hover:bg-primary/90 active:bg-primary/85",
        destructive:
          "bg-destructive text-white shadow-md shadow-destructive/20 hover:bg-destructive/90 active:bg-destructive/85",
        outline:
          "border-2 border-border bg-transparent hover:bg-accent/10 hover:border-accent/50 active:bg-accent/20",
        secondary:
          "bg-secondary text-secondary-foreground shadow-sm hover:bg-secondary/80 active:bg-secondary/70",
        ghost:
          "hover:bg-accent/20 hover:text-accent-foreground active:bg-accent/30",
        link: "text-primary underline-offset-4 hover:underline",
        // Premium gradient variant for hero CTAs - Stripe-style
        gradient:
          "bg-gradient-to-r from-primary via-[oklch(0.65_0.2_220)] to-[oklch(0.6_0.22_280)] text-white shadow-lg shadow-primary/30 hover:shadow-xl hover:shadow-primary/40 hover:brightness-110 active:brightness-95",
        // Subtle gradient for secondary emphasis
        "gradient-subtle":
          "bg-gradient-to-r from-white/10 to-white/5 border border-white/20 text-white hover:from-white/15 hover:to-white/10 hover:border-white/30 active:from-white/20 active:to-white/15",
      },
      size: {
        default: "h-11 px-5 py-2.5 text-sm",
        sm: "h-9 px-4 text-sm rounded-lg",
        lg: "h-12 px-6 text-base rounded-xl",
        xl: "h-14 px-8 text-lg rounded-xl",
        icon: "size-11 rounded-xl",
        "icon-sm": "size-9 rounded-lg",
        "icon-lg": "size-12 rounded-xl",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  }
);

type ButtonVariantProps = VariantProps<typeof buttonVariants>;

interface ButtonProps
  extends Omit<HTMLMotionProps<"button">, "children">,
    ButtonVariantProps {
  asChild?: boolean;
  children?: React.ReactNode;
  /** Disable motion animations (for server components or reduced motion) */
  disableMotion?: boolean;
  /** Show loading spinner and disable button */
  loading?: boolean;
  /** Optional text to show alongside spinner when loading (if omitted, only spinner shown) */
  loadingText?: string;
}

/**
 * Button component with spring animations and HIG-compliant touch targets.
 *
 * Features:
 * - 44px minimum height (default) for reliable touch targets
 * - Spring-based hover and tap animations
 * - Multiple variants: default, destructive, outline, secondary, ghost, link
 * - Multiple sizes: sm (36px), default (44px), lg (48px), xl (56px)
 * - Icon-only variants with square proportions
 */
const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  (
    {
      className,
      variant = "default",
      size = "default",
      asChild = false,
      disableMotion = false,
      loading = false,
      loadingText,
      children,
      disabled,
      ...props
    },
    ref
  ) => {
    const isDisabled = disabled || loading;
    const prefersReducedMotion = useReducedMotion();
    const shouldDisableMotion = disableMotion || prefersReducedMotion;

    // Loading spinner component
    const LoadingSpinner = () => (
      <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
    );

    // Render content with optional loading state
    const renderContent = () => {
      if (loading) {
        return (
          <>
            <LoadingSpinner />
            {loadingText && <span>{loadingText}</span>}
          </>
        );
      }
      return children;
    };

    // For asChild, use Slot without motion
    if (asChild) {
      return (
        <Slot
          ref={ref as React.Ref<HTMLElement>}
          className={cn(buttonVariants({ variant, size, className }))}
          {...(props as React.ComponentPropsWithoutRef<typeof Slot>)}
        >
          {children}
        </Slot>
      );
    }

    // For link variant or when motion should be disabled, render without animations
    // This respects both the explicit disableMotion prop and user's reduced motion preference
    if (variant === "link" || shouldDisableMotion) {
      return (
        <button
          type="button"
          ref={ref}
          disabled={isDisabled}
          aria-busy={loading}
          className={cn(buttonVariants({ variant, size, className }))}
          {...(props as React.ComponentPropsWithoutRef<"button">)}
        >
          {renderContent()}
        </button>
      );
    }

    // Motion-enhanced button with spring animations
    // Using m.button (not motion.button) for LazyMotion compatibility
    return (
      <m.button
        type="button"
        ref={ref}
        disabled={isDisabled}
        aria-busy={loading}
        className={cn(buttonVariants({ variant, size, className }))}
        whileHover={isDisabled ? {} : { scale: 1.02 }}
        whileTap={isDisabled ? {} : { scale: 0.98 }}
        transition={springs.snappy}
        {...props}
      >
        {renderContent()}
      </m.button>
    );
  }
);

Button.displayName = "Button";

export { Button, buttonVariants };
