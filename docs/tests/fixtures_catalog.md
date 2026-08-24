# Real Fixtures Catalog (No Mocks)

This catalog lists **existing** files used as real fixtures for tests. Do not
introduce synthetic mocks for core behavior; prefer these artifacts.

## Manifests
- `acfs.manifest.yaml` — Canonical module manifest (full real data set).

## Generated Artifacts (Real outputs)
- `scripts/generated/manifest_index.sh` — Deterministic module index with canonical category order and generated-ownership metadata.
- `scripts/generated/install_base.sh` — Source-only generated module library (base).
- `scripts/generated/install_users.sh` — Zero-handler source-only library; production owns the `users.ubuntu` handoff.
- `scripts/generated/install_filesystem.sh` — Source-only generated module library (filesystem).
- `scripts/generated/install_shell.sh` — Source-only generated module library (shell).
- `scripts/generated/install_cli.sh` — Source-only generated module library (CLI tools).
- `scripts/generated/install_network.sh` — Source-only generated module library (network).
- `scripts/generated/install_lang.sh` — Source-only generated module library (languages).
- `scripts/generated/install_tools.sh` — Source-only generated module library (tools).
- `scripts/generated/install_db.sh` — Source-only generated module library (db).
- `scripts/generated/install_cloud.sh` — Source-only generated module library (cloud).
- `scripts/generated/install_agents.sh` — Source-only generated module library (agents).
- `scripts/generated/install_stack.sh` — Source-only generated module library (stack).
- `scripts/generated/install_acfs.sh` — Source-only generated module library (acfs).
- `scripts/generated/install_all.sh` — Source-only generated-module harness; not a production entrypoint.
- `scripts/generated/doctor_checks.sh` — Generated doctor checks list.
- `scripts/generated/internal_checksums.sh` — Schema-1 data-only critical-script checksum ledger.

## Installer + Libs (Real logic under test)
- `install.sh` — Orchestrator entrypoint and CLI parsing.
- `scripts/lib/install_helpers.sh` — Selection + run helpers.
- `scripts/lib/contract.sh` — Module contract enforcement.
- `scripts/lib/security.sh` — Checksum verification logic.
- `scripts/preflight.sh` — Preflight validation script.

## E2E Harnesses (Real integration scripts)
- `tests/vm/test_install_ubuntu.sh` — Installer E2E (Docker).
- `tests/vm/test_acfs_update.sh` — Update E2E (Docker).
- `tests/vm/resume_checks.sh` — Resume logic checks.

## Web E2E Fixtures
- `apps/web/e2e/wizard-flow.spec.ts` — Playwright wizard flow tests.
- `apps/web/playwright.config.ts` — Runner configuration.

## Notes
- Generated artifacts should be regenerated via `bun run generate` before tests when manifest changes.
- Avoid “fake” YAMLs; if smaller fixtures are needed, derive them from real manifest subsets and commit them as real files.
