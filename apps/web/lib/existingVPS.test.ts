import { strict as assert } from "node:assert";
import { spawnSync } from "node:child_process";
import { chownSync, existsSync, mkdtempSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { buildInstallCommandDetails, buildRootSessionKeyRepairCommand } from "./commandBuilder";

test("in-place installer preserves ref, user, mode and modules without requesting an upgrade", () => {
  const modules = { onlyModules: ["lang.bun"] };
  const guided = buildInstallCommandDetails("safe", "release/v1.2", "developer", modules);
  for (const release of ["22.04", "24.04"]) {
    const inPlace = buildInstallCommandDetails("safe", "release/v1.2", "developer", modules, release);
    assert.equal(inPlace.command, guided.command.replace("--target-ubuntu=26.04", "--skip-ubuntu-upgrade"));
    assert.ok(inPlace.command.includes('TARGET_USER="developer"'));
    assert.ok(inPlace.command.includes('--only "lang.bun"'));
    assert.ok(inPlace.command.includes("--mode safe"));
    assert.ok(!inPlace.command.includes("--target-ubuntu"));
    assert.equal(inPlace.targetUbuntu, release);
  }
});

test("the root-session key enrollment command refuses invalid input before looking up an account", () => {
  assert.throws(() => buildRootSessionKeyRepairCommand("invalid name"));
  const dir = mkdtempSync(join(tmpdir(), "acfs-existing-ssh-"));
  const bin = join(dir, "bin");
  mkdirSync(bin);
  writeFileSync(join(bin, "getent"), "#!/bin/sh\ntouch \"$ACCOUNT_LOOKUP\"\nexit 1\n", { mode: 0o755 });
  const marker = join(dir, "lookup");
  const result = spawnSync("sh", ["-c", buildRootSessionKeyRepairCommand("developer")], {
    input: "not a public key\n",
    env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, ACCOUNT_LOOKUP: marker },
  });
  assert.notEqual(result.status, 0);
  assert.equal(existsSync(marker), false);
});

test("the existing admin session can enroll a public key for another login without replacing older keys", {
  skip: process.platform !== "linux",
}, () => {
  const temp = mkdtempSync(join(tmpdir(), "acfs-existing-key-"));
  const bin = join(temp, "bin");
  const accountHome = join(temp, "login home");
  mkdirSync(bin);
  mkdirSync(accountHome);
  const uid = process.getuid!() || 1000;
  const gid = process.getgid!();
  if (process.getuid!() === 0) chownSync(accountHome, uid, gid);
  writeFileSync(join(bin, "getent"),
    "#!/bin/sh\nprintf 'developer:x:%s:%s::%s:/bin/sh\\n' \"$ACCOUNT_UID\" \"$ACCOUNT_GID\" \"$ACCOUNT_HOME\"\n",
    { mode: 0o755 });
  const key = join(temp, "acfs_ed25519");
  const generated = spawnSync("ssh-keygen", ["-q", "-t", "ed25519", "-N", "", "-f", key]);
  assert.equal(generated.status, 0);
  const publicKey = readFileSync(`${key}.pub`, "utf8");
  const ssh = join(accountHome, ".ssh");
  mkdirSync(ssh);
  const authorizedKeys = join(ssh, "authorized_keys");
  writeFileSync(authorizedKeys, "# existing authorization");
  const command = buildRootSessionKeyRepairCommand("developer");
  for (let attempt = 0; attempt < 2; attempt++) {
    const result = spawnSync("sh", ["-c", command], {
      input: publicKey,
      encoding: "utf8",
      env: {
        ...process.env, PATH: `${bin}:${process.env.PATH}`,
        ACCOUNT_HOME: accountHome, ACCOUNT_UID: String(uid), ACCOUNT_GID: String(gid),
      },
    });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(readFileSync(authorizedKeys, "utf8"), `# existing authorization\n${publicKey}`);
  }
});
