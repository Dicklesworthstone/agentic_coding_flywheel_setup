# Check installed plugin health without reinstalling

`plugin:install --status` reports saved installation state; it does not prove the
installed tools still exist. Use `--check` for a live verification sweep of a
previously reviewed plugin selection without downloading or running installers.

Run from `packages/manifest` as the matching non-root Linux target user, with the
same archive, independent review, target tuple and module selection used to
install. For example:

```bash
bun run plugin:install \
  --archive /path/to/example-tools.tar.gz \
  --review /trusted/reviews/example-tools.json \
  --target ubuntu/26.04/x86_64/glibc \
  --only plugin.example_tools.cli \
  --check --json
```

The target is an example, not a platform-support declaration. The actual host
must match the reviewed tuple. Archive and review validation runs again on every
invocation; a saved receipt, saved plan or health result is not trust authority.
A changed plan identifies a different receipt and cannot inherit old completion.
An expired review must be renewed independently; `--check` cannot bypass it.

## Results and exit codes

JSON uses `{ "status": "checked", "mode": "check", "health": { ... } }`.
`health.schema` is `acfs.plugin-install-health.v1`. The nested result includes
the plan and receipt digests, recorded receipt status, whether checks actually
ran, and per-prerequisite and per-module pass/fail evidence.

| `health.status` | Meaning | Exit |
| --- | --- | --- |
| `healthy` | Receipt and every action are complete; all current checks passed. | 0 |
| `unhealthy` | Saved installation is complete, but a current check failed. | 1 |
| `incomplete` | Checks ran, but the receipt or an action is not complete. | 1 |
| `busy` | Another process holds the existing execution lock; nothing was checked. | 1 |
| `interrupted` | An action has ambiguous `running` state; nothing was checked. | 1 |
| `not_started` | No receipt exists for this exact plan; nothing was checked. | 1 |

Invalid options return 2. Verification/trust/state errors return 1 with a
`failed` result and diagnostic rather than a partial success. SIGINT and SIGTERM
return 130 and 143. Do not interpret the outer `checked` label as a health pass;
require exit zero and `health.status: "healthy"`. Human output names failed
prerequisites and modules without exposing raw command output.

## Boundaries

Health checking runs canonical first-party verification commands and checks
plugin executable availability in the controlled target-user PATH. Plugin
binaries themselves are not executed. This does **not** certify their versions,
contents, authentication, provider access or end-to-end functionality. Canonical
prerequisite commands may contact local or network services; this is not an
assertion of offline execution or a filesystem/network sandbox.

The existing inherited lock remains held throughout the sweep. No state
directory, lock file or receipt is created, and receipts are not rewritten.
Malformed, unsafe or changing state fails closed. The complete sweep has a
120-second deadline, in addition to existing per-command timeouts and process
group cleanup. Cancellation never produces a healthy result.

Do not combine `--check` with `--status`, `--dry-run`, `--yes`, plan/receipt
approval, recovery or cache options. Default previews and `--status` keep their
existing no-health-command behavior. Checking never installs, repairs, recovers
or silently marks work complete. For `interrupted`, inspect with `--status` and
follow the explicit [recovery workflow](plugin-review-workflow.md). For drift,
review a separate installation/retry plan rather than treating a health check as
permission to repair the machine.

## Regression tests

```bash
cd packages/manifest
bun test src/plugin-health.test.ts src/plugin-health-cli.test.ts
bun run type-check
```

Run execution cases as a non-root Linux user. The root-refusal case is also tested
separately under root in the regression workflow. Tests use real subprocesses,
receipts and locks for runtime behavior; CLI dispatch tests also exercise the
existing in-process service seams without relaxing production trust loading.
