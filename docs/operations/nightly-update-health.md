# Nightly update execution health

`acfs status` now includes the persisted nightly updater's execution result.
A host that deferred its updates every night must not look healthy merely
because its command-line tools are still installed. The nightly wrapper's
resource checks and bounded retries are unchanged; this integration observes
their result without initiating any work.

## Inspect the result

Run as the account whose ACFS installation you are inspecting:

```bash
acfs status
acfs status --short
acfs status --json
```

A resource-blocked installation reports, for example:

```text
ACFS WARN: 27 tools; nightly: retry budget exhausted (load); 4 skipped night(s) since last full success
```

The count is **skipped nights since the last full success**, not necessarily
consecutive calendar nights. Retries on the same date do not add nights.
Observing status never clears this history; only a fully successful update
resets it. A partial update remains a failure for this purpose.

Human output includes the reason. Short output returns `WARN`. JSON adds a
`nightly_update` object alongside the existing status fields:

```json
{
  "health": "warn",
  "code": "skipped",
  "state": {
    "outcome": "skipped",
    "reason": "load",
    "skipped_nights": 4,
    "last_attempt_epoch": 1791777600,
    "last_success_epoch": null,
    "next_retry_epoch": null
  }
}
```

The numbers above are illustrative Unix timestamps. A recorded success has
`health: "pass"`; no record has `health: "skip"`, `code: "not_recorded"`, and
`state: null`. Absence is not a success and does not by itself warn installations
that never enabled the timer. Existing installation errors retain exit code 2;
nightly warnings use exit code 1. The editor contract (`--ide`) inherits the
aggregate warning without changing its schema or querying live sessions.

## Interpret warnings

`skipped` means the resource-check retry budget was exhausted. `retrying` means
a retry was recorded; more than five minutes beyond that deadline becomes
`retry_overdue`. `running` means an update was recorded in progress, not that a
process was proven alive. After the two-hour service budget plus five minutes,
that record becomes `run_overdue`.

`failed` includes partial updates, while `interrupted` records an unfinished
invocation. A success older than three days produces `stale_success`. Invalid
clocks or future-dated records produce clock warnings, not fresh success.

The data comes from `~/.acfs/nightly-update.state`, not scraped log text. The
reader is bounded, rejects ambiguous/trailing records including NUL suffixes,
and does not follow symlinked state files or read FIFOs. Invalid data produces
`invalid_state`; it is neither executed nor overwritten. Paths and raw record
contents are not echoed. Missing or old unsafe-to-source reader code produces
`reader_unavailable` when an execution record exists.

This is not upstream-version attestation, timer enablement detection, or a
live process check. A recent successful update can intentionally omit ACFS
self-update. No network, update, cleanup, timer change, or state write is made
by the new status integration. `acfs doctor` reports the same verdict as its
`updates.nightly_runs` check, with a fix hint for skipped, interrupted and
invalid records.

## Resource-checked manual retry

Inspect local update logs and fix the underlying resource condition first.
Run the installed wrapper once without waiting through its retry window:

```bash
ACFS_NIGHTLY_MAX_RETRIES=0 "$HOME/.acfs/scripts/nightly-update.sh"
```

This still checks load and disk and takes the normal update lock. It does not
force an update on an overloaded host. The ordinary default remains two more
resource checks at 30-minute intervals. Do not edit execution state to make
status appear healthy.

## Regression tests

```bash
python3 tests/unit/test_nightly_update.py
python3 tests/unit/test_nightly_health.py
bats tests/unit/lib/test_doctor_fix_args_and_holds.bats
bash -n scripts/lib/nightly_update.sh scripts/lib/status.sh
shellcheck scripts/lib/nightly_update.sh scripts/lib/status.sh
cd packages/manifest
bun run generate --diff
```

The tests load complete runtime source, not production excerpts. Reader tests
use real files and Bash; status tests control unrelated discovery. A connected
case drives the actual nightly wrapper through four skipped nights, a partial
failure, and success, checking status after each stage. Only resource metrics,
clock/sleep, cleanup, and the external updater are fixtures. No real update,
network request, systemd change, or live-host certification is claimed.
