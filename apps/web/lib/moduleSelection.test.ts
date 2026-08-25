import { describe, expect, test } from "bun:test";
import {
  buildInstallSelectorArgs,
  formatModuleSelectionPlan,
  resolveModuleSelection,
} from "./moduleSelection";
import {
  manifestSelectionProfiles,
  type ManifestModuleMetadata,
} from "./generated/manifest-modules";

function includedIds(profile?: Parameters<typeof resolveModuleSelection>[0]) {
  return resolveModuleSelection(profile).included.map((entry) => entry.id);
}

describe("resolveModuleSelection", () => {
  test("default selection follows enabled-by-default manifest metadata", () => {
    const plan = resolveModuleSelection();

    expect(plan.ok).toBe(true);
    expect(plan.selectedCount).toBeGreaterThan(0);
    expect(includedIds()).toContain("agents.claude");
    expect(includedIds()).toContain("lang.bun");
    expect(includedIds()).not.toContain("db.postgres18");
    expect(includedIds()).not.toContain("tools.vault");
    expect(plan.excluded.find((entry) => entry.id === "db.postgres18")?.reason).toBe("disabled by default");
  });

  test("cloud-only profile lowers to cloud CLIs, not the broader cloud-db phase", () => {
    const plan = resolveModuleSelection({ profile: "cloud-only" });
    const ids = plan.included.map((entry) => entry.id);

    expect(plan.ok).toBe(true);
    expect(ids).toContain("cloud.wrangler");
    expect(ids).toContain("cloud.supabase");
    expect(ids).toContain("cloud.vercel");
    expect(ids).toContain("lang.bun");
    expect(ids).toContain("base.filesystem");
    expect(ids).not.toContain("tools.vault");
    expect(ids).not.toContain("db.postgres18");
  });

  test("minimal profile uses the contract allowlist plus dependency closure", () => {
    const ids = includedIds({ profile: "minimal" });

    expect(ids).toContain("shell.omz");
    expect(ids).toContain("shell.zsh");
    expect(ids).toContain("stack.mcp_agent_mail");
    expect(ids).toContain("stack.rch");
    expect(ids).toContain("lang.rust");
    expect(ids).toContain("lang.go");
    expect(ids).toContain("tools.ast_grep");
    expect(ids).not.toContain("network.tailscale");
    expect(ids).not.toContain("tools.lazygit");
    expect(ids).not.toContain("acfs.nightly");
  });

  test("stack-only profile follows phase selection and dependencies", () => {
    const ids = includedIds({ profile: "stack-only" });

    expect(ids).toContain("stack.ntm");
    expect(ids).toContain("stack.rch");
    expect(ids).toContain("utils.giil");
    expect(ids).toContain("cli.modern");
    expect(ids).not.toContain("agents.opencode");
    expect(ids).not.toContain("cloud.wrangler");
  });

  test("every generated profile resolves against the current manifest", () => {
    for (const profile of manifestSelectionProfiles) {
      const plan = resolveModuleSelection({ profile: profile.id });

      expect(plan.errors).toEqual([]);
      expect(plan.ok).toBe(true);
      expect(plan.selectedCount).toBeGreaterThan(0);
    }
  });

  test("unknown module and unknown phase fail before plan output", () => {
    expect(resolveModuleSelection({ onlyModules: ["agents.not_real"] })).toMatchObject({
      ok: false,
      errors: ["Unknown module id in --only: agents.not_real"],
    });
    expect(resolveModuleSelection({ onlyPhases: ["99"] })).toMatchObject({
      ok: false,
      errors: ["Unknown phase in --only-phase: 99"],
    });
  });

  test("skipping a required dependency fails unless noDeps is explicit", () => {
    const unsafe = resolveModuleSelection({
      onlyModules: ["agents.codex"],
      skipModules: ["lang.bun"],
    });

    expect(unsafe.ok).toBe(false);
    expect(unsafe.errors.join("\n")).toContain("agents.codex depends on skipped lang.bun");
    expect(unsafe.errors.join("\n")).toContain("Dependency chain: agents.codex -> lang.bun");

    const noDeps = resolveModuleSelection({
      onlyModules: ["agents.codex"],
      skipModules: ["lang.bun"],
      noDeps: true,
    });

    expect(noDeps.ok).toBe(true);
    expect(noDeps.warnings.join("\n")).toContain("--no-deps disables dependency closure");
    expect(noDeps.included.map((entry) => entry.id)).toEqual(["agents.codex"]);
  });

  test("direct profile or only skip contradictions fail even with noDeps", () => {
    const plan = resolveModuleSelection({
      profile: "cloud-only",
      skipModules: ["cloud.wrangler"],
      noDeps: true,
    });

    expect(plan.ok).toBe(false);
    expect(plan.errors.join("\n")).toContain("cloud.wrangler was requested with --only");
  });

  test("profile selectors cannot be mixed with explicit only selectors", () => {
    const plan = resolveModuleSelection({
      profile: "minimal",
      onlyModules: ["agents.claude"],
    });

    expect(plan.ok).toBe(false);
    expect(plan.errors.join("\n")).toContain("profile minimal cannot be combined");
  });

  test("serializes stable machine-readable plan JSON", () => {
    const modules: ManifestModuleMetadata[] = [
      {
        id: "base.system",
        description: "Base packages",
        category: "base",
        phase: 1,
        dependencies: [],
        tags: ["critical"],
        enabledByDefault: true,
        optional: false,
      },
      {
        id: "lang.bun",
        description: "Bun runtime",
        category: "lang",
        phase: 6,
        dependencies: ["base.system"],
        tags: ["runtime"],
        enabledByDefault: true,
        optional: false,
      },
      {
        id: "agents.codex",
        description: "Codex CLI",
        category: "agents",
        phase: 7,
        dependencies: ["lang.bun"],
        tags: ["agent"],
        enabledByDefault: true,
        optional: false,
      },
      {
        id: "cloud.wrangler",
        description: "Wrangler CLI",
        category: "cloud",
        phase: 8,
        dependencies: ["lang.bun"],
        tags: ["cloud"],
        enabledByDefault: false,
        optional: true,
      },
    ];

    const plan = resolveModuleSelection(
      { onlyModules: ["agents.codex"] },
      modules,
      manifestSelectionProfiles,
    );

    expect(JSON.stringify(plan, null, 2)).toBe(`{
  "ok": true,
  "included": [
    {
      "id": "base.system",
      "description": "Base packages",
      "category": "base",
      "phase": 1,
      "reason": "dependency of lang.bun"
    },
    {
      "id": "lang.bun",
      "description": "Bun runtime",
      "category": "lang",
      "phase": 6,
      "reason": "dependency of agents.codex"
    },
    {
      "id": "agents.codex",
      "description": "Codex CLI",
      "category": "agents",
      "phase": 7,
      "reason": "explicitly requested"
    }
  ],
  "excluded": [
    {
      "id": "cloud.wrangler",
      "reason": "not selected"
    }
  ],
  "warnings": [],
  "errors": [],
  "selectedCount": 3,
  "availableCount": 4
}`);
  });
});

describe("buildInstallSelectorArgs", () => {
  test("serializes profile-lowered cloud-only selectors", () => {
    expect(buildInstallSelectorArgs({ profile: "cloud-only" })).toEqual([
      "--profile",
      "\"cloud-only\"",
    ]);
  });

  test("serializes phase profiles and expert dependency mode", () => {
    expect(buildInstallSelectorArgs({ profile: "stack-only", noDeps: true })).toEqual([
      "--profile",
      "\"stack-only\"",
      "--no-deps",
    ]);
  });

  test("serializes explicit only modules and phases when no profile specified", () => {
    expect(
      buildInstallSelectorArgs({ onlyModules: ["cloud.wrangler", "cloud.supabase"] }),
    ).toEqual([
      "--only",
      "\"cloud.wrangler\"",
      "--only",
      "\"cloud.supabase\"",
    ]);
    expect(buildInstallSelectorArgs({ onlyPhases: ["agents"] })).toEqual([
      "--only-phase",
      "\"7\"",
    ]);
  });

  test("throws instead of serializing invalid selectors", () => {
    expect(() => buildInstallSelectorArgs({ onlyModules: ["bad;module"] })).toThrow(
      "Unknown module id in --only: bad;module",
    );
  });

  test("throws instead of silently dropping unsupported selector types", () => {
    expect(() => buildInstallSelectorArgs({ skipTags: ["critical"] })).toThrow(
      "Tag and category skip selectors cannot be serialized",
    );
  });
});

describe("formatModuleSelectionPlan", () => {
  test("renders stable human-readable plan output", () => {
    const text = formatModuleSelectionPlan(resolveModuleSelection({ onlyModules: ["agents.codex"] }));

    expect(text).toContain("ACFS Module Selection Plan");
    expect(text).toContain("Selected modules:");
    expect(text).toContain("[Phase 6] lang.bun");
    expect(text).toContain("[Phase 7] agents.codex");
  });
});
