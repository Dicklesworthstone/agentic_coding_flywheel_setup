import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, chmodSync, existsSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import test from "node:test";
import {
  buildRehearsalPlan, rehearseProfiles, parseProfileStatus, rehearsalEnvironment,
  runBoundedProbe, formatRehearsal, RehearsalError,
  type ProbeRequest, type ProbeResult, type RehearsalPorts,
} from "./agent-profile-rehearsal.js";

// Retain named fixtures so a failure is inspectable; never invoke a real provider.
const ROOT = mkdtempSync(join(tmpdir(), "acfs-profile-rehearsal-tests-"));
const ok = (text: string, stderr = ""): ProbeResult => ({
  outcome: "ok", exitCode: 0, stdout: Buffer.from(text), stderr: Buffer.from(stderr),
});
const status = (provider = "claude", name = "private@example.com", logged = true, locked = false): string =>
  `Profile: ${provider}/${name}\n  Path: /home/private/${provider}\n  Auth mode: oauth\n  Logged in: ${logged}\n  Locked: ${locked}\n`;
const plan = () => buildRehearsalPlan(["claude:private@example.com"]);
const ENV = { PATH: "/usr/bin:/bin", ANTHROPIC_API_KEY: "sk-private-test", OPENAI_API_KEY: "sk-other-private" };
function harness(fn?: (r: ProbeRequest, count: number) => ProbeResult | Promise<ProbeResult>) {
  const calls: ProbeRequest[] = [];
  const deps: RehearsalPorts = {
    uid: () => 1000, euid: () => 1000, home: () => "/home/test", findCaam: () => "/usr/bin/caam",
    run: async (request) => {
      calls.push(request);
      if (fn) return fn(request, calls.length);
      return request.args[0] === "exec" ? ok("2.1.4 (Claude Code)\n") : ok(status());
    },
  };
  return { calls, deps };
}
function nodeProbe(source: string, timeoutMs = 1000, signal?: AbortSignal): ProbeRequest {
  return { binary: process.execPath, args: ["-e", source], env: { PATH: "/usr/bin:/bin" }, timeoutMs, signal };
}

test("plan-only operation never resolves binaries, homes, identity, or runs commands", async () => {
  const unexpected = () => { throw new Error("unexpected side effect"); };
  const report = await rehearseProfiles(plan(), {}, {
    uid: unexpected, euid: unexpected, home: unexpected, findCaam: unexpected, run: unexpected,
  });
  assert.equal(report.status, "planned");
  assert.equal(report.executed, false);
  assert.equal(report.profiles[0]!.localAuthPresent, null);
  assert.ok(!JSON.stringify(report).includes("private@example.com"));
  assert.ok(!formatRehearsal(report).includes("private@example.com"));
});
test("selection validation bounds providers, names, count, and duplicate identities", () => {
  for (const values of [[], ["claude:"], ["claude:../work"], ["claude:-option"], ["codex:$(touch bad)"],
    ["claude:name\nnext"], ["unknown:work"], ["claude:."], ["claude:.."], ["claude:a".padEnd(140, "x")],
    ["claude:a", "claude:a"], Array.from({ length: 9 }, (_, i) => `claude:a${i}`)]) {
    assert.throws(() => buildRehearsalPlan(values), RehearsalError);
  }
  const result = buildRehearsalPlan(["claude:work+1@example.com", "codex:_safe-name.2"]);
  assert.equal(result.selections.length, 2);
  assert.ok(Object.isFrozen(result) && Object.isFrozen(result.selections[0]));
  assert.throws(() => buildRehearsalPlan(["claude:work"], 0));
  assert.throws(() => buildRehearsalPlan(["claude:work"], 31));
  assert.throws(() => buildRehearsalPlan(["claude:work"], 1.5));
});
test("execution refuses root and mismatched effective UID before the first command", async () => {
  const { deps, calls } = harness();
  for (const identity of [{ uid: () => 0 }, { euid: () => 0 }]) {
    await assert.rejects(rehearseProfiles(plan(), { execute: true, env: ENV }, { ...deps, ...identity }),
      /run_as_target_user_without_sudo/);
  }
  assert.equal(calls.length, 0);
});
test("sudo context is refused without a bypass switch", async () => {
  const { deps, calls } = harness();
  await assert.rejects(rehearseProfiles(plan(), { execute: true, env: { ...ENV, SUDO_USER: "test" } }, deps),
    /run_as_target_user_without_sudo/);
  assert.equal(calls.length, 0);
});
test("profile homes, credentials and runtime hooks are not inherited", () => {
  const original = {
    PATH: ".:relative:/usr/bin::/bin", HOME: "/wrong", CAAM_HOME: "/home/test/.caam",
    XDG_DATA_HOME: "/home/test/.local/share", OPENAI_API_KEY: "secret", ANTHROPIC_AUTH_TOKEN: "secret",
    CLAUDE_CODE_OAUTH_TOKEN: "secret", CODEX_HOME: "/wrong", CLAUDE_CONFIG_DIR: "/wrong",
    GOOGLE_APPLICATION_CREDENTIALS: "/wrong", NODE_OPTIONS: "--require=bad", PYTHONPATH: "/bad",
    BASH_ENV: "/bad", LD_PRELOAD: "/bad", GIT_CONFIG_COUNT: "1", HTTPS_PROXY: "http://private",
  };
  const result = rehearsalEnvironment(original, "/home/test");
  assert.equal(result.HOME, "/home/test");
  assert.equal(result.PATH, "/usr/bin:/bin");
  assert.equal(result.CAAM_HOME, original.CAAM_HOME);
  assert.equal(result.XDG_DATA_HOME, original.XDG_DATA_HOME);
  assert.equal(result.TERM, "dumb");
  for (const key of Object.keys(original)) {
    if (!["PATH", "HOME", "CAAM_HOME", "XDG_DATA_HOME"].includes(key)) assert.equal(result[key], undefined);
  }
  assert.equal(original.CODEX_HOME, "/wrong");
  assert.throws(() => rehearsalEnvironment({ XDG_DATA_HOME: "relative" }, "/home/test"));
  assert.throws(() => rehearsalEnvironment({}, "relative"));
});
test("successful execution uses exact CAAM isolation arguments and a final status check", async () => {
  const { calls, deps } = harness();
  const report = await rehearseProfiles(plan(), { execute: true, env: ENV }, deps);
  assert.equal(report.status, "pass");
  assert.equal(report.profiles[0]!.version, "2.1.4");
  assert.equal(report.profiles[0]!.localAuthPresent, true);
  assert.deepEqual(calls.map((c) => c.args), [
    ["profile", "status", "claude", "private@example.com"],
    ["exec", "claude", "private@example.com", "--", "--version"],
    ["profile", "status", "claude", "private@example.com"],
  ]);
  assert.equal(calls[0]!.env.ANTHROPIC_API_KEY, undefined);
  assert.equal(report.liveAuthenticationVerified, false);
  assert.equal(report.modelPromptSent, false);
  assert.equal(report.globalActivationRequested, false);
});
test("all supported providers run independently with pseudonymous references", async () => {
  const { calls, deps } = harness((r) => r.args[0] === "exec" ? ok("tool 1.2.3\n") :
    ok(status(r.args[2], r.args[3])));
  const report = await rehearseProfiles(buildRehearsalPlan([
    "claude:one", "codex:two", "gemini:three", "agy:four",
  ]), { execute: true, env: ENV }, deps);
  assert.equal(report.status, "pass");
  assert.equal(calls.length, 12);
  assert.deepEqual(report.profiles.map((p) => p.profileRef), ["profile-1", "profile-2", "profile-3", "profile-4"]);
});
test("missing local auth and busy profiles do not start a CLI or unlock anything", async () => {
  for (const [loggedIn, locked, code] of [[false, false, "local_auth_missing"], [true, true, "profile_locked"]] as const) {
    const { calls, deps } = harness(() => ok(status("claude", "private@example.com", loggedIn, locked)));
    const report = await rehearseProfiles(plan(), { execute: true, env: ENV }, deps);
    assert.equal(report.status, "fail");
    assert.equal(report.profiles[0]!.checks[0]!.code, code);
    assert.equal(calls.length, 1);
  }
});
test("missing profile, producer failure and timeout are not reported as unauthenticated success", async () => {
  for (const outcome of ["exit_nonzero", "timeout", "output_limit", "spawn_failed"] as const) {
    const { calls, deps } = harness(() => ({ ...ok(status()), outcome, exitCode: 7 }));
    const report = await rehearseProfiles(plan(), { execute: true, env: ENV }, deps);
    assert.equal(report.status, "fail");
    assert.equal(report.profiles[0]!.localAuthPresent, null);
    assert.equal(calls.length, 1);
  }
});
test("status parser rejects conflicting, spoofed, reordered, noisy and wrong-profile evidence", () => {
  const selected = plan().selections[0]!;
  for (const value of ["", status("codex"), "banner\n" + status(), status().replace("true", "yes"),
    status().replace("  Locked: false", "  Logged in: true\n  Locked: false"),
    status() + "  Description: note\n  Logged in: true\n", status() + "\x1b[2J",
    status().replace("oauth", "unknown"), status().replace("/home/private", "relative")]) {
    assert.equal(parseProfileStatus(ok(value), selected), null, value);
  }
  assert.deepEqual(parseProfileStatus(ok(status().replace(/\n/g, "\r\n")), selected), { loggedIn: true, locked: false });
  const bytes = Buffer.concat([Buffer.from(status()), Buffer.from([0xff])]);
  assert.equal(parseProfileStatus({ ...ok(""), stdout: bytes }, selected), null);
});
test("unrecognized status blocks CLI execution rather than guessing", async () => {
  const { calls, deps } = harness(() => ok("Logged in: true\n"));
  const report = await rehearseProfiles(plan(), { execute: true, env: ENV }, deps);
  assert.equal(report.status, "warn");
  assert.equal(calls.length, 1);
});
test("version command failures stop that profile without retries", async () => {
  const { calls, deps } = harness((_, n) => n === 2 ? { ...ok("2.1.4"), outcome: "exit_nonzero", exitCode: 9 } : ok(status()));
  const report = await rehearseProfiles(plan(), { execute: true, env: ENV }, deps);
  assert.equal(report.status, "fail");
  assert.equal(calls.length, 2);
});
test("exit-zero version with no recognizable version remains a warning", async () => {
  const { calls, deps } = harness((_, n) => ok(n === 2 ? "" : status()));
  const report = await rehearseProfiles(plan(), { execute: true, env: ENV }, deps);
  assert.equal(report.status, "warn");
  assert.equal(report.profiles[0]!.version, null);
  assert.equal(calls.length, 3);
});
test("changed or locked post-execution state is not restored or ignored", async () => {
  const { calls, deps } = harness((_, n) => ok(n === 2 ? "1.2.3" : status("claude", "private@example.com", true, n === 3)));
  const report = await rehearseProfiles(plan(), { execute: true, env: ENV }, deps);
  assert.equal(report.status, "fail");
  assert.equal(report.profiles[0]!.checks[2]!.code, "profile_state_not_confirmed_after_execution");
  assert.equal(calls.length, 3);
});
test("raw stdout/stderr, profile metadata, paths, email and tokens never enter either report format", async () => {
  const secret = "sk-never-record-this-secret";
  const { deps } = harness((_, n) => n === 2 ? ok(`1.2.3\n${secret}\n/home/private 10.0.0.1`, secret) :
    ok(status() + `  Account: ${secret}\n  Description: private@example.com\n`, secret));
  const report = await rehearseProfiles(plan(), { execute: true, env: ENV }, deps);
  for (const output of [JSON.stringify(report), formatRehearsal(report)]) {
    for (const forbidden of [secret, "private@example.com", "/home/private", "10.0.0.1"]) assert.ok(!output.includes(forbidden));
  }
});
test("cancellation preserves a report and prevents every later profile from running", async () => {
  const { calls, deps } = harness(() => ({ ...ok(""), outcome: "cancelled", exitCode: null }));
  const report = await rehearseProfiles(buildRehearsalPlan(["claude:one", "codex:two"]), { execute: true, env: ENV }, deps);
  assert.equal(report.status, "cancelled");
  assert.equal(calls.length, 1);
  assert.equal(report.profiles[1]!.status, "warn");
});
test("an already-aborted rehearsal does not execute a probe", async () => {
  const controller = new AbortController(); controller.abort();
  const { calls, deps } = harness();
  const report = await rehearseProfiles(plan(), { execute: true, env: ENV, signal: controller.signal }, deps);
  assert.equal(report.status, "cancelled");
  assert.equal(calls.length, 0);
});
test("real child runner captures a nonzero exit and both streams without a shell", async () => {
  const result = await runBoundedProbe(nodeProbe(`console.log('stdout'); console.error('stderr'); process.exitCode=7`));
  assert.equal(result.outcome, "exit_nonzero");
  assert.equal(result.exitCode, 7);
  assert.equal(result.stdout.toString(), "stdout\n");
  assert.equal(result.stderr.toString(), "stderr\n");
});
test("real child runner has a neutral cwd and closed stdin", async () => {
  const result = await runBoundedProbe(nodeProbe(`const fs=require('fs'); console.log(process.cwd()); console.log(fs.readFileSync(0).length)`));
  assert.equal(result.outcome, "ok");
  assert.equal(result.stdout.toString(), "/\n0\n");
});
test("real child runner bounds stdout and stderr together", async () => {
  const result = await runBoundedProbe(nodeProbe(`process.stdout.write('a'.repeat(40000)); process.stderr.write('b'.repeat(40000)); setInterval(()=>{},1000)`));
  assert.equal(result.outcome, "output_limit");
  assert.equal(result.stdout.length + result.stderr.length, 0);
});
test("timeout kills children holding inherited pipes even after the direct parent exits", async () => {
  const start = Date.now();
  const result = await runBoundedProbe(nodeProbe(`require('child_process').spawn(process.execPath,['-e','setInterval(()=>{},1000)'],{stdio:['ignore',1,2]}).unref(); process.exit(0)`, 150));
  assert.equal(result.outcome, "timeout");
  assert.ok(Date.now() - start < 2000);
});
test("timeout stops a descendant before it can write its delayed marker", async () => {
  const marker = join(ROOT, "unexpected-child-marker");
  const descendant = `setTimeout(()=>require('fs').writeFileSync(${JSON.stringify(marker)},'bad'),800)`;
  const code = `require('child_process').spawn(process.execPath,['-e',${JSON.stringify(descendant)}],{stdio:['ignore',1,2]});`;
  const result = await runBoundedProbe(nodeProbe(code, 120));
  assert.equal(result.outcome, "timeout");
  await new Promise((done) => setTimeout(done, 900));
  assert.equal(existsSync(marker), false);
});
test("abort signal terminates the active process group", async () => {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 80);
  const result = await runBoundedProbe(nodeProbe("setInterval(()=>{},1000)", 1000, controller.signal));
  clearTimeout(timer);
  assert.equal(result.outcome, "cancelled");
});
test("missing executable is bounded and its raw error is not returned", async () => {
  const result = await runBoundedProbe({ ...nodeProbe(""), binary: "/does/not/exist/private-token" });
  assert.equal(result.outcome, "spawn_failed");
  assert.equal(result.stdout.length + result.stderr.length, 0);
});
test("the CLI plans by default, redacts errors, and rejects root execution", () => {
  const cli = fileURLToPath(new URL("./agent-profile-rehearsal.js", import.meta.url));
  // These CLI tests run against the compiled module under Node as well as Bun's source runner.
  const target = existsSync(cli) ? cli : cli.replace(/\.js$/, ".ts");
  const planned = spawnSync(process.execPath, [target, "--profile", "claude:private@example.com", "--json"], { encoding: "utf8" });
  assert.equal(planned.status, 0, planned.stderr);
  assert.equal(JSON.parse(planned.stdout).executed, false);
  assert.ok(!planned.stdout.includes("private@example.com"));
  const bad = spawnSync(process.execPath, [target, "--bad-private-token", "--json"], { encoding: "utf8" });
  assert.equal(bad.status, 2);
  assert.equal(JSON.parse(bad.stdout).code, "unknown_rehearsal_option");
  assert.ok(!bad.stdout.includes("private-token"));
  if (process.getuid?.() === 0) {
    const result = spawnSync(process.execPath, [target, "--profile", "claude:private@example.com", "--run", "--json"], { encoding: "utf8" });
    assert.equal(result.status, 2);
    assert.equal(JSON.parse(result.stdout).code, "run_as_target_user_without_sudo");
  }
});

test("real CLI runs fixture CAAM as an unprivileged user with isolated argv and scrubbed environment", () => {
  const directory = mkdtempSync(join(ROOT, "cli-"));
  chmodSync(ROOT, 0o755); chmodSync(directory, 0o777);
  const bin = join(directory, "bin"); mkdirSync(bin, { mode: 0o755 });
  const record = join(directory, "calls.jsonl");
  const fake = join(bin, "caam");
  writeFileSync(fake, `#!${process.execPath}\nconst fs=require('fs');
const args=process.argv.slice(2);
fs.appendFileSync(${JSON.stringify(record)}, JSON.stringify({args,uid:process.getuid(),cwd:process.cwd(),credentialInherited:!!process.env.OPENAI_API_KEY})+'\\n');
if(args[0]==='profile') console.log('Profile: '+args[2]+'/'+args[3]+'\\n  Path: /profiles/isolated\\n  Auth mode: oauth\\n  Logged in: true\\n  Locked: false');
else if(JSON.stringify(args.slice(-2))==='["--","--version"]') console.log('fixture 1.2.3');
else process.exitCode=98;
`, { mode: 0o755 });
  const js = fileURLToPath(new URL("./agent-profile-rehearsal.js", import.meta.url));
  const target = existsSync(js) ? js : js.replace(/\.js$/, ".ts");
  const identity = process.getuid?.() === 0 ? { uid: 65534, gid: 65534 } : {};
  const result = spawnSync(process.execPath, [target, "--profile", "claude:private@example.com", "--run", "--json"], {
    encoding: "utf8", timeout: 5000, ...identity,
    env: { PATH: `${bin}:/usr/bin:/bin`, OPENAI_API_KEY: "sk-never-inherit" },
  });
  assert.equal(result.status, 0, result.stderr + result.stdout);
  const report = JSON.parse(result.stdout);
  assert.equal(report.status, "pass");
  assert.equal(report.profiles[0].version, "1.2.3");
  assert.ok(!result.stdout.includes("private@example.com"));
  const calls = readFileSync(record, "utf8").trim().split("\n").map((line) => JSON.parse(line));
  assert.equal(calls.length, 3);
  assert.ok(calls.every((c) => c.uid !== 0 && c.cwd === "/" && !c.credentialInherited));
  assert.deepEqual(calls[1].args, ["exec", "claude", "private@example.com", "--", "--version"]);
});
