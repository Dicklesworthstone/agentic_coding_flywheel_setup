"use client";

import nextDynamic from "next/dynamic";

/**
 * Client boundary for the WebGL storm: `next/dynamic` with `ssr: false`
 * is not permitted in Server Components, so the page imports this wrapper.
 */
const ToolStorm = nextDynamic(() => import("./tool-storm"), { ssr: false });

export default function StormCanvas({ className }: { className?: string }) {
  return <ToolStorm className={className} />;
}
