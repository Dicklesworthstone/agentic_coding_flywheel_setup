# Diagnose a doctor JSON report in the wizard

The Status Check step includes **Diagnose a doctor JSON report locally** below
the ordinary health-check content. It compares a real report with the current
dependency-complete module selection, including an adopted team profile.

On the intended VPS, as the configured installation account, run:

```bash
acfs doctor --json
```

Save the JSON output to a local file and choose it in the panel. A nonzero doctor
exit can still produce a valid diagnostic report. Do not include terminal
prompts, stderr, or surrounding prose. The reader accepts one nonempty UTF-8 JSON
file up to 1 MiB. It never uploads the report, saves it in browser storage,
changes preferences, executes a suggested fix, or acknowledges a doctor run.

## What the comparison means

The table shows each selected module, the worst result among its mapped checks,
and how many checks were reported. Exact manifest IDs and generated `.N` check
IDs are mapped directly. A small explicit map covers the current doctor's
language, agent, shell, and core-tool aliases. Labels, details, and suggested
shell commands never determine module ownership.

Absent checks are **No mapped checks**, not successful checks. Skips and timeouts
also remain unverified. A row with reported passes does not establish complete
test coverage for that module. Multiple checks aggregate conservatively: fail,
timeout, warning, skipped, then pass. Known modules outside the selection and
unmapped/system checks have separate totals. Failures in those groups remain
visible and cannot be used as permission to install excluded modules.

The reader validates the report's totals against the individual checks. The
doctor counts timeouts as warnings in its summary; this panel separates them
while checking that combined tally. Duplicate check identities, duplicate
decoded JSON keys, invalid statuses, malformed timestamps, invalid UTF-8, and
over-budget inputs are refused instead of allowing a later pass to hide a
failure. Reports with changed formats need an explicit reader update.

Reported account and install mode are compared with the wizard's effective
settings. Mismatches are called out without exposing the raw account value.
The panel also calls out an OS different from the recommended destination and
timestamps more than 24 hours old or five minutes ahead at the time of reading.
Those age indicators are snapshots, not an ongoing clock or monitoring service.

## Trust and privacy boundaries

Current doctor JSON has no host identity, architecture, selection digest, or
manifest/checksum attestation. Even a matching username, mode, and OS cannot
prove the report belongs to the intended VPS. The displayed SHA-256 identifies
the exact file bytes; it does not authenticate their origin. Confirm the source
yourself and inspect the original report privately for detailed diagnostics.

The public review contains canonical module IDs, sanitized status counts,
bounded OS metadata, a normalized timestamp, and the file digest. Raw labels,
details, usernames, unknown check IDs, and suggested commands are not retained
in the review or rendered. The raw report can still contain secrets; avoid
sharing it unredacted. The panel deliberately does not offer raw-report export.

Changing the target, account, mode, exact installer command, selected modules,
or catalogue identity discards the local review. A delayed read from a previous
context cannot replace a newer result. Selecting another file, clearing the
panel, or leaving the page cancels publication of earlier reads. Nothing is
restored from a saved report object or browser cache.

## Recovery remains an explicit decision

For selected modules with reported failures, the panel identifies the modules
and points back to the existing exact installation/recovery workflow. It does
not generate commands from the report's `fix` strings or automatically rerun
the installer. Inspect logs and any running upgrade first. The ordinary doctor
acknowledgement remains separate: importing a report never sets it, and a report
does not independently unlock onboarding or assert remote success.

## Tests

```bash
cd apps/web
node --test lib/doctorReport.test.mjs lib/doctorReport.emitter.test.mjs components/doctor-report-panel.test.mjs
bun run type-check
bun run lint
bun run build
```

The reader tests execute the actual parser and comparison with native Blob,
UTF-8, and Web Crypto behavior. Panel tests additionally substitute React hooks,
the already-validated health context, and UI primitives; they are not browser
renderer tests. A production-emitter integration test exercises the existing
Bash JSON emitter with controlled check data, not a live machine diagnosis. It
reads the current repository's `scripts/lib/doctor.sh` by default. The test-only
`ACFS_DOCTOR_TEST_SOURCE` override allows a fetched emitter snapshot in a partial
checkout; runs using it must identify that limitation rather than claim full
doctor or full-checkout integration.
