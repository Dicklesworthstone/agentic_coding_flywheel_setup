/**
 * Agent Flywheel Analytics Library
 * Comprehensive GA4 instrumentation for deep user insights
 * Build timestamp: 2025-12-25T17:40:00Z
 */

import { safeGetItem, safeSetItem, safeGetJSON, safeSetJSON } from './utils';
import { TOTAL_STEPS } from './wizardSteps';

// Types for GA4 events
declare global {
  interface Window {
    gtag: (
      command: 'js' | 'config' | 'event' | 'set' | 'consent',
      targetId: string | Date,
      config?: Record<string, unknown>
    ) => void;
    dataLayer: unknown[];
  }
}

function sanitizeGaMeasurementId(value: unknown): string | undefined {
  if (typeof value !== 'string') return undefined;

  let cleaned = value.trim();
  if (!cleaned) return undefined;

  // Handle accidental quoting in env var values (common copy/paste mistake).
  if (
    (cleaned.startsWith('"') && cleaned.endsWith('"')) ||
    (cleaned.startsWith("'") && cleaned.endsWith("'"))
  ) {
    cleaned = cleaned.slice(1, -1).trim();
  }

  // Remove common trailing garbage (escaped newlines, whitespace sequences)
  // that can appear from misconfigured env vars or Vercel CLI pulls.
  cleaned = cleaned.replace(/\\n$/, '').replace(/\s+$/, '');

  // Extract valid GA4 measurement ID (G-XXXXXXXXXX) or legacy UA format.
  // Use extraction rather than strict matching to handle any remaining edge cases.
  const ga4Match = cleaned.match(/^(G-[A-Z0-9]+)/i);
  if (ga4Match) {
    return ga4Match[1];
  }

  const uaMatch = cleaned.match(/^(UA-\d+-\d+)/i);
  if (uaMatch) {
    return uaMatch[1];
  }

  return undefined;
}

// Measurement ID from environment (sanitized to prevent script injection / prod crashes)
const GA_MEASUREMENT_ID_RAW = process.env.NEXT_PUBLIC_GA_MEASUREMENT_ID;
export const GA_MEASUREMENT_ID = sanitizeGaMeasurementId(GA_MEASUREMENT_ID_RAW);

// Check if analytics is available
export const isAnalyticsEnabled = (): boolean => {
  return typeof window !== 'undefined' && !!GA_MEASUREMENT_ID && !!window.gtag;
};

const GA_CLIENT_ID_STORAGE_KEY = 'ga_client_id';
const MAX_GA_CLIENT_ID_LENGTH = 100;

function isNumericGaClientId(value: string): boolean {
  if (!value || value.length > MAX_GA_CLIENT_ID_LENGTH) return false;
  return /^\d{1,16}\.\d{1,16}$/.test(value);
}

function fnv1a32(input: string): number {
  let hash = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    hash ^= input.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return hash >>> 0;
}

function randomDigits10(): string {
  const digits = 10;

  try {
    if (typeof crypto !== 'undefined' && 'getRandomValues' in crypto) {
      const values = new Uint32Array(2);
      crypto.getRandomValues(values);
      // Combine into a 53-bit safe integer (avoid BigInt; TS target < ES2020).
      const combined = (values[0] & 0x001fffff) * 0x100000000 + values[1];
      return (combined % 10_000_000_000).toString().padStart(digits, '0');
    }
  } catch {
    // Fall back to Math.random for older/locked-down environments.
  }

  return Math.floor(Math.random() * 10 ** digits)
    .toString()
    .padStart(digits, '0');
}

function generateNumericClientId(): string {
  const randomPart = randomDigits10();
  const timestampSeconds = Math.floor(Date.now() / 1000);
  return `${randomPart}.${timestampSeconds}`;
}

function normalizeClientId(raw: string): string {
  if (isNumericGaClientId(raw)) return raw;

  // Migrate legacy format: "<timestamp_ms>.<base36>" → "<randomDigits>.<timestamp_seconds>"
  const legacyMatch = /^(\d{1,16})\.([a-z0-9]{1,32})$/i.exec(raw);
  if (legacyMatch) {
    const legacyTimestamp = Number(legacyMatch[1]);
    const legacySuffix = legacyMatch[2];
    if (Number.isSafeInteger(legacyTimestamp) && legacyTimestamp > 0) {
      const timestampSeconds =
        legacyMatch[1].length > 10 ? Math.floor(legacyTimestamp / 1000) : legacyTimestamp;
      const randomPart = (fnv1a32(legacySuffix) % 10 ** 10).toString().padStart(10, '0');
      const migrated = `${randomPart}.${timestampSeconds}`;
      if (isNumericGaClientId(migrated)) return migrated;
    }
  }

  return generateNumericClientId();
}

// Get or create a persistent client ID for server-side tracking
const getClientId = (): string => {
  if (typeof window === 'undefined') return '';
  const existing = safeGetItem(GA_CLIENT_ID_STORAGE_KEY);
  const normalized = existing ? normalizeClientId(existing) : generateNumericClientId();
  if (!existing || normalized !== existing) {
    safeSetItem(GA_CLIENT_ID_STORAGE_KEY, normalized);
  }
  return normalized;
};

/**
 * Server-side event tracking via Measurement Protocol
 * Bypasses ad blockers for reliable tracking
 */
export const sendServerEvent = async (
  eventName: string,
  params?: Record<string, string | number | boolean>
): Promise<void> => {
  if (typeof window === 'undefined') return;
  if (!GA_MEASUREMENT_ID) return;

  try {
    await fetch('/api/track', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        client_id: getClientId(),
        events: [{ name: eventName, params }],
      }),
    });
  } catch {
    // Silently fail - don't disrupt user experience
  }
};

// ============================================================
// Core Event Tracking
// ============================================================

/**
 * Send a custom event to GA4
 */
export const sendEvent = (
  eventName: string,
  parameters?: Record<string, unknown>
): void => {
  if (!isAnalyticsEnabled()) return;

  window.gtag('event', eventName, {
    ...parameters,
    timestamp: new Date().toISOString(),
  });
};

/**
 * Set user properties for segmentation
 */
export const setUserProperties = (
  properties: Record<string, string | number | boolean>
): void => {
  if (!isAnalyticsEnabled()) return;

  window.gtag('set', 'user_properties', properties);
};

// ============================================================
// Wizard Step Tracking
// ============================================================

export type WizardStep =
  | 'os_selection'
  | 'rent_vps'
  | 'create_vps'
  | 'install_terminal'
  | 'generate_ssh_key'
  | 'ssh_connect'
  | 'accounts'
  | 'preflight_check'
  | 'verify_key_connection'
  | 'reconnect_ubuntu'
  | 'run_installer'
  | 'status_check'
  | 'launch_onboarding'
  | 'windows_terminal_setup';

/**
 * Track wizard step views
 */
export const trackWizardStep = (
  step: WizardStep,
  stepNumber: number,
  additionalParams?: Record<string, unknown>
): void => {
  sendEvent('wizard_step_view', {
    step_name: step,
    step_number: stepNumber,
    ...additionalParams,
  });
};

/**
 * Track wizard step completion
 */
export const trackWizardStepComplete = (
  step: WizardStep,
  stepNumber: number,
  timeSpentSeconds?: number
): void => {
  sendEvent('wizard_step_complete', {
    step_name: step,
    step_number: stepNumber,
    time_spent_seconds: timeSpentSeconds,
  });
};

/**
 * Track wizard abandonment
 */
export const trackWizardAbandonment = (
  lastStep: WizardStep,
  lastStepNumber: number,
  reason?: string
): void => {
  sendEvent('wizard_abandoned', {
    last_step: lastStep,
    last_step_number: lastStepNumber,
    abandonment_reason: reason,
  });
};

/**
 * Track wizard completion
 */
export const trackWizardComplete = (
  totalTimeSeconds: number,
  stepsCompleted: number
): void => {
  sendEvent('wizard_complete', {
    total_time_seconds: totalTimeSeconds,
    steps_completed: stepsCompleted,
  });
};

// ============================================================
// User Engagement Tracking
// ============================================================

/**
 * Track scroll depth milestones
 */
export const trackScrollDepth = (
  depth: 25 | 50 | 75 | 90 | 100,
  pagePath: string
): void => {
  sendEvent('scroll_depth', {
    depth_percentage: depth,
    page_path: pagePath,
  });
};

/**
 * Track time on page milestones
 */
export const trackTimeOnPage = (
  seconds: number,
  pagePath: string
): void => {
  sendEvent('time_on_page', {
    seconds_elapsed: seconds,
    page_path: pagePath,
  });
};

/**
 * Track user interactions
 */
export const trackInteraction = (
  interactionType: 'click' | 'hover' | 'focus' | 'copy' | 'paste',
  elementId: string,
  elementType: string,
  additionalParams?: Record<string, unknown>
): void => {
  sendEvent('user_interaction', {
    interaction_type: interactionType,
    element_id: elementId,
    element_type: elementType,
    ...additionalParams,
  });
};

// ============================================================
// Feature-Specific Tracking
// ============================================================

/**
 * Track OS selection
 */
export const trackOSSelection = (os: string): void => {
  sendEvent('os_selected', {
    os_name: os,
  });
  setUserProperties({ selected_os: os });
};

/**
 * Track VPS provider selection
 */
export const trackVPSProviderSelection = (provider: string): void => {
  sendEvent('vps_provider_selected', {
    provider_name: provider,
  });
  setUserProperties({ vps_provider: provider });
};

/**
 * Track terminal selection
 */
export const trackTerminalSelection = (terminal: string): void => {
  sendEvent('terminal_selected', {
    terminal_name: terminal,
  });
  setUserProperties({ terminal_app: terminal });
};

/**
 * Track SSH key generation
 */
export const trackSSHKeyGeneration = (
  keyType: 'ed25519' | 'rsa',
  success: boolean
): void => {
  sendEvent('ssh_key_generated', {
    key_type: keyType,
    success,
  });
};

/**
 * Track SSH connection attempt
 */
export const trackSSHConnection = (
  success: boolean,
  errorType?: string
): void => {
  sendEvent('ssh_connection_attempt', {
    success,
    error_type: errorType,
  });
};

/**
 * Track installer command copy
 */
export const trackInstallerCopy = (command: string): void => {
  sendEvent('installer_command_copied', {
    command_length: command.length,
    command_preview: command.slice(0, 50),
  });
};

/**
 * Track installation start
 */
export const trackInstallationStart = (): void => {
  sendEvent('installation_started', {
    start_time: new Date().toISOString(),
  });
};

/**
 * Track installation completion
 */
export const trackInstallationComplete = (
  durationMinutes: number,
  success: boolean
): void => {
  sendEvent('installation_complete', {
    duration_minutes: durationMinutes,
    success,
  });
};

// ============================================================
// Error Tracking
// ============================================================

/**
 * Track errors
 */
export const trackError = (
  errorType: string,
  errorMessage: string,
  errorStack?: string,
  context?: Record<string, unknown>
): void => {
  sendEvent('error_occurred', {
    error_type: errorType,
    error_message: errorMessage,
    error_stack: errorStack?.slice(0, 500),
    ...context,
  });
};

/**
 * Track API errors
 */
export const trackAPIError = (
  endpoint: string,
  statusCode: number,
  errorMessage: string
): void => {
  sendEvent('api_error', {
    endpoint,
    status_code: statusCode,
    error_message: errorMessage,
  });
};

// ============================================================
// Performance Tracking
// ============================================================

/**
 * Track page load performance
 */
export const trackPagePerformance = (): void => {
  if (typeof window === 'undefined' || !window.performance) return;

  const timing = performance.getEntriesByType('navigation')[0] as PerformanceNavigationTiming;

  if (!timing) return;

  sendEvent('page_performance', {
    dns_lookup_ms: Math.round(timing.domainLookupEnd - timing.domainLookupStart),
    tcp_connect_ms: Math.round(timing.connectEnd - timing.connectStart),
    ttfb_ms: Math.round(timing.responseStart - timing.requestStart),
    dom_interactive_ms: Math.round(timing.domInteractive - timing.startTime),
    dom_complete_ms: Math.round(timing.domComplete - timing.startTime),
    load_complete_ms: Math.round(timing.loadEventEnd - timing.startTime),
  });
};

/**
 * Track Core Web Vitals
 */
export const trackWebVitals = (metric: {
  name: string;
  value: number;
  id: string;
}): void => {
  sendEvent('web_vitals', {
    metric_name: metric.name,
    metric_value: Math.round(metric.value),
    metric_id: metric.id,
  });
};

// ============================================================
// Outbound Link Tracking
// ============================================================

/**
 * Track outbound link clicks
 */
export const trackOutboundLink = (
  url: string,
  linkText: string
): void => {
  let linkDomain = 'unknown';
  try {
    linkDomain = new URL(url).hostname;
  } catch {
    // Invalid URL, use fallback
  }

  sendEvent('outbound_link_click', {
    link_url: url,
    link_text: linkText,
    link_domain: linkDomain,
  });
};

// ============================================================
// Session & User Tracking
// ============================================================

/**
 * Extract UTM parameters and referrer from current URL
 */
function getAcquisitionData(): {
  utm_source: string;
  utm_medium: string;
  utm_campaign: string;
  utm_term: string;
  utm_content: string;
  referrer: string;
  referrer_domain: string;
  landing_page: string;
} {
  if (typeof window === 'undefined') {
    return {
      utm_source: 'direct',
      utm_medium: 'none',
      utm_campaign: '',
      utm_term: '',
      utm_content: '',
      referrer: '',
      referrer_domain: '',
      landing_page: '',
    };
  }

  const params = new URLSearchParams(window.location.search);
  const referrer = document.referrer || '';
  let referrerDomain = '';

  try {
    if (referrer) {
      referrerDomain = new URL(referrer).hostname;
    }
  } catch {
    // Invalid URL
  }

  // Determine source from UTM or referrer
  let source = params.get('utm_source') || '';
  let medium = params.get('utm_medium') || '';

  if (!source && referrer) {
    // Infer source from referrer
    if (referrerDomain.includes('google')) {
      source = 'google';
      medium = medium || 'organic';
    } else if (referrerDomain.includes('bing')) {
      source = 'bing';
      medium = medium || 'organic';
    } else if (referrerDomain.includes('twitter') || referrerDomain.includes('x.com') || referrerDomain.includes('t.co')) {
      source = 'twitter';
      medium = medium || 'social';
    } else if (referrerDomain.includes('linkedin')) {
      source = 'linkedin';
      medium = medium || 'social';
    } else if (referrerDomain.includes('facebook')) {
      source = 'facebook';
      medium = medium || 'social';
    } else if (referrerDomain.includes('reddit')) {
      source = 'reddit';
      medium = medium || 'social';
    } else if (referrerDomain.includes('github')) {
      source = 'github';
      medium = medium || 'referral';
    } else if (referrerDomain.includes('news.ycombinator') || referrerDomain.includes('hn.algolia')) {
      source = 'hackernews';
      medium = medium || 'social';
    } else if (referrerDomain) {
      source = referrerDomain;
      medium = medium || 'referral';
    }
  }

  return {
    utm_source: source || 'direct',
    utm_medium: medium || 'none',
    utm_campaign: params.get('utm_campaign') || '',
    utm_term: params.get('utm_term') || '',
    utm_content: params.get('utm_content') || '',
    referrer,
    referrer_domain: referrerDomain,
    landing_page: window.location.pathname,
  };
}

const FIRST_VISIT_KEY = 'acfs_first_visit';
const FIRST_SOURCE_KEY = 'acfs_first_source';

/**
 * Detect platform from user agent
 */
function detectPlatform(): string {
  if (typeof navigator === 'undefined') return 'unknown';

  const ua = navigator.userAgent;
  if (ua.includes('Mac')) return 'macOS';
  if (ua.includes('Win')) return 'Windows';
  if (ua.includes('Linux') && !ua.includes('Android')) return 'Linux';
  if (ua.includes('iPhone') || ua.includes('iPad')) return 'iOS';
  if (ua.includes('Android')) return 'Android';
  return 'unknown';
}

/**
 * Track session start with device info, UTM parameters, and referrer
 */
export const trackSessionStart = (): void => {
  if (typeof window === 'undefined') return;

  const screenWidth = window.screen.width;
  const screenHeight = window.screen.height;
  const devicePixelRatio = window.devicePixelRatio || 1;
  const isTouchDevice = 'ontouchstart' in window;
  const acquisition = getAcquisitionData();

  // Check for first visit
  const isFirstVisit = !safeGetItem(FIRST_VISIT_KEY);
  const now = new Date().toISOString();

  if (isFirstVisit) {
    safeSetItem(FIRST_VISIT_KEY, now);
    safeSetJSON(FIRST_SOURCE_KEY, {
      source: acquisition.utm_source,
      medium: acquisition.utm_medium,
      campaign: acquisition.utm_campaign,
      landing_page: acquisition.landing_page,
      referrer: acquisition.referrer,
    });
  }

  // Get first visit data for user properties
  const firstVisitDate = safeGetItem(FIRST_VISIT_KEY) || now;
  const firstSource = safeGetJSON<{
    source: string;
    medium: string;
    campaign: string;
    landing_page: string;
  }>(FIRST_SOURCE_KEY);

  sendEvent('session_start_enhanced', {
    // Device info
    screen_width: screenWidth,
    screen_height: screenHeight,
    device_pixel_ratio: devicePixelRatio,
    is_touch_device: isTouchDevice,
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    language: navigator.language,
    platform: detectPlatform(),
    // Acquisition data
    utm_source: acquisition.utm_source,
    utm_medium: acquisition.utm_medium,
    utm_campaign: acquisition.utm_campaign,
    utm_term: acquisition.utm_term,
    utm_content: acquisition.utm_content,
    referrer: acquisition.referrer,
    referrer_domain: acquisition.referrer_domain,
    landing_page: acquisition.landing_page,
    is_first_visit: isFirstVisit,
  });

  // Check for returning user
  const visitCount = parseInt(safeGetItem('acfs_visit_count') || '0', 10) + 1;
  safeSetItem('acfs_visit_count', String(visitCount));

  // Set comprehensive user properties
  setUserProperties({
    // Visit tracking
    visit_count: visitCount,
    is_returning_user: visitCount > 1,
    // First visit attribution (persists across sessions)
    first_visit_date: firstVisitDate,
    first_traffic_source: firstSource?.source || acquisition.utm_source,
    first_traffic_medium: firstSource?.medium || acquisition.utm_medium,
    first_landing_page: firstSource?.landing_page || acquisition.landing_page,
    // Current session attribution
    latest_traffic_source: acquisition.utm_source,
    latest_traffic_medium: acquisition.utm_medium,
    // UTM parameters
    utm_source: acquisition.utm_source,
    utm_medium: acquisition.utm_medium,
    utm_campaign: acquisition.utm_campaign,
    utm_term: acquisition.utm_term,
    utm_content: acquisition.utm_content,
  });
};

/**
 * Get or create a persistent user ID for cross-session tracking
 */
export const getOrCreateUserId = (): string => {
  if (typeof window === 'undefined') return '';

  const storageKey = 'acfs_user_id';
  let userId = safeGetItem(storageKey);

  if (!userId) {
    userId = `user_${Date.now()}_${Math.random().toString(36).slice(2, 11)}`;
    safeSetItem(storageKey, userId);

    sendEvent('new_user_created', {
      user_id: userId,
    });
  }

  return userId;
};

// ============================================================
// Conversion Tracking
// ============================================================

/**
 * Track key conversions (dual client + server-side for reliability)
 */
export const trackConversion = (
  conversionType: 'wizard_start' | 'wizard_complete' | 'vps_created' | 'installer_run' | 'learning_hub_started' | 'lesson_funnel_complete',
  value?: number
): void => {
  const params = {
    conversion_type: conversionType,
    conversion_value: value ?? 0,
  };

  // Client-side tracking (fast, may be blocked)
  sendEvent('conversion', params);

  // Server-side tracking (reliable, bypasses ad blockers)
  sendServerEvent('conversion', params);
};

// ============================================================
// A/B Test Tracking
// ============================================================

/**
 * Track A/B test variant assignment
 */
export const trackExperimentVariant = (
  experimentId: string,
  variantId: string
): void => {
  sendEvent('experiment_variant', {
    experiment_id: experimentId,
    variant_id: variantId,
  });

  setUserProperties({
    [`experiment_${experimentId}`]: variantId,
  });
};

// ============================================================
// Funnel Tracking
// ============================================================

const FUNNEL_STORAGE_KEY = 'acfs_funnel_data';

interface FunnelData {
  sessionId: string;
  startedAt: string;
  currentStep: number;
  maxStepReached: number;
  stepTimestamps: Record<number, { entered: string; completed?: string }>;
  completedSteps: number[];
  source: string;
  medium: string;
  campaign: string;
}

/**
 * Get or initialize funnel tracking data
 */
export const getFunnelData = (): FunnelData | null => {
  if (typeof window === 'undefined') return null;
  return safeGetJSON<FunnelData>(FUNNEL_STORAGE_KEY);
};

/**
 * Initialize a new funnel session
 */
export const initFunnel = (): FunnelData => {
  if (typeof window === 'undefined') {
    return {
      sessionId: '',
      startedAt: new Date().toISOString(),
      currentStep: 0,
      maxStepReached: 0,
      stepTimestamps: {},
      completedSteps: [],
      source: '',
      medium: '',
      campaign: '',
    };
  }

  // Parse UTM parameters
  const params = new URLSearchParams(window.location.search);

  const funnelData: FunnelData = {
    sessionId: `funnel_${Date.now()}_${Math.random().toString(36).slice(2, 11)}`,
    startedAt: new Date().toISOString(),
    currentStep: 0,
    maxStepReached: 0,
    stepTimestamps: {},
    completedSteps: [],
    source: params.get('utm_source') || document.referrer || 'direct',
    medium: params.get('utm_medium') || 'none',
    campaign: params.get('utm_campaign') || 'none',
  };

  safeSetJSON(FUNNEL_STORAGE_KEY, funnelData);

  // Track funnel initiation
  sendEvent('funnel_initiated', {
    funnel_id: funnelData.sessionId,
    source: funnelData.source,
    medium: funnelData.medium,
    campaign: funnelData.campaign,
    referrer: document.referrer,
  });

  setUserProperties({
    funnel_source: funnelData.source,
    funnel_medium: funnelData.medium,
    funnel_campaign: funnelData.campaign,
  });

  return funnelData;
};

/**
 * Track entering a funnel step
 */
export const trackFunnelStepEnter = (
  stepNumber: number,
  stepName: string,
  stepTitle: string
): void => {
  if (typeof window === 'undefined') return;

  let funnelData = getFunnelData();
  if (!funnelData) {
    funnelData = initFunnel();
  }

  const now = new Date().toISOString();
  const previousStep = funnelData.currentStep;
  const isNewMaxStep = stepNumber > funnelData.maxStepReached;

  // Update funnel data
  funnelData.currentStep = stepNumber;
  funnelData.maxStepReached = Math.max(funnelData.maxStepReached, stepNumber);
  funnelData.stepTimestamps[stepNumber] = {
    ...funnelData.stepTimestamps[stepNumber],
    entered: now,
  };

  safeSetJSON(FUNNEL_STORAGE_KEY, funnelData);

  // Calculate time from previous step
  let timeFromPreviousStep: number | undefined;
  if (previousStep > 0 && funnelData.stepTimestamps[previousStep]?.entered) {
    const prevTime = new Date(funnelData.stepTimestamps[previousStep].entered).getTime();
    timeFromPreviousStep = Math.round((Date.now() - prevTime) / 1000);
  }

  // Track the funnel step entry
  sendEvent('funnel_step_enter', {
    funnel_id: funnelData.sessionId,
    step_number: stepNumber,
    step_name: stepName,
    step_title: stepTitle,
    previous_step: previousStep,
    is_new_max_step: isNewMaxStep,
    max_step_reached: funnelData.maxStepReached,
    time_from_previous_step_seconds: timeFromPreviousStep,
    total_steps: TOTAL_STEPS,
    progress_percentage: Math.round((stepNumber / TOTAL_STEPS) * 100),
    is_returning: !isNewMaxStep && stepNumber <= funnelData.maxStepReached,
  });

  // Track as conversion milestone for key steps
  if (stepNumber === 1) {
    sendEvent('funnel_milestone', {
      milestone: 'wizard_started',
      funnel_id: funnelData.sessionId,
    });
  } else if (stepNumber === 4) {
    sendEvent('funnel_milestone', {
      milestone: 'vps_selection',
      funnel_id: funnelData.sessionId,
    });
  } else if (stepNumber === 9) {
    sendEvent('funnel_milestone', {
      milestone: 'installer_step',
      funnel_id: funnelData.sessionId,
    });
  } else if (stepNumber === TOTAL_STEPS) {
    sendEvent('funnel_milestone', {
      milestone: 'final_step',
      funnel_id: funnelData.sessionId,
    });
  }
};

/**
 * Track completing a funnel step
 */
export const trackFunnelStepComplete = (
  stepNumber: number,
  stepName: string,
  additionalData?: Record<string, unknown>
): void => {
  if (typeof window === 'undefined') return;

  const funnelData = getFunnelData();
  if (!funnelData) return;

  const now = new Date().toISOString();

  // Calculate time spent on step
  let timeOnStep: number | undefined;
  if (funnelData.stepTimestamps[stepNumber]?.entered) {
    const enterTime = new Date(funnelData.stepTimestamps[stepNumber].entered).getTime();
    timeOnStep = Math.round((Date.now() - enterTime) / 1000);
  }

  // Update funnel data
  if (!funnelData.completedSteps.includes(stepNumber)) {
    funnelData.completedSteps.push(stepNumber);
    funnelData.completedSteps.sort((a, b) => a - b);
  }
  funnelData.stepTimestamps[stepNumber] = {
    ...funnelData.stepTimestamps[stepNumber],
    completed: now,
  };

  safeSetJSON(FUNNEL_STORAGE_KEY, funnelData);

  // Track the completion
  sendEvent('funnel_step_complete', {
    funnel_id: funnelData.sessionId,
    step_number: stepNumber,
    step_name: stepName,
    time_on_step_seconds: timeOnStep,
    completed_steps_count: funnelData.completedSteps.length,
    total_steps: TOTAL_STEPS,
    completion_percentage: Math.round((funnelData.completedSteps.length / TOTAL_STEPS) * 100),
    ...additionalData,
  });

  // Track step-specific conversions (note: wizard_start is tracked on step 1 entry in useWizardAnalytics)
  if (stepNumber === 5) {
    trackConversion('vps_created', 10);
  } else if (stepNumber === 9) {
    trackConversion('installer_run', 50);
  } else if (stepNumber === TOTAL_STEPS) {
    trackFunnelComplete();
  }
};

/**
 * Track funnel completion
 */
export const trackFunnelComplete = (): void => {
  if (typeof window === 'undefined') return;

  const funnelData = getFunnelData();
  if (!funnelData) return;

  const startTime = new Date(funnelData.startedAt).getTime();
  const totalTimeSeconds = Math.round((Date.now() - startTime) / 1000);
  const totalTimeMinutes = Math.round(totalTimeSeconds / 60);

  sendEvent('funnel_complete', {
    funnel_id: funnelData.sessionId,
    total_time_seconds: totalTimeSeconds,
    total_time_minutes: totalTimeMinutes,
    completed_steps: funnelData.completedSteps.length,
    max_step_reached: funnelData.maxStepReached,
    source: funnelData.source,
    medium: funnelData.medium,
    campaign: funnelData.campaign,
  });

  trackConversion('wizard_complete', 100);

  // Set user property for completed users
  setUserProperties({
    wizard_completed: true,
    wizard_completion_date: new Date().toISOString(),
    wizard_completion_time_minutes: totalTimeMinutes,
  });
};

/**
 * Track funnel drop-off (called on page exit or navigation away)
 */
export const trackFunnelDropoff = (reason?: string): void => {
  if (typeof window === 'undefined') return;

  const funnelData = getFunnelData();
  if (!funnelData || funnelData.completedSteps.includes(TOTAL_STEPS)) return;

  const startTime = new Date(funnelData.startedAt).getTime();
  const totalTimeSeconds = Math.round((Date.now() - startTime) / 1000);

  // Calculate time on current step
  let timeOnCurrentStep: number | undefined;
  if (funnelData.stepTimestamps[funnelData.currentStep]?.entered) {
    const enterTime = new Date(funnelData.stepTimestamps[funnelData.currentStep].entered).getTime();
    timeOnCurrentStep = Math.round((Date.now() - enterTime) / 1000);
  }

  sendEvent('funnel_dropoff', {
    funnel_id: funnelData.sessionId,
    dropped_at_step: funnelData.currentStep,
    max_step_reached: funnelData.maxStepReached,
    completed_steps_count: funnelData.completedSteps.length,
    total_time_seconds: totalTimeSeconds,
    time_on_current_step_seconds: timeOnCurrentStep,
    dropoff_reason: reason || 'unknown',
    source: funnelData.source,
    medium: funnelData.medium,
  });
};

/**
 * Track CTA clicks on landing page
 */
export const trackLandingCTA = (
  ctaType: 'hero_start' | 'feature_start' | 'footer_start' | 'nav_start',
  ctaText: string
): void => {
  sendEvent('landing_cta_click', {
    cta_type: ctaType,
    cta_text: ctaText,
    page_scroll_depth: typeof window !== 'undefined'
      ? (() => {
          const scrollableHeight = document.documentElement.scrollHeight - window.innerHeight;
          return scrollableHeight > 0
            ? Math.round((window.scrollY / scrollableHeight) * 100)
            : 0;
        })()
      : 0,
  });

  // Initialize funnel on CTA click
  initFunnel();
};

/**
 * Track landing page engagement
 */
export const trackLandingEngagement = (
  engagementType: 'feature_view' | 'step_preview' | 'faq_expand' | 'video_play',
  details?: Record<string, unknown>
): void => {
  sendEvent('landing_engagement', {
    engagement_type: engagementType,
    ...details,
  });
};

// ============================================================
// Learning Hub Funnel Tracking
// ============================================================

const LESSON_FUNNEL_STORAGE_KEY = 'acfs_lesson_funnel_data';

interface LessonFunnelData {
  sessionId: string;
  startedAt: string;
  currentLesson: number;
  maxLessonReached: number;
  lessonTimestamps: Record<number, { entered?: string; completed?: string }>;
  completedLessons: number[];
  source: string;
  medium: string;
  campaign: string;
}

/**
 * Get current lesson funnel data from storage
 */
export const getLessonFunnelData = (): LessonFunnelData | null => {
  if (typeof window === 'undefined') return null;
  return safeGetJSON<LessonFunnelData>(LESSON_FUNNEL_STORAGE_KEY);
};

/**
 * Initialize a new lesson funnel session
 */
export const initLessonFunnel = (totalLessons: number): LessonFunnelData => {
  if (typeof window === 'undefined') {
    return {
      sessionId: '',
      startedAt: new Date().toISOString(),
      currentLesson: 0,
      maxLessonReached: 0,
      lessonTimestamps: {},
      completedLessons: [],
      source: '',
      medium: '',
      campaign: '',
    };
  }

  // Parse UTM parameters
  const params = new URLSearchParams(window.location.search);

  const funnelData: LessonFunnelData = {
    sessionId: `lesson_funnel_${Date.now()}_${Math.random().toString(36).slice(2, 11)}`,
    startedAt: new Date().toISOString(),
    currentLesson: 0,
    maxLessonReached: 0,
    lessonTimestamps: {},
    completedLessons: [],
    source: params.get('utm_source') || document.referrer || 'direct',
    medium: params.get('utm_medium') || 'none',
    campaign: params.get('utm_campaign') || 'none',
  };

  safeSetJSON(LESSON_FUNNEL_STORAGE_KEY, funnelData);

  // Track lesson funnel initiation
  sendEvent('lesson_funnel_initiated', {
    funnel_id: funnelData.sessionId,
    source: funnelData.source,
    medium: funnelData.medium,
    campaign: funnelData.campaign,
    referrer: document.referrer,
    total_lessons: totalLessons,
  });

  // Track as conversion
  trackConversion('learning_hub_started');

  setUserProperties({
    lesson_funnel_source: funnelData.source,
    lesson_funnel_medium: funnelData.medium,
  });

  return funnelData;
};

/**
 * Track entering a lesson
 */
export const trackLessonEnter = (
  lessonId: number,
  lessonSlug: string,
  lessonTitle: string,
  totalLessons: number
): void => {
  if (typeof window === 'undefined') return;

  let funnelData = getLessonFunnelData();
  if (!funnelData) {
    funnelData = initLessonFunnel(totalLessons);
  }

  const now = new Date().toISOString();
  const previousLesson = funnelData.currentLesson;
  const isNewMaxLesson = lessonId > funnelData.maxLessonReached;

  // Update funnel data
  funnelData.currentLesson = lessonId;
  funnelData.maxLessonReached = Math.max(funnelData.maxLessonReached, lessonId);
  funnelData.lessonTimestamps[lessonId] = {
    ...funnelData.lessonTimestamps[lessonId],
    entered: now,
  };

  safeSetJSON(LESSON_FUNNEL_STORAGE_KEY, funnelData);

  // Calculate time from previous lesson (only if visiting a different lesson)
  let timeFromPreviousLesson: number | undefined;
  if (previousLesson >= 0 && previousLesson !== lessonId && funnelData.lessonTimestamps[previousLesson]?.entered) {
    const prevTime = new Date(funnelData.lessonTimestamps[previousLesson].entered!).getTime();
    timeFromPreviousLesson = Math.round((Date.now() - prevTime) / 1000);
  }

  // Track the lesson entry
  sendEvent('lesson_view', {
    funnel_id: funnelData.sessionId,
    lesson_id: lessonId,
    lesson_slug: lessonSlug,
    lesson_title: lessonTitle,
    previous_lesson: previousLesson,
    is_new_max_lesson: isNewMaxLesson,
    max_lesson_reached: funnelData.maxLessonReached,
    time_from_previous_lesson_seconds: timeFromPreviousLesson,
    total_lessons: totalLessons,
    progress_percentage: Math.round(((lessonId + 1) / totalLessons) * 100),
    is_returning: !isNewMaxLesson && lessonId <= funnelData.maxLessonReached,
    source: funnelData.source,
    medium: funnelData.medium,
    campaign: funnelData.campaign,
  });

  // Track milestones
  if (lessonId === 0) {
    sendEvent('lesson_milestone', {
      milestone: 'learning_started',
      funnel_id: funnelData.sessionId,
    });
  } else if (lessonId === Math.floor(totalLessons / 2)) {
    sendEvent('lesson_milestone', {
      milestone: 'halfway_point',
      funnel_id: funnelData.sessionId,
    });
  } else if (lessonId === totalLessons - 1) {
    sendEvent('lesson_milestone', {
      milestone: 'final_lesson',
      funnel_id: funnelData.sessionId,
    });
  }
};

/**
 * Track completing a lesson
 */
export const trackLessonComplete = (
  lessonId: number,
  lessonSlug: string,
  lessonTitle: string,
  totalLessons: number,
  additionalData?: Record<string, unknown>
): void => {
  if (typeof window === 'undefined') return;

  const funnelData = getLessonFunnelData();
  if (!funnelData) return;

  const now = new Date().toISOString();

  // Calculate time spent on lesson
  let timeOnLesson: number | undefined;
  if (funnelData.lessonTimestamps[lessonId]?.entered) {
    const enterTime = new Date(funnelData.lessonTimestamps[lessonId].entered!).getTime();
    timeOnLesson = Math.round((Date.now() - enterTime) / 1000);
  }

  // Update funnel data
  if (!funnelData.completedLessons.includes(lessonId)) {
    funnelData.completedLessons.push(lessonId);
    funnelData.completedLessons.sort((a, b) => a - b);
  }
  funnelData.lessonTimestamps[lessonId] = {
    ...funnelData.lessonTimestamps[lessonId],
    completed: now,
  };

  safeSetJSON(LESSON_FUNNEL_STORAGE_KEY, funnelData);

  // Track the completion
  sendEvent('lesson_complete', {
    funnel_id: funnelData.sessionId,
    lesson_id: lessonId,
    lesson_slug: lessonSlug,
    lesson_title: lessonTitle,
    time_on_lesson_seconds: timeOnLesson,
    completed_lessons_count: funnelData.completedLessons.length,
    total_lessons: totalLessons,
    completion_percentage: Math.round((funnelData.completedLessons.length / totalLessons) * 100),
    source: funnelData.source,
    medium: funnelData.medium,
    ...additionalData,
  });

  // Also send server-side for reliability
  sendServerEvent('lesson_complete', {
    lesson_id: lessonId,
    lesson_slug: lessonSlug,
    completion_percentage: Math.round((funnelData.completedLessons.length / totalLessons) * 100),
  });

  // Check for full completion
  if (funnelData.completedLessons.length === totalLessons) {
    trackLessonFunnelComplete(totalLessons);
  }
};

/**
 * Track full lesson funnel completion
 */
export const trackLessonFunnelComplete = (totalLessons: number): void => {
  if (typeof window === 'undefined') return;

  const funnelData = getLessonFunnelData();
  if (!funnelData) return;

  const startTime = new Date(funnelData.startedAt).getTime();
  const totalTimeSeconds = Math.round((Date.now() - startTime) / 1000);

  sendEvent('lesson_funnel_complete', {
    funnel_id: funnelData.sessionId,
    total_time_seconds: totalTimeSeconds,
    total_time_minutes: Math.round(totalTimeSeconds / 60),
    total_lessons: totalLessons,
    lessons_completed: funnelData.completedLessons.length,
    source: funnelData.source,
    medium: funnelData.medium,
  });

  // Track as major conversion with value
  trackConversion('lesson_funnel_complete', 100);

  // Also send server-side for reliability
  sendServerEvent('lesson_funnel_complete', {
    total_time_minutes: Math.round(totalTimeSeconds / 60),
    total_lessons: totalLessons,
  });
};

/**
 * Track lesson funnel dropoff
 */
export const trackLessonDropoff = (reason?: string): void => {
  if (typeof window === 'undefined') return;

  const funnelData = getLessonFunnelData();
  if (!funnelData) return;

  const startTime = new Date(funnelData.startedAt).getTime();
  const totalTimeSeconds = Math.round((Date.now() - startTime) / 1000);

  sendEvent('lesson_funnel_dropoff', {
    funnel_id: funnelData.sessionId,
    dropped_at_lesson: funnelData.currentLesson,
    max_lesson_reached: funnelData.maxLessonReached,
    completed_lessons: funnelData.completedLessons.length,
    time_in_funnel_seconds: totalTimeSeconds,
    dropoff_reason: reason || 'unknown',
    source: funnelData.source,
    medium: funnelData.medium,
  });
};

/**
 * Get lesson funnel analytics summary (for debugging)
 */
export const getLessonFunnelSummary = (totalLessons: number): Record<string, unknown> | null => {
  const funnelData = getLessonFunnelData();
  if (!funnelData) return null;

  const startTime = new Date(funnelData.startedAt).getTime();
  const totalTimeSeconds = Math.round((Date.now() - startTime) / 1000);

  return {
    funnelId: funnelData.sessionId,
    currentLesson: funnelData.currentLesson,
    maxLessonReached: funnelData.maxLessonReached,
    completedLessons: funnelData.completedLessons,
    totalTimeMinutes: Math.round(totalTimeSeconds / 60),
    source: funnelData.source,
    completionRate: Math.round((funnelData.completedLessons.length / totalLessons) * 100),
  };
};

// ============================================================
// Debug Mode
// ============================================================

/**
 * Enable debug mode for development
 */
export const enableDebugMode = (): void => {
  if (typeof window === 'undefined' || !GA_MEASUREMENT_ID) return;

  // GA4 debug mode
  if (window.gtag) {
    window.gtag('config', GA_MEASUREMENT_ID, {
      debug_mode: true,
    });
  }

  console.log('[Analytics] Debug mode enabled');
};

/**
 * Get funnel analytics summary (for debugging)
 */
export const getFunnelSummary = (): Record<string, unknown> | null => {
  const funnelData = getFunnelData();
  if (!funnelData) return null;

  const startTime = new Date(funnelData.startedAt).getTime();
  const totalTimeSeconds = Math.round((Date.now() - startTime) / 1000);

  return {
    funnelId: funnelData.sessionId,
    currentStep: funnelData.currentStep,
    maxStepReached: funnelData.maxStepReached,
    completedSteps: funnelData.completedSteps,
    totalTimeMinutes: Math.round(totalTimeSeconds / 60),
    source: funnelData.source,
    completionRate: Math.round((funnelData.completedSteps.length / TOTAL_STEPS) * 100),
  };
};
