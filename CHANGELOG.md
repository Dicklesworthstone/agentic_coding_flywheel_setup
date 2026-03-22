# Changelog

All notable changes to the [Agentic Coding Flywheel Setup (ACFS)](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup) project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Each version links to its GitHub Release (where one exists) or to the tag comparison. Representative commits are linked for traceability.

---

## [Unreleased](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/compare/v0.6.0...HEAD)

> 427 commits since v0.6.0 (2026-02-02 through 2026-03-21). Internal version bumped to 0.7.0 in [`729822e`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/729822eb).

### Installer & CLI

- **`acfs services` command** for unified daemon management -- start/stop/restart all ACFS background services (Agent Mail, nightly timer, etc.) from one place ([`2d48c4b`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/2d48c4b1))
- **`--only` and `--only-phase` flags** allow selective tool or phase installation on fresh VPS installs, with OR semantics when combined ([`da096a7`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/da096a7c), [`287dc59`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/287dc596))
- **`--stack-only` flag** for `acfs update` to update only Dicklesworthstone stack tools ([`6199da1`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/6199da18))
- **`loginctl enable-linger`** so `systemctl --user` services survive SSH disconnects on fresh installs ([`fff5933`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/fff59332))
- **Verified installer framework** -- `install_asset_from_path` helper, DSR migrated to verified installer, 13 missing tool installers added ([`bcd4734`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/bcd47348), [`e81279f`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/e81279fa))
- **Version + commit hash shown** in `acfs update` output for traceability ([`711c06a`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/711c06a8))
- **8 new stack tools integrated** across install, update, and E2E test surfaces ([`7629cf1`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/7629cf11))
- **Atomic file writes** for workflow templates; CR stripped earlier in redirect parsing ([`1b0fb6a`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/1b0fb6ac))
- **Curl timeouts** added to prevent indefinite hangs during installs and updates ([`46a1bb9`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/46a1bb9c), [`47ff6a6`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/47ff6a6e))
- **`acfs update` self-update orphan recovery** and MDWB `--yes` flag ([`bb62f5f`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/bb62f5f8))
- Fixed `--only` flag overriding resume skip logic; fixed Gemini `trustedFolders` format ([`831add0`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/831add05))
- Fixed missing tools phase 5 dispatch ([`729822e`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/729822eb))
- Fixed duplicate `esac` causing syntax error on fresh installs ([`3ddba53`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/3ddba53e))
- Fixed symlink repair path for agent-mail binary ([`7717fdd`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/7717fdd7))
- Fixed dots in usernames and added agent-mail flag corrections ([`e81279f`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/e81279fa))
- Restored accidentally deleted verified installer functions ([`137f7b9`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/137f7b94))
- Resolved `acfs update` failures from unbound variable and untracked files ([`1f76ef9`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/1f76ef9e))
- Corrected four `acfs doctor` secondary checks that always warned ([`17093da`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/17093dab))

### Agent Mail

- **MCP Agent Mail as systemd managed service** -- replaces tmux-spawn with proper systemd unit, `LimitNOFILE=65536`, `Restart=always`, backend auto-detection ([`17d2fd4`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/17d2fd47), [`a806cc5`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/a806cc5a))
- **Service lifecycle overhaul** -- target-context execution, expanded manifest drift detection ([`5db9a70`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/5db9a708))
- **Switched from Python to Rust installer** ([`e9cdfb1`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/e9cdfb1e))
- Fixed `--dest` vs `--dir` and removed invalid `--no-start` flag ([`fbbaaa3`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/fbbaaa3e), [`18192b9`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/18192b9f))
- Health endpoint polling for success detection ([`42f3ad0`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/42f3ad0b))
- Spurious `--` separator removed from s2p and brenner_bot installer args ([`4e8129d`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/4e8129de))

### Web Application

- **Complete Guide rewrite** -- converged on narrative-post style with interactive visualizations, exhibit panels, and QuickNav across multiple iterations ([`700b2c2`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/700b2c20), [`5d77488`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/5d774887), [`f7cd53f`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/f7cd53f7))
- **Core Flywheel page** (`/core-flywheel`) with 4 new interactive visualizations and dedicated OG/Twitter share images ([`478c56f`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/478c56f6), [`a59fea1`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/a59fea19))
- **15 new lesson components** for the onboarding Learning Hub, covering RCH, WezTerm, Brenner, GIIL, S2P, and 7 utility tools ([`fd30a07`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/fd30a07a), [`3552ce6`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/3552ce6a))
- **Persistent wizard state** -- VPS checklist and checked-services state survive page reloads ([`df5b451`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/df5b4515), [`b0c16e3`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/b0c16e3e))
- **Research-driven feature planning** section in Complete Guide ([`f429d92`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/f429d923))
- **Zod schema validators** for VPS wizard IP validation, replacing inline regex ([`0fc907c`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/0fc907cb))
- **TanStack Query** for user preference hooks, replacing local `useState` ([`9bed651`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/9bed6515))
- **`/core_flywheel` route renamed to `/core-flywheel`** for URL consistency ([`0cd2bb8`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/0cd2bb86))
- **Accessibility overhaul** -- focus states, contrast, ARIA labels, reduced motion, touch targets, escape-key modals ([`f302394`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/f3023941), [`2e7068a`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/2e7068aeb), [`8831d4f`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/8831d4fe))
- **Premium UI polish** -- bottom sheet with swipe gestures, EmptyState component, CodeBlock line hover, fluid display typography tokens ([`2dee1e8`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/2dee1e81), [`a3e557d`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/a3e557de), [`b4ebc96`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/b4ebc966))
- OG/Twitter metadata added for social sharing cards across all pages ([`cf89907`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/cf899071), [`df0ff5e`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/df0ff5e6))
- Fixed keyboard handlers gated on viewport visibility to prevent multi-viz conflicts ([`903180b`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/903180b8))
- Model references updated in lesson components ([`f966b3d`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/f966b3dc))
- `node` to `bun` symlink removed ([`d988e73`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/d988e735))

### Manifest & Security

- **Manifest schema hardening** -- pre-install checks, extended drift detection, topo-sort consolidation ([`2b8ddb7`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/2b8ddb70), [`08cc1df`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/08cc1df8))
- **Internal script integrity verification** at install time ([`3fb952a`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/3fb952ad))
- **`KNOWN_INSTALLERS` URLs synced from `checksums.yaml`** at load time to prevent drift ([`9c0b631`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/9c0b6311))
- **GitHub Actions hardened** against script injection and race conditions ([`3312d8b`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/3312d8b9), [`1df8159`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/1df8159a))
- **Shell scripts hardened** against unsafe inputs and edge cases ([`e6031c9`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/e6031c99))
- `systemctl --user` pre-check applied to manifest source ([`f1f8276`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/f1f8276e))

### Shell & Scripting

- **Deep codebase audit** (3 rounds) fixed 16+ bugs across scripts and web ([`f733392`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/f733392b), [`3b1cbbf`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/3b1cbbf4), [`eb8b5c4`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/eb8b5c45))
- **`fd` alias no longer shadows `find`**; fzf keybinding disable var corrected ([`0b09aef`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/0b09aef1))
- **POSIX regex compatibility**, SLB source build, model reference updates ([`1e389fe`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/1e389fe7))
- **Onboard: sparse lesson numbers** supported; progress file validated with file locking ([`46dd0d7`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/46dd0d71))
- Bash arithmetic hardened across test scripts and installer ([`d50cb58`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/d50cb584), [`5b04cd6`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/5b04cd66))
- `br-agent-instructions` canonical markers added to generated `CLAUDE.md` ([`dff802d`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/dff802d8))
- `gmi` alias converted to auto-update+patch function; `uca` alias hardened ([`5ba4916`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/5ba49169))
- Subprocess spawns reduced in state management and apt install for performance ([`99f1023`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/99f10238))

### Testing

- **Expanded test suites** -- E2E, unit, and VM tests for installer, doctor, newproj, and web ([`5d1b2f2`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/5d1b2f28), [`e851325`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/e8513250))
- **Comprehensive tests for 9 new Dicklesworthstone tools** ([`0ce1d0c`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/0ce1d0cc))
- POSIX-correct grep patterns (`grep -qiE` instead of `grep -qi 'A\|B'`) ([`ee925a1`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/ee925a19))

### Infrastructure

- **Systemd timer** for daily unattended `acfs-update` ([`18c52d8`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/18c52d8d))
- **Automated manifest drift detection** and auto-fix script ([`1e34eb6`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/1e34eb69))
- **ntfy.sh push notifications** for agent task lifecycle with debouncing ([`32c718e`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/32c718e4), [`f171fca`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/f171fca2))
- MIT + OpenAI/Anthropic Rider license adopted ([`a6b3bbe`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/a6b3bbe0))
- GitHub social preview image added ([`6afb503`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/6afb5036))

---

## [v0.6.0](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/releases/tag/v0.6.0) -- 2026-02-02

> 308 commits since v0.5.0. [Compare with v0.5.0](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/compare/v0.5.0...v0.6.0).

### Binary Rename (bd to br)

- **Complete `bd` to `br` migration** across the entire project -- the `beads_rust` binary is now exclusively `br` everywhere ([`1d7fd86`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/1d7fd866))
- Removed stale `alias br='bun run'` from older ACFS versions using `whence -p br` detection ([`1d7fd86`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/1d7fd866))
- CLI flags renamed: `--no-bd` to `--no-br`; env vars renamed: `AGENTS_ENABLE_BD` to `AGENTS_ENABLE_BR` ([`1d7fd86`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/1d7fd866))
- Bead IDs (`bd-XXXX`) preserved as historical identifiers

### Expanded Tool Ecosystem

- **5 new tools integrated**: APR, JFP, Process Triage, X Archive Search, Meta Skill (MS) ([`2ad1fe9`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/2ad1fe96), [`d6884fe`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/d6884fe4))
- **SRPS (System Resource Protection Script)** added to flywheel stack ([`b813d1d`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/b813d1df), [`017ccfd`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/017ccfd5))
- WezTerm Automata (WA) and Brenner Bot lesson components and test suites ([`f746315`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/f7463155), [`25c3a2d`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/25c3a2d3))
- BR and RCH integration tests, onboarding lessons, and installer overhaul ([`127db22`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/127db221), [`dd9996b`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/dd9996b9))
- Comprehensive TL;DR page showcasing all flywheel tools ([`ca3e95a`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/ca3e95a5))

### Installer Hardening

- **Crash-safe change recording and undo system** for autofix ([`8d28a12`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/8d28a12d))
- **`--pin-ref` flag** for pinned installations with wizard command builder integration ([`2cd7c72`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/2cd7c72b), [`8cb670c`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/8cb670c1))
- **Pre-flight warning auto-fix system** ([`654c2d4`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/654c2d43))
- **Shell completion scripts** for bash and zsh ([`f511fb6`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/f511fb68))
- **Stderr log file capture** and **JSON summary emission** ([`b88e424`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/b88e424b), [`f67bbf1`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/f67bbf19))
- **`needrestart` apt hook disabled** to prevent installation hangs ([`68fbb8a`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/68fbb8ad))
- **Batch cargo installs** optimization ([`ec45b76`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/ec45b76e))
- **ACFS self-update** as first operation in update command with self-update orphan recovery ([`97f15b5`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/97f15b56))
- Tool installation tracking for failed tools ([`1e2a8c5`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/1e2a8c57))
- Silent exit on Ubuntu 25.04 (bash 5.3+) prevented ([`18bb3bb`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/18bb3bbf))
- NTM command palette wired during installation ([`cfd9ff3`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/cfd9ff3d))
- Claude Code switched to `latest` channel ([`5b975a8`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/5b975a8f))

### Web Application

- **Dynamic OG images** for social sharing ([`b720937`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/b7209374))
- **Comprehensive OG images** for all sections including lessons ([`47ca275`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/47ca275d))
- **Dark/light/system theme toggle** ([`5f19854`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/5f198546))
- **VPS provider comparison table** ([`cfc3c49`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/cfc3c496))
- **Personalized command builder panel** with pinned ref toggle ([`efd6338`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/efd63384), [`8cb670c`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/8cb670c1))
- **Contextual help button** with per-step troubleshooting ([`993b7b0`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/993b7b01))
- **Copy-to-clipboard** on all wizard code blocks ([`0fbec04`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/0fbec04c))
- **Centralized step validation** before navigation ([`a3111d9`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/a3111d9e))
- **Manifest-driven web generation** with web metadata consumed from manifest ([`f20c6d2`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/f20c6d2f))
- Vercel monorepo deployment configuration ([`8fe3a45`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/8fe3a452))
- Zod 4 migration ([`5a51fa1`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/5a51fa18))
- Wizard step 5 UX improvement for VPS IP entry ([`98959a3`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/98959a31))

### Doctor & Diagnostics

- **`acfs doctor --fix` and `--dry-run` modes** for automatic remediation ([`c6238fa`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/c6238fa0))
- **`acfs status` one-line health summary** ([`9d13efcb`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/9d13efcb))
- **`acfs support-bundle`** diagnostic collection with redaction rules ([`77da131`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/77da131e), [`cde5241`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/cde5241a))
- **Per-module fix suggestions** with mode awareness ([`dd0d4fc`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/dd0d4fc7))
- **Network health checks** in `--deep` mode ([`bf772ea`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/bf772ea0))
- ARM64 Linux meta_skill detection in doctor ([`dd2d121`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/dd2d1213))
- Critical bugs fixed in deep cloud auth checks ([`2272d2a`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/2272d2a4))

### Shell & Scripting

- **TOON output format support** and `--stats` flag for `acfs info` ([`3a0b15e`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/3a0b15e2), [`883baae`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/883baaea))
- **Dynamic lesson discovery** in onboard TUI ([`df66cea`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/df66cea3))
- **File locking and Ubuntu upgrade tracking** in state management ([`83f240d`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/83f240d8))
- Visual indicators added to log output functions ([`a746886`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/a7468864))
- `echo -e` replaced with `printf` throughout for robust logging ([`81147304`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/81147304), [`e0775f8`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/e0775f82))
- Session export sanitization enhanced ([`2c5b1e4`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/2c5b1e41))
- Hardened CLI argument parsing to reject flag-like values as option arguments ([`b094694`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/b094694c))

### Security

- **Composite pre-commit hook** to prevent manifest drift ([`513758a`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/513758a7))
- **Strict canary + release checksum gate** CI workflow ([`15540a7`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/15540a7d))
- **Cross-repo installer notification system** via GitHub Actions ([`893680f`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/893680f0))
- **Repo-dispatch workflow templates** for tool repos ([`be32a64`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/be32a648))
- Checksums auto-refreshed before stack updates ([`847d3fc`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/847d3fc9))
- JSON checksum verification log leakage prevented ([`202975a`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/202975ac))
- Race condition in atomic writes prevented by setting ownership before rename ([`27d5fc9`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/27d5fc96))

### Testing & CI

- **Comprehensive E2E test infrastructure** including Playwright tests and CI verification ([`4e341c0`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/4e341c07), [`4146aa3`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/4146aa31))
- **Unit tests expanded** with command stubbing and improved assertion helpers ([`37bfed2`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/37bfed29), [`2f58044`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/2f580442))
- **Functional smoke tests** for flywheel tools ([`289e0dd`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/289e0dd4))
- **Pipefail and TTY safety linters** ([`b09a6fa`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/b09a6fab))
- TOON integration tests workflow ([`90ccf65`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/90ccf65e))
- CI: SLB installed via `.deb` to avoid GitHub API rate limits ([`75a91c5`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/75a91c50))
- CI: apt preferred for zoxide to avoid rate limits ([`7b3b535`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/7b3b5357))

---

## [v0.5.0](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/releases/tag/v0.5.0) -- 2026-01-11

> 97 commits since v0.4.0. [Compare with v0.4.0](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/compare/v0.4.0...v0.5.0).

### DCG (Destructive Command Guard) -- Full Integration

- Complete DCG integration across website, installer, and onboarding ([`36ea411`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/36ea4116), [`26ca3d2`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/26ca3d2e))
- New DCG lesson in onboarding TUI and flywheel loop lesson ([`ee2b8bf`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/ee2b8bfd), [`3a94748`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/3a94748d))
- 88+ passing DCG tests covering edge cases, allow-once workflow, pack config, performance benchmarks, DCG+SLB layered safety ([`6d6df2f`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/6d6df2f3), [`98d53ad`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/98d53adf), [`c217bdf`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/c217bdfd))
- Old Python `git_safety_guard` removed -- DCG supersedes it ([`f1fd501`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/f1fd501f))

### RU (Repo Updater) -- Full Integration

- RU tool page added to learn section and webapp flywheel ([`cf8643b`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/cf8643b2))
- RU lesson component with structural tests and Playwright E2E tests ([`904ba8e`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/904ba8e8), [`fb4fc3d`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/fb4fc3dc))
- RU doctor and update integration tests ([`72746b9`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/72746b91))
- RU integrated into installer CI workflow ([`789d0e0`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/789d0e09))

### Onboarding

- **File locking for concurrent operations** prevents race conditions in progress tracking ([`9b34186`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/9b341867))
- **Dynamic lesson counts** derived from array length for maintainability ([`9b34186`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/9b341867))
- Lesson count updated from 9 to 11 (adding RU and DCG) ([`153d56e`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/153d56eb))
- Certificate and help text updated with RU/DCG skills ([`02a19ea`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/02a19ea9))

### Web Application

- **Error boundary for lesson rendering** catches JS errors with recovery UI ([`94566fb`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/94566fbi))
- **IPv6 zone ID validation** rejects zone IDs (like `%eth0`) in VPS IP input ([`98c16e7`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/98c16e75))
- `maxDelay` cap for stagger animations ([`692c857`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/692c8575))
- `prefers-reduced-motion` respected in button animations ([`c82fde1`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/c82fde12))
- Tool page split into server and client components ([`539cd66`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/539cd668))
- Comprehensive `flywheel.ts` unit tests ([`4cb9dcd`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/4cb9dcd8))

### Security & Reliability

- Category name validation in manifest to prevent injection ([`9c0e779`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/9c0e7791))
- Error handling improvements in `acfs_chown_tree` ([`66bc4af`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/66bc4af1))
- Manifest cycle detection consolidated (removed duplicate implementation) ([`cb05753`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/cb05753c))
- Unused `fallback_url` field removed from manifest schema ([`69d3e84`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/69d3e844))
- Nested hook structures handled in DCG removal ([`c2863bb`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/c2863bb7))
- LTS version format handled in upgrade detection ([`e90c3f8`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/e90c3f88))

---

## [v0.4.0](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/releases/tag/v0.4.0) -- 2026-01-08

> 3 substantive commits since v0.3.0. [Compare with v0.3.0](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/compare/v0.3.0...v0.4.0).

### New Flywheel Tools

- **Destructive Command Guard (DCG)** -- Rust-based Claude Code PreToolUse hook blocking dangerous git/fs commands with sub-millisecond latency. Replaces the simpler Python-based `git_safety_guard` ([`b770c9f`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/b770c9fa))
- **Repo Updater (RU)** -- 17K-line Bash tool for multi-repo sync plus AI-driven commit automation ([`b770c9f`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/b770c9fa))

### New Utilities

- **giil (Get Image from Internet Link)** -- downloads cloud-hosted images for visual debugging in SSH/headless environments ([`b770c9f`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/b770c9fa))
- **csctf (Chat Shared Conversation to File)** -- converts AI chat share links to Markdown/HTML archives with full formatting preservation ([`b770c9f`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/b770c9fa))

### Maintenance

- All documentation updated to reflect 10-tool stack
- Checksums added and verified for all 4 new installers
- Installer scripts regenerated from manifest
- Fixed test framework pollution of `/data/projects` ([`a7a94d3`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/a7a94d35))

---

## [v0.3.0](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/releases/tag/v0.3.0) -- 2026-01-07

> 29 commits since v0.2.0. [Compare with v0.2.0](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/compare/v0.2.0...v0.3.0).

### Security

- **Critical fix: command injection in `validate_directory()`** -- the old `eval echo "$dir"` for tilde expansion could allow arbitrary command execution; replaced with safe pattern matching ([`6c6e899`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/6c6e8996))

### TUI Wizard for Project Creation

- **Complete interactive TUI** with 9 screens: Welcome, Project Name, Directory, Tech Stack, Features, AGENTS.md Preview, Confirmation, Progress, and Success ([`540102a`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/540102a2), [`e971e12`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/e971e124))
- **Smart AGENTS.md generation** with tech stack detection for Python, Node.js, Rust, Go, Ruby, PHP, Java ([`ee1cf43`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/ee1cf435), [`7da31c7`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/7da31c77))
- TUI core framework with state management and navigation engine ([`5cd1921`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/5cd1921f))
- Error handling and recovery infrastructure ([`490b223`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/490b223d))
- Detailed logging infrastructure ([`9b29b04`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/9b29b04a))
- `.gitignore`, `.ubsignore`, and AGENTS.md templates included by default ([`6c993f7`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/6c993f74))
- Usage: `newproj --interactive` (TUI) or `newproj myproject ./path` (CLI)

### Testing Infrastructure

- **284 unit tests** using bats-core framework ([`04f740e`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/04f740ed))
- **53 E2E tests** covering happy paths, navigation, and error recovery ([`a28ebd1`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/a28ebd13))
- Expect-based TUI testing for full interactive workflow verification

### Bug Fixes

- ASCII box alignment in welcome screen ([`ee6d755`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/ee6d7553))
- File tree rendering for nested paths ([`068c571`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/068c571f))
- Tech stack display name in confirmation screen ([`9850cc5`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/9850cc5a))
- Safe arithmetic increment to avoid `set -e` failures ([`45f30b2`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/45f30b2c))
- Unconfigured git user handled gracefully ([`7c93951`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/7c93951a))
- SSH keepalive check and newproj install message corrected ([`a770657`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/a770657014))
- Claude auth and PostgreSQL role doctor checks fixed ([`7fa199a`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/7fa199a6))

---

## [v0.2.0](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/releases/tag/v0.2.0) -- 2026-01-06

> 21 commits since v0.1.0. [Compare with v0.1.0](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/compare/v0.1.0...v0.2.0).

### Documentation

- **README expanded by 1,000+ lines** with detailed technical documentation covering every major system component:
  - Tmux configuration deep dive with agent workflow optimizations ([`53f6c72`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/53f6c720))
  - Wizard state management (TanStack Query architecture with optimistic updates) ([`53f6c72`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/53f6c720))
  - Generated manifest index and validation system ([`3bc33a2`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/3bc33a25))
  - Learning Hub, CI/CD automation, generator architecture ([`5bafe16`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/5bafe16d))
  - Provider guides (Contabo, OVH, Hetzner comparison) ([`3bc33a2`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/3bc33a25))
  - Test harness API documentation ([`3bc33a2`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/3bc33a25))

### Shell Experience

- **6 new Oh-My-Zsh plugins** added: python, pip, tmux, tmuxinator, systemd, rsync ([`387c825`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/387c825d))

### Analytics

- Comprehensive GA4 acquisition tracking and diagnostics ([`15f93cd`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/15f93cd8))

### Bug Fixes

- Gemini CLI tmux compatibility: terminal detection and heredoc syntax ([`b7fe883`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/b7fe8834), [`42ad104`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/42ad1041))
- `jq` alternative operator (`//`) treating `false` as falsy ([`b973229`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/b9732296))
- CI: YAML lint, shellcheck, and SSH key TTY issues resolved ([`9506bf5`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/9506bf53))
- E2E: strict mode violations and flaky navigation test timing ([`0fa6dcf`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/0fa6dcf4))

### Maintenance

- Obsolete CASS robot wrapper code removed ([`8db8543`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/8db8543e))

---

## [v0.1.0](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/releases/tag/v0.1.0) -- 2026-01-03

> Initial public release. 1,572 commits of foundational development.

### Core Infrastructure

- **One-liner installer** (`curl | bash`) that transforms a fresh Ubuntu VPS into a fully-configured agentic coding environment in ~30 minutes ([`aaf0a58`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/aaf0a587))
- **Idempotent execution** -- interrupted installs resume automatically from the last completed phase
- **Manifest-driven architecture** -- `acfs.manifest.yaml` as single source of truth with TypeScript parser (Zod) and code generation ([`31a5923`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/31a59233), [`142eaff`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/142eaff0))
- **Security verification** -- SHA256 checksum verification for all upstream installers with fail-closed semantics ([`bc41158`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/bc41158b), [`9dba55f`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/9dba55fc))

### Agent System

- **Three-tier agent support**: Claude Code, Codex CLI, and Gemini CLI ([`865d6e5`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/865d6e5c))
- **Named Tmux Manager (NTM)** -- agent cockpit for managing coding sessions
- **Unified Session Search (CASS)** -- search across all agent session history
- **Procedural Memory (CM)** -- persistent context system for agents
- **Auth Switching (CAAM)** -- instant switching between API keys
- **Security Guardrails (SLB)** -- two-person rule enforcement for dangerous commands

### Shell Environment

- Modern shell setup: zsh + oh-my-zsh + powerlevel10k theme
- All language runtimes: bun, uv/Python, Rust, Go
- Cloud CLIs: Vault, Wrangler, Supabase, Vercel
- 20+ developer tools (ripgrep, fd, bat, delta, gh, etc.)
- Optimized tmux configuration with Catppuccin theme and vim-style copy mode

### Web Application

- **Wizard website** at [agent-flywheel.com](https://agent-flywheel.com) built with Next.js 16 + bun workspaces ([`2b320e0`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/2b320e05))
- 10-step interactive wizard guiding beginners from laptop to running AI agents ([`6c0bbe3`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/6c0bbe30) through [`aa9f043`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/aa9f043a))
- Jargon tooltip component (desktop hover, mobile bottom sheet)
- CommandCard component with copy and checkbox state ([`fba5969`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/fba59691))
- Stepper navigation component ([`33c3714`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/33c37149))

### Diagnostics & Updates

- **`acfs doctor`** -- self-healing diagnostic system with `--json` output ([`2fca17d`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/2fca17de))
- **`acfs update`** -- component update command ([`e6d310b`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/e6d310bc))
- **Interactive onboarding TUI** with gum support and progress tracking ([`d96659e`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/d96659ec))

### Installer Libraries

- Modular library scripts: `cli_tools.sh`, `languages.sh`, `agents.sh`, `stack.sh`, `cloud_db.sh` ([`43f59f0`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/43f59f0b), [`d779651`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/d7796510), [`865d6e5`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/865d6e5c), [`f40adca`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/f40adca1), [`7b14fbd`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/7b14fbde))
- Cloud/database phase with Vault, Wrangler, Supabase CLI ([`47d6138`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/47d61386))
- VPS provider setup guides for OVH, Contabo, Hetzner ([`8c725ed`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/8c725edc))

### CI/CD

- Installer CI workflow with doctor integration ([`4664d79`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/4664d79b))
- Docker integration test script ([`c0873bd`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/c0873bdb))
- Fail-fast remote `curl|bash` subshells ([`fd677f7`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/fd677f7a))
