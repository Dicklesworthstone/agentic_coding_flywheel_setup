import { cn } from "@/lib/utils";

interface SkeletonProps extends React.HTMLAttributes<HTMLDivElement> {
  /** Shimmer animation variant */
  shimmer?: boolean;
}

function Skeleton({ className, shimmer = true, ...props }: SkeletonProps) {
  return (
    <div
      data-slot="skeleton"
      className={cn(
        "rounded-md bg-muted/80",
        // Enhanced shimmer with glow effect for premium feel
        shimmer && [
          "relative overflow-hidden",
          "before:absolute before:inset-0 before:-translate-x-full",
          "before:animate-[shimmer_2s_infinite]",
          "before:bg-gradient-to-r before:from-transparent before:via-white/15 before:to-transparent",
          // Subtle pulse animation layered with shimmer
          "animate-pulse",
        ],
        className
      )}
      {...props}
    />
  );
}

function SkeletonText({
  lines = 3,
  className,
  ...props
}: { lines?: number } & React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div className={cn("space-y-2", className)} {...props}>
      {Array.from({ length: lines }).map((_, i) => (
        <Skeleton
          key={i}
          className={cn(
            "h-4",
            i === lines - 1 && lines > 1 ? "w-3/4" : "w-full"
          )}
        />
      ))}
    </div>
  );
}

function SkeletonCard({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn(
        "rounded-xl border border-border/50 bg-card/50 p-6 space-y-4",
        className
      )}
      {...props}
    >
      {/* Icon placeholder */}
      <Skeleton className="h-12 w-12 rounded-xl" />
      {/* Title */}
      <Skeleton className="h-5 w-2/3" />
      {/* Description */}
      <SkeletonText lines={2} />
    </div>
  );
}

function SkeletonAvatar({
  size = "md",
  className,
  ...props
}: { size?: "sm" | "md" | "lg" } & React.HTMLAttributes<HTMLDivElement>) {
  const sizeClasses = {
    sm: "h-8 w-8",
    md: "h-10 w-10",
    lg: "h-14 w-14",
  };

  return (
    <Skeleton
      className={cn("rounded-full", sizeClasses[size], className)}
      {...props}
    />
  );
}

function SkeletonButton({
  size = "default",
  className,
  ...props
}: { size?: "sm" | "default" | "lg" } & React.HTMLAttributes<HTMLDivElement>) {
  const sizeClasses = {
    sm: "h-8 w-20",
    default: "h-10 w-28",
    lg: "h-12 w-36",
  };

  return (
    <Skeleton
      className={cn("rounded-lg", sizeClasses[size], className)}
      {...props}
    />
  );
}

export { Skeleton, SkeletonText, SkeletonCard, SkeletonAvatar, SkeletonButton };
