# Changelog

All notable changes to the [Agentic Coding Flywheel Setup (ACFS)](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup) project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Each version links to its GitHub Release (where one exists) or to the tag comparison. Representative commits are linked for traceability.

---

## [Unreleased](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/compare/v0.6.0...HEAD)

> 424 commits since v0.6.0 (2026-02-02 through 2026-03-21). Internal version bumped to 0.7.0 in [`729822e`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/729822eb).

### Added

- **`acfs services` command** -- unified daemon management for all ACFS background services (Agent Mail, nightly update timer, etc.) ([`2d48c4b`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/2d48c4b1))
- **Complete Guide rewrite** -- the `/complete-guide` web page was rewritten multiple times, converging on a narrative-post style with interactive visualizations, exhibit panels, and QuickNav ([`700b2c2`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/700b2c20), [`5d77488`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/5d774887), [`f7cd53f`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/f7cd53f7))
- **Core Flywheel page** (`/core-flywheel`) with 4 new interactive visualizations and dedicated OG/Twitter share images ([`478c56f`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/478c56f6), [`a59fea1`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/a59fea19))
- **15 new lesson components** for the onboarding Learning Hub, covering RCH, WezTerm, Brenner, GIIL, S2P, and 7 utility tools ([`fd30a07`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/fd30a07a), [`3552ce6`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/3552ce6a))
- **MCP Agent Mail as systemd managed service** -- replaces tmux-spawn with a proper systemd unit, including `LimitNOFILE=65536`, `Restart=always`, and backend auto-detection ([`17d2fd4`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/17d2fd47), [`a806cc5`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/a806cc5a))
- **Agent Mail service lifecycle overhaul** -- target-context execution, expanded manifest drift detection ([`5db9a70`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/5db9a708))
- **Manifest schema hardening** -- pre-install checks, extended drift detection, topo-sort consolidation ([`2b8ddb7`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/2b8ddb70), [`08cc1df`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/08cc1df8))
- **Verified installer framework** -- `install_asset_from_path` helper, DSR migrated to verified installer, 13 missing tool installers added ([`bcd4734`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/bcd47348), [`e81279f`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/e81279fa))
- **Installer `--only` and `--only-phase` flags** for selective tool/phase installation on fresh VPS ([`da096a7`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/da096a7c), [`287dc59`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/287dc596))
- **`loginctl enable-linger`** so `systemctl --user` services survive SSH disconnects on fresh installs ([`fff5933`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/fff59332))
- **Persistent wizard state** -- VPS checklist and checked-services state survive page reloads ([`df5b451`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/df5b4515), [`b0c16e3`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/b0c16e3e))
- **Research-driven feature planning** section in Complete Guide ([`f429d92`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/f429d923))
- **8 new stack tools integrated** across install, update, and E2E test surfaces ([`7629cf1`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/7629cf11))
- **Expanded test suites** -- E2E, unit, and VM tests for installer, doctor, newproj, and web ([`5d1b2f2`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/5d1b2f28), [`e851325`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/e8513250))

### Changed

- **Web: Zod schema validators** for VPS wizard IP validation, replacing inline regex ([`0fc907c`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/0fc907cb))
- **Web: TanStack Query** for user preference hooks, replacing local `useState` ([`9bed651`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/9bed6515))
- **Onboard: sparse lesson numbers** supported; progress file validated with file locking ([`46dd0d7`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/46dd0d71))
- **`/core_flywheel` route renamed to `/core-flywheel`** for URL consistency ([`0cd2bb8`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/0cd2bb86))
- **`mcp_agent_mail` switched from Python to Rust installer** ([`e9cdfb1`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/e9cdfb1e))

### Fixed

- **Deep codebase audit** (3 rounds) fixed 16+ bugs across scripts and web ([`f733392`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/f733392b), [`3b1cbbf`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/3b1cbbf4), [`eb8b5c4`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/eb8b5c45))
- **Security: `KNOWN_INSTALLERS` URLs synced from `checksums.yaml`** at load time ([`9c0b631`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/9c0b6311))
- **Restored accidentally deleted verified installer functions** in update script ([`137f7b9`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/137f7b94))
- **OG/Twitter metadata** added for social sharing cards across all pages ([`cf89907`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/cf899071), [`df0ff5e`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/df0ff5e6))
- **`fd` alias no longer shadows `find`**; fzf keybinding disable var corrected ([`0b09aef`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/0b09aef1))
- **Agent Mail installer flags**: `--dest` instead of `--dir`, removed invalid `--no-start` ([`fbbaaa3`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/fbbaaa3e), [`18192b9`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/18192b9f))
- **Onboard: duplicate `esac`** causing syntax error on fresh installs ([`3ddba53`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/3ddba53e))
- **Installer: symlink repair path** for agent-mail binary ([`7717fdd`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/7717fdd7))
- **POSIX regex compat**, SLB source build, and model reference updates ([`1e389fe`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/1e389fe7))
- **Atomic file writes** for workflow templates; CR stripped earlier in redirect parsing ([`1b0fb6a`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/1b0fb6ac))
- **Newproj: canonical `br-agent-instructions` markers** in generated `CLAUDE.md` ([`dff802d`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/dff802d8))
- **Newproj: directory validation** hardened with permission checks, path normalization, parent dir guards ([`12e0f10`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/12e0f106))
- **Web: keyboard handlers gated on viewport visibility** to prevent multi-viz conflicts ([`903180b`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/903180b8))
- **Bash arithmetic bugs** (`set -e` traps) fixed across scripts and tests ([`d50cb58`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/d50cb584), [`b5b04cd`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/b5b04cd66))

### Security

- Continuous automated checksum updates for upstream tools (atuin, uv, rch, br, mcp_agent_mail, gemini_patch, pt)

---

## [v0.6.0](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/releases/tag/v0.6.0) -- 2026-02-02

> **Complete `bd` to `br` migration.** 308 commits since v0.5.0.

### Breaking

- **Removed `bd` alias for `br` (beads_rust)** -- use `br` directly. The `bd` command no longer works. Bead IDs (`bd-XXXX`) are preserved as historical identifiers.
- CLI flag `--no-bd` renamed to `--no-br`; env var `AGENTS_ENABLE_BD` renamed to `AGENTS_ENABLE_BR`.

### Added

- **`br` alias guard** -- automatically removes stale `alias br='bun run'` from older ACFS versions using `whence -p br` ([`1d7fd86`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/1d7fd866))
- **NTM command palette** wired during ACFS install ([`cfd9ff3`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/cfd9ff3d))
- **Dynamic lesson discovery** in onboard TUI -- lessons no longer need hardcoded indices ([`df66cea`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/df66cea3))
- **TOON output format** support in `acfs info` and cheatsheet/doctor commands ([`3a0b15e`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/3a0b15e2), [`883baae`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/883baaea))
- **RCH, WezTerm, Brenner, GIIL, S2P lessons** and tools index page ([`931fd4d`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/931fd4df))
- **TL;DR page** (`/tldr`) showcasing all flywheel tools with synergy diagram ([`ca3e95a`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/ca3e95a5))
- **Dynamic OG images** for social sharing across all web sections ([`b720937`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/b7209374), [`47ca275`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/47ca275d))
- **CSCTF and Meta Skill (ms)** tool pages added to web flywheel ecosystem ([`c71540d`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/c71540d4), [`b677d63`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/b677d631))
- **E2E tests, CI linters, signal handling, and process locking** ([`1cb97b5`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/1cb97b56))
- **`flywheel-update-agents-md`** installer and update integration ([`0636809`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/06368093))
- **Nightly systemd timer** for daily unattended `acfs-update` ([`18c52d8`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/18c52d8d))
- **Automated manifest drift detection and auto-fix** script ([`1e34eb6`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/1e34eb69))
- **Internal script integrity verification** at installer side ([`3fb952a`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/3fb952ad))
- **ntfy.sh push notifications** for agent task lifecycle with debouncing ([`32c718e`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/32c718e4), [`f171fca`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/f171fca2))
- **Native cross-agent session conversion** (X -> Y format) ([`9634dd4`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/9634dd4b))
- **`--stack-only` flag** for `acfs update` to update only stack tools ([`6199da1`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/6199da18))
- **UI component library enhancements** -- bottom sheet with swipe gestures, premium motion variants, fluid display typography, CodeBlock line hover, EmptyState component ([`2dee1e8`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/2dee1e81), [`f3f28ea`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/f3f28ea3), [`b4ebc96`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/b4ebc966))

### Changed

- **All `bd` references migrated to `br`** across shell config, web lessons, installer scripts, CLI flags, env vars, state variables, and test suites ([`1d7fd86`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/1d7fd866))
- **Claude Code channel switched to `latest`** instead of `stable` ([`5b975a8`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/5b975a8f))
- **Vercel config** moved from root to `apps/web` for monorepo deployment ([`8fe3a45`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/8fe3a452))

### Fixed

- **Bash 5.3+ (Ubuntu 25.04) silent exit** -- subshell guards added for all `exec` FD redirections ([`18bb3bb`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/18bb3bbf), [`03c154e`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/03c154e0), [`848a125`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/848a1256))
- **Exit code capture and non-atomic state write bugs** ([`047f9ab`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/047f9abb))
- **State save error propagation** through state update functions ([`fbc5c8c`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/fbc5c8c4))
- **Missing `confirm()` function** in install.sh ([`dc1e76a`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/dc1e76aa))
- **CLI argument parsing hardened** to reject flag-like values as option arguments ([`b094694`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/b094694c))
- **Autofix: unbound variable** with `set -u`, module-level lock FD, `declare -g` for arrays ([`8a88587`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/8a88587e), [`d6e180b`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/d6e180b0), [`4156ed5`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/4156ed57))
- **`--yes` mode respected in `confirm()`** to prevent non-TTY failures ([`54b447a`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/54b447a7))
- **Wizard step 5 UX** improved for VPS IP entry ([`98959a3`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/98959a31))
- **Next.js 15+ OG image compat** -- `await params` Promise in dynamic routes ([`6f79f46`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/6f79f462))
- **CI reliability**: SLB installed via `.deb` to avoid GitHub API rate limits; apt preferred for zoxide; `ACFS_HOME`/`ACFS_STATE_FILE` env vars respected ([`75a91c5`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/75a91c50), [`7b3b535`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/7b3b5357), [`5869135`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/5869135d))
- **State field parsing** uses unit separator instead of null byte ([`6ee416d`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/6ee416de))
- **Web accessibility pass** -- focus states, contrast, ARIA labels, escape-key handling, reduced-motion support ([`2e7068a`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/2e7068ae), [`8831d4f`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/8831d4fe), [`5cf4a0a`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/5cf4a0a6))
- **Performance: reduced subprocess spawns** in state management and apt install ([`99f1023`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/99f10238))
- **SLB mktemp guarded** against failure to prevent root filesystem write ([`f120351`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/f1203511))

---

## [v0.5.0](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/releases/tag/v0.5.0) -- 2026-01-11

> **DCG and RU integration release.** 97 commits since v0.4.0.

### Added

- **DCG (Destructive Command Guard) full integration** -- website, installer, onboarding lesson, 88+ tests, DCG+SLB layered safety tests ([`f1fd501`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/f1fd501f))
- **RU (Repo Updater) full integration** -- learn page, lesson component, Playwright E2E tests, Installer CI workflow ([`cf8643b`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/cf8643b2))
- **Onboarding TUI enhancements** -- file locking for concurrent ops, dynamic `NUM_LESSONS`, new DCG and RU lessons
- **Web: error boundary** for lesson rendering with user-friendly recovery UI ([`94566fb`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/94566fbf))
- **IPv6 zone ID rejection** in VPS IP validation (security) ([`98c16e7`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/98c16e75))
- **Comprehensive flywheel.ts unit tests** ([`4cb9dcd`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/4cb9dcd8))

### Changed

- **Legacy `git_safety_guard.py` fully removed** -- DCG is now the sole command safety mechanism. `acfs update` auto-cleans legacy files.
- **Manifest schema**: removed unused `fallback_url` field; duplicate cycle-detection consolidated ([`69d3e84`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/69d3e844), [`cb05753`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/cb05753c))
- **Tool page split** into server and client components ([`539cd66`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/539cd668))
- **Button: respects `prefers-reduced-motion`** ([`c82fde1`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/c82fde12))

### Fixed

- **Path normalization** in `screen_directory.sh` ([`958fe0b`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/958fe0b8))
- **Upgrade detection** for LTS version format ([`e90c3f8`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/e90c3f88))
- **Nested hook structures** in DCG removal ([`c2863bb`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/c2863bb7))
- **`maxDelay` cap** for stagger animations ([`692c857`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/692c8575))
- **Category name validation** in manifest to prevent injection ([`9c0e779`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/9c0e779d))
- **`acfs_chown_tree` error handling** ([`66bc4af`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/66bc4af1))
- **State write atomic errno capture** ([`f702b36`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/f702b365))

---

## [v0.4.0](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/releases/tag/v0.4.0) -- 2026-01-08

> **Expanded flywheel stack to 10 tools + utilities.** 3 commits since v0.3.0.

### Added

- **DCG (Destructive Command Guard)** -- Rust-based Claude Code `PreToolUse` hook; blocks recursive deletions, force pushes, hard resets with sub-millisecond latency ([`b770c9f`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/b770c9fa))
- **RU (Repo Updater)** -- 17K-line Bash tool for multi-repo sync and AI-driven commit automation
- **giil (Get Image from Internet Link)** -- downloads cloud-hosted images for visual debugging in headless SSH environments
- **csctf (Chat Shared Conversation to File)** -- converts AI chat share links (Claude, ChatGPT, Grok) to Markdown/HTML archives
- Checksums added for all 4 new installers; regenerated installer scripts from manifest

### Fixed

- **Newproj: prevented test framework pollution** of `/data/projects` ([`a7a94d3`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/a7a94d35))

---

## [v0.3.0](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/releases/tag/v0.3.0) -- 2026-01-07

> **TUI wizard and security release.** 29 commits since v0.2.0.

### Security

- **Command injection vulnerability fixed** in `validate_directory()` -- previous `eval echo "$dir"` for tilde expansion allowed arbitrary command execution; replaced with safe pattern matching ([`6c6e899`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/6c6e8996))

### Added

- **Complete TUI wizard for `newproj`** -- 9 interactive screens (welcome, project name, directory, tech stack, features, AGENTS.md preview, confirmation, progress, success) ([`540102a`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/540102a2))
  - `newproj --interactive` (or `-i`) for TUI mode; `newproj myproject ./path` for CLI mode
- **Smart AGENTS.md generation** with tech stack detection for Python, Node.js, Rust, Go, Ruby, PHP, Java ([`ee1cf43`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/ee1cf435))
- **284 unit tests** (bats-core) + **53 E2E tests** + expect-based TUI testing ([`04f740e`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/04f740ed), [`a28ebd1`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/a28ebd13))
- **`.ubsignore` template** for UBS bug scanner in new projects ([`79f9187`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/79f91873))

### Fixed

- ASCII box alignment, file tree rendering for nested paths, missing `.gitignore` in wizard screens
- Safe arithmetic increment to avoid `set -e` issues ([`45f30b2`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/45f30b2c))
- Unconfigured git user handled gracefully ([`7c93951`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/7c93951a))
- SSH keepalive check, Claude auth, and PostgreSQL role checks in doctor ([`7fa199a`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/7fa199a6))

---

## [v0.2.0](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/releases/tag/v0.2.0) -- 2026-01-06

> **Documentation and polish release.** 20 commits since v0.1.0.

### Added

- **6 new Oh-My-Zsh plugins**: `python`, `pip`, `tmux`, `tmuxinator`, `systemd`, `rsync` ([`387c825`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/387c825d))
- **Comprehensive GA4 acquisition tracking** and analytics diagnostics ([`15f93cd`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/15f93cd8))
- **~1,000+ lines of README documentation** covering tmux config, wizard state management (TanStack Query), manifest index, shell keybindings, Learning Hub, CI/CD automation, provider guides (Contabo, OVH, Hetzner), validation system (Tarjan's SCC), and test harness API ([`53f6c72`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/53f6c720), [`3bc33a2`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/3bc33a25), [`5bafe16`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/5bafe16d), [`4797c96`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/4797c968))

### Fixed

- **Gemini CLI**: tmux compatibility, heredoc syntax, file ownership bugs ([`b7fe883`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/b7fe8834), [`42ad104`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/42ad1041))
- **jq alternative operator (`//`)** treating `false` as falsy ([`b973229`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/b9732296))
- **CI**: YAML lint warnings, shellcheck issues, SSH key TTY handling ([`9506bf5`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/9506bf53))
- **E2E tests**: strict mode violations, flaky navigation timing ([`0fa6dcf`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/0fa6dcf4))

### Removed

- Obsolete CASS robot wrapper code ([`8db8543`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/8db8543e))

---

## [v0.1.0](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/releases/tag/v0.1.0) -- 2026-01-03

> **Initial public release.** Project started 2025-12-19 ([`d540dca`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/d540dca8)).

### Added

- **One-liner `curl | bash` installer** for Ubuntu VPS environments -- idempotent, checkpointed, resumes after interruption ([`aaf0a58`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/aaf0a587))
- **Web wizard** at [agent-flywheel.com](https://agent-flywheel.com) -- 13-step guided setup for beginners, built with Next.js 16 + bun workspaces ([`2b320e0`](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/commit/2b320e05))
  - Steps: OS selection, terminal install, SSH key generation, VPS rental, VPS creation, SSH connection, installer execution, reconnect, status check, onboarding
- **Three AI coding agents**: Claude Code, Codex CLI, Gemini CLI
- **Dicklesworthstone stack** (8 tools at launch):
  - **NTM** (Named Tmux Manager) -- agent cockpit for multi-agent sessions
  - **CASS** (Claude Agent Session Search) -- unified session history search
  - **CM** (Claude Memory / Procedural Memory) -- persistent agent context
  - **CAAM** (Claude Account Auth Manager) -- instant API key switching
  - **SLB** (Second Look Buffer) -- two-person rule for dangerous commands
  - **MCP Agent Mail** -- asynchronous agent-to-agent coordination
  - **beads** -- dependency-aware issue tracking
  - **UBS** (Ultimate Bug Scanner) -- pre-commit code analysis
- **Interactive onboarding TUI** with lesson completion tracking
- **`acfs doctor`** -- self-healing diagnostic and repair tool
- **Manifest-driven tool definitions** with SHA256 checksum verification
- **Shell environment**: zsh + oh-my-zsh + powerlevel10k, language runtimes (bun, uv/Python, Rust, Go), cloud CLIs (Vault, Wrangler, Supabase, Vercel), and 20+ developer tools
- **Vibe mode** (`--mode vibe`): passwordless sudo, dangerous agent flags enabled, optimized for maximum velocity
- CASS wrapper installation detection fix, CI stderr corruption fix, checksum E2E tests, doctor fix messages
