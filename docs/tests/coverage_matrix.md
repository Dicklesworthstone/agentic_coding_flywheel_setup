# Test Coverage Matrix (No Mocks)

This matrix defines **real-data** coverage goals. “No mocks” means tests must use
actual files, generated scripts, and real flags/CLI behavior rather than stubs.

## Legend
- **Current**: observed coverage today
- **Target**: desired coverage state
- **Fixtures**: real files used by tests

## Matrix

| Component | Current | Target | Fixtures (real files) | Notes |
| --- | --- | --- | --- | --- |
| `packages/manifest` schema + parser | Partial (`test-edge-cases.ts`) | Full unit suite | `acfs.manifest.yaml`, `docs/reference/MANIFEST_SCHEMA_VNEXT.md`, generated `scripts/generated/manifest_index.sh` | Add fixture-driven tests for schema fields + errors |
| `packages/manifest` generator outputs | Minimal | Full unit suite | `acfs.manifest.yaml`, `scripts/generated/*.sh` | Validate deterministic ordering + content |
| `scripts/lib/install_helpers.sh` (selection) | None | Unit + integration | `scripts/generated/manifest_index.sh` | Exercise `--only/--skip/--only-phase/--no-deps/--print-plan` via real arrays |
| `scripts/lib/contract.sh` | None | Unit | `scripts/lib/contract.sh` | Verify error cases + required env checks |
| `scripts/lib/security.sh` | Partial | Unit + integration | `checksums.yaml` | Verify checksum load + verify output (no network mocks) |
| `scripts/preflight.sh` | None | Unit + integration | `scripts/preflight.sh` | Run in controlled envs; validate expected warnings/errors |
| `install.sh` selection/introspection | Partial (manual) | Unit + integration | `install.sh`, `scripts/generated/manifest_index.sh` | Ensure plan output is stable + no state mutation |
| `tests/vm/test_install_ubuntu.sh` | Present | Enhanced E2E | `tests/vm/test_install_ubuntu.sh` | Add explicit selection + bootstrap cases |
| `tests/vm/test_acfs_update.sh` | Present | Enhanced E2E | `tests/vm/test_acfs_update.sh` | Standardize logging + artifacts |
| `tests/vm/resume_checks.sh` | Present | Enhanced E2E | `tests/vm/resume_checks.sh` | Add selection/plan integration when ready |
| Web wizard E2E | Present | Maintain + richer artifacts | `apps/web/e2e/wizard-flow.spec.ts` | Add runner script with logs + traces |

## Gaps (Immediate)
- No unit coverage for bash libs (selection/contract/security/preflight).
- Generator output tests rely on manual verification.
- E2E logging is not standardized (timestamps/sections/artifacts).

## Next Steps
- Implement fixture catalog (docs/tests/fixtures_catalog.md).
- Create test harness for bash libs (shell-based, real files).
- Add standardized logging helper for `tests/vm` scripts.
