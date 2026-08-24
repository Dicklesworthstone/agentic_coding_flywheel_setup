import { describe, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { toScopedDistDir } from "../next.config";

const scriptPath = fileURLToPath(
  new URL("./prepare-isolated-tsconfig.mjs", import.meta.url),
);
const packagePath = fileURLToPath(new URL("../package.json", import.meta.url));

describe("prepare-isolated-tsconfig", () => {
  test("removes canonical and scoped Next type outputs without touching source globs", () => {
    const artifactDir = mkdtempSync(join(tmpdir(), "acfs-isolated-tsconfig-"));
    const configPath = join(artifactDir, "tsconfig.json");

    writeFileSync(
      configPath,
      `${JSON.stringify({
        include: [
          "next-env.d.ts",
          "**/*.ts",
          ".next/types/**/*.ts",
          ".next/dev/types/**/*.ts",
          ".next-brandsweep/types/**/*.ts",
          ".next-brandsweep/dev/types/**/*.ts",
          ".nextish/types/**/*.ts",
        ],
      })}\n`,
    );

    const result = spawnSync(process.execPath, [scriptPath, configPath], {
      encoding: "utf8",
    });

    expect(result.status, result.stderr).toBe(0);
    expect(JSON.parse(readFileSync(configPath, "utf8")).include).toEqual([
      "next-env.d.ts",
      "**/*.ts",
      ".nextish/types/**/*.ts",
    ]);
  });

  test("routes explicitly scoped builds through the paired isolation wrapper", () => {
    const packageJson = JSON.parse(readFileSync(packagePath, "utf8"));
    const buildScript = packageJson.scripts?.build;

    expect(buildScript).toContain("ACFS_NEXT_DIST_SCOPE");
    expect(buildScript).toContain("bun run build:isolated");
    expect(buildScript).toContain("next build --webpack");
  });

  test("uses one injective, fail-closed scope grammar in every wrapper", () => {
    const packageJson = JSON.parse(readFileSync(packagePath, "utf8"));
    const scopedScriptNames = [
      "build:isolated",
      "lint:isolated",
      "type-check:isolated",
    ];

    for (const scriptName of scopedScriptNames) {
      const script = packageJson.scripts?.[scriptName];
      expect(script).toContain("^[a-z0-9][a-z0-9_-]{0,63}$");
      expect(script).not.toContain("tr -cs");
    }

    expect(toScopedDistDir("review-42_alpha")).toBe(".next-review-42_alpha");
    expect(toScopedDistDir("")).toBeUndefined();

    // These values previously normalized onto another scope's output directory.
    expect(() => toScopedDistDir("Review-42_alpha")).toThrow();
    expect(() => toScopedDistDir("review 42_alpha")).toThrow();
    expect(() => toScopedDistDir("-review-42")).toThrow();
    expect(() => toScopedDistDir(`a${"b".repeat(64)}`)).toThrow();
  });
});
