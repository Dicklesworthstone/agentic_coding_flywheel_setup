# Inspect module binaries before running them

The architecture auditor reads Linux ELF headers for x86_64 and ARM64. It does
not run binaries, wrappers, `--version`, `ldd`, an installer, or a network probe.
Use it to find wrong-platform artifacts before installation, or incompatible
executables already occupying a managed bin directory.

From a trusted, complete checkout with Bun:

```bash
cd packages/manifest
bun run architecture:audit -- --only agents.claude,stack.rch --json
bun run architecture:audit -- --arch arm64 --binary stack.rch=/path/to/rch --json
```

The module identities, command names, optional/default flags, and provenance
come from the existing manifest generator's outputs. There is no independently
maintained tool catalogue. Regenerate normally after changing the manifest.
The auditor is a checkout command, not a newly installed `acfs` subcommand.

`--only` accepts exact comma-separated IDs and can be repeated. `--binary` binds
a module to a particular downloaded binary; repeated bindings for one module
are refused. Explicit artifacts do not have to be executable yet. Without
`--only`, artifact bindings imply exactly their own scope. Without either flag,
the report includes every canonical module, including modules with no declared
single CLI. Artifact overrides outside an explicitly selected scope are errors.

For installed-command inspection, lookup visits the selected home's
`.local/bin`, `.bun/bin`, and `.cargo/bin`, then PATH. `--home` changes the home;
`--path` replaces PATH (absolute directories only). The first executable wins,
even if incompatible. A later compatible copy cannot mask a broken managed
installation. Ordinary executable symlinks are followed; special files are not
consumed. No PATH candidate or artifact is executed.

## Evidence and exit codes

JSON uses schema `acfs.architecture-audit.v1` and includes ordered per-module
results, the target architecture, catalogue hashes, the evidence source, and
whether the local ELF interpreter was checked. `amd64`/`x64` and `arm64` are
normalized to `x86_64` and `aarch64`. Unknown architectures are rejected, never
silently treated as x86_64. A non-Linux host needs an explicit `--arch`.

Exit **0** means every selected candidate has matching, structurally accepted
ELF headers. Exit **1** means an incompatible, missing, or unreadable candidate.
Exit **2** means invalid arguments/catalogue or an auditor error. Exit **3**
means incomplete evidence without a detected blocker: script wrappers,
unrecognized formats, or modules without single-CLI metadata remain unknown.
Optional status is exposed, not permission to hide a requested failure.

The parser bounds header tables, integer offsets, segment ranges, and ELF
interpreter strings without reading executable payloads. Matching-host inspection
also checks that a declared ELF interpreter exists as an executable regular
file. Cross-target inspection does not infer loader availability from the
machine running the audit. A shell/Node wrapper remains unknown because its
selected native payload cannot be determined safely by executing it.

**Matching headers are not release certification.** This report does not verify
CPU extensions, glibc versions, shared libraries, authentication, functionality,
upstream artifact signatures, or a full fresh-host installation. It cannot tell
whether a binary was downloaded or source-built. Explicit artifact-to-module
bindings are operator selections, not proof that a particular upstream release
produced those bytes. No absent evidence is promoted into a native/source-build
support promise. The broader `bd-wqrgy` architecture certification work still
needs per-release and real-host evidence.

## Regression tests

```bash
cd packages/manifest
bun test src/binary-architecture.test.ts src/architecture-audit.test.ts
```

Tests cover both machine types, truncated and malformed ELF structures, bounded
reads, interpreter handling, executable symlinks, inert wrappers, ambiguous
catalogues, stable selection, path precedence, exit codes, and real system ELF
inspection without launching it. These are parser/filesystem tests, not ARM64
VM execution or full-installer certification.
