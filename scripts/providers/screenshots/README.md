# No Provider Screenshots

The provider guides in `scripts/providers/` are text-only on purpose. Provider consoles
(Contabo, OVH, Hetzner) change their layouts and labels often, and a stale screenshot
misleads a beginner more than a precise sentence does. Each guide names the choice that
matters at every step (plan size, Ubuntu 26.04 LTS image, login method) instead.

Plan prices and specs for Contabo and OVH come from `apps/web/lib/vpsProviders.ts`, the
single source the wizard renders from. Keep the guides in sync with that file rather than
adding images here.
