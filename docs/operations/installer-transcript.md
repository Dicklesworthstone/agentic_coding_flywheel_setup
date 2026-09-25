# Explain a failed installer transcript locally

`acfs rescue --log-file PATH` provides an offline first-run diagnostic for an
installer transcript. It complements the existing checkpoint-based `acfs rescue`:
no credentials, provider request, telemetry, repair, or installed-state mutation
is required. The same command is available from a checkout:

```bash
bash scripts/lib/rescue.sh --log-file /path/to/install.log --json
acfs rescue --log-file /path/to/install.log
```

## What the report means

The analyzer reuses the installer's `errors.sh` pattern vocabulary and reports
recognized checksum/signature, host-key, disk, memory, package-lock, package-state,
network, TLS, permission, rate-limit, authentication, interrupted-upgrade and
tool failures. Repeated matches are grouped with occurrence counts and the last
matching line number. Trust failures rank ahead of subsequent generic failures.
A bare `Killed` is explicitly ambiguous, not proof of an out-of-memory kill.
A dpkg error is not presented as proof of database corruption.

`phase` and `module` are the last recognized context in the analyzed run, not
proof that a particular module caused a failure. Phase IDs come from the
installer's fixed vocabulary; module IDs come from its generated manifest index,
read as inert text. Unknown context is null rather than copied from the log.
Concatenated transcripts are analyzed from the final explicit
`=== ACFS Install Log ===` header. Without such a header, runs cannot reliably be
distinguished. A success footer is recorded separately and never erases failures
or establishes a healthy installation.

JSON uses `acfs.installer-transcript.v1`. Exit 1 means recognized evidence needs
attention; 0 means no recognized pattern was found, **not** successful installation;
2 means invalid input or an unavailable analyzer. The report always marks
`installation_verified: false`. A recognized pattern is advisory evidence, not
an independently verified root cause.

## Read-only guidance, not automatic repair

Each cause includes an explanation, a conservative next step and a fixed
`diagnostic_argv`. These commands are suggestions only. No command from the
transcript is parsed as executable input. In particular, the analyzer does not
remove package locks, rewrite host keys, kill processes, change ownership,
disable TLS, bypass checksums, reboot or run a downloaded script.

`retry.command` is null: a transcript alone cannot establish the original ref,
module selection, installer flags, checkpoint validity or current package locks.
Run `acfs rescue --json` to inspect saved state separately before selecting a
resume command. `acfs support-bundle` is offered separately; it is not run or
uploaded automatically. The older checkpoint mode and its explicit input flags
remain unchanged; mixing those flags with `--log-file` is rejected.

## Privacy and input limits

The report includes no raw log excerpts, input paths, arbitrary module names,
hostnames, account names, URLs, credentials or hashes of secret-bearing input.
It exposes only fixed diagnostic text, numeric counters and allowlisted context.
Both human and JSON errors omit offending argument values and filesystem paths.
ANSI styling and OSC hyperlink payloads are removed before pattern matching.

The default is a bounded 1 MiB tail. `--max-bytes N` accepts 1024 through 8388608.
When a tail cuts a line, that incomplete first line is discarded; lines over
65536 characters are omitted and counted. Earlier evidence can therefore be
missing. JSON states whether line numbers refer to the original file or only
the analyzed tail. Invalid UTF-8 is decoded with replacement rather than echoed.

The file must be regular and single-linked. Symlinked files or parent directories,
FIFOs, devices and directories are refused without following or blocking on them.
A file that changes during the read is refused. The analyzer never rewrites it.
Python 3 and the installed sibling `errors.sh` are required. It uses an isolated
system Python rather than a project-local interpreter or `PYTHONPATH` hooks.

## Verification

```bash
python3 -B tests/unit/test_installer_transcript.py -v
TARGET_USER="$(id -un)" bash tests/unit/test_rescue.sh
bash -n scripts/lib/rescue.sh
shellcheck scripts/lib/rescue.sh
```

The subprocess regressions exercise actual rescue and doctor routing, real
installer error-context formatting, bounded/malformed input, unsafe file types,
credential-bearing transcripts, inert log commands and unchanged checkpoint
behavior. They do not install packages or certify a live VPS bootstrap.
