/**
 * Drift guard for sitemap.xml: STATIC_ROUTES must list exactly the static
 * pages under app/, minus next.config.ts redirect sources.
 */

import { describe, expect, test } from "bun:test";
import { readdirSync } from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import nextConfig from "../next.config";
import sitemap from "../app/sitemap";
import robots from "../app/robots";
import { LESSONS } from "./lessons";
import { SITE_URL, STATIC_ROUTES } from "./site-routes";

const APP_DIR = resolve(dirname(fileURLToPath(import.meta.url)), "../app");

function pageRoutes(directory: string): string[] {
  const routes: string[] = [];
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) routes.push(...pageRoutes(path));
    else if (entry.name === "page.tsx") {
      // Route groups such as (marketing) do not appear in the URL.
      const segments = relative(APP_DIR, directory).split(sep).filter((part) => part && !/^\(.*\)$/.test(part));
      routes.push(`/${segments.join("/")}`);
    }
  }
  return routes;
}

describe("sitemap", () => {
  test("STATIC_ROUTES lists every static page except redirect sources", async () => {
    const redirectSources = new Set((await nextConfig.redirects!()).map((rule) => rule.source));
    const expected = pageRoutes(APP_DIR)
      .filter((route) => !route.includes("["))
      .filter((route) => !redirectSources.has(route))
      .sort();
    expect([...STATIC_ROUTES].sort()).toEqual(expected);
  });

  test("includes lessons and tool pages as absolute canonical URLs", () => {
    const urls = sitemap().map((entry) => entry.url);
    expect(urls).toContain(SITE_URL);
    expect(urls).toContain(`${SITE_URL}/cloud-agents`);
    expect(urls).toContain(`${SITE_URL}/learn/${LESSONS[0].slug}`);
    expect(urls.some((url) => url.startsWith(`${SITE_URL}/learn/tools/`))).toBe(true);
    expect(urls).not.toContain(`${SITE_URL}/learn/glossary`);
    expect(new Set(urls).size).toBe(urls.length);
    for (const url of urls) expect(url.startsWith(SITE_URL)).toBe(true);
  });

  test("robots.txt points crawlers at the sitemap", () => {
    expect(robots().sitemap).toBe(`${SITE_URL}/sitemap.xml`);
  });
});
