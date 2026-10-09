import type { MetadataRoute } from "next";
import { LESSONS } from "@/lib/lessons";
import { SITE_URL, STATIC_ROUTES } from "@/lib/site-routes";
import { TOOL_IDS } from "./learn/tools/[tool]/tool-data";

export default function sitemap(): MetadataRoute.Sitemap {
  const paths = [
    ...STATIC_ROUTES,
    ...LESSONS.map((lesson) => `/learn/${lesson.slug}`),
    ...TOOL_IDS.map((tool) => `/learn/tools/${tool}`),
  ];
  return paths.map((path) => ({ url: path === "/" ? SITE_URL : `${SITE_URL}${path}` }));
}
