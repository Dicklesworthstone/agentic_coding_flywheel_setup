/** Native Web Crypto and DOM-contract tests; no React or remote health claims. */
import { strict as assert } from "node:assert";
import { webcrypto } from "node:crypto";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { test } from "node:test";
import { runInNewContext } from "node:vm";

const require = createRequire(import.meta.url);
const ts = require("typescript");
function fixture(crypto = webcrypto) {
  const module = { exports: {} };
  const output = ts.transpileModule(
    readFileSync(new URL("./installerCheckpoint.ts", import.meta.url), "utf8"),
    {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
      reportDiagnostics: true,
    },
  );
  assert.deepEqual(
    output.diagnostics?.filter((item) => item.category === ts.DiagnosticCategory.Error),
    [],
  );
  runInNewContext(
    output.outputText,
    { module, exports: module.exports, crypto, TextEncoder },
    { timeout: 5000 },
  );
  return module.exports;
}
const input = () => ({
  command: "bash install.sh --only agents.claude",
  doctorCommand: "acfs doctor",
  host: "203.0.113.42",
  manifestSha256: "a".repeat(64),
  checksumsYamlSha256: "b".repeat(64),
});

test("doctor acknowledgement binds both commands and is distinct from installation acknowledgement", async () => {
  const api = fixture();
  const source = input();
  const doctor = await api.createDoctorCheckpoint(source);
  const installer = await api.createInstallerCheckpoint(source);
  assert.match(doctor.persistKey, /^flywheel-doctor-v2-[a-f0-9]{64}$/);
  assert.notEqual(doctor.persistKey, installer.persistKey);
  assert.equal(api.doctorCheckpointMatches(doctor, source), true);
  assert.equal(api.doctorCheckpointMatches(installer, source), false);
  assert.equal(api.installerCheckpointMatches(doctor, source), false);
  assert.equal((await api.createDoctorCheckpoint({ ...source })).persistKey, doctor.persistKey);
  assert.equal(Object.isFrozen(doctor), true);
  assert.ok(!doctor.persistKey.includes(source.host));
  assert.ok(!doctor.persistKey.includes(source.command));
});

for (const field of ["command", "doctorCommand", "host", "manifestSha256", "checksumsYamlSha256"]) {
  test(`changing ${field} requires a new doctor acknowledgement`, async () => {
    const api = fixture();
    const source = input();
    const checkpoint = await api.createDoctorCheckpoint(source);
    source[field] = field.endsWith("Sha256")
      ? "c".repeat(64)
      : field === "host"
        ? "203.0.113.99"
        : `${source[field]} --changed`;
    assert.equal(api.doctorCheckpointMatches(checkpoint, source), false);
    assert.notEqual((await api.createDoctorCheckpoint(source)).persistKey, checkpoint.persistKey);
  });
}

for (const value of ["", " ", null, 1, "a\0b", "x".repeat(65_537)]) {
  test(`refuses malformed doctor command (${typeof value}, ${String(value).length} characters)`, async () => {
    const api = fixture();
    await assert.rejects(api.createDoctorCheckpoint({ ...input(), doctorCommand: value }));
  });
}

test("validates the complete installation context, not only the doctor command", async () => {
  const api = fixture();
  for (const change of [
    { command: "" },
    { host: "" },
    { host: "bad host" },
    { manifestSha256: "bad" },
    { checksumsYamlSha256: "" },
  ]) {
    await assert.rejects(api.createDoctorCheckpoint({ ...input(), ...change }));
  }
  await assert.rejects(api.createDoctorCheckpoint(null));
  assert.equal(api.doctorCheckpointMatches(undefined, input()), false);
  assert.equal(api.doctorCheckpointMatches({}, null), false);
});

test("captures the complete input before either asynchronous digest", async () => {
  let resume;
  const wait = new Promise((done) => {
    resume = done;
  });
  let calls = 0;
  const api = fixture({
    subtle: {
      async digest(...args) {
        calls++;
        await wait;
        return webcrypto.subtle.digest(...args);
      },
    },
  });
  const source = input();
  const original = { ...source };
  const pending = api.createDoctorCheckpoint(source);
  Object.assign(source, { command: "changed", doctorCommand: "other", host: "203.0.113.88" });
  resume();
  const result = await pending;
  assert.equal(calls, 2);
  assert.equal(api.doctorCheckpointMatches(result, original), true);
  assert.equal(api.doctorCheckpointMatches(result, source), false);
  assert.equal(result.persistKey, (await fixture().createDoctorCheckpoint(original)).persistKey);
});

test("unavailable or failed secure hashing cannot invent a shared fallback key", async () => {
  for (const crypto of [
    null,
    {},
    {
      subtle: {
        digest: async () => {
          throw new Error("unavailable");
        },
      },
    },
  ]) {
    await assert.rejects(fixture(crypto).createDoctorCheckpoint(input()));
  }
});

function control(key = `flywheel-doctor-v2-${"a".repeat(64)}`, attributes = {}, extra = {}) {
  const attrs = { "data-acfs-completion-key": key, "data-state": "checked", ...attributes };
  return {
    tagName: "BUTTON",
    getAttribute: (name) => attrs[name] ?? null,
    hasAttribute: (name) => Object.hasOwn(attrs, name),
    closest: () => null,
    ...extra,
  };
}
function root(controls) {
  return { querySelectorAll: () => controls };
}

test("shared navigation requires exactly one currently rendered acknowledged scoped control", () => {
  const api = fixture();
  assert.equal(api.isRenderedCheckpointComplete("doctor", root([control()])), true);
  assert.equal(api.isRenderedCheckpointComplete("doctor", root([])), false);
  assert.equal(api.isRenderedCheckpointComplete("doctor", root([control(), control()])), false);
  assert.equal(api.isRenderedCheckpointComplete("doctor"), false);
  assert.equal(api.isRenderedCheckpointComplete("installer", root([control()])), false);
  assert.equal(
    api.isRenderedCheckpointComplete(
      "installer",
      root([control(`run-flywheel-installer-v2-${"b".repeat(64)}`)]),
    ),
    true,
  );
});

for (const key of [
  "flywheel-doctor",
  "run-flywheel-installer",
  "flywheel-doctor-v2-invalid",
  `flywheel-doctor-v2-${"a".repeat(65)}`,
]) {
  test(`legacy or malformed rendered key is refused (${key.length} characters)`, () => {
    assert.equal(fixture().isRenderedCheckpointComplete("doctor", root([control(key)])), false);
  });
}

for (const state of [
  { "data-state": "unchecked" },
  { "data-state": "indeterminate" },
  { disabled: "" },
  { "data-disabled": "" },
  { "aria-disabled": "true" },
]) {
  test(`refuses unchecked, unhydrated or disabled control ${JSON.stringify(state)}`, () => {
    assert.equal(
      fixture().isRenderedCheckpointComplete("doctor", root([control(undefined, state)])),
      false,
    );
  });
}

test("native checkboxes work; hidden/inert controls and failed DOM reads fail closed", () => {
  const api = fixture();
  const native = control(
    undefined,
    { "data-state": null },
    { tagName: "INPUT", type: "checkbox", checked: true },
  );
  assert.equal(api.isRenderedCheckpointComplete("doctor", root([native])), true);
  native.checked = false;
  assert.equal(api.isRenderedCheckpointComplete("doctor", root([native])), false);
  assert.equal(
    api.isRenderedCheckpointComplete(
      "doctor",
      root([control(undefined, {}, { closest: () => ({ hidden: true }) })]),
    ),
    false,
  );
  assert.equal(
    api.isRenderedCheckpointComplete("doctor", {
      querySelectorAll() {
        throw new Error("unavailable");
      },
    }),
    false,
  );
  assert.equal(api.isRenderedCheckpointComplete("other", root([control()])), false);
});
