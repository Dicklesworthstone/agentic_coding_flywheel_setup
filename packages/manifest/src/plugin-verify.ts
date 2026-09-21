#!/usr/bin/env bun
/** Read-only archive + review verification, distinct from generator activation. */
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import type {
  PluginValidationOptions,
  PluginValidationResult,
  PluginValidationTarget,
} from "./plugin.js";
import { PluginArchiveError, readPluginInputFile } from "./plugin-archive.js";
import {
  PluginReviewError,
  parsePluginTarget,
  readReviewedPluginArchive,
} from "./plugin-review.js";
import type { InstallerChecksumEntry } from "./validate.js";

/** No caller-supplied actual digest or loose extracted manifest can enter here. */
export async function loadReviewedPluginPackage(
  archivePath: string,
  reviewPath: string,
  options: Omit<PluginValidationOptions, "packageSha256" | "expectedPackageSha256" | "target"> & {
    target: PluginValidationTarget;
  },
): Promise<PluginValidationResult> {
  try {
    const archive = readReviewedPluginArchive(archivePath, reviewPath, options.target);
    const { validatePluginPackage, mergeValidatedPlugins } = await import("./plugin.js");
    const { ManifestSchema } = await import("./schema.js");
    const { validateManifest, validateVerifiedInstallerChecksums } = await import("./validate.js");
    const { validateManifestData } = await import("./parser.js");
    const result = validatePluginPackage(archive.manifest, {
      ...options,
      packageSha256: archive.packageSha256,
      expectedPackageSha256: archive.expectedPackageSha256,
    });
    if (!result.valid) return result;
    const merged = mergeValidatedPlugins(options.firstPartyManifest, [result]);
    if (
      !ManifestSchema.safeParse(merged).success ||
      !validateManifestData(merged).valid ||
      !validateManifest(merged).valid ||
      validateVerifiedInstallerChecksums(merged, options.installers ?? {}).length > 0
    ) {
      return {
        valid: false,
        manifestModules: [],
        diagnostics: [
          {
            code: "plugin_dependency_invalid",
            severity: "error",
            path: "<merged-manifest>",
            message:
              "Merged plugin graph failed canonical schema, dependency, phase, or checksum validation",
          },
        ],
      };
    }
    return result;
  } catch (error) {
    if (error instanceof PluginArchiveError || error instanceof PluginReviewError) {
      return {
        valid: false,
        manifestModules: [],
        diagnostics: [
          {
            code: error.code,
            severity: "error",
            path: "<package>",
            message: error.message,
          },
        ],
      };
    }
    // Do not echo filesystem paths, loader errors, or untrusted package content.
    return {
      valid: false,
      manifestModules: [],
      diagnostics: [
        {
          code: "plugin_disallowed_behavior",
          severity: "error",
          path: "<validation>",
          message:
            "Plugin verification could not complete; check the local manifest tooling and trust inputs",
        },
      ],
    };
  }
}

export interface PluginVerifyArguments {
  archive: string;
  review: string;
  target: PluginValidationTarget;
  json: boolean;
}
export function parsePluginVerifyArguments(args: readonly string[]): PluginVerifyArguments {
  const values = new Map<string, string>();
  let json = false;
  for (let index = 0; index < args.length; index++) {
    const option = args[index]!;
    if (option === "--json" && !json) {
      json = true;
      continue;
    }
    if (!["--archive", "--review", "--target"].includes(option) || values.has(option)) {
      throw new Error("Unknown or duplicate plugin verification option");
    }
    const value = args[++index];
    if (!value || value.startsWith("--"))
      throw new Error("Plugin verification option requires a value");
    values.set(option, value);
  }
  if (values.size !== 3)
    throw new Error("Explicit --archive, --review and --target values are required");
  return {
    archive: values.get("--archive")!,
    review: values.get("--review")!,
    target: parsePluginTarget(values.get("--target")!),
    json,
  };
}

export async function pluginVerifyMain(args: readonly string[]): Promise<number> {
  if (args.length === 1 && (args[0] === "--help" || args[0] === "-h")) {
    console.log(
      "Usage: bun run plugin:verify --archive package.tar.gz --review trusted-review.json --target os/version/arch/libc [--json]\nRead-only verification. Never installs plugins or changes generated output.",
    );
    return 0;
  }
  const json = args.includes("--json");
  let output: {
    valid: boolean;
    activation: "disabled";
    diagnostics: unknown[];
    moduleCount?: number;
  };
  let exitCode: number;
  try {
    const options = parsePluginVerifyArguments(args);
    // Verify archive/review/target before loading first-party dependencies.
    // loadReviewedPluginPackage repeats this check against its own immutable
    // snapshot; a pathname swap between checks can never validate other bytes.
    readReviewedPluginArchive(options.archive, options.review, options.target);
    const { parseManifestString } = await import("./parser.js");
    const { parse: parseYaml } = await import("yaml");
    const root = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
    const manifest = parseManifestString(
      readPluginInputFile(join(root, "acfs.manifest.yaml"), 4 * 1024 * 1024).toString("utf8"),
    );
    const checksums = parseYaml(
      readPluginInputFile(join(root, "checksums.yaml"), 1024 * 1024).toString("utf8"),
    ) as {
      installers?: Record<string, InstallerChecksumEntry>;
    };
    if (
      !manifest.success ||
      !manifest.data ||
      !checksums ||
      typeof checksums.installers !== "object" ||
      checksums.installers === null ||
      Array.isArray(checksums.installers)
    ) {
      throw new Error("Canonical manifest or installer checksums are invalid");
    }
    const result = await loadReviewedPluginPackage(options.archive, options.review, {
      firstPartyManifest: manifest.data,
      installers: checksums.installers,
      target: options.target,
    });
    output = {
      valid: result.valid,
      activation: "disabled",
      diagnostics: result.diagnostics,
      ...(result.valid ? { moduleCount: result.manifestModules.length } : {}),
    };
    exitCode = result.valid ? 0 : 1;
  } catch (error) {
    const known = error instanceof PluginArchiveError || error instanceof PluginReviewError;
    output = {
      valid: false,
      activation: "disabled",
      diagnostics: [
        {
          code: known ? error.code : "plugin_verification_input_invalid",
          severity: "error",
          path: "<input>",
          message: known
            ? error.message
            : "Verification arguments or canonical trust inputs are invalid or unavailable",
        },
      ],
    };
    exitCode = known ? 1 : 2;
  }
  if (json) console.log(JSON.stringify(output));
  else {
    console.log(
      output.valid
        ? `Plugin verification passed (${output.moduleCount} modules). Activation remains disabled.`
        : "Plugin verification failed. Activation remains disabled.",
    );
    for (const diagnostic of output.diagnostics) console.log(JSON.stringify(diagnostic));
  }
  return exitCode;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  process.exitCode = await pluginVerifyMain(process.argv.slice(2));
}
