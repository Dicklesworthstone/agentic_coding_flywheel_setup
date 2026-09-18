# Review a shared team profile in the wizard

The **Run Installer** step includes **Have a shared team profile? Review it
locally** below the main wizard content. After reviewing a local file, choose
between a separate manual command and an explicitly adopted installation for
this wizard tab. Neither option automatically executes the file's defaults.

Reviewing a profile never changes saved wizard preferences, provisions a VPS,
executes a command, supplies credentials, or marks installation complete.

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
4. For a separate manual command, confirm the manual-command checkbox and choose
   **Approve profile command**. The canonical validator runs again before a
   copyable command is shown. Use this separate command in the intended VPS root
   shell **instead of**, not in addition to, the normal wizard command.

The command is rebuilt by ACFS from the validated profile. A command string
embedded in imported data is never executable authority. Required sign-in slots
describe later provider/CLI authentication; they do not carry secret values.
Never add tokens, private keys, passwords or session state to a team profile.

The existing [schema and compatibility rules](team-profile-schema.md) still
apply. In particular, the package's manifest/checksum provenance, Ubuntu image,
architecture, ref policy, known selectors and dependency closure must validate.
There is no bypass or "approve anyway" action for rejected profiles.

## Use the reviewed installation throughout the wizard

To use the reviewed choices in the normal wizard instead of a separate command,
select the independent wizard-adoption confirmation and choose **Use reviewed
installation in this wizard**. Manual-command confirmation alone never performs
this action. The retained source is revalidated against current saved settings
and trust metadata before an active installation is published.

A banner identifies the active team profile. Its mode, pinned ref, username,
and exact module/phase/skip selections travel together through the primary
installer, cached command, runbook, provider packet, team-profile export,
reconnection pages, Status Check retry, and final command panel. A profile label
alone cannot replace a narrower reviewed selection. Cache preparation uses the
operator-confirmed architecture and the installer's upgrade destination; the
starting image remains a separate declared fact in handoff exports. Imported
provider claims do not overwrite the actual saved provider selection.

Settings controls cannot partially edit an active installation. The command
panel becomes read-only, and a regenerated installer that differs from the
approved command is withheld. Choose **Discard reviewed installation and use
saved settings** in the banner before editing defaults. Discard restores the
unchanged saved preferences, not defaults copied from the imported file.

This installation is held in memory at the application root so client-side
wizard navigation does not lose it. Public routes still use saved preferences.
Only the constant `acfs-reviewed-installation-pending-v1` tab-session guard is
stored, never profile contents, host details, commands or approval tokens.
Reloading while that guard exists blocks the wizard's command subtree until
another review or explicit discard. Missing, unreadable or changed guard state
cannot revive an old in-memory approval. Failed storage writes or failed guard
removal do not select a new/default installation.

Clearing a file preview or closing its disclosure does **not** discard an
already adopted installation; use the banner action. Adopting a profile does
not check a remote machine, execute anything, or record success. The primary
installer's acknowledgement is recomputed from its exact command and host; an
acknowledgement for a different command or host cannot stand in for this one.

## Changed inputs require a new review

Approval is bound in memory to the exact source snapshot, the target VPS, the
current wizard settings, the declared image/architecture, and the current
generated manifest/checksum metadata. A changed host, profile, mode, username,
ref, provider selection, image or architecture invalidates the file review.
Changed saved facts or trust metadata also block an active installation; simply
restoring the old values does not resurrect it. Reselect the file and approve
the resulting current differences rather than reusing a previous command.
A copied/deserialized preview is not an approval candidate.

Selecting another file or clearing the section removes its preceding manual
approval and adoption consent. An earlier slow read cannot replace a newer
selection or restore a cleared command. Withdrawn or cleared confirmation
callbacks cannot adopt a profile later. The separate manual command has no
completion flag; approval says only that a command was reviewed, not that
anything happened on the server.

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
only the rebuilt command. `activateTeamProfileInstallation` derives the complete
immutable installation from the privately retained source, never a serialized
preview. `WizardInstallationProvider` retains it across navigation and guards
reloads; preference hooks overlay only their returned values, not persisted
query data. The review panel uses the separate saved-preference hooks so it can
still review a file while effective installation consumers are blocked.

From a checkout with the web dependencies installed:

```bash
cd apps/web
node --test lib/teamProfileImport.test.mjs components/team-profile-import-panel.test.mjs
node --test components/wizard-installation-provider.test.mjs app/wizard/run-installer/page.test.mjs lib/installerCheckpoint.test.mjs
node --test components/command-builder-panel.test.mjs
bun test lib/teamProfileImport.integration.test.ts
bun run type-check
bun run lint
bun run build
```

The Node tests use real Blob reads, UTF-8 handling, native Web Crypto, the actual
review/session and preference code, and actual command-consuming components.
They substitute React/query and canonical-validation contracts rather than
running a browser renderer. The connected tests cover adoption, cross-route
exact selectors and usernames, stale callbacks, storage failures, reload
blocking, explicit discard and event cleanup. The separate canonical test
imports the real validator, command builder and generated catalogue; it needs
the full checkout and its runtime dependencies. Passing isolated tests does not
substitute for canonical integration, a React/browser run, or a live VPS install.
