/** Page-routing tests with memoizing hook/service doubles, not a browser renderer. */
import { strict as assert } from "node:assert";
import { createHash, webcrypto } from "node:crypto";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { createContext, runInContext } from "node:vm";

const require = createRequire(import.meta.url);
const ts = require("typescript");
const pageUrl = new URL("./page.tsx", import.meta.url);
const compiled = ts.transpileModule(readFileSync(pageUrl, "utf8"), {
  fileName: fileURLToPath(pageUrl),
  reportDiagnostics: true,
  compilerOptions: {
    module: ts.ModuleKind.CommonJS,
    target: ts.ScriptTarget.ES2022,
    jsx: ts.JsxEmit.ReactJSX,
    esModuleInterop: true,
  },
});
assert.deepEqual(
  (compiled.diagnostics ?? []).filter((item) => item.category === ts.DiagnosticCategory.Error),
  [],
);

// Fixture graph makes routing errors visible; graph correctness is covered by
// moduleSelection's production-catalogue contract tests, not these service doubles.
const profiles = [
  { id: "full", label: "Full" },
  { id: "safe", label: "Safe", mode: "safe" },
  { id: "vibe", label: "Vibe", mode: "vibe" },
  { id: "minimal", label: "Minimal" },
  { id: "agents-only", label: "Agents only" },
  { id: "cloud-only", label: "Cloud only" },
  { id: "stack-only", label: "Stack only" },
];
const ids = {
  full: ["base.system", "agents.claude", "stack.ntm"],
  safe: ["base.system", "agents.claude", "stack.ntm"],
  vibe: ["base.system", "agents.claude", "stack.ntm"],
  minimal: ["base.system", "agents.claude"],
  "agents-only": ["base.system", "agents.claude"],
  "cloud-only": ["base.system", "cloud.wrangler"],
  "stack-only": ["base.system", "stack.ntm"],
};
const plain = (value) => JSON.parse(JSON.stringify(value));
const text = (node) =>
  Array.isArray(node)
    ? node.map(text).join("")
    : node && typeof node === "object"
      ? text(node.props?.children)
      : typeof node === "string" || typeof node === "number"
        ? String(node)
        : "";

function fixture(initial = {}) {
  const prefs = {
    os: "linux",
    mode: "safe",
    ref: null,
    ip: "203.0.113.42",
    username: "developer",
    profile: "cloud-only",
    provider: {
      providerId: "other",
      planName: "custom plan",
      ubuntuVersion: "24.04",
      region: "not-listed",
      targetAgents: 10,
      workloadId: "standard",
    },
    ...initial,
  };
  const loaded = {
    os: true,
    mode: true,
    ref: true,
    ip: true,
    username: true,
    profile: true,
    provider: true,
  };
  const calls = { command: [], runbook: [], provider: [], profile: [] };
  const session = { status: "saved", installation: null };
  const copies = [];
  const navigations = [];
  const completed = [];
  const slots = [];
  let acknowledgeNext = false;
  let invalidPlan = false;
  let cursor = 0;
  let navigation;
  let lastCompletionKey = null;
  let lastCheckpoint;
  let checkpointPending = false;
  let checkpointFailed = false;
  let checkpointOverride;
  const acknowledgements = new Map();
  const provenance = { manifestSha256: "a".repeat(64), checksumsYamlSha256: "b".repeat(64) };
  const sameDeps = (a, b) =>
    a && b && a.length === b.length && a.every((item, index) => Object.is(item, b[index]));
  const react = {
    useState(initialValue) {
      const index = cursor++;
      if (!(index in slots))
        slots[index] = typeof initialValue === "function" ? initialValue() : initialValue;
      return [
        slots[index],
        (next) => {
          slots[index] = typeof next === "function" ? next(slots[index]) : next;
        },
      ];
    },
    useMemo(fn, deps) {
      const index = cursor++;
      if (!slots[index] || !sameDeps(slots[index].deps, deps)) slots[index] = { deps, value: fn() };
      return slots[index].value;
    },
    useCallback(fn, deps) {
      return react.useMemo(() => fn, deps);
    },
    useRef(value) {
      const index = cursor++;
      slots[index] ??= { current: value };
      return slots[index];
    },
    useEffect() {
      cursor++;
    },
  };
  const jsx = (type, props) => ({ type, props: props ?? {} });
  const pref = (key) => () => {
    const active = session.status === "active" ? session.installation : null;
    const imported = active && {
      mode: active.mode,
      ref: active.ref,
      username: active.username,
      profile: active.moduleSelection.profile,
    };
    return [
      imported && Object.hasOwn(imported, key) ? imported[key] : prefs[key],
      (value) => {
        if (!active) prefs[key] = value;
      },
      loaded[key],
    ];
  };
  const command = (mode, ref, username, selection) => {
    calls.command.push(plain({ mode, ref, username, selection: selection ?? null }));
    return (
      `bash install.sh --mode ${mode} --target-ubuntu=${prefs.installDestination ?? "26.04"} --user ${username}` +
      (ref ? ` --ref "${ref}"` : "") +
      (selection ? ` --profile "${selection.profile}"` : "") +
      (selection?.onlyModules ?? []).map((id) => ` --only "${id}"`).join("") +
      (selection?.skipModules ?? []).map((id) => ` --skip "${id}"`).join("")
    );
  };
  const artifact = (kind) => (input) => {
    calls[kind].push(plain(input));
    return {
      kind,
      input: plain(input),
      command: command(
        input.mode ?? input.installMode,
        input.ref ?? input.sourceRef ?? null,
        input.username,
        input.moduleSelection,
      ),
    };
  };
  const deps = {
    react,
    "react/jsx-runtime": { jsx, jsxs: jsx, Fragment: "fragment" },
    "@tanstack/react-query": {
      useQuery: (options) => {
        if (options.queryKey[0] === "installerCheckpoint") {
          const input = options.queryKey[1];
          if (!input || checkpointPending || checkpointFailed)
            return { data: undefined, isError: checkpointFailed };
          const digest = createHash("sha256")
            .update(
              JSON.stringify([
                "acfs.installer-acknowledgement.v1",
                input.command,
                input.host,
                input.manifestSha256,
                input.checksumsYamlSha256,
              ]),
            )
            .digest("hex");
          lastCheckpoint = { ...input, persistKey: `run-flywheel-installer-v2-${digest}` };
          return { data: checkpointOverride ?? lastCheckpoint, isError: false };
        }
        lastCompletionKey = options.queryKey[1];
        if (acknowledgeNext && options.enabled !== false) {
          acknowledgements.set(lastCompletionKey, true);
          acknowledgeNext = false;
        }
        return { data: acknowledgements.get(lastCompletionKey) ?? false };
      },
    },
    "next/navigation": {
      useRouter: () => ({ push: (path) => navigations.push(path), replace: () => {} }),
    },
    "lucide-react": Object.fromEntries(
      [
        "Sparkles",
        "Clock",
        "ExternalLink",
        "Check",
        "Rocket",
        "ShieldCheck",
        "Code",
        "Wifi",
        "Pin",
        "Info",
        "Download",
        "FileJson",
        "FileText",
      ].map((name) => [name, `icon-${name}`]),
    ),
    "@/components/ui/button": { Button: "button" },
    "@/components/ui/checkbox": { Checkbox: "checkbox" },
    "@/components/command-card": {
      CommandCard: "command-card",
      commandCompletionKeys: { completion: (key) => ["completion", key] },
    },
    "@/components/alert-card": {
      AlertCard: "alert-card",
      OutputPreview: "output-preview",
      DetailsSection: "details-section",
    },
    "@/components/tracked-link": { TrackedLink: "tracked-link" },
    "@/components/simpler-guide": Object.fromEntries(
      ["SimplerGuide", "GuideSection", "GuideStep", "GuideExplain", "GuideTip", "GuideCaution"].map(
        (key) => [key, `guide-${key}`],
      ),
    ),
    "@/components/jargon": { Jargon: "jargon" },
    "@/lib/wizardSteps": {
      canAccessWizardStep: () => true,
      getCompletedSteps: () => [],
      getNextReachableWizardStep: () => ({ slug: "create-vps" }),
      markStepComplete: (step) => completed.push(step),
      useWizardForwardNav: (options) => {
        navigation = options;
        return { current: null };
      },
    },
    "@/lib/hooks/useWizardAnalytics": { useWizardAnalytics: () => ({ markComplete: () => {} }) },
    "@/lib/utils": {
      copyTextToClipboard: async (value) => {
        copies.push(value);
        return true;
      },
      safeGetItem: () => null,
      withCurrentSearch: (path) => path,
    },
    "@/lib/userPreferences": {
      useUserOS: pref("os"),
      useInstallMode: pref("mode"),
      useACFSRef: pref("ref"),
      useVPSIP: pref("ip"),
      useSSHUsername: pref("username"),
      useVPSReadinessSelection: pref("provider"),
      useModuleProfile: pref("profile"),
      useModuleSelection: () => [
        session.installation?.moduleSelection ?? { profile: prefs.profile },
        loaded.profile,
      ],
      normalizeGitRef: (value) =>
        typeof value === "string" &&
        /^[A-Za-z0-9_./-]+$/.test(value.trim()) &&
        !value.includes("..")
          ? value.trim()
          : null,
    },
    "@/lib/wizardInstallation": { useWizardInstallation: () => session },
    "@/lib/generated/manifest-modules": {
      manifestSelectionProfiles: profiles,
      manifestProvenance: provenance,
    },
    "@/lib/vpsProviders": { ACFS_RECOMMENDED_UBUNTU: "26.04" },
    "@/lib/moduleSelection": {
      resolveModuleSelection: ({ profile, onlyModules, skipModules }) => {
        const valid = !invalidPlan && Object.hasOwn(ids, profile);
        const included = valid
          ? (onlyModules?.length ? onlyModules : ids[profile])
              .filter((id) => !skipModules?.includes(id))
              .map((id) => ({ id, phase: 1, description: `Fixture ${id}`, reason: "included" }))
          : [];
        return {
          ok: valid,
          included,
          excluded: [],
          selectedCount: included.length,
          availableCount: 4,
          warnings: [],
          errors: valid ? [] : ["The selected profile cannot be resolved."],
        };
      },
    },
    "@/lib/commandBuilder": {
      buildInstallCommand: command,
      buildInstallCommandDetails: (...args) => ({
        command: command(...args),
        targetUbuntu: prefs.installDestination ?? "26.04",
      }),
      buildHandoffRunbook: artifact("runbook"),
      buildTeamProfile: artifact("profile"),
      formatHandoffRunbookMarkdown: JSON.stringify,
      serializeHandoffRunbookJson: JSON.stringify,
      formatTeamProfileReviewMarkdown: JSON.stringify,
      serializeTeamProfileJson: JSON.stringify,
      formatSshTarget: (username, host) => `${username}@${host}`,
    },
    "@/lib/providerProvisioningPacket": {
      buildProviderProvisioningPacket: artifact("provider"),
      serializeProviderProvisioningPacketJson: JSON.stringify,
    },
  };
  const context = createContext({
    setTimeout: () => 1,
    clearTimeout: () => {},
    crypto: webcrypto,
    TextEncoder,
  });
  const checkpointSource = ts.transpileModule(
    readFileSync(new URL("../../../lib/installerCheckpoint.ts", import.meta.url), "utf8"),
    {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    },
  );
  const checkpointModule = { exports: {} };
  runInContext(`(function(module,exports){${checkpointSource.outputText}\n})`, context)(
    checkpointModule,
    checkpointModule.exports,
  );
  deps["@/lib/installerCheckpoint"] = checkpointModule.exports;
  const module = { exports: {} };
  runInContext(`(function(require,module,exports){${compiled.outputText}\n})`, context, {
    filename: fileURLToPath(pageUrl),
    timeout: 5000,
  })(
    (name) => {
      assert.ok(Object.hasOwn(deps, name), `Unexpected dependency: ${name}`);
      return deps[name];
    },
    module,
    module.exports,
  );
  function render() {
    cursor = 0;
    const nodes = [];
    function visit(node) {
      if (Array.isArray(node)) {
        node.forEach(visit);
        return;
      }
      if (!node || typeof node !== "object") return;
      nodes.push(node);
      visit(node.props.children);
    }
    visit(module.exports.default());
    const find = (predicate) => {
      const node = nodes.find(predicate);
      assert.ok(node, "Expected page control");
      return node;
    };
    return {
      nodes,
      main: () =>
        nodes.find(
          (node) =>
            node.type === "command-card" &&
            node.props.description === "Agent Flywheel installer one-liner",
        ),
      cache: () =>
        nodes.find(
          (node) =>
            node.type === "command-card" &&
            node.props.description === "Installer one-liner using the local cache",
        ),
      button: (label) => find((node) => node.type === "button" && text(node).trim() === label),
      picker: () => find((node) => node.type === "select" && node.props.id === "installer-profile"),
      pinToggle: () => find((node) => node.type === "checkbox" && node.props.id === "pin-ref"),
      pinInput: () =>
        find(
          (node) =>
            node.type === "input" && node.props["aria-label"] === "Git ref to pin the installer to",
        ),
      errors: () =>
        nodes
          .filter((node) => node.props.role === "alert")
          .map(text)
          .join("\n"),
      navigation: () => navigation,
    };
  }
  return {
    render,
    prefs,
    loaded,
    calls,
    copies,
    navigations,
    completed,
    provenance,
    acknowledgements,
    session,
    adopt: (overrides = {}) => {
      const value = {
        profileId: "team-test",
        displayName: "Team Test",
        mode: "safe",
        ref: "v1.2.3",
        username: "team-user",
        architecture: "aarch64",
        ubuntuVersion: "22.04",
        moduleSelection: {
          profile: "full",
          onlyModules: ["agents.claude"],
          onlyPhases: [],
          skipModules: ["acfs.nightly"],
          noDeps: false,
        },
        ...overrides,
      };
      session.status = "active";
      session.installation = {
        ...value,
        command: command(value.mode, value.ref, value.username, value.moduleSelection),
      };
    },
    setAcknowledged: (value) => {
      if (lastCompletionKey) acknowledgements.set(lastCompletionKey, value);
      else acknowledgeNext = value;
    },
    checkpoint: () => lastCheckpoint,
    setCheckpointPending: (value) => {
      checkpointPending = value;
    },
    setCheckpointFailed: (value) => {
      checkpointFailed = value;
    },
    overrideCheckpoint: (value) => {
      checkpointOverride = value;
    },
    failPlan: () => {
      invalidPlan = true;
    },
  };
}

for (const { id } of profiles) {
  test(`saved ${id} profile reaches every executable and export path`, async () => {
    const item = fixture({ profile: id });
    const view = item.render();
    assert.equal(item.calls.command[0].selection?.profile, id);
    assert.match(view.main().props.command, new RegExp(`--profile "${id}"`));
    assert.ok(view.cache().props.command.startsWith(view.main().props.command));
    for (const name of [
      "Runbook JSON",
      "Runbook Markdown",
      "Provider Packet",
      "Team Profile",
      "Profile Review",
    ]) {
      const button = view.button(name);
      assert.equal(Boolean(button.props.disabled), false);
      button.props.onClick();
    }
    await Promise.resolve();
    assert.equal(item.copies.length, 5);
    for (const output of item.copies) {
      const artifact = JSON.parse(output);
      assert.equal(artifact.input.moduleSelection.profile, id);
      assert.match(artifact.command, new RegExp(`--profile "${id}"`));
    }
  });
}

test("changing the native profile picker refreshes memoized commands and all exports", async () => {
  const item = fixture();
  const before = item.render();
  before.picker().props.onChange({ target: { value: "stack-only" } });
  const after = item.render();
  assert.equal(item.prefs.profile, "stack-only");
  assert.match(after.main().props.command, /--profile "stack-only"/);
  assert.match(after.cache().props.command, /--profile "stack-only"/);
  for (const kind of ["runbook", "provider", "profile"])
    assert.equal(item.calls[kind].at(-1).moduleSelection.profile, "stack-only");
  after.button("Runbook JSON").props.onClick();
  await Promise.resolve();
  assert.equal(JSON.parse(item.copies[0]).input.moduleSelection.profile, "stack-only");
  after.picker().props.onChange({ target: { value: "not-a-profile" } });
  assert.equal(item.prefs.profile, "stack-only");
});

test("mode-bearing profiles cannot be downgraded by a conflicting saved install mode", () => {
  for (const mode of ["safe", "vibe"]) {
    const item = fixture({ profile: mode, mode: mode === "safe" ? "vibe" : "safe" });
    item.render();
    assert.ok(item.calls.command.every((call) => call.mode === mode));
    assert.equal(item.calls.profile[0].mode, mode);
    assert.equal(item.calls.provider[0].installMode, mode);
  }
});

test("saved profile hydration gates every command and artifact builder", () => {
  const item = fixture();
  item.loaded.profile = false;
  const view = item.render();
  assert.equal(view.main(), undefined);
  assert.equal(view.cache(), undefined);
  for (const calls of Object.values(item.calls)) assert.equal(calls.length, 0);
  item.loaded.profile = true;
  assert.match(item.render().main().props.command, /cloud-only/);
});

test("all other preference hydration gates remain intact", () => {
  for (const key of ["os", "mode", "ref", "ip", "username", "provider"]) {
    const item = fixture();
    item.loaded[key] = false;
    assert.equal(item.render().main(), undefined);
    assert.equal(item.calls.command.length, 0, key);
  }
});

test("a missing host cannot generate commands or unlock the mobile continuation", () => {
  const item = fixture({ ip: null });
  item.setAcknowledged(true);
  const view = item.render();
  assert.equal(view.main(), undefined);
  assert.equal(item.calls.command.length, 0);
  assert.equal(view.navigation().disabled, true);
  view.navigation().onContinue();
  assert.deepEqual(item.completed, []);
});

test("invalid and blank pinned drafts block main, cache, exports, desktop and mobile continuation", async () => {
  for (const draft of ["bad;ref", "", "  ", "../escape"]) {
    const item = fixture({ ref: "reviewed-tag" });
    item.setAcknowledged(true);
    item
      .render()
      .pinInput()
      .props.onChange({ target: { value: draft } });
    const count = item.calls.command.length;
    const view = item.render();
    assert.equal(view.main(), undefined, draft);
    assert.equal(view.cache(), undefined, draft);
    assert.equal(item.calls.command.length, count, "invalid drafts must not reach builders");
    assert.match(view.errors(), /blocked/);
    for (const name of [
      "Runbook JSON",
      "Runbook Markdown",
      "Provider Packet",
      "Team Profile",
      "Profile Review",
    ]) {
      const button = view.button(name);
      assert.equal(button.props.disabled, true);
      button.props.onClick();
    }
    await Promise.resolve();
    assert.deepEqual(item.copies, []);
    assert.equal(view.button("Installation finished").props.disabled, true);
    assert.equal(view.navigation().disabled, true);
    view.button("Installation finished").props.onClick();
    view.navigation().onContinue();
    assert.deepEqual(item.navigations, []);
    assert.deepEqual(item.completed, []);
    view.pinToggle().props.onCheckedChange(false);
    assert.ok(
      item.render().main(),
      "explicitly turning off pinning can restore a default-ref command",
    );
  }
});

test("valid pinned ref and customized username survive profile changes", () => {
  const item = fixture({ ref: "0123456789abcdef0123456789abcdef01234567", username: "dev-user" });
  item
    .render()
    .picker()
    .props.onChange({ target: { value: "minimal" } });
  const view = item.render();
  assert.match(view.main().props.command, /--user dev-user/);
  assert.match(view.main().props.command, /--ref "0123456789abcdef0123456789abcdef01234567"/);
  assert.match(view.main().props.command, /--profile "minimal"/);
});

test("a resolver refusal never reaches executable builders or completion handlers", () => {
  const item = fixture();
  item.failPlan();
  item.setAcknowledged(true);
  const view = item.render();
  assert.equal(view.main(), undefined);
  assert.equal(view.cache(), undefined);
  assert.equal(item.calls.command.length, 0);
  assert.match(view.errors(), /cannot be resolved/);
  view.navigation().onContinue();
  assert.deepEqual(item.completed, []);
});

test("what-installs summary is the resolved profile, not the hard-coded full tool catalogue", () => {
  const item = fixture();
  const view = item.render();
  const section = view.nodes.find(
    (node) =>
      node.type === "details-section" && node.props.summary === "What this command installs",
  );
  assert.ok(section);
  assert.match(text(section), /cloud.wrangler/);
  assert.match(text(section), /base.system/);
  assert.doesNotMatch(text(section), /PostgreSQL|Vault|stack.ntm/);
});

test("continuation still requires the installer acknowledgement", () => {
  const item = fixture();
  let view = item.render();
  assert.equal(view.navigation().disabled, true);
  view.navigation().onContinue();
  assert.deepEqual(item.completed, []);
  item.setAcknowledged(true);
  view = item.render();
  assert.equal(view.navigation().disabled, false);
  view.navigation().onContinue();
  assert.deepEqual(item.completed, [9]);
  assert.deepEqual(item.navigations, ["/wizard/reconnect-ubuntu"]);
});

for (const [key, value] of [
  ["profile", "minimal"],
  ["mode", "vibe"],
  ["ref", "another-tag"],
  ["username", "another-user"],
  ["ip", "203.0.113.43"],
]) {
  test(`acknowledgement cannot survive a changed ${key}`, () => {
    const item = fixture();
    let view = item.render();
    const previousKey = view.main().props.persistKey;
    item.setAcknowledged(true);
    assert.equal(item.render().navigation().disabled, false);
    item.prefs[key] = value;
    view = item.render();
    assert.notEqual(view.main().props.persistKey, previousKey);
    assert.equal(view.navigation().disabled, true);
    view.navigation().onContinue();
    assert.deepEqual(item.completed, []);
    item.setAcknowledged(true);
    assert.equal(item.render().navigation().disabled, false);
  });
}

test("old unbound acknowledgements do not approve a new scoped command", () => {
  const item = fixture();
  item.acknowledgements.set("acfs-command-run-flywheel-installer", true);
  const view = item.render();
  assert.equal(view.navigation().disabled, true);
  assert.match(view.main().props.persistKey, /^run-flywheel-installer-v2-[a-f0-9]{64}$/);
  assert.ok(!view.main().props.persistKey.includes(item.prefs.ip));
  assert.ok(!view.main().props.persistKey.includes(item.prefs.username));
});

test("catalogue and checksum changes invalidate a formerly acknowledged command", () => {
  for (const key of ["manifestSha256", "checksumsYamlSha256"]) {
    const item = fixture();
    let view = item.render();
    const previousKey = view.main().props.persistKey;
    item.setAcknowledged(true);
    assert.equal(item.render().navigation().disabled, false);
    item.provenance[key] = "c".repeat(64);
    view = item.render();
    assert.notEqual(view.main().props.persistKey, previousKey);
    assert.equal(view.navigation().disabled, true);
  }
});

test("pending or failed hashing cannot reuse a preceding completion but leaves the safe command copyable", () => {
  const item = fixture();
  item.render();
  item.setAcknowledged(true);
  for (const set of [item.setCheckpointPending, item.setCheckpointFailed]) {
    set(true);
    const view = item.render();
    assert.ok(view.main().props.command);
    assert.equal(view.main().props.showCheckbox, false);
    assert.equal(view.main().props.persistKey, undefined);
    assert.equal(view.navigation().disabled, true);
    set(false);
  }
});

test("late or placeholder checkpoint data from a different host cannot unlock the new context", () => {
  const item = fixture();
  item.render();
  item.setAcknowledged(true);
  const old = item.checkpoint();
  item.prefs.ip = "203.0.113.99";
  item.overrideCheckpoint(old);
  const view = item.render();
  assert.equal(view.main().props.showCheckbox, false);
  assert.equal(view.navigation().disabled, true);
});

test("an acknowledged context can be revisited without approving a different one", () => {
  const item = fixture();
  const first = item.render().main().props.persistKey;
  item.setAcknowledged(true);
  item.prefs.profile = "minimal";
  assert.equal(item.render().navigation().disabled, true);
  item.prefs.profile = "cloud-only";
  const view = item.render();
  assert.equal(view.main().props.persistKey, first);
  assert.equal(view.navigation().disabled, false);
});

test("cache targets the explicit upgrade destination while exports preserve an older source image", () => {
  const item = fixture();
  const view = item.render();
  const cacheBuilder = view.nodes.find(
    (node) =>
      node.type === "command-card" &&
      node.props.description === "Build the verified installer cache",
  );
  assert.match(cacheBuilder.props.command, /--ubuntu-version 26\.04/);
  assert.doesNotMatch(cacheBuilder.props.command, /24\.04/);
  assert.equal(item.calls.provider[0].ubuntuVersion, "24.04");
  assert.equal(item.calls.profile[0].providerSelection.ubuntuVersion, "24.04");
});

test("cache destination follows structured command details, not a duplicate hard-coded version", () => {
  const item = fixture({ installDestination: "24.04" });
  const view = item.render();
  const cacheBuilder = view.nodes.find(
    (node) =>
      node.type === "command-card" &&
      node.props.description === "Build the verified installer cache",
  );
  assert.match(cacheBuilder.props.command, /--ubuntu-version 24\.04/);
  assert.match(view.cache().props.command, /--target-ubuntu=24\.04/);
});

test("missing provider preferences use the shared recommendation rather than retired 25.10", () => {
  const item = fixture({ provider: null });
  item.render();
  assert.equal(item.calls.provider[0].ubuntuVersion, "26.04");
  assert.equal(item.calls.profile[0].providerSelection.ubuntuVersion, "26.04");
});

test("active reviewed selection drives primary, cache and all handoffs without widening profile-only defaults", async () => {
  const item = fixture();
  item.render();
  const saved = plain(item.prefs);
  item.adopt();
  const view = item.render();
  const active = item.session.installation;
  assert.equal(view.main().props.command, active.command);
  assert.match(view.main().props.command, /--only "agents.claude"/);
  assert.match(view.cache().props.command, /--skip "acfs.nightly"/);
  for (const kind of ["runbook", "profile", "provider"]) {
    assert.deepEqual(item.calls[kind].at(-1).moduleSelection, active.moduleSelection);
    assert.equal(item.calls[kind].at(-1).username, "team-user");
  }
  assert.deepEqual(item.prefs, saved);
  for (const label of ["Runbook JSON", "Provider Packet", "Team Profile"])
    view.button(label).props.onClick();
  await Promise.resolve();
  for (const serialized of item.copies)
    assert.deepEqual(JSON.parse(serialized).input.moduleSelection, active.moduleSelection);
});

test("adoption ignores an earlier invalid pin draft and prevents settings handlers from changing approved choices", () => {
  const item = fixture({ ref: "v0.1.0" });
  let view = item.render();
  view.pinInput().props.onChange({ target: { value: "bad;ref" } });
  assert.equal(item.render().main(), undefined);
  item.adopt();
  view = item.render();
  assert.equal(view.main().props.command, item.session.installation.command);
  assert.equal(view.picker().props.disabled, true);
  assert.equal(view.pinInput().props.disabled, true);
  assert.equal(view.pinToggle().props.disabled, true);
  view.picker().props.onChange({ target: { value: "minimal" } });
  view.pinInput().props.onChange({ target: { value: "v9.0.0" } });
  view.pinToggle().props.onCheckedChange(false);
  assert.equal(item.render().main().props.command, item.session.installation.command);
  assert.equal(item.prefs.profile, "cloud-only");
  assert.equal(item.prefs.ref, "v0.1.0");
});

test("reviewed main ref remains unpinned despite an earlier open pin editor", () => {
  const item = fixture({ ref: "old-tag" });
  item
    .render()
    .pinInput()
    .props.onChange({ target: { value: "other-tag" } });
  item.adopt({ ref: null });
  const view = item.render();
  assert.equal(view.pinToggle().props.checked, false);
  assert.doesNotMatch(view.main().props.command, /--ref/);
  assert.equal(view.main().props.command, item.session.installation.command);
});

test("reviewed mode is not silently replaced by a conflicting profile label", () => {
  const item = fixture();
  item.adopt({
    mode: "vibe",
    moduleSelection: {
      profile: "safe",
      onlyModules: [],
      onlyPhases: [],
      skipModules: [],
      noDeps: false,
    },
  });
  assert.equal(item.render().main().props.command, item.session.installation.command);
  assert.ok(item.calls.command.every((call) => call.mode === "vibe"));
});

test("cache architecture and export source image use operator-confirmed reviewed facts", () => {
  const item = fixture();
  item.adopt();
  const view = item.render();
  const cacheBuilder = view.nodes.find(
    (node) =>
      node.type === "command-card" &&
      node.props.description === "Build the verified installer cache",
  );
  assert.match(cacheBuilder.props.command, /--arch aarch64/);
  assert.match(cacheBuilder.props.command, /--ubuntu-version 26.04/);
  assert.equal(item.calls.profile.at(-1).architecture, "aarch64");
  assert.equal(item.calls.profile.at(-1).providerSelection.ubuntuVersion, "22.04");
  assert.equal(item.calls.provider.at(-1).ubuntuVersion, "22.04");
  assert.equal(item.prefs.provider.ubuntuVersion, "24.04");
});

test("an exact-command mismatch blocks primary, cached, exported and continuation paths", () => {
  const item = fixture();
  item.adopt();
  item.session.installation.command += " UNREVIEWED";
  const view = item.render();
  assert.equal(view.main(), undefined);
  assert.equal(view.cache(), undefined);
  assert.equal(item.calls.runbook.length, 0);
  assert.equal(item.calls.provider.length, 0);
  assert.equal(item.calls.profile.length, 0);
  assert.equal(view.navigation().disabled, true);
  view.navigation().onContinue();
  assert.deepEqual(item.completed, []);
  for (const label of ["Runbook JSON", "Provider Packet", "Team Profile"])
    view.button(label).props.onClick();
  assert.equal(item.copies.length, 0);
});

test("adoption changes the scoped acknowledgement and cannot reuse saved installation completion", () => {
  const item = fixture();
  const previous = item.render().main().props.persistKey;
  item.setAcknowledged(true);
  assert.equal(item.render().navigation().disabled, false);
  item.adopt();
  const view = item.render();
  assert.notEqual(view.main().props.persistKey, previous);
  assert.equal(view.navigation().disabled, true);
});
