"use client";

import { AlertTriangle, Home, RefreshCw } from "lucide-react";
import Link from "next/link";
import * as React from "react";
import { Button } from "./button";

interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
}

interface ErrorBoundaryProps {
  children: React.ReactNode;
  /** Custom fallback component to show on error */
  fallback?: React.ReactNode;
  /** Called when an error is caught */
  onError?: (error: Error, errorInfo: React.ErrorInfo) => void;
  /** Link to navigate to on "Go Back" action */
  backLink?: string;
  /** Label for the back link */
  backLinkLabel?: string;
}

/**
 * Error boundary component that catches JavaScript errors in child components.
 *
 * React error boundaries must be class components - they cannot be implemented
 * as function components as of React 18.
 *
 * @example
 * ```tsx
 * <ErrorBoundary
 *   backLink="/learn"
 *   backLinkLabel="Learning Hub"
 *   onError={(error) => console.error(error)}
 * >
 *   <LessonContent lesson={lesson} />
 * </ErrorBoundary>
 * ```
 */
export class ErrorBoundary extends React.Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: React.ErrorInfo): void {
    // Log error for debugging
    console.error("ErrorBoundary caught an error:", error, errorInfo);

    // Call optional error handler
    this.props.onError?.(error, errorInfo);
  }

  handleRetry = (): void => {
    this.setState({ hasError: false, error: null });
  };

  render(): React.ReactNode {
    if (this.state.hasError) {
      // Custom fallback takes precedence
      if (this.props.fallback) {
        return this.props.fallback;
      }

      const { backLink = "/learn", backLinkLabel = "Learning Hub" } = this.props;

      // Default styled error UI
      return (
        <div className="flex min-h-[400px] items-center justify-center p-8">
          <div className="relative max-w-lg text-center">
            {/* Background glow */}
            <div className="absolute inset-0 -z-10 bg-gradient-to-br from-red-500/10 via-transparent to-orange-500/10 blur-3xl" />

            {/* Error card */}
            <div className="rounded-2xl border border-red-500/20 bg-gradient-to-br from-red-500/10 via-black/40 to-orange-500/5 p-8 backdrop-blur-xl">
              {/* Icon */}
              <div className="mx-auto mb-6 flex h-16 w-16 items-center justify-center rounded-2xl bg-gradient-to-br from-red-500/20 to-orange-500/20 border border-red-500/30">
                <AlertTriangle className="h-8 w-8 text-red-400" />
              </div>

              {/* Title */}
              <h2 className="mb-3 text-2xl font-bold text-white">Something went wrong</h2>

              {/* Description */}
              <p className="mb-6 text-white/60">
                We encountered an error while loading this content. This might be a temporary issue.
              </p>

              {/* Error details (development only) */}
              {process.env.NODE_ENV === "development" && this.state.error && (
                <div className="mb-6 rounded-xl bg-black/40 p-4 text-left">
                  <p className="mb-2 text-xs font-medium uppercase tracking-wider text-red-400/80">
                    Error Details
                  </p>
                  <pre className="overflow-auto text-xs text-white/50">
                    {this.state.error.message}
                  </pre>
                </div>
              )}

              {/* Actions */}
              <div className="flex flex-col gap-3 sm:flex-row sm:justify-center">
                <Button
                  onClick={this.handleRetry}
                  variant="outline"
                  className="gap-2 border-white/20 hover:bg-white/10"
                >
                  <RefreshCw className="h-4 w-4" />
                  Try Again
                </Button>
                <Button asChild className="gap-2 bg-gradient-to-r from-primary to-violet-500">
                  <Link href={backLink}>
                    <Home className="h-4 w-4" />
                    Go to {backLinkLabel}
                  </Link>
                </Button>
              </div>
            </div>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}
