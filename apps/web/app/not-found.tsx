import Link from "next/link";
import { ArrowRight, BookOpen, Home, Terminal } from "lucide-react";

const LINKS = [
  { href: "/", label: "Home", icon: Home },
  { href: "/wizard/os-selection", label: "Setup Wizard", icon: Terminal },
  { href: "/learn", label: "Learning Hub", icon: BookOpen },
] as const;

/**
 * Branded 404. Server-rendered, no client JS of its own. The `dark` island
 * keeps the composition on the dark tokens even when the wizard's toggle
 * stored `light`, and the `main#main-content` landmark lets the layout's
 * skip link land here like on every other route.
 */
export default function NotFound() {
  return (
    <div className="dark relative flex min-h-screen flex-col bg-background text-foreground">
      <div className="pointer-events-none absolute inset-0 bg-gradient-hero" aria-hidden="true" />
      <div className="pointer-events-none absolute inset-0 bg-grid-pattern opacity-30" aria-hidden="true" />

      <main
        id="main-content"
        tabIndex={-1}
        className="relative z-10 mx-auto flex w-full max-w-2xl flex-1 flex-col items-center justify-center px-6 py-24 text-center"
      >
        <p className="mb-4 font-mono text-sm font-bold uppercase tracking-[0.25em] text-primary">
          Error 404
        </p>
        <h1 className="mb-4 font-mono text-4xl font-bold tracking-tight sm:text-5xl">
          Page not found
        </h1>
        <p className="mb-10 max-w-md text-lg leading-relaxed text-muted-foreground">
          That address does not exist on Agent Flywheel. It may have moved, or
          the link you followed has a typo.
        </p>

        <nav aria-label="Where to go next" className="flex flex-col gap-3 sm:flex-row">
          {LINKS.map(({ href, label, icon: Icon }) => (
            <Link
              key={href}
              href={href}
              className="inline-flex h-12 items-center justify-center gap-2 rounded-xl border border-border/50 bg-card/50 px-5 text-sm font-medium text-foreground transition-colors hover:border-primary/30 hover:bg-card focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background"
            >
              <Icon className="h-4 w-4 text-primary" aria-hidden="true" />
              {label}
              <ArrowRight className="h-4 w-4 text-muted-foreground" aria-hidden="true" />
            </Link>
          ))}
        </nav>
      </main>
    </div>
  );
}
