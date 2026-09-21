#!/usr/bin/env bun
/** Author a package against canonical policy; never issue a review or install it. */
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { PluginArchiveError, readPluginInputFile } from "./plugin-archive.js";
import {
  buildPluginArchive,
  type PluginArchiveBuild,
  PluginPackError,
  pluginArchiveBytes,
  writePluginArchive,
} from "./plugin-pack.js";
import { type PluginArchiveTarget, PluginReviewError, parsePluginTarget } from "./plugin-review.js";

export interface PluginPackArguments {
  source: string;
  output?: string;
  target: PluginArchiveTarget;
  dryRun: boolean;
  json: boolean;
}
export interface PluginPackValidation {
  valid: boolean;
  moduleCount: number;
  diagnosticCodes: string[];
}
export interface PluginPackCommandServices {
  /** In-process testing seam only; the CLI has no bypass or trust-root flags. */
  validate: (
    build: PluginArchiveBuild,
    target: PluginArchiveTarget,
  ) => Promise<PluginPackValidation>;
  write: (message: string) => void;
}
export function parsePluginPackArguments(args: readonly string[]): PluginPackArguments {
  const values = new Map<string, string>();
  const flags = new Set<string>();
  for (let index = 0; index < args.length; index++) {
    const key = args[index]!;
    if (key === "--dry-run" || key === "--json") {
      if (flags.has(key)) throw new Error("Duplicate packaging option");
      flags.add(key);
      continue;
    }
    if (!["--source", "--output", "--target"].includes(key) || values.has(key))
      throw new Error("Unknown or duplicate packaging option");
    const value = args[++index];
    if (!value || value.startsWith("--") || /[\x00-\x1f\x7f]/.test(value))
      throw new Error("Packaging option requires a valid value");
    values.set(key, value);
  }
  if (
    !values.has("--source") ||
    !values.has("--target") ||
    (!flags.has("--dry-run") && !values.has("--output"))
  ) {
    throw new Error("Explicit source, target and output (unless dry-run) are required");
  }
  return {
    source: values.get("--source")!,
    output: values.get("--output"),
    target: Object.freeze(parsePluginTarget(values.get("--target")!)),
    dryRun: flags.has("--dry-run"),
    json: flags.has("--json"),
  };
}

/**
 * Check author-produced bytes against real first-party schema, dependency,
 * capability and checksum policy. Matching the digest to itself here proves
 * only producer consistency, NOT independent review. No installation modules,
 * review record or approval token escape this authoring-only result.
 */
export async function validatePluginArchiveForPublication(
  build: PluginArchiveBuild,
  target: PluginArchiveTarget,
): Promise<PluginPackValidation> {
  pluginArchiveBytes(build); // Require a process-built retained snapshot.
  const { parseManifestString, validateManifestData } = await import("./parser.js");
  const { parse: parseYaml } = await import("yaml");
  const { validatePluginPackage, mergeValidatedPlugins } = await import("./plugin.js");
  const { ManifestSchema } = await import("./schema.js");
  const { validateManifest, validateVerifiedInstallerChecksums } = await import("./validate.js");
  const root = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
  const firstParty = parseManifestString(
    readPluginInputFile(join(root, "acfs.manifest.yaml"), 4 * 1024 * 1024).toString("utf8"),
  );
  const database: unknown = parseYaml(
    readPluginInputFile(join(root, "checksums.yaml"), 1024 * 1024).toString("utf8"),
  );
  if (
    !firstParty.success ||
    !firstParty.data ||
    !database ||
    typeof database !== "object" ||
    !("installers" in database) ||
    !database.installers ||
    typeof database.installers !== "object" ||
    Array.isArray(database.installers)
  )
    throw new Error("Canonical trust inputs are invalid");
  const installers: Record<string, { url: string; sha256: string }> = Object.create(null);
  for (const [key, value] of Object.entries(database.installers)) {
    if (
      !/^[a-z][a-z0-9_]*$/.test(key) ||
      !value ||
      typeof value !== "object" ||
      !("url" in value) ||
      typeof value.url !== "string" ||
      !("sha256" in value) ||
      typeof value.sha256 !== "string"
    )
      throw new Error("Canonical checksum entry is invalid");
    installers[key] = { url: value.url, sha256: value.sha256 };
  }
  const result = validatePluginPackage(build.manifest, {
    firstPartyManifest: firstParty.data,
    installers,
    target,
    packageSha256: build.packageSha256,
    expectedPackageSha256: build.packageSha256,
  });
  if (!result.valid || result.diagnostics.length !== 0) {
    return {
      valid: false,
      moduleCount: 0,
      diagnosticCodes: [
        ...new Set<string>(result.diagnostics.map((entry: { code: string }) => entry.code)),
      ],
    };
  }
  const merged = mergeValidatedPlugins(firstParty.data, [result]);
  if (
    !ManifestSchema.safeParse(merged).success ||
    !validateManifestData(merged).valid ||
    !validateManifest(merged).valid ||
    validateVerifiedInstallerChecksums(merged, installers).length !== 0
  ) {
    return { valid: false, moduleCount: 0, diagnosticCodes: ["plugin_dependency_invalid"] };
  }
  return { valid: true, moduleCount: result.manifestModules.length, diagnosticCodes: [] };
}

export async function pluginPackMain(
  args: readonly string[],
  services: PluginPackCommandServices = {
    validate: validatePluginArchiveForPublication,
    write: (message) => console.log(message),
  },
): Promise<number> {
  if (args.length === 1 && ["--help", "-h"].includes(args[0]!)) {
    services.write(
      "Usage: bun run plugin:pack --source package-directory --target os/version/arch/libc --output new-package.tar.gz [--dry-run] [--json]\nDry run builds and validates without publishing; --output is optional then.\nSource must contain plugin.json, README.md, LICENSE and only declared static assets.\nNever executes installers, changes source files, overwrites output, or creates an independent review.",
    );
    return 0;
  }
  const json = args.includes("--json");
  let parsed = false;
  let cancelled = 0;
  const interrupt = (): void => {
    cancelled = 130;
  };
  const terminate = (): void => {
    cancelled = 143;
  };
  process.once("SIGINT", interrupt);
  process.once("SIGTERM", terminate);
  try {
    const options = parsePluginPackArguments(args);
    parsed = true;
    const build = buildPluginArchive(options.source);
    const validation = await services.validate(build, options.target);
    if (cancelled) throw new Error("cancelled");
    if (
      validation.valid !== true ||
      !Number.isSafeInteger(validation.moduleCount) ||
      validation.moduleCount < 1 ||
      !Array.isArray(validation.diagnosticCodes) ||
      validation.diagnosticCodes.length !== 0
    ) {
      const codes = Array.isArray(validation.diagnosticCodes)
        ? validation.diagnosticCodes
            .filter((code) => typeof code === "string" && /^plugin_[a-z_]{1,80}$/.test(code))
            .slice(0, 32)
        : [];
      services.write(
        json
          ? JSON.stringify({
              status: "failed",
              reviewRequired: true,
              diagnostic: {
                code: "plugin_pack_validation_failed",
                causes: codes,
                message:
                  "Package did not pass canonical manifest, target, capability or checksum validation; no output was published",
              },
            })
          : `Package validation refused publication (${codes.join(", ") || "invalid validation result"}). No output was published.`,
      );
      return 1;
    }
    const archive = options.dryRun
      ? {
          packageSha256: build.packageSha256,
          compressedBytes: build.compressedBytes,
          expandedBytes: build.expandedBytes,
          fileCount: build.fileCount,
          reviewRequired: true as const,
        }
      : writePluginArchive(build, options.output!);
    services.write(
      json
        ? JSON.stringify({
            status: options.dryRun ? "validated" : "packed",
            dryRun: options.dryRun,
            archive,
            checkedTarget: options.target,
            moduleCount: validation.moduleCount,
            reviewRequired: true,
          })
        : `${options.dryRun ? "Package validated; no files written" : "Package published"}: ${archive.packageSha256}\n${archive.fileCount} files, ${validation.moduleCount} modules. Independent review is still required before installation.`,
    );
    return 0;
  } catch (error) {
    const known =
      error instanceof PluginPackError ||
      error instanceof PluginArchiveError ||
      error instanceof PluginReviewError;
    const code = cancelled
      ? "plugin_pack_cancelled"
      : !parsed
        ? "plugin_pack_arguments_invalid"
        : known
          ? error.code
          : "plugin_pack_validation_unavailable";
    const message = cancelled
      ? "Package publication cancelled"
      : !parsed
        ? "Invalid packaging options; use --help for source, target and output syntax"
        : known
          ? error.message
          : "Canonical validation could not complete; check the trusted checkout and manifest dependencies";
    services.write(
      json
        ? JSON.stringify({ status: "failed", reviewRequired: true, diagnostic: { code, message } })
        : `${code}: ${message}`,
    );
    return cancelled || (parsed ? 1 : 2);
  } finally {
    process.removeListener("SIGINT", interrupt);
    process.removeListener("SIGTERM", terminate);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  process.exitCode = await pluginPackMain(process.argv.slice(2));
}
