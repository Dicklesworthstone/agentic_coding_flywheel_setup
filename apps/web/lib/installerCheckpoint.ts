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
