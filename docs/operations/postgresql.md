# PostgreSQL 18 on supported Ubuntu LTS hosts

`db.postgres18` is an explicit, optional module. It installs both the PostgreSQL
18 server and client packages, not merely whatever version provides `psql`.
Select it with the normal installer module selection (`--only db.postgres18`).
The normal Ubuntu upgrade/checkpoint rules still apply before module execution.

Ubuntu 26.04 includes PostgreSQL 18, so ACFS uses the configured Ubuntu package
repositories without adding a PGDG repository or downloading another signing
key. Ubuntu 22.04 and 24.04 use the PostgreSQL project's signed repository for
**their own** release: `jammy-pgdg` or `noble-pgdg`. Unknown distributions,
version/codename mismatches, and end-of-life interim releases are refused before
repository writes or network calls. No fallback maps an interim release to
Noble packages or silently installs an older PostgreSQL major.

The installed check and first generated doctor check require both packages to
be fully configured and the version-specific server/client binaries to report
major 18. An unrelated `psql` on PATH, a client-only installation, a partially
configured package, and an older running database do not satisfy that check.
The separate PostgreSQL service check remains a diagnostic; package presence
and binary versions alone do not establish a healthy database service.

## Existing installations and recovery

PostgreSQL majors can coexist. Installing this module does not migrate or delete
old clusters, run `pg_upgradecluster`, change authentication, create superusers,
open firewall ports, or expose the service on external interfaces. Review and
back up existing databases before performing any separate major-version data
migration. Normal package scripts retain their usual cluster/service behavior.

APT refresh must succeed for every configured repository, and installation uses
`--no-remove`. A broken repository or an incompatible package solution is a
failure, not permission to remove packages or reuse stale metadata. ACFS does
not weaken signature/freshness checks or ignore package failures.

On the PGDG path, an existing `pgdg.list` must exactly match the requested
release and signing-key location. A customized, disabled, or wrong-release file
is preserved and requires operator review. Key/source symlinks, hardlinks, and
special files are refused. Key bytes are staged before becoming available to
APT, and failed staging remains for inspection. A retry with an already matching
repository and nonempty keyring does not download or rewrite them.

On 26.04, existing third-party APT configuration is left untouched. In
particular, a previously configured wrong-release PGDG source is **not** silently
removed or rewritten. Review that source separately if it causes APT to fail;
then retry the same module selection. The native path avoids introducing this
mismatch on a fresh installation, not repairing every possible prior APT setup.

## Verification

```bash
python3 -B tests/unit/test_postgresql_install.py
```

These host-safe tests execute the actual authored Bash blocks with fixed paths
redirected in memory and package/network commands replaced by fixtures. They
cover release selection, exact package/version checks, idempotent repository
setup, input preservation, and failure propagation. They do not install packages.

The separate `--live-package` test is **only** for a fresh disposable Ubuntu
container with `ACFS_POSTGRES_DISPOSABLE=1`. It installs the actual packages,
repeats provisioning, starts the disposable cluster when needed, checks the
server's reported major, and performs a transaction with a temporary table.
It does not certify a full VPS bootstrap, OS upgrade, or existing-data migration.

Source policies: PostgreSQL's Ubuntu package instructions at
https://www.postgresql.org/download/linux/ubuntu/ and Ubuntu's native package at
https://packages.ubuntu.com/resolute/postgresql-18. Recheck those sources before
adding another supported release or changing repository policy.
