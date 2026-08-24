'use client';

import {
  useEffect,
  useCallback,
  useLayoutEffect,
  useRef,
  useState,
  type ReactNode,
  Suspense,
} from 'react';
import { usePathname, useSearchParams } from 'next/navigation';
import Script from 'next/script';
import {
  GA_MEASUREMENT_ID,
  analyticsContextContainsSensitiveState,
  disableAnalyticsForDocument,
  isAnalyticsPrivacyAllowed,
  sanitizeAnalyticsReferrer,
  trackSessionStart,
  trackPagePerformance,
  trackScrollDepth,
  trackTimeOnPage,
  getOrCreateUserId,
  setUserProperties,
  sendEvent,
} from '@/lib/analytics';
import {
  queryContainsSensitiveState,
  isPrivateWizardPath,
  safeGetItem,
  safeSetItem,
  inspectSensitiveNavigationUrl,
  stripSensitiveQueryState,
} from '@/lib/utils';

interface AnalyticsProviderProps {
  children: ReactNode;
}

type DataLayerEntry = Record<string, unknown> | readonly unknown[];
type AnalyticsWindow = Window & {
  dataLayer?: DataLayerEntry[];
  gtag?: NonNullable<Window['gtag']>;
};

/**
 * Inner component that uses useSearchParams - isolated in its own Suspense boundary
 * to prevent SSR bailout for the entire app
 */
function AnalyticsTracker() {
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const pagePath =
    pathname ?? (typeof window !== 'undefined' ? window.location.pathname : null);
  const parameterSearchQuery =
    searchParams?.toString() ??
    (typeof window !== 'undefined' ? window.location.search.slice(1) : '');
  const liveSearchQuery = typeof window !== 'undefined'
    ? window.location.search.slice(1)
    : parameterSearchQuery;
  const sensitiveQuery = queryContainsSensitiveState(parameterSearchQuery)
    || queryContainsSensitiveState(liveSearchQuery);
  const searchQuery = stripSensitiveQueryState(liveSearchQuery);
  const gaId = GA_MEASUREMENT_ID?.trim();
  const privacyAllowed = isAnalyticsPrivacyAllowed();
  const scrollDepthsReached = useRef<Set<number>>(new Set());
  const pageStartTime = useRef<number>(0);
  const timeIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const hasInitializedGa = useRef<boolean>(false);
  const hasTrackedSession = useRef<boolean>(false);

  // Initialize GA state once
  useEffect(() => {
    if (!gaId || sensitiveQuery || !privacyAllowed) return;

    const analyticsWindow = window as AnalyticsWindow;
    const dataLayer = analyticsWindow.dataLayer ?? [];
    analyticsWindow.dataLayer = dataLayer;

    const gtag: NonNullable<Window['gtag']> = (command, targetId, config) => {
      if (typeof config === 'undefined') {
        dataLayer.push([command, targetId]);
        return;
      }

      dataLayer.push([command, targetId, config]);
    };

    if (!analyticsWindow.gtag) {
      analyticsWindow.gtag = gtag;
    }

    if (!hasInitializedGa.current && analyticsWindow.gtag) {
      analyticsWindow.gtag('js', new Date());
      hasInitializedGa.current = true;
    }
  }, [gaId, sensitiveQuery, privacyAllowed]);

  // Track page views on route change
  useEffect(() => {
    if (!gaId || sensitiveQuery || !privacyAllowed || pagePath === null) return;

    const url = searchQuery ? `${pagePath}?${searchQuery}` : pagePath;
    const analyticsWindow = window as AnalyticsWindow;
    const sanitizedReferrer = sanitizeAnalyticsReferrer(document.referrer || '');

    // Reset tracking for new page
    scrollDepthsReached.current.clear();
    pageStartTime.current = Date.now();

    // Track pageview
    analyticsWindow.gtag?.('config', gaId, {
      page_path: url,
      page_location: `${window.location.origin}${url}`,
      page_referrer: sanitizedReferrer.referrer || undefined,
      page_title: document.title,
      cookie_flags: 'SameSite=None;Secure',
      send_page_view: true,
      allow_google_signals: false,
      allow_ad_personalization_signals: false,
      custom_map: {
        dimension1: 'user_type',
        dimension2: 'wizard_step',
        dimension3: 'selected_os',
        dimension4: 'vps_provider',
        dimension5: 'terminal_app',
      },
    });

    // Track page performance after load
    if (document.readyState === 'complete') {
      trackPagePerformance();
    } else {
      window.addEventListener('load', trackPagePerformance, { once: true });
    }

    return () => {
      window.removeEventListener('load', trackPagePerformance);
    };
  }, [pagePath, searchQuery, gaId, sensitiveQuery, privacyAllowed]);

  // Initialize session tracking on mount
  useEffect(() => {
    if (!gaId || sensitiveQuery || !privacyAllowed || hasTrackedSession.current) return;
    hasTrackedSession.current = true;

    // Get or create user ID
    const userId = getOrCreateUserId();

    // Set user ID for cross-session tracking
    setUserProperties({
      user_id: userId,
      first_visit_date: safeGetItem('acfs_first_visit') || new Date().toISOString(),
    });

    // Store first visit date
    if (!safeGetItem('acfs_first_visit')) {
      safeSetItem('acfs_first_visit', new Date().toISOString());
    }

    // Track enhanced session start
    trackSessionStart();

  }, [gaId, sensitiveQuery, privacyAllowed]);

  // Scroll depth tracking
  const handleScroll = useCallback(() => {
    if (!gaId || sensitiveQuery || !privacyAllowed || pagePath === null) return;

    const scrollTop = window.scrollY;
    const docHeight = document.documentElement.scrollHeight - window.innerHeight;
    const scrollPercent = docHeight > 0 ? Math.round((scrollTop / docHeight) * 100) : 0;

    const milestones = [25, 50, 75, 90, 100] as const;

    for (const milestone of milestones) {
      if (scrollPercent >= milestone && !scrollDepthsReached.current.has(milestone)) {
        scrollDepthsReached.current.add(milestone);
        trackScrollDepth(milestone, pagePath);
      }
    }
  }, [pagePath, gaId, sensitiveQuery, privacyAllowed]);

  // Set up scroll tracking
  useEffect(() => {
    if (!gaId || sensitiveQuery || !privacyAllowed) return;

    window.addEventListener('scroll', handleScroll, { passive: true });
    return () => window.removeEventListener('scroll', handleScroll);
  }, [handleScroll, gaId, sensitiveQuery, privacyAllowed]);

  // Time on page tracking
  useEffect(() => {
    if (!gaId || sensitiveQuery || !privacyAllowed || pagePath === null) return;

    const timeCheckpoints = [30, 60, 120, 300, 600]; // seconds
    let lastCheckpoint = 0;

    timeIntervalRef.current = setInterval(() => {
      const elapsed = Math.floor((Date.now() - pageStartTime.current) / 1000);

      // Check time checkpoints
      for (const checkpoint of timeCheckpoints) {
        if (elapsed >= checkpoint && lastCheckpoint < checkpoint) {
          trackTimeOnPage(checkpoint, pagePath);
          lastCheckpoint = checkpoint;
        }
      }
    }, 5000); // Check every 5 seconds

    return () => {
      if (timeIntervalRef.current) {
        clearInterval(timeIntervalRef.current);
      }
    };
  }, [pagePath, gaId, sensitiveQuery, privacyAllowed]);

  // Track visibility changes (tab switching)
  useEffect(() => {
    if (!gaId || sensitiveQuery || !privacyAllowed || pagePath === null) return;

    const handleVisibilityChange = () => {
      if (document.hidden) {
        const timeSpent = Math.floor((Date.now() - pageStartTime.current) / 1000);
        sendEvent('page_hidden', {
          page_path: pagePath,
          time_spent_seconds: timeSpent,
        });
      } else {
        sendEvent('page_visible', {
          page_path: pagePath,
        });
      }
    };

    document.addEventListener('visibilitychange', handleVisibilityChange);
    return () => document.removeEventListener('visibilitychange', handleVisibilityChange);
  }, [pagePath, gaId, sensitiveQuery, privacyAllowed]);

  // Track page exit
  useEffect(() => {
    if (!gaId || sensitiveQuery || !privacyAllowed || pagePath === null) return;

    const handleBeforeUnload = () => {
      const timeSpent = Math.floor((Date.now() - pageStartTime.current) / 1000);

      // Use GA4 gtag with beacon transport (Measurement Protocol api_secret cannot
      // be safely used client-side).
      sendEvent('page_exit', {
        page_path: pagePath,
        time_spent_seconds: timeSpent,
        scroll_depths_reached: Array.from(scrollDepthsReached.current),
        transport_type: 'beacon',
      });
    };

    window.addEventListener('beforeunload', handleBeforeUnload);
    return () => window.removeEventListener('beforeunload', handleBeforeUnload);
  }, [pagePath, gaId, sensitiveQuery, privacyAllowed]);

  if (sensitiveQuery || !privacyAllowed || !gaId) return null;
  return (
    <Script
      src={`https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(gaId)}`}
      strategy="afterInteractive"
    />
  );
}

/**
 * Install the URL privacy boundary before loading any vendor runtime.
 *
 * History mutations are projected onto safe query state. Session-recording and
 * generic tag-manager runtimes are deliberately not mounted by the shared root
 * layout: an App Router document can later render an operator's host address.
 */
function PrivacyControlledScripts() {
  const [analyticsAllowed, setAnalyticsAllowed] = useState(false);
  const documentTainted = useRef<boolean | null>(null);

  useLayoutEffect(() => {
    const browserHistory = window.history;
    const originalPushState = browserHistory.pushState;
    const originalReplaceState = browserHistory.replaceState;
    const documentIsPrivate = isPrivateWizardPath(window.location.pathname);
    if (documentTainted.current === null) {
      documentTainted.current = !isAnalyticsPrivacyAllowed()
        || analyticsContextContainsSensitiveState(
        window.location.search,
        document.referrer || '',
        window.location.href,
      )
        || isPrivateWizardPath(window.location.pathname);
      if (documentTainted.current) {
        disableAnalyticsForDocument();
      }
    }

    const markDocumentTainted = (): void => {
      documentTainted.current = true;
      disableAnalyticsForDocument();
    };

    const routeInCurrentDocument = (
      method: 'push' | 'replace',
      data: unknown,
      unused: string,
      value?: string | URL | null,
    ): void => {
      const current = new URL(window.location.href);
      const result = inspectSensitiveNavigationUrl(value, current.href);
      const destination = result.value;
      let target: URL | null = null;
      if (typeof destination === 'string') {
        try {
          target = new URL(destination, current);
        } catch {
          // Let native History preserve its own error semantics below.
        }
      }

      const crossesPrivacyZone = target?.origin === current.origin
        && isPrivateWizardPath(target.pathname) !== isPrivateWizardPath(current.pathname);
      if (result.sensitiveStateDetected || crossesPrivacyZone) {
        markDocumentTainted();
      }
      if (result.sensitiveStateRemoved || crossesPrivacyZone) {
        if (target?.origin === current.origin) {
          if (method === 'replace') {
            window.location.replace(target.href);
          } else {
            window.location.assign(target.href);
          }
          return;
        }
      }

      if (method === 'replace') {
        originalReplaceState.call(browserHistory, data, unused, destination);
      } else {
        originalPushState.call(browserHistory, data, unused, destination);
      }
    };

    const guardedPushState: History['pushState'] = (data, unused, value) => {
      routeInCurrentDocument('push', data, unused, value);
    };
    const guardedReplaceState: History['replaceState'] = (data, unused, value) => {
      routeInCurrentDocument('replace', data, unused, value);
    };

    browserHistory.pushState = guardedPushState;
    browserHistory.replaceState = guardedReplaceState;

    const scrubCurrentLocation = (): void => {
      const result = inspectSensitiveNavigationUrl(
        window.location.href,
        window.location.href,
      );
      if (isPrivateWizardPath(window.location.pathname) !== documentIsPrivate) {
        markDocumentTainted();
        window.location.replace(
          typeof result.value === 'string' ? result.value : window.location.href,
        );
        return;
      }
      if (result.sensitiveStateRemoved && typeof result.value === 'string') {
        markDocumentTainted();
        window.location.replace(result.value);
      }
    };

    const handlePopState = (): void => {
      scrubCurrentLocation();
    };
    window.addEventListener('popstate', handlePopState);
    window.addEventListener('hashchange', handlePopState);

    scrubCurrentLocation();
    if (!documentTainted.current) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setAnalyticsAllowed(true);
    }

    return () => {
      window.removeEventListener('popstate', handlePopState);
      window.removeEventListener('hashchange', handlePopState);
      if (browserHistory.pushState === guardedPushState) {
        browserHistory.pushState = originalPushState;
      }
      if (browserHistory.replaceState === guardedReplaceState) {
        browserHistory.replaceState = originalReplaceState;
      }
    };
  }, []);

  if (!analyticsAllowed) return null;
  return (
    <AnalyticsTracker />
  );
}

/**
 * Analytics Provider Component
 * Handles GA4 initialization, pageview tracking, and engagement metrics
 *
 * IMPORTANT: useSearchParams is isolated in AnalyticsTracker with its own Suspense
 * to prevent SSR bailout for the entire app tree.
 */
export function AnalyticsProvider({ children }: AnalyticsProviderProps) {
  return (
    <>
      {/* Vendor runtimes mount only after the document privacy boundary exists. */}
      <Suspense fallback={null}>
        <PrivacyControlledScripts />
      </Suspense>
      {children}
    </>
  );
}

export default AnalyticsProvider;
