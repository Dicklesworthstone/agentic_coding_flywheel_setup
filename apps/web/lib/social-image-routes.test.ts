/**
 * Drift guard for the share cards: every image route has copy, the copy fits
 * the card, wizard positions match the wizard, and each card shape renders a
 * real PNG (Satori fails silently with an empty 200 response).
 */

import { describe, expect, test } from "bun:test";
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

import { TOOLS } from "../app/learn/tools/[tool]/tool-data";
import cloudSocialImages from "./cloud-social-images.json";
import { LESSONS } from "./lessons";
import { renderSocialImage, type SocialImageData } from "./social-image";
import {
  getStaticRouteSocialData,
  lessonSocialData,
  STATIC_SOCIAL_ROUTES,
  socialImageAlt,
  toolSocialData,
  WIZARD_SOCIAL_TOTAL,
} from "./social-image-routes";
import { TOTAL_STEPS, WIZARD_STEPS } from "./wizardSteps";

const APP_DIR = resolve(dirname(fileURLToPath(import.meta.url)), "../app");

function imageRouteFiles(directory: string): string[] {
  const files: string[] = [];
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) files.push(...imageRouteFiles(path));
    else if (entry.name === "opengraph-image.tsx" || entry.name === "twitter-image.tsx") files.push(path);
  }
  return files;
}

function routeOf(file: string): string {
  const segments = relative(APP_DIR, dirname(file)).split(sep).filter(Boolean);
  return `/${segments.join("/")}`;
}

const files = imageRouteFiles(APP_DIR);
const lessonCards = LESSONS.map((lesson) => lessonSocialData(lesson, LESSONS.length));
const toolCards = Object.values(TOOLS).map((tool) => toolSocialData(tool));

describe("share card routes", () => {
  test("every route has both an Open Graph and an X card", () => {
    const routes = new Set(files.map(routeOf));
    for (const route of routes) {
      const base = join(APP_DIR, route);
      expect(files).toContain(join(base, "opengraph-image.tsx"));
      expect(files).toContain(join(base, "twitter-image.tsx"));
    }
  });

  test("static image routes and the copy table cover each other exactly", () => {
    const referenced = new Set<string>();
    for (const file of files) {
      const match = readFileSync(file, "utf-8").match(/getStaticRouteSocialData\("([^"]+)"\)/);
      if (!match) continue;
      expect(match[1]).toBe(routeOf(file));
      referenced.add(match[1]);
    }
    expect([...referenced].sort()).toEqual([...STATIC_SOCIAL_ROUTES].sort());
  });

  test("wizard cards sit at the wizard's own step numbers", () => {
    expect(WIZARD_SOCIAL_TOTAL).toBe(TOTAL_STEPS);
    for (const step of WIZARD_STEPS) {
      const card = getStaticRouteSocialData(`/wizard/${step.slug}`);
      expect(card.step).toEqual({ current: step.id, total: TOTAL_STEPS });
      expect(card.hub).toBe(String(step.id).padStart(2, "0"));
    }
  });

  test("copy fits the card: two-line descriptions, two-line titles", () => {
    const cards: SocialImageData[] = [
      ...STATIC_SOCIAL_ROUTES.map((route) => getStaticRouteSocialData(route)),
      ...lessonCards,
      ...toolCards,
    ];
    for (const card of cards) {
      const title = [card.title, card.accent].filter(Boolean).join(" ");
      expect({ path: card.path, length: card.description.length }).toEqual({
        path: card.path,
        length: Math.min(card.description.length, 100),
      });
      expect({ path: card.path, length: title.length }).toEqual({
        path: card.path,
        length: Math.min(title.length, 44),
      });
      expect(card.badge.length).toBeLessThanOrEqual(40);
      expect((card.nodes ?? []).length).toBeLessThanOrEqual(6);
      expect(socialImageAlt(card)).toContain(card.description);
    }
  });

  test("each card shape renders a full-size PNG", async () => {
    const shapes: SocialImageData[] = [
      { ...getStaticRouteSocialData("/complete-guide"), stats: [{ value: "42", label: "Prompts" }] },
      getStaticRouteSocialData("/"),
      getStaticRouteSocialData("/wizard/run-installer"),
      getStaticRouteSocialData("/learn/commands"),
      lessonCards[0],
      toolCards[0],
    ];
    for (const card of shapes) {
      for (const [variant, height] of [["opengraph", 630], ["twitter", 600]] as const) {
        const response = await renderSocialImage(card, variant);
        const bytes = Buffer.from(await response.arrayBuffer());
        expect(response.status).toBe(200);
        expect(bytes.subarray(0, 8)).toEqual(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
        expect(bytes.readUInt32BE(16)).toBe(1200);
        expect(bytes.readUInt32BE(20)).toBe(height);
        // A blank canvas compresses to a few KB; a real card is far larger.
        expect(bytes.length).toBeGreaterThan(40_000);
      }
    }
  });

  test("the pre-rendered /cloud-agents cards match the current template and copy", async () => {
    // Rendering is deterministic, so a stale bundle shows up as a byte diff.
    // Fix with `bun run generate:cloud-social-images`.
    for (const variant of ["opengraph", "twitter"] as const) {
      const response = await renderSocialImage(getStaticRouteSocialData("/cloud-agents"), variant);
      const fresh = Buffer.from(await response.arrayBuffer());
      const bundled = Buffer.from(cloudSocialImages[variant], "base64");
      expect({ variant, upToDate: fresh.equals(bundled) }).toEqual({ variant, upToDate: true });
    }
  });
});
