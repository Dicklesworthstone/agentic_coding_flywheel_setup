'use client';

import { useEffect, useCallback, useRef, type ReactNode, Suspense } from 'react';
import { usePathname, useSearchParams } from 'next/navigation';
import Script from 'next/script';
import {
  GA_MEASUREMENT_ID,
  trackSessionStart,
  trackPagePerformance,
  trackScrollDepth,
  trackTimeOnPage,
  getOrCreateUserId,
  setUserProperties,
  sendEvent,
} from '@/lib/analytics';
import { safeGetItem, safeSetItem } from '@/lib/utils';

interface AnalyticsProviderProps {
  children: ReactNode;
}

/**
 * Inner component that uses useSearchParams - isolated in its own Suspense boundary
 * to prevent SSR bailout for the entire app
 */
function AnalyticsTracker() {
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const gaId = GA_MEASUREMENT_ID?.trim();
  const scrollDepthsReached = useRef<Set<number>>(new Set());
  const pageStartTime = useRef<number>(0);
  const timeIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const hasInitializedGa = useRef<boolean>(false);

  // Initialize GA stub early (no inline script injection)
  useEffect(() => {
    if (!gaId) return;

    window.dataLayer = window.dataLayer || [];
    if (!window.gtag) {
      window.gtag = ((...args: unknown[]) => {
        window.dataLayer.push(args);
      }) as unknown as Window['gtag'];
    }

    if (!hasInitializedGa.current) {
      window.gtag('js', new Date());
      hasInitializedGa.current = true;
    }
  }, [gaId]);

  // Track page views on route change
  useEffect(() => {
    if (!gaId) return;

    const url = pathname + (searchParams?.toString() ? `?${searchParams.toString()}` : '');

    // Reset tracking for new page
    scrollDepthsReached.current.clear();
    pageStartTime.current = Date.now();

    // Track pageview
    window.gtag?.('config', gaId, {
      page_path: url,
      page_title: document.title,
      cookie_flags: 'SameSite=None;Secure',
      send_page_view: true,
      allow_google_signals: true,
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
  }, [pathname, searchParams, gaId]);

  // Initialize session tracking on mount
  useEffect(() => {
    if (!gaId) return;

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

    // Track returning vs new user
    const visitCount = parseInt(safeGetItem('acfs_visit_count') || '0', 10) + 1;
    safeSetItem('acfs_visit_count', visitCount.toString());

    setUserProperties({
      visit_count: visitCount,
      is_returning_user: visitCount > 1,
    });
  }, [gaId]);

  // Scroll depth tracking
  const handleScroll = useCallback(() => {
    if (!gaId) return;

    const scrollTop = window.scrollY;
    const docHeight = document.documentElement.scrollHeight - window.innerHeight;
    const scrollPercent = docHeight > 0 ? Math.round((scrollTop / docHeight) * 100) : 0;

    const milestones = [25, 50, 75, 90, 100] as const;

    for (const milestone of milestones) {
      if (scrollPercent >= milestone && !scrollDepthsReached.current.has(milestone)) {
        scrollDepthsReached.current.add(milestone);
        trackScrollDepth(milestone, pathname);
      }
    }
  }, [pathname, gaId]);

  // Set up scroll tracking
  useEffect(() => {
    if (!gaId) return;

    window.addEventListener('scroll', handleScroll, { passive: true });
    return () => window.removeEventListener('scroll', handleScroll);
  }, [handleScroll, gaId]);

  // Time on page tracking
  useEffect(() => {
    if (!gaId) return;

    const timeCheckpoints = [30, 60, 120, 300, 600]; // seconds
    let lastCheckpoint = 0;

    timeIntervalRef.current = setInterval(() => {
      const elapsed = Math.floor((Date.now() - pageStartTime.current) / 1000);

      for (const checkpoint of timeCheckpoints) {
        if (elapsed >= checkpoint && lastCheckpoint < checkpoint) {
          trackTimeOnPage(checkpoint, pathname);
          lastCheckpoint = checkpoint;
        }
      }
    }, 5000); // Check every 5 seconds

    return () => {
      if (timeIntervalRef.current) {
        clearInterval(timeIntervalRef.current);
      }
    };
  }, [pathname, gaId]);

  // Track visibility changes (tab switching)
  useEffect(() => {
    if (!gaId) return;

    const handleVisibilityChange = () => {
      if (document.hidden) {
        const timeSpent = Math.floor((Date.now() - pageStartTime.current) / 1000);
        sendEvent('page_hidden', {
          page_path: pathname,
          time_spent_seconds: timeSpent,
        });
      } else {
        sendEvent('page_visible', {
          page_path: pathname,
        });
      }
    };

    document.addEventListener('visibilitychange', handleVisibilityChange);
    return () => document.removeEventListener('visibilitychange', handleVisibilityChange);
  }, [pathname, gaId]);

  // Track page exit
  useEffect(() => {
    if (!gaId) return;

    const handleBeforeUnload = () => {
      const timeSpent = Math.floor((Date.now() - pageStartTime.current) / 1000);

      // Use GA4 gtag with beacon transport (Measurement Protocol api_secret cannot
      // be safely used client-side).
      sendEvent('page_exit', {
        page_path: pathname,
        time_spent_seconds: timeSpent,
        scroll_depths_reached: Array.from(scrollDepthsReached.current),
        transport_type: 'beacon',
      });
    };

    window.addEventListener('beforeunload', handleBeforeUnload);
    return () => window.removeEventListener('beforeunload', handleBeforeUnload);
  }, [pathname, gaId]);

  return null; // This component only tracks, doesn't render anything
}

/**
 * Analytics Provider Component
 * Handles GA4 initialization, pageview tracking, and engagement metrics
 *
 * IMPORTANT: useSearchParams is isolated in AnalyticsTracker with its own Suspense
 * to prevent SSR bailout for the entire app tree.
 */
export function AnalyticsProvider({ children }: AnalyticsProviderProps) {
  const gaId = GA_MEASUREMENT_ID?.trim();

  if (!gaId) {
    return <>{children}</>;
  }

  const gaExternalScriptProps = {
    src: `https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(gaId)}`,
    strategy: 'afterInteractive' as const,
  };

  return (
    <>
      {/* Google Analytics Script */}
      <Script {...gaExternalScriptProps} />
      {/* Analytics tracker wrapped in Suspense to prevent SSR bailout */}
      <Suspense fallback={null}>
        <AnalyticsTracker />
      </Suspense>
      {children}
    </>
  );
}

export default AnalyticsProvider;
