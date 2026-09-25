# Restore an exported module selection

`acfs export-config` records what is installed, but a version inventory is not a
machine image. `scripts/import-config.py` provides the reverse path for **module
selection**: validate an export, resolve its dependencies with the ordinary ACFS
installer, and optionally install that selection on the destination.

Run the helper with Python 3 from a **trusted, complete ACFS checkout**. It is a
bootstrap helper, not a new installed `acfs` subcommand. It never downloads an
installer named by the export and does not execute exported text as shell code.

## Migrate to another host

On the source host:

```bash
acfs export-config --json --output acfs-export.json
```

Copy that file to the destination. From the destination's trusted ACFS checkout,
preview the resolved plan without starting an installation:

```bash
python3 scripts/import-config.py /path/to/acfs-export.json
python3 scripts/import-config.py /path/to/acfs-export.json --json
```

After reviewing the module list and dependency plan, run:

```bash
python3 scripts/import-config.py /path/to/acfs-export.json --apply
```

The normal installer handles privileges, preflight checks, checksums and
checkpoints. For an explicitly non-interactive restore, add `--yes`. To request
its resume behavior explicitly, add `--resume`. The helper preserves the real
installer's exit status, including partial failures, rather than printing a
success result merely because it started a child process.

The default mode is **safe**, even when the source export says `vibe`. Choose
`--mode vibe` explicitly to opt into that mode on the destination. Restore
commands always include `--skip-ubuntu-upgrade`; a configuration migration is
not an implicit operating-system upgrade. Use the ordinary installer separately
for an intentional OS upgrade.

## Input and output contract

All three exporter formats are accepted: default YAML, `--json`, and `--minimal`.
For example, `acfs export-config --output acfs-export.yaml` can be restored with
`python3 scripts/import-config.py acfs-export.yaml --apply`.

YAML support deliberately covers the block mappings, quoted scalars and module
list emitted by ACFS, without requiring PyYAML. It does not accept arbitrary YAML
features such as tags, anchors, aliases, merge keys or multiline scalars. Use the
JSON export for other tooling rather than hand-authoring a richer YAML dialect.
Duplicate sections and fields are refused, not silently overwritten.

Minimal
files contain one canonical module ID per line, with optional blank lines and
`#` comments. UTF-8 BOM and CRLF are accepted. Use `-` to read from stdin; applying
from stdin also requires `--yes`, because the export consumes the input stream.

Empty selections, malformed IDs, duplicate JSON keys and oversized inputs are
rejected. Repeated module IDs are deduplicated without changing their order.
Unknown modules and dependency failures are rejected by the installer's existing
`--print-plan` resolver **before** installation. The helper does not maintain a
second dependency graph or bypass dependencies with `--no-deps`.

`--json` emits a preview document with schema `acfs.config-import.v1`, the
normalized module list, destination mode, installer argv and resolved plan.
It cannot be combined with `--apply`, whose terminal belongs to the installer.
`--plan-timeout` bounds planning (default 60 seconds, maximum 300), not the actual
installation. `--installer /trusted/checkout/install.sh` selects another local
installer explicitly; this is an executable trust decision, not an export field.

## Install only the missing modules

For an additive restore on a host that already has ACFS, capture a **fresh
export on that destination** and supply it separately:

```bash
acfs export-config --minimal > destination.modules
python3 scripts/import-config.py source-export.yaml --against destination.modules --json
python3 scripts/import-config.py source-export.yaml --against destination.modules --apply
```

The report separates `missing`, `already_present` and `extra` modules. Only
missing modules become explicit installer selections; their dependencies still
go through the ordinary resolver. Extras are reported, never uninstalled. An
empty delta returns `status: "noop"` and does not invoke the installer at all,
including with `--apply`. It cannot fall back to the installer's full default
selection. An empty destination export is valid; an empty source export is not.

Comparison is based on the supplied snapshot (`comparison.basis` is
`supplied_export`), **not a live health check**. A stale or wrong-host destination
export can hide missing or broken tools. Omit `--against` to submit the complete
source selection to the installer, or refresh the destination export before
applying. Credentials and versions are not compared. The JSON report retains
all desired `modules` and separately records the reduced `install_modules`.
Only one input may be stdin; either stdin input requires `--yes` when applying.

## What is deliberately not restored

The helper does not restore credentials, SSH keys, API tokens, source-host paths,
accounts, source-host state/checkpoints, arbitrary dotfiles, or recorded tool
versions. Versions in the export remain an inventory; installation uses the
selected checkout's ordinary verified installers. Extra destination modules are
not removed, and the installer retains its existing installed-module checks.
Authentication remains a separate destination-host task.

## Tests

```bash
python3 -m unittest discover -s tests/unit -p test_import_config.py -v
```

Tests use real files, pipes and subprocesses with an inert installer fixture.
They verify parsing, safe defaults, exact argv, resolver refusal, timeout cleanup,
startup-hook isolation, stdin handling, YAML handling, snapshot deltas, no-op
restores and exit-status/signal propagation. They do not
perform a privileged installation or claim a fresh Ubuntu VM end-to-end result.
