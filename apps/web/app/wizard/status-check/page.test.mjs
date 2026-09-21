/** Actual page, service catalogue, checkpoint helper and step validator; React/query/resolver/command-builder doubles. */
import { strict as assert } from "node:assert";
import { webcrypto } from "node:crypto";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { createContext, runInContext } from "node:vm";

const require = createRequire(import.meta.url);
const ts = require("typescript");
const text = (node) =>
  Array.isArray(node)
    ? node.map(text).join("")
    : node && typeof node === "object"
      ? text(node.props?.children)
      : typeof node === "string" || typeof node === "number"
        ? String(node)
        : "";
const plain = (value) => JSON.parse(JSON.stringify(value));
function load(path, dependencies, scope) {
  const result = ts.transpileModule(readFileSync(path, "utf8"), {
    fileName: fileURLToPath(path),
    reportDiagnostics: true,
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      jsx: ts.JsxEmit.ReactJSX,
      target: ts.ScriptTarget.ES2022,
    },
  });
  assert.deepEqual(
    result.diagnostics?.filter((entry) => entry.category === ts.DiagnosticCategory.Error),
    [],
  );
  const module = { exports: {} };
  runInContext(`(function(require,module,exports){${result.outputText}\n})`, scope)(
    (name) => {
      assert.ok(Object.hasOwn(dependencies, name), name);
      return dependencies[name];
    },
    module,
    module.exports,
  );
  return module.exports;
}
function fixture() {
  const prefs = {
    host: "203.0.113.42",
    username: "developer",
    mode: "safe",
    ref: "v1.2.3",
    selection: { profile: "full" },
  };
  const loaded = Object.fromEntries(Object.keys(prefs).map((key) => [key, true]));
  const storage = new Map();
  const queries = new Map();
  const queryWrites = [];
  const routes = [];
  const redirects = [];
  const listeners = new Map();
  const progressWrites = [];
  let completedStepCount = 11;
  const commandInputs = [];
  let commandFailure = false;
  let commandSuffix = "";
  let resolverFailure = false;
  const metadata = { manifestSha256: "a".repeat(64), checksumsYamlSha256: "b".repeat(64) };
  let selectionIds = [
    "agents.claude",
    "agents.codex",
    "agents.antigravity",
    "network.tailscale",
    "cli.modern",
    "lang.bun",
    "stack.meta_skill",
    "cloud.wrangler",
    "cloud.supabase",
    "cloud.vercel",
    "shell.omz",
  ];
  let session = null;
  let queryStatus = "success";
  let placeholder;
  let forward;
  let marked = 0;
  let analytics = 0;
  const slots = [];
  let cursor = 0;
  let effects = [];
  let dirty = false;
  let mounted = true;
  let lateUpdates = 0;
  let renderedControls = [];
  const same = (a, b) =>
    a && b && a.length === b.length && a.every((value, index) => Object.is(value, b[index]));
  const jsx = (type, props) => ({ type, props: props ?? {} });
  const react = {
    createContext: (value) => ({ value }),
    useState(initial) {
      const at = cursor++;
      slots[at] ??= { value: typeof initial === "function" ? initial() : initial };
      return [
        slots[at].value,
        (next) => {
          if (!mounted) lateUpdates++;
          const value = typeof next === "function" ? next(slots[at].value) : next;
          if (!Object.is(value, slots[at].value)) dirty = true;
          slots[at].value = value;
        },
      ];
    },
    useMemo(fn, deps) {
      const at = cursor++;
      if (!slots[at] || !same(deps, slots[at].deps)) slots[at] = { deps, value: fn() };
      return slots[at].value;
    },
    useCallback(fn, deps) {
      return react.useMemo(() => fn, deps);
    },
    useRef(value) {
      const at = cursor++;
      slots[at] ??= { current: value };
      return slots[at];
    },
    useEffect(fn, deps) {
      const at = cursor++;
      if (!slots[at] || !same(deps, slots[at].deps)) {
        const old = slots[at]?.cleanup;
        slots[at] = { deps };
        effects.push(() => {
          old?.();
          slots[at].cleanup = fn();
        });
      }
    },
  };
  const scope = createContext({
    crypto: webcrypto,
    TextEncoder,
    TextDecoder,
    structuredClone,
    setTimeout,
    clearTimeout,
    window: {
      addEventListener(name, fn) {
        if (!listeners.has(name)) listeners.set(name, new Set());
        listeners.get(name).add(fn);
      },
      removeEventListener(name, fn) {
        listeners.get(name)?.delete(fn);
      },
    },
    document: {
      querySelectorAll: (selector) =>
        renderedControls.filter((control) => selector.includes(control.kind)),
      getElementById: () => null,
    },
  });
  const checkpoint = load(
    new URL("../../../lib/installerCheckpoint.ts", import.meta.url),
    {},
    scope,
  );
  const catalogue = load(new URL("../../../lib/services.ts", import.meta.url), {}, scope);
  const rawSteps = load(
    new URL("../../../lib/wizardSteps.ts", import.meta.url),
    {
      react,
      "@tanstack/react-query": {},
      "./installerCheckpoint": checkpoint,
      "./utils": {
        safeGetItem: (key) => storage.get(key) ?? null,
        safeGetJSON: () => [],
        safeSetJSON: () => true,
      },
      "./userPreferences": {
        detectOS: () => null,
        getUserOS: () => "linux",
        getVPSIP: () => prefs.host,
        getCreateVPSChecklist: () => [],
        isCreateVPSChecklistComplete: () => true,
        setUserOS: () => {},
      },
    },
    scope,
  );
  const pref = (name) => () => [
    prefs[name],
    () => assert.fail("Health page must not mutate preferences"),
    loaded[name],
  ];
  const queryClient = {
    setQueryData(key, value) {
      queries.set(JSON.stringify(key), value);
      queryWrites.push({ key, value });
    },
  };
  const builder = (mode, ref, user, selection) => {
    commandInputs.push(plain({ mode, ref, user, selection }));
    if (commandFailure) throw new Error("PRIVATE_CONTEXT");
    return `bash install.sh --mode ${mode} --ref ${ref ?? "main"} --user ${user} --selection ${JSON.stringify(selection)}${commandSuffix}`;
  };
  const router = { push: (path) => routes.push(path), replace: (path) => redirects.push(path) };
  const markComplete = () => {
    analytics++;
  };
  const dependencies = {
    react,
    "react/jsx-runtime": { jsx, jsxs: jsx, Fragment: "fragment" },
    "@tanstack/react-query": {
      useQueryClient: () => queryClient,
      useQuery(options) {
        const key = JSON.stringify(options.queryKey);
        if (!queries.has(key) && options.enabled !== false && queryStatus === "success")
          queries.set(key, options.queryFn());
        const data = placeholder !== undefined ? placeholder : queries.get(key);
        return { data, status: queryStatus };
      },
    },
    "next/navigation": { useRouter: () => router },
    "next/link": { default: "link" },
    "lucide-react": Object.fromEntries(
      [
        "AlertCircle",
        "Stethoscope",
        "KeyRound",
        "Shield",
        "Bot",
        "Cloud",
        "Wrench",
        "BookOpen",
        "Laptop",
        "PartyPopper",
        "ExternalLink",
        "Sparkles",
        "ArrowRight",
        "GraduationCap",
        "Terminal",
        "RefreshCw",
        "FolderPlus",
        "FolderOpen",
      ].map((id) => [id, `icon-${id}`]),
    ),
    "@/components/ui/button": { Button: "button" },
    "@/components/ui/card": { Card: "card" },
    "@/components/command-builder-panel": { CommandBuilderPanel: "command-panel" },
    "@/components/command-card": {
      CommandCard: "command-card",
      CodeBlock: "code-block",
      commandCompletionKeys: { completion: (key) => ["commandCompletion", key] },
      COMMAND_COMPLETION_CHANGED_EVENT: "acfs:command-completion-changed",
    },
    "@/components/alert-card": { AlertCard: "alert", OutputPreview: "output-preview" },
    "@/components/connection-check": { WhereAmICheck: "where-am-i" },
    "@/components/simpler-guide": Object.fromEntries(
      ["SimplerGuide", "GuideSection", "GuideStep", "GuideExplain", "GuideTip", "GuideCaution"].map(
        (id) => [id, id],
      ),
    ),
    "@/components/jargon": { Jargon: "jargon" },
    "@/lib/services": catalogue,
    "@/lib/installerCheckpoint": checkpoint,
    "@/lib/generated/manifest-modules": { manifestProvenance: metadata },
    "@/lib/wizardInstallation": { useWizardInstallation: () => session },
    "@/lib/wizardSteps": {
      ...rawSteps,
      getCompletedSteps: () => Array.from({ length: completedStepCount }, (_, i) => i + 1),
      markStepComplete: (step) => {
        marked++;
        completedStepCount = Math.max(completedStepCount, step);
      },
      setCompletedSteps: (steps) => {
        progressWrites.push(plain(steps));
        completedStepCount = Math.max(...steps);
      },
      useWizardForwardNav: (action) => {
        forward = action;
        return () => {};
      },
    },
    "@/lib/hooks/useWizardAnalytics": { useWizardAnalytics: () => ({ markComplete }) },
    "@/lib/analytics": { trackConversion: () => {} },
    "@/lib/lessons": { TOTAL_LESSONS: 1 },
    "@/lib/userPreferences": {
      useVPSIP: pref("host"),
      useSSHUsername: pref("username"),
      useInstallMode: pref("mode"),
      useACFSRef: pref("ref"),
      useModuleSelection: () => [prefs.selection, loaded.selection],
    },
    "@/lib/utils": {
      safeGetItem: (key) => storage.get(key) ?? null,
      withCurrentSearch: (path) => path,
    },
    "@/lib/inputValidation": {
      isValidIP: (value) => /^203\.0\.113\.\d+$/.test(value),
      normalizeSSHUsername: (value) =>
        /^[a-z][a-z0-9_-]+$/.test(value) && value !== "root" ? value : null,
      normalizeGitRef: (value) =>
        typeof value === "string" && /^[a-zA-Z0-9_./-]+$/.test(value) ? value : null,
    },
    "@/lib/moduleSelection": {
      resolveModuleSelection(selection) {
        const ok = !resolverFailure;
        return {
          ok,
          included: ok ? selectionIds.map((id) => ({ id })) : [],
          errors: ok ? [] : ["invalid selection"],
          warnings: selection.noDeps ? ["Dependency closure is disabled."] : [],
          selectedCount: ok ? selectionIds.length : 0,
        };
      },
    },
    "@/lib/commandBuilder": {
      buildInstallCommand: builder,
      formatSshTarget: (user, host) => `${user}@${host}`,
    },
  };
  dependencies["@/lib/hooks/useInstallationHealth"] = load(
    new URL("../../../lib/hooks/useInstallationHealth.ts", import.meta.url),
    dependencies,
    scope,
  );
  let page = load(new URL("./page.tsx", import.meta.url), dependencies, scope);
  function render() {
    let nodes;
    for (let attempts = 0; attempts < 10; attempts++) {
      cursor = 0;
      dirty = false;
      effects = [];
      nodes = [];
      const visit = (node) => {
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
      };
      visit(page.default());
      renderedControls = nodes
        .filter((node) => node.type === "command-card" && node.props.showCheckbox)
        .filter((node) => node.props.persistKey?.startsWith("flywheel-doctor-v2-"))
        .map((node) => ({
          kind: "flywheel-doctor-v2-",
          tagName: "BUTTON",
          getAttribute(name) {
            if (name === "data-acfs-completion-key") return node.props.persistKey;
            if (name === "data-state")
              return queries.get(
                JSON.stringify(["commandCompletion", `acfs-command-${node.props.persistKey}`]),
              ) === true
                ? "checked"
                : "unchecked";
            return null;
          },
          hasAttribute: (name) => name === "disabled" && queryStatus !== "success",
          closest: () => null,
        }));
      effects.forEach((effect) => effect());
      if (!dirty) break;
      assert.ok(attempts < 9, "effects must converge");
    }
    const cards = nodes.filter((node) => node.type === "command-card");
    return {
      nodes,
      cards,
      doctor: () => cards.find((node) => node.props.command === "acfs doctor"),
      retry: () => cards.find((node) => node.props.command?.startsWith("bash install.sh")),
      continue: () =>
        nodes.find((node) => node.type === "button" && node.props["data-wizard-primary-cta"]),
      text: () => nodes.map(text).join(" "),
      error: () =>
        nodes
          .filter(
            (node) =>
              node.props.role === "alert" ||
              (node.type === "alert" && node.props.variant === "error"),
          )
          .map((node) => (node.props.title ?? "") + text(node))
          .join(" "),
    };
  }
  async function settle() {
    for (let i = 0; i < 100; i++) {
      await new Promise((done) => setTimeout(done, 1));
      const view = render();
      if (
        view.doctor()?.props.showCheckbox ||
        /hashing failed/.test(view.error()) ||
        !view.doctor()
      )
        return view;
    }
    assert.fail("checkpoint did not settle");
  }
  function acknowledge(value = true) {
    const card = render().doctor();
    assert.ok(card?.props.persistKey);
    const key = `acfs-command-${card.props.persistKey}`;
    storage.set(key, String(value));
    queries.set(JSON.stringify(["commandCompletion", key]), value);
    return render();
  }
  return {
    prefs,
    loaded,
    render,
    settle,
    acknowledge,
    storage,
    queries,
    queryWrites,
    scope,
    metadata,
    checkpoint,
    catalogue,
    rawSteps,
    routes,
    redirects,
    listeners,
    progressWrites,
    commandInputs,
    forward: () => forward,
    marked: () => marked,
    analytics: () => analytics,
    progress: (count) => {
      completedStepCount = count;
    },
    dispatch: (event) => {
      for (const fn of listeners.get(event.type) ?? []) fn(event);
    },
    navigateToOnboarding() {
      for (const slot of slots) slot?.cleanup?.();
      slots.length = 0;
      renderedControls = [];
      page = load(new URL("../launch-onboarding/page.tsx", import.meta.url), dependencies, scope);
      return render();
    },
    select(ids) {
      selectionIds = ids;
      prefs.selection = { ...prefs.selection };
    },
    session(value) {
      session = value;
    },
    failPlan() {
      resolverFailure = true;
    },
    failBuilder() {
      commandFailure = true;
    },
    changeCommand() {
      commandSuffix = " --changed";
      prefs.selection = { ...prefs.selection };
    },
    queryStatus(value) {
      queryStatus = value;
    },
    placeholder(value) {
      placeholder = value;
    },
    unmount() {
      mounted = false;
      for (const slot of slots) slot?.cleanup?.();
    },
    lateUpdates: () => lateUpdates,
  };
}

test("doctor requires a context-bound acknowledgement and a currently rendered checked control", async () => {
  const f = fixture();
  const pending = f.render();
  assert.equal(pending.doctor().props.showCheckbox, false);
  assert.equal(pending.continue().props.disabled, true);
  const view = await f.settle();
  assert.match(view.doctor().props.persistKey, /^flywheel-doctor-v2-[a-f0-9]{64}$/);
  assert.equal(view.doctor().props.checkboxId, "flywheel-doctor");
  assert.equal(f.rawSteps.validateStep(12).valid, false);
  view.continue().props.onClick();
  assert.equal(f.routes.length, 0);
  f.acknowledge().continue().props.onClick();
  assert.equal(f.marked(), 1);
  assert.equal(f.analytics(), 1);
  assert.deepEqual(f.routes, ["/wizard/launch-onboarding"]);
});

test("old global doctor/installer acknowledgements cannot unlock navigation", async () => {
  const f = fixture();
  f.storage.set("acfs-command-flywheel-doctor", "true");
  f.storage.set("acfs-command-run-flywheel-installer", "true");
  f.render();
  const view = await f.settle();
  assert.equal(view.continue().props.disabled, true);
  assert.equal(f.rawSteps.validateStep(12).valid, false);
  assert.equal(f.rawSteps.validateStep(9).valid, false);
  view.continue().props.onClick();
  assert.equal(f.marked(), 0);
});

for (const field of [
  "host",
  "username",
  "mode",
  "ref",
  "selection",
  "manifestSha256",
  "checksumsYamlSha256",
]) {
  test(`changing ${field} blocks the old acknowledgement and stale forward handler`, async () => {
    const f = fixture();
    f.render();
    await f.settle();
    const old = f.acknowledge();
    const callback = old.continue().props.onClick;
    const oldKey = old.doctor().props.persistKey;
    if (field === "host") f.prefs.host = "203.0.113.88";
    if (field === "username") f.prefs.username = "another-user";
    if (field === "mode") f.prefs.mode = "vibe";
    if (field === "ref") f.prefs.ref = "other-ref";
    if (field === "selection") f.prefs.selection = { onlyModules: ["agents.claude"] };
    if (field.endsWith("Sha256")) f.metadata[field] = "c".repeat(64);
    let view = f.render();
    assert.equal(view.continue().props.disabled, true);
    callback();
    assert.equal(f.routes.length, 0);
    view = await f.settle();
    assert.notEqual(view.doctor().props.persistKey, oldKey);
    assert.equal(view.continue().props.disabled, true);
    f.acknowledge().continue().props.onClick();
    assert.equal(f.routes.length, 1);
  });
}

test("withdrawing acknowledgement invalidates an earlier forward callback", async () => {
  const f = fixture();
  f.render();
  await f.settle();
  const callback = f.acknowledge().continue().props.onClick;
  f.acknowledge(false);
  callback();
  assert.equal(f.marked(), 0);
  assert.equal(f.routes.length, 0);
});

for (const field of ["host", "username", "mode", "ref", "selection"]) {
  test(`waits for ${field} hydration before building commands or acknowledging`, () => {
    const f = fixture();
    f.loaded[field] = false;
    const view = f.render();
    assert.equal(view.cards.length, 0);
    assert.equal(f.commandInputs.length, 0);
    f.forward().onContinue();
    assert.equal(f.routes.length, 0);
  });
}

for (const change of [
  { host: "unreviewed-host" },
  { username: "root" },
  { username: " padded" },
  { ref: "bad;ref" },
  { mode: "other" },
]) {
  test(`invalid context suppresses commands without fallback ${JSON.stringify(change)}`, () => {
    const f = fixture();
    Object.assign(f.prefs, change);
    const view = f.render();
    assert.match(view.error(), /Status check blocked/);
    assert.equal(view.cards.length, 0);
    f.forward().onContinue();
    assert.equal(f.routes.length, 0);
  });
}

for (const failure of ["plan", "builder"]) {
  test(`${failure} refusal cannot throw during rendering or expose default commands`, () => {
    const f = fixture();
    failure === "plan" ? f.failPlan() : f.failBuilder();
    const view = f.render();
    assert.match(view.error(), /Status check blocked/);
    assert.equal(view.cards.length, 0);
    assert.doesNotMatch(view.error(), /PRIVATE_CONTEXT/);
    f.forward().onContinue();
    assert.equal(f.routes.length, 0);
  });
}

test("adopted installation must reproduce the exact approved retry command", async () => {
  const f = fixture();
  f.prefs.selection = { onlyModules: ["agents.claude"], skipModules: ["acfs.nightly"] };
  f.select(["agents.claude"]);
  const original = f.render().retry().props.command;
  f.session({ status: "active", installation: { command: original } });
  let view = f.render();
  await f.settle();
  assert.equal(view.retry().props.command, original);
  assert.deepEqual(f.commandInputs.at(-1).selection, f.prefs.selection);
  f.changeCommand();
  view = f.render();
  assert.equal(view.cards.length, 0);
  assert.match(view.error(), /blocked/);
});

for (const status of ["loading", "review_required", "unavailable"]) {
  test(`guarded installation session ${status} exposes no saved/default commands`, () => {
    const f = fixture();
    f.session({ status, installation: null });
    const view = f.render();
    assert.equal(view.cards.length, 0);
    assert.equal(f.commandInputs.length, 0);
  });
}

test("a claimed active session without its approved installation is blocked", () => {
  const f = fixture();
  f.session({ status: "active", installation: null });
  assert.equal(f.render().cards.length, 0);
});

test("hash failure leaves the manual doctor command but never a fallback completion control", async () => {
  const f = fixture();
  f.scope.crypto = null;
  f.render();
  const view = await f.settle();
  assert.match(view.error(), /hashing failed/);
  assert.equal(view.doctor().props.showCheckbox, false);
  assert.equal(view.continue().props.disabled, true);
  view.continue().props.onClick();
  assert.equal(f.routes.length, 0);
});

test("a late hash from the previous host cannot replace the current checkpoint", async () => {
  const f = fixture();
  let resume;
  const wait = new Promise((done) => {
    resume = done;
  });
  let first = true;
  f.scope.crypto = {
    subtle: {
      async digest(...args) {
        if (first) {
          first = false;
          await wait;
        }
        return webcrypto.subtle.digest(...args);
      },
    },
  };
  f.render();
  f.prefs.host = "203.0.113.88";
  f.render();
  const current = await f.settle();
  const key = current.doctor().props.persistKey;
  resume();
  await new Promise((done) => setTimeout(done, 10));
  assert.equal(f.render().doctor().props.persistKey, key);
  assert.equal(f.render().continue().props.disabled, true);
});

test("unmounting abandons in-flight hashes and stale navigation callbacks", async () => {
  const f = fixture();
  let resume;
  const wait = new Promise((done) => {
    resume = done;
  });
  f.scope.crypto = {
    subtle: {
      async digest(...args) {
        await wait;
        return webcrypto.subtle.digest(...args);
      },
    },
  };
  f.render();
  const callback = f.forward().onContinue;
  f.unmount();
  resume();
  await new Promise((done) => setTimeout(done, 10));
  callback();
  assert.equal(f.lateUpdates(), 0);
  assert.equal(f.routes.length, 0);
});

for (const status of ["pending", "error"]) {
  test(`cached true data does not bypass ${status} completion hydration`, async () => {
    const f = fixture();
    f.render();
    await f.settle();
    f.acknowledge();
    f.queryStatus(status);
    const view = f.render();
    assert.equal(view.continue().props.disabled, true);
    f.forward().onContinue();
    assert.equal(f.routes.length, 0);
  });
}

test("nonboolean completion data is not acknowledgement", async () => {
  const f = fixture();
  f.render();
  await f.settle();
  f.placeholder("true");
  const view = f.render();
  assert.equal(view.continue().props.disabled, true);
  view.continue().props.onClick();
  assert.equal(f.routes.length, 0);
});

test("narrow agent selection omits unselected cloud agents and spot checks across the whole guide", async () => {
  const f = fixture();
  f.prefs.selection = { onlyModules: ["agents.claude"] };
  f.select(["agents.claude"]);
  f.render();
  const view = await f.settle();
  const commands = view.cards.map((card) => card.props.command);
  assert.ok(commands.includes("claude --version"));
  assert.ok(commands.includes("claude"));
  for (const forbidden of [
    "bun --version",
    "ms --version",
    "which tmux",
    "codex login --device-auth",
    "agy",
    "vercel login",
    "sudo tailscale up",
    "source ~/.zshrc",
  ]) {
    assert.ok(!commands.includes(forbidden), forbidden);
  }
  assert.doesNotMatch(
    view.text(),
    /Wrangler: Headless|Codex CLI: Special|SUPABASE_ACCESS_TOKEN|GEMINI_API_KEY/,
  );
});

for (const serviceId of [
  "tailscale",
  "claude-code",
  "codex-cli",
  "antigravity-cli",
  "github",
  "vercel",
  "supabase",
  "cloudflare",
]) {
  test(`service authentication follows exact module membership: ${serviceId}`, async () => {
    const f = fixture();
    const service = f.catalogue.SERVICES.find((entry) => entry.id === serviceId);
    f.select([service.moduleId]);
    f.render();
    const view = await f.settle();
    const auth = view.cards.filter((card) => card.props.persistKey?.startsWith("auth-"));
    assert.equal(auth.length, 1);
    assert.equal(auth[0].props.command, service.postInstallCommand);
    assert.ok(auth[0].props.persistKey.includes(view.doctor().props.persistKey));
    assert.equal(
      f.rawSteps.validateStep(12).valid,
      false,
      "auth notes never unlock the doctor gate",
    );
  });
}

test("empty/no-login selections do not invent a full set of services or quick checks", async () => {
  const f = fixture();
  f.select([]);
  f.render();
  const view = await f.settle();
  assert.equal(view.cards.filter((card) => card.props.persistKey?.startsWith("auth-")).length, 0);
  assert.match(view.text(), /No service sign-ins/);
  assert.doesNotMatch(view.text(), /cc --version|bun --version|ms --version|which tmux/);
});

test("all 256 service module combinations preserve exact membership without mutating the catalogue", () => {
  const f = fixture();
  const original = JSON.stringify(f.catalogue.SERVICES);
  const services = f.catalogue.SERVICES;
  for (let mask = 0; mask < 256; mask++) {
    const selected = services.filter((_, index) => mask & (1 << index));
    const groups = f.catalogue.getSelectedAuthServices(
      new Set(selected.map((service) => service.moduleId)),
    );
    const actual = Object.values(groups).flat();
    assert.deepEqual(
      plain(actual.map((service) => service.id).sort()),
      plain(selected.map((service) => service.id).sort()),
    );
    for (const [category, entries] of Object.entries(groups))
      assert.ok(entries.every((entry) => entry.category === category));
  }
  assert.equal(JSON.stringify(services), original);
});

async function finishNavigation(f) {
  for (let i = 0; i < 100; i++) {
    await new Promise((done) => setTimeout(done, 1));
    const view = f.render();
    if (view.cards.length || f.redirects.length) return view;
  }
  assert.fail("navigation checkpoint did not settle");
}

test("status-to-onboarding transition revalidates the same key after the doctor card unmounts", async () => {
  const f = fixture();
  f.render();
  await f.settle();
  const original = f.acknowledge().doctor().props.persistKey;
  f.render().continue().props.onClick();
  assert.equal(f.routes.at(-1), "/wizard/launch-onboarding");
  const pending = f.navigateToOnboarding();
  assert.equal(pending.cards.length, 0);
  assert.equal(
    f.rawSteps.validateStep(12).valid,
    false,
    "the old DOM control is intentionally gone",
  );
  const view = await finishNavigation(f);
  assert.ok(view.cards.length > 0, "completed navigation must not bounce forever to Status Check");
  assert.equal(f.redirects.length, 0);
  assert.equal(f.marked(), 2);
  assert.deepEqual(
    f.progressWrites.at(-1),
    Array.from({ length: 13 }, (_, i) => i + 1),
  );
  assert.equal(f.storage.get(`acfs-command-${original}`), "true");
});

test("a bookmark and globally completed steps cannot forge current installation health", async () => {
  const f = fixture();
  f.progress(13);
  f.storage.set("acfs-command-flywheel-doctor", "true");
  f.navigateToOnboarding();
  const view = await finishNavigation(f);
  assert.equal(view.cards.length, 0);
  assert.equal(f.redirects.at(-1), "/wizard/status-check");
  assert.equal(f.marked(), 0);
  assert.equal(f.progressWrites.length, 0);
});

test("changed target on onboarding removes unlocked content before the new hash resolves", async () => {
  const f = fixture();
  f.render();
  await f.settle();
  f.acknowledge().continue().props.onClick();
  f.navigateToOnboarding();
  await finishNavigation(f);
  const previous = f.marked();
  f.prefs.host = "203.0.113.89";
  assert.equal(f.render().cards.length, 0);
  await finishNavigation(f);
  assert.equal(f.redirects.at(-1), "/wizard/status-check");
  assert.equal(f.marked(), previous);
});

for (const type of ["storage", "same-tab"]) {
  test(`${type} revocation remains live after leaving the acknowledging card`, async () => {
    const f = fixture();
    f.render();
    await f.settle();
    const card = f.acknowledge().doctor();
    f.render().continue().props.onClick();
    f.navigateToOnboarding();
    await finishNavigation(f);
    if (type === "storage") {
      f.storage.clear();
      f.dispatch({ type: "storage", key: null, newValue: null });
    } else
      f.dispatch({
        type: "acfs:command-completion-changed",
        detail: { key: `acfs-command-${card.props.persistKey}`, completed: false },
      });
    assert.equal(f.render().cards.length, 0);
    assert.equal(f.redirects.at(-1), "/wizard/status-check");
  });
}

test("health synchronization listeners are removed on unmount", async () => {
  const f = fixture();
  f.render();
  await f.settle();
  assert.equal(f.listeners.get("storage").size, 1);
  f.unmount();
  assert.equal(f.listeners.get("storage").size, 0);
  assert.equal(f.listeners.get("acfs:command-completion-changed").size, 0);
});

test("no raw command or host is stored in health query keys or acknowledgement storage", async () => {
  const f = fixture();
  f.render();
  await f.settle();
  f.acknowledge();
  const keys = [...f.queries.keys(), ...f.storage.keys()].join("\n");
  assert.ok(!keys.includes(f.prefs.host));
  assert.ok(!keys.includes("bash install.sh"));
  assert.deepEqual([...f.storage.values()], ["true"]);
});
