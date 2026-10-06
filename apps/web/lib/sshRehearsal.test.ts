import { describe, expect, test } from "bun:test";
import {
  HOST_KEY_PROMPT,
  HOST_KEY_RETRY_PROMPT,
  REHEARSAL_HOSTNAME,
  REHEARSAL_LOCAL_PROMPT,
  REHEARSAL_REMOTE_PROMPT,
  isSshRehearsalSecret,
  sshRehearsalPrompt,
  startSshRehearsal,
  stepSshRehearsal,
  type SshRehearsalState,
} from "./sshRehearsal";

const TARGET = "root@203.0.113.42";
const HOST = "203.0.113.42";

function run(inputs: string[], state: SshRehearsalState = startSshRehearsal(TARGET, HOST)) {
  return inputs.reduce(stepSshRehearsal, state);
}

function texts(state: SshRehearsalState): string[] {
  return state.lines.map((line) => line.text);
}

describe("ssh rehearsal", () => {
  test("walks the whole first login: command, host key, blind password, hostname, exit", () => {
    let state = startSshRehearsal(TARGET, HOST);
    expect(state.stage).toBe("local");
    expect(sshRehearsalPrompt(state)).toBe(REHEARSAL_LOCAL_PROMPT);

    state = stepSshRehearsal(state, `  ssh   ${TARGET} `);
    expect(state.stage).toBe("hostkey");
    expect(sshRehearsalPrompt(state)).toBe(HOST_KEY_PROMPT);
    expect(texts(state)).toContain(
      `The authenticity of host '${HOST} (${HOST})' can't be established.`,
    );

    state = stepSshRehearsal(state, "yes");
    expect(state.stage).toBe("password");
    expect(isSshRehearsalSecret(state)).toBe(true);
    expect(sshRehearsalPrompt(state)).toBe(`${TARGET}'s password:`);

    state = stepSshRehearsal(state, "practice-pass");
    expect(state.stage).toBe("remote");
    expect(sshRehearsalPrompt(state)).toBe(REHEARSAL_REMOTE_PROMPT);

    state = stepSshRehearsal(state, "hostname");
    expect(state.checkedHostname).toBe(true);
    expect(texts(state)).toContain(REHEARSAL_HOSTNAME);

    state = stepSshRehearsal(state, "exit");
    expect(state.stage).toBe("done");
    expect(texts(state)).toContain(`Connection to ${HOST} closed.`);
  });

  test("a partial answer re-prompts with OpenSSH's wording and explains y vs yes", () => {
    const state = run([`ssh ${TARGET}`, "y"]);
    expect(state.stage).toBe("hostkey");
    expect(sshRehearsalPrompt(state)).toBe(HOST_KEY_RETRY_PROMPT);
    expect(texts(state).join("\n")).toContain('whole word "yes"');

    const accepted = stepSshRehearsal(state, "YES");
    expect(accepted.stage).toBe("password");
    expect(sshRehearsalPrompt(accepted)).toBe(`${TARGET}'s password:`);
  });

  test("answering no aborts like real ssh and the command can be retried", () => {
    const state = run([`ssh ${TARGET}`, "no"]);
    expect(state.stage).toBe("local");
    expect(texts(state)).toContain("Host key verification failed.");
    expect(run([`ssh ${TARGET}`], state).stage).toBe("hostkey");
  });

  test("blind-typed input at the password prompt never enters state or transcript", () => {
    const typed = "blind-typing-sample-123";
    const state = run([`ssh ${TARGET}`, "yes", typed]);
    expect(state.stage).toBe("remote");
    expect(JSON.stringify(state)).not.toContain(typed);
    // The echoed line is the bare prompt, like a real terminal.
    expect(texts(state)).toContain(`${TARGET}'s password:`);
  });

  test("empty passwords are refused, and the third ends the attempt", () => {
    let state = run([`ssh ${TARGET}`, "yes", ""]);
    expect(state.stage).toBe("password");
    expect(texts(state)).toContain("Permission denied, please try again.");

    state = run(["", ""], state);
    expect(state.stage).toBe("local");
    expect(texts(state)).toContain(`${TARGET}: Permission denied (publickey,password).`);
    expect(state.failedPasswords).toBe(0);
  });

  test("other commands get guidance instead of execution", () => {
    const local = run(["rm -rf /"]);
    expect(local.stage).toBe("local");
    expect(texts(local).at(-1)).toBe(`In this practice, connect with: ssh ${TARGET}`);

    const remote = run([`ssh ${TARGET}`, "yes", "pw", "sudo reboot"]);
    expect(remote.stage).toBe("remote");
    expect(texts(remote).at(-1)).toBe("This practice terminal only knows: hostname, whoami, exit.");
    expect(texts(run(["whoami"], remote))).toContain("root");
  });

  test("IPv6 targets keep brackets in the command but not in SSH's messages", () => {
    const state = run(
      ["ssh root@[2001:db8::1]", "yes", "pw", "exit"],
      startSshRehearsal("root@[2001:db8::1]", "[2001:db8::1]"),
    );
    expect(state.stage).toBe("done");
    expect(texts(state)).toContain(
      "The authenticity of host '2001:db8::1 (2001:db8::1)' can't be established.",
    );
    expect(texts(state)).toContain(
      "Warning: Permanently added '2001:db8::1' (ED25519) to the list of known hosts.",
    );
    expect(texts(state)).toContain("Connection to 2001:db8::1 closed.");
  });

  test("the transcript stays bounded", () => {
    const state = run(Array.from({ length: 400 }, () => "ls"));
    expect(state.lines.length).toBe(200);
  });
});
