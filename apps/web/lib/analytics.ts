/**
 * ACFS Analytics Library
 * Comprehensive GA4 instrumentation for deep user insights
 */

import { safeGetItem, safeSetItem, safeGetJSON, safeSetJSON } from './utils';

// Types for GA4 events
declare global {
  interface Window {
    gtag: (
      command: 'config' | 'event' | 'set' | 'consent',
      targetId: string,
      config?: Record<string, unknown>
    ) => void;
    dataLayer: unknown[];
  }
}

// Measurement ID from environment
export const GA_MEASUREMENT_ID = process.env.NEXT_PUBLIC_GA_MEASUREMENT_ID;

// Check if analytics is available
export const isAnalyticsEnabled = (): boolean => {
  return typeof window !== 'undefined' && !!GA_MEASUREMENT_ID && !!window.gtag;
};

// Get or create a persistent client ID for server-side tracking
const getClientId = (): string => {
  if (typeof window === 'undefined') return '';
  let clientId = safeGetItem('ga_client_id');
  if (!clientId) {
    clientId = `${Date.now()}.${Math.random().toString(36).slice(2, 11)}`;
    safeSetItem('ga_client_id', clientId);
  }
  return clientId;
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
  | 'reconnect_ubuntu'
  | 'run_installer'
  | 'status_check'
  | 'launch_onboarding';

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
 * Track session start with device info
 */
export const trackSessionStart = (): void => {
  if (typeof window === 'undefined') return;

  const screenWidth = window.screen.width;
  const screenHeight = window.screen.height;
  const devicePixelRatio = window.devicePixelRatio || 1;
  const isTouchDevice = 'ontouchstart' in window;

  sendEvent('session_start_enhanced', {
    screen_width: screenWidth,
    screen_height: screenHeight,
    device_pixel_ratio: devicePixelRatio,
    is_touch_device: isTouchDevice,
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    language: navigator.language,
    platform: navigator.platform,
    user_agent_data: navigator.userAgent,
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
  conversionType: 'wizard_start' | 'wizard_complete' | 'vps_created' | 'installer_run',
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
    total_steps: 10,
    progress_percentage: Math.round((stepNumber / 10) * 100),
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
  } else if (stepNumber === 7) {
    sendEvent('funnel_milestone', {
      milestone: 'installer_step',
      funnel_id: funnelData.sessionId,
    });
  } else if (stepNumber === 10) {
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

  localStorage.setItem(FUNNEL_STORAGE_KEY, JSON.stringify(funnelData));

  // Track the completion
  sendEvent('funnel_step_complete', {
    funnel_id: funnelData.sessionId,
    step_number: stepNumber,
    step_name: stepName,
    time_on_step_seconds: timeOnStep,
    completed_steps_count: funnelData.completedSteps.length,
    total_steps: 10,
    completion_percentage: Math.round((funnelData.completedSteps.length / 10) * 100),
    ...additionalData,
  });

  // Track step-specific conversions (note: wizard_start is tracked on step 1 entry in useWizardAnalytics)
  if (stepNumber === 5) {
    trackConversion('vps_created', 10);
  } else if (stepNumber === 7) {
    trackConversion('installer_run', 50);
  } else if (stepNumber === 10) {
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
  if (!funnelData || funnelData.completedSteps.includes(10)) return;

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
    completionRate: Math.round((funnelData.completedSteps.length / 10) * 100),
  };
};
