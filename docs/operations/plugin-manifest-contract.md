# ACFS Plugin Manifest Contract

This document defines the v1 plugin package schema and trust policy for future
ACFS plugin support. It is a design contract for maintainers and for the
validator implementation that follows it.

Plugins are not a second installer language. A plugin can describe installable
modules, static assets, support metadata, and documentation, but it cannot lower
the trust requirements that first-party modules already follow.

## Goals

- Keep executable behavior behind explicit, reviewable capability gates.
- Preserve `checksums.yaml` as the trust root for any `verified_installer`
  module.
- Make module ID collisions, dependency collisions, and generated Bash function
  collisions deterministic validation errors.
- Keep module selection, offline packs, doctor checks, and web metadata derived
  from one validated plugin graph.
- Refuse secrets, host-specific state, and unreviewed shell behavior before any
  plugin module is merged into the ACFS manifest.

## Non-Goals

- v1 does not support arbitrary Bash snippets from third-party packages.
- v1 does not support compatibility shims for deprecated manifest fields.
- v1 does not allow plugins to edit generated files directly.
- v1 does not allow plugins to overwrite first-party ACFS module IDs.
- v1 does not provide a credential vault or hosted plugin marketplace.

## Package Layout

Use one top-level directory before compression:

```text
acfs-plugin-package/
+-- plugin.json
+-- README.md
+-- LICENSE
+-- assets/
|   +-- <asset-id>/
+-- docs/
|   +-- <doc-file>.md
+-- provenance/
    +-- <attestation-file>.json
```

Compressed packages should use `tar.gz` first because ACFS installer and offline
pack tooling already depend on GNU tar. Consumers must reject archives with
absolute paths, `..` path traversal, duplicate paths, unsafe symlinks, files not
declared in `plugin.json`, or any file outside the single
`acfs-plugin-package/` root.

## Manifest Schema

`plugin.json` is JSON so the eventual Bash and TypeScript validators can share
fixtures without YAML parser drift.

```json
{
  "schema": "acfs.plugin-package.v1",
  "schemaVersion": 1,
  "packageId": "example.tools",
  "displayName": "Example Tools",
  "version": "1.2.3",
  "description": "Installable ACFS modules for Example Tools.",
  "publisher": {
    "name": "Example Maintainers",
    "contactUrl": "https://example.com/security",
    "sourceUrl": "https://github.com/example/acfs-plugin-example"
  },
  "license": "Apache-2.0",
  "docsUrl": "https://example.com/acfs-plugin-example",
  "provenance": {
    "generatedAt": "2026-05-08T00:00:00Z",
    "sourceRef": "main",
    "sourceCommit": "0123456789abcdef0123456789abcdef01234567",
    "acfsManifestVersion": 1
  },
  "targets": [
    {
      "os": "ubuntu",
      "versions": ["25.10"],
      "arch": ["x86_64", "aarch64"],
      "libc": ["glibc"]
    }
  ],
  "capabilities": {
    "allowed": ["verified_installer", "release_artifact", "copy_asset", "doctor_check", "web_metadata"],
    "reviewRequired": ["root_run_as", "systemd_user_service"],
    "disallowed": ["arbitrary_shell", "secret_values"]
  },
  "modules": [
    {
      "id": "plugin.example_tools.cli",
      "description": "Example command-line tool.",
      "category": "tools",
      "phase": 6,
      "run_as": "target_user",
      "optional": false,
      "enabled_by_default": true,
      "dependencies": ["lang.bun"],
      "install": {
        "kind": "verified_installer",
        "tool": "example_tools",
        "url": "https://example.com/install.sh",
        "runner": "bash",
        "args": [],
        "env": []
      },
      "verify": [{ "kind": "command_exists", "command": "example" }],
      "docs_url": "https://example.com/acfs-plugin-example/cli",
      "web": {
        "display_name": "Example CLI",
        "short_name": "Example",
        "visible": true,
        "short_desc": "Example plugin module."
      }
    }
  ],
  "offline": {
    "bundlingPolicy": "metadata_only",
    "liveAuthRequired": false,
    "providerInteractionRequired": false
  },
  "extensions": {}
}
```

Unknown top-level fields are allowed only under `extensions`. Unknown fields
inside `modules`, `install`, `capabilities`, `targets`, `offline`, or
`provenance` must not change validation decisions.
External plugin documentation and web metadata links must use HTTPS; plugin web
metadata may also use a site-relative path beginning with `/`.

## Required Fields

Every v1 plugin package must include:

- `schema: "acfs.plugin-package.v1"` and `schemaVersion: 1`
- `packageId`, `displayName`, `version`, `description`, `publisher`, `license`
- `provenance.generatedAt`, `provenance.sourceRef`,
  `provenance.sourceCommit`, and `provenance.acfsManifestVersion`
- at least one `targets[]` entry with `os`, `versions`, `arch`, and `libc`
- `capabilities.allowed`, `capabilities.reviewRequired`, and
  `capabilities.disallowed`
- at least one `modules[]` entry; documentation-only packages are not supported
  in v1
- one `offline` block describing bundling and live-interaction behavior

Every module must include:

- `id` using the `plugin.<package_slug>.<module_name>` namespace
- `description`, `category`, `phase`, `run_as`, `optional`,
  `enabled_by_default`
- `install.kind` and the fields required by that install kind
- at least one declarative `verify[]` check
- `docs_url`

## Module ID And Merge Rules

Plugin module IDs are merged into the first-party manifest only after the full
package validates. Merge is all-or-nothing.

- Plugin IDs must match `plugin.<package_slug>.<module_name>`, using only
  lowercase letters, digits, underscores, and dots so the ID also satisfies the
  first-party manifest schema.
- `packageId` must normalize to the same `<package_slug>` used in every module
  ID. Normalization lowercases the package ID and replaces non-alphanumeric
  runs with a single underscore.
- A plugin module must not reuse any first-party ACFS module ID.
- A plugin module must not reuse any module ID from another loaded plugin.
- Dependencies may reference first-party IDs or IDs from the same plugin
  package. Cross-plugin dependencies are review-required in v1.
- Generated Bash function names use the same `install_<module_id_with_dots_as_underscores>`
  rule as first-party modules. Any generated function collision is a validation
  error.
- A plugin cannot alter first-party module fields, default selection, phase,
  verification commands, or web metadata.
- A plugin cannot replace or shadow `checksums.yaml`, `acfs.manifest.yaml`,
  `scripts/generated/*`, or any first-party source file.

## Allowed Capabilities

Allowed capabilities are still fail-closed. A package can request only the
capabilities it uses, and the validator must reject undeclared capability use.

| Capability | Meaning |
| --- | --- |
| `verified_installer` | Run a HTTPS installer only when it has a matching `checksums.yaml` entry and an allowed runner. |
| `release_artifact` | Download or consume an exact release artifact by URL and sha256, then place files through a declarative copy rule. |
| `copy_asset` | Copy static package assets into ACFS-owned plugin locations. |
| `manual_step` | Show a documented manual action without executing host changes. |
| `web_metadata` | Add wizard/doctor display metadata for validated modules. |
| `doctor_check` | Add declarative, non-mutating verification checks that report status only. |

## Install Kinds

`install.kind` is one of:

- `verified_installer`: requires `tool`, HTTPS `url`, `runner` of `bash` or
  `sh`, and optional script `args`. `fallback_url` is forbidden. V1 accepts
  only an empty `env` array and forbids the `--` runner-option delimiter;
  otherwise shell startup variables or runner flags could execute code before
  the checksum-verified installer file. Future environment support needs an
  explicit per-installer allowlist.
- `release_artifact`: requires HTTPS `url`, `sha256`, `targetPath`,
  `assetId`, and a declarative `mode`. Extraction cannot write outside the
  plugin-owned target root.
- `copy_asset`: requires `assetId`, `sourcePath`, `targetPath`, and `mode`.
  Source paths must reference files declared in `plugin.json`.
- `manual_step`: requires `summary`, `docs_url`, and `blocking`. It cannot
  provide shell commands.

The current normalized-manifest emitter implements only `verified_installer`.
The validator checks the reserved `release_artifact`, `copy_asset`, and
`manual_step` shapes but refuses activation with `plugin_disallowed_behavior`
until their dedicated executors exist. It must never normalize one of those
kinds into an empty successful install.

Raw shell arrays, heredocs, command templates, `eval`, process substitution,
remote command strings, and inline scripts are not valid v1 install kinds.

`verify[]` is also declarative. V1 currently supports only
`{ "kind": "command_exists", "command": "<bare executable name>" }`, which
normalizes to a non-mutating executable lookup. Raw verification shell strings
are rejected.

## Review-Required Capabilities

The validator must surface these as `plugin_review_required` and refuse
automatic enablement unless a maintainer review record is supplied:

- `root_run_as` or any `run_as: "root"` or `run_as: "current"` module; the
  current installer process commonly has root authority
- `systemd_user_service` or `systemd_system_service`
- package manager repository configuration, including APT sources and keys
- PATH, shell startup, tmux, git config, SSH config, or sudoers changes
- local daemons, socket listeners, browser extensions, or background workers
- provider account interaction, OAuth/device-login steps, or cloud resource
  creation
- cross-plugin dependencies
- writes outside ACFS-owned plugin directories
- modules that must be required by default for a profile

Review records must name reviewer, reviewed package version, reviewed source
commit, capabilities approved, and expiration. A review cannot approve a
different package hash.

## Disallowed Behavior

These must be refused with `plugin_disallowed_behavior` before merge:

- arbitrary shell, inline scripts, command templates, or `curl | bash` outside
  `verified_installer`
- `verified_installer.fallback_url`
- HTTP installer URLs or disabled TLS verification
- unsigned release artifacts or missing sha256 values
- deletion, recursive cleanup, destructive rollback, or overwrite semantics
  outside the explicitly declared plugin target files
- modifying first-party source, generated files, `checksums.yaml`, or
  `acfs.manifest.yaml`
- setuid/setgid, Linux capabilities, kernel modules, privileged containers, or
  host firewall rewrites
- secrets, tokens, cookies, SSH private keys, API keys, passwords, Vault root
  tokens, credential helper databases, or session stores
- obfuscated payloads, base64 command payloads, self-modifying installers, or
  network-loaded executable code not represented by a checksum

## Relationship To `checksums.yaml`

`checksums.yaml` remains the runtime source of truth for
`verified_installer`. A plugin can request a new verified installer key, but it
cannot provide its own trusted checksum database.

- `verified_installer.tool` must match an entry in `checksums.yaml` before the
  module can be installable.
- `verified_installer.url` must equal the URL for that key in `checksums.yaml`.
- The checksum entry must have a valid 64-character sha256.
- New or changed checksum entries must be produced only through
  `./scripts/lib/security.sh --update-checksums`.
- If the checksum is missing, malformed, stale, or URL-mismatched, report
  `plugin_verified_installer_checksum_required` and refuse install output.

## Compatibility With Module Selection

Plugin modules participate in the same resolver as first-party modules after
validation.

- Required first-party modules stay locked and cannot be disabled by plugins.
- `enabled_by_default` controls only the plugin module default, not first-party
  defaults.
- Dependency closure can add plugin modules only when the source module is
  selected and the dependency is validated.
- `--no-deps` must not allow an install plan that violates required plugin
  dependencies.
- Profile exports must record plugin package ID, version, package hash, selected
  plugin modules, and skipped plugin modules.
- Profile imports must show plugin additions, removals, dependency closure, and
  review-required capabilities in dry-run output before any command is emitted.

## Compatibility With Offline Packs

Offline pack planning must treat plugin artifacts with the same policy as
first-party modules.

- `offline.bundlingPolicy` is one of `bundled`, `metadata_only`,
  `live_required`, or `prohibited`.
- Bundled plugin artifacts must be listed in the offline pack `manifest.json`
  with module ID, package ID, package version, artifact sha256, and package
  provenance.
- `verified_installer` modules remain bound to `checksums.yaml`.
- A fully offline install must refuse selected plugin modules marked
  `metadata_only`, `live_required`, or `prohibited`.
- Plugin packages must not bundle credentials, local host state, OAuth sessions,
  provider account state, or mutable cache directories.
- Offline consumers must reject plugin package hashes that do not match profile
  or pack provenance.

## Trust Model

A plugin package is trusted only after all verification steps pass. The
compressed-package digest is external to `plugin.json`: embedding the final
archive hash inside a file contained by that archive would be self-referential.
The consumer must calculate the exact archive SHA-256 and compare it with an
independently trusted digest from a profile, offline pack, or maintainer review
record.

1. The archive extracts to exactly one `acfs-plugin-package/` root without path
   traversal, unsafe symlinks, duplicate paths, or undeclared files.
2. `plugin.json` parses as v1 JSON and contains all required fields.
3. The calculated compressed-package SHA-256 matches the independently trusted
   expected digest.
4. The target Ubuntu version, architecture, and libc match one of `targets[]`.
5. Every requested capability is declared and either allowed or backed by an
   unexpired maintainer review record.
6. Every module ID, generated function name, dependency, phase, and category is
   valid after merging with the first-party manifest.
7. Every `verified_installer` entry matches `checksums.yaml`.
8. Every artifact URL uses HTTPS and has a valid sha256.
9. No forbidden field name or secret-looking value appears anywhere in the
   package manifest, docs metadata, provenance, or module metadata.
10. Offline policy is compatible with the requested install mode.

The consumer must fail closed. A plugin validation warning can prevent automatic
enablement even when the package is otherwise readable.

## Forbidden Field And Value Checks

Validators must scan field names and string values recursively before exposing
plugin-derived command output.

Forbidden field names include:

```text
token apiKey api_key secret password passphrase privateKey private_key
clientSecret client_secret refreshToken refresh_token accessToken access_token
cookie session vaultRootToken vault_root_token sshPrivateKey ssh_private_key
```

Forbidden value patterns include:

- PEM or OpenSSH private-key blocks
- GitHub, Stripe, OpenAI, Anthropic, Google, Cloudflare, Vercel, Supabase, and
  provider token shapes
- `Bearer <credential>` style header values
- raw IPv4 or IPv6 addresses outside documentation examples
- raw hostnames, provider account IDs, cookies, and session identifiers
- `secret://` values outside explicitly declared secret-slot references

Plugins are not a credential vault. If a plugin needs credentials, it must use a
documented `manual_step` or a first-party ACFS secret-slot flow in a later
schema version.

## Error Codes

Stable validator codes:

| Code | Meaning |
| --- | --- |
| `plugin_schema_unsupported` | `schema` or `schemaVersion` is not supported. |
| `plugin_missing_required_field` | A required package or module field is absent. |
| `plugin_unknown_top_level_field` | Unknown package data appears outside `extensions`. |
| `plugin_archive_layout_invalid` | Archive layout, path, symlink, duplicate, or undeclared file check failed. |
| `plugin_package_hash_mismatch` | The calculated package hash is absent, malformed, or differs from the independently trusted digest. |
| `plugin_target_unsupported` | Target OS, Ubuntu version, architecture, or libc is unsupported. |
| `plugin_module_id_invalid` | Module ID does not match the plugin namespace. |
| `plugin_module_collision` | A module ID collides with first-party or plugin modules. |
| `plugin_generated_function_collision` | Generated Bash function name collides with another module or reserved name. |
| `plugin_dependency_invalid` | Dependency is missing, cyclic, cross-plugin without review, or phase-invalid. |
| `plugin_capability_undeclared` | A module uses a capability absent from `capabilities`. |
| `plugin_review_required` | Requested behavior needs maintainer review before enablement. |
| `plugin_disallowed_behavior` | Package requested behavior v1 never permits. |
| `plugin_verified_installer_checksum_required` | `verified_installer` is missing or mismatched in `checksums.yaml`. |
| `plugin_artifact_hash_required` | Release artifact has no valid sha256. |
| `plugin_secret_material_refused` | Manifest, metadata, or provenance contains secret-looking material. |
| `plugin_offline_policy_incompatible` | Offline policy cannot satisfy the selected install mode. |

## Validator Requirements

The validator must:

- parse and validate `plugin.json` before reading executable artifacts
- return machine-readable JSON with error code, path, module ID when available,
  severity, and redacted context
- validate the package in isolation before merge, then validate the merged graph
- reuse existing manifest validation for dependency existence, cycles, phase
  ordering, generated function names, reserved names, and verified installers
- emit a dry-run plan before any installer command includes plugin modules
- redact values before writing support bundles or logs
- preserve deterministic ordering for errors, merged modules, web metadata, and
  offline pack entries

## Maintainer Review Requirements

Review records are local-first JSON documents stored outside plugin packages.
A valid review record must include:

- `reviewSchema: "acfs.plugin-review.v1"`
- `packageId`, `version`, `pluginSha256`, and reviewed `sourceCommit`
- reviewer name or handle
- `approvedCapabilities[]`
- `approvedModules[]`
- `expiresAt`
- rationale for every review-required capability

The review record can grant review-required capabilities, but it cannot grant
disallowed behavior or bypass checksum, package-hash, target, secret, archive,
dependency, or collision checks.

## Support And Redaction

Support bundles may include plugin package IDs, versions, selected module IDs,
validation codes, review-required capability names, and hashes. They must not
include raw package docs, raw provenance files, hostnames, IP addresses, account
IDs, tokens, cookies, private keys, passwords, or unredacted installer output.

When plugin validation fails, support output should include:

- package ID and version
- package hash prefix, not the full hash unless explicitly requested
- validation codes and redacted paths
- target OS, Ubuntu version, and architecture
- whether module selection or offline planning triggered the failure
- the safest next command or documentation link

## Example Validation Flow

```text
read archive -> validate layout -> parse plugin.json -> scan for secrets
-> validate package schema -> validate target -> validate capabilities
-> validate checksums/artifacts -> merge candidate graph
-> run manifest validators -> resolve module selection -> produce dry-run plan
```

No installer command should include plugin modules until the dry-run plan has no
errors and no unresolved review-required capabilities.
