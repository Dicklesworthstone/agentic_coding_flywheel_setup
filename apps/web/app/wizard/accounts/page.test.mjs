/** Actual Accounts page, agent roster, service catalogue and module resolver. */
import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { test } from "node:test";
import { createContext, runInContext } from "node:vm";

const require = createRequire(import.meta.url);
const ts = require("typescript");
const compiled = new Map();
const text = (node) => Array.isArray(node) ? node.map(text).join(" ") :
  node && typeof node === "object" ? text(node.props?.children) :
    typeof node === "string" || typeof node === "number" ? String(node) : "";

function fixture(selection = { profile: "full" }) {
  const scope = createContext({});
  function load(path, dependencies = {}) {
    const source = readFileSync(path, "utf8");
    let entry = compiled.get(path.href);
    if (entry?.source !== source) {
      entry = { source, output: ts.transpileModule(source, {
        fileName: path.pathname,
        reportDiagnostics: true,
        compilerOptions: {
          module: ts.ModuleKind.CommonJS,
          target: ts.ScriptTarget.ES2022,
          jsx: ts.JsxEmit.ReactJSX,
        },
      }) };
      compiled.set(path.href, entry);
    }
    assert.deepEqual(entry.output.diagnostics.filter((item) => item.category === ts.DiagnosticCategory.Error), []);
    const cjs = { exports: {} };
    runInContext(`(function(require,module,exports){${entry.output.outputText}\n})`, scope)(
      (name) => {
        assert.ok(Object.hasOwn(dependencies, name), name);
        return dependencies[name];
      }, cjs, cjs.exports,
    );
    return cjs.exports;
  }
  const parse = runInContext("JSON.parse", scope);
  let selected = parse(JSON.stringify(selection));
  let loaded = true;
  let session = { status: "saved", installation: null };
  const checked = new Set();
  const profileWrites = [];
  const completion = [];
  const analytics = [];
  const routes = [];
  const instances = new Map();
  let owner;
  let cursor;
  let forward;
  const react = {
    useMemo: (fn) => fn(),
    useCallback: (fn) => fn,
    useState(initial) {
      const instance = owner;
      const index = cursor++;
      if (!(index in instance)) instance[index] = typeof initial === "function" ? initial() : initial;
      return [instance[index], (value) => {
        instance[index] = typeof value === "function" ? value(instance[index]) : value;
      }];
    },
  };
  const jsx = (type, props, key) => ({ type, props: props ?? {}, key });
  const catalogue = load(new URL("../../../lib/generated/manifest-modules.ts", import.meta.url));
  const agents = load(new URL("../../../lib/generated/manifest-agents.ts", import.meta.url));
  const index = { ...agents, defaultManifestAgents: agents.manifestAgents.filter((agent) => agent.status === "default") };
  const services = load(new URL("../../../lib/services.ts", import.meta.url), {
    "./generated/manifest-agents": agents,
  });
  const resolver = load(new URL("../../../lib/moduleSelection.ts", import.meta.url), {
    "./generated/manifest-modules": catalogue,
  });
  const usable = () => loaded && ["saved", "active"].includes(session.status);
  const preferences = {
    useCheckedServices: () => [[...checked], (id) => checked.has(id) ? checked.delete(id) : checked.add(id), loaded],
    useModuleProfile: () => [selected.profile ?? "full", (profile) => {
      assert.equal(session.status, "saved", "a reviewed selection cannot be edited");
      profileWrites.push(profile);
      selected = parse(JSON.stringify({ profile }));
    }, usable()],
    useModuleSelection: () => [session.status === "active" ? session.installation.moduleSelection : selected, usable()],
  };
  const common = {
    react,
    "react/jsx-runtime": { jsx, jsxs: jsx, Fragment: "fragment" },
    "next/link": { default: "link" },
    "next/navigation": { useRouter: () => ({ push: (path) => routes.push(path) }) },
    "lucide-react": new Proxy({}, { get: (_target, name) => `icon-${String(name)}` }),
    "@/components/ui/button": { Button: "button" },
    "@/components/ui/checkbox": { Checkbox: "checkbox" },
    "@/components/alert-card": { AlertCard: "alert" },
    "@/components/jargon": { Jargon: "jargon" },
    "@/components/simpler-guide": Object.fromEntries(
      ["GuideExplain", "GuideSection", "GuideStep", "GuideTip", "SimplerGuide"].map((name) => [name, name]),
    ),
    "@/components/tracked-link": { TrackedLink: "tracked-link" },
    "@/lib/generated/manifest-web-index": index,
    "@/lib/generated/manifest-modules": catalogue,
    "@/lib/hooks/useWizardAnalytics": { useWizardAnalytics: () => ({ markComplete: (value) => analytics.push(value) }) },
    "@/lib/services": services,
    "@/lib/moduleSelection": resolver,
    "@/lib/userPreferences": preferences,
    "@/lib/utils": { withCurrentSearch: (path) => path, cn: (...values) => values.filter(Boolean).join(" ") },
    "@/lib/wizardInstallation": { useWizardInstallation: () => session },
    "@/lib/wizardSteps": {
      markStepComplete: (step) => completion.push(step),
      useWizardForwardNav: (value) => { forward = value; return () => {}; },
    },
  };
  const roster = load(new URL("../../../components/agent-roster.tsx", import.meta.url), common);
  const page = load(new URL("./page.tsx", import.meta.url), { ...common, "@/components/agent-roster": roster });
  function render() {
    const nodes = [];
    function visit(node, path) {
      if (Array.isArray(node)) { node.forEach((child, number) => visit(child, `${path}/${child?.key ?? number}`)); return; }
      if (!node || typeof node !== "object") return;
      if (typeof node.type === "function") {
        const previous = owner;
        const previousCursor = cursor;
        owner = instances.get(path) ?? [];
        instances.set(path, owner);
        cursor = 0;
        visit(node.type(node.props), `${path}/render`);
        owner = previous;
        cursor = previousCursor;
      } else {
        nodes.push(node);
        visit(node.props.children, `${path}/children`);
      }
    }
    visit(jsx(page.default, {}), "page");
    return {
      nodes,
      text: () => nodes.map(text).join(" "),
      services: () => nodes.filter((node) => node.type === "checkbox" && node.props.id?.startsWith("service-"))
        .map((node) => node.props.id.slice("service-".length)).sort(),
      profile: () => nodes.find((node) => node.type === "select" && node.props.id === "accounts-profile"),
    };
  }
  function expand() {
    for (const node of render().nodes) {
      if (node.type === "button" && node.props["aria-expanded"] === false) node.props.onClick();
    }
    return render();
  }
  return {
    render, expand, checked, profileWrites, completion, analytics, routes,
    expectedServices: (input = selected) => {
      const plan = resolver.resolveModuleSelection(input);
      const groups = services.getSelectedAuthServices(new Set(plan.included.map((module) => module.id)));
      return Object.values(groups).flat().map((service) => service.id).sort();
    },
    reviewed: (value) => {
      session = { status: "active", installation: {
        displayName: "Reviewed Narrow Stack", moduleSelection: parse(JSON.stringify(value)),
      } };
    },
    unavailable: (status) => { session = { status, installation: null }; },
    setLoaded: (value) => { loaded = value; },
    forward: () => forward,
  };
}

test("cloud-only account setup omits unselected coding subscriptions and sign-in commands", () => {
  const f = fixture({ profile: "cloud-only" });
  const view = f.expand();
  assert.deepEqual(view.services(), ["cloudflare", "supabase", "vercel"]);
  assert.doesNotMatch(view.text(), /Claude Code|Codex CLI|Antigravity CLI|Requires Claude Max|Requires ChatGPT Pro/);
});

test("an approved exact Codex selection drives account guidance without rewriting reviewed selectors", () => {
  const f = fixture();
  f.reviewed({ profile: "full", onlyModules: ["agents.codex"], skipModules: ["acfs.nightly"] });
  const view = f.expand();
  assert.deepEqual(view.services(), ["codex-cli"]);
  assert.match(view.text(), /Reviewed Narrow Stack/);
  assert.match(view.text(), /codex login --device-auth/);
  assert.doesNotMatch(view.text(), /Claude Code|Antigravity CLI/);
  assert.equal(view.profile(), undefined);
  assert.deepEqual(f.profileWrites, []);
});

for (const profile of ["full", "minimal", "agents-only", "cloud-only", "stack-only"]) {
  test(`${profile} signup cards match the services needed by its dependency-complete installation`, () => {
    const f = fixture({ profile });
    assert.deepEqual(f.expand().services(), f.expectedServices());
    assert.equal(f.forward().disabled, false);
  });
}

test("choosing tools before signup changes account guidance while preserving existing signup progress", () => {
  const f = fixture();
  for (const id of ["claude-code", "github", "vercel"]) f.checked.add(id);
  const view = f.expand();
  const profile = view.profile();
  assert.ok(profile, "the user can choose a profile before creating accounts");
  const options = view.nodes.filter((node) => node.type === "option").map((node) => node.props.value);
  assert.deepEqual(options, ["full", "minimal", "agents-only", "cloud-only", "stack-only"]);

  profile.props.onChange({ target: { value: "cloud-only" } });
  const selected = f.expand();
  assert.deepEqual(f.profileWrites, ["cloud-only"]);
  assert.deepEqual(selected.services(), ["cloudflare", "supabase", "vercel"]);
  assert.deepEqual([...f.checked].sort(), ["claude-code", "github", "vercel"]);
  assert.equal(selected.nodes.find((node) => node.props.id === "service-vercel").props.checked, true);

  f.forward().onContinue();
  assert.deepEqual(JSON.parse(JSON.stringify(f.analytics)), [{
    accounts_checked: ["vercel"], accounts_count: 1,
  }]);
  assert.deepEqual(f.completion, [7]);
  assert.deepEqual(f.routes, ["/wizard/preflight-check"]);
});

test("default account guidance uses the canonical subscription options instead of requiring premium tiers", () => {
  const f = fixture();
  const view = f.expand();
  assert.match(view.text(), /Pro works for lighter use/);
  assert.match(view.text(), /Plus also works/);
  assert.doesNotMatch(view.text(), /Requires Claude Max|Requires ChatGPT Pro|Knock out the two essential accounts/);
});

test("a reviewed base-only installation can continue without irrelevant signup or auth commands", () => {
  const f = fixture();
  f.reviewed({ onlyModules: ["base.system"] });
  const view = f.expand();
  assert.deepEqual(view.services(), []);
  assert.ok(view.nodes.some((node) => node.props.title === "No listed accounts needed for this selection"));
  assert.equal(view.nodes.some((node) => node.type === "code"), false);
  assert.equal(view.profile(), undefined);
  assert.equal(f.forward().disabled, false);
  f.forward().onContinue();
  assert.deepEqual(f.completion, [7]);
  assert.deepEqual(f.routes, ["/wizard/preflight-check"]);
  assert.deepEqual(f.profileWrites, []);
});

test("an optional-agent-only selection explains provider accounts instead of claiming none are needed", () => {
  const f = fixture();
  f.reviewed({ onlyModules: ["agents.omp", "agents.opencode"] });
  const view = f.expand();
  assert.deepEqual(view.services(), []);
  assert.ok(view.nodes.some((node) => node.props.title === "Review your selected agents' sign-in options"));
  assert.ok(!view.nodes.some((node) => node.props.title === "No listed accounts needed for this selection"));
  assert.match(view.text(), /omp auth-broker login <provider>/);
  assert.match(view.text(), /opencode auth login/);
  assert.doesNotMatch(view.text(), /Claude Code|Codex CLI|Grok CLI/);
  assert.equal(f.forward().disabled, false, "provider signup remains optional");
});

for (const status of ["loading", "review_required", "unavailable"]) {
  test(`${status} installation context withholds account guidance and continuation`, () => {
    const f = fixture();
    f.unavailable(status);
    const view = f.expand();
    assert.deepEqual(view.services(), []);
    assert.equal(view.nodes.some((node) => node.type === "code" || node.type === "tracked-link"), false);
    assert.equal(f.forward().disabled, true);
    f.forward().onContinue();
    assert.deepEqual(f.routes, []);
    assert.deepEqual(f.completion, []);
    assert.deepEqual(f.analytics, []);
  });
}

test("account guidance waits for preferences before displaying a default installation", () => {
  const f = fixture({ profile: "cloud-only" });
  f.setLoaded(false);
  assert.deepEqual(f.expand().services(), []);
  assert.equal(f.forward().disabled, true);
  f.setLoaded(true);
  assert.deepEqual(f.expand().services(), ["cloudflare", "supabase", "vercel"]);
  assert.equal(f.forward().disabled, false);
});

test("an invalid saved selection shows no signup commands and can recover through profile choice", () => {
  const f = fixture({ onlyModules: ["agents.missing"] });
  const view = f.expand();
  assert.deepEqual(view.services(), []);
  assert.ok(view.nodes.some((node) => node.props.title === "Account guidance unavailable"));
  assert.equal(f.forward().disabled, true);
  f.forward().onContinue();
  assert.deepEqual(f.routes, []);
  assert.deepEqual(f.completion, []);

  view.profile().props.onChange({ target: { value: "minimal" } });
  assert.deepEqual(f.expand().services(), f.expectedServices());
  assert.equal(f.forward().disabled, false);
  assert.deepEqual(f.profileWrites, ["minimal"]);
});
