import { describe, expect, test } from "bun:test";
import {
  type ManifestModuleMetadata,
  manifestSelectionProfiles,
} from "./generated/manifest-modules";
import {
  buildInstallSelectorArgs,
  formatModuleSelectionPlan,
  getGuidedModuleSelection,
  getMissingWizardPrerequisites,
  resolveModuleSelection,
  WIZARD_PREREQUISITE_MODULES,
} from "./moduleSelection";

function includedIds(profile?: Parameters<typeof resolveModuleSelection>[0]) {
  return resolveModuleSelection(profile).included.map((entry) => entry.id);
}

describe("guided setup prerequisites are an explicit addition", () => {
  for (const profile of ["agents-only", "cloud-only", "stack-only"] as const) {
    test(`${profile} remains an exact CLI profile until guided setup is requested`, () => {
      const original = { profile };
      const before = resolveModuleSelection(original);
      expect(before.ok).toBe(true);
      expect(getMissingWizardPrerequisites(before)).toContain("acfs.doctor");
      expect(getGuidedModuleSelection(profile, false)).toEqual(original);
      expect(buildInstallSelectorArgs(original)).toEqual(["--profile", `"${profile}"`]);

      const guided = getGuidedModuleSelection(profile, true);
      const after = resolveModuleSelection(guided);
      expect(after.ok).toBe(true);
      expect(getMissingWizardPrerequisites(after)).toEqual([]);
      expect(new Set(after.included.map((entry) => entry.id))).toEqual(
        new Set([...before.included.map((entry) => entry.id), ...WIZARD_PREREQUISITE_MODULES]),
      );
      expect(buildInstallSelectorArgs(guided)).toContain('"acfs.doctor"');
      expect(buildInstallSelectorArgs(guided)).not.toContain("--profile");
      expect(buildInstallSelectorArgs(guided)).not.toContain("--no-deps");
      expect(getGuidedModuleSelection(profile, false)).toEqual(original);
      expect(includedIds(original)).not.toContain("acfs.doctor");
    });
  }

  for (const profile of ["full", "minimal"] as const) {
    test(`${profile} needs no rewritten selectors`, () => {
      expect(getMissingWizardPrerequisites(resolveModuleSelection({ profile }))).toEqual([]);
      expect(getGuidedModuleSelection(profile, true)).toEqual({ profile });
    });
  }

  test("a custom fresh-server selection reports its missing account, workspace and Doctor", () => {
    const plan = resolveModuleSelection({ onlyModules: ["base.system"] });
    expect(plan.ok).toBe(true);
    expect(getMissingWizardPrerequisites(plan)).toEqual([
      "users.ubuntu", "base.filesystem", "acfs.doctor",
    ]);
    expect(plan.included.map((entry) => entry.id)).toEqual(["base.system"]);
  });

  test("guided phase profiles keep optional tools in their phase and dependencies inferred", () => {
    const guided = getGuidedModuleSelection("agents-only", true);
    expect(guided).toEqual({
      onlyModules: ["base.system", "users.ubuntu", "base.filesystem", "acfs.doctor"],
      onlyPhases: ["agents"],
    });
    const plan = resolveModuleSelection(guided);
    expect(plan.ok).toBe(true);
    expect(plan.included.find((entry) => entry.id === "agents.gemini")?.reason).toBe("phase 7");
    expect(plan.included.find((entry) => entry.id === "agents.opencode")?.reason).toBe("phase 7");
    expect(plan.included.find((entry) => entry.id === "lang.bun")?.reason).toStartWith("dependency of ");
    expect(plan.included.find((entry) => entry.id === "acfs.doctor")?.reason).toBe("explicitly requested");
    expect(plan.included.some((entry) => entry.id === "acfs.nightly")).toBe(false);
    expect(plan.included.some((entry) => entry.id === "acfs.onboard")).toBe(false);
  });

  test("guided exact-module profiles preserve their roots without promoting dependencies", () => {
    const guided = getGuidedModuleSelection("cloud-only", true);
    expect(guided.onlyModules).toEqual([
      "cloud.wrangler", "cloud.supabase", "cloud.vercel",
      "base.system", "users.ubuntu", "base.filesystem", "acfs.doctor",
    ]);
    expect(guided.onlyPhases).toBeUndefined();
    const plan = resolveModuleSelection(guided);
    expect(plan.included.find((entry) => entry.id === "lang.bun")?.reason).toStartWith("dependency of ");
    expect(plan.included.some((entry) => entry.id === "db.postgres18")).toBe(false);
  });
});

describe("resolveModuleSelection", () => {
  test("default selection follows enabled-by-default manifest metadata", () => {
    const plan = resolveModuleSelection();

    expect(plan.ok).toBe(true);
    expect(plan.selectedCount).toBeGreaterThan(0);
    expect(includedIds()).toContain("agents.claude");
    expect(includedIds()).toContain("lang.bun");
    expect(includedIds()).not.toContain("db.postgres18");
    expect(includedIds()).not.toContain("tools.vault");
    expect(plan.excluded.find((entry) => entry.id === "db.postgres18")?.reason).toBe(
      "disabled by default",
    );
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


  test("mixed module and phase selectors form a union with explicit module precedence", () => {
    const selection = {
      onlyModules: ["acfs.doctor", "agents.gemini"],
      onlyPhases: ["agents"],
      skipModules: ["agents.grok"],
    };
    const plan = resolveModuleSelection(selection);
    expect(plan.ok).toBe(true);
    const ids = plan.included.map((entry) => entry.id);
    expect(ids).toContain("agents.claude");
    expect(ids).toContain("agents.codex");
    expect(ids).toContain("acfs.doctor");
    expect(ids).toContain("lang.bun");
    expect(ids).not.toContain("agents.grok");
    expect(plan.included.find((entry) => entry.id === "agents.gemini")?.reason).toBe("explicitly requested");
    expect(plan.included.find((entry) => entry.id === "agents.claude")?.reason).toBe("phase 7");

    const noDeps = resolveModuleSelection({ ...selection, noDeps: true });
    expect(noDeps.ok).toBe(true);
    expect(noDeps.included.map((entry) => entry.id)).not.toContain("lang.bun");
    expect(noDeps.included.map((entry) => entry.id)).toContain("agents.claude");
  });

  test("mixed selectors validate both roots and keep phase dependency conflicts", () => {
    expect(resolveModuleSelection({ onlyModules: ["acfs.doctor"], onlyPhases: ["99"] }).ok).toBe(false);
    expect(resolveModuleSelection({ onlyModules: ["agents.not_real"], onlyPhases: ["agents"] }).ok).toBe(false);
    const conflict = resolveModuleSelection({
      onlyModules: ["acfs.doctor"],
      onlyPhases: ["agents"],
      skipModules: ["lang.bun"],
    });
    expect(conflict.ok).toBe(false);
    expect(conflict.errors.join("\n")).toContain("depends on skipped lang.bun");
    expect(resolveModuleSelection({
      onlyModules: ["agents.gemini"],
      onlyPhases: ["agents"],
      skipModules: ["agents.gemini"],
      noDeps: true,
    }).ok).toBe(false);
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
      '"cloud-only"',
    ]);
  });

  test("serializes phase profiles and expert dependency mode", () => {
    expect(buildInstallSelectorArgs({ profile: "stack-only", noDeps: true })).toEqual([
      "--profile",
      '"stack-only"',
      "--no-deps",
    ]);
  });

  test("serializes explicit only modules and phases when no profile specified", () => {
    expect(buildInstallSelectorArgs({ onlyModules: ["cloud.wrangler", "cloud.supabase"] })).toEqual(
      ["--only", '"cloud.wrangler"', "--only", '"cloud.supabase"'],
    );
    expect(buildInstallSelectorArgs({ onlyPhases: ["agents"] })).toEqual(["--only-phase", '"7"']);
  });

  test("preserves explicit selectors when paired with a mode-only profile", () => {
    expect(
      buildInstallSelectorArgs({
        profile: "safe",
        onlyModules: ["agents.codex"],
      }),
    ).toEqual(["--only", '"agents.codex"']);
    expect(
      buildInstallSelectorArgs({
        profile: "full",
        onlyPhases: ["agents"],
      }),
    ).toEqual(["--only-phase", '"7"']);
  });

  test("throws instead of serializing invalid selectors", () => {
    expect(() => buildInstallSelectorArgs({ onlyModules: ["bad;module"] })).toThrow(
      "Unknown module id in --only: bad;module",
    );
  });

  test("lowers supported group exclusions without dropping dependency checks", () => {
    expect(buildInstallSelectorArgs({ skipTags: ["maintenance"] })).toEqual([
      "--skip",
      '"acfs.nightly"',
    ]);
    expect(buildInstallSelectorArgs({ skipCategories: ["network"] })).toEqual([
      "--skip",
      '"network.tailscale"',
      "--skip",
      '"network.ssh_keepalive"',
    ]);
    expect(() => buildInstallSelectorArgs({ skipTags: ["critical"] })).toThrow(
      "depends on skipped",
    );
  });
});

describe("formatModuleSelectionPlan", () => {
  test("renders stable human-readable plan output", () => {
    const text = formatModuleSelectionPlan(
      resolveModuleSelection({ onlyModules: ["agents.codex"] }),
    );

    expect(text).toContain("ACFS Module Selection Plan");
    expect(text).toContain("Selected modules:");
    expect(text).toContain("[Phase 6] lang.bun");
    expect(text).toContain("[Phase 7] agents.codex");
  });
});
