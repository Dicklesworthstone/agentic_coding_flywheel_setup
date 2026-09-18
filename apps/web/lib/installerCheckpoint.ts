/** Bind a wizard acknowledgement to one host, exact command, and catalogue snapshot.
 * This is a user acknowledgement, NOT proof that the remote installer succeeded.
 * Raw command/host values remain in memory; only the opaque key is persisted.
 */
export interface InstallerCheckpointInput {
  command: string;
  host: string;
  manifestSha256: string;
  checksumsYamlSha256: string;
}

export interface InstallerCheckpoint extends InstallerCheckpointInput {
  persistKey: string;
}

const CHECKPOINT_DOMAIN = "acfs.installer-acknowledgement.v1";
const KEY_PREFIX = "run-flywheel-installer-v2-";

export async function createInstallerCheckpoint(
  input: InstallerCheckpointInput,
): Promise<InstallerCheckpoint> {
  if (!input || typeof input.command !== "string" || !input.command.trim()
      || input.command.length > 65_536 || input.command.includes("\0")
      || typeof input.host !== "string" || !input.host.trim() || input.host.length > 256
      || /[\x00-\x20\x7f]/.test(input.host)
      || typeof input.manifestSha256 !== "string" || !/^[a-f0-9]{64}$/.test(input.manifestSha256)
      || typeof input.checksumsYamlSha256 !== "string" || !/^[a-f0-9]{64}$/.test(input.checksumsYamlSha256)) {
    throw new Error("A complete installer context is required for acknowledgement");
  }
  // Capture before the asynchronous digest: caller mutation must not associate
  // an old digest with a newer command or host in the returned value.
  const snapshot = {
    command: input.command,
    host: input.host,
    manifestSha256: input.manifestSha256,
    checksumsYamlSha256: input.checksumsYamlSha256,
  };
  if (!globalThis.crypto?.subtle) {
    throw new Error("Secure browser hashing is unavailable for installer acknowledgement");
  }
  const bytes = new TextEncoder().encode(JSON.stringify([CHECKPOINT_DOMAIN,
    snapshot.command, snapshot.host, snapshot.manifestSha256, snapshot.checksumsYamlSha256]));
  const digest = await globalThis.crypto.subtle.digest("SHA-256", bytes);
  const hex = Array.from(new Uint8Array(digest), (value) => value.toString(16).padStart(2, "0")).join("");
  return Object.freeze({ ...snapshot, persistKey: `${KEY_PREFIX}${hex}` });
}

/** Query placeholders or late async results may belong to the previous context. */
export function installerCheckpointMatches(
  checkpoint: InstallerCheckpoint | undefined,
  input: InstallerCheckpointInput | null,
): checkpoint is InstallerCheckpoint {
  return Boolean(checkpoint && input
    && checkpoint.command === input.command && checkpoint.host === input.host
    && checkpoint.manifestSha256 === input.manifestSha256
    && checkpoint.checksumsYamlSha256 === input.checksumsYamlSha256
    && new RegExp(`^${KEY_PREFIX}[a-f0-9]{64}$`).test(checkpoint.persistKey));
}

export interface DoctorCheckpointInput extends InstallerCheckpointInput {
  /** The health command itself; command above remains the exact install context. */
  doctorCommand: string;
}
export interface DoctorCheckpoint extends DoctorCheckpointInput {
  persistKey: string;
}
const DOCTOR_KEY_PREFIX = "flywheel-doctor-v2-";

/** A doctor's acknowledgement cannot substitute for running the installer (or vice versa). */
export async function createDoctorCheckpoint(input: DoctorCheckpointInput): Promise<DoctorCheckpoint> {
  if (!input || typeof input.doctorCommand !== "string" || !input.doctorCommand.trim()
      || input.doctorCommand.length > 65_536 || input.doctorCommand.includes("\0")) {
    throw new Error("A complete doctor context is required for acknowledgement");
  }
  const snapshot = { ...input };
  // Reuse the existing validated immutable installation snapshot, including
  // caller-mutation protection, without reusing its acknowledgement identity.
  const installation = await createInstallerCheckpoint(snapshot);
  const bytes = new TextEncoder().encode(JSON.stringify([
    "acfs.doctor-acknowledgement.v1", installation.persistKey, snapshot.doctorCommand,
  ]));
  const digest = await globalThis.crypto.subtle.digest("SHA-256", bytes);
  const hex = Array.from(new Uint8Array(digest), (value) => value.toString(16).padStart(2, "0")).join("");
  return Object.freeze({ command: installation.command, host: installation.host,
    manifestSha256: installation.manifestSha256, checksumsYamlSha256: installation.checksumsYamlSha256,
    doctorCommand: snapshot.doctorCommand, persistKey: `${DOCTOR_KEY_PREFIX}${hex}` });
}

export function doctorCheckpointMatches(
  checkpoint: DoctorCheckpoint | undefined,
  input: DoctorCheckpointInput | null,
): checkpoint is DoctorCheckpoint {
  return Boolean(checkpoint && input && checkpoint.command === input.command
    && checkpoint.host === input.host && checkpoint.manifestSha256 === input.manifestSha256
    && checkpoint.checksumsYamlSha256 === input.checksumsYamlSha256
    && checkpoint.doctorCommand === input.doctorCommand
    && new RegExp(`^${DOCTOR_KEY_PREFIX}[a-f0-9]{64}$`).test(checkpoint.persistKey));
}

/**
 * Shared navigation checks the currently rendered, hydrated control only.
 * A legacy storage boolean or an acknowledgement from an unmounted page must
 * not unlock a new install. This is UI acknowledgement, not remote evidence.
 */
export function isRenderedCheckpointComplete(
  kind: "installer" | "doctor",
  root: Pick<Document, "querySelectorAll"> | undefined = typeof document === "undefined" ? undefined : document,
): boolean {
  if (!root) return false;
  const prefix = kind === "installer" ? KEY_PREFIX : kind === "doctor" ? DOCTOR_KEY_PREFIX : null;
  if (!prefix) return false;
  try {
    const controls = root.querySelectorAll(`[data-acfs-completion-key^="${prefix}"]`);
    if (controls.length !== 1) return false;
    const control = controls[0];
    if (!new RegExp(`^${prefix}[a-f0-9]{64}$`).test(control.getAttribute("data-acfs-completion-key") ?? "")
        || control.hasAttribute("disabled") || control.hasAttribute("data-disabled")
        || control.getAttribute("aria-disabled") === "true"
        || control.closest('[hidden], [inert], [aria-hidden="true"]')) return false;
    return control.getAttribute("data-state") === "checked"
      || (control.tagName === "INPUT" && (control as HTMLInputElement).type === "checkbox"
        && (control as HTMLInputElement).checked === true);
  } catch { return false; }
}
