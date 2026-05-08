# Offline Artifact Pack Manifest And Trust Policy

This note records the `bd-8woeg` design for verified ACFS offline artifact
packs. It is a contract for later builder and installer-consumer beads; it does
not describe current installer behavior.

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
    "commit": "0123456789abcdef0123456789abcdef01234567",
    "manifestSha256": "<sha256 of acfs.manifest.yaml>",
    "checksumsSha256": "<sha256 of checksums.yaml>",
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
- `acfs.version`, `acfs.sourceRef`, `acfs.commit`, `acfs.manifestSha256`,
  `acfs.checksumsSha256`, `acfs.generatedIndexSha256`
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

## Consumer Requirements

Future installer consumers must:

- verify the pack before reading any executable artifact
- copy or execute only files represented in `manifest.json`
- refuse live fallback in `networkMode: "offline"`
- keep normal `checksums.yaml` verification enabled
- report stable error codes from this document
- continue to run existing preflight checks for OS, shell, disk, user, and
  required local tools

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
