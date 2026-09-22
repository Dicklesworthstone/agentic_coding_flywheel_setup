import assert from "node:assert/strict";
import { chmodSync, chownSync, existsSync, linkSync, mkdirSync, mkdtempSync, readFileSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import test from "node:test";
import {
  buildRehearsalPlan, rehearseProfiles, parseNativeAuth, nativeAuthArgs,
  preflightEvidencePath, writeRehearsalEvidence, formatRehearsal,
  type ProbeRequest, type ProbeResult, type RehearsalPorts,
} from "./agent-profile-rehearsal.js";

const ROOT = mkdtempSync(join(tmpdir(), "acfs-native-rehearsal-tests-"));
const response = (stdout: string, stderr = "", exitCode = 0): ProbeResult => ({
  outcome: exitCode === 0 ? "ok" : "exit_nonzero", exitCode,
  stdout: Buffer.from(stdout), stderr: Buffer.from(stderr),
});
const selection = () => buildRehearsalPlan(["claude:private@example.com"]);
function harness(native: ProbeResult, afterLoggedIn = true) {
  const calls: ProbeRequest[] = [];
  const deps: RehearsalPorts = {
    uid: () => 1000, euid: () => 1000, home: () => "/home/test", findCaam: () => "/usr/bin/caam",
    run: async (request) => {
      calls.push(request);
      const args = request.args;
      if (args[0] === "profile") {
        const loggedIn = calls.length === 1 || afterLoggedIn;
        return response(`Profile: ${args[2]}/${args[3]}\n  Path: /private/profile\n  Auth mode: oauth\n  Logged in: ${loggedIn}\n  Locked: false\n`);
      }
      return args.at(-1) === "--version" ? response("1.2.3") : native;
    },
  };
  return { calls, deps };
}
const runOptions = { execute: true, nativeAuth: true, env: { PATH: "/usr/bin:/bin" } };
const js = fileURLToPath(new URL("./agent-profile-rehearsal.js", import.meta.url));
const target = existsSync(js) ? js : js.replace(/\.js$/, ".ts");

test("native command allowlist only uses verified status protocols", () => {
  assert.deepEqual(nativeAuthArgs("claude"), ["auth", "status"]);
  assert.deepEqual(nativeAuthArgs("codex"), ["login", "status"]);
  assert.equal(nativeAuthArgs("gemini"), null);
  assert.equal(nativeAuthArgs("agy"), null);
});
test("Claude parser requires booleans and consistent native exit status", () => {
  assert.equal(parseNativeAuth("claude", response('{"loggedIn":true}')), "present");
  assert.equal(parseNativeAuth("claude", response('{"loggedIn":false}', "", 1)), "missing");
  for (const result of [response('{"loggedIn":"true"}'), response('{"loggedIn":1}'), response('{}'),
    response('[]'), response('null'), response('bad JSON'), response('{"loggedIn":false}'),
    response('{"loggedIn":true}', "", 1), response('{"loggedIn":true}', "", 2),
    response('{"loggedIn":true}\n{"loggedIn":true}')]) {
    assert.equal(parseNativeAuth("claude", result), "unknown");
  }
});
test("Claude parser rejects duplicate keys including escaped and nested duplicates", () => {
  for (const text of [
    '{"loggedIn":false,"loggedIn":true}',
    '{"loggedIn":false,"logged\\u0049n":true}',
    '{"loggedIn":true,"metadata":{"a":1,"a":2}}',
    '{"loggedIn":true,"metadata":[{"a":1,"\\u0061":2}]}',
  ]) assert.equal(parseNativeAuth("claude", response(text)), "unknown", text);
  assert.equal(parseNativeAuth("claude", response('{"loggedIn":true,"a":{"key":1},"b":{"key":2}}')), "present");
  assert.equal(parseNativeAuth("claude", response('{"loggedIn":true,"note":"\\\"loggedIn\\\":false"}')), "present");
  assert.equal(parseNativeAuth("claude", response('{"logged\\u0049n":true}')), "present");
});
test("invalid UTF-8 never becomes recognized authentication evidence", () => {
  const bad = Buffer.from([0xff]);
  assert.equal(parseNativeAuth("claude", { ...response(""), stdout: bad }), "unknown");
  assert.equal(parseNativeAuth("codex", { ...response(""), stderr: bad }), "unknown");
});
test("Codex stderr status supports known modes but never exports masked key fragments", () => {
  for (const mode of ["ChatGPT", "access token", "personal access token", "workload identity",
    "Amazon Bedrock API key", "Amazon Bedrock AWS access keys", "an API key - sk-private...tail"]) {
    assert.equal(parseNativeAuth("codex", response("", `Logged in using ${mode}\n`)), "present");
  }
  assert.equal(parseNativeAuth("codex", response("", "Not logged in\n", 1)), "missing");
  assert.equal(parseNativeAuth("codex", response("Logged in using ChatGPT", "")), "unknown");
  for (const text of ["", "Usage: codex login", "Not logged in", "Logged in using ChatGPT\nNot logged in",
    "Error checking login status: token expired", "Logged in using an unknown method"]) {
    assert.equal(parseNativeAuth("codex", response("", text)), "unknown");
  }
});
test("transport failure is inconclusive even if the private capture contains a success string", () => {
  for (const outcome of ["timeout", "output_limit", "spawn_failed", "cancelled", "signaled"] as const) {
    assert.equal(parseNativeAuth("claude", { ...response('{"loggedIn":true}'), outcome }), "unknown");
  }
});
test("opt-in native status uses the selected isolated profile and rechecks its final state", async () => {
  const { deps, calls } = harness(response('{"loggedIn":true,"email":"private@example.com","orgName":"private-team"}'));
  const report = await rehearseProfiles(selection(), runOptions, deps);
  assert.equal(report.status, "pass");
  assert.equal(report.profiles[0]!.nativeAuth, "present");
  assert.deepEqual(calls[2]!.args, ["exec", "claude", "private@example.com", "--", "auth", "status"]);
  assert.equal(calls[3]!.args[0], "profile");
  assert.equal(report.liveAuthenticationVerified, false);
  for (const text of [JSON.stringify(report), formatRehearsal(report)]) {
    assert.ok(!text.includes("private@example.com"));
    assert.ok(!text.includes("private-team"));
  }
});
test("Codex native check never invokes a login flow or forwards a key", async () => {
  const { deps, calls } = harness(response("", "Logged in using an API key - sk-private...tail\n"));
  const report = await rehearseProfiles(buildRehearsalPlan(["codex:review"]), runOptions, deps);
  assert.equal(report.status, "pass");
  assert.deepEqual(calls[2]!.args, ["exec", "codex", "review", "--", "login", "status"]);
  assert.ok(!JSON.stringify(report).includes("sk-private"));
});
test("native missing credentials override CAAM's optimistic local-file status", async () => {
  const { deps, calls } = harness(response('{"loggedIn":false}', "private diagnostic", 1));
  const report = await rehearseProfiles(selection(), runOptions, deps);
  assert.equal(report.status, "fail");
  assert.equal(report.profiles[0]!.localAuthPresent, true);
  assert.equal(report.profiles[0]!.nativeAuth, "missing");
  assert.equal(calls.length, 4);
  assert.ok(!JSON.stringify(report).includes("private diagnostic"));
});
test("unrecognized native status warns, or fails when required, without an automatic login", async () => {
  for (const requireNativeAuth of [false, true]) {
    const { deps, calls } = harness(response("help text"));
    const report = await rehearseProfiles(selection(), { ...runOptions, requireNativeAuth }, deps);
    assert.equal(report.status, requireNativeAuth ? "fail" : "warn");
    assert.equal(report.profiles[0]!.nativeAuth, "unknown");
    assert.equal(calls.length, 4);
  }
});
test("unsupported native protocols are explicit and required checks cannot pass", async () => {
  for (const requireNativeAuth of [false, true]) {
    const { deps, calls } = harness(response(""));
    const report = await rehearseProfiles(buildRehearsalPlan(["agy:work"]), { ...runOptions, requireNativeAuth }, deps);
    assert.equal(report.status, requireNativeAuth ? "fail" : "pass");
    assert.equal(report.profiles[0]!.nativeAuth, "unsupported");
    assert.equal(calls.length, 3);
    assert.ok(calls.every((c) => c.args[0] === "profile" || c.args.at(-1) === "--version"));
  }
});
test("successful native evidence does not hide a changed final profile state", async () => {
  const { deps } = harness(response('{"loggedIn":true}'), false);
  const report = await rehearseProfiles(selection(), runOptions, deps);
  assert.equal(report.profiles[0]!.nativeAuth, "present");
  assert.equal(report.status, "fail");
});
test("cancelling a native probe does not run the final probe or another profile", async () => {
  const { deps, calls } = harness({ ...response(""), outcome: "cancelled", exitCode: null });
  const report = await rehearseProfiles(selection(), runOptions, deps);
  assert.equal(report.status, "cancelled");
  assert.equal(calls.length, 3);
});
test("native checks still require --run and are disclosed in the plan", async () => {
  const { deps, calls } = harness(response(""));
  const report = await rehearseProfiles(selection(), { nativeAuth: true, requireNativeAuth: true }, deps);
  assert.equal(report.status, "planned");
  assert.equal(report.nativeAuthRequested, true);
  assert.equal(report.nativeAuthRequired, true);
  assert.equal(calls.length, 0);
});
test("evidence export uses a new private file and never changes an existing report", async () => {
  const directory = mkdtempSync(join(ROOT, "private-"));
  const path = join(directory, "evidence.json");
  const report = await rehearseProfiles(selection());
  assert.equal(preflightEvidencePath(path), path);
  writeRehearsalEvidence(path, report);
  assert.equal(statSync(path).mode & 0o777, 0o600);
  const original = readFileSync(path, "utf8");
  assert.deepEqual(JSON.parse(original), report);
  assert.ok(!original.includes("private@example.com"));
  assert.throws(() => writeRehearsalEvidence(path, report), /evidence_already_exists/);
  assert.equal(readFileSync(path, "utf8"), original);
});
test("evidence paths reject symlinks, hard-linked targets and shared writable parents", async () => {
  const directory = mkdtempSync(join(ROOT, "paths-"));
  const source = join(directory, "source.json"); writeFileSync(source, "original");
  symlinkSync(source, join(directory, "symlink.json"));
  linkSync(source, join(directory, "hardlink.json"));
  symlinkSync(join(directory, "missing.json"), join(directory, "broken.json"));
  symlinkSync(directory, join(directory, "alias"));
  for (const path of [join(directory, "symlink.json"), join(directory, "hardlink.json"), join(directory, "broken.json"),
    join(directory, "alias", "report.json"), "bad\nname.json"]) {
    assert.throws(() => preflightEvidencePath(path));
  }
  const shared = join(directory, "shared"); mkdirSync(shared); chmodSync(shared, 0o777);
  assert.throws(() => preflightEvidencePath(join(shared, "new.json")));
  assert.equal(readFileSync(source, "utf8"), "original");
});
test("an output target created after preflight is preserved at publication", async () => {
  const path = join(mkdtempSync(join(ROOT, "race-")), "report.json");
  preflightEvidencePath(path);
  writeFileSync(path, "created concurrently");
  const report = await rehearseProfiles(selection());
  assert.throws(() => writeRehearsalEvidence(path, report), /evidence_already_exists/);
  assert.equal(readFileSync(path, "utf8"), "created concurrently");
});

test("CLI supports private plan export and rejects an existing output before execution", () => {
  const directory = mkdtempSync(join(ROOT, "cli-export-"));
  const output = join(directory, "report.json");
  const result = spawnSync(process.execPath, [target, "--profile", "claude:work", "--native-auth", "--json", "--output", output], { encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr + result.stdout);
  assert.equal(JSON.parse(result.stdout).executed, false);
  assert.equal(JSON.parse(readFileSync(output, "utf8")).nativeAuthRequested, true);
  assert.equal(statSync(output).mode & 0o777, 0o600);
  const again = spawnSync(process.execPath, [target, "--profile", "claude:work", "--run", "--json", "--output", output], { encoding: "utf8" });
  assert.equal(again.status, 2);
  assert.equal(JSON.parse(again.stdout).code, "evidence_already_exists");
});
test("wrapper preserves ordinary audit routing and forwards rehearsal arguments literally", () => {
  const repo = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
  const wrapper = join(repo, "scripts", "agent-readiness-audit.sh");
  assert.ok(existsSync(wrapper), `Missing wrapper fixture: ${wrapper}`);
  const directory = mkdtempSync(join(ROOT, "wrapper-"));
  const bun = join(directory, "bun");
  writeFileSync(bun, `#!${process.execPath}\nconsole.log(JSON.stringify({args:process.argv.slice(2),cwd:process.cwd()}))\n`, { mode: 0o755 });
  const env = { ...process.env, PATH: `${directory}:/usr/bin:/bin`, ACFS_AGENT_READINESS_REPO_ROOT: repo };
  const ordinary = spawnSync("/bin/bash", [wrapper, "--no-version", "--json"], { env, encoding: "utf8" });
  assert.equal(ordinary.status, 0, ordinary.stderr);
  assert.deepEqual(JSON.parse(ordinary.stdout).args, ["run", "src/agent-readiness-audit.ts", "--no-version", "--json"]);
  const rehearsal = spawnSync("/bin/bash", [wrapper, "--rehearse", "--profile", "claude:work+1@example.com", "--native-auth"], { env, encoding: "utf8" });
  assert.equal(rehearsal.status, 0, rehearsal.stderr);
  assert.deepEqual(JSON.parse(rehearsal.stdout).args, ["run", "src/agent-profile-rehearsal.ts", "--profile", "claude:work+1@example.com", "--native-auth"]);
  assert.equal(JSON.parse(rehearsal.stdout).cwd, join(repo, "packages/manifest"));
});

test("native-auth execution and private export work together through the real unprivileged CLI", () => {
  for (const collide of [false, true]) {
    const directory = mkdtempSync(join(ROOT, "native-cli-"));
    chmodSync(ROOT, 0o755);
    const uid = process.getuid?.() ?? -1;
    if (uid === 0) chownSync(directory, 65534, 65534);
    chmodSync(directory, 0o700);
    const bin = join(directory, "bin"); mkdirSync(bin, { mode: 0o755 });
    const output = join(directory, "evidence.json");
    const record = join(directory, "calls.jsonl");
    const fake = join(bin, "caam");
    writeFileSync(fake, `#!${process.execPath}\nconst fs=require('fs'); const args=process.argv.slice(2);
fs.appendFileSync(${JSON.stringify(record)},JSON.stringify(args)+'\\n');
if(${collide} && !fs.existsSync(${JSON.stringify(output)})) fs.writeFileSync(${JSON.stringify(output)},'concurrent evidence');
if(args[0]==='profile') console.log('Profile: '+args[2]+'/'+args[3]+'\\n  Path: /private/profile\\n  Auth mode: oauth\\n  Logged in: true\\n  Locked: false');
else if(args.at(-1)==='--version') console.log('1.2.3');
else if(JSON.stringify(args.slice(-2))==='["auth","status"]') console.log(JSON.stringify({loggedIn:true,email:'private@example.com',orgName:'private-team'}));
else process.exitCode=97;
`, { mode: 0o755 });
    const result = spawnSync(process.execPath, [target, "--profile", "claude:private@example.com", "--require-native-auth", "--run", "--json", "--output", output], {
      encoding: "utf8", timeout: 5000, env: { PATH: `${bin}:/usr/bin:/bin` },
      ...(uid === 0 ? { uid: 65534, gid: 65534 } : {}),
    });
    assert.equal(result.status, collide ? 2 : 0, result.stdout + result.stderr);
    const payload = JSON.parse(result.stdout);
    const report = collide ? payload.report : payload;
    assert.equal(report.status, "pass");
    assert.equal(report.profiles[0].nativeAuth, "present");
    assert.equal(report.nativeAuthRequired, true);
    if (collide) {
      assert.equal(payload.code, "evidence_already_exists");
      assert.equal(readFileSync(output, "utf8"), "concurrent evidence");
    } else {
      assert.deepEqual(JSON.parse(readFileSync(output, "utf8")), report);
      assert.equal(statSync(output).mode & 0o777, 0o600);
    }
    assert.equal(readFileSync(record, "utf8").trim().split("\n").length, 4);
    assert.ok(!result.stdout.includes("private@example.com"));
    assert.ok(!result.stdout.includes("private-team"));
  }
});
test("native auth not reached after a prerequisite failure is not mislabeled as unrequested", async () => {
  const { deps } = harness(response(""));
  deps.run = async () => response("unknown profile", "private diagnostics", 1);
  const report = await rehearseProfiles(selection(), runOptions, deps);
  assert.equal(report.status, "fail");
  assert.equal(report.nativeAuthRequested, true);
  assert.equal(report.profiles[0]!.nativeAuth, "not_checked");
});
