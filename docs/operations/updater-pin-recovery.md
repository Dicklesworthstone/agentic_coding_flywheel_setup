# Updater installer-pin failures

A downloaded installer is executable only after its exact bytes match a trusted
entry in `checksums.yaml`. A mismatch can indicate a stale published pin or
unexpected upstream content; repeated downloads are not evidence of trust.

## Recovery behavior

The verifier can refresh checksum metadata once using its existing trusted
metadata path. If the refreshed pin matches the bytes already downloaded, those
same bytes are accepted without downloading them again. A different URL or pin
can justify one new download and verification. An unchanged URL/pin pair is not
retried after rejection. The updater does not run Claude's identical reinstall
fallback after a checksum refusal, even with `--force`.

The verified-installer boundary returns a distinct internal checksum result.
It is created only before executing the downloaded installer, using the
verifier's structured failure reason rather than searching human log messages.
An installer exiting with that reserved status is treated as an ordinary failed
installer, not as a pre-execution pin refusal. Missing or malformed pins also
block execution. Network errors remain eligible for the existing bounded retry
policy; active holds and rollback backoff still take precedence.

## Operator output

Pin-blocked updates remain included in the existing failed-tool count and
process exit convention (1 for total failure, 2 for partial failure). They are
also listed separately under `CHECKSUM BLOCKED`, including in `--quiet` output
and the update log. A working existing binary cannot turn a refused checksum
into a successful update or a transient-outage skip.

Read the verification diagnostics and review the published `checksums.yaml`.
Maintainers must independently review upstream changes before updating pins and
run the canonical manifest generator afterward. Never make the expected hash
match merely to silence a failure. End users can explicitly hold the affected
tool while its published metadata is investigated. No hold is created for them.

This is not a transaction for the entire update run: earlier tools may already
have been updated when another tool is blocked. The updater does not weaken
verification, change pins automatically outside its existing metadata refresh,
or launch a live update as part of the regression tests.

## Regression coverage

```sh
python3 -B tests/unit/test_update_pin_failures.py
```

These tests source the complete updater and security library. Network download
and installed-binary discovery are controlled fixtures; real hashing, exact-byte
verification, inert shell execution, background and pipeline exit propagation,
retry dispatch, and summaries use the production functions. They do not call
public installer endpoints or install packages. Live fleet acceptance and the
external automated setup checker are separate requirements.
