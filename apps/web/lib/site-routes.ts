/**
 * Canonical public origin and every static page route, for sitemap.xml.
 * site-routes.test.ts checks this list against app/**\/page.tsx, so a new
 * page cannot silently miss the sitemap. next.config.ts redirect sources
 * (such as /learn/glossary) stay out; dynamic lesson and tool pages are
 * added from their data in app/sitemap.ts.
 */
export const SITE_URL = "https://agent-flywheel.com";

export const STATIC_ROUTES = [
  "/",
  "/cloud-agents",
  "/complete-guide",
  "/core-flywheel",
  "/docs/security",
  "/flywheel",
  "/glossary",
  "/learn",
  "/learn/commands",
  "/omarchy",
  "/tldr",
  "/troubleshooting",
  "/workflow",
  "/wizard/os-selection",
  "/wizard/install-terminal",
  "/wizard/windows-terminal-setup",
  "/wizard/generate-ssh-key",
  "/wizard/rent-vps",
  "/wizard/create-vps",
  "/wizard/ssh-connect",
  "/wizard/preflight-check",
  "/wizard/run-installer",
  "/wizard/reconnect-ubuntu",
  "/wizard/verify-key-connection",
  "/wizard/status-check",
  "/wizard/accounts",
  "/wizard/launch-onboarding",
] as const;
