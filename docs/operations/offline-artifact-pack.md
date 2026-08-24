# Verified Installer Entrypoint Cache

<!-- CURRENT-CONTRACT:BEGIN -->

This section is the authoritative contract for the cache that ACFS currently
builds and consumes. The historical full-offline design is retained below only
as a superseded proposal for future work.

## Capability Boundary

The v1 cache contains the checksum-reviewed **entrypoint script** for each
selected `verified_installer` module. Selecting the cache makes acquisition of
those entrypoint bytes fail closed: ACFS either validates and stages the exact
cached script or refuses the module without attempting a live entrypoint
download.

This is **not an offline or air-gapped installation bundle**. An accepted
entrypoint can still download release archives, packages, repositories, or
registry payloads when it runs. Bootstrap archives, apt metadata and packages,
Git repositories, language registries, OAuth/device flows, provider actions,
and other transitive dependencies are not bundled. The target machine therefore
still needs network access for normal installer execution.

The cache has one deliberately narrow guarantee:

> The first executable bytes fetched for a cached `verified_installer` module
> are the same HTTPS URL and SHA-256-approved bytes recorded in the current
> `checksums.yaml`; they are read from the selected cache, not from the network.

## Public Interface

Build the cache on a connected, trusted machine:

```bash
acfs installer-cache build --output /tmp/acfs-cache
acfs installer-cache build --output /tmp/acfs-cache --module stack.rch
acfs installer-cache build --dry-run --json
```

`--module` is repeatable. With no `--module`, the builder selects every manifest
module with valid `verified_installer` metadata. The output directory must be
empty and receives exactly one `acfs-installer-cache/` child.

Select that cache during installation with either the flag or its environment
equivalent:

```bash
./install.sh \
  --verified-installer-cache /tmp/acfs-cache/acfs-installer-cache \
  --yes --mode vibe

ACFS_VERIFIED_INSTALLER_CACHE=/tmp/acfs-cache/acfs-installer-cache \
  ./install.sh --yes --mode vibe
```

The selected path may name `acfs-installer-cache/` itself or its immediate
parent. If neither the flag nor `ACFS_VERIFIED_INSTALLER_CACHE` is set, verified
installers retain their normal live-download behavior. If a cache is explicitly
selected, a missing, malformed, expired, incompatible, incomplete, or tampered
cache is terminal for that verified installer. An explicitly selected cache has
no live entrypoint fallback.

There are no legacy offline-mode aliases in this contract. In particular, the
cache does not imply that execution is network-free.

## Directory Layout

The published directory is:

```text
acfs-installer-cache/
├── manifest.json
├── checksums.yaml
├── acfs.manifest.yaml
├── VERSION
├── artifacts/
│   └── <module-id>/
│       └── <tool>-install.sh
└── provenance/
    ├── builder-env.json
    └── source-index.json
```

The builder writes a private, same-parent staging directory, writes
`manifest.json` last as the acceptance marker, and publishes with a no-clobber
rename. It refuses a non-empty output directory. A successful build never
merges into or replaces an existing cache.

`--best-effort` is diagnostic only. If any selected entrypoint cannot be
acquired and verified, the emitted manifest uses `packMode: "diagnostic"` and
contains failure records. The installer accepts only a complete
`entrypoint-cache` manifest with an empty `failures` array.

## Manifest And Policy Contract

The current manifest is JSON with these fixed identity and policy values:

```json
{
  "schema": "acfs.verified-installer-entrypoint-cache.v1",
  "schemaVersion": 1,
  "generatedBy": "acfs installer-cache build",
  "packMode": "entrypoint-cache",
  "packScope": "verified_installer_entrypoints",
  "targets": [
    {"os": "ubuntu", "version": "25.10", "architecture": "x86_64"}
  ],
  "failures": [],
  "policy": {
    "entrypointFetchMode": "cache_required",
    "executionNetworkMode": "required",
    "transitiveClosure": "not_bundled",
    "bootstrap": "not_bundled",
    "verifiedInstallerPolicy": "must_match_checksums_yaml",
    "partialPackPolicy": "refuse_unless_best_effort_diagnostic"
  }
}
```

The full manifest also records generation and expiry timestamps, the expiry
window, ACFS version and source provenance, hashes of the packed
`acfs.manifest.yaml`, `checksums.yaml`, and both provenance files, plus a
one-to-one mapping between modules and artifacts. Each module must have
`coverage: "entrypoint_cached"`. Each artifact must have kind
`verified_installer_entrypoint`, its HTTPS source URL, verified-installer key,
SHA-256, byte size, and architecture.

The only supported target OS is Ubuntu. A cache names exactly one Ubuntu
version and one architecture (`x86_64` or `aarch64`); the consumer requires an
exact match with the target host. An entrypoint is limited to 16 MiB.

## Trust And Consumption Rules

`checksums.yaml` remains the canonical trust boundary. The builder does not
mint new trust: it copies the current manifest and checksum inputs, downloads
only HTTPS URLs represented by a unique checksum key, and verifies each
download before publication. The consumer independently requires all of the
following before returning executable bytes:

1. `manifest.json` is a contained, regular, readable file with the supported
   schema, fixed policy values, complete module/artifact cardinality, and no
   duplicate identities or paths.
2. The manifest has not expired, and its single Ubuntu version and architecture
   match the host.
3. The packed and currently installed `checksums.yaml` are identical to the
   manifest hash.
4. The packed and currently installed `acfs.manifest.yaml` are identical to the
   manifest hash.
5. Both bounded provenance files match their declared hashes.
6. Exactly one contained, regular artifact matches the requested checksum key,
   HTTPS URL, SHA-256, and architecture.
7. A bounded private snapshot of that artifact matches both its declared size
   and SHA-256 before the snapshot path is returned for execution.

Paths containing traversal segments, backslashes, control characters, query
strings, fragments, or URL user-info are rejected. Manifest, checksum,
provenance, and artifact reads are bounded. Cache files are executable supply
chain material and must be transported and stored with the same care as the
original installers.

Stable refusal classes currently include:

| Code | Meaning |
| --- | --- |
| `pack_missing_manifest` | The selected cache has no readable acceptance marker. |
| `pack_malformed_manifest` | Structure, fixed policy, identity, or bound metadata is invalid. |
| `pack_schema_unsupported` | Cache schema or schema version is unsupported. |
| `pack_expired` | The cache has passed `expiresAt`. |
| `pack_arch_unsupported` | The host architecture does not match the cache. |
| `pack_ubuntu_unsupported` | The host is not the exact cached Ubuntu version. |
| `pack_path_escape` | A selected path is unsafe or resolves outside the cache. |
| `pack_hash_mismatch` | Entrypoint bytes or size do not match the manifest. |
| `pack_checksums_mismatch` | Current trust-root bytes, URL, or approved SHA-256 do not match. |
| `pack_unbundled_required_module` | The requested entrypoint is absent or the cache is diagnostic/incomplete. |

## Test Boundary

Builder and consumer fixture tests must include a complete-cache success case
and mutation-sensitive refusals for malformed schemas, diagnostic/failure
manifests, duplicate identities and paths, missing module coverage, target
mismatch, expired timestamps, trust-root drift, provenance drift, path escape,
oversized files, and artifact hash/size mismatch. Every explicit-cache refusal
must assert both zero live entrypoint fetches and empty executable stdout.

Those tests prove entrypoint-cache behavior only. A network-enabled test cannot
prove an offline install merely because the entrypoint itself came from disk.

## Future True-Offline Work

A future air-gapped bundle is a separate capability and must not reuse the v1
cache name or imply that `executionNetworkMode` is anything but `required`.
Before such a mode can be advertised, it needs all of the following:

- a resolved transitive artifact graph for every selected module, including
  bootstrap bytes, apt repository snapshots and packages, release archives,
  Git objects, and language-registry payloads;
- a closed-world inventory binding every archive member and execution input to
  an independently reviewed digest, with safe extraction and no undeclared,
  special, duplicate, or escaping paths;
- explicit `bundled`, `metadata_only`, `live_required`, and `prohibited`
  classifications for credentials, OAuth/device login, provider interaction,
  mutable host state, and artifacts that cannot be redistributed;
- secret scanning and support-output redaction that never package keys, tokens,
  cookies, sessions, hostnames, IP addresses, or credential stores; and
- a mutation-sensitive end-to-end install run with outbound networking denied,
  proving both success from the bundle and failure when any required transitive
  artifact is removed or changed.

Until those requirements are implemented and observed, ACFS must describe this
feature only as a verified installer entrypoint cache.

<!-- CURRENT-CONTRACT:END -->

<details>
<summary>Historical full-offline proposal (superseded; not current behavior or a public CLI contract)</summary>

## Superseded Full-Offline Design (`bd-8woeg`)

Everything below this point is preserved as design history. Names, schemas,
commands, environment variables, layouts, and guarantees below are not current
interfaces and must not be used to describe the v1 entrypoint cache.

## Purpose

ACFS already supports limited offline/cache checks during preflight, and the
bootstrap tests can stage a local copy of ACFS scripts. A full artifact pack is
different: it is a user-provided bundle of upstream installer scripts, release
archives, generated ACFS assets, and provenance metadata that lets the installer
work when the target machine has weak or no network access.

Offline mode is only safe if ACFS can prove exactly what is inside the pack. The
pack manifest must be explicit enough for a future `acfs artifact-pack verify`
command and an installer consumer to make the same decision without contacting
an upstream provider.

The pack answers:

> Which exact bytes may the installer use instead of live downloads, where did
> they come from, which ACFS modules do they satisfy, and when must the pack be
> rejected as stale, incomplete, unsupported, or untrusted?

## Non-Goals

- It is not a package mirror for apt, Homebrew, npm, crates.io, or GitHub as a
  whole. The pack contains only explicitly listed artifacts.
- It is not a credentials bundle. Tokens, passwords, SSH private keys, provider
  API keys, browser cookies, Vault root tokens, and local hostnames are refused.
- It is not a provider automation bundle. VPS creation, payment, DNS ownership,
  OAuth device flows, and cloud login flows still require live user action.
- It does not weaken verified installers. A packed artifact must match the same
  policy ACFS would enforce online.
- It does not replace `checksums.yaml`; it references and extends it with
  per-pack artifact hashes.

## Pack Layout

Use a single top-level directory before compression:

```text
acfs-offline-pack/
├── manifest.json
├── checksums.yaml
├── acfs.manifest.yaml
├── VERSION
├── scripts/
│   ├── lib/
│   └── generated/
├── acfs/
├── artifacts/
│   └── <module-id>/
│       └── <artifact-file>
└── provenance/
    ├── builder-env.json
    └── source-index.json
```

Compressed packs should use `tar.gz` first because the installer and offline
bootstrap tests already rely on GNU tar. The archive must contain exactly one
top-level `acfs-offline-pack/` directory. Consumers must reject archives with
absolute paths, `..` path traversal, symlinks escaping the pack root, duplicate
manifest entries, or files not represented in `manifest.json`.

## Manifest Schema

`manifest.json` is JSON so installer scripts can validate it with `jq`.

```json
{
  "schema": "acfs.offline-artifact-pack.v1",
  "schemaVersion": 1,
  "generatedBy": "acfs-artifact-pack-builder",
  "generatedAt": "2026-05-08T00:00:00Z",
  "expiresAt": "2026-06-07T00:00:00Z",
  "staleAfterDays": 30,
  "acfs": {
    "version": "0.0.0-dev",
    "sourceRef": "main",
    "sourceCommit": "0123456789abcdef0123456789abcdef01234567",
    "manifestSha256": "<sha256 of acfs.manifest.yaml>",
    "checksumsYamlSha256": "<sha256 of checksums.yaml>",
    "generatedIndexSha256": "<sha256 of scripts/generated/manifest_index.sh>"
  },
  "targets": [
    {
      "os": "ubuntu",
      "versions": ["25.10", "24.04"],
      "arch": "x86_64",
      "libc": "glibc"
    }
  ],
  "modules": [
    {
      "id": "lang.bun",
      "phase": 6,
      "category": "languages",
      "bundlingPolicy": "bundled",
      "liveAuthRequired": false,
      "providerInteractionRequired": false,
      "artifacts": ["bun-install-script"]
    }
  ],
  "artifacts": [
    {
      "id": "bun-install-script",
      "moduleId": "lang.bun",
      "kind": "verified_installer_script",
      "path": "artifacts/lang.bun/install.sh",
      "sourceUrl": "https://bun.sh/install",
      "resolvedUrl": "https://bun.sh/install",
      "version": "1.3.13",
      "sha256": "<sha256 of artifacts/lang.bun/install.sh>",
      "sizeBytes": 12345,
      "mediaType": "text/x-shellscript",
      "executable": false,
      "verifiedInstallerKey": "bun",
      "checksumsYamlSha256": "<sha256 recorded for bun in checksums.yaml>",
      "license": "unknown",
      "platform": {
        "os": "linux",
        "arch": "x86_64"
      }
    }
  ],
  "policy": {
    "networkMode": "offline",
    "failClosed": true,
    "allowLiveFallback": false,
    "allowUnsignedArtifacts": false,
    "allowSecrets": false,
    "pathTraversalAllowed": false,
    "verifiedInstallerPolicy": "must_match_checksums_yaml"
  }
}
```

Unknown top-level fields are allowed only under `extensions`. Unknown fields
inside `modules`, `artifacts`, or `policy` must be ignored by old consumers but
must not change validation decisions.

## Required Fields

Every v1 pack manifest must include:

- `schema`, `schemaVersion`, `generatedBy`, `generatedAt`, `expiresAt`,
  `staleAfterDays`
- `acfs.version`, `acfs.sourceRef`, `acfs.sourceCommit`,
  `acfs.manifestSha256`, `acfs.checksumsYamlSha256`,
  `acfs.generatedIndexSha256`
- at least one `targets[]` entry with `os`, `versions`, `arch`, and `libc`
- one `modules[]` entry for every ACFS manifest module the pack claims to cover
- one `artifacts[]` entry for every packed file under `artifacts/`
- `policy.failClosed: true`, `policy.allowLiveFallback: false`,
  `policy.allowSecrets: false`, and
  `policy.verifiedInstallerPolicy: "must_match_checksums_yaml"`

## Artifact Fields

Each artifact entry must record:

- stable `id`
- `moduleId` matching an ACFS manifest module id
- `kind`: `verified_installer_script`, `release_archive`, `release_binary`,
  `generated_acfs_file`, `metadata`, or `operator_note`
- relative `path` inside the pack
- HTTPS `sourceUrl` and final `resolvedUrl`
- exact `version` or `sourceRef`
- `sha256`, `sizeBytes`, and `mediaType`
- `platform.os` and `platform.arch` when platform-specific
- `verifiedInstallerKey` and `checksumsYamlSha256` when the artifact
  corresponds to a `checksums.yaml` entry
- dependency artifact ids if the file is unusable by itself

Artifact paths must be normalized POSIX paths. Consumers must reject absolute
paths, empty path segments, `.` segments, `..` segments, backslashes, and paths
outside `artifacts/`, `scripts/`, `acfs/`, `provenance/`, or the explicit root
files in the layout section.

## Bundling Policy

`modules[].bundlingPolicy` is one of:

| Policy | Meaning |
| --- | --- |
| `bundled` | All required bytes for this module are in the pack and validated. |
| `metadata_only` | The pack documents expected online work but provides no install bytes. |
| `live_required` | The module cannot complete without live network or user auth. |
| `prohibited` | The module must never be bundled because it would include secrets or unstable local state. |

The builder may bundle:

- ACFS scripts, generated installer files, `acfs/` config assets, `VERSION`, and
  `acfs.manifest.yaml`
- verified upstream installer scripts listed in `checksums.yaml`
- GitHub release archives or binaries when the release publishes a checksum or
  when ACFS records a reviewed sha256 in the pack manifest
- static documentation needed by the installer or support bundle

The builder must mark these as `live_required` or `metadata_only` unless a later
bead adds a stronger mirror policy:

- apt packages and apt repository metadata
- Bun/npm global packages
- Cargo, Go, uv, pip, and other language registry downloads
- OAuth/device-login steps for Claude Code, Codex CLI, Gemini CLI, Cloudflare,
  Supabase, Vercel, GitHub, Vault, or provider consoles
- provider VPS creation, payment, DNS, and identity-verification steps

The builder must mark these as `prohibited`:

- SSH private keys, API tokens, cookies, session stores, credential helper
  databases, Vault root tokens, provider account ids when not redacted, and
  local machine hostnames
- generated logs or support bundles that have not passed ACFS redaction
- mutable cache directories whose contents are not individually hashed

## Trust Model

The pack is trusted only after all verification steps pass:

1. The archive extracts to exactly one `acfs-offline-pack/` root without path
   traversal or unsafe symlinks.
2. `manifest.json` parses as v1 JSON and contains all required fields.
3. `manifest.json` has not expired (`expiresAt`) and is not older than
   `staleAfterDays`.
4. The target Ubuntu version and architecture match one of `targets[]`.
5. `acfs.manifest.yaml`, `checksums.yaml`, and generated manifest indexes match
   the hashes declared under `acfs`.
6. Every file in `artifacts/`, `scripts/`, `acfs/`, and `provenance/` has a
   manifest entry or is an allowed root metadata file.
7. Every artifact hash and size matches its manifest entry.
8. Every `verified_installer_script` matches both its artifact sha256 and the
   corresponding `checksums.yaml` sha256.
9. Every claimed module is either fully `bundled` or explicitly marked
   `metadata_only`, `live_required`, or `prohibited`.
10. No scalar value in the manifest or provenance files matches secret-looking
    patterns or forbidden field names.

The consumer must fail closed. It must not silently fall back to live downloads
unless the operator requested a separate online mode outside this pack policy.

## Relationship To `checksums.yaml`

`checksums.yaml` remains the canonical trust root for `verified_installer`
entries. A pack can include a copy of `checksums.yaml`, but it cannot weaken it:

- If an artifact has `verifiedInstallerKey`, its `checksumsYamlSha256` must equal
  the sha256 for that key in the packed `checksums.yaml`.
- If the packed `checksums.yaml` differs from the ACFS ref used by the
  installer, the installer must report a policy error unless the operator has
  explicitly pinned the same ref.
- If a module uses `verified_installer` in `acfs.manifest.yaml` but the pack has
  no matching artifact, the module is not offline installable.
- A pack builder may refresh checksums only through the canonical
  `./scripts/lib/security.sh --update-checksums` review flow. The pack manifest
  must record the resulting `checksums.yaml` hash.

This preserves the online installer guarantee: no upstream script runs unless
its bytes match a reviewed sha256.

## Compatibility Rules

Consumers must reject a pack with:

- unsupported `schemaVersion`
- target OS other than Ubuntu
- target Ubuntu version not listed in `targets[].versions`
- target architecture not listed in `targets[].arch`
- stale or expired manifest timestamps
- missing ACFS root files (`VERSION`, `acfs.manifest.yaml`, `checksums.yaml`,
  generated manifest index)
- module ids not present in `acfs.manifest.yaml`
- duplicate artifact ids or duplicate artifact paths
- required modules marked `metadata_only`, `live_required`, or `prohibited`
  when the install was requested as fully offline

Consumers may warn and continue when:

- a non-requested module is `live_required`
- optional support documentation is missing but all install artifacts pass
- the pack was generated by an older patch version with the same schemaVersion
  and all required fields still validate

## Error Codes

Future commands should use stable machine-readable reasons:

| Code | Meaning |
| --- | --- |
| `pack_missing_manifest` | `manifest.json` is absent or unreadable. |
| `pack_malformed_manifest` | `manifest.json` is not valid JSON. |
| `pack_schema_unsupported` | `schema` or `schemaVersion` is not supported. |
| `pack_expired` | `expiresAt` or `staleAfterDays` is exceeded. |
| `pack_arch_unsupported` | Target architecture is not listed. |
| `pack_ubuntu_unsupported` | Target Ubuntu version is not listed. |
| `pack_hash_mismatch` | A file hash or size does not match. |
| `pack_checksums_mismatch` | A verified installer does not match `checksums.yaml`. |
| `pack_path_escape` | Archive or manifest paths escape the pack root. |
| `pack_secret_material_refused` | Manifest/provenance includes secret-looking values. |
| `pack_unbundled_required_module` | Fully offline install requested a module not bundled. |
| `pack_live_auth_required` | A requested module requires live auth. |
| `pack_provider_interaction_required` | A requested module requires live provider action. |
| `pack_unknown_module` | Manifest references a module absent from `acfs.manifest.yaml`. |
| `pack_duplicate_artifact` | Duplicate artifact id or path. |

## Support And Redaction

Support-bundle output may include:

- pack schema, version, generation timestamp, expiry timestamp, and status
- ACFS version/ref/commit
- target OS and architecture
- module ids, artifact ids, hashes, sizes, and source URLs
- verification error codes and redacted messages

Support-bundle output must not include:

- private keys, provider tokens, OAuth tokens, passwords, cookies, Vault secrets,
  credential helper files, local usernames except the target ACFS username,
  raw hostnames, raw IP addresses, or unredacted provider account ids
- artifact file contents unless a future command explicitly emits a redacted,
  bounded excerpt

## Builder Requirements

Future pack builder commands must:

- generate `manifest.json` deterministically except for documented timestamps
- sort modules and artifacts by id
- record the exact ACFS source ref and commit
- compute sha256 after files are written into their final pack paths
- refuse dirty generated artifacts unless the operator explicitly points at a
  committed source tree
- print a summary with bundled, live-required, metadata-only, and prohibited
  module counts
- emit JSON output for CI and support

## Builder Command

`acfs offline-pack build` prepares `acfs-offline-pack/` from a connected
machine:

```bash
acfs offline-pack build --output /tmp/acfs-pack --module stack.rch
acfs offline-pack build --dry-run --json
```

The command resolves modules from `acfs.manifest.yaml`, includes only modules
with `verified_installer` metadata, reads source URLs and SHA256 values from
`checksums.yaml`, downloads each approved installer into `artifacts/`, verifies
the downloaded bytes, copies the local ACFS scripts/configuration needed for
offline verification, and writes `manifest.json`.

Default behavior is fail-closed: any missing checksum entry, unsupported module,
download failure, timeout, or hash mismatch aborts the pack. `--best-effort`
must be set explicitly to write a diagnostic pack with failure metadata.

## Consumer Requirements

Future installer consumers must:

- verify the pack before reading any executable artifact
- copy or execute only files represented in `manifest.json`
- refuse live fallback in `networkMode: "offline"`
- keep normal `checksums.yaml` verification enabled
- report stable error codes from this document
- continue to run existing preflight checks for OS, shell, disk, user, and
  required local tools

The installer accepts an extracted pack with:

```bash
./install.sh --offline-pack /path/to/acfs-offline-pack --yes --mode vibe
```

The equivalent environment contract is:

```bash
ACFS_OFFLINE_PACK=/path/to/acfs-offline-pack
ACFS_OFFLINE_NETWORK_MODE=offline
ACFS_OFFLINE_PACK_REQUIRED=true
```

When `ACFS_OFFLINE_PACK` is unset, verified installers keep the normal live
download behavior. When it is set, `verify_checksum` must prefer a matching
local artifact and fail closed for `ACFS_OFFLINE_NETWORK_MODE=offline`.

## Test Plan

The design bead pins this document with a policy conformance test that checks
for the manifest schema, required fields, layout, bundling policies,
`checksums.yaml` relationship, compatibility errors, redaction rules, and
builder/consumer requirements.

Implementation beads should add fixture tests for:

- valid minimal pack
- expired pack
- unsupported architecture
- missing required module artifact
- verified installer checksum mismatch
- path traversal attempt
- secret-looking manifest value
- fully offline request with `live_required` module

</details>
