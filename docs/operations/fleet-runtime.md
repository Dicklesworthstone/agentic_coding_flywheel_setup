# Install the fleet controllers without retaining a checkout

`acfs-fleet` provides one installed entrypoint for the existing fleet `launch`,
`prepare`, and `dispatch` controllers. Install it explicitly from a trusted,
complete ACFS checkout on a Linux controller with Python 3.9 or newer. It does
not replace `acfs`, change the one-line installer, or install anything remotely.

## Preview and install

Choose existing user-owned directories that are not group/world-writable. For
example, after creating `$HOME/.acfs/fleet` and `$HOME/.local/bin` yourself:

```bash
python3 -I scripts/acfs-fleet.py install \
  --prefix "$HOME/.acfs/fleet" --bin-dir "$HOME/.local/bin"
```

This reads and syntax-checks the four controller files, reports a content-derived
runtime ID and an installation plan digest, and creates nothing. Review the
paths, files and previous launcher. Repeat the command with
`--apply --accept-plan THE_RETURNED_DIGEST` to install, as the target user without
sudo. Installation performs no network access and launches no agents or prompts.
The source checkout is a code trust decision; hashes are not publisher signatures.

The prefix contains `releases/RUNTIME_ID/`, holding the frontend, three complete
controllers and a hash/size manifest. The release directory and entrypoint are
mode 0500; remaining files are mode 0400. A symlink named `acfs-fleet` in the
selected bin directory points to the completed release. Ensure that directory
is on PATH; the installer does not edit shell startup files.

## Use the existing workflows

```bash
acfs-fleet version
acfs-fleet launch --help
acfs-fleet prepare --help
acfs-fleet dispatch --help
```

All options after the command are forwarded literally to the corresponding
controller. Standard input, current directory, terminal and exit/signal status
are preserved. There is no new approval parser or implicit `--launch`,
`--prepare`, `--send`, or `--resume`. The launch/dispatch controllers' previews
can open SSH connections; preparation's preview stays local. Their normal
explicit approvals, trust files, receipt rules and recovery limitations remain.
Consult the existing fleet launch, preparation and dispatch operating guides.

The frontend replaces itself with the selected Python controller in isolated
mode. It verifies the complete cohort before doing so, including siblings that
a different command imports. Missing manifests, changed files, symlinked
controllers or partial releases cannot silently fall back to PATH or a checkout.
This checks local integrity, not provider readiness, remote software, filesystem
sandboxing or resistance to a malicious same-user process replacing the verifier.

## Updates and interrupted installs

Run the same explicit installation flow from a newer trusted checkout. Approval
binds its file hashes, destination directory identities and previous launcher.
A changed source, replaced destination or changed launcher requires a new review.
An unrelated existing `acfs-fleet` file or symlink is never overwritten.

Each distinct cohort gets its own immutable-by-convention release directory.
The active symlink changes only after all files and the final manifest are
written, synced and verified. The update retains every previous release.
Interrupted writes retain their partial evidence and leave the old launcher
usable. An incomplete release is refused, not overwritten or deleted on retry.
There is no garbage collection, forced repair or destructive rollback command.
Concurrent cooperating installations use an exclusive kernel directory lock.

**Keep the runtime ID with the operation's private records, outside its strict
journal directory.** Fleet preparation approval includes controller-derived
policy bytes; recovering an old operation with different code may be refused.
The install result includes `pinned_launcher`, an absolute entrypoint for that
exact retained cohort. Invoke it directly to use the original code after an
update. Do not edit or rehash an old journal to bypass a changed-policy refusal.

## Validation

```bash
python3 -B tests/unit/test_fleet_runtime.py -v
```

These tests run the actual frontend and installer with real private files and
unprivileged child processes. Controller peers record arguments and perform no
SSH, provider request, agent launch, or work dispatch. Tests cover installation
without the checkout, upgrades, retained releases, literal arguments, stdin,
exit/signals, damaged/partial releases and refusal boundaries. They do not replace
full acceptance against installed ACFS hosts and authenticated providers.
