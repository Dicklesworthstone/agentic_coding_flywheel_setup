# ACFS Plugin Validator Review Guide

> **Implementation status:** ACFS has a schema validator and pure generation
> seams for plugin-shaped fixtures. It does not yet have the archive loader,
> independent review-record lookup, target binding, profile integration, or
> activation planner required to trust a real package. This guide does not
> activate or install plugins.

This guide records the design-stage review contract and the checks exercised by
the validator tests. The generator deliberately refuses `--plugin`,
`--plugins-dir`, `ACFS_PLUGIN_PATHS`, and `ACFS_PLUGINS_DIR` inputs until the
missing trust bindings are implemented.

---

## 1. Overview & Trust Architecture

The future plugin loader must extend the declarative manifest without weakening
the first-party trust guarantees:

- **Fail-Closed by Default**: Untrusted or malformed plugin files are rejected before merge.
- **External Package Digest**: The compressed package digest (`expectedPackageSha256`) is independently trusted from a review record or pinned digest—never self-attested by the package itself.
- **Checksum Discipline**: Any `verified_installer` must match a canonical HTTPS URL and SHA-256 digest recorded in `checksums.yaml`.
- **Distinct Provenance Labeling**: Pure generator functions can tag validated
  fixtures in installer, manifest-index, doctor, and web output. Canonical ACFS
  artifacts do not currently contain activated plugin modules.

---

## 2. Maintainer Inspection Commands

There is no supported plugin activation command yet. The following commands
exercise the validator implementation and its static type boundary; they do not
establish package trust or write plugin-derived generated artifacts:

```bash
cd packages/manifest
bun test src/plugin.test.ts
bun run type-check
```

The generator's normal first-party validation remains available:

```bash
cd packages/manifest
bun run generate --validate
```

For research on a proposed verified-installer URL, maintainers may calculate a
remote digest and inspect the canonical checksum candidate. This is evidence
for a future review record, not plugin approval by itself:

```bash
# Calculate remote installer SHA-256
./scripts/lib/security.sh --checksum "https://example.com/install.sh"

# Review candidate checksums diff
./scripts/lib/security.sh --update-checksums > /tmp/acfs-checksums.candidate.yaml
diff -u checksums.yaml /tmp/acfs-checksums.candidate.yaml
```

An invocation such as `bun run generate --plugin ./plugin.json` must fail with
the explicit activation-unavailable diagnostic. A bare path cannot provide an
independently trusted archive digest, review decision, and target tuple.

---

## 3. Future Activation Review Checklist

These are acceptance criteria for the future archive/review loader. Completing
the manual checks today does not activate a package.

| Check | Requirement | Verification Command / Method |
|---|---|---|
| **1. Provenance** | `provenance.sourceCommit` and `sourceRef` correspond to an auditable Git commit in an authentic repository. | `git clone` or inspect commit log on remote repository. |
| **2. Trusted Hash** | Calculate the SHA-256 of the exact compressed package bytes and record it outside the package. | `sha256sum acfs-plugin-package.tar.gz` plus an external review record. |
| **3. Checksums Entry** | Every `verified_installer` tool matches an exact entry in `checksums.yaml`. | `grep -A 3 "^  <tool>:" checksums.yaml` |
| **4. Capabilities** | Declared `capabilities.allowed` match only the used capabilities (`verified_installer`, `doctor_check`, `web_metadata`). | Review `capabilities` block in `plugin.json`. |
| **5. No Review-Required** | No `root_run_as`, `systemd_user_service`, or cross-plugin dependency proceeds without an explicit, unexpired review record. | Inspect the proposed record; the activation command is not implemented. |
| **6. No Disallowed Logic** | No arbitrary shell strings, eval, `curl \| bash`, or network code execution outside `verified_installer`. | Inspect `install` and `verify` fields. |
| **7. No Secret Leakage** | No API keys, passwords, tokens, private keys, or host-specific IPs are present in metadata or docs. | Exercise `validatePluginPackage` with independently supplied validation options. |
| **8. Web & Status Surfaces** | Tool metadata includes clear descriptions and distinct plugin provenance. | Inspect pure generator output in `src/plugin.test.ts`; there is no activated production package. |

---

## 4. Status Surfaces & Distinct Labeling

The pure generator seams produce the following provenance surfaces from an
already validated fixture. These examples are unit-level design evidence, not
proof that the absent package loader established trust.

### Installer Category Libraries (`scripts/generated/install_<category>.sh`)
A fixture-derived install function includes the plugin package name and version in its header comment:
```bash
# Example command-line tool. [plugin: example.tools@1.2.3]
acfs_generated_install_plugin_example_tools_cli() {
    local module_id="plugin.example_tools.cli"
    acfs_require_contract "module:${module_id}" || return 1
    ...
}
```

### Manifest Index (`scripts/generated/manifest_index.sh`)
Fixture-derived Bash associative arrays carry provenance records:
```bash
declare -gA ACFS_MODULE_PLUGIN_PACKAGE=(
  ['plugin.example_tools.cli']="example.tools"
)

declare -gA ACFS_MODULE_PLUGIN_VERSION=(
  ['plugin.example_tools.cli']="1.2.3"
)

declare -gA ACFS_MODULE_PLUGIN_SHA256=(
  ['plugin.example_tools.cli']="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
)
```

### Web Tool Cards (`apps/web/app/tools/page.tsx`)
The tool-card component is prepared to display a badge when trusted plugin data
eventually reaches the canonical generated manifest:
```tsx
{tool.plugin && (
  <span
    className="inline-flex items-center gap-1 rounded-full bg-purple-500/20 px-2 py-0.5 text-xs font-medium text-purple-300 border border-purple-500/30"
    title={`Plugin package: ${tool.plugin.packageId} (v${tool.plugin.version})`}
  >
    Plugin: {tool.plugin.packageId}
  </span>
)}
```

---

## 5. Examples

### Safe Plugin Schema Fixture

This JSON exercises the schema validator when the test supplies a synthetic
target, actual digest, independently expected digest, first-party manifest, and
installer checksum map. It is not a standalone trusted package or a file that
the generator can activate.

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
      "arch": ["x86_64"],
      "libc": ["glibc"]
    }
  ],
  "capabilities": {
    "allowed": ["verified_installer", "doctor_check", "web_metadata"],
    "reviewRequired": ["root_run_as", "cross_plugin_dependency", "default_enabled_module"],
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
      "enabled_by_default": false,
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
        "tagline": "A high-performance example CLI tool",
        "visible": true,
        "cli_name": "example"
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

---

### Rejected Plugin Examples & Diagnostic Codes

#### 1. Package Hash Mismatch (`plugin_package_hash_mismatch`)
When the computed package archive SHA-256 differs from the trusted digest in the review record:
```text
[plugin_package_hash_mismatch] <package>: Plugin package SHA-256 is missing, malformed, or does not match the independently trusted digest
```

#### 2. Undeclared Capability (`plugin_capability_undeclared` / `plugin_review_required`)
When a plugin uses `run_as: "root"` or `modules[0].web` without declaring it in `capabilities`:
```text
[plugin_capability_undeclared] modules[0].web: Module uses capability "web_metadata" which is not declared in capabilities.allowed
```

#### 3. Unverified Installer Checksum (`plugin_verified_installer_checksum_required`)
When a plugin requests a `verified_installer` whose URL or tool name is not in `checksums.yaml`:
```text
[plugin_verified_installer_checksum_required] modules[0].install: verified_installer tool "untrusted_tool" has no matching entry in checksums.yaml
```

#### 4. Secret Material Refusal (`plugin_secret_material_refused`)
When a descriptor or documentation field contains API keys or tokens:
```text
[plugin_secret_material_refused] description: Value matches forbidden secret pattern (sk-ant-...)
```
