import type { NextConfig } from "next";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const configDir = dirname(fileURLToPath(import.meta.url));
const workspaceRoot = resolve(configDir, "../..");
const NEXT_DIST_SCOPE_ENV = "ACFS_NEXT_DIST_SCOPE";
const NEXT_TSCONFIG_PATH_ENV = "ACFS_NEXT_TSCONFIG_PATH";

const toScopedDistDir = (scope: string): string | undefined => {
  const normalized = scope
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, "-")
    .replace(/^-+|-+$/g, "");

  if (!normalized) return undefined;
  return `.next-${normalized}`;
};

const scopedDistDir = toScopedDistDir(process.env[NEXT_DIST_SCOPE_ENV] ?? "");
const scopedTsconfigPath = process.env[NEXT_TSCONFIG_PATH_ENV]?.trim();

const nextConfig: NextConfig = {
  // Allow concurrent agents in the same checkout to opt into isolated Next.js
  // artifacts by setting ACFS_NEXT_DIST_SCOPE before build/typegen/start.
  ...(scopedDistDir ? { distDir: scopedDistDir } : {}),
  ...(scopedTsconfigPath ? { typescript: { tsconfigPath: scopedTsconfigPath } } : {}),
  turbopack: {
    // Bun workspaces install deps at the workspace root; Turbopack needs this
    // to resolve `next` and other packages when multiple lockfiles exist.
    root: workspaceRoot,
  },
  images: {
    remotePatterns: [
      {
        protocol: "https",
        hostname: "raw.githubusercontent.com",
        pathname: "/Dicklesworthstone/agentic_coding_flywheel_setup/**",
      },
    ],
  },
};

export default nextConfig;
