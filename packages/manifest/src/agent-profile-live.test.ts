import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, chownSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import {
  buildRehearsalPlan, buildLiveModelPlan, liveModelArgs, liveModelResponseMatches,
  rehearseProfiles, formatRehearsal, runBoundedProbe,
  type ProbeRequest, type ProbeResult, type RehearsalPorts,
} from "./agent-profile-rehearsal.js";

// Named fixtures are retained. No test invokes an installed provider or sends a request.
const ROOT = mkdtempSync(join(tmpdir(), "acfs-live-tests-"));
const TOKEN = "ACFS_LIVE_" + "ab".repeat(16);
const ENV = { PATH: "/usr/bin:/bin", OPENAI_API_KEY: "sk-never-inherit", NODE_OPTIONS: "--require=secret" };
const plan = () => buildRehearsalPlan(["claude:private@example.com"]);
const live = { execute: true, liveModels: ["claude:sonnet"], env: ENV };
const ok = (text: string): ProbeResult => ({ outcome: "ok", exitCode: 0, stdout: Buffer.from(text), stderr: Buffer.alloc(0) });
const status = (provider: string, name: string) =>
  `Profile: ${provider}/${name}\n  Path: /private/profile\n  Auth mode: oauth\n  Logged in: true\n  Locked: false\n`;
const response = (challenge: string) => ({
  type: "result", subtype: "success", is_error: false, num_turns: 1,
  result: challenge, permission_denials: [],
});
const isLive = (request: ProbeRequest) => request.args.includes("--print") || request.args.includes("--ephemeral");
const codexEvents = (challenge: string): Record<string, unknown>[] => [
  { type: "thread.started", thread_id: "0199a213-81c0-7800-8aa1-bbab2a035a53" },
  { type: "turn.started" },
  { type: "item.completed", item: { id: "item_0", type: "reasoning", text: "Return the token." } },
  { type: "item.completed", item: { id: "item_1", type: "agent_message", text: challenge } },
  { type: "turn.completed", usage: { input_tokens: 120, cached_input_tokens: 0, output_tokens: 24, reasoning_output_tokens: 0 } },
];
const jsonl = (events: Record<string, unknown>[]) => events.map((e) => JSON.stringify(e)).join("\n") + "\n";
function harness(change?: (request: ProbeRequest, normal: ProbeResult, index: number) => ProbeResult | Promise<ProbeResult>) {
  const calls: ProbeRequest[] = [];
  const deps: RehearsalPorts = {
    uid: () => 1000, euid: () => 1000, home: () => "/home/private",
    findCaam: () => "/usr/bin/caam",
    run: async (request) => {
      calls.push(request);
      const normal = request.args[0] === "profile" ? ok(status(request.args[2]!, request.args[3]!)) :
        isLive(request) ? ok(request.args[1] === "codex" ? jsonl(codexEvents(request.args.at(-1)!)) : JSON.stringify(response(request.args.at(-1)!))) :
        request.args.includes("--version") ? ok("CLI 2.1.300\n") :
        request.args.includes("login") ? { ...ok(""), stderr: Buffer.from("Logged in using ChatGPT\n") } : ok('{"loggedIn":true}');
      return change ? change(request, normal, calls.length) : normal;
    },
  };
  return { calls, deps };
}
const js = fileURLToPath(new URL("./agent-profile-rehearsal.js", import.meta.url));
const cli = existsSync(js) ? js : js.replace(/\.js$/, ".ts");

test("live plan remains side-effect free and explicitly identifies spending and requested model", async () => {
  const forbidden = () => { throw Error("side effect"); };
  const report = await rehearseProfiles(plan(), { liveModels: ["claude:sonnet"] }, {
    uid: forbidden, euid: forbidden, home: forbidden, findCaam: forbidden, run: forbidden,
  });
  assert.equal(report.status, "planned");
  assert.equal(report.executed, false);
  assert.equal(report.modelPromptSent, false);
  assert.equal(report.liveModelPolicy?.mayIncurCharges, true);
  assert.equal(report.liveModelPolicy?.responseVerified, false);
  assert.equal(report.profiles[0]!.liveModel?.requestedModel, "sonnet");
  assert.equal(report.profiles[0]!.liveModel?.attempts, 0);
  assert.match(formatRehearsal(report), /may consume quota or incur charges/);
  assert.ok(!JSON.stringify(report).includes("private@example.com"));
});

test("model validation rejects ambiguous selection, unselected providers, invalid models and deadlines", () => {
  for (const selectors of [["claude:"], ["codex:gpt-5"], ["agy:gemini"], ["claude:--flag"],
    ["claude:a b"], ["claude:$(touch bad)"], ["claude:model\n"],
    ["claude:sonnet", "claude:opus"], ["claude:" + "x".repeat(129)]]) {
    assert.throws(() => buildLiveModelPlan(plan(), selectors));
  }
  assert.throws(() => buildLiveModelPlan(buildRehearsalPlan(["codex:work"]), ["claude:sonnet"]));
  assert.throws(() => buildLiveModelPlan(buildRehearsalPlan(["claude:work", "codex:work"]), ["claude:sonnet"]));
  for (const timeout of [0, 121, -1, 0.5, NaN, Infinity]) assert.throws(() => buildLiveModelPlan(plan(), ["claude:sonnet"], timeout));
  assert.throws(() => buildLiveModelPlan(plan(), [], 10));
  assert.equal(buildLiveModelPlan(plan()), undefined);
  const built = buildLiveModelPlan(plan(), ["claude:sonnet"], 120)!;
  assert.equal(built.timeoutMs, 120000);
  assert.ok(Object.isFrozen(built) && Object.isFrozen(built.models));
});

test("the live Claude command preserves OAuth, disables tools and context, and requests no persistence", () => {
  const args = liveModelArgs("claude", "sonnet", TOKEN);
  const value = (flag: string) => args[args.indexOf(flag) + 1];
  for (const flag of ["--print", "--safe-mode", "--no-session-persistence", "--strict-mcp-config", "--disable-slash-commands"]) assert.ok(args.includes(flag));
  assert.equal(value("--model"), "sonnet");
  assert.equal(value("--max-turns"), "1");
  assert.equal(value("--max-budget-usd"), "0.25");
  assert.equal(value("--tools"), "");
  assert.equal(value("--disallowedTools"), "*");
  assert.equal(value("--permission-mode"), "dontAsk");
  assert.equal(value("--setting-sources"), "");
  assert.deepEqual(JSON.parse(value("--settings")!), { disableAllHooks: true });
  assert.deepEqual(JSON.parse(value("--mcp-config")!), { mcpServers: {} });
  assert.equal(args.at(-1), TOKEN);
  for (const flag of ["--bare", "--dangerously-skip-permissions", "--continue", "--resume", "--fallback-model", "--add-dir"]) assert.ok(!args.includes(flag));
  assert.throws(() => liveModelArgs("gemini", "model", TOKEN));
  assert.throws(() => liveModelArgs("claude", "--bad", TOKEN));
  assert.throws(() => liveModelArgs("claude", "sonnet", "arbitrary prompt"));
});

test("completed exact nonce response is required, not exit zero, a banner, denial or conflicting evidence", () => {
  const good = response(TOKEN);
  assert.equal(liveModelResponseMatches("claude", ok(JSON.stringify(good)), TOKEN), true);
  for (const fields of [{ type: "assistant" }, { subtype: "error_during_execution" }, { is_error: true },
    { is_error: undefined }, { num_turns: 0 }, { num_turns: 2 }, { num_turns: true },
    { result: "OK" }, { result: "prefix " + TOKEN }, { result: "ACFS_LIVE_" + "cd".repeat(16) },
    { permission_denials: [{}] }, { permission_denials: undefined }]) {
    assert.equal(liveModelResponseMatches("claude", ok(JSON.stringify({ ...good, ...fields })), TOKEN), false);
  }
  for (const text of [TOKEN, "banner\n" + JSON.stringify(good), JSON.stringify([good]),
    JSON.stringify(good) + "\n{}", JSON.stringify(good).replace('"is_error":false', '"is_error":true,"is_error":false'),
    JSON.stringify(good).replace('"is_error":false', '"is_error":true,"is_\\u0065rror":false')]) {
    assert.equal(liveModelResponseMatches("claude", ok(text), TOKEN), false);
  }
  for (const outcome of ["exit_nonzero", "spawn_failed", "timeout", "output_limit", "cancelled", "signaled", "lingering_processes"] as const)
    assert.equal(liveModelResponseMatches("claude", { ...ok(JSON.stringify(good)), outcome }, TOKEN), false);
  assert.equal(liveModelResponseMatches("claude", { ...ok(JSON.stringify(good)), exitCode: null }, TOKEN), false);
  assert.equal(liveModelResponseMatches("claude", { ...ok(JSON.stringify(good)), exitCode: 7 }, TOKEN), false);
  assert.equal(liveModelResponseMatches("claude", { ...ok(JSON.stringify(good)), stderr: Buffer.alloc(65536) }, TOKEN), false);
  assert.equal(liveModelResponseMatches("claude", { ...ok(""), stdout: Buffer.concat([Buffer.from(JSON.stringify(good)), Buffer.from([255])]) }, TOKEN), false);
});

test("real rehearsal runs one fixed challenge in a fresh private directory between existing local checks", async () => {
  const { deps, calls } = harness();
  const report = await rehearseProfiles(plan(), { ...live, liveTimeoutSeconds: 90 }, deps);
  assert.equal(report.status, "pass");
  assert.equal(report.profiles[0]!.liveModel?.status, "verified");
  assert.equal(report.profiles[0]!.liveModel?.attempts, 1);
  assert.equal(report.liveModelPolicy?.responseVerified, true);
  assert.equal(report.modelPromptSent, true);
  assert.equal(report.liveAuthenticationVerified, false); // No independent account attestation.
  assert.equal(report.globalActivationRequested, false);
  assert.equal(calls.length, 4);
  assert.deepEqual(calls[0]!.args, ["profile", "status", "claude", "private@example.com"]);
  assert.deepEqual(calls[1]!.args, ["exec", "claude", "private@example.com", "--", "--version"]);
  assert.deepEqual(calls[3]!.args, calls[0]!.args);
  const request = calls[2]!;
  assert.deepEqual(request.args.slice(0, 4), ["exec", "claude", "private@example.com", "--"]);
  assert.match(request.args.at(-1)!, /^ACFS_LIVE_[a-f0-9]{32}$/);
  assert.equal(request.timeoutMs, 90000);
  assert.equal(request.requireQuiescence, true);
  assert.equal(request.env.OPENAI_API_KEY, undefined);
  assert.equal(request.env.NODE_OPTIONS, undefined);
  assert.ok(request.cwd && request.cwd !== process.cwd() && request.cwd !== "/");
  assert.deepEqual(readdirSync(request.cwd!), []);
  assert.equal(statSync(request.cwd!).mode & 0o077, 0);
  const rendered = JSON.stringify(report) + formatRehearsal(report);
  for (const value of ["private@example.com", "/private/profile", request.cwd!, request.args.at(-1)!]) assert.ok(!rendered.includes(value));
});

test("two explicitly selected profiles get different challenges and workspaces, with stable references", async () => {
  const { deps, calls } = harness();
  const report = await rehearseProfiles(buildRehearsalPlan(["claude:one", "claude:two"]), live, deps);
  const requests = calls.filter(isLive);
  assert.equal(report.status, "pass");
  assert.equal(report.liveModelPolicy?.maximumCliAttempts, 2);
  assert.equal(requests.length, 2);
  assert.notEqual(requests[0]!.args.at(-1), requests[1]!.args.at(-1));
  assert.notEqual(requests[0]!.cwd, requests[1]!.cwd);
  assert.deepEqual(report.profiles.map((p) => p.profileRef), ["profile-1", "profile-2"]);
});

test("missing local auth, busy profiles, failed version or unknown version cannot start a paid attempt", async () => {
  for (const condition of ["missing", "locked", "bad-version", "unknown-version"]) {
    const { deps, calls } = harness((request, normal) => {
      if (request.args[0] === "profile" && condition === "missing") return ok(normal.stdout.toString().replace("Logged in: true", "Logged in: false"));
      if (request.args[0] === "profile" && condition === "locked") return ok(normal.stdout.toString().replace("Locked: false", "Locked: true"));
      if (request.args.includes("--version") && condition === "bad-version") return { ...normal, outcome: "exit_nonzero", exitCode: 12 };
      if (request.args.includes("--version") && condition === "unknown-version") return ok("unrecognized");
      return normal;
    });
    const report = await rehearseProfiles(plan(), live, deps);
    assert.equal(report.status, "fail", condition);
    assert.equal(calls.filter(isLive).length, 0);
    assert.equal(report.modelPromptSent, false);
    assert.equal(report.profiles[0]!.liveModel?.status, "not_attempted");
    assert.equal(report.liveModelPolicy?.responseVerified, false);
  }
});

test("requested native-auth failures and unknown protocols stop before a paid attempt", async () => {
  for (const native of [ok("{}"), { ...ok('{"loggedIn":false}'), outcome: "exit_nonzero" as const, exitCode: 1 }]) {
    const { deps, calls } = harness((request, normal) => request.args.includes("auth") ? native : normal);
    const report = await rehearseProfiles(plan(), { ...live, nativeAuth: true }, deps);
    assert.equal(report.status, "fail");
    assert.equal(calls.filter(isLive).length, 0);
    assert.equal(report.profiles[0]!.liveModel?.attempts, 0);
  }
});

test("unconfirmed responses stop subsequent profiles and never imply that nothing was billed", async () => {
  for (const outcome of ["ok", "exit_nonzero", "spawn_failed", "timeout", "output_limit", "lingering_processes"] as const) {
    const { deps, calls } = harness((request, normal) => isLive(request) ? { ...ok("not the challenge"), outcome, exitCode: 0 } : normal);
    const report = await rehearseProfiles(buildRehearsalPlan(["claude:one", "claude:two"]), live, deps);
    assert.equal(report.status, "fail");
    assert.equal(report.modelPromptSent, null);
    assert.equal(report.liveModelPolicy?.responseVerified, false);
    assert.equal(report.profiles[0]!.liveModel?.status, "unconfirmed");
    assert.equal(report.profiles[1]!.liveModel?.attempts, 0);
    assert.equal(calls.filter(isLive).length, 1);
    assert.equal(calls.length, 4); // Always inspect the first profile again, never run the second.
    assert.match(formatRehearsal(report), /does not prove no request was billed/);
  }
});

test("thrown live runner errors are redacted and preserved as uncertain attempts", async () => {
  const { deps, calls } = harness((request, normal) => {
    if (isLive(request)) throw Error("sk-secret-in-runner-error");
    return normal;
  });
  const report = await rehearseProfiles(plan(), live, deps);
  assert.equal(report.status, "fail");
  assert.equal(report.modelPromptSent, null);
  assert.equal(calls.length, 4);
  assert.ok(!JSON.stringify(report).includes("sk-secret"));
});

test("live cancellation stops all later probes even when a valid reply raced with abort", async () => {
  const controller = new AbortController();
  const { deps, calls } = harness((request, normal) => {
    if (isLive(request)) controller.abort();
    return normal;
  });
  const report = await rehearseProfiles(buildRehearsalPlan(["claude:one", "claude:two"]), { ...live, signal: controller.signal }, deps);
  assert.equal(report.status, "cancelled");
  assert.equal(report.modelPromptSent, null);
  assert.equal(report.liveModelPolicy?.responseVerified, false);
  assert.equal(report.profiles[0]!.liveModel?.status, "unconfirmed");
  assert.equal(calls.length, 3);
});

test("a changed post-check cannot make an otherwise verified response a fully passing rehearsal", async () => {
  const { deps, calls } = harness((_, normal, n) => n === 4 ? ok(normal.stdout.toString().replace("Locked: false", "Locked: true")) : normal);
  const report = await rehearseProfiles(plan(), live, deps);
  assert.equal(report.status, "fail");
  assert.equal(report.liveModelPolicy?.responseVerified, false);
  assert.equal(report.profiles[0]!.liveModel?.status, "verified"); // Historical evidence is retained.
  assert.equal(report.modelPromptSent, true);
  assert.equal(calls.length, 4);
});

test("response metadata and failed diagnostics never enter text or JSON reports", async () => {
  const secret = "sk-this-must-not-be-reported";
  const { deps } = harness((request, normal) => isLive(request) ? {
    ...ok(JSON.stringify({ ...response(request.args.at(-1)!), secret, session_id: "private-session", cwd: "/private/repo" })),
    stderr: Buffer.from(secret),
  } : normal);
  const report = await rehearseProfiles(plan(), live, deps);
  assert.equal(report.status, "pass");
  for (const text of [JSON.stringify(report), formatRehearsal(report)]) {
    for (const value of [secret, "private-session", "/private/repo", "private@example.com", "ACFS_LIVE_"]) assert.ok(!text.includes(value));
  }
});

test("real runner executes in the private cwd with closed stdin and rejects background survivors", async () => {
  const cwd = mkdtempSync(join(ROOT, "workspace-"));
  const normal = await runBoundedProbe({ binary: process.execPath,
    args: ["-e", "console.log(process.cwd());console.log(require('fs').readFileSync(0).length)"],
    env: {}, cwd, timeoutMs: 2000, requireQuiescence: true });
  assert.equal(normal.outcome, "ok");
  assert.equal(normal.stdout.toString(), cwd + "\n0\n");
  const marker = join(ROOT, "background-survived");
  const child = `setTimeout(()=>require('fs').writeFileSync(${JSON.stringify(marker)},'bad'),700)`;
  const result = await runBoundedProbe({ binary: process.execPath,
    args: ["-e", `require('child_process').spawn(process.execPath,['-e',${JSON.stringify(child)}],{stdio:'ignore'}).unref()`],
    env: {}, cwd, timeoutMs: 2000, requireQuiescence: true });
  assert.equal(result.outcome, "lingering_processes");
  assert.equal(result.stdout.length + result.stderr.length, 0);
  await new Promise((done) => setTimeout(done, 850));
  assert.equal(existsSync(marker), false);
});

test("CLI refuses malformed live requests before probes and previews without executing", () => {
  const preview = spawnSync(process.execPath, [cli, "--profile", "claude:private@example.com", "--live-model", "claude:sonnet", "--json"], { encoding: "utf8" });
  assert.equal(preview.status, 0, preview.stderr);
  assert.equal(JSON.parse(preview.stdout).status, "planned");
  assert.equal(JSON.parse(preview.stdout).liveModelPolicy.mayIncurCharges, true);
  for (const flags of [["--live-model", "claude:--bad"], ["--live-timeout", "1"],
    ["--live-model", "claude:sonnet", "--live-timeout", "121"], ["--live-model", "claude:sonnet", "--live-timeout", "1", "--live-timeout", "2"]]) {
    const result = spawnSync(process.execPath, [cli, "--profile", "claude:private@example.com", ...flags, "--run", "--json"], { encoding: "utf8" });
    assert.equal(result.status, 2);
    assert.ok(!result.stdout.includes("private@example.com"));
    assert.notEqual(JSON.parse(result.stdout).code, "run_as_target_user_without_sudo");
  }
});

test("real unprivileged CLI executes fixture CAAM live path and saves redacted evidence", () => {
  const directory = mkdtempSync(join(ROOT, "cli-"));
  chmodSync(ROOT, 0o755); chmodSync(directory, 0o777);
  const bin = join(directory, "bin"); mkdirSync(bin, { mode: 0o755 });
  const record = join(directory, "calls.jsonl");
  const fake = join(bin, "caam");
  writeFileSync(fake, `#!${process.execPath}\nconst fs=require('fs');
const args=process.argv.slice(2);
fs.appendFileSync(${JSON.stringify(record)},JSON.stringify({args,cwd:process.cwd(),uid:process.getuid(),credential:!!process.env.OPENAI_API_KEY,stdin:fs.readFileSync(0).length})+'\\n');
if(args[0]==='profile') console.log('Profile: '+args[2]+'/'+args[3]+'\\n  Path: /private/profile\\n  Auth mode: oauth\\n  Logged in: true\\n  Locked: false');
else if(args.includes('--version')) console.log('Claude 2.1.300');
else if(args.includes('--print')) console.log(JSON.stringify({type:'result',subtype:'success',is_error:false,num_turns:1,result:args.at(-1),permission_denials:[],private:'sk-secret-hidden'}));
else process.exitCode=98;
`, { mode: 0o755 });
  const identity = process.getuid?.() === 0 ? { uid: 65534, gid: 65534 } : {};
  // A private evidence parent is separate from the world-writable fixture log.
  const evidenceDir = mkdtempSync(join(tmpdir(), "acfs-live-evidence-"));
  if (identity.uid !== undefined) chownSync(evidenceDir, identity.uid, identity.gid!);
  const evidence = join(evidenceDir, "report.json");
  const result = spawnSync(process.execPath, [cli, "--profile", "claude:private@example.com", "--live-model", "claude:sonnet", "--run", "--json", "--output", evidence], {
    encoding: "utf8", timeout: 5000, ...identity, env: { PATH: `${bin}:/usr/bin:/bin`, OPENAI_API_KEY: "sk-never-inherit" },
  });
  assert.equal(result.status, 0, result.stderr + result.stdout);
  const report = JSON.parse(result.stdout);
  assert.equal(report.status, "pass");
  assert.equal(report.liveModelPolicy.responseVerified, true);
  assert.deepEqual(JSON.parse(readFileSync(evidence, "utf8")), report);
  assert.equal(statSync(evidence).mode & 0o777, 0o600);
  const calls = readFileSync(record, "utf8").trim().split("\n").map((line) => JSON.parse(line));
  assert.equal(calls.length, 4);
  assert.ok(calls.every((c) => c.uid !== 0 && c.stdin === 0 && !c.credential));
  assert.notEqual(calls[2].cwd, "/");
  assert.equal(statSync(calls[2].cwd).mode & 0o077, 0);
  assert.ok(!result.stdout.includes("private@example.com") && !result.stdout.includes("sk-secret"));
});

test("Codex uses ephemeral read-only execution with explicit model and per-invocation restrictions", () => {
  const args = liveModelArgs("codex", "gpt-test", TOKEN);
  for (const flag of ["exec", "--ignore-user-config", "--ephemeral", "--skip-git-repo-check", "--json"])
    assert.ok(args.includes(flag));
  assert.equal(args[args.indexOf("--sandbox") + 1], "read-only");
  assert.equal(args[args.indexOf("--model") + 1], "gpt-test");
  assert.equal(args[args.indexOf("--color") + 1], "never");
  for (const feature of ["shell_tool", "hooks", "plugins", "multi_agent", "apps", "memories", "shell_snapshot", "skill_mcp_dependency_install"])
    assert.equal(args[args.indexOf(feature) - 1], "--disable");
  for (const override of ['approval_policy="never"', 'web_search="disabled"', "mcp_servers={}", "project_doc_max_bytes=0"])
    assert.equal(args[args.indexOf(override) - 1], "--config");
  assert.equal(args.at(-1), TOKEN);
  for (const flag of ["--dangerously-bypass-approvals-and-sandbox", "--full-auto", "--ignore-rules", "--oss", "--resume", "--output-last-message"])
    assert.ok(!args.includes(flag));
});

test("Codex accepts one completed lifecycle with reasoning and matching final response", () => {
  assert.equal(liveModelResponseMatches("codex", ok(jsonl(codexEvents(TOKEN))), TOKEN), true);
  const streamed = [
    ...codexEvents(TOKEN).slice(0, 2),
    { type: "item.started", item: { id: "a", type: "agent_message", text: "" } },
    { type: "item.updated", item: { id: "a", type: "agent_message", text: TOKEN.slice(0, 12) } },
    { type: "item.completed", item: { id: "a", type: "agent_message", text: TOKEN } },
    ...codexEvents(TOKEN).slice(-1),
  ];
  assert.equal(liveModelResponseMatches("codex", ok(jsonl(streamed).replace(/\n/g, "\r\n")), TOKEN), true);
});

test("Codex refuses incomplete, reordered, repeated or trailing lifecycles", () => {
  const events = codexEvents(TOKEN);
  for (const transcript of [events.slice(1), events.slice(0, -1), [events[1]!, events[0]!, ...events.slice(2)],
    [...events.slice(0, 2), events[1]!, ...events.slice(2)], [...events, ...events],
    [...events, { type: "error", message: "private failure" }],
    [...events.slice(0, -1), { type: "turn.failed", error: { message: "bad" } }],
    [events[0]!, events[1]!, events.at(-1)!]]) {
    assert.equal(liveModelResponseMatches("codex", ok(jsonl(transcript)), TOKEN), false);
  }
  assert.equal(liveModelResponseMatches("codex", ok("banner\n" + jsonl(events)), TOKEN), false);
  assert.equal(liveModelResponseMatches("codex", ok(jsonl(events) + "garbage"), TOKEN), false);
  assert.equal(liveModelResponseMatches("codex", ok(TOKEN), TOKEN), false);
});

test("every tool or unknown item invalidates an otherwise successful Codex stream", () => {
  for (const type of ["command_execution", "file_change", "mcp_tool_call", "collab_tool_call", "web_search", "todo_list", "error", "future_tool"]) {
    const events = codexEvents(TOKEN);
    events.splice(2, 0, { type: "item.completed", item: { id: "tool", type, text: "private payload", status: "completed" } });
    assert.equal(liveModelResponseMatches("codex", ok(jsonl(events)), TOKEN), false, type);
  }
});

test("Codex rejects duplicate item completion, type changes, unfinished items and multiple replies", () => {
  for (const extra of [
    { type: "item.completed", item: { id: "item_1", type: "agent_message", text: TOKEN } },
    { type: "item.completed", item: { id: "reply2", type: "agent_message", text: TOKEN } },
    { type: "item.started", item: { id: "never-completed", type: "reasoning", text: "pending" } },
    { type: "item.updated", item: { id: "never-started", type: "reasoning", text: "bad" } },
  ]) {
    const events = codexEvents(TOKEN);
    events.splice(-1, 0, extra);
    assert.equal(liveModelResponseMatches("codex", ok(jsonl(events)), TOKEN), false);
  }
  const events = codexEvents(TOKEN);
  events.splice(2, 0, { type: "item.started", item: { id: "item_1", type: "reasoning", text: "pending" } });
  assert.equal(liveModelResponseMatches("codex", ok(jsonl(events)), TOKEN), false);
  const wrong = codexEvents("ACFS_LIVE_" + "cd".repeat(16));
  assert.equal(liveModelResponseMatches("codex", ok(jsonl(wrong)), TOKEN), false);
});

test("Codex requires bounded valid usage and rejects ambiguous JSON or malformed encodings", () => {
  const usage = { input_tokens: 120, cached_input_tokens: 0, output_tokens: 24 };
  for (const bad of [null, [], {}, { ...usage, input_tokens: -1 }, { ...usage, output_tokens: 0 },
    { ...usage, cached_input_tokens: 121 }, { ...usage, output_tokens: true }, { ...usage, input_tokens: 0.5 },
    { ...usage, reasoning_output_tokens: -1 }, { ...usage, cache_write_input_tokens: "10" },
    { ...usage, output_tokens: 1e100 }]) {
    const events = codexEvents(TOKEN); events[events.length - 1] = { type: "turn.completed", usage: bad };
    assert.equal(liveModelResponseMatches("codex", ok(jsonl(events)), TOKEN), false);
  }
  const good = jsonl(codexEvents(TOKEN));
  for (const text of [good.replace('"turn.completed"', '"turn.failed","type":"turn.completed"'),
    good.replace('"output_tokens":24', '"output_tokens":0,"output_\\u0074okens":24'),
    good.replace('"input_tokens":120', '"input_tokens":1e999'), good.replace('"thread_id":', '"thread_id":null,"thread_id":')]) {
    assert.equal(liveModelResponseMatches("codex", ok(text), TOKEN), false);
  }
  assert.equal(liveModelResponseMatches("codex", { ...ok(good), stdout: Buffer.concat([Buffer.from(good), Buffer.from([255])]) }, TOKEN), false);
  assert.equal(liveModelResponseMatches("codex", ok("\n".repeat(70000) + good), TOKEN), false);
  for (const outcome of ["timeout", "cancelled", "lingering_processes", "exit_nonzero"] as const)
    assert.equal(liveModelResponseMatches("codex", { ...ok(good), outcome }, TOKEN), false);
});

test("mixed Claude and Codex profiles complete their own challenges through one shared workflow", async () => {
  const { deps, calls } = harness();
  const report = await rehearseProfiles(buildRehearsalPlan(["codex:review", "claude:implementation"]), {
    ...live, liveModels: ["claude:sonnet", "codex:gpt-test"], requireNativeAuth: true,
  }, deps);
  assert.equal(report.status, "pass");
  assert.equal(report.liveModelPolicy?.responseVerified, true);
  assert.deepEqual(report.profiles.map((p) => [p.provider, p.nativeAuth, p.liveModel?.status]), [
    ["codex", "present", "verified"], ["claude", "present", "verified"],
  ]);
  const requests = calls.filter(isLive);
  assert.equal(requests.length, 2);
  assert.deepEqual(requests[0]!.args.slice(0, 4), ["exec", "codex", "review", "--"]);
  assert.deepEqual(requests[1]!.args.slice(0, 4), ["exec", "claude", "implementation", "--"]);
  assert.notEqual(requests[0]!.args.at(-1), requests[1]!.args.at(-1));
  assert.equal(calls.length, 10);
});

test("a failed Codex result does not fall back to Claude or retry with relaxed restrictions", async () => {
  const { deps, calls } = harness((request, normal) => isLive(request) ? ok(jsonl([
    ...codexEvents(request.args.at(-1)!).slice(0, -1), { type: "turn.failed", error: { message: "private quota exhausted" } },
  ])) : normal);
  const report = await rehearseProfiles(buildRehearsalPlan(["codex:review", "claude:implementation"]), {
    ...live, liveModels: ["codex:gpt-test", "claude:sonnet"],
  }, deps);
  assert.equal(report.status, "fail");
  assert.equal(report.modelPromptSent, null);
  assert.equal(calls.filter(isLive).length, 1);
  assert.equal(report.profiles[1]!.liveModel?.status, "not_attempted");
  assert.ok(!JSON.stringify(report).includes("quota exhausted"));
});

test("local-only all-provider rehearsals retain the original non-model sequence", async () => {
  const { deps, calls } = harness();
  const report = await rehearseProfiles(buildRehearsalPlan(["claude:one", "codex:two", "gemini:three", "agy:four"]), {
    execute: true, env: ENV,
  }, deps);
  assert.equal(report.status, "pass");
  assert.equal(report.modelPromptSent, false);
  assert.equal(report.liveModelPolicy, undefined);
  assert.equal(report.scope, "isolated-cli-startup-and-local-auth");
  assert.equal(calls.length, 12);
  assert.equal(calls.filter(isLive).length, 0);
  assert.ok(calls.every((c) => c.cwd === undefined && c.requireQuiescence === undefined));
});

test("real Codex fixture CLI emits JSONL under an unprivileged isolated execution", () => {
  const directory = mkdtempSync(join(ROOT, "codex-cli-"));
  chmodSync(ROOT, 0o755); chmodSync(directory, 0o777);
  const bin = join(directory, "bin"); mkdirSync(bin, { mode: 0o755 });
  const record = join(directory, "calls.jsonl");
  writeFileSync(join(bin, "caam"), `#!${process.execPath}
const fs=require('fs'), args=process.argv.slice(2);
fs.appendFileSync(${JSON.stringify(record)},JSON.stringify({args,uid:process.getuid(),cwd:process.cwd(),secret:!!process.env.OPENAI_API_KEY})+'\\n');
if(args[0]==='profile') console.log('Profile: '+args[2]+'/'+args[3]+'\\n  Path: /private/profile\\n  Auth mode: oauth\\n  Logged in: true\\n  Locked: false');
else if(args.includes('--version')) console.log('codex-cli 1.2.3');
else if(args.includes('--ephemeral')) {
  const events=${JSON.stringify(codexEvents("CHALLENGE"))};
  events[3].item.text=args.at(-1);
  for(const event of events) console.log(JSON.stringify(event));
} else process.exitCode=98;
`, { mode: 0o755 });
  const result = spawnSync(process.execPath, [cli, "--profile", "codex:private@example.com", "--live-model", "codex:gpt-test", "--run", "--json"], {
    encoding: "utf8", timeout: 5000,
    ...(process.getuid?.() === 0 ? { uid: 65534, gid: 65534 } : {}),
    env: { PATH: `${bin}:/usr/bin:/bin`, OPENAI_API_KEY: "sk-not-inherited" },
  });
  assert.equal(result.status, 0, result.stderr + result.stdout);
  const report = JSON.parse(result.stdout);
  assert.equal(report.liveModelPolicy.responseVerified, true);
  assert.equal(report.profiles[0].liveModel.requestedModel, "gpt-test");
  const calls = readFileSync(record, "utf8").trim().split("\n").map((line) => JSON.parse(line));
  assert.equal(calls.length, 4);
  assert.ok(calls.every((c) => c.uid !== 0 && !c.secret));
  assert.notEqual(calls[2].cwd, "/");
  assert.equal(calls[2].args[calls[2].args.indexOf("--sandbox") + 1], "read-only");
  for (const value of ["private@example.com", "ACFS_LIVE_", "thread_id", "Return the token."])
    assert.ok(!result.stdout.includes(value));
});
