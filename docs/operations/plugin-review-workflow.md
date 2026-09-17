# ACFS Plugin Archive Verification and Review

ACFS can now read a real, digest-pinned plugin `tar.gz`, bind it to an external
review and an explicit target, and validate its manifest against the canonical
schema, dependency graph, capability policy, and `checksums.yaml`.

**Verification is read-only, not activation.** It never extracts archive members,
runs an installer, modifies profiles, or writes generated output. The generator
continues to refuse `--plugin`, `--plugins-dir`, `ACFS_PLUGIN_PATHS`, and
`ACFS_PLUGINS_DIR`. Profile integration, activation planning, elevated-capability
approval, and true offline execution remain separate work. The broader design
contract is in [plugin-manifest-contract.md](plugin-manifest-contract.md).

## Verify a package

Run from a trusted checkout with the manifest package's Bun dependencies installed:

```bash
cd packages/manifest
bun run plugin:verify \
  --archive /path/to/example-tools.tar.gz \
  --review /trusted/reviews/example-tools.json \
  --target ubuntu/26.04/x86_64/glibc \
  --json
```

The target is always explicit and is never inferred from the developer's laptop
or copied from the package. OS, version, architecture, and libc must all match
both the external review and one complete `targets[]` entry in the package.
This example target does not change the installer defaults or certify Ubuntu
26.04 support for the rest of ACFS.

Exit status is `0` for successful verification, `1` for refused package/review
validation, and `2` for invalid command arguments or unavailable canonical
inputs. JSON output always states `"activation":"disabled"`. Successful output
includes the validated module count, not installer commands or untrusted archive
contents. Errors do not echo archive paths, review identities, or parser input.
There is no fallback to an unverified package when any check fails.

## External review record

The operator must select a review from a separately trusted source. A review is
not a signature, and anyone can write a JSON file: accepting a package author's
self-issued review does not establish independent trust. Never generate the
review automatically from an untrusted package during verification.

```json
{
  "schema": "acfs.plugin-review.v1",
  "packageId": "example.tools",
  "version": "1.2.3",
  "sourceCommit": "0123456789abcdef0123456789abcdef01234567",
  "packageSha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "reviewer": "maintainer-identity",
  "reviewedAt": "2026-09-17T00:00:00Z",
  "expiresAt": "2026-10-17T00:00:00Z",
  "target": {
    "os": "ubuntu",
    "version": "26.04",
    "arch": "x86_64",
    "libc": "glibc"
  },
  "approvedCapabilities": ["verified_installer", "doctor_check", "web_metadata"]
}
```

The digest above is an illustration, not an approval. A maintainer must record
the SHA-256 of the **exact compressed package bytes** after reviewing the
package, source revision, installer entry, and declared capabilities. The loader
checks the digest before decompression and parses the same in-memory byte
snapshot; a loose `plugin.json` cannot substitute for the archive.

All review fields are required and unknown fields are rejected. UTC timestamps
must be canonical. Future-dated, expired, reversed, malformed, duplicate-key,
symlinked, hardlinked, or oversized review records are refused. Expiration is
exclusive: a review stops being valid at its `expiresAt` timestamp.

Only `verified_installer`, `doctor_check`, and `web_metadata` can currently be
approved. A review cannot unlock root/current-user execution, default-enabled
plugin modules, cross-plugin dependencies, arbitrary shell, services, or the
reserved `release_artifact`, `copy_asset`, and `manual_step` executors. The
canonical validator retains all of those refusals.

## Archive contract

Packages have exactly one namespace, with these three required regular files:

```text
acfs-plugin-package/
  plugin.json
  README.md
  LICENSE
```

Create a portable archive with a normal directory argument, not an absolute path:

```bash
tar --format=ustar -czf example-tools.tar.gz acfs-plugin-package
sha256sum example-tools.tar.gz
```

Plain GNU tar and POSIX ustar headers are accepted. PAX/long-name extensions,
sparse files, symlinks, hardlinks, devices, FIFOs, setuid/setgid/sticky bits,
absolute paths, dot-segment traversal, duplicate names, conflicting file and
directory paths, malformed headers, nonzero padding, truncated members, and
payload after the archive terminator are refused. Paths use portable ASCII
segments starting with a letter, digit, or underscore and containing only
letters, digits, underscores, dots, and hyphens.

`plugin.json`, `README.md`, and `LICENSE` are implicitly declared. Every extra
regular file must be under `assets/`, `docs/`, or `provenance/` and explicitly
listed with its own SHA-256 in `plugin.json`:

```json
{
  "extensions": {
    "archiveFiles": [
      {
        "path": "docs/guide.md",
        "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
      }
    ]
  }
}
```

Each declaration has exactly `path` and `sha256`. Missing, duplicated,
undeclared, or content-mismatched files are refused. This is an integrity check,
not an asset executor or a claim that arbitrary binary contents have been
semantically reviewed. Static-file contents are not printed or installed.

Limits are 16 MiB compressed, 64 MiB expanded, 1 MiB for `plugin.json`, 8 MiB per
other member, 1,024 archive entries, and 64 KiB for the external review. JSON also
has depth and node limits, must be UTF-8, and cannot contain duplicate decoded
object keys, a byte-order mark, or non-finite numeric values. Archive files and
review records must be nonempty, single-link regular files.

## Canonical trust checks and API

`loadReviewedPluginPackage(archivePath, reviewPath, options)` requires an explicit
`options.target` and a trusted first-party manifest/checksum map. It supplies the
computed compressed digest and the independent review digest to the existing
plugin validator, then rechecks the merged schema, dependency graph, phases,
and installer checksums. It returns no modules on failure. It never changes the
first-party manifest.

The lower-level `readVerifiedPluginArchive` and `readReviewedPluginArchive`
functions establish byte/review bindings only. Their `manifest` remains
`unknown`; callers must not treat it as installable without canonical semantic
validation. Public types and loaders are exported from `@acfs/manifest`.

`verified_installer` still requires an exact tool/HTTPS-URL/SHA-256 entry in
`checksums.yaml`; a package or review cannot supply a replacement checksum map.
New canonical installer checksums must continue to be produced through
`./scripts/lib/security.sh --update-checksums`, not handwritten into the database.

## Tests

```bash
cd packages/manifest
bun test src/plugin-archive.test.ts src/plugin-review.test.ts src/plugin-verify.test.ts
bun test src/plugin.test.ts
bun run type-check
bun run generate --validate
```

The archive/review tests exercise actual filesystem reads, gzip, and system tar,
including malicious archives and expiration boundaries. The command tests cover
argument handling and redacted JSON output; canonical integration tests cover
normalized provenance, installer-checksum refusal, privilege/default-selection
refusal, dependency cycles, and unsafe verification commands. Running the full
Bun/canonical suite remains required before enabling any future activation path.
