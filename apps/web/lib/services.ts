/**
 * Service Catalog for ACFS
 *
 * Defines all services that ACFS recommends or installs.
 * Used by the Accounts wizard step and other components.
 */

export type ServiceCategory = 'access' | 'agent' | 'cloud' | 'devtools';
export type ServicePriority = 'strongly-recommended' | 'recommended' | 'optional';
export type ServiceTier = 'essential' | 'recommended' | 'optional';

export interface Service {
  /** Unique identifier, matches manifest module id where applicable */
  id: string;

  /** Display name */
  name: string;

  /** Company/provider name */
  provider: string;

  /** Path to logo (relative to /public) or inline SVG */
  logo: string;

  /** Service category for grouping */
  category: ServiceCategory;

  /** Priority tier for ordering */
  priority: ServicePriority;

  /** Account setup tier for the wizard */
  tier: ServiceTier;

  /** Sort order within a tier */
  sortOrder: number;

  /** One-line description */
  shortDescription: string;

  /** Whether this service requires a paid subscription to be usable */
  requiresSubscription?: boolean;

  /** Short note shown as a badge (e.g., "Requires Claude Max ($200/mo)") */
  subscriptionNote?: string;

  /** Why this service matters for vibe coding */
  whyNeeded: string;

  /** Primary signup URL */
  signupUrl: string;

  /** Does this service support Google SSO? */
  supportsGoogleSso: boolean;

  /** Direct URL to Google SSO signup flow (if different from signupUrl) */
  googleSsoUrl?: string;

  /** Alternative auth methods available */
  alternativeAuth?: ('github' | 'email' | 'apple')[];

  /** Command to run after install for authentication */
  postInstallCommand?: string;

  /** Whether this service is installed by ACFS */
  installedByAcfs: boolean;

  /** External documentation URL */
  docsUrl: string;
}

export const SERVICES: Service[] = [
  // Access Layer
  {
    id: 'tailscale',
    name: 'Tailscale',
    provider: 'Tailscale',
    logo: '/logos/tailscale.svg',
    category: 'access',
    priority: 'strongly-recommended',
    tier: 'optional',
    sortOrder: 1,
    shortDescription: 'Zero-config VPN for secure remote access',
    whyNeeded: 'Access your VPS from anywhere without exposing ports. SSH over private network, no firewall needed.',
    signupUrl: 'https://login.tailscale.com/start',
    supportsGoogleSso: true,
    googleSsoUrl: 'https://login.tailscale.com/start',
    alternativeAuth: ['github', 'apple'],
    postInstallCommand: 'sudo tailscale up',
    installedByAcfs: true,
    docsUrl: 'https://tailscale.com/kb/',
  },

  // Coding Agents
  {
    id: 'claude-code',
    name: 'Claude Code',
    provider: 'Anthropic',
    logo: '/logos/anthropic.svg',
    category: 'agent',
    priority: 'strongly-recommended',
    tier: 'essential',
    sortOrder: 2,
    shortDescription: 'Primary AI coding agent',
    requiresSubscription: true,
    subscriptionNote: 'Requires Claude Max ($200/mo)',
    whyNeeded: 'Claude Code is your main AI pair programmer. Understands context, writes code, explains concepts.',
    signupUrl: 'https://claude.ai/',
    supportsGoogleSso: true,
    googleSsoUrl: 'https://claude.ai/login',
    postInstallCommand: 'claude',
    installedByAcfs: true,
    docsUrl: 'https://docs.anthropic.com/',
  },
  {
    id: 'codex-cli',
    name: 'Codex CLI',
    provider: 'OpenAI',
    logo: '/logos/openai.svg',
    category: 'agent',
    priority: 'recommended',
    tier: 'recommended',
    sortOrder: 1,
    shortDescription: 'OpenAI coding agent (requires ChatGPT Pro)',
    requiresSubscription: true,
    subscriptionNote: 'Requires ChatGPT Pro ($200/mo)',
    whyNeeded: 'Secondary AI agent. Different model = different perspectives. Requires ChatGPT Pro subscription.',
    signupUrl: 'https://chat.openai.com/',
    supportsGoogleSso: true,
    googleSsoUrl: 'https://chat.openai.com/auth/login',
    alternativeAuth: ['apple', 'email'],
    postInstallCommand: 'codex login',
    installedByAcfs: true,
    docsUrl: 'https://platform.openai.com/docs/',
  },
  {
    id: 'gemini-cli',
    name: 'Gemini CLI',
    provider: 'Google',
    logo: '/logos/google.svg',
    category: 'agent',
    priority: 'optional',
    tier: 'recommended',
    sortOrder: 2,
    shortDescription: 'Google AI coding agent',
    requiresSubscription: true,
    subscriptionNote: 'Gemini Advanced (~$20/mo)',
    whyNeeded: 'Third AI option. Uses Gemini 3. Native Google integration. Good for Google Cloud projects.',
    signupUrl: 'https://accounts.google.com/',
    supportsGoogleSso: true, // It IS Google
    postInstallCommand: 'gemini',
    installedByAcfs: true,
    docsUrl: 'https://ai.google.dev/',
  },

  // Developer Tools
  {
    id: 'github',
    name: 'GitHub',
    provider: 'Microsoft',
    logo: '/logos/github.svg',
    category: 'devtools',
    priority: 'strongly-recommended',
    tier: 'essential',
    sortOrder: 1,
    shortDescription: 'Code hosting and version control',
    whyNeeded: 'Store your code, collaborate, use GitHub Actions for CI/CD. Essential for any developer.',
    signupUrl: 'https://github.com/signup',
    supportsGoogleSso: false, // Email-based, but can link Google email
    alternativeAuth: ['email'],
    postInstallCommand: 'gh auth login',
    installedByAcfs: false, // Just needs git config
    docsUrl: 'https://docs.github.com/',
  },

  // Cloud Platforms
  {
    id: 'vercel',
    name: 'Vercel',
    provider: 'Vercel',
    logo: '/logos/vercel.svg',
    category: 'cloud',
    priority: 'recommended',
    tier: 'optional',
    sortOrder: 2,
    shortDescription: 'Frontend deployment platform',
    whyNeeded: 'Deploy Next.js, React, and static sites with zero config. Git push = live site.',
    signupUrl: 'https://vercel.com/signup',
    supportsGoogleSso: true,
    alternativeAuth: ['github', 'email'],
    postInstallCommand: 'vercel login',
    installedByAcfs: true,
    docsUrl: 'https://vercel.com/docs',
  },
  {
    id: 'supabase',
    name: 'Supabase',
    provider: 'Supabase',
    logo: '/logos/supabase.svg',
    category: 'cloud',
    priority: 'optional',
    tier: 'optional',
    sortOrder: 3,
    shortDescription: 'Postgres database + auth + realtime',
    whyNeeded: 'Firebase alternative with real Postgres. Great for MVPs and full apps alike.',
    signupUrl: 'https://supabase.com/dashboard',
    supportsGoogleSso: true,
    alternativeAuth: ['github'],
    postInstallCommand: 'supabase login',
    installedByAcfs: true,
    docsUrl: 'https://supabase.com/docs',
  },
  {
    id: 'convex',
    name: 'Convex',
    provider: 'Convex',
    logo: '/logos/convex.svg',
    category: 'cloud',
    priority: 'optional',
    tier: 'optional',
    sortOrder: 4,
    shortDescription: 'Realtime app database and backend',
    whyNeeded: 'Managed database with functions, realtime subscriptions, and auth integrations.',
    signupUrl: 'https://dashboard.convex.dev',
    supportsGoogleSso: true,
    alternativeAuth: ['github'],
    postInstallCommand: 'convex login',
    installedByAcfs: true,
    docsUrl: 'https://docs.convex.dev',
  },
  {
    id: 'cloudflare',
    name: 'Cloudflare',
    provider: 'Cloudflare',
    logo: '/logos/cloudflare.svg',
    category: 'cloud',
    priority: 'optional',
    tier: 'optional',
    sortOrder: 5,
    shortDescription: 'CDN, DNS, Workers, and more',
    whyNeeded: 'Free CDN, DNS management, edge computing. Great for performance and DDoS protection.',
    signupUrl: 'https://dash.cloudflare.com/sign-up',
    supportsGoogleSso: false, // Email-based only
    alternativeAuth: ['email'],
    postInstallCommand: 'wrangler login',
    installedByAcfs: true,
    docsUrl: 'https://developers.cloudflare.com/',
  },
];

// Helper functions
export function getServicesByCategory(category: ServiceCategory): Service[] {
  return SERVICES.filter((s) => s.category === category);
}

export function getServicesByPriority(priority: ServicePriority): Service[] {
  return SERVICES.filter((s) => s.priority === priority);
}

export function getServicesByTier(tier: ServiceTier): Service[] {
  return SERVICES.filter((s) => s.tier === tier);
}

/** Group services by tier for the accounts wizard */
export function groupByTier(): Record<ServiceTier, Service[]> {
  const groups: Record<ServiceTier, Service[]> = {
    essential: [],
    recommended: [],
    optional: [],
  };
  for (const service of SERVICES) {
    groups[service.tier].push(service);
  }
  // Sort by sortOrder within each tier
  for (const tier of Object.keys(groups) as ServiceTier[]) {
    groups[tier].sort((a, b) => a.sortOrder - b.sortOrder);
  }
  return groups;
}

export function getGoogleSsoServices(): Service[] {
  return SERVICES.filter((s) => s.supportsGoogleSso);
}

export function getServiceById(id: string): Service | undefined {
  return SERVICES.find((s) => s.id === id);
}

/** Category display names */
export const CATEGORY_NAMES: Record<ServiceCategory, string> = {
  access: 'Access & Security',
  agent: 'AI Coding Agents',
  cloud: 'Cloud Platforms',
  devtools: 'Developer Tools',
};

/** Priority display names */
export const PRIORITY_NAMES: Record<ServicePriority, string> = {
  'strongly-recommended': 'Strongly Recommended',
  recommended: 'Recommended',
  optional: 'Optional',
};

export const TIER_NAMES: Record<ServiceTier, string> = {
  essential: 'Essential',
  recommended: 'Recommended',
  optional: 'Optional',
};
