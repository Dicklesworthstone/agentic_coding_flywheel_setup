/**
 * Deploy-time cache buster for OG/Twitter image URLs.
 *
 * X (Twitter) caches card images aggressively. The convention-file content hash
 * only changes when the image code changes. This version string changes on
 * every Vercel deploy, forcing X to re-crawl fresh images.
 *
 * Usage in layout metadata:
 *   openGraph: { images: [{ url: `/page/opengraph-image?v=${ogVersion}`, ... }] }
 */
export const ogVersion = process.env.VERCEL_GIT_COMMIT_SHA?.slice(0, 8) ?? String(Date.now());
