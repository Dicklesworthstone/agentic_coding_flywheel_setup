/**
 * Deterministic rehearsal of a first SSH login, so beginners can practice the
 * host-key prompt, blind password typing, `hostname` and `exit` before they
 * touch a real server. Scripted states only: nothing is executed, sent or
 * stored, and the practice password never enters the state or transcript.
 */

export type SshRehearsalStage = "local" | "hostkey" | "password" | "remote" | "done";

export type SshRehearsalLineKind = "input" | "output" | "warning" | "error" | "success" | "note";

export interface SshRehearsalLine {
  kind: SshRehearsalLineKind;
  text: string;
}

export interface SshRehearsalState {
  stage: SshRehearsalStage;
  /** e.g. `root@203.0.113.42` (already formatted by formatSshTarget). */
  target: string;
  /** Host as SSH prints it, e.g. `203.0.113.42` or `[2001:db8::1]`. */
  host: string;
  lines: SshRehearsalLine[];
  hostKeyRetry: boolean;
  failedPasswords: number;
  checkedHostname: boolean;
}

export const REHEARSAL_LOCAL_PROMPT = "you@laptop ~ %";
export const REHEARSAL_HOSTNAME = "vps-12345";
export const REHEARSAL_REMOTE_PROMPT = `root@${REHEARSAL_HOSTNAME}:~#`;
export const REHEARSAL_FINGERPRINT = "SHA256:PracticeOnly0NotARealServerKey0000000000000";
export const HOST_KEY_PROMPT = "Are you sure you want to continue connecting (yes/no/[fingerprint])?";
// OpenSSH's exact re-prompt after an answer other than yes/no/fingerprint.
export const HOST_KEY_RETRY_PROMPT = "Please type 'yes', 'no' or the fingerprint:";
export const REMOTE_COMMANDS = ["hostname", "whoami", "exit"] as const;

const MAX_PASSWORD_ATTEMPTS = 3;
const MAX_LINES = 200;

export function startSshRehearsal(target: string, host: string): SshRehearsalState {
  return {
    stage: "local",
    target,
    host,
    lines: [
      {
        kind: "note",
        text: "Practice terminal: nothing here connects anywhere. Type the ssh command to begin.",
      },
    ],
    hostKeyRetry: false,
    failedPasswords: 0,
    checkedHostname: false,
  };
}

/** The prompt shown in front of the input for the current stage. */
export function sshRehearsalPrompt(state: SshRehearsalState): string {
  switch (state.stage) {
    case "hostkey":
      return state.hostKeyRetry ? HOST_KEY_RETRY_PROMPT : HOST_KEY_PROMPT;
    case "password":
      return `${state.target}'s password:`;
    case "remote":
      return REHEARSAL_REMOTE_PROMPT;
    default:
      return REHEARSAL_LOCAL_PROMPT;
  }
}

/** True while input must stay invisible, like a real password prompt. */
export function isSshRehearsalSecret(state: SshRehearsalState): boolean {
  return state.stage === "password";
}

export function sshRehearsalCommand(state: SshRehearsalState): string {
  return `ssh ${state.target}`;
}

function withLines(
  state: SshRehearsalState,
  lines: SshRehearsalLine[],
  patch: Partial<SshRehearsalState> = {},
): SshRehearsalState {
  return { ...state, ...patch, lines: [...state.lines, ...lines].slice(-MAX_LINES) };
}

/** SSH prints IPv6 hosts without the brackets used in `user@[addr]` targets. */
function bareHost(state: SshRehearsalState): string {
  return state.host.replace(/^\[|\]$/g, "");
}

function echo(state: SshRehearsalState, text: string): SshRehearsalLine {
  const prompt = sshRehearsalPrompt(state);
  return { kind: "input", text: text ? `${prompt} ${text}` : prompt };
}

function stepLocal(state: SshRehearsalState, command: string): SshRehearsalState {
  const input = echo(state, command);
  if (!command) return withLines(state, [input]);

  if (command === sshRehearsalCommand(state)) {
    return withLines(
      state,
      [
        input,
        {
          kind: "warning",
          text: `The authenticity of host '${bareHost(state)} (${bareHost(state)})' can't be established.`,
        },
        { kind: "output", text: `ED25519 key fingerprint is ${REHEARSAL_FINGERPRINT}.` },
        { kind: "output", text: "This key is not known by any other names." },
      ],
      { stage: "hostkey", hostKeyRetry: false, failedPasswords: 0 },
    );
  }

  return withLines(state, [
    input,
    { kind: "note", text: `In this practice, connect with: ${sshRehearsalCommand(state)}` },
  ]);
}

function stepHostKey(state: SshRehearsalState, answer: string): SshRehearsalState {
  const input = echo(state, answer);
  const normalized = answer.toLowerCase();

  if (normalized === "yes") {
    return withLines(
      state,
      [
        input,
        {
          kind: "output",
          text: `Warning: Permanently added '${bareHost(state)}' (ED25519) to the list of known hosts.`,
        },
        {
          kind: "note",
          text: "Next comes the password. Nothing appears while you type it; that's normal.",
        },
      ],
      { stage: "password", hostKeyRetry: false },
    );
  }

  if (normalized === "no") {
    return withLines(
      state,
      [
        input,
        { kind: "error", text: "Host key verification failed." },
        {
          kind: "note",
          text: "Answering no stops the connection. Run the ssh command again and type yes.",
        },
      ],
      { stage: "local", hostKeyRetry: false },
    );
  }

  const lines: SshRehearsalLine[] = [input];
  if (normalized === "y") {
    lines.push({ kind: "note", text: 'SSH needs the whole word "yes", not just "y".' });
  }
  return withLines(state, lines, { hostKeyRetry: true });
}

function stepPassword(state: SshRehearsalState, password: string): SshRehearsalState {
  // Echo the prompt only: a real terminal shows nothing for typed passwords.
  const input = echo(state, "");

  if (!password) {
    const failedPasswords = state.failedPasswords + 1;
    if (failedPasswords >= MAX_PASSWORD_ATTEMPTS) {
      return withLines(
        state,
        [
          input,
          { kind: "error", text: `${state.target}: Permission denied (publickey,password).` },
          {
            kind: "note",
            text: "Three wrong passwords end the attempt. Run the ssh command again to retry.",
          },
        ],
        { stage: "local", failedPasswords: 0 },
      );
    }
    return withLines(
      state,
      [input, { kind: "error", text: "Permission denied, please try again." }],
      { failedPasswords },
    );
  }

  return withLines(
    state,
    [
      input,
      { kind: "output", text: "Welcome to Ubuntu 24.04 LTS (GNU/Linux x86_64)" },
      {
        kind: "note",
        text: "You're in. The prompt now ends in #, so you're root on the VPS. Check where you are with hostname.",
      },
    ],
    { stage: "remote", failedPasswords: 0 },
  );
}

function stepRemote(state: SshRehearsalState, command: string): SshRehearsalState {
  const input = echo(state, command);

  switch (command) {
    case "":
      return withLines(state, [input]);
    case "hostname":
      return withLines(
        state,
        [
          input,
          { kind: "output", text: REHEARSAL_HOSTNAME },
          {
            kind: "success",
            text: "That's the VPS's name, not your laptop's. Everything you type now runs on the VPS.",
          },
        ],
        { checkedHostname: true },
      );
    case "whoami":
      return withLines(state, [input, { kind: "output", text: "root" }]);
    case "exit":
    case "logout":
      return withLines(
        state,
        [
          input,
          { kind: "output", text: "logout" },
          { kind: "output", text: `Connection to ${bareHost(state)} closed.` },
          { kind: "success", text: "Back on your laptop. That's the whole first login." },
        ],
        { stage: "done" },
      );
    default:
      return withLines(state, [
        input,
        {
          kind: "note",
          text: `This practice terminal only knows: ${REMOTE_COMMANDS.join(", ")}.`,
        },
      ]);
  }
}

/** Advance the rehearsal by one submitted line of input. */
export function stepSshRehearsal(state: SshRehearsalState, rawInput: string): SshRehearsalState {
  if (state.stage === "password") {
    return stepPassword(state, rawInput);
  }

  const input = rawInput.trim().replace(/\s+/g, " ");
  switch (state.stage) {
    case "local":
      return stepLocal(state, input);
    case "hostkey":
      return stepHostKey(state, input);
    case "remote":
      return stepRemote(state, input);
    default:
      return withLines(state, [
        echo(state, input),
        { kind: "note", text: "Practice complete. Use Restart to go through it again." },
      ]);
  }
}
