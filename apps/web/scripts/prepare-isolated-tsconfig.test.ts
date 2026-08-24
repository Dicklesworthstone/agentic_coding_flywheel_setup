import { describe, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const scriptPath = fileURLToPath(
  new URL("./prepare-isolated-tsconfig.mjs", import.meta.url),
);

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
});
