# External installer audit: checksum monitor #494

Audit date: 2026-10-30 UTC. Repository and policy base:
`9d16dff4516b5ede866dbccbe2b3ce3c69a6b0bd`.

## Decision

Atuin v18.24.4, uv 0.13.6, and oh-my-pi's reviewed installer change are
supported candidates for a future human-authorized checksum update. Keep Grok
deferred until its deployed changes have corroborated upstream provenance and
the Cursor command-ownership behavior is resolved for ACFS.

**This audit authorizes no checksum changes.** Do not approve the four-tool
digest in #494 on the strength of the three explained changes. No audited
installer or its downstream application payload was executed. No checksum
pin, installer URL, or authorization file was changed.

The `omp` entry is **oh-my-pi**, the coding agent from `can1357/oh-my-pi`, not
Oh My Posh. ACFS's `agents.omp` manifest entry and the installer's redirect
identify the project. Oh My Posh documents a different endpoint,
`https://ohmyposh.dev/install.sh`.

| Entry | Verified explanation | Recommendation |
| --- | --- | --- |
| `atuin` | Expected and three observed hashes match four successive official release assets; only version literals and seven archive hashes change. | Candidate: v18.24.4, subject to human authorization. |
| `uv` | Expected hash is 0.13.4; all observations are 0.13.6; only version literals and eighteen archive hashes change. | Candidate: 0.13.6, subject to human authorization. |
| `omp` | Exact public source diff raises the minimum Bun version from 1.3.14 to 1.4.4. Release v18.13.3 contains the same script. | Candidate: reviewed `c3b645cb` script, subject to human authorization. |
| `grok` | Deployed script adds Cursor switch-record parsing and preserves Cursor-owned commands. Public source still has the older script. | Defer: source-publication gap and ACFS command-identity concern. |

## Scope, evidence, and limitations

Sources include monitor issues [#492][issue492], [#493][issue493], and
[#494][issue494]; the base commit's `checksums.yaml`, `acfs.manifest.yaml`,
`scripts/lib/security.sh`, `scripts/lib/github_api.sh`, and
`scripts/checksum-monitor-local.sh`; version-specific upstream release
metadata and installer bodies; source-commit paths; and release notes.
The comprehensive plan and relevant beads were also inspected. The older
`bd-3f8du` review concerns a different four-tool set and retains an
external-checker condition; this audit does not close it.

Downloads used certificate-verified HTTPS, HTTPS-only redirects, an honest
ACFS project User-Agent, and explicit transfer timeouts. Bodies were saved as
inert `.body` files. Evidence includes complete redirect headers, transfer
metadata, exact SHA-256 values and lengths, complete diffs, upstream metadata,
and per-file inventories. The separately delivered
`acfs-494-audit-evidence.zip` includes a top-level `SHA256SUMS` inventory.
Public repository documentation does not embed cookies or expiring signed
asset URLs from response captures.

**Evidence recovery:** the execution environment restarted before the first
evidence bundle was saved, losing those local captures and test logs. The
delivered bundle contains explicitly dated fresh recovery captures from
October 30 and newly rerun validation logs. It does not claim to contain the
lost originals. Fresh recovery downloads reproduce every expected and
observed installer hash, including all three historical Atuin variants.
Recovery notices and timestamps are part of the evidence inventory.

The original host-local full JSON verification reports and original HTTP
responses from the three monitor runs were never available in this
workspace. Their full-report digests are preserved as issue assertions,
not independently verified report hashes. Historical bodies were
reconstructed from upstream sources and matched to the reported hashes;
original network headers cannot be reconstructed retroactively.

This is a static installer and provenance review, not certification of every
downstream binary or upstream build system. GitHub-provided asset digests and
source metadata corroborate the upstream distribution platform; they do not
establish independent reproducible builds. No cryptographic attestation
verification is claimed.

## Monitor reports and authorization binding

| Issue | Opened, UTC | Pinned repository base | Verification report SHA-256 stated by issue |
| --- | --- | --- | --- |
| #492 | 2026-10-28 21:33:52 | `016867ffd84b2617acdb58a33a5a137068796df6` | `7adf91796402f9179ac3a4fc5e77fd43aa4531ca5952838ee47bc37532886556` |
| #493 | 2026-10-29 02:46:19 | `119701551296ef14615b6e90943a0a66b60c4b68` | `61964506f79ecb03f5fd649c7327812c30358c2b4aa255f5fd5cf6b98ede5b32` |
| #494 | 2026-10-30 02:01:21 | `9d16dff4516b5ede866dbccbe2b3ce3c69a6b0bd` | `b98ac217e2cc44299bb962128bfd9825f44d93dca89cd34edcb180f29f01c7d5` |

Each external authorization digest was independently reproduced from the
issue's four observations using the monitor's exact canonicalization:
select `{actual, expected, name, url}`, sort entries by `name`, serialize
compact JSON with sorted object keys and a trailing newline, then SHA-256.

| Issue | Reproduced authorization digest |
| --- | --- |
| #492 | `6de1311594c212f5c0964e22170c3e51d27e95d757ecccfe34c0bad9db14004f` |
| #493 | `70301d385689d2837cb1a966a785f0fac008329f75e23d4aa6cf089bee123d8a` |
| #494 | `d567512534e27628be99b3e02b40ac6b4ecd9e5c1e05ae6234f02317924cd8f3` |

Authorization is bound to the external observations, **not the base
commit**. Unrelated commits or trusted-owner updates do not invalidate an
otherwise unchanged digest. Changing a tool, URL, expected hash, observed
hash, or the external mismatch set changes its input. The pinned base and
complete policy/report bindings independently constrain candidate construction
and publication.

Only exact `https://raw.githubusercontent.com/Dicklesworthstone/` installer
origins enter the internal trusted-owner path. These four entries remain
external. The monitor requires an owner-owned, single-link, non-symlink
regular authorization file with no group/world permissions, bounded size,
and exactly one matching `authorize:<digest>` line. It rechecks selected
authorization at acceptance boundaries, restricts candidate changes to
validated observations, requires a clean pinned base and allowed publication
paths, and verifies publication. Pending external pins stay deferred while
eligible internal updates may proceed.

The current monitor authorizes the external mismatch set together. It does
not offer a per-tool interpretation of #494's digest. A review accepting
three entries and deferring Grok cannot safely write that authorization.
A future separate reviewed apply set must be produced through an explicit,
supported authorization workflow; do not reinterpret the existing digest
or hand-edit `checksums.yaml`.

## Atuin: successive releases explain the changing bytes

| Evidence | Release | Published, UTC | Exact installer SHA-256 |
| --- | --- | --- | --- |
| Expected | v18.24.1 | 2026-10-16 22:43:14 | `69c7c0e057084ede4536de25f856c037f4649dcf8f29cc98a64ac52340320a99` |
| #492 | v18.24.2 | 2026-10-22 10:07:24 | `682117ada10ef0886fa4974f1afcf5fb396ce466c45acaffbf075eeb06f6dc25` |
| #493 | v18.24.3 | 2026-10-29 02:41:57 | `7cafa689898e9913588c227473c4018310a3e808a6ac7ded14c4ffc53554b8a2` |
| #494 | v18.24.4 | 2026-10-30 01:57:12 | `4e32fb752978e433fe512bffc83b2d1d1257b72c968180e1c305f4ae5a064c67` |

Each installer is 55,965 bytes. Each body's hash matches the issue/manifest
value and the corresponding GitHub release asset digest. The ACFS
`releases/latest/download` URL returns v18.24.4 through GitHub's versioned
release URL and `release-assets.githubusercontent.com`, entirely over HTTPS.

The #493 and #494 reports followed their corresponding releases by about four
minutes. Successive releases explain the changing bytes without assuming
randomized responses, injected content, or gzip variation. A stale web index
showed v18.24.3 for `latest`; direct version-specific metadata and exact-byte
retrieval establish v18.24.4.

Complete v18.24.1-to-.2/.3/.4 diffs change only app/receipt/help version
literals, versioned archive paths, and seven embedded archive SHA-256 values.
All 28 embedded values across four scripts match official release metadata.
Normalizing only these reviewed literals makes the scripts identical. This
normalization is analysis only and must never replace exact-byte pinning.

v18.24.3's release notes include dependency advisory fixes, stricter tool
arguments, daemon key handling after login, and password checks before
account deletion. v18.24.4 adds Copilot session support and related fixes.
The v18.24.2 Docker CA warning concerns the server image and does not
demonstrate shell-installer compromise.

Existing qualifications remain: download-location environment overrides are
trust inputs, and archive verification is skipped when `sha256sum` is absent.
The generic separate-updater branch is inactive because every platform's
updater name is empty. GitHub marks these releases `immutable: false`;
retain exact hashes even for versioned URLs.

The v18.24.4 shell-installer attestation lookup returned 404. A platform
archive lookup returned a SLSA bundle naming tag v18.24.4, commit
`b7ccdaf6b71f648d096de24b66cc8c7821d73351`, and workflow run 40986115974.
The bundle was preserved and decoded, not signature-verified. This is not
verified installer attestation.

**Recommendation:** v18.24.4's exact hash is a supported pin candidate,
pending human authorization for the actual reviewed apply set.

## uv: 0.13.4 to 0.13.6

The expected `1f5390d273b0158bd5eaa3527ae049f3667baa881abb1e7c883dd637d84432f9`
is the official uv 0.13.4 installer. The observed
`f7a56e7afaec49a3bcbc3ac3cdbe917e7c6ce30e0d815308a12e531aa5ef23b7`
is the official uv 0.13.6 installer, published 2026-10-27 00:47:49 UTC.
uv 0.13.5 was retrieved as an intermediate comparison. Each script is
71,300 bytes; GitHub marks all three releases immutable.

`https://astral.sh/uv/install.sh` redirects to
`https://releases.astral.sh/installers/uv/latest/uv-installer.sh`. Its body
matches the 0.13.6 versioned GitHub release asset and recorded digest.
That release predates all three reports, explaining the stable observation.

The complete .4-to-.6 diff changes only version literals and eighteen
embedded archive hashes. All 54 embedded hashes across .4, .5, and .6 match
official release metadata, using the actual archive names selected by the
script. The normalized scripts are identical. No download origin, command,
or verification branch is added by this installer diff.

uv 0.13.6 includes a filesystem-safety fix preventing certain
`--active --script` operations from deleting non-virtual-environment
directories. The earlier 0.13.4 release already addresses a bundled root-CA
advisory; that earlier fix is not attributed to this pin advancement.
Download-location overrides and the missing-`sha256sum` skip remain.

**Recommendation:** 0.13.6's exact hash is a supported pin candidate,
pending human authorization. This covers the installer diff and release
identity, not an independent audit of every uv binary.

## oh-my-pi: one-line minimum Bun version change

Expected bytes (12,297 bytes) were recovered at upstream commit
`4585b144ff86b9d3dd6d9d17263cbd541a4ba8aa`, `scripts/install.sh`, and hash to
`cd2ea5553e9ad8f89fe5e04f771ec13db6f33a773f7ba8f85c84b63cdbeb9065`.
Observed bytes (12,296 bytes) hash to
`cd8f77920da58c6f56b5851c841b61d5e30b4ba8f4cab683afba1f8274b56a06`
and match commit `c3b645cb275e03ac8a176fbfb0a877cfb3a2c2ef` and
release v18.13.3 exactly.

The entire script diff is:

```diff
-MIN_BUN_VERSION="1.3.14"
+MIN_BUN_VERSION="1.4.4"
```

GitHub reports the commit signature valid. Release v18.13.3, published
2026-10-28 12:49:52 UTC, documents the Bun requirement increase. Fresh
endpoint downloads match that source. `omp.sh` redirects to
`raw.githubusercontent.com/can1357/oh-my-pi/main/scripts/install.sh`.

ACFS passes `--binary`; that branch does not call `require_bun_version`, so
this change does not alter ACFS's selected binary installation path. The
`build.stencil.so` service, `PI_BUILD_URL` override, same-service checksum,
and binary version execution predate the change. ACFS commit
`f28bead54cd6de64bf8a161dfb3c60f3786a528e` records the earlier distribution
service review. A checksum from the same service does not supply an
independent signing trust root for the binary.

**Recommendation:** the observed script is a supported pin candidate,
pending human authorization. Correct the project identity in every review
or approval record; reviewing Oh My Posh would review the wrong software.

## Grok: explained behavior, unresolved published provenance

The expected 19,501-byte script was recovered from `xai-org/grok-build`
commit `bb7f39d5858cbf5e00de639367f59debbdcb0138`, path
`crates/codegen/xai-grok-pager/scripts/install.sh`. It hashes to
`7fd6fdc75d9418b2e58356726fcbf1ae849416f773925da07d0ccc7a60d3e791`.
Current public source still returns those bytes. Public main was
`2bdd1d6a6369de0e8c68132ea4539e9abd9e14a8`, dated 2026-09-29.

Fresh `https://x.ai/cli/install.sh` downloads are 29,553 bytes, HTTP 200
`text/plain`, and hash to
`dcc19d498e14f96ab93828251b2848fde94cc2ab0bd6f9cad9baffbf7a229182`.
The direct vendor storage origin returns the same body and metadata:
Last-Modified 2026-10-28 21:30:27 UTC, GCS generation `1793223027049983`.
These URLs corroborate the same deployed object; they are not independent
provenance authorities.

The complete diff has 208 added and 21 removed lines. It adds a byte-oriented
`od`/`awk` JSON parser for Cursor's `grok-switch.json`, resolves Cursor
configuration from environment/default paths, and preserves Cursor ownership
of `grok` and `agent` names while a switch is pending or active. It avoids
replacing those links/executables or creating competing PATH links.
Completions use the downloaded Grok binary's actual path; messages explain
how to switch back.

The diff changes no binary-download domain, credential-reading logic,
deployment-key destination, or checksum/signature verification logic. It is
consistent with deliberate interoperability work. No finding in the diff
demonstrates malware or upstream compromise.

However, no matching immutable public source commit or release-specific
change record was recovered. The vendor stable pointer remains 1.0.70,
and the public changelog's latest entry is dated October 23. Those facts
do not explain an installer object modified five days later.

Two security-relevant qualifications prevent approving it based on stable
hashes:

1. Both scripts download a mutable-channel application payload and execute
   it without SHA-256 or signature authentication of that payload. A
   `--version` smoke check is execution, not authentication.
2. The new ownership behavior can preserve a Cursor shim under `grok`.
   ACFS's `command -v grok`, executable-existence, and version/help checks do
   not authenticate that name as the intended Grok executable. This is an
   integration risk inferred from static code, not a reproduced install
   failure.

**Recommendation:** keep this checksum deferred. Obtain upstream source
publication or maintainer confirmation tied to the exact observed digest,
then review command ownership and ACFS's verification contract. Do not run
the installer to establish provenance or approve it solely because the
vendor endpoint and storage origin repeatedly agree.

## Repository improvements and validation

The audit identified two verification defects, separate from Atuin's
legitimate release sequence:

- The production monitor retained a digest-only report but discarded the
  temporary downloaded bodies and response headers. A later re-fetch cannot
  preserve the original observation needed for authorization review.
- The GitHub backoff downloader bypassed the bounded Content-Encoding
  decoder used by other security download paths. Server-supplied gzip could
  therefore be hashed as a compression envelope. This independently
  reproduced defect does not explain the historical Atuin variants.

Commit `2b8c8073ec43a7a3718ae76b30729b0c71c7fc59` fixes the GitHub path.
Supported coding is decoded with the existing bounded decoder before
publishing the private bytes. Invalid or unsupported coding fails closed
without changing a caller's destination or emitting a response body.
Standalone use without the decoder accepts identity and rejects coded
responses.

The accompanying monitor change retains private first-observation decoded
bodies, content-coded response entities, headers, and per-tool metadata.
The saved entity is what curl receives after HTTP transfer framing, before
Content-Encoding decoding; it is not a network packet capture. The monitor
binds the evidence index to the original policy and report, rehashes it at
acceptance boundaries, and rejects missing, changed, misbound, or unsafe
evidence. Public records receive only its digest and a retention notice.
External authorization semantics and checksum pins are unchanged.

Retained observations accumulate beneath the private monitor state
directory. This change deliberately provides no automatic deletion or
expiry policy; the host operator must manage retention and available disk
space without removing evidence still needed for review.

Fresh validation after recovery passed:

| Gate | Result and scope |
| --- | --- |
| GitHub download regression suite | 31/31 cases pass on the published fix; the pinned incumbent with the identical suite passes 22/31 and fails the same nine encoding regressions. Each used isolated source snapshots. |
| Security library suite | 37/37 tests pass, including 153 descriptor/evidence/candidate assertions and actual localhost TLS fixtures for exact decoded/raw/header preservation and failed transfers. |
| Monitor evidence and authorization tests | Existing checks and 19 private-evidence cases pass, including tampering, unsafe links/modes, wrong identity, and modification of the original index. |
| Full publication state machine | Seven scenarios pass: pending authorization, external-only changes, exact authorization, unavailable review delivery while pending, unavailable review delivery while authorized, rejected atomic push, and upstream fetch error. |
| Canonical generation and drift | 121 internal checksums, 461 manifest contract checks, and 75 modules verify cleanly. Only the changed libraries' internal checksum rows advance across the two fixes. |
| Static checks | Bash syntax, ShellCheck 0.9.0, and `git diff --check` pass. |

The full-state tests use disposable local bare Git repositories, synthetic
installer observations, and mocked issue delivery. They exercise real local
atomic publication and acceptance/authorization-consumption behavior, not
the maintainer's deployed monitor or hosted GitHub acceptance. Test fixture
changes preserve all production guards and share only the prepared Bun cache
for frozen, lifecycle-disabled dependency installation.

The required host-specific external checker could not run: neither
`/dp/automated_flywheel_setup_checker/Cargo.toml` nor `cargo` exists here.
The prescribed `validate --path ...`, `list`, and
`check --dry-run --local` invocations were attempted and recorded as
unavailable. `ubs` and `br` are also unavailable, so UBS and beads sync are
not claimed as completed; no bead is closed. `/data/projects/AGENTS.md` is
absent. The delivered evidence preserves these precise limitations instead
of substituting local fixture results for host installation checks.

## Primary source links

- [ACFS policy at the audit base][basepolicy], [manifest][basemanifest], and
  [monitor][basemonitor]
- Atuin release metadata: [v18.24.1][atuin1], [v18.24.2][atuin2],
  [v18.24.3][atuin3], [v18.24.4][atuin4]
- uv releases: [0.13.4][uv4], [0.13.6][uv6]
- [oh-my-pi commit][ompcommit] and [v18.13.3 release][omprelease]
- [Grok expected source][groksource], [deployed installer][grokdeployed], and
  [official changelog][grokchangelog]

[issue492]: https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/issues/492
[issue493]: https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/issues/493
[issue494]: https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/issues/494
[basepolicy]: https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/blob/9d16dff4516b5ede866dbccbe2b3ce3c69a6b0bd/checksums.yaml
[basemanifest]: https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/blob/9d16dff4516b5ede866dbccbe2b3ce3c69a6b0bd/acfs.manifest.yaml
[basemonitor]: https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/blob/9d16dff4516b5ede866dbccbe2b3ce3c69a6b0bd/scripts/checksum-monitor-local.sh
[atuin1]: https://api.github.com/repos/atuinsh/atuin/releases/tags/v18.24.1
[atuin2]: https://api.github.com/repos/atuinsh/atuin/releases/tags/v18.24.2
[atuin3]: https://api.github.com/repos/atuinsh/atuin/releases/tags/v18.24.3
[atuin4]: https://api.github.com/repos/atuinsh/atuin/releases/tags/v18.24.4
[uv4]: https://github.com/astral-sh/uv/releases/tag/0.13.4
[uv6]: https://github.com/astral-sh/uv/releases/tag/0.13.6
[ompcommit]: https://github.com/can1357/oh-my-pi/commit/c3b645cb275e03ac8a176fbfb0a877cfb3a2c2ef
[omprelease]: https://github.com/can1357/oh-my-pi/releases/tag/v18.13.3
[groksource]: https://raw.githubusercontent.com/xai-org/grok-build/bb7f39d5858cbf5e00de639367f59debbdcb0138/crates/codegen/xai-grok-pager/scripts/install.sh
[grokdeployed]: https://x.ai/cli/install.sh
[grokchangelog]: https://x.ai/changelog/build
