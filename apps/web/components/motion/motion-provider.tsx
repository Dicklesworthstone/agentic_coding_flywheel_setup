"use client";

import { domAnimation, LazyMotion, MotionConfig } from "framer-motion";
import { springs } from "./index";

interface MotionProviderProps {
  children: React.ReactNode;
}

/**
 * MotionProvider wraps the app with optimized Framer Motion configuration.
 *
 * Features:
 * - LazyMotion with domAnimation for smaller bundle (~13KB gzipped vs ~25KB full)
 * - MotionConfig sets default transition for consistent feel across app
 * - Strict mode catches missing features at build time
 *
 * Usage: Wrap your app's root layout with this provider:
 * <MotionProvider>{children}</MotionProvider>
 */
export function MotionProvider({ children }: MotionProviderProps) {
  return (
    <LazyMotion features={domAnimation} strict>
      <MotionConfig transition={springs.smooth} reducedMotion="user">
        {children}
      </MotionConfig>
    </LazyMotion>
  );
}
