/** Linux target-user execution of an already reviewed, freshly rebuilt plan. */
import { createHash, randomUUID } from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import { constants, closeSync, fchmodSync, fstatSync, fsyncSync, lstatSync, mkdirSync,
  openSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { get } from 'node:https';
import { userInfo } from 'node:os';
import { dirname, isAbsolute, join, resolve, sep } from 'node:path';
import type { PluginInstallAction, PluginInstallPlan, PluginPlanTarget } from './plugin-plan.js';

export class PluginInstallError extends Error {
  constructor(public readonly code: string, message: string) { super(message); this.name = 'PluginInstallError'; }
}
function refuse(code: string, message: string): never { throw new PluginInstallError(code, message); }
const hash = (bytes: Uint8Array): string => createHash('sha256').update(bytes).digest('hex');
const MAX_INSTALLER_BYTES = 8 * 1024 * 1024;
const MAX_STAGED_BYTES = 32 * 1024 * 1024;
export interface PluginRuntimeOptions {
  /** Library/test seam only; the CLI always uses the operating system account home. */
  home?: string;
  timeoutSeconds?: number;
  signal?: AbortSignal;
  /** Trusted transport seam. Every returned byte buffer is independently hash-checked here. */
  download?: (action: PluginInstallAction, signal: AbortSignal) => Promise<Buffer>;
}
interface ActionState { status: 'pending' | 'running' | 'complete' | 'failed'; exitCode: number | null }
export interface PluginInstallReceipt {
  schema: 'acfs.plugin-install-receipt.v1';
  planSha256: string;
  packageSha256: string;
  status: 'pending' | 'running' | 'complete' | 'failed';
  updatedAt: string;
  actions: Record<string, ActionState>;
  /** Only this protocol can prove live orphan installers still exclude a retry. */
  executionProtocol?: 'inherited-lock-v1';
}

/** Parse OS-owned release metadata as data, never as shell code. */
export function parsePluginHostRelease(text: string): { os: string; version: string } {
  const values = new Map<string, string>();
  for (const line of text.split('\n')) {
    const match = /^(ID|VERSION_ID)=(?:"([a-z0-9_.-]+)"|'([a-z0-9_.-]+)'|([a-z0-9_.-]+))$/.exec(line);
    if (!match) continue;
    if (values.has(match[1]!)) refuse('plugin_host_unsupported', 'Duplicate operating-system identity fields');
    values.set(match[1]!, match[2] ?? match[3] ?? match[4]!);
  }
  if (!values.has('ID') || !values.has('VERSION_ID')) refuse('plugin_host_unsupported', 'Operating-system identity is unavailable');
  return { os: values.get('ID')!, version: values.get('VERSION_ID')! };
}
export function detectPluginInstallTarget(): PluginPlanTarget {
  if (process.platform !== 'linux') refuse('plugin_host_unsupported', 'Plugin execution currently requires Linux');
  const arch = process.arch === 'x64' ? 'x86_64' : process.arch === 'arm64' ? 'aarch64' : '';
  const report = process.report.getReport() as { header?: { glibcVersionRuntime?: string } };
  if (!arch || !report.header?.glibcVersionRuntime) refuse('plugin_host_unsupported', 'Plugin execution requires a supported glibc architecture');
  let text: string;
  try { text = readFileSync('/etc/os-release', 'utf8'); }
  catch { return refuse('plugin_host_unsupported', 'Operating-system identity could not be read'); }
  return { ...parsePluginHostRelease(text), arch, libc: 'glibc' };
}
function checkTarget(expected: PluginPlanTarget): void {
  const actual = detectPluginInstallTarget();
  if (actual.os !== expected.os || actual.version !== expected.version
      || actual.arch !== expected.arch || actual.libc !== expected.libc) {
    refuse('plugin_target_unsupported', 'Execution host does not match the reviewed target tuple');
  }
  if (typeof process.getuid !== 'function' || process.getuid() === 0
      || typeof process.geteuid !== 'function' || process.geteuid() !== process.getuid()) {
    refuse('plugin_root_execution_refused', 'Run plugin installs directly as the target user, never through sudo');
  }
}
function environment(home: string): NodeJS.ProcessEnv {
  return { HOME: home, USER: userInfo().username, LOGNAME: userInfo().username,
    PATH: `${home}/.local/bin:${home}/.bun/bin:${home}/.cargo/bin:${home}/go/bin:/usr/local/bin:/usr/bin:/bin`,
    LANG: 'C.UTF-8', LC_ALL: 'C.UTF-8', TMPDIR: '/tmp', SHELL: '/bin/bash' };
}
function assertDirectory(path: string, privateDirectory: boolean): void {
  const stat = lstatSync(path);
  if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid!()
      || (stat.mode & (privateDirectory ? 0o077 : 0o022)) !== 0) {
    refuse('plugin_state_unsafe', 'Plugin state requires real, user-owned directories without unsafe permissions');
  }
}
function stateDirectory(home: string): string {
  if (!isAbsolute(home) || resolve(home) !== home || /[\x00-\x1f\x7f:]/.test(home)) {
    refuse('plugin_state_unsafe', 'Target-user home must be a canonical absolute path');
  }
  // Reject symlinked ancestors before the first mkdir, including a symlinked home.
  let current: string = sep;
  for (const part of home.split(sep).filter(Boolean)) {
    current = join(current, part);
    const stat = lstatSync(current);
    if (!stat.isDirectory() || stat.isSymbolicLink()) refuse('plugin_state_unsafe', 'Target-user home has an unsafe path component');
  }
  assertDirectory(home, false);
  for (const part of ['.acfs', 'plugin-installs']) {
    current = join(current, part);
    try { mkdirSync(current, { mode: 0o700 }); }
    catch (error) { if ((error as NodeJS.ErrnoException).code !== 'EEXIST') throw error; }
    assertDirectory(current, part === 'plugin-installs');
  }
  return current;
}
function safeFile(path: string, flags: number): number {
  const fd = openSync(path, flags | constants.O_NOFOLLOW | constants.O_NONBLOCK, 0o600);
  const stat = fstatSync(fd);
  if (!stat.isFile() || stat.nlink !== 1 || stat.uid !== process.getuid!() || (stat.mode & 0o077) !== 0) {
    closeSync(fd); refuse('plugin_state_unsafe', 'Plugin state file has an unsafe type, owner, links, or permissions');
  }
  return fd;
}
function writeReceipt(directory: string, receipt: PluginInstallReceipt): void {
  assertDirectory(dirname(directory), false);
  assertDirectory(directory, true);
  const target = join(directory, `${receipt.planSha256}.json`);
  try { const fd = safeFile(target, constants.O_RDONLY); closeSync(fd); }
  catch (error) { if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error; }
  receipt.updatedAt = new Date().toISOString();
  const temp = join(directory, `.receipt-${randomUUID()}.tmp`);
  const fd = safeFile(temp, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL);
  try { writeFileSync(fd, JSON.stringify(receipt) + '\n'); fchmodSync(fd, 0o600); fsyncSync(fd); }
  finally { closeSync(fd); }
  renameSync(temp, target);
  const directoryFd = openSync(directory, constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW);
  try { fsyncSync(directoryFd); } finally { closeSync(directoryFd); }
}
function readReceipt(directory: string, plan: PluginInstallPlan): PluginInstallReceipt {
  let fd: number;
  try { fd = safeFile(join(directory, `${plan.planSha256}.json`), constants.O_RDONLY); }
  catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
    return { schema: 'acfs.plugin-install-receipt.v1', planSha256: plan.planSha256,
      packageSha256: plan.package.pluginSha256, status: 'pending', updatedAt: new Date().toISOString(),
      actions: Object.fromEntries(plan.actions.map((action) => [action.id, { status: 'pending', exitCode: null }])) };
  }
  let data: PluginInstallReceipt;
  try {
    if (fstatSync(fd).size > 1024 * 1024) refuse('plugin_state_invalid', 'Plugin receipt exceeds its size budget');
    data = JSON.parse(readFileSync(fd, 'utf8')) as PluginInstallReceipt;
  } catch { return refuse('plugin_state_invalid', 'Plugin receipt is malformed; existing state was preserved'); }
  finally { closeSync(fd); }
  const statuses = new Set(['pending', 'running', 'complete', 'failed']);
  if (!data || data.schema !== 'acfs.plugin-install-receipt.v1' || data.planSha256 !== plan.planSha256
      || data.packageSha256 !== plan.package.pluginSha256 || !statuses.has(data.status)
      || !data.actions || Array.isArray(data.actions) || typeof data.actions !== 'object'
      || Object.keys(data.actions).sort().join(',') !== plan.actions.map((action) => action.id).sort().join(',')
      || Object.values(data.actions).some((action) => !action || !statuses.has(action.status)
        || (action.exitCode !== null && (!Number.isInteger(action.exitCode) || action.exitCode < 0 || action.exitCode > 255))
        || (action.status === 'complete' && action.exitCode !== 0))) {
    return refuse('plugin_state_invalid', 'Plugin receipt does not match the reviewed execution plan');
  }
  if (Object.values(data.actions).some((action) => action.status === 'running')) {
    refuse('plugin_install_interrupted', 'An interrupted installer has uncertain effects; inspect its receipt and processes before retrying');
  }
  return data;
}

interface ExecutionLease {
  fd: number;
  assertHeld: () => void;
  release: () => void;
}

/**
 * flock locks the shared open-file description, not a pathname or helper PID.
 * Keep our descriptor open and pass it to ALL execution children. Never unlock
 * explicitly: surviving descendants must exclude new work after parent death.
 */
function acquireLock(directory: string, env: NodeJS.ProcessEnv): ExecutionLease {
  const path = join(directory, 'install.lock');
  const fd = safeFile(path, constants.O_RDWR | constants.O_CREAT);
  let released = false;
  const release = (): void => { if (!released) { released = true; closeSync(fd); } };
  const assertHeld = (): void => {
    if (released) refuse('plugin_lock_failed', 'Plugin execution lease is closed');
    assertDirectory(dirname(directory), false);
    assertDirectory(directory, true);
    const opened = fstatSync(fd);
    const current = lstatSync(path);
    if (!current.isFile() || current.isSymbolicLink() || current.dev !== opened.dev
        || current.ino !== opened.ino || current.nlink !== 1 || current.uid !== process.getuid!()
        || (current.mode & 0o077) !== 0) {
      refuse('plugin_lock_failed', 'Plugin execution lock changed; existing receipts were preserved');
    }
  };
  try {
    const result = spawnSync('/usr/bin/flock', ['--exclusive', '--nonblock', '--conflict-exit-code', '73', '3'],
      { env, stdio: ['ignore', 'ignore', 'ignore', fd], timeout: 5000 });
    if (result.error || result.status !== 0) {
      refuse(result.status === 73 ? 'plugin_install_busy' : 'plugin_lock_failed',
        'Another install owns the lock, or system locking is unavailable');
    }
    assertHeld();
    return { fd, assertHeld, release };
  } catch (error) { release(); throw error; }
}

/** Strict TLS, bounded redirects, a total deadline, and bounded response bytes. */
export async function downloadPluginInstaller(action: PluginInstallAction, signal: AbortSignal): Promise<Buffer> {
  const deadline = Date.now() + 60_000;
  const visit = async (address: string, redirects: number): Promise<Buffer> => {
    const url = new URL(address);
    if (url.protocol !== 'https:' || url.username || url.password || url.hash || redirects > 5) {
      return refuse('plugin_download_refused', 'Installer redirect or URL violates HTTPS policy');
    }
    const remaining = deadline - Date.now();
    if (remaining <= 0) return refuse('plugin_download_failed', 'Installer download exceeded its deadline');
    return new Promise((accept, reject) => {
      const fail = (): void => reject(new PluginInstallError('plugin_download_failed', 'Installer download failed or exceeded its bounds'));
      const request = get(url, { agent: false, rejectUnauthorized: true, signal,
        headers: { 'User-Agent': 'ACFS-plugin-installer', 'Accept-Encoding': 'identity' } }, (response) => {
        if ([301, 302, 303, 307, 308].includes(response.statusCode ?? 0)) {
          const location = response.headers.location;
          response.destroy();
          if (!location) { fail(); return; }
          try { visit(new URL(location, url).href, redirects + 1).then(accept, reject); }
          catch { fail(); }
          return;
        }
        if (response.statusCode !== 200 || (response.headers['content-encoding'] && response.headers['content-encoding'] !== 'identity')) {
          response.destroy(); fail(); return;
        }
        const chunks: Buffer[] = []; let size = 0;
        response.on('data', (chunk: Buffer) => {
          size += chunk.length;
          if (size > MAX_INSTALLER_BYTES) { response.destroy(); fail(); } else chunks.push(chunk);
        });
        response.once('end', () => {
          if (!response.complete || size === 0) { fail(); return; }
          const bytes = Buffer.concat(chunks);
          if (hash(bytes) !== action.installer.sha256) {
            reject(new PluginInstallError('plugin_installer_hash_mismatch', 'Downloaded installer does not match canonical checksums'));
          } else accept(bytes);
        });
        response.once('error', fail);
        response.once('aborted', fail);
      });
      const timer = setTimeout(() => request.destroy(new Error('deadline')), remaining);
      request.once('close', () => clearTimeout(timer));
      request.once('error', fail);
    });
  };
  return visit(action.installer.url, 0);
}

/** Execute script bytes over stdin so another installer cannot swap a staged path. */
async function command(executable: string, args: string[], home: string, seconds: number,
  signal: AbortSignal, lease: ExecutionLease, input?: Buffer): Promise<number> {
  signal.throwIfAborted();
  lease.assertHeld();
  return new Promise((accept, reject) => {
    // no-new-privs prevents setuid/file-capability elevation through execve.
    // A new session bounds group cleanup to this command, never the caller.
    const child = spawn('/usr/bin/timeout', ['--signal=TERM', '--kill-after=2s', `${seconds}s`,
      '/usr/bin/setpriv', '--no-new-privs', executable, ...args],
    { cwd: home, env: environment(home), detached: true, stdio: ['pipe', 'ignore', 'ignore', lease.fd] });
    const groupSignal = (value: NodeJS.Signals | 0): boolean => {
      if (!child.pid) return false;
      try { process.kill(-child.pid, value); return true; }
      catch (error) {
        if ((error as NodeJS.ErrnoException).code === 'ESRCH') return false;
        throw new PluginInstallError('plugin_cleanup_failed', 'Could not stop the installer process group');
      }
    };
    let escalation: ReturnType<typeof setTimeout> | undefined;
    const cancel = (): void => {
      try { groupSignal('SIGTERM'); }
      catch (error) { reject(error); }
      escalation ??= setTimeout(() => {
        try { groupSignal('SIGKILL'); } catch (error) { reject(error); }
      }, 2000);
    };
    signal.addEventListener('abort', cancel, { once: true });
    if (signal.aborted) cancel();
    child.once('error', () => reject(new PluginInstallError('plugin_execution_failed', 'Required system execution tools are unavailable')));
    child.once('close', async (code) => {
      signal.removeEventListener('abort', cancel);
      if (escalation) clearTimeout(escalation);
      try {
        const lingering = groupSignal(0);
        if (lingering) {
          groupSignal('SIGTERM');
          await new Promise<void>((done) => setTimeout(done, 2000));
          groupSignal('SIGKILL');
        }
        // An entrypoint that abandons children is not a successful installer.
        accept(signal.aborted ? 130 : code === 0 && lingering ? 125 : code ?? 1);
      } catch (error) { reject(error); }
    });
    child.stdin!.on('error', () => { /* Early exit may close stdin; exit status is authoritative. */ });
    child.stdin!.end(input);
  });
}
async function verify(action: PluginInstallAction, home: string, signal: AbortSignal, lease: ExecutionLease): Promise<boolean> {
  for (const executable of action.verify) {
    if (await command('/bin/bash', ['-p', '-c', 'command -v -- "$1" >/dev/null 2>&1', 'acfs-plugin-check', executable], home, 15, signal, lease) !== 0) return false;
  }
  return true;
}

/** Never accepts a plan file: production callers rebuild this from trusted inputs. */
export async function executePluginInstallPlan(plan: PluginInstallPlan, options: PluginRuntimeOptions = {}): Promise<PluginInstallReceipt> {
  checkTarget(plan.target);
  const { planSha256, ...payload } = plan;
  if (!/^[a-f0-9]{64}$/.test(planSha256) || hash(Buffer.from(JSON.stringify(payload))) !== planSha256) {
    refuse('plugin_plan_changed', 'Execution plan changed after validation');
  }
  const seconds = options.timeoutSeconds ?? 900;
  if (!Number.isInteger(seconds) || seconds < 1 || seconds > 3600) refuse('plugin_timeout_invalid', 'Installer timeout must be between 1 and 3600 seconds');
  const home = options.home ?? userInfo().homedir;
  const directory = stateDirectory(home);
  const lock = await acquireLock(directory, environment(home));
  const signal = options.signal ?? new AbortController().signal;
  try {
    const state = readReceipt(directory, plan);
    const save = (): void => { signal.throwIfAborted(); lock.assertHeld(); writeReceipt(directory, state); };
    signal.throwIfAborted();
    for (const prerequisite of plan.prerequisites) {
      for (const check of prerequisite.verify) {
        if (await command('/bin/bash', ['-p', '-c', check], home, 30, signal, lock) !== 0) {
          refuse('plugin_prerequisite_missing', `First-party prerequisite failed verification: ${prerequisite.id}`);
        }
      }
    }
    const pending: PluginInstallAction[] = [];
    for (const action of plan.actions) {
      if (state.actions[action.id]!.status !== 'complete' || !await verify(action, home, signal, lock)) {
        state.actions[action.id] = { status: 'pending', exitCode: null }; pending.push(action);
      }
    }
    const scripts = new Map<string, Buffer>(); let totalBytes = 0;
    for (const action of pending) {
      signal.throwIfAborted();
      const bytes = await (options.download ?? downloadPluginInstaller)(action, signal);
      if (bytes.length < 1 || bytes.length > MAX_INSTALLER_BYTES || hash(bytes) !== action.installer.sha256) {
        refuse('plugin_installer_hash_mismatch', 'Installer bytes do not match the reviewed canonical digest');
      }
      totalBytes += bytes.length;
      if (totalBytes > MAX_STAGED_BYTES) refuse('plugin_download_refused', 'Selected installers exceed the total staging budget');
      scripts.set(action.id, Buffer.from(bytes));
    }
    // No installer runs until all pending entrypoint bytes have been verified.
    state.executionProtocol = 'inherited-lock-v1';
    state.status = 'running'; save();
    for (const action of pending) {
      state.actions[action.id] = { status: 'running', exitCode: null }; save();
      const code = await command(action.installer.runner === 'bash' ? '/bin/bash' : '/bin/sh',
        ['-p', '-s', '--', ...action.installer.args], home, seconds, signal, lock, scripts.get(action.id));
      scripts.delete(action.id);
      const passed = code === 0 && !signal.aborted && await verify(action, home, signal, lock);
      state.actions[action.id] = { status: passed ? 'complete' : 'failed', exitCode: passed ? 0 : code || 1 };
      if (!passed) state.status = 'failed';
      // A lost lock must never let a stale writer alter another owner's receipt.
      lock.assertHeld(); writeReceipt(directory, state);
      if (!passed) refuse('plugin_install_failed', `Plugin installer or verification failed: ${action.id}`);
    }
    for (const action of plan.actions) {
      if (!await verify(action, home, signal, lock)) {
        state.actions[action.id] = { status: 'failed', exitCode: 1 }; state.status = 'failed'; save();
        refuse('plugin_verification_failed', `Final plugin verification failed: ${action.id}`);
      }
    }
    state.status = 'complete'; save();
    return state;
  } finally { await lock.release(); }
}
