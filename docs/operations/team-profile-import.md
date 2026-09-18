# Review a shared team profile in the wizard

The **Run Installer** step now includes **Have a shared team profile? Review it
locally** below the main wizard content. This is a local-file review and approved
manual-command workflow, not automatic application of the file's defaults.

The normal wizard command and this alternative command are separate. Reviewing
or approving a team profile does not change wizard preferences, provision a VPS,
execute a command, supply credentials, or mark any installation complete.

## Review, then approve

1. Record the intended VPS address in the wizard. Open the team-profile section
   and confirm the VPS's Ubuntu image **before installation** and architecture.
   The architecture must be chosen explicitly; it is not inferred from the
   browser or the imported file. These are operator declarations, not detected
   facts about the server. The installer may still upgrade an older LTS image.
2. Choose a local `acfs-team-profile.json` file. The reader accepts one nonempty
   UTF-8 JSON object up to 256 KiB. It never uploads the file or stores its text
   in localStorage, query parameters, or a server account.
3. Review provider/access-default differences, installer and module-selection
   changes, added dependencies, exact skips, and required/optional sign-in slots.
   The preview includes the SHA-256 of the exact selected bytes but withholds
   the executable command. A digest identifies the bytes; it is not a signature
   or proof that the profile author is trusted.
4. Explicitly confirm that you reviewed the changes and trust the source, then
   choose **Approve profile command**. The canonical validator runs again before
   a copyable command is shown. Use this separate manual command in the intended
   VPS root shell **instead of**, not in addition to, the normal wizard command.

The command is rebuilt by ACFS from the validated profile. A command string
embedded in imported data is never executable authority. Required sign-in slots
describe later provider/CLI authentication; they do not carry secret values.
Never add tokens, private keys, passwords or session state to a team profile.

The existing [schema and compatibility rules](team-profile-schema.md) still
apply. In particular, the package's manifest/checksum provenance, Ubuntu image,
architecture, ref policy, known selectors and dependency closure must validate.
There is no bypass or "approve anyway" action for rejected profiles.

## Changed inputs require a new review

Approval is bound in memory to the exact source snapshot, the target VPS, the
current wizard settings, the declared image/architecture, and the current
generated manifest/checksum metadata. A changed host, profile, mode, username,
ref, provider selection, image or architecture invalidates the review. Reselect
the file and approve the resulting current differences rather than reusing the
previous command. A copied/deserialized preview is not an approval candidate.

Selecting another file or clearing the section removes the preceding approval.
An earlier slow file read cannot replace a newer selection or restore a cleared
command. Closing the page abandons this in-memory workflow. No completion flag
is assigned to the imported command; approval says only that a command was
reviewed, not that anything happened on the server.

## Input and error boundaries

The reader rejects invalid UTF-8, byte-order marks, duplicate decoded JSON keys,
non-finite numbers, non-object roots, more than 32 nesting levels or more than
16,384 JSON nodes. File-size checks happen before reading and are checked again
against the bounded byte snapshot. Secure browser hashing must be available;
there is no weaker fallback when Web Crypto fails.

Invalid profiles do not expose their source contents or filenames in errors.
The panel shows a generic refusal plus canonical finding codes, not untrusted
field paths, credential-like values, or raw parser exceptions. Validated display
text is rendered as text, not HTML. The original source is retained privately
for revalidation and is not exposed by the public review object.

The workflow does not detect the actual host configuration, authenticate the
profile author, resolve a mutable Git branch to a commit, install dependencies,
or guarantee that a remote installation will succeed. Review the pinned ref and
target before manually using an approved command.

## Implementation and tests

`reviewTeamProfileFile` reads and validates the source through
`buildTeamProfileImportDiff`. `approveTeamProfileReview` reruns that canonical
validator, compares the current result with the retained review, and exposes
only the rebuilt command. `teamProfileReviewMatches` rejects stale contexts and
fabricated review objects. The new panel is mounted by the Run Installer layout;
it does not replace the primary wizard page or its scoped acknowledgement.

From a checkout with the web dependencies installed:

```bash
cd apps/web
node --test lib/teamProfileImport.test.mjs components/team-profile-import-panel.test.mjs
bun test lib/teamProfileImport.integration.test.ts
bun run type-check
bun run lint
bun run build
```

The Node tests use real Blob reads, UTF-8 handling, native Web Crypto and the
actual file-review implementation. They deliberately substitute canonical
validation results to exercise refused/changed plans. Panel tests additionally
use hook, preference and command-card doubles, not a browser renderer. The
separate integration test imports the actual canonical validator, command
builder and generated catalogue; it requires the full checkout and its runtime
dependencies. Passing the isolated tests does not substitute for that integration
test, a React/browser run, or a live VPS installation.