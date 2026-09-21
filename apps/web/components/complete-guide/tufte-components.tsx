"use client";

import type { ReactNode } from "react";

export function TufteSection({ children, id }: { children: ReactNode; id?: string }) {
  return (
    <section
      id={id}
      className="relative w-full grid grid-cols-1 xl:grid-cols-12 gap-8 xl:gap-16 mb-24 xl:mb-40 scroll-mt-32"
    >
      {children}
    </section>
  );
}

export function MainColumn({ children }: { children: ReactNode }) {
  return <div className="col-span-1 xl:col-span-7 xl:col-start-1">{children}</div>;
}

export function MarginColumn({ children }: { children: ReactNode }) {
  return (
    <aside className="col-span-1 xl:col-span-4 xl:col-start-9 relative">
      <div className="xl:sticky top-32 flex flex-col gap-8">{children}</div>
    </aside>
  );
}

export function FullWidthColumn({ children }: { children: ReactNode }) {
  return <div className="col-span-1 xl:col-span-12">{children}</div>;
}
