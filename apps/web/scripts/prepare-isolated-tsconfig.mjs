#!/usr/bin/env bun

import { readFileSync, writeFileSync } from "node:fs";

const tsconfigPath = process.argv[2];

if (!tsconfigPath) {
  console.error("usage: prepare-isolated-tsconfig.mjs <tsconfig-path>");
  process.exit(2);
}

let config;
try {
  config = JSON.parse(readFileSync(tsconfigPath, "utf8"));
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`failed to parse ${tsconfigPath}: ${message}`);
  process.exit(1);
}

if (!config || typeof config !== "object" || Array.isArray(config)) {
  console.error(`failed to prepare ${tsconfigPath}: expected a JSON object`);
  process.exit(1);
}

if (Array.isArray(config.include)) {
  // Next writes generated type includes back to whichever tsconfig it uses.
  // Strip both the default output and every scoped `.next-<scope>` output so
  // an accidentally polluted canonical config cannot couple isolated builds.
  config.include = config.include.filter(
    (entry) => typeof entry !== "string" || !/^\.next(?:-[^/]+)?\//.test(entry),
  );
}

try {
  writeFileSync(tsconfigPath, `${JSON.stringify(config, null, 2)}\n`);
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`failed to write ${tsconfigPath}: ${message}`);
  process.exit(1);
}
