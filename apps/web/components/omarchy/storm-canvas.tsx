"use client";

import nextDynamic from "next/dynamic";
import type { RefObject } from "react";
import type { StormTools } from "./tool-storm";

/**
 * Client boundary for the WebGL storm: `next/dynamic` with `ssr: false`
 * is not permitted in Server Components, so the page imports this wrapper.
 */
const ToolStorm = nextDynamic(() => import("./tool-storm"), { ssr: false });

export default function StormCanvas({
  className,
  tools,
  avoid,
}: {
  className?: string;
  tools: StormTools;
  avoid?: readonly RefObject<HTMLElement | null>[];
}) {
  return <ToolStorm className={className} tools={tools} avoid={avoid} />;
}
