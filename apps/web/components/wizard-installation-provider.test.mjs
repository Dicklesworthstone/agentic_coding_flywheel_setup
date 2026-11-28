/** Real review/session and preference code; React/query/canonical-validator contracts are doubled. */
import { strict as assert } from "node:assert";
import { webcrypto } from "node:crypto";
import { getEventListeners, setMaxListeners } from "node:events";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { test } from "node:test";
import { createContext, runInContext } from "node:vm";

const require = createRequire(import.meta.url);
const ts = require("typescript");
// Reuse only compilation output. Every load still reads the current source,
// checks diagnostics and evaluates fresh exports in its fixture's VM.
const compiledSources = new Map();
const plain = (value) => JSON.parse(JSON.stringify(value));
const key = "acfs-reviewed-installation-pending-v1";
const text = (node) =>
  Array.isArray(node)
    ? node.map(text).join(" ")
    : node && typeof node === "object"
      ? text(node.props?.children)
      : typeof node === "string"
        ? node
        : "";

function fixture(sessionEntries = new Map(), initialPath = "/wizard/run-installer") {
  const local = new Map([
    ["agent-flywheel-vps-ip", "203.0.113.7"],
    ["agent-flywheel-ssh-username", "ubuntu"],
    ["agent-flywheel-module-profile", "full"],
    ["agent-flywheel-install-mode", "vibe"],
    ["agent-flywheel-user-os", "linux"],
    [
      "agent-flywheel-vps-readiness-selection",
      JSON.stringify({
        providerId: "other",
        planName: "custom plan",
        region: "not-listed",
        ubuntuVersion: "24.04",
        targetAgents: 10,
        workloadId: "standard",
      }),
    ],
  ]);
  const storageWrites = [];
  const queryWrites = [];
  let loaded = true;
  let localWritesBlocked = false;
  let path = initialPath;
  const storage = {
    getItem: (name) => sessionEntries.get(name) ?? null,
    setItem(name, value) {
      storageWrites.push([name, value]);
      sessionEntries.set(name, value);
    },
    removeItem(name) {
      storageWrites.push([name, null]);
      sessionEntries.delete(name);
    },
  };
  const window = new EventTarget();
  // Each mounted production preference hook subscribes independently, as in a
  // browser. Node's EventTarget warning threshold is lower than this fixture.
  setMaxListeners(100, window);
  window.sessionStorage = storage;
  window.location = { href: "https://example.invalid/wizard/run-installer", search: "" };
  window.history = {
    state: null,
    replaceState(_state, _unused, address) {
      window.location.href = address;
      window.location.search = new URL(address).search;
    },
  };
  const instances = new Map();
  let instance;
  let index;
  let changed = false;
  const equal = (a, b) =>
    a && b && a.length === b.length && a.every((value, n) => Object.is(value, b[n]));
  function slot() {
    const n = index++;
    return [instance, n];
  }
  const react = {
    createContext: (value) => ({ value, Provider: Symbol("provider") }),
    useContext: (context) => context.value,
    useId() {
      const [owner, n] = slot();
      return (owner.slots[n] ??= { value: `fixture-${n}` }).value;
    },
    useState(initial) {
      const [owner, n] = slot();
      if (!owner.slots[n])
        owner.slots[n] = { value: typeof initial === "function" ? initial() : initial };
      return [
        owner.slots[n].value,
        (next) => {
          const previous = owner.slots[n].value;
          const value = typeof next === "function" ? next(previous) : next;
          if (!Object.is(previous, value)) {
            owner.slots[n].value = value;
            changed = true;
          }
        },
      ];
    },
    useRef(value) {
      const [owner, n] = slot();
      return (owner.slots[n] ??= { current: value });
    },
    useMemo(fn, deps) {
      const [owner, n] = slot();
      const previous = owner.slots[n];
      if (!previous || !equal(previous.deps, deps)) owner.slots[n] = { value: fn(), deps };
      return owner.slots[n].value;
    },
    useCallback(fn, deps) {
      return react.useMemo(() => fn, deps);
    },
    useEffect(fn, deps) {
      const [owner, n] = slot();
      const previous = owner.slots[n];
      if (!previous || !equal(previous.deps, deps)) {
        owner.effects.push(() => {
          previous?.cleanup?.();
          const cleanup = fn();
          owner.slots[n].cleanup = cleanup;
        });
        owner.slots[n] = { deps, cleanup: previous?.cleanup };
      }
    },
  };
  const jsx = (type, props) => ({ type, props: props ?? {} });
  const vm = createContext({
    window,
    URL,
    URLSearchParams,
    Event,
    TextEncoder,
    TextDecoder,
    crypto: webcrypto,
    structuredClone,
  });
  function load(url, dependencies) {
    const source = readFileSync(url, "utf8");
    let cached = compiledSources.get(url.href);
    if (cached?.source !== source) {
      cached = {
        source,
        compiled: ts.transpileModule(source, {
          fileName: url.pathname,
          reportDiagnostics: true,
          compilerOptions: {
            module: ts.ModuleKind.CommonJS,
            target: ts.ScriptTarget.ES2022,
            jsx: ts.JsxEmit.ReactJSX,
          },
        }),
      };
      compiledSources.set(url.href, cached);
    }
    const compiled = cached.compiled;
    assert.deepEqual(
      (compiled.diagnostics ?? []).filter(
        (entry) => entry.category === ts.DiagnosticCategory.Error,
      ),
      [],
    );
    const cjs = { exports: {} };
    const invoke = runInContext(
      `(function(require,module,exports){${compiled.outputText}\n})`,
      vm,
      { timeout: 5000 },
    );
    invoke(
      (name) => {
        assert.ok(Object.hasOwn(dependencies, name), `Unexpected import ${name}`);
        return dependencies[name];
      },
      cjs,
      cjs.exports,
    );
    return cjs.exports;
  }
  const catalogue = {
    manifestProvenance: { manifestSha256: "a".repeat(64), checksumsYamlSha256: "b".repeat(64) },
    manifestSelectionProfiles: [
      "full",
      "minimal",
      "agents-only",
      "cloud-only",
      "stack-only",
      "safe",
      "vibe",
    ].map((id) => ({
      id,
      label: id,
      onlyModules: [],
      onlyPhases: [],
      ...(["safe", "vibe"].includes(id) ? { mode: id } : {}),
    })),
  };
  const contextModule = load(new URL("../lib/wizardInstallation.ts", import.meta.url), { react });
  const selectionCatalogue = load(new URL("../lib/generated/manifest-modules.ts", import.meta.url), {});
  const selections = load(new URL("../lib/moduleSelection.ts", import.meta.url), {
    "./generated/manifest-modules": selectionCatalogue,
  });
  const queryClient = {
    invalidateQueries() {},
    getQueryData() {
      return undefined;
    },
    setQueryData(queryKey, value) {
      queryWrites.push([plain(queryKey), plain(value)]);
    },
  };
  const queryCache = new Map();
  const useQuery = ({ queryKey, queryFn }) => {
    const key = JSON.stringify(queryKey);
    const next = queryFn();
    const previous = queryCache.get(key);
    const data =
      previous && JSON.stringify(previous.data) === JSON.stringify(next) ? previous.data : next;
    queryCache.set(key, { data });
    return { data, status: loaded ? "success" : "pending" };
  };
  const inputValidation = {
    isValidIP: (value) => /^203\.0\.113\.\d+$/.test(value),
    normalizeGitRef: (value) =>
      typeof value === "string" && /^[a-zA-Z0-9/_.-]+$/.test(value.trim()) ? value.trim() : null,
    normalizeSSHUsername: (value) =>
      typeof value === "string" && /^[a-z][a-z0-9_-]*$/.test(value.trim()) ? value.trim() : null,
  };
  const preferences = load(new URL("../lib/userPreferences.ts", import.meta.url), {
    react,
    "./wizardInstallation": contextModule,
    "./moduleSelection": selections,
    "@tanstack/react-query": { useQuery, useQueryClient: () => queryClient },
    "./inputValidation": inputValidation,
    "./utils": {
      safeGetItem: (name) => local.get(name) ?? null,
      safeGetJSON: (name) => (local.has(name) ? JSON.parse(local.get(name)) : null),
      safeSetItem: (name, value) => {
        if (localWritesBlocked) return false;
        local.set(name, value);
        return true;
      },
      safeSetJSON: (name, value) => {
        local.set(name, JSON.stringify(value));
        return true;
      },
      stripSensitiveQueryState: (search) => search,
      urlContainsSensitiveState: () => false,
    },
    "./vpsProviders": { VPS_PROVIDERS: [], validateUbuntuImage: () => ({ status: "supported" }) },
    "./generated/manifest-modules": catalogue,
  });
  let validate = true;
  let revision = "";
  let commandRevision = "";
  const command = (mode, ref, username, selection) =>
    `${mode}|${ref ?? "main"}|${username}|${JSON.stringify(selection)}`;
  const commandCalls = [];
  const copies = [];
  const commands = {
    buildInstallCommand: (...args) => {
      commandCalls.push(plain(args));
      return command(...args) + commandRevision;
    },
    formatSshTarget: (user, host) => `${user}@${host}`,
    buildCommands: (input) => [
      {
        id: "installer",
        label: "Install",
        description: "Reviewed installer",
        runLocation: "vps",
        command: commands.buildInstallCommand(
          input.mode,
          input.ref,
          input.username,
          input.moduleSelection,
        ),
      },
      {
        id: "ssh-user",
        label: "Reconnect",
        description: "Reviewed user",
        runLocation: "local",
        command: `ssh -i ~/.ssh/acfs_ed25519 ${input.username}@${input.ip}`,
        windowsCommand: `ssh -i $HOME\\.ssh\\acfs_ed25519 ${input.username}@${input.ip}`,
      },
    ],
    buildShareURL: () => assert.fail("Reviewed approval cannot be shared through URLs"),
    buildTeamProfileImportDiff(source) {
      return {
        schema: "acfs.team-profile-import-diff.v1",
        dryRun: true,
        ok: validate,
        profile: { profileId: source.profileId, displayName: source.displayName },
        findings: validate ? [] : [{ code: "team_profile_manifest_mismatch" }],
        installerCommand: {
          command:
            command(
              source.install.mode,
              source.install.ref.value === "main" ? null : source.install.ref.value,
              source.providerDefaults.sshUser,
              {
                profile: source.install.profile,
                onlyModules: source.install.modules.only,
                onlyPhases: source.install.modules.onlyPhases,
                skipModules: source.install.modules.skip,
                noDeps: false,
              },
            ) + revision,
          changes: [],
        },
        skips: { allowed: validate, requested: source.install.modules.skip, warnings: [] },
        safeDefaults: { changes: [] },
        dependencyClosure: [],
        secretSlots: { required: [], optional: [] },
        incompatibilities: [],
        refusals: [],
      };
    },
  };
  const core = load(new URL("../lib/teamProfileImport.ts", import.meta.url), {
    "./commandBuilder": commands,
    "./generated/manifest-modules": catalogue,
  });
  const common = {
    react,
    "react/jsx-runtime": { jsx, jsxs: jsx, Fragment: "fragment" },
    "@/components/ui/button": { Button: "button" },
    "@/components/command-card": {
      CommandCard: "command-card",
      CodeBlock: "code-block",
      commandCompletionKeys: { completion: (value) => ["command", value] },
    },
    "@/lib/userPreferences": preferences,
    "@/lib/wizardInstallation": contextModule,
    "@/lib/teamProfileImport": core,
    "@/lib/commandBuilder": commands,
    "@/lib/moduleSelection": selections,
    "@/lib/utils": {
      cn: (...parts) => parts.filter(Boolean).join(" "),
      safeGetItem: () => null,
      withCurrentSearch: (path) => path,
    },
    "lucide-react": Object.fromEntries(
      [
        "Terminal",
        "Link2",
        "Check",
        "Copy",
        "Server",
        "Monitor",
        "Settings2",
        "ChevronDown",
        "Boxes",
        "AlertCircle",
        "Stethoscope",
        "KeyRound",
        "Shield",
        "Bot",
        "Cloud",
        "Wrench",
        "BookOpen",
        "Laptop",
      ].map((value) => [value, `icon-${value}`]),
    ),
  };
  const panel = load(new URL("./team-profile-import-panel.tsx", import.meta.url), {
    ...common,
    "@/lib/vpsProviders": { VPS_UBUNTU_IMAGE_OPTIONS: ["26.04", "24.04", "22.04"] },
  });
  // Independent consumers are loaded only by their corresponding helper. They
  // retain fresh exports per fixture, without compiling every route for an SSR
  // hydration-only check.
  let healthHook;
  function getHealthHook() {
    return (healthHook ??= load(new URL("../lib/hooks/useInstallationHealth.ts", import.meta.url), {
      react,
      "@tanstack/react-query": { useQuery, useQueryClient: () => queryClient },
      "@/components/command-card": {
        ...common["@/components/command-card"],
        COMMAND_COMPLETION_CHANGED_EVENT: "acfs:command-completion-changed",
      },
      "@/lib/commandBuilder": commands,
      "@/lib/generated/manifest-modules": catalogue,
      "@/lib/inputValidation": inputValidation,
      "@/lib/installerCheckpoint": load(new URL("../lib/installerCheckpoint.ts", import.meta.url), {}),
      "@/lib/moduleSelection": selections,
      "@/lib/userPreferences": preferences,
      "@/lib/utils": { safeGetItem: () => null },
      "@/lib/wizardInstallation": contextModule,
    }));
  }
  let statusPage;
  function getStatusPage() {
    if (statusPage) return statusPage;
    statusPage = load(new URL("../app/wizard/status-check/page.tsx", import.meta.url), {
      ...common,
      "@/lib/hooks/useInstallationHealth": getHealthHook(),
      "@tanstack/react-query": { useQuery },
      "next/link": { default: "link" },
      "next/navigation": { useRouter: () => ({ push() {}, replace() {} }) },
      "@/components/alert-card": { AlertCard: "alert", OutputPreview: "output-preview" },
      "@/components/connection-check": { WhereAmICheck: "connection-check" },
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
        markStepComplete() {},
        useWizardForwardNav: () => ({}),
        validateStep: () => ({ valid: true }),
      },
      "@/lib/services": load(new URL("../lib/services.ts", import.meta.url), {
        "./generated/manifest-agents": load(new URL("../lib/generated/manifest-agents.ts", import.meta.url), {}),
      }),
      "@/lib/hooks/useWizardAnalytics": { useWizardAnalytics: () => ({ markComplete() {} }) },
    });
    return statusPage;
  }
  let learnPage;
  function getLearnPage() {
    if (learnPage) return learnPage;
    const lessons = load(new URL("../lib/lessons.ts", import.meta.url), {});
    const progress = load(new URL("../lib/lessonProgress.ts", import.meta.url), {
      react,
      "./lessons": lessons,
      "./utils": common["@/lib/utils"],
      "@tanstack/react-query": {},
    });
    const learningPath = load(new URL("../lib/learningPath.ts", import.meta.url), {
      "./generated/manifest-tools": load(new URL("../lib/generated/manifest-tools.ts", import.meta.url), {}),
      "./generated/manifest-agents": load(new URL("../lib/generated/manifest-agents.ts", import.meta.url), {}),
      "./lessons": lessons,
      "./moduleSelection": selections,
    });
    const doctor = load(new URL("./doctor-report-panel.tsx", import.meta.url), {
      ...common,
      "next/link": { default: "link" },
      "@/lib/doctorReport": load(new URL("../lib/doctorReport.ts", import.meta.url), {}),
      "@/lib/generated/manifest-modules": { ...selectionCatalogue, ...catalogue },
      "@/lib/hooks/useInstallationHealth": getHealthHook(),
      "@/lib/vpsProviders": { ACFS_RECOMMENDED_UBUNTU: "26.04" },
    });
    learnPage = load(new URL("../app/learn/page.tsx", import.meta.url), {
      ...common,
      "next/link": { default: "link" },
      "next/navigation": { useRouter: () => ({ push() {}, replace() {} }) },
      "@/components/motion": { motion: new Proxy({}, { get: (_object, tag) => `motion-${String(tag)}` }) },
      "@/components/doctor-report-panel": doctor,
      "@/lib/analytics": { getLessonFunnelData: () => ({}), initLessonFunnel() {}, sendEvent() {} },
      "@/lib/design-tokens": { springs: {} },
      "@/lib/hooks/useReducedMotion": { useReducedMotion: () => true },
      "@/lib/lessonProgress": {
        ...progress,
        getCompletedLessons: () => [],
        useCompletedLessons: () => ({ completedLessons: [], hasLoaded: true }),
      },
      "@/lib/learningPath": learningPath,
      "@/lib/utils": { ...common["@/lib/utils"], isInteractiveKeyboardTarget: () => false },
    });
    return learnPage;
  }
  let commandPanel;
  function getCommandPanel() {
    return (commandPanel ??= load(new URL("./command-builder-panel.tsx", import.meta.url), {
      ...common,
      "@/components/ui/code-block": { CopyStatus: "copy-status" },
      "@/lib/hooks/useCopyFeedback": {
        useCopyFeedback: () => ({ state: "idle", copy: async (value) => copies.push(value) }),
      },
      "@/lib/moduleSelection": {
        resolveModuleSelection: () =>
          assert.fail("An active panel must not reenter editable defaults"),
      },
      "@/lib/generated/manifest-modules": catalogue,
    }));
  }
  const component = load(new URL("./wizard-installation-provider.tsx", import.meta.url), {
    react,
    "react/jsx-runtime": { jsx, jsxs: jsx, Fragment: "fragment" },
    "next/navigation": { usePathname: () => path },
    "@/components/ui/button": { Button: "button" },
    "@/components/team-profile-import-panel": panel,
    "@/lib/userPreferences": preferences,
    "@/lib/wizardInstallation": contextModule,
    "@/lib/teamProfileImport": core,
    "@/lib/commandBuilder": commands,
  });
  let rootLayout;
  function getRootLayout() {
    return (rootLayout ??= load(new URL("../app/layout.tsx", import.meta.url), {
      react: { Suspense: "suspense" },
      "react/jsx-runtime": common["react/jsx-runtime"],
      "./globals.css": {},
      "next/font/local": {
        default: ({ variable }) => ({ variable }),
      },
      "@/components/query-provider": { QueryProvider: "query-provider" },
      "@/components/analytics-provider": { AnalyticsProvider: "analytics-provider" },
      "@/components/motion/motion-provider": { MotionProvider: "motion-provider" },
      "@/components/third-party-scripts": { ThirdPartyScripts: "third-party-scripts" },
      "@/components/wizard-installation-provider": component,
    }));
  }
  function invoke(name, fn, effects = true) {
    instance = instances.get(name) ?? { slots: [], effects: [] };
    instances.set(name, instance);
    let result;
    let attempts = 0;
    do {
      assert.ok(attempts++ < 10, "render loop");
      changed = false;
      index = 0;
      result = fn();
      if (effects) {
        const queue = instance.effects.splice(0);
        for (const effect of queue) effect();
      }
    } while (effects && changed);
    return result;
  }
  let tree;
  function render(effects = true) {
    tree = invoke(
      "provider",
      () => component.WizardInstallationProvider({ children: jsx("wizard-children", {}) }),
      effects,
    );
    contextModule.WizardInstallationContext.value =
      tree.type === contextModule.WizardInstallationContext.Provider ? tree.props.value : null;
    return tree;
  }
  function context() {
    return {
      targetHost: preferences.getVPSIP(),
      current: {
        providerSelection: preferences.getVPSReadinessSelection(),
        installMode: preferences.getInstallMode(),
        ref: preferences.getACFSRef(),
        username: preferences.getSSHUsername(),
        architecture: "aarch64",
        ubuntuVersion: "24.04",
        moduleSelection: preferences.getSavedModuleSelection(),
      },
    };
  }
  const profile = {
    profileId: "team-example",
    displayName: "Team Example",
    compatibility: {
      architectures: ["aarch64"],
      targetUbuntuVersions: ["24.04", "26.04"],
    },
    providerDefaults: { sshUser: "team-user" },
    install: {
      mode: "safe",
      profile: "full",
      ref: { value: "v1.2.3" },
      modules: { only: ["agents.claude"], onlyPhases: [], skip: ["acfs.nightly"], noDeps: false },
    },
  };
  function ui(name, renderComponent) {
    const nodes = invoke(name, () => {
      const nodes = [];
      function visit(node) {
        if (Array.isArray(node)) {
          node.forEach(visit);
          return;
        }
        if (!node || typeof node !== "object") return;
        if (typeof node.type === "function") {
          visit(node.type(node.props));
          return;
        }
        nodes.push(node);
        visit(node.props.children);
      }
      visit(renderComponent());
      return nodes;
    });
    const find = (test) => {
      const node = nodes.find(test);
      assert.ok(node, "expected element");
      return node;
    };
    return {
      nodes,
      text: () => nodes.map(text).join(" "),
      button: (label) =>
        find(
          (node) =>
            node.type === "button" &&
            (node.props["aria-label"] === label ||
              text(node).replace(/\s+/g, " ").trim() === label),
        ),
      control: (suffix) => find((node) => node.props.id?.endsWith(`-${suffix}`)),
    };
  }
  return {
    render,
    core,
    context,
    profile,
    preferences,
    storage,
    sessionEntries,
    local,
    window,
    blockLocalWrites: () => { localWritesBlocked = true; },
    storageWrites,
    queryWrites,
    catalogue,
    commandCalls,
    copies,
    panel: () => ui("panel", () => panel.TeamProfileImportPanel()),
    statusPage: () => ui("status-page", () => getStatusPage().default()),
    learnPage: () => ui("learn-page", () => getLearnPage().default()),
    health: () => invoke("health-consumer", () => getHealthHook().useInstallationHealth()),
    commands: () => ui("command-panel", () => getCommandPanel().CommandBuilderPanel()),
    root: () => getRootLayout().default({ children: jsx("route", {}) }),
    providerType: component.WizardInstallationProvider,
    session: () => contextModule.WizardInstallationContext.value,
    hooks: () =>
      invoke("consumer", () => ({
        user: preferences.useSSHUsername(),
        mode: preferences.useInstallMode(),
        ref: preferences.useACFSRef(),
        profile: preferences.useModuleProfile(),
        selection: preferences.useModuleSelection(),
        setup: preferences.useWizardSetup(),
      })),
    review: () => core.reviewTeamProfileFile(new Blob([JSON.stringify(profile)]), context()),
    navigate: (value) => {
      path = value;
      return render();
    },
    refuse: () => {
      validate = false;
    },
    changeValidation: () => {
      revision = "-changed";
    },
    changeCommand: () => {
      commandRevision = "-changed";
    },
    setLoaded: (value) => {
      loaded = value;
    },
    event: (name) => {
      window.dispatchEvent(new Event(name));
      return render();
    },
    unmount: () => {
      for (const item of instances.values()) for (const slot of item.slots) slot?.cleanup?.();
    },
    listenerCount: () =>
      ["storage", "popstate", "pageshow", "focus", "acfs:user-preferences-updated"].reduce(
        (count, name) => count + getEventListeners(window, name).length,
        0,
      ),
    hasChildren: () =>
      text(tree).includes("never-used") || JSON.stringify(tree).includes("wizard-children"),
  };
}

async function activeFixture() {
  const f = fixture();
  f.render();
  f.session().activate(await f.review(), f.context(), true);
  f.render();
  assert.equal(f.session().status, "active");
  return f;
}

test("SSR and unhydrated queries never expose a default command subtree", () => {
  const f = fixture();
  const server = f.render(false);
  assert.match(text(server), /Loading installation/);
  assert.equal(f.hasChildren(), false);
  f.setLoaded(false);
  f.render();
  assert.equal(f.session().status, "loading");
  assert.equal(f.hasChildren(), false);
  f.setLoaded(true);
  f.render();
  assert.equal(f.session().status, "saved");
  assert.equal(f.hasChildren(), true);
});

test("review activation atomically changes every install preference without saved or query writes", async () => {
  const f = fixture();
  f.render();
  const localBefore = [...f.local];
  const queriesBefore = plain(f.queryWrites);
  f.session().activate(await f.review(), f.context(), true);
  f.render();
  const values = f.hooks();
  assert.equal(values.user[0], "team-user");
  assert.equal(values.mode[0], "safe");
  assert.equal(values.ref[0], "v1.2.3");
  assert.deepEqual(plain(values.selection[0]), {
    profile: "full",
    onlyModules: ["agents.claude"],
    onlyPhases: [],
    skipModules: ["acfs.nightly"],
    noDeps: false,
  });
  assert.equal(values.user[2], true);
  assert.equal(values.selection[1], true);
  assert.deepEqual(plain(f.session().installation.compatibilityTargets), {
    architectures: ["aarch64"],
    targetUbuntuVersions: ["24.04", "26.04"],
  });
  assert.deepEqual([...f.local], localBefore);
  assert.deepEqual(f.queryWrites, queriesBefore);
  assert.deepEqual(f.storageWrites, [[key, "review-required"]]);
  assert.equal(
    f.preferences.getSSHUsername(),
    "ubuntu",
    "saved getter must not become an imported value",
  );
});

for (const route of [
  "reconnect-ubuntu",
  "verify-key-connection",
  "status-check",
  "launch-onboarding",
  "windows-terminal-setup",
]) {
  test(`the approved username and exact selection survive client navigation to ${route}`, async () => {
    const f = await activeFixture();
    const first = f.session().installation;
    f.navigate(`/wizard/${route}`);
    assert.equal(f.session().installation, first);
    assert.equal(f.hooks().user[0], "team-user");
    assert.equal(f.hasChildren(), true);
  });
}

test("visiting a public route leaves its preference consumers unchanged and retains the wizard session", async () => {
  const f = await activeFixture();
  const first = f.session().installation;
  f.navigate("/");
  assert.equal(f.session(), null);
  assert.equal(f.hooks().user[0], "ubuntu");
  f.navigate("/wizard/run-installer");
  assert.equal(f.session().installation, first);
});

for (const route of ["/learn", "/learn/tools/claude-code"]) {
  test(`the reviewed installation survives the onboarding handoff to ${route}`, async () => {
    const f = await activeFixture();
    const installation = f.session().installation;
    const saved = [...f.local];
    const writes = plain(f.storageWrites);
    f.navigate(route);
    assert.equal(f.session()?.installation, installation);
    const values = f.hooks();
    assert.equal(values.user[0], "team-user");
    assert.equal(values.mode[0], "safe");
    assert.equal(values.ref[0], "v1.2.3");
    assert.deepEqual(plain(values.selection[0]), plain(installation.moduleSelection));
    assert.equal(values.selection[1], true);
    assert.equal(f.hasChildren(), true, "learning pages remain accessible");
    assert.deepEqual([...f.local], saved);
    assert.deepEqual(f.storageWrites, writes);
    f.navigate("/wizard/status-check");
    assert.equal(f.session().installation, installation);
  });
}

test("a pending review on the Learning Hub cannot revive the saved full installation", () => {
  const f = fixture(new Map([[key, "review-required"]]), "/learn");
  const saved = [...f.local];
  f.render();
  assert.equal(f.session()?.status, "review_required");
  assert.equal(f.session().installation, null);
  assert.equal(f.hasChildren(), true, "the lesson catalogue must stay public");
  assert.equal(f.hooks().selection[1], false);
  assert.equal(f.hooks().user[2], false);
  assert.equal(f.commands().nodes.some((node) => node.type === "code"), false);
  assert.deepEqual([...f.local], saved);
  assert.deepEqual(f.storageWrites, []);
});

test("Learning Hub recommendations and Doctor use the exact approved stack, account and mode", async () => {
  const f = await activeFixture();
  const installation = f.session().installation;
  f.navigate("/learn");
  const view = f.learnPage();
  const recommendations = view.nodes
    .map((node) => node.props["data-recommendation-id"])
    .filter(Boolean);
  assert.deepEqual(recommendations, ["lesson-welcome", "tool-claude-code", "command-reference"]);
  assert.match(view.text(), /Using reviewed team profile:.*Team Example/);
  assert.ok(view.nodes.some((node) => node.type === "input" && node.props.type === "file"));
  const health = f.health();
  assert.equal(health.sshUsername, "team-user");
  assert.equal(health.reinstallCommand, installation.command);
  assert.deepEqual(
    plain(health.selectedPlan.included.map((module) => module.id)),
    ["base.system", "users.ubuntu", "agents.claude"],
  );
  assert.equal(f.hooks().mode[0], "safe");
});

for (const unavailable of [false, true]) {
  test(`Learning Hub offers recovery without hiding lessons when context is ${unavailable ? "unavailable" : "pending"}`, () => {
    const f = fixture(new Map([[key, "review-required"]]), "/learn");
    if (unavailable) f.storage.getItem = () => { throw new Error("storage blocked"); };
    f.render();
    const view = f.learnPage();
    assert.match(view.text(), unavailable ? /cannot read its session storage/ : /needs review again/);
    assert.match(view.text(), /All Lessons/);
    assert.ok(view.nodes.some((node) => node.type === "link" && node.props.href === "/wizard/run-installer"));
    assert.ok(view.nodes.some((node) => node.type === "link" && node.props.href === "/learn/welcome"));
    assert.ok(!view.nodes.some((node) => node.props["data-recommendation-id"]));
    assert.ok(!view.nodes.some((node) => node.type === "input" && node.props.type === "file"));
    assert.equal(f.health().reinstallCommand, null);
    assert.deepEqual(f.storageWrites, []);
  });
}

test("a first-time Learning Hub visitor retains generic guidance without assuming a full install", () => {
  const f = fixture(new Map(), "/learn");
  f.local.delete("agent-flywheel-vps-ip");
  f.render();
  const view = f.learnPage();
  const recommendations = view.nodes.find((node) => node.props["data-testid"] === "learning-recommendations");
  assert.equal(recommendations?.props["data-persona"], "getting-started");
  assert.equal(recommendations?.props["data-fallback"], "no-selection");
  assert.match(view.text(), /All Lessons/);
  assert.ok(!view.nodes.some((node) => node.type === "input" && node.props.type === "file"));
  assert.deepEqual(f.storageWrites, []);
});

test("reload cannot reconstruct an approval or silently show saved/default wizard commands", async () => {
  const first = await activeFixture();
  first.unmount();
  const f = fixture(first.sessionEntries);
  f.render();
  assert.equal(f.session().status, "review_required");
  assert.equal(f.session().installation, null);
  assert.equal(f.hasChildren(), false);
  assert.match(text(f.render()), /Reloading never restores approval/);
  assert.equal(f.hooks().selection[1], false);
  f.session().activate(await f.review(), f.context(), true);
  f.render();
  assert.equal(f.session().status, "active");
});

for (const [field, storageKey, value] of [
  ["host", "agent-flywheel-vps-ip", "203.0.113.8"],
  ["username", "agent-flywheel-ssh-username", "different"],
  ["mode", "agent-flywheel-install-mode", "safe"],
  ["ref", "agent-flywheel-acfs-ref", "v2.0.0"],
  ["profile", "agent-flywheel-module-profile", "minimal"],
  [
    "provider",
    "agent-flywheel-vps-readiness-selection",
    JSON.stringify({ ubuntuVersion: "26.04" }),
  ],
]) {
  test(`out-of-band ${field} edits block immediately and restoring old settings does not resurrect approval`, async () => {
    const f = await activeFixture();
    const previous = f.local.get(storageKey);
    f.local.set(storageKey, value);
    f.event("storage");
    assert.equal(f.session().status, "review_required");
    assert.equal(f.hasChildren(), false);
    previous === undefined ? f.local.delete(storageKey) : f.local.set(storageKey, previous);
    f.render();
    assert.equal(f.session().status, "review_required");
  });
}

for (const event of ["popstate", "pageshow", "focus", "acfs:user-preferences-updated"]) {
  test(`${event} rechecks raw host state rather than trusting a stale query snapshot`, async () => {
    const f = await activeFixture();
    f.local.set("agent-flywheel-vps-ip", "203.0.113.9");
    f.event(event);
    assert.equal(f.session().status, "review_required");
    assert.equal(f.hasChildren(), false);
  });
}

test("late activation handlers re-read saved context before writing an approval guard", async () => {
  const f = fixture();
  f.render();
  const review = await f.review();
  const context = f.context();
  const activate = f.session().activate;
  f.local.set("agent-flywheel-vps-ip", "203.0.113.9");
  assert.throws(() => activate(review, context, true), /changed/);
  assert.deepEqual(f.storageWrites, []);
});

test("changing generated trust metadata or the regenerated command invalidates an active installation", async () => {
  for (const mutate of [
    (f) => {
      f.catalogue.manifestProvenance.manifestSha256 = "c".repeat(64);
    },
    (f) => f.changeCommand(),
  ]) {
    const f = await activeFixture();
    mutate(f);
    f.render();
    assert.equal(f.session().status, "review_required");
    assert.equal(f.hasChildren(), false);
  }
});

test("active settings controls cannot partially write the saved username, mode, ref or profile", async () => {
  const f = await activeFixture();
  const before = [...f.local];
  const values = f.hooks();
  values.user[1]("different");
  values.mode[1]("vibe");
  values.ref[1]("v9.0.0");
  values.profile[1]("minimal");
  f.render();
  assert.deepEqual([...f.local], before);
  assert.equal(f.session().status, "active");
  assert.match(text(f.render()), /Discard the reviewed installation explicitly/);
});

test("explicit discard clears only its guard and restores the unchanged saved settings", async () => {
  const f = await activeFixture();
  f.sessionEntries.set("unrelated", "preserve");
  const before = [...f.local];
  f.session().discard();
  f.render();
  assert.equal(f.session().status, "saved");
  assert.equal(f.hooks().user[0], "ubuntu");
  assert.deepEqual([...f.local], before);
  assert.deepEqual([...f.sessionEntries], [["unrelated", "preserve"]]);
  f.hooks().user[1]("new-user");
  f.render();
  assert.equal(f.hooks().user[0], "new-user");
});

for (const failure of ["get", "write", "readback", "remove"]) {
  test(`sessionStorage ${failure} failure never exposes a restored/default installation`, async () => {
    const f = fixture(new Map([[key, "review-required"]]));
    f.render();
    if (failure === "get")
      f.storage.getItem = () => {
        throw new Error("PRIVATE");
      };
    if (failure === "write")
      f.storage.setItem = () => {
        throw new Error("PRIVATE");
      };
    if (failure === "readback")
      f.storage.setItem = () => {
        f.storage.getItem = () => {
          throw new Error("PRIVATE");
        };
      };
    if (failure === "remove") f.storage.removeItem = () => {};
    if (failure === "remove") f.session().discard();
    if (failure === "write" || failure === "readback") {
      const review = await f.review();
      assert.throws(() => f.session().activate(review, f.context(), true));
    }
    f.render();
    assert.notEqual(f.session().status, "saved");
    assert.equal(f.hasChildren(), false);
    assert.ok(!text(f.render()).includes("PRIVATE"));
  });
}

test("storage blocked from the first read renders the steps but withholds installation commands", () => {
  const f = fixture();
  f.storage.getItem = () => {
    throw new Error("PRIVATE");
  };
  const tree = f.render();
  assert.equal(f.session().status, "unavailable");
  assert.equal(f.hasChildren(), true, "setup steps must not be locked behind a dead-end review");
  assert.match(text(tree), /Installation commands are hidden in this tab/);
  assert.ok(!text(tree).includes("PRIVATE"));
  const hooks = f.hooks();
  for (const name of ["user", "mode", "ref", "profile"]) assert.equal(hooks[name][2], false, name);
  assert.equal(hooks.selection[1], false);
  const panel = f.commands();
  assert.ok(!panel.nodes.some((node) => node.type === "code"), "no command may render");
  assert.match(panel.text(), /before generating commands/);
});

test("an unresolved pathname cannot bypass hydration and render wizard commands", () => {
  const f = fixture(new Map(), null);
  f.render();
  assert.equal(f.hasChildren(), false);
  assert.equal(f.session().status, "loading");
});

test("lost guard blocks commands instead of reviving the active object", async () => {
  const f = await activeFixture();
  f.sessionEntries.delete(key);
  f.event("focus");
  assert.equal(f.session().status, "review_required");
  assert.equal(f.hasChildren(), false);
});

test("refused/changed canonical validation and fabricated reviews cannot activate a session", async () => {
  for (const mutation of ["refused", "changed", "fabricated"]) {
    const f = fixture();
    f.render();
    const review = await f.review();
    if (mutation === "refused") f.refuse();
    if (mutation === "changed") f.changeValidation();
    assert.throws(() =>
      f.session().activate(mutation === "fabricated" ? plain(review) : review, f.context(), true),
    );
    assert.deepEqual(f.storageWrites, []);
    assert.equal(f.session().installation, null);
  }
});

test("unmounted activation/discard callbacks cannot mutate storage", async () => {
  const f = fixture();
  f.render();
  const review = await f.review();
  const session = f.session();
  f.unmount();
  assert.throws(() => session.activate(review, f.context(), true), /Wait/);
  session.discard();
  assert.deepEqual(f.storageWrites, []);
});

async function reviewedPanel(f) {
  f.render();
  f.panel()
    .control("arch")
    .props.onChange({ target: { value: "aarch64" } });
  f.panel()
    .control("file")
    .props.onChange({
      currentTarget: { files: [new Blob([JSON.stringify(f.profile)])], value: "private.json" },
    });
  for (let attempt = 0; attempt < 100; attempt++) {
    await new Promise((done) => setTimeout(done, 1));
    const view = f.panel();
    if (view.nodes.some((node) => node.props.id?.endsWith("-adopt"))) return view;
  }
  assert.fail("The actual local review did not finish");
}

test("root layout mounts one persistent installation provider below QueryProvider", () => {
  const f = fixture();
  let found = 0;
  function visit(node, ancestors = []) {
    if (Array.isArray(node)) {
      node.forEach((child) => visit(child, ancestors));
      return;
    }
    if (!node || typeof node !== "object") return;
    if (node.type === f.providerType) {
      found++;
      assert.ok(ancestors.includes("query-provider"));
    }
    visit(node.props.children, [...ancestors, node.type]);
  }
  visit(f.root());
  assert.equal(found, 1);
});

// ThirdPartyScripts reads useSearchParams, so it needs its own Suspense
// boundary or every statically rendered route bails out to client rendering.
test("root layout mounts ThirdPartyScripts once, directly inside a Suspense boundary", () => {
  const f = fixture();
  let found = 0;
  function visit(node, ancestors = []) {
    if (Array.isArray(node)) {
      node.forEach((child) => visit(child, ancestors));
      return;
    }
    if (!node || typeof node !== "object") return;
    if (node.type === "third-party-scripts") {
      found++;
      assert.equal(ancestors.at(-1), "suspense");
    }
    visit(node.props.children, [...ancestors, node.type]);
  }
  visit(f.root());
  assert.equal(found, 1);
});

test("manual-command consent cannot silently adopt wizard settings; adoption has separate explicit consent", async () => {
  const f = fixture();
  let view = await reviewedPanel(f);
  assert.equal(view.button("Use reviewed installation in this wizard").props.disabled, true);
  view.control("confirm").props.onChange({ target: { checked: true } });
  view = f.panel();
  view.button("Approve profile command").props.onClick();
  view = f.panel();
  assert.ok(view.nodes.some((node) => node.type === "command-card"));
  view.button("Use reviewed installation in this wizard").props.onClick();
  assert.equal(f.storageWrites.length, 0);
  assert.equal(f.session().status, "saved");
  view.control("adopt").props.onChange({ target: { checked: true } });
  f.panel().button("Use reviewed installation in this wizard").props.onClick();
  f.render();
  assert.equal(f.session().status, "active");
  assert.equal(f.hooks().user[0], "team-user");
});

test("file-review UI activation drives actual retry and command-panel consumers with exact selectors", async () => {
  const f = fixture();
  const saved = [...f.local];
  const view = await reviewedPanel(f);
  view.control("adopt").props.onChange({ target: { checked: true } });
  f.panel().button("Use reviewed installation in this wizard").props.onClick();
  f.render();
  const active = f.session().installation;
  assert.ok(active);
  f.navigate("/wizard/status-check");
  const status = f.statusPage();
  assert.ok(
    status.nodes.some(
      (node) => node.type === "command-card" && node.props.command === active.command,
    ),
  );
  assert.ok(
    status.nodes.some(
      (node) =>
        node.type === "command-card" && node.props.command.includes("team-user@203.0.113.7"),
    ),
  );
  assert.deepEqual(f.commandCalls.at(-1)[3], plain(active.moduleSelection));
  f.navigate("/wizard/launch-onboarding");
  const commands = f.commands();
  assert.ok(commands.nodes.some((node) => node.type === "code" && text(node) === active.command));
  assert.equal(
    commands.nodes.some((node) => node.type === "input" || node.type === "select"),
    false,
  );
  assert.equal(
    commands.nodes.some((node) => node.type === "button" && /Share link/.test(text(node))),
    false,
  );
  await commands.button("Copy Install command").props.onClick();
  assert.equal(f.copies.at(-1), active.command);
  assert.deepEqual([...f.local], saved);
});

test("the reload blocker can review and activate again through raw saved hooks", async () => {
  const f = fixture(new Map([[key, "review-required"]]));
  f.render();
  assert.equal(f.session().status, "review_required");
  assert.equal(f.hasChildren(), false);
  const view = await reviewedPanel(f);
  view.control("adopt").props.onChange({ target: { checked: true } });
  f.panel().button("Use reviewed installation in this wizard").props.onClick();
  f.render();
  assert.equal(f.session().status, "active");
  assert.equal(f.hasChildren(), true);
});

test("clearing a file preview does not silently discard an active installation", async () => {
  const f = fixture();
  let view = await reviewedPanel(f);
  view.control("adopt").props.onChange({ target: { checked: true } });
  f.panel().button("Use reviewed installation in this wizard").props.onClick();
  f.render();
  const active = f.session().installation;
  view = f.panel();
  view.button("Clear imported profile").props.onClick();
  f.panel();
  f.render();
  assert.equal(f.session().installation, active);
  assert.equal(f.sessionEntries.get(key), "review-required");
});

test("a new file or changed declaration clears adoption consent before another activation", async () => {
  const f = fixture();
  let view = await reviewedPanel(f);
  view.control("adopt").props.onChange({ target: { checked: true } });
  view = f.panel();
  view.control("image").props.onChange({ target: { value: "26.04" } });
  f.panel();
  view = await reviewedPanel(f);
  assert.equal(view.control("adopt").props.checked, false);
  view.button("Use reviewed installation in this wizard").props.onClick();
  assert.equal(f.session().status, "saved");
  assert.equal(f.storageWrites.length, 0);
});

test("status retry preserves an ordinary saved minimal profile too", () => {
  const f = fixture();
  f.local.set("agent-flywheel-module-profile", "minimal");
  f.render();
  f.statusPage();
  assert.deepEqual(f.commandCalls.at(-1)[3], { profile: "minimal" });
});

test("status does not build a default retry while exact selections are still loading", () => {
  const f = fixture();
  f.setLoaded(false);
  f.render();
  const before = f.commandCalls.length;
  assert.equal(
    f.statusPage().nodes.some((node) => node.type === "command-card"),
    false,
  );
  assert.equal(f.commandCalls.length, before);
});

test("reviewed command panel retains the matching PowerShell reconnect spelling", async () => {
  const f = await activeFixture();
  f.local.set("agent-flywheel-user-os", "windows");
  f.navigate("/wizard/launch-onboarding");
  const view = f.commands();
  assert.ok(
    view.nodes.some(
      (node) =>
        node.type === "code" &&
        text(node).includes("$HOME\\.ssh\\acfs_ed25519 team-user@203.0.113.7"),
    ),
  );
});

test("cleared and withdrawn adoption callbacks cannot activate through a stale UI closure", async () => {
  for (const cancel of ["clear", "withdraw"]) {
    const f = fixture();
    let view = await reviewedPanel(f);
    view.control("adopt").props.onChange({ target: { checked: true } });
    view = f.panel();
    const stale = view.button("Use reviewed installation in this wizard").props.onClick;
    if (cancel === "clear") view.button("Clear imported profile").props.onClick();
    else view.control("adopt").props.onChange({ target: { checked: false } });
    stale();
    f.render();
    assert.equal(f.session().status, "saved");
    assert.deepEqual(f.storageWrites, []);
  }
});

test("readonly panel refuses a changed generated installer instead of exposing new executable output", async () => {
  const f = await activeFixture();
  f.changeCommand();
  const view = f.commands();
  assert.equal(
    view.nodes.some((node) => node.type === "code"),
    false,
  );
  assert.match(view.text(), /commands are unavailable or changed/);
});

test("all native event subscriptions are removed when the connected session and consumers unmount", async () => {
  const f = await activeFixture();
  f.panel();
  f.statusPage();
  f.commands();
  assert.ok(f.listenerCount() > 10);
  f.unmount();
  assert.equal(f.listenerCount(), 0);
});

test("guided setup is opt-in for one saved profile and reaches the imperative review baseline", () => {
  const f = fixture();
  f.local.set("agent-flywheel-module-profile", "cloud-only");
  f.render();
  let hooks = f.hooks();
  assert.equal(hooks.setup[0], false);
  assert.deepEqual(plain(hooks.selection[0]), { profile: "cloud-only" });
  hooks.setup[1](true);
  hooks = f.hooks();
  assert.equal(hooks.setup[0], true);
  const included = plain(hooks.selection[0]).onlyModules;
  for (const id of ["cloud.wrangler", "cloud.supabase", "cloud.vercel", "acfs.doctor"])
    assert.ok(included.includes(id), id);
  for (const id of ["agents.claude", "stack.ntm", "db.postgres18"])
    assert.ok(!included.includes(id), id);
  assert.deepEqual(plain(f.preferences.getSavedModuleSelection()), plain(hooks.selection[0]));
  assert.deepEqual(plain(f.context().current.moduleSelection), plain(hooks.selection[0]));

  hooks.profile[1]("stack-only");
  hooks = f.hooks();
  assert.equal(hooks.setup[0], false);
  assert.deepEqual(plain(hooks.selection[0]), { profile: "stack-only" });
  hooks.profile[1]("cloud-only");
  hooks = f.hooks();
  assert.equal(hooks.setup[0], true);
  hooks.setup[1](false);
  assert.deepEqual(plain(f.hooks().selection[0]), { profile: "cloud-only" });
  assert.deepEqual(plain(f.preferences.getSavedModuleSelection()), { profile: "cloud-only" });
});

test("saved guided setup cannot rewrite an imported approval or its restoration after discard", async () => {
  const f = fixture();
  f.local.set("agent-flywheel-module-profile", "cloud-only");
  f.render();
  f.hooks().setup[1](true);
  const savedSelection = plain(f.hooks().selection[0]);
  const review = await f.review();
  f.session().activate(review, f.context(), true);
  f.render();
  assert.equal(f.session().status, "active");
  const imported = plain(f.session().installation.moduleSelection);
  assert.deepEqual(plain(f.hooks().selection[0]), imported);
  assert.ok(!imported.onlyModules.includes("acfs.doctor"));
  const stored = new Map(f.local);
  f.hooks().setup[1](true);
  f.render();
  assert.deepEqual(f.local, stored);
  assert.deepEqual(plain(f.hooks().selection[0]), imported);
  f.session().discard();
  f.render();
  assert.deepEqual(plain(f.hooks().selection[0]), savedSelection);
});

test("cached guided setup cannot override a withdrawn canonical opt-in", () => {
  const f = fixture();
  f.local.set("agent-flywheel-module-profile", "cloud-only");
  f.render();
  f.hooks().setup[1](true);
  assert.ok(plain(f.hooks().selection[0]).onlyModules.includes("acfs.doctor"));
  f.local.delete(f.preferences.WIZARD_SETUP_PROFILE_KEY);
  assert.equal(f.hooks().setup[0], false);
  assert.deepEqual(plain(f.hooks().selection[0]), { profile: "cloud-only" });
  assert.deepEqual(plain(f.preferences.getSavedModuleSelection()), { profile: "cloud-only" });
});

test("shared profile reset reaches both hook and imperative selections until explicit opt-in", () => {
  const f = fixture();
  f.local.set("agent-flywheel-module-profile", "cloud-only");
  f.local.set(f.preferences.WIZARD_SETUP_PROFILE_KEY, JSON.stringify("cloud-only"));
  f.window.history.replaceState(null, "", "https://example.invalid/wizard/run-installer?profile=cloud-only&setup=none");
  f.render();
  assert.equal(f.hooks().setup[0], false);
  assert.deepEqual(plain(f.hooks().selection[0]), { profile: "cloud-only" });
  assert.deepEqual(plain(f.preferences.getSavedModuleSelection()), { profile: "cloud-only" });
  assert.equal(f.local.get(f.preferences.WIZARD_SETUP_PROFILE_KEY), JSON.stringify("cloud-only"));

  f.hooks().setup[1](true);
  assert.equal(new URL(f.window.location.href).searchParams.has("setup"), false);
  assert.equal(f.hooks().setup[0], true);
  assert.ok(plain(f.hooks().selection[0]).onlyModules.includes("acfs.doctor"));
  assert.deepEqual(plain(f.preferences.getSavedModuleSelection()), plain(f.hooks().selection[0]));

  f.hooks().setup[1](false);
  assert.equal(new URL(f.window.location.href).searchParams.get("setup"), "none");
  assert.deepEqual(plain(f.hooks().selection[0]), { profile: "cloud-only" });
  assert.deepEqual(plain(f.preferences.getSavedModuleSelection()), { profile: "cloud-only" });
});

test("a blocked History write cannot lift a shared profile reset", () => {
  const f = fixture();
  f.local.set("agent-flywheel-module-profile", "cloud-only");
  f.window.history.replaceState(null, "", "https://example.invalid/wizard/run-installer?profile=cloud-only&setup=none");
  f.window.history.replaceState = () => { throw new Error("history blocked"); };
  f.render();
  f.hooks().setup[1](true);
  assert.equal(f.hooks().setup[0], false);
  assert.deepEqual(plain(f.hooks().selection[0]), { profile: "cloud-only" });
  assert.deepEqual(plain(f.preferences.getSavedModuleSelection()), { profile: "cloud-only" });
});

test("explicit setup withdrawal survives reload when durable preference writes fail", () => {
  const f = fixture();
  f.local.set("agent-flywheel-module-profile", "cloud-only");
  f.local.set(f.preferences.WIZARD_SETUP_PROFILE_KEY, JSON.stringify("cloud-only"));
  f.render();
  assert.equal(f.hooks().setup[0], true);
  f.blockLocalWrites();
  f.hooks().setup[1](false);
  assert.equal(f.hooks().setup[0], false);
  assert.equal(f.local.get(f.preferences.WIZARD_SETUP_PROFILE_KEY), JSON.stringify("cloud-only"));

  const reloaded = fixture();
  for (const [name, value] of f.local) reloaded.local.set(name, value);
  reloaded.window.history.replaceState(null, "", f.window.location.href);
  reloaded.render();
  assert.equal(reloaded.hooks().setup[0], false);
  assert.deepEqual(plain(reloaded.preferences.getSavedModuleSelection()), { profile: "cloud-only" });
});
