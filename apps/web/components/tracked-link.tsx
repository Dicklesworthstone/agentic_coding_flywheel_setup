'use client';

import { forwardRef, type AnchorHTMLAttributes } from 'react';
import Link from 'next/link';
import { trackOutboundLink, sendEvent } from '@/lib/analytics';

interface TrackedLinkProps extends AnchorHTMLAttributes<HTMLAnchorElement> {
  href: string;
  trackingId?: string;
  isExternal?: boolean;
  children: React.ReactNode;
}

/**
 * Link component with built-in click tracking
 * Automatically detects external links and tracks them
 */
export const TrackedLink = forwardRef<HTMLAnchorElement, TrackedLinkProps>(
  ({ href, trackingId, isExternal, onClick, children, ...props }, ref) => {
    // Detect if link is external
    const isExternalLink =
      isExternal ?? (href.startsWith('http://') || href.startsWith('https://'));

    const handleClick = (e: React.MouseEvent<HTMLAnchorElement>) => {
      const linkText = typeof children === 'string' ? children : trackingId || href;

      if (isExternalLink) {
        trackOutboundLink(href, linkText);
      } else {
        sendEvent('internal_link_click', {
          link_href: href,
          link_text: linkText,
          tracking_id: trackingId,
        });
      }

      onClick?.(e);
    };

    if (isExternalLink) {
      return (
        <a
          ref={ref}
          href={href}
          onClick={handleClick}
          target="_blank"
          rel="noopener noreferrer"
          {...props}
        >
          {children}
        </a>
      );
    }

    return (
      <Link ref={ref} href={href} onClick={handleClick} {...props}>
        {children}
      </Link>
    );
  }
);

TrackedLink.displayName = 'TrackedLink';

export default TrackedLink;
