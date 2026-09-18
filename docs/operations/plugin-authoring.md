# Build a reproducible ACFS plugin package

`plugin:pack` turns a dedicated source directory into the `tar.gz` consumed by
`plugin:verify` and `plugin:install`. It validates the actual package against the
canonical manifest, capability rules, dependency graph, phases and installer
checksums before publication. It does not execute installers, create a review,
modify the source, download dependencies, or change generated ACFS output.

## Source directory

Prepare the v1 JSON described in [the manifest contract](plugin-manifest-contract.md)
and place it with the required documentation:

```text
my-plugin/
  plugin.json
  README.md
  LICENSE
  docs/
    guide.md
```

The source directory's name is arbitrary; the archive root is always
`acfs-plugin-package/`. Every extra regular file must be under `assets/`, `docs/`
or `provenance/` and declared in `extensions.archiveFiles` with its relative path
and exact SHA-256. The packer does not silently calculate replacement declarations
or rewrite the manifest to make mismatched inputs pass. For example:

```json
{"extensions":{"archiveFiles":[{"path":"docs/guide.md","sha256":"REPLACE_WITH_THE_FILE_SHA256"}]}}
```

That placeholder is not a valid declaration. Compute the file's digest and put
it in the source manifest before building. Only declared files belong in this
directory: `.git`, `.env`, editor files, unlisted documentation and local review
records are refused, not silently included or ignored.

## Validate, publish, independently review

Run from a trusted ACFS checkout with its manifest package dependencies installed:

```bash
cd packages/manifest
bun run plugin:pack --source /path/to/my-plugin \
  --target ubuntu/26.04/x86_64/glibc --dry-run --json

bun run plugin:pack --source /path/to/my-plugin \
  --target ubuntu/26.04/x86_64/glibc \
  --output /path/to/releases/my-plugin-1.2.3.tar.gz --json
```

The explicit target is the tuple checked by canonical validation, not a claim
that every declared target was tested on a real host. An unsupported target,
missing checksum entry, unknown dependency, cycle, privileged module or other
validation failure prevents publication. There is no validation-bypass flag.

Dry-run returns `status: "validated"` and the prospective compressed digest,
file count and sizes without writing files. Publication returns `status: "packed"`
and the exact same fields for the bytes actually written. Both always report
`reviewRequired: true`. Source edits between invocations can change the digest.

The output must be a **new** `.tar.gz` file outside the source directory, with
an existing parent directory. It is created with mode `0600`, and the file and
parent directory are fsynced before reporting publication. Existing paths are
never replaced. An I/O failure may leave a partial file for inspection; retry
with a new output path rather than destroying evidence.

Next, follow [the independent review and installation workflow](plugin-review-workflow.md).
A maintainer must review the actual package and record its exact compressed
SHA-256 in a separately trusted review. The pack command does not auto-generate
an approving review or turn the author's self-consistency check into trust.
A package still fails ingestion when its external review is absent, expired,
for another target/identity, or pins different bytes.

## Reproducibility and limits

Files are ordered by portable ASCII paths. ustar headers use fixed uid/gid,
modes and timestamps; gzip headers contain no build time or builder OS. Source
location, enumeration order, normal file permissions and filesystem timestamps
do not change the archive. Exact file contents, including JSON whitespace and
`provenance.generatedAt`, are preserved. Use the same runtime/compressor version
for byte-for-byte reproduction across machines; compressor-version equivalence
is not promised.

The producer checks its output through the production archive reader before it
can be published. Empty declared static files and long ustar prefix paths are
supported. Symlinks, hardlinks, special files, special permission bits,
group/world-writable source members, unsafe paths, duplicate JSON keys,
undeclared/missing assets and digest mismatches are refused. Paths must fit
ustar without PAX extensions. Known private-key and credential markers are
screened across included bytes, including documentation. This is not a complete
secret detector or a semantic audit of arbitrary binary assets; review remains
necessary. Build from a trusted, quiescent source tree, not an adversarially
modified shared workspace.

Limits match the reader: 16 MiB compressed, 64 MiB expanded, 1 MiB manifest,
8 MiB per other file, 1,024 entries, and bounded JSON depth/node counts. The
snapshot retained for publication is private: later source edits or mutations
of a caller's returned byte copy cannot replace the bytes that were validated.

## API and tests

`buildPluginArchive` performs bounded source snapshotting and archive-structure
validation only. `pluginArchiveBytes` returns an owned copy. `writePluginArchive`
exclusively publishes the retained snapshot. These low-level functions do not
grant semantic validity or installation authority. The CLI additionally calls
`validatePluginArchiveForPublication`, which uses the real canonical validators;
it exposes only validation metadata, never install modules or review approval.

```bash
cd packages/manifest
bun test src/plugin-pack.test.ts src/plugin-pack-cli.test.ts
bun test src/plugin-archive.test.ts src/plugin-review.test.ts src/plugin.test.ts
bun run type-check
```

CLI routing tests inject semantic-validation outcomes while using real archive
production, publication and independent-review ingestion. The separately named
canonical publication test requires the full checkout and YAML/Zod dependencies.

Exit codes: `0` for validated dry-run or successful publication, `1` for source,
validation or output failure, `2` for invalid arguments, `130`/`143` for signal
cancellation before publication. Errors omit source paths and file contents.
