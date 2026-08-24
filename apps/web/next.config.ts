import type { NextConfig } from "next";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const configDir = dirname(fileURLToPath(import.meta.url));
const workspaceRoot = resolve(configDir, "../..");
const NEXT_DIST_SCOPE_ENV = "ACFS_NEXT_DIST_SCOPE";
const NEXT_TSCONFIG_PATH_ENV = "ACFS_NEXT_TSCONFIG_PATH";
const NEXT_BUILD_CPUS_ENV = "ACFS_NEXT_BUILD_CPUS";
const DEFAULT_BUILD_CPUS = 1;

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

const parseBuildCpus = (value: string | undefined): number | undefined => {
  const trimmed = value?.trim();
  if (!trimmed) return undefined;

  if (!/^[1-9][0-9]*$/.test(trimmed)) {
    throw new Error(`${NEXT_BUILD_CPUS_ENV} must be a positive integer when set.`);
  }

  const parsed = Number(trimmed);
  if (!Number.isSafeInteger(parsed)) {
    throw new Error(`${NEXT_BUILD_CPUS_ENV} must be a positive integer when set.`);
  }

  return parsed;
};

const buildCpus = parseBuildCpus(process.env[NEXT_BUILD_CPUS_ENV]) ?? DEFAULT_BUILD_CPUS;

const nextConfig: NextConfig = {
  // The isolated package scripts pair this scoped output with a private
  // tsconfig so Next never writes scope-specific includes into tsconfig.json.
  ...(scopedDistDir ? { distDir: scopedDistDir } : {}),
  ...(scopedTsconfigPath ? { typescript: { tsconfigPath: scopedTsconfigPath } } : {}),
  turbopack: {
    // Bun workspaces install deps at the workspace root; Turbopack needs this
    // to resolve `next` and other packages when multiple lockfiles exist.
    root: workspaceRoot,
  },
  experimental: {
    // Next defaults to os.cpus() - 1 workers. Under Bun 1.3.12, even moderate
    // static-generation worker fanout can SIGILL during teardown on this host.
    cpus: buildCpus,
  },
  async redirects() {
    return [
      {
        source: "/core_flywheel",
        destination: "/core-flywheel",
        permanent: true,
      },
      {
        // The manifest-generated catalog duplicated /tldr; its useful parts
        // (search, CLI names, command examples) now live on /tldr.
        source: "/tools",
        destination: "/tldr",
        permanent: true,
      },
    ];
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
