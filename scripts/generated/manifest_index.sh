#!/usr/bin/env bash
# shellcheck disable=SC2034
# ============================================================
# AUTO-GENERATED FROM acfs.manifest.yaml - DO NOT EDIT
# Regenerate: bun run generate (from packages/manifest)
# ============================================================
# Data-only manifest index. Safe to source.

ACFS_MANIFEST_SHA256="3eff6bb83be7e3a68a5d1f65efe45c83818d9827d277c9adbc0eb340ecd975b8"

ACFS_MODULES_IN_ORDER=(
  "base.system"
  "users.ubuntu"
  "base.filesystem"
  "shell.zsh"
  "shell.login"
  "shell.omz"
  "cli.modern"
  "tools.lazygit"
  "tools.lazydocker"
  "network.tailscale"
  "network.ssh_keepalive"
  "lang.bun"
  "lang.uv"
  "lang.rust"
  "lang.go"
  "lang.nvm"
  "tools.atuin"
  "tools.zoxide"
  "tools.ast_grep"
  "agents.claude"
  "agents.codex"
  "agents.gemini"
  "agents.antigravity"
  "agents.opencode"
  "agents.omp"
  "agents.grok"
  "tools.vault"
  "db.postgres18"
  "cloud.wrangler"
  "cloud.supabase"
  "cloud.vercel"
  "stack.ntm"
  "stack.mcp_agent_mail"
  "stack.meta_skill"
  "stack.automated_plan_reviser"
  "stack.jeffreysprompts"
  "stack.process_triage"
  "stack.ultimate_bug_scanner"
  "stack.beads_rust"
  "stack.beads_viewer"
  "stack.cass"
  "stack.cm"
  "stack.caam"
  "stack.slb"
  "stack.dcg"
  "stack.ru"
  "stack.brenner_bot"
  "stack.rch"
  "stack.wezterm_automata"
  "stack.srps"
  "stack.frankensearch"
  "stack.storage_ballast_helper"
  "stack.cross_agent_session_resumer"
  "stack.doodlestein_self_releaser"
  "stack.agent_settings_backup"
  "stack.pcr"
  "stack.eidetic_engine_cli"
  "stack.franken_markdown"
  "stack.pi_agent_rust"
  "stack.power_failure_resumer"
  "utils.giil"
  "utils.csctf"
  "utils.xf"
  "utils.toon_rust"
  "utils.rano"
  "utils.mdwb"
  "utils.s2p"
  "utils.rust_proxy"
  "utils.aadc"
  "utils.caut"
  "acfs.workspace"
  "acfs.onboard"
  "acfs.update"
  "acfs.nightly"
  "acfs.doctor"
)

ACFS_CATEGORIES_IN_ORDER=(
  "base"
  "users"
  "filesystem"
  "shell"
  "cli"
  "network"
  "lang"
  "tools"
  "db"
  "cloud"
  "agents"
  "stack"
  "acfs"
)

declare -gA ACFS_MODULE_PHASE=(
  ['base.system']="1"
  ['users.ubuntu']="2"
  ['base.filesystem']="3"
  ['shell.zsh']="4"
  ['shell.login']="4"
  ['shell.omz']="4"
  ['cli.modern']="5"
  ['tools.lazygit']="5"
  ['tools.lazydocker']="5"
  ['network.tailscale']="5"
  ['network.ssh_keepalive']="5"
  ['lang.bun']="6"
  ['lang.uv']="6"
  ['lang.rust']="6"
  ['lang.go']="6"
  ['lang.nvm']="6"
  ['tools.atuin']="6"
  ['tools.zoxide']="6"
  ['tools.ast_grep']="6"
  ['agents.claude']="7"
  ['agents.codex']="7"
  ['agents.gemini']="7"
  ['agents.antigravity']="7"
  ['agents.opencode']="7"
  ['agents.omp']="7"
  ['agents.grok']="7"
  ['tools.vault']="8"
  ['db.postgres18']="8"
  ['cloud.wrangler']="8"
  ['cloud.supabase']="8"
  ['cloud.vercel']="8"
  ['stack.ntm']="9"
  ['stack.mcp_agent_mail']="9"
  ['stack.meta_skill']="9"
  ['stack.automated_plan_reviser']="9"
  ['stack.jeffreysprompts']="9"
  ['stack.process_triage']="9"
  ['stack.ultimate_bug_scanner']="9"
  ['stack.beads_rust']="9"
  ['stack.beads_viewer']="9"
  ['stack.cass']="9"
  ['stack.cm']="9"
  ['stack.caam']="9"
  ['stack.slb']="9"
  ['stack.dcg']="9"
  ['stack.ru']="9"
  ['stack.brenner_bot']="9"
  ['stack.rch']="9"
  ['stack.wezterm_automata']="9"
  ['stack.srps']="9"
  ['stack.frankensearch']="9"
  ['stack.storage_ballast_helper']="9"
  ['stack.cross_agent_session_resumer']="9"
  ['stack.doodlestein_self_releaser']="9"
  ['stack.agent_settings_backup']="9"
  ['stack.pcr']="9"
  ['stack.eidetic_engine_cli']="9"
  ['stack.franken_markdown']="9"
  ['stack.pi_agent_rust']="9"
  ['stack.power_failure_resumer']="9"
  ['utils.giil']="9"
  ['utils.csctf']="9"
  ['utils.xf']="9"
  ['utils.toon_rust']="9"
  ['utils.rano']="9"
  ['utils.mdwb']="9"
  ['utils.s2p']="9"
  ['utils.rust_proxy']="9"
  ['utils.aadc']="9"
  ['utils.caut']="9"
  ['acfs.workspace']="10"
  ['acfs.onboard']="10"
  ['acfs.update']="10"
  ['acfs.nightly']="10"
  ['acfs.doctor']="10"
)

declare -gA ACFS_MODULE_DEPS=(
  ['base.system']=""
  ['users.ubuntu']=""
  ['base.filesystem']="users.ubuntu"
  ['shell.zsh']="base.system,base.filesystem"
  ['shell.login']="shell.zsh,users.ubuntu"
  ['shell.omz']="shell.login,users.ubuntu"
  ['cli.modern']="base.system,users.ubuntu"
  ['tools.lazygit']="base.system,users.ubuntu"
  ['tools.lazydocker']="base.system,users.ubuntu"
  ['network.tailscale']="base.system"
  ['network.ssh_keepalive']="base.system"
  ['lang.bun']="base.system,users.ubuntu"
  ['lang.uv']="base.system,users.ubuntu"
  ['lang.rust']="base.system,users.ubuntu"
  ['lang.go']="base.system,users.ubuntu"
  ['lang.nvm']="base.system,users.ubuntu"
  ['tools.atuin']="base.system,users.ubuntu"
  ['tools.zoxide']="base.system,users.ubuntu"
  ['tools.ast_grep']="lang.rust,users.ubuntu"
  ['agents.claude']="base.system,users.ubuntu"
  ['agents.codex']="lang.bun,users.ubuntu"
  ['agents.gemini']="lang.bun,lang.nvm,users.ubuntu"
  ['agents.antigravity']="base.system,users.ubuntu"
  ['agents.opencode']="base.system,users.ubuntu"
  ['agents.omp']="base.system,users.ubuntu"
  ['agents.grok']="base.system,users.ubuntu"
  ['tools.vault']="base.system,users.ubuntu"
  ['db.postgres18']="base.system"
  ['cloud.wrangler']="lang.bun,users.ubuntu"
  ['cloud.supabase']="base.system,base.filesystem,users.ubuntu"
  ['cloud.vercel']="lang.bun,users.ubuntu"
  ['stack.ntm']="cli.modern,users.ubuntu"
  ['stack.mcp_agent_mail']="lang.bun,lang.uv,users.ubuntu"
  ['stack.meta_skill']="lang.rust,lang.uv,users.ubuntu"
  ['stack.automated_plan_reviser']="lang.rust,users.ubuntu"
  ['stack.jeffreysprompts']="users.ubuntu"
  ['stack.process_triage']="lang.rust,users.ubuntu"
  ['stack.ultimate_bug_scanner']="lang.bun,lang.uv,tools.ast_grep,users.ubuntu"
  ['stack.beads_rust']="lang.rust,users.ubuntu"
  ['stack.beads_viewer']="lang.go,stack.beads_rust,users.ubuntu"
  ['stack.cass']="lang.rust,lang.uv,users.ubuntu"
  ['stack.cm']="lang.rust,lang.uv,users.ubuntu"
  ['stack.caam']="lang.bun,users.ubuntu"
  ['stack.slb']="lang.go,users.ubuntu"
  ['stack.dcg']="agents.claude,users.ubuntu"
  ['stack.ru']="cli.modern,stack.ntm,users.ubuntu"
  ['stack.brenner_bot']="lang.rust,stack.cass,users.ubuntu"
  ['stack.rch']="lang.rust,users.ubuntu"
  ['stack.wezterm_automata']="lang.rust,users.ubuntu"
  ['stack.srps']="base.system,lang.go,users.ubuntu"
  ['stack.frankensearch']="lang.rust,users.ubuntu"
  ['stack.storage_ballast_helper']="lang.rust,users.ubuntu"
  ['stack.cross_agent_session_resumer']="lang.rust,users.ubuntu"
  ['stack.doodlestein_self_releaser']="cli.modern,users.ubuntu"
  ['stack.agent_settings_backup']="base.system,users.ubuntu"
  ['stack.pcr']="agents.claude,users.ubuntu"
  ['stack.eidetic_engine_cli']="lang.rust,users.ubuntu"
  ['stack.franken_markdown']="lang.rust,users.ubuntu"
  ['stack.pi_agent_rust']="lang.rust,users.ubuntu"
  ['stack.power_failure_resumer']="cli.modern,users.ubuntu"
  ['utils.giil']="base.system,users.ubuntu"
  ['utils.csctf']="base.system,users.ubuntu"
  ['utils.xf']="lang.rust,users.ubuntu"
  ['utils.toon_rust']="lang.rust,users.ubuntu"
  ['utils.rano']="lang.rust,users.ubuntu"
  ['utils.mdwb']="lang.rust,users.ubuntu"
  ['utils.s2p']="lang.bun,users.ubuntu"
  ['utils.rust_proxy']="lang.rust,users.ubuntu"
  ['utils.aadc']="lang.rust,users.ubuntu"
  ['utils.caut']="lang.rust,users.ubuntu"
  ['acfs.workspace']="agents.claude,agents.codex,agents.antigravity,cli.modern,users.ubuntu"
  ['acfs.onboard']="users.ubuntu"
  ['acfs.update']="users.ubuntu"
  ['acfs.nightly']="acfs.update,users.ubuntu"
  ['acfs.doctor']="users.ubuntu"
)

declare -gA ACFS_MODULE_FUNC=(
  ['base.system']="acfs_generated_install_base_system"
  ['base.filesystem']="acfs_generated_install_base_filesystem"
  ['shell.zsh']="acfs_generated_install_shell_zsh"
  ['shell.login']="acfs_generated_install_shell_login"
  ['shell.omz']="acfs_generated_install_shell_omz"
  ['cli.modern']="acfs_generated_install_cli_modern"
  ['tools.lazygit']="acfs_generated_install_tools_lazygit"
  ['tools.lazydocker']="acfs_generated_install_tools_lazydocker"
  ['network.tailscale']="acfs_generated_install_network_tailscale"
  ['network.ssh_keepalive']="acfs_generated_install_network_ssh_keepalive"
  ['lang.bun']="acfs_generated_install_lang_bun"
  ['lang.uv']="acfs_generated_install_lang_uv"
  ['lang.rust']="acfs_generated_install_lang_rust"
  ['lang.go']="acfs_generated_install_lang_go"
  ['lang.nvm']="acfs_generated_install_lang_nvm"
  ['tools.atuin']="acfs_generated_install_tools_atuin"
  ['tools.zoxide']="acfs_generated_install_tools_zoxide"
  ['tools.ast_grep']="acfs_generated_install_tools_ast_grep"
  ['agents.claude']="acfs_generated_install_agents_claude"
  ['agents.codex']="acfs_generated_install_agents_codex"
  ['agents.gemini']="acfs_generated_install_agents_gemini"
  ['agents.antigravity']="acfs_generated_install_agents_antigravity"
  ['agents.opencode']="acfs_generated_install_agents_opencode"
  ['agents.omp']="acfs_generated_install_agents_omp"
  ['agents.grok']="acfs_generated_install_agents_grok"
  ['tools.vault']="acfs_generated_install_tools_vault"
  ['db.postgres18']="acfs_generated_install_db_postgres18"
  ['cloud.wrangler']="acfs_generated_install_cloud_wrangler"
  ['cloud.supabase']="acfs_generated_install_cloud_supabase"
  ['cloud.vercel']="acfs_generated_install_cloud_vercel"
  ['stack.ntm']="acfs_generated_install_stack_ntm"
  ['stack.mcp_agent_mail']="acfs_generated_install_stack_mcp_agent_mail"
  ['stack.meta_skill']="acfs_generated_install_stack_meta_skill"
  ['stack.automated_plan_reviser']="acfs_generated_install_stack_automated_plan_reviser"
  ['stack.jeffreysprompts']="acfs_generated_install_stack_jeffreysprompts"
  ['stack.process_triage']="acfs_generated_install_stack_process_triage"
  ['stack.ultimate_bug_scanner']="acfs_generated_install_stack_ultimate_bug_scanner"
  ['stack.beads_rust']="acfs_generated_install_stack_beads_rust"
  ['stack.beads_viewer']="acfs_generated_install_stack_beads_viewer"
  ['stack.cass']="acfs_generated_install_stack_cass"
  ['stack.cm']="acfs_generated_install_stack_cm"
  ['stack.caam']="acfs_generated_install_stack_caam"
  ['stack.slb']="acfs_generated_install_stack_slb"
  ['stack.dcg']="acfs_generated_install_stack_dcg"
  ['stack.ru']="acfs_generated_install_stack_ru"
  ['stack.brenner_bot']="acfs_generated_install_stack_brenner_bot"
  ['stack.rch']="acfs_generated_install_stack_rch"
  ['stack.wezterm_automata']="acfs_generated_install_stack_wezterm_automata"
  ['stack.srps']="acfs_generated_install_stack_srps"
  ['stack.frankensearch']="acfs_generated_install_stack_frankensearch"
  ['stack.storage_ballast_helper']="acfs_generated_install_stack_storage_ballast_helper"
  ['stack.cross_agent_session_resumer']="acfs_generated_install_stack_cross_agent_session_resumer"
  ['stack.doodlestein_self_releaser']="acfs_generated_install_stack_doodlestein_self_releaser"
  ['stack.agent_settings_backup']="acfs_generated_install_stack_agent_settings_backup"
  ['stack.pcr']="acfs_generated_install_stack_pcr"
  ['stack.eidetic_engine_cli']="acfs_generated_install_stack_eidetic_engine_cli"
  ['stack.franken_markdown']="acfs_generated_install_stack_franken_markdown"
  ['stack.pi_agent_rust']="acfs_generated_install_stack_pi_agent_rust"
  ['stack.power_failure_resumer']="acfs_generated_install_stack_power_failure_resumer"
  ['utils.giil']="acfs_generated_install_utils_giil"
  ['utils.csctf']="acfs_generated_install_utils_csctf"
  ['utils.xf']="acfs_generated_install_utils_xf"
  ['utils.toon_rust']="acfs_generated_install_utils_toon_rust"
  ['utils.rano']="acfs_generated_install_utils_rano"
  ['utils.mdwb']="acfs_generated_install_utils_mdwb"
  ['utils.s2p']="acfs_generated_install_utils_s2p"
  ['utils.rust_proxy']="acfs_generated_install_utils_rust_proxy"
  ['utils.aadc']="acfs_generated_install_utils_aadc"
  ['utils.caut']="acfs_generated_install_utils_caut"
  ['acfs.workspace']="acfs_generated_install_acfs_workspace"
  ['acfs.onboard']="acfs_generated_install_acfs_onboard"
  ['acfs.update']="acfs_generated_install_acfs_update"
  ['acfs.nightly']="acfs_generated_install_acfs_nightly"
  ['acfs.doctor']="acfs_generated_install_acfs_doctor"
)

declare -gA ACFS_MODULE_GENERATED=(
  ['base.system']="1"
  ['users.ubuntu']="0"
  ['base.filesystem']="1"
  ['shell.zsh']="1"
  ['shell.login']="1"
  ['shell.omz']="1"
  ['cli.modern']="1"
  ['tools.lazygit']="1"
  ['tools.lazydocker']="1"
  ['network.tailscale']="1"
  ['network.ssh_keepalive']="1"
  ['lang.bun']="1"
  ['lang.uv']="1"
  ['lang.rust']="1"
  ['lang.go']="1"
  ['lang.nvm']="1"
  ['tools.atuin']="1"
  ['tools.zoxide']="1"
  ['tools.ast_grep']="1"
  ['agents.claude']="1"
  ['agents.codex']="1"
  ['agents.gemini']="1"
  ['agents.antigravity']="1"
  ['agents.opencode']="1"
  ['agents.omp']="1"
  ['agents.grok']="1"
  ['tools.vault']="1"
  ['db.postgres18']="1"
  ['cloud.wrangler']="1"
  ['cloud.supabase']="1"
  ['cloud.vercel']="1"
  ['stack.ntm']="1"
  ['stack.mcp_agent_mail']="1"
  ['stack.meta_skill']="1"
  ['stack.automated_plan_reviser']="1"
  ['stack.jeffreysprompts']="1"
  ['stack.process_triage']="1"
  ['stack.ultimate_bug_scanner']="1"
  ['stack.beads_rust']="1"
  ['stack.beads_viewer']="1"
  ['stack.cass']="1"
  ['stack.cm']="1"
  ['stack.caam']="1"
  ['stack.slb']="1"
  ['stack.dcg']="1"
  ['stack.ru']="1"
  ['stack.brenner_bot']="1"
  ['stack.rch']="1"
  ['stack.wezterm_automata']="1"
  ['stack.srps']="1"
  ['stack.frankensearch']="1"
  ['stack.storage_ballast_helper']="1"
  ['stack.cross_agent_session_resumer']="1"
  ['stack.doodlestein_self_releaser']="1"
  ['stack.agent_settings_backup']="1"
  ['stack.pcr']="1"
  ['stack.eidetic_engine_cli']="1"
  ['stack.franken_markdown']="1"
  ['stack.pi_agent_rust']="1"
  ['stack.power_failure_resumer']="1"
  ['utils.giil']="1"
  ['utils.csctf']="1"
  ['utils.xf']="1"
  ['utils.toon_rust']="1"
  ['utils.rano']="1"
  ['utils.mdwb']="1"
  ['utils.s2p']="1"
  ['utils.rust_proxy']="1"
  ['utils.aadc']="1"
  ['utils.caut']="1"
  ['acfs.workspace']="1"
  ['acfs.onboard']="1"
  ['acfs.update']="1"
  ['acfs.nightly']="1"
  ['acfs.doctor']="1"
)

declare -gA ACFS_MODULE_CATEGORY=(
  ['base.system']="base"
  ['users.ubuntu']="users"
  ['base.filesystem']="filesystem"
  ['shell.zsh']="shell"
  ['shell.login']="shell"
  ['shell.omz']="shell"
  ['cli.modern']="cli"
  ['tools.lazygit']="tools"
  ['tools.lazydocker']="tools"
  ['network.tailscale']="network"
  ['network.ssh_keepalive']="network"
  ['lang.bun']="lang"
  ['lang.uv']="lang"
  ['lang.rust']="lang"
  ['lang.go']="lang"
  ['lang.nvm']="lang"
  ['tools.atuin']="tools"
  ['tools.zoxide']="tools"
  ['tools.ast_grep']="tools"
  ['agents.claude']="agents"
  ['agents.codex']="agents"
  ['agents.gemini']="agents"
  ['agents.antigravity']="agents"
  ['agents.opencode']="agents"
  ['agents.omp']="agents"
  ['agents.grok']="agents"
  ['tools.vault']="tools"
  ['db.postgres18']="db"
  ['cloud.wrangler']="cloud"
  ['cloud.supabase']="cloud"
  ['cloud.vercel']="cloud"
  ['stack.ntm']="stack"
  ['stack.mcp_agent_mail']="stack"
  ['stack.meta_skill']="stack"
  ['stack.automated_plan_reviser']="stack"
  ['stack.jeffreysprompts']="stack"
  ['stack.process_triage']="stack"
  ['stack.ultimate_bug_scanner']="stack"
  ['stack.beads_rust']="stack"
  ['stack.beads_viewer']="stack"
  ['stack.cass']="stack"
  ['stack.cm']="stack"
  ['stack.caam']="stack"
  ['stack.slb']="stack"
  ['stack.dcg']="stack"
  ['stack.ru']="stack"
  ['stack.brenner_bot']="stack"
  ['stack.rch']="stack"
  ['stack.wezterm_automata']="stack"
  ['stack.srps']="stack"
  ['stack.frankensearch']="stack"
  ['stack.storage_ballast_helper']="stack"
  ['stack.cross_agent_session_resumer']="stack"
  ['stack.doodlestein_self_releaser']="stack"
  ['stack.agent_settings_backup']="stack"
  ['stack.pcr']="stack"
  ['stack.eidetic_engine_cli']="stack"
  ['stack.franken_markdown']="stack"
  ['stack.pi_agent_rust']="stack"
  ['stack.power_failure_resumer']="stack"
  ['utils.giil']="tools"
  ['utils.csctf']="tools"
  ['utils.xf']="tools"
  ['utils.toon_rust']="tools"
  ['utils.rano']="tools"
  ['utils.mdwb']="tools"
  ['utils.s2p']="tools"
  ['utils.rust_proxy']="tools"
  ['utils.aadc']="tools"
  ['utils.caut']="tools"
  ['acfs.workspace']="acfs"
  ['acfs.onboard']="acfs"
  ['acfs.update']="acfs"
  ['acfs.nightly']="acfs"
  ['acfs.doctor']="acfs"
)

declare -gA ACFS_MODULE_TAGS=(
  ['base.system']="critical"
  ['users.ubuntu']="orchestration,critical"
  ['base.filesystem']="critical"
  ['shell.zsh']="critical,shell-ux"
  ['shell.login']="critical,shell-ux"
  ['shell.omz']="critical,shell-ux"
  ['cli.modern']="recommended,cli-modern"
  ['tools.lazygit']="recommended,cli-modern"
  ['tools.lazydocker']="recommended,cli-modern"
  ['network.tailscale']="networking,vpn,security,google-sso"
  ['network.ssh_keepalive']="networking,remote-dev,ssh"
  ['lang.bun']="critical,runtime"
  ['lang.uv']="critical,runtime"
  ['lang.rust']="critical,runtime"
  ['lang.go']="critical,runtime"
  ['lang.nvm']="critical,runtime"
  ['tools.atuin']="recommended,shell-ux"
  ['tools.zoxide']="recommended,shell-ux"
  ['tools.ast_grep']="recommended"
  ['agents.claude']="recommended,agent"
  ['agents.codex']="recommended,agent"
  ['agents.gemini']="legacy,agent"
  ['agents.antigravity']="recommended,agent"
  ['agents.opencode']="optional,agent"
  ['agents.omp']="optional,agent"
  ['agents.grok']="optional,agent"
  ['tools.vault']="optional,cloud"
  ['db.postgres18']="optional,database"
  ['cloud.wrangler']="optional,cloud"
  ['cloud.supabase']="optional,cloud"
  ['cloud.vercel']="optional,cloud"
  ['stack.ntm']="recommended"
  ['stack.mcp_agent_mail']="recommended"
  ['stack.meta_skill']="recommended,agent-skills"
  ['stack.automated_plan_reviser']="recommended,agent-tools"
  ['stack.jeffreysprompts']="recommended,agent-skills,prompts"
  ['stack.process_triage']="recommended,system-tools"
  ['stack.ultimate_bug_scanner']="recommended"
  ['stack.beads_rust']="recommended"
  ['stack.beads_viewer']="recommended"
  ['stack.cass']="recommended"
  ['stack.cm']="recommended"
  ['stack.caam']="recommended"
  ['stack.slb']="optional"
  ['stack.dcg']="recommended,safety"
  ['stack.ru']="recommended"
  ['stack.brenner_bot']="recommended"
  ['stack.rch']="recommended,performance"
  ['stack.wezterm_automata']="optional,automation"
  ['stack.srps']="recommended,system-health"
  ['stack.frankensearch']="recommended,search"
  ['stack.storage_ballast_helper']="recommended,system-tools"
  ['stack.cross_agent_session_resumer']="recommended,agent-tools"
  ['stack.doodlestein_self_releaser']="recommended,release"
  ['stack.agent_settings_backup']="recommended,backup"
  ['stack.pcr']="recommended,safety,hooks"
  ['stack.eidetic_engine_cli']="recommended,memory"
  ['stack.franken_markdown']="recommended,docs"
  ['stack.pi_agent_rust']="recommended,agent"
  ['stack.power_failure_resumer']="recommended,reliability"
  ['utils.giil']="utility"
  ['utils.csctf']="utility"
  ['utils.xf']="utility,search"
  ['utils.toon_rust']="utility,llm"
  ['utils.rano']="utility,network,debug"
  ['utils.mdwb']="utility,web,llm"
  ['utils.s2p']="utility,llm,tui"
  ['utils.rust_proxy']="utility,network,debug"
  ['utils.aadc']="utility,ascii"
  ['utils.caut']="utility,tracking"
  ['acfs.workspace']="workspace,agents"
  ['acfs.onboard']="orchestration"
  ['acfs.update']="orchestration"
  ['acfs.nightly']="orchestration,maintenance"
  ['acfs.doctor']="orchestration"
)

declare -gA ACFS_MODULE_DEFAULT=(
  ['base.system']="1"
  ['users.ubuntu']="1"
  ['base.filesystem']="1"
  ['shell.zsh']="1"
  ['shell.login']="1"
  ['shell.omz']="1"
  ['cli.modern']="1"
  ['tools.lazygit']="1"
  ['tools.lazydocker']="1"
  ['network.tailscale']="1"
  ['network.ssh_keepalive']="1"
  ['lang.bun']="1"
  ['lang.uv']="1"
  ['lang.rust']="1"
  ['lang.go']="1"
  ['lang.nvm']="1"
  ['tools.atuin']="1"
  ['tools.zoxide']="1"
  ['tools.ast_grep']="1"
  ['agents.claude']="1"
  ['agents.codex']="1"
  ['agents.gemini']="0"
  ['agents.antigravity']="1"
  ['agents.opencode']="0"
  ['agents.omp']="0"
  ['agents.grok']="0"
  ['tools.vault']="0"
  ['db.postgres18']="0"
  ['cloud.wrangler']="0"
  ['cloud.supabase']="0"
  ['cloud.vercel']="0"
  ['stack.ntm']="1"
  ['stack.mcp_agent_mail']="1"
  ['stack.meta_skill']="1"
  ['stack.automated_plan_reviser']="1"
  ['stack.jeffreysprompts']="1"
  ['stack.process_triage']="1"
  ['stack.ultimate_bug_scanner']="1"
  ['stack.beads_rust']="1"
  ['stack.beads_viewer']="1"
  ['stack.cass']="1"
  ['stack.cm']="1"
  ['stack.caam']="1"
  ['stack.slb']="1"
  ['stack.dcg']="1"
  ['stack.ru']="1"
  ['stack.brenner_bot']="1"
  ['stack.rch']="1"
  ['stack.wezterm_automata']="0"
  ['stack.srps']="1"
  ['stack.frankensearch']="1"
  ['stack.storage_ballast_helper']="1"
  ['stack.cross_agent_session_resumer']="1"
  ['stack.doodlestein_self_releaser']="1"
  ['stack.agent_settings_backup']="1"
  ['stack.pcr']="1"
  ['stack.eidetic_engine_cli']="1"
  ['stack.franken_markdown']="1"
  ['stack.pi_agent_rust']="1"
  ['stack.power_failure_resumer']="1"
  ['utils.giil']="1"
  ['utils.csctf']="1"
  ['utils.xf']="0"
  ['utils.toon_rust']="1"
  ['utils.rano']="0"
  ['utils.mdwb']="1"
  ['utils.s2p']="1"
  ['utils.rust_proxy']="0"
  ['utils.aadc']="0"
  ['utils.caut']="0"
  ['acfs.workspace']="1"
  ['acfs.onboard']="1"
  ['acfs.update']="1"
  ['acfs.nightly']="1"
  ['acfs.doctor']="1"
)

declare -gA ACFS_MODULE_DESC=(
  ['base.system']="Base packages + sane defaults"
  ['users.ubuntu']="Ensure target user + passwordless sudo + ssh keys"
  ['base.filesystem']="Create workspace and ACFS directories"
  ['shell.zsh']="Zsh shell package"
  ['shell.login']="Validated and recoverable login-shell configuration"
  ['shell.omz']="Oh My Zsh + Powerlevel10k + plugins + ACFS config"
  ['cli.modern']="Modern CLI tools referenced by the zshrc intent"
  ['tools.lazygit']="Lazygit (apt or binary fallback)"
  ['tools.lazydocker']="Lazydocker (binary install)"
  ['network.tailscale']="Zero-config mesh VPN for secure remote VPS access"
  ['network.ssh_keepalive']="Configure SSH server keepalive to prevent VPN/NAT disconnects"
  ['lang.bun']="Bun runtime for JS tooling and global CLIs"
  ['lang.uv']="uv Python tooling (fast venvs)"
  ['lang.rust']="Rust nightly + cargo"
  ['lang.go']="Go toolchain"
  ['lang.nvm']="nvm + latest Node.js"
  ['tools.atuin']="Atuin CLI with guarded agent-safe shim"
  ['tools.zoxide']="Zoxide (better cd)"
  ['tools.ast_grep']="ast-grep (used by UBS for syntax-aware scanning)"
  ['agents.claude']="Claude Code"
  ['agents.codex']="OpenAI Codex CLI"
  ['agents.gemini']="Legacy Google Gemini CLI (retired; not installed by default)"
  ['agents.antigravity']="Antigravity CLI (agy) — Google, successor to the retired Gemini CLI"
  ['agents.opencode']="OpenCode (multi-provider agent harness)"
  ['agents.omp']="oh-my-pi (omp) — community fork of the Pi coding agent"
  ['agents.grok']="Grok CLI (xAI coding agent)"
  ['tools.vault']="HashiCorp Vault CLI"
  ['db.postgres18']="PostgreSQL 18"
  ['cloud.wrangler']="Cloudflare Wrangler CLI"
  ['cloud.supabase']="Supabase CLI"
  ['cloud.vercel']="Vercel CLI"
  ['stack.ntm']="Named tmux manager (agent cockpit)"
  ['stack.mcp_agent_mail']="Like gmail for coding agents; MCP HTTP server + token; installs beads tools"
  ['stack.meta_skill']="Local-first knowledge management with hybrid semantic search (ms)"
  ['stack.automated_plan_reviser']="Automated iterative spec refinement with extended AI reasoning (apr)"
  ['stack.jeffreysprompts']="Curated battle-tested prompts for AI agents - browse and install as skills (jfp)"
  ['stack.process_triage']="Find and terminate stuck/zombie processes with intelligent scoring (pt)"
  ['stack.ultimate_bug_scanner']="UBS bug scanning (easy-mode)"
  ['stack.beads_rust']="beads_rust (br) - Rust issue tracker with graph-aware dependencies"
  ['stack.beads_viewer']="bv TUI for Beads tasks"
  ['stack.cass']="Unified search across agent session history"
  ['stack.cm']="Procedural memory for agents (cass-memory)"
  ['stack.caam']="Instant auth switching for agent CLIs"
  ['stack.slb']="Two-person rule for dangerous commands (optional guardrails)"
  ['stack.dcg']="Destructive Command Guard - Claude Code hook blocking dangerous git/fs commands"
  ['stack.ru']="Repo Updater - multi-repo sync + AI-driven commit automation"
  ['stack.brenner_bot']="Brenner Bot - research session manager with hypothesis tracking"
  ['stack.rch']="Remote Compilation Helper - transparent build offloading for AI coding agents"
  ['stack.wezterm_automata']="WezTerm Automata (wa) - terminal automation and orchestration for AI agents"
  ['stack.srps']="System Resource Protection Script - ananicy-cpp rules + TUI monitor for responsive dev workstations"
  ['stack.frankensearch']="Two-tier hybrid local search — lexical (BM25) + semantic retrieval with progressive delivery (fsfs)"
  ['stack.storage_ballast_helper']="Cross-platform disk-pressure defense for AI coding workloads (sbh)"
  ['stack.cross_agent_session_resumer']="Cross-provider AI coding session resumption — convert and resume sessions across providers (casr)"
  ['stack.doodlestein_self_releaser']="Fallback release infrastructure — local builds via act when GitHub Actions is throttled (dsr)"
  ['stack.agent_settings_backup']="Smart backup tool for AI coding agent configuration folders (asb)"
  ['stack.pcr']="Post-compaction reminder hook for Claude Code that forces an AGENTS.md re-read"
  ['stack.eidetic_engine_cli']="Durable, local-first, explainable memory for coding agents (ee)"
  ['stack.franken_markdown']="Pure-Rust Markdown engine rendering self-contained HTML and tagged PDF (fmd)"
  ['stack.pi_agent_rust']="Native single-binary Rust port of the Pi coding agent (pi)"
  ['stack.power_failure_resumer']="Recover crashed coding-agent sessions after a hard power cut (pfr)"
  ['utils.giil']="Get Image from Internet Link - download cloud images for visual debugging"
  ['utils.csctf']="Chat Shared Conversation to File - convert AI share links to Markdown/HTML"
  ['utils.xf']="xf - Ultra-fast X/Twitter archive search with Tantivy"
  ['utils.toon_rust']="toon_rust (toon) - Token-optimized notation format for LLM context efficiency"
  ['utils.rano']="rano - Network observer for AI CLIs with request/response logging"
  ['utils.mdwb']="markdown_web_browser (mdwb) - Convert websites to Markdown for LLM consumption"
  ['utils.s2p']="source_to_prompt_tui (s2p) - Code to LLM prompt generator with TUI"
  ['utils.rust_proxy']="rust_proxy - Transparent proxy routing for debugging network traffic"
  ['utils.aadc']="aadc - ASCII diagram corrector for fixing malformed ASCII art"
  ['utils.caut']="coding_agent_usage_tracker (caut) - LLM provider usage tracker"
  ['acfs.workspace']="Agent workspace with tmux session and project folder"
  ['acfs.onboard']="Onboarding TUI tutorial"
  ['acfs.update']="ACFS update command wrapper"
  ['acfs.nightly']="Nightly auto-update timer (systemd)"
  ['acfs.doctor']="ACFS doctor command for health checks"
)

declare -gA ACFS_MODULE_INSTALLED_CHECK=(
  ['base.system']='command -v curl && command -v git && command -v jq'
  ['base.filesystem']='test -d /data/projects && test -d ~/.acfs'
  ['shell.zsh']='command -v zsh'
  ['shell.login']='source "${ACFS_LIB_DIR:-$HOME/.acfs/scripts/lib}/user.sh" &&
  user_login_shell_configured
'
  ['shell.omz']='test -d ~/.oh-my-zsh && test -f ~/.acfs/zsh/acfs.zshrc &&
  source "${ACFS_LIB_DIR:-$HOME/.acfs/scripts/lib}/user.sh" &&
  user_login_shell_configured
'
  ['cli.modern']='command -v rg && command -v tmux && command -v fzf'
  ['tools.lazygit']='command -v lazygit'
  ['tools.lazydocker']='command -v lazydocker'
  ['network.tailscale']='command -v tailscale'
  ['network.ssh_keepalive']='# Check if ClientAliveInterval is configured (non-zero)
grep -qE '\''^ClientAliveInterval[[:space:]]+[1-9]'\'' /etc/ssh/sshd_config 2>/dev/null
'
  ['lang.bun']='test -x ~/.bun/bin/bun'
  ['lang.uv']='test -x "${ACFS_BIN_DIR:-$HOME/.local/bin}/uv" || test -x "$HOME/.local/bin/uv"'
  ['lang.rust']='test -x ~/.cargo/bin/cargo'
  ['lang.go']='command -v go'
  ['lang.nvm']='test -d ~/.nvm && ls ~/.nvm/versions/node/ 2>/dev/null | grep -q .'
  ['tools.atuin']='test -x ~/.atuin/bin/atuin && test -x "${ACFS_BIN_DIR:-$HOME/.local/bin}/atuin" && grep -Fq "agent hook integration disabled by ACFS" "${ACFS_BIN_DIR:-$HOME/.local/bin}/atuin"'
  ['tools.zoxide']='command -v zoxide'
  ['tools.ast_grep']='command -v sg'
  ['agents.claude']='test -x "${ACFS_BIN_DIR:-$HOME/.local/bin}/claude" || test -x "$HOME/.local/bin/claude"'
  ['agents.codex']='test -x "${ACFS_BIN_DIR:-$HOME/.local/bin}/codex" || test -x "$HOME/.local/bin/codex"'
  ['agents.gemini']='test -x "${ACFS_BIN_DIR:-$HOME/.local/bin}/gemini" || test -x "$HOME/.local/bin/gemini"'
  ['agents.antigravity']='target_bin="${ACFS_BIN_DIR:-$HOME/.local/bin}"; test -x "$target_bin/agy" && test -x "$target_bin/agy-locked" && test -x "$target_bin/agy-real" && test -x "$target_bin/gmi"'
  ['agents.opencode']='command -v opencode'
  ['agents.omp']='command -v omp'
  ['agents.grok']='command -v grok'
  ['tools.vault']='command -v vault'
  ['db.postgres18']='for package in postgresql-18 postgresql-client-18; do
  package_status=$(dpkg-query -W -f='\''${db:Status-Status}'\'' "$package" 2>/dev/null) || exit 1
  test "$package_status" = installed || exit 1
done
/usr/lib/postgresql/18/bin/postgres --version | grep -Eq '\''^postgres \(PostgreSQL\) 18\.'\''
/usr/lib/postgresql/18/bin/psql --version | grep -Eq '\''^psql \(PostgreSQL\) 18\.'\''
'
  ['cloud.wrangler']='command -v wrangler'
  ['cloud.supabase']='command -v supabase'
  ['cloud.vercel']='command -v vercel'
  ['stack.ntm']='command -v ntm'
  ['stack.mcp_agent_mail']='command -v am'
  ['stack.meta_skill']='command -v ms'
  ['stack.automated_plan_reviser']='command -v apr'
  ['stack.jeffreysprompts']='command -v jfp'
  ['stack.process_triage']='command -v pt'
  ['stack.ultimate_bug_scanner']='command -v ubs'
  ['stack.beads_rust']='command -v br'
  ['stack.beads_viewer']='command -v bv'
  ['stack.cass']='command -v cass'
  ['stack.cm']='command -v cm'
  ['stack.caam']='command -v caam'
  ['stack.slb']='command -v slb'
  ['stack.dcg']='command -v dcg'
  ['stack.ru']='command -v ru'
  ['stack.brenner_bot']='command -v brenner'
  ['stack.rch']='command -v rch'
  ['stack.wezterm_automata']='command -v wa'
  ['stack.srps']='command -v sysmoni && systemctl is-active ananicy-cpp >/dev/null 2>&1'
  ['stack.frankensearch']='command -v fsfs'
  ['stack.storage_ballast_helper']='command -v sbh'
  ['stack.cross_agent_session_resumer']='command -v casr'
  ['stack.doodlestein_self_releaser']='command -v dsr'
  ['stack.agent_settings_backup']='command -v asb'
  ['stack.pcr']='claude_settings_has_command_hook() {
  local settings_file="${1:-}"
  local command_pattern="${2:-}"
  local jq_bin=""

  [[ -n "$settings_file" && -n "$command_pattern" ]] || return 1
  [[ -f "$settings_file" ]] || return 1
  for jq_bin in /usr/bin/jq /bin/jq /usr/local/bin/jq /usr/local/sbin/jq /usr/sbin/jq /sbin/jq; do
    [[ -x "$jq_bin" ]] && break
  done
  [[ -x "$jq_bin" ]] || return 1

  "$jq_bin" -e --arg pattern "$command_pattern" '\''
    def command_hook_matches:
      type == "object"
      and ((.type? // "command") == "command")
      and ((.command? // "") | strings | test($pattern));
    def event_entry_matches:
      if type == "object" and (.hooks? | type) == "array" then
        any(.hooks[]?; command_hook_matches)
      else
        command_hook_matches
      end;
    def hook_event_entries:
      if (.hooks? | type) == "object" then
        .hooks | to_entries[]? | .value | arrays | .[]?
      elif (.hooks? | type) == "array" then
        .hooks[]?
      else
        empty
      end;
    any(hook_event_entries; event_entry_matches)
  '\'' "$settings_file" >/dev/null 2>&1
}

target_home="${TARGET_HOME:-$HOME}"
hook_script="$target_home/.local/bin/claude-post-compact-reminder"
settings="$target_home/.claude/settings.json"
alt_settings="$target_home/.config/claude/settings.json"
pcr_command_pattern='\''(^|[[:space:]/])claude-post-compact-reminder([[:space:]]|$)'\''

test -x "$hook_script" || exit 1

claude_settings_has_command_hook "$settings" "$pcr_command_pattern" ||
  claude_settings_has_command_hook "$alt_settings" "$pcr_command_pattern"
'
  ['stack.eidetic_engine_cli']='command -v ee'
  ['stack.franken_markdown']='command -v fmd'
  ['stack.pi_agent_rust']='command -v pi'
  ['stack.power_failure_resumer']='command -v pfr'
  ['utils.giil']='command -v giil'
  ['utils.csctf']='command -v csctf'
  ['utils.xf']='command -v xf'
  ['utils.toon_rust']='command -v toon'
  ['utils.rano']='command -v rano'
  ['utils.mdwb']='command -v mdwb'
  ['utils.s2p']='command -v s2p'
  ['utils.rust_proxy']='command -v rust_proxy'
  ['utils.aadc']='command -v aadc'
  ['utils.caut']='command -v caut'
  ['acfs.workspace']='test -d /data/projects/my_first_project'
  ['acfs.nightly']='systemctl --user is-enabled acfs-nightly-update.timer 2>/dev/null'
)

declare -gA ACFS_MODULE_INSTALLED_CHECK_RUN_AS=(
  ['base.system']="current"
  ['base.filesystem']="target_user"
  ['shell.zsh']="current"
  ['shell.login']="current"
  ['shell.omz']="target_user"
  ['cli.modern']="current"
  ['tools.lazygit']="current"
  ['tools.lazydocker']="current"
  ['network.tailscale']="current"
  ['network.ssh_keepalive']="current"
  ['lang.bun']="target_user"
  ['lang.uv']="target_user"
  ['lang.rust']="target_user"
  ['lang.go']="current"
  ['lang.nvm']="target_user"
  ['tools.atuin']="target_user"
  ['tools.zoxide']="target_user"
  ['tools.ast_grep']="target_user"
  ['agents.claude']="target_user"
  ['agents.codex']="target_user"
  ['agents.gemini']="target_user"
  ['agents.antigravity']="target_user"
  ['agents.opencode']="target_user"
  ['agents.omp']="target_user"
  ['agents.grok']="target_user"
  ['tools.vault']="current"
  ['db.postgres18']="root"
  ['cloud.wrangler']="target_user"
  ['cloud.supabase']="target_user"
  ['cloud.vercel']="target_user"
  ['stack.ntm']="target_user"
  ['stack.mcp_agent_mail']="target_user"
  ['stack.meta_skill']="target_user"
  ['stack.automated_plan_reviser']="target_user"
  ['stack.jeffreysprompts']="target_user"
  ['stack.process_triage']="target_user"
  ['stack.ultimate_bug_scanner']="target_user"
  ['stack.beads_rust']="target_user"
  ['stack.beads_viewer']="target_user"
  ['stack.cass']="target_user"
  ['stack.cm']="target_user"
  ['stack.caam']="target_user"
  ['stack.slb']="target_user"
  ['stack.dcg']="target_user"
  ['stack.ru']="target_user"
  ['stack.brenner_bot']="target_user"
  ['stack.rch']="target_user"
  ['stack.wezterm_automata']="target_user"
  ['stack.srps']="target_user"
  ['stack.frankensearch']="target_user"
  ['stack.storage_ballast_helper']="target_user"
  ['stack.cross_agent_session_resumer']="target_user"
  ['stack.doodlestein_self_releaser']="target_user"
  ['stack.agent_settings_backup']="target_user"
  ['stack.pcr']="target_user"
  ['stack.eidetic_engine_cli']="target_user"
  ['stack.franken_markdown']="target_user"
  ['stack.pi_agent_rust']="target_user"
  ['stack.power_failure_resumer']="target_user"
  ['utils.giil']="target_user"
  ['utils.csctf']="target_user"
  ['utils.xf']="target_user"
  ['utils.toon_rust']="target_user"
  ['utils.rano']="target_user"
  ['utils.mdwb']="target_user"
  ['utils.s2p']="target_user"
  ['utils.rust_proxy']="target_user"
  ['utils.aadc']="target_user"
  ['utils.caut']="target_user"
  ['acfs.workspace']="target_user"
  ['acfs.nightly']="target_user"
)

declare -gA ACFS_MODULE_VERIFY_COUNT=(
  ['base.system']="4"
  ['users.ubuntu']="2"
  ['base.filesystem']="2"
  ['shell.zsh']="1"
  ['shell.login']="1"
  ['shell.omz']="4"
  ['cli.modern']="12"
  ['tools.lazygit']="1"
  ['tools.lazydocker']="1"
  ['network.tailscale']="2"
  ['network.ssh_keepalive']="2"
  ['lang.bun']="1"
  ['lang.uv']="1"
  ['lang.rust']="2"
  ['lang.go']="1"
  ['lang.nvm']="1"
  ['tools.atuin']="1"
  ['tools.zoxide']="1"
  ['tools.ast_grep']="1"
  ['agents.claude']="1"
  ['agents.codex']="1"
  ['agents.gemini']="1"
  ['agents.antigravity']="1"
  ['agents.opencode']="1"
  ['agents.omp']="1"
  ['agents.grok']="1"
  ['tools.vault']="1"
  ['db.postgres18']="1"
  ['cloud.wrangler']="1"
  ['cloud.supabase']="1"
  ['cloud.vercel']="1"
  ['stack.ntm']="1"
  ['stack.mcp_agent_mail']="2"
  ['stack.meta_skill']="1"
  ['stack.automated_plan_reviser']="1"
  ['stack.jeffreysprompts']="1"
  ['stack.process_triage']="1"
  ['stack.ultimate_bug_scanner']="1"
  ['stack.beads_rust']="1"
  ['stack.beads_viewer']="1"
  ['stack.cass']="1"
  ['stack.cm']="1"
  ['stack.caam']="1"
  ['stack.slb']="1"
  ['stack.dcg']="2"
  ['stack.ru']="1"
  ['stack.brenner_bot']="1"
  ['stack.rch']="1"
  ['stack.wezterm_automata']="1"
  ['stack.srps']="2"
  ['stack.frankensearch']="1"
  ['stack.storage_ballast_helper']="1"
  ['stack.cross_agent_session_resumer']="1"
  ['stack.doodlestein_self_releaser']="1"
  ['stack.agent_settings_backup']="1"
  ['stack.pcr']="1"
  ['stack.eidetic_engine_cli']="1"
  ['stack.franken_markdown']="1"
  ['stack.pi_agent_rust']="1"
  ['stack.power_failure_resumer']="1"
  ['utils.giil']="1"
  ['utils.csctf']="1"
  ['utils.xf']="1"
  ['utils.toon_rust']="1"
  ['utils.rano']="1"
  ['utils.mdwb']="1"
  ['utils.s2p']="1"
  ['utils.rust_proxy']="1"
  ['utils.aadc']="1"
  ['utils.caut']="1"
  ['acfs.workspace']="2"
  ['acfs.onboard']="1"
  ['acfs.update']="1"
  ['acfs.nightly']="1"
  ['acfs.doctor']="1"
)

# Verification commands are serialized shell source; quoted tildes expand when
# the command is interpreted in its child shell, not while loading this index.
# shellcheck disable=SC2088
declare -gA ACFS_MODULE_VERIFY_COMMAND=(
  ['base.system.0']='curl --version'
  ['base.system.1']='git --version'
  ['base.system.2']='jq --version'
  ['base.system.3']='gpg --version'
  ['users.ubuntu.0']='id "${TARGET_USER:-ubuntu}"'
  ['users.ubuntu.1']='[[ "${MODE:-vibe}" != "vibe" ]] || runuser -u "${TARGET_USER:-ubuntu}" -- sudo -n true'
  ['base.filesystem.0']='test -d /data/projects'
  ['base.filesystem.1']='# Generated helper functions used by this child shell.
acfs_generated_system_binary_path() {
    local name="${1:-}"
    local candidate=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..)
            return 1
            ;;
        *[!A-Za-z0-9._+-]*)
            return 1
            ;;
    esac

    for candidate in \
        "/usr/bin/$name" \
        "/bin/$name" \
        "/usr/sbin/$name" \
        "/sbin/$name"
    do
        [[ -x "$candidate" ]] || continue
        printf '\''%s\n'\'' "$candidate"
        return 0
    done

    return 1
}

acfs_generated_resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(acfs_generated_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(acfs_generated_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '\''%s\n'\'' "$current_user"
}

acfs_generated_getent_passwd_entry() {
    local user="${1-}"
    local getent_bin=""
    local passwd_entry=""
    local passwd_line=""
    local printed_any=false

    getent_bin="$(acfs_generated_system_binary_path getent 2>/dev/null || true)"
    if [[ -z "$user" ]]; then
        if [[ -n "$getent_bin" ]]; then
            while IFS= read -r passwd_line; do
                printf '\''%s\n'\'' "$passwd_line"
                printed_any=true
            done < <("$getent_bin" passwd 2>/dev/null || true)
            if [[ "$printed_any" == true ]]; then
                return 0
            fi
        fi

        [[ -r /etc/passwd ]] || return 1
        while IFS= read -r passwd_line; do
            printf '\''%s\n'\'' "$passwd_line"
        done < /etc/passwd
        return 0
    fi

    if [[ -n "$getent_bin" ]]; then
        passwd_entry="$("$getent_bin" passwd "$user" 2>/dev/null || true)"
    fi

    if [[ -z "$passwd_entry" ]] && [[ -r /etc/passwd ]]; then
        while IFS= read -r passwd_line; do
            [[ "${passwd_line%%:*}" == "$user" ]] || continue
            passwd_entry="$passwd_line"
            break
        done < /etc/passwd
    fi

    [[ -n "$passwd_entry" ]] || return 1
    printf '\''%s\n'\'' "$passwd_entry"
}

acfs_generated_passwd_home_from_entry() {
    local passwd_entry="${1:-}"
    local passwd_home=""

    [[ -n "$passwd_entry" ]] || return 1
    IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
    if [[ -n "$passwd_home" ]] && [[ "$passwd_home" == /* ]] && [[ "$passwd_home" != "/" ]]; then
        printf '\''%s\n'\'' "${passwd_home%/}"
        return 0
    fi

    return 1
}

acfs_generated_target_user_exists() {
    local user="${1:-}"
    local id_bin=""

    [[ -n "$user" ]] || return 1
    id_bin="$(acfs_generated_system_binary_path id 2>/dev/null || true)"
    [[ -n "$id_bin" ]] || return 1
    "$id_bin" "$user" >/dev/null 2>&1
}

acfs_generated_default_home_for_new_user() {
    local user="${1:-}"

    [[ -n "$user" ]] || return 1
    [[ "$user" =~ ^[a-z_][a-z0-9._-]*$ ]] || return 1

    if [[ "$user" == "root" ]]; then
        printf '\''/root\n'\''
        return 0
    fi

    printf '\''/home/%s\n'\'' "$user"
}

# Resolve TARGET_HOME using generated helper functions. Doctor
# injects these helpers for manifest checks that reference
# acfs_generated_* functions, so this stays consistent with
# installer target-home resolution and avoids inherited HOME leaks.
explicit_target_home="${TARGET_HOME:-}"
if [[ -n "$explicit_target_home" ]]; then
  explicit_target_home="${explicit_target_home%/}"
fi
target_home=""
if [[ "${TARGET_USER:-ubuntu}" == "root" ]]; then
  target_home="/root"
else
  _acfs_passwd_entry="$(acfs_generated_getent_passwd_entry "${TARGET_USER:-ubuntu}" 2>/dev/null || true)"
  if [[ -n "$_acfs_passwd_entry" ]]; then
    target_home="$(acfs_generated_passwd_home_from_entry "$_acfs_passwd_entry" 2>/dev/null || true)"
  else
    current_user="$(acfs_generated_resolve_current_user 2>/dev/null || true)"
    current_home="${HOME:-}"
    if [[ -n "$current_home" ]]; then
      current_home="${current_home%/}"
    fi
    if [[ -n "$current_user" ]] && [[ "$current_user" == "${TARGET_USER:-ubuntu}" ]] && [[ -n "$current_home" ]] && [[ "$current_home" == /* ]] && [[ "$current_home" != "/" ]] && { [[ -z "$explicit_target_home" ]] || [[ "$current_home" == "$explicit_target_home" ]]; }; then
      target_home="$current_home"
    fi
    unset current_user current_home
  fi
  unset _acfs_passwd_entry
fi
unset explicit_target_home
if [[ -z "$target_home" ]] || [[ "$target_home" == "/" ]] || [[ "$target_home" != /* ]]; then
  echo "ERROR: Unable to resolve TARGET_HOME for '\''${TARGET_USER:-ubuntu}'\''; export TARGET_HOME explicitly (got: '\''${target_home:-<empty>}'\'')" >&2
  exit 1
fi
test -d "$target_home/.acfs"
test -f "$target_home/.acfs/docs/AGENTS.workspace.md"'
  ['shell.zsh.0']='zsh --version'
  ['shell.login.0']='source "${ACFS_LIB_DIR:-$HOME/.acfs/scripts/lib}/user.sh"
user_login_shell_configured'
  ['shell.omz.0']='test -d ~/.oh-my-zsh'
  ['shell.omz.1']='test -f ~/.acfs/zsh/acfs.zshrc'
  ['shell.omz.2']='test -f ~/.p10k.zsh'
  ['shell.omz.3']='source "${ACFS_LIB_DIR:-$HOME/.acfs/scripts/lib}/user.sh"
user_login_shell_configured'
  ['cli.modern.0']='rg --version'
  ['cli.modern.1']='tmux -V'
  ['cli.modern.2']='fzf --version'
  ['cli.modern.3']='direnv version'
  ['cli.modern.4']='jq --version'
  ['cli.modern.5']='gh --version'
  ['cli.modern.6']='git-lfs version'
  ['cli.modern.7']='rsync --version'
  ['cli.modern.8']='strace --version'
  ['cli.modern.9']='command -v lsof'
  ['cli.modern.10']='command -v dig'
  ['cli.modern.11']='command -v nc'
  ['tools.lazygit.0']='lazygit --version'
  ['tools.lazydocker.0']='lazydocker --version'
  ['network.tailscale.0']='tailscale version'
  ['network.tailscale.1']='systemctl is-enabled tailscaled'
  ['network.ssh_keepalive.0']='grep -E '\''^ClientAliveInterval[[:space:]]+60'\'' /etc/ssh/sshd_config'
  ['network.ssh_keepalive.1']='grep -E '\''^ClientAliveCountMax[[:space:]]+3'\'' /etc/ssh/sshd_config'
  ['lang.bun.0']='~/.bun/bin/bun --version'
  ['lang.uv.0']='command -v uv >/dev/null 2>&1 && uv --version'
  ['lang.rust.0']='~/.cargo/bin/cargo --version'
  ['lang.rust.1']='~/.cargo/bin/rustup show | grep -q nightly'
  ['lang.go.0']='go version'
  ['lang.nvm.0']='export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
node --version'
  ['tools.atuin.0']='~/.atuin/bin/atuin --version'
  ['tools.zoxide.0']='command -v zoxide'
  ['tools.ast_grep.0']='sg --version'
  ['agents.claude.0']='target_bin="${ACFS_BIN_DIR:-$HOME/.local/bin}"
"$target_bin/claude" --version || "$target_bin/claude" --help'
  ['agents.codex.0']='target_bin="${ACFS_BIN_DIR:-$HOME/.local/bin}"
"$target_bin/codex" --version || "$target_bin/codex" --help'
  ['agents.gemini.0']='target_bin="${ACFS_BIN_DIR:-$HOME/.local/bin}"
"$target_bin/gemini" --version || "$target_bin/gemini" --help'
  ['agents.antigravity.0']='# acfs-summary: verify agy-locked launchers and pinned settings
target_bin="${ACFS_BIN_DIR:-$HOME/.local/bin}"
test -x "$target_bin/agy"
test -x "$target_bin/agy-locked"
test -x "$target_bin/agy-real"
test -x "$target_bin/gmi"
/usr/bin/python3 - <<'\''PY'\''
import json
import pathlib
import sys

settings_path = pathlib.Path.home() / ".gemini" / "antigravity-cli" / "settings.json"
hooks_path = pathlib.Path.home() / ".gemini" / "config" / "hooks.json"
hook_path = pathlib.Path.home() / ".gemini" / "config" / "hooks" / "dcg-antigravity-hook.py"
try:
    settings = json.loads(settings_path.read_text(encoding="utf-8"))
    hooks = json.loads(hooks_path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"invalid or missing Antigravity settings/hooks: {exc}", file=sys.stderr)
    raise SystemExit(1)

expected = {
    "model": "Gemini 4 Argon (High)",
    "toolPermission": "always-proceed",
    "artifactReviewPolicy": "always-proceed",
    "enableTelemetry": False,
    "enableTerminalSandbox": False,
    "allowNonWorkspaceAccess": True,
    "notifications": False,
    "showTips": False,
    "showFeedbackSurvey": False,
    "useG1Credits": False,
    "verbosity": "high",
    "runningLightSpeed": "medium",
    "colorScheme": "terminal",
    "editor": "auto",
    "altScreenMode": "never",
}
for key, value in expected.items():
    if settings.get(key) != value:
        print(f"Antigravity setting {key} is {settings.get(key)!r}, expected {value!r}", file=sys.stderr)
        raise SystemExit(1)
if not hook_path.is_file():
    print(f"Antigravity dcg hook is missing: {hook_path}", file=sys.stderr)
    raise SystemExit(1)
dcg_group = hooks.get("dcg")
pre_tool_use = dcg_group.get("PreToolUse", []) if isinstance(dcg_group, dict) else []
if not isinstance(pre_tool_use, list):
    pre_tool_use = []
hook_registered = any(
    isinstance(entry, dict)
    and entry.get("matcher") == "run_command"
    and any(
        isinstance(hook, dict)
        and hook.get("type") == "command"
        and hook.get("command") == str(hook_path)
        and hook.get("timeout") == 6
        for hook in entry.get("hooks", [])
    )
    for entry in pre_tool_use
)
if not isinstance(dcg_group, dict) or dcg_group.get("enabled") is not True or not hook_registered:
    print(f"Antigravity dcg hook is not enabled and registered in {hooks_path}", file=sys.stderr)
    raise SystemExit(1)
PY'
  ['agents.opencode.0']='opencode --version || opencode --help'
  ['agents.omp.0']='omp --version || omp --help'
  ['agents.grok.0']='grok --version || grok --help'
  ['tools.vault.0']='vault --version'
  ['db.postgres18.0']='for package in postgresql-18 postgresql-client-18; do
  package_status=$(dpkg-query -W -f='\''${db:Status-Status}'\'' "$package" 2>/dev/null) || exit 1
  test "$package_status" = installed || exit 1
done
/usr/lib/postgresql/18/bin/postgres --version | grep -E '\''^postgres \(PostgreSQL\) 18\.'\'' || exit 1
/usr/lib/postgresql/18/bin/psql --version | grep -E '\''^psql \(PostgreSQL\) 18\.'\'''
  ['cloud.wrangler.0']='wrangler --version'
  ['cloud.supabase.0']='supabase --version'
  ['cloud.vercel.0']='vercel --version'
  ['stack.ntm.0']='ntm --help'
  ['stack.mcp_agent_mail.0']='command -v am'
  ['stack.mcp_agent_mail.1']='agent_mail_service_curl() {
  local curl_bin=""
  local candidate=""

  for candidate in /usr/bin/curl /bin/curl /usr/local/bin/curl /usr/local/sbin/curl /usr/sbin/curl /sbin/curl; do
    [[ -x "$candidate" ]] || continue
    curl_bin="$candidate"
    break
  done

  [[ -n "$curl_bin" ]] || return 127
  "$curl_bin" "$@"
}

agent_mail_readiness_ready() {
  local readiness_body=""
  local readiness_url=""

  for readiness_url in \
    http://127.0.0.1:8765/health/readiness \
    http://127.0.0.1:8765/health
  do
    readiness_body="$(agent_mail_service_curl -fsS --max-time 10 "$readiness_url" 2>/dev/null)" || continue
    if printf '\''%s\n'\'' "$readiness_body" | grep -Eq '\''"status"[[:space:]]*:[[:space:]]*"ready"([[:space:]]*[,}])'\''; then
      return 0
    fi
  done

  return 1
}

runtime_dir="/run/user/$(id -u)"
if [[ -d "$runtime_dir" ]]; then
  export XDG_RUNTIME_DIR="$runtime_dir"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus"
fi
if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
  systemctl --user is-active --quiet agent-mail.service >/dev/null 2>&1 || exit 1
fi
agent_mail_service_curl -fsS --max-time 10 http://127.0.0.1:8765/health/liveness >/dev/null
agent_mail_readiness_ready'
  ['stack.meta_skill.0']='ms --version'
  ['stack.automated_plan_reviser.0']='apr --help'
  ['stack.jeffreysprompts.0']='jfp --version'
  ['stack.process_triage.0']='pt --help'
  ['stack.ultimate_bug_scanner.0']='ubs --help'
  ['stack.beads_rust.0']='br --version'
  ['stack.beads_viewer.0']='bv --help || bv --version'
  ['stack.cass.0']='cass --help || cass --version'
  ['stack.cm.0']='cm --version'
  ['stack.caam.0']='caam status || caam --help'
  ['stack.slb.0']='export PATH="$HOME/go/bin:$PATH" && slb >/dev/null 2>&1 || slb --help >/dev/null 2>&1'
  ['stack.dcg.0']='dcg --version'
  ['stack.dcg.1']='claude_settings_has_command_hook() {
  local settings_file="${1:-}"
  local command_pattern="${2:-}"
  local jq_bin=""

  [[ -n "$settings_file" && -n "$command_pattern" ]] || return 1
  [[ -f "$settings_file" ]] || return 1
  for jq_bin in /usr/bin/jq /bin/jq /usr/local/bin/jq /usr/local/sbin/jq /usr/sbin/jq /sbin/jq; do
    [[ -x "$jq_bin" ]] && break
  done
  [[ -x "$jq_bin" ]] || return 1

  "$jq_bin" -e --arg pattern "$command_pattern" '\''
    def command_hook_matches:
      type == "object"
      and ((.type? // "command") == "command")
      and ((.command? // "") | strings | test($pattern));
    def event_entry_matches:
      if type == "object" and (.hooks? | type) == "array" then
        any(.hooks[]?; command_hook_matches)
      else
        command_hook_matches
      end;
    def hook_event_entries:
      if (.hooks? | type) == "object" then
        .hooks | to_entries[]? | .value | arrays | .[]?
      elif (.hooks? | type) == "array" then
        .hooks[]?
      else
        empty
      end;
    any(hook_event_entries; event_entry_matches)
  '\'' "$settings_file" >/dev/null 2>&1
}

settings="$HOME/.claude/settings.json"
alt_settings="$HOME/.config/claude/settings.json"
dcg_command_pattern='\''(^|[[:space:]/])dcg([[:space:]]|$)'\''

claude_settings_has_command_hook "$settings" "$dcg_command_pattern" ||
  claude_settings_has_command_hook "$alt_settings" "$dcg_command_pattern"'
  ['stack.ru.0']='ru --version'
  ['stack.brenner_bot.0']='brenner --version || brenner --help'
  ['stack.rch.0']='rch --version || rch --help'
  ['stack.wezterm_automata.0']='wa --version || wa --help'
  ['stack.srps.0']='command -v sysmoni'
  ['stack.srps.1']='systemctl is-active ananicy-cpp'
  ['stack.frankensearch.0']='fsfs version || fsfs --help'
  ['stack.storage_ballast_helper.0']='command -v sbh'
  ['stack.cross_agent_session_resumer.0']='casr providers || casr --help'
  ['stack.doodlestein_self_releaser.0']='dsr --version || dsr --help'
  ['stack.agent_settings_backup.0']='asb version || asb help'
  ['stack.pcr.0']='claude_settings_has_command_hook() {
  local settings_file="${1:-}"
  local command_pattern="${2:-}"
  local jq_bin=""

  [[ -n "$settings_file" && -n "$command_pattern" ]] || return 1
  [[ -f "$settings_file" ]] || return 1
  for jq_bin in /usr/bin/jq /bin/jq /usr/local/bin/jq /usr/local/sbin/jq /usr/sbin/jq /sbin/jq; do
    [[ -x "$jq_bin" ]] && break
  done
  [[ -x "$jq_bin" ]] || return 1

  "$jq_bin" -e --arg pattern "$command_pattern" '\''
    def command_hook_matches:
      type == "object"
      and ((.type? // "command") == "command")
      and ((.command? // "") | strings | test($pattern));
    def event_entry_matches:
      if type == "object" and (.hooks? | type) == "array" then
        any(.hooks[]?; command_hook_matches)
      else
        command_hook_matches
      end;
    def hook_event_entries:
      if (.hooks? | type) == "object" then
        .hooks | to_entries[]? | .value | arrays | .[]?
      elif (.hooks? | type) == "array" then
        .hooks[]?
      else
        empty
      end;
    any(hook_event_entries; event_entry_matches)
  '\'' "$settings_file" >/dev/null 2>&1
}

target_home="${TARGET_HOME:-$HOME}"
hook_script="$target_home/.local/bin/claude-post-compact-reminder"
settings="$target_home/.claude/settings.json"
alt_settings="$target_home/.config/claude/settings.json"
pcr_command_pattern='\''(^|[[:space:]/])claude-post-compact-reminder([[:space:]]|$)'\''

test -x "$hook_script" || exit 1

claude_settings_has_command_hook "$settings" "$pcr_command_pattern" ||
  claude_settings_has_command_hook "$alt_settings" "$pcr_command_pattern"'
  ['stack.eidetic_engine_cli.0']='ee --version || ee --help'
  ['stack.franken_markdown.0']='fmd --version || fmd --help'
  ['stack.pi_agent_rust.0']='pi --version || pi --help'
  ['stack.power_failure_resumer.0']='command -v pfr'
  ['utils.giil.0']='giil --help || giil --version'
  ['utils.csctf.0']='csctf --help || csctf --version'
  ['utils.xf.0']='xf --help || xf --version'
  ['utils.toon_rust.0']='toon --help || toon --version'
  ['utils.rano.0']='rano --help || rano --version'
  ['utils.mdwb.0']='mdwb --help || mdwb --version'
  ['utils.s2p.0']='s2p --help'
  ['utils.rust_proxy.0']='rust_proxy --help || rust_proxy --version'
  ['utils.aadc.0']='aadc --help || aadc --version'
  ['utils.caut.0']='caut --help || caut --version'
  ['acfs.workspace.0']='test -d /data/projects/my_first_project'
  ['acfs.workspace.1']='acfs_has_active_agents_alias() {
  local file="${1:-}"
  [[ -f "$file" ]] || return 1

  awk '\''
      /^[[:space:]]*#/ { next }
      /^[[:space:]]*alias[[:space:]]+agents=/ { found=1; exit }
      END { exit(found ? 0 : 1) }
  '\'' "$file" 2>/dev/null
}

acfs_has_active_agents_alias ~/.zshrc.local || acfs_has_active_agents_alias ~/.zshrc'
  ['acfs.onboard.0']='onboard --help || command -v onboard'
  ['acfs.update.0']='acfs-update --help || command -v acfs-update'
  ['acfs.nightly.0']='systemctl --user is-enabled acfs-nightly-update.timer'
  ['acfs.doctor.0']='acfs doctor --help || command -v acfs'
)

declare -gA ACFS_MODULE_VERIFY_RUN_AS=(
  ['base.system']="root"
  ['users.ubuntu']="root"
  ['base.filesystem']="root"
  ['shell.zsh']="root"
  ['shell.login']="current"
  ['shell.omz']="target_user"
  ['cli.modern']="target_user"
  ['tools.lazygit']="target_user"
  ['tools.lazydocker']="target_user"
  ['network.tailscale']="root"
  ['network.ssh_keepalive']="root"
  ['lang.bun']="target_user"
  ['lang.uv']="target_user"
  ['lang.rust']="target_user"
  ['lang.go']="target_user"
  ['lang.nvm']="target_user"
  ['tools.atuin']="target_user"
  ['tools.zoxide']="target_user"
  ['tools.ast_grep']="target_user"
  ['agents.claude']="target_user"
  ['agents.codex']="target_user"
  ['agents.gemini']="target_user"
  ['agents.antigravity']="target_user"
  ['agents.opencode']="target_user"
  ['agents.omp']="target_user"
  ['agents.grok']="target_user"
  ['tools.vault']="target_user"
  ['db.postgres18']="root"
  ['cloud.wrangler']="target_user"
  ['cloud.supabase']="target_user"
  ['cloud.vercel']="target_user"
  ['stack.ntm']="target_user"
  ['stack.mcp_agent_mail']="target_user"
  ['stack.meta_skill']="target_user"
  ['stack.automated_plan_reviser']="target_user"
  ['stack.jeffreysprompts']="target_user"
  ['stack.process_triage']="target_user"
  ['stack.ultimate_bug_scanner']="target_user"
  ['stack.beads_rust']="target_user"
  ['stack.beads_viewer']="target_user"
  ['stack.cass']="target_user"
  ['stack.cm']="target_user"
  ['stack.caam']="target_user"
  ['stack.slb']="target_user"
  ['stack.dcg']="target_user"
  ['stack.ru']="target_user"
  ['stack.brenner_bot']="target_user"
  ['stack.rch']="target_user"
  ['stack.wezterm_automata']="target_user"
  ['stack.srps']="target_user"
  ['stack.frankensearch']="target_user"
  ['stack.storage_ballast_helper']="target_user"
  ['stack.cross_agent_session_resumer']="target_user"
  ['stack.doodlestein_self_releaser']="target_user"
  ['stack.agent_settings_backup']="target_user"
  ['stack.pcr']="target_user"
  ['stack.eidetic_engine_cli']="target_user"
  ['stack.franken_markdown']="target_user"
  ['stack.pi_agent_rust']="target_user"
  ['stack.power_failure_resumer']="target_user"
  ['utils.giil']="target_user"
  ['utils.csctf']="target_user"
  ['utils.xf']="target_user"
  ['utils.toon_rust']="target_user"
  ['utils.rano']="target_user"
  ['utils.mdwb']="target_user"
  ['utils.s2p']="target_user"
  ['utils.rust_proxy']="target_user"
  ['utils.aadc']="target_user"
  ['utils.caut']="target_user"
  ['acfs.workspace']="target_user"
  ['acfs.onboard']="target_user"
  ['acfs.update']="target_user"
  ['acfs.nightly']="target_user"
  ['acfs.doctor']="target_user"
)

declare -gA ACFS_MODULE_PLUGIN_PACKAGE=(
)

declare -gA ACFS_MODULE_PLUGIN_VERSION=(
)

declare -gA ACFS_MODULE_PLUGIN_SHA256=(
)

declare -gA ACFS_MODULE_OPTIONAL=(
  ['base.system']="0"
  ['users.ubuntu']="0"
  ['base.filesystem']="0"
  ['shell.zsh']="0"
  ['shell.login']="0"
  ['shell.omz']="0"
  ['cli.modern']="0"
  ['tools.lazygit']="0"
  ['tools.lazydocker']="0"
  ['network.tailscale']="0"
  ['network.ssh_keepalive']="1"
  ['lang.bun']="0"
  ['lang.uv']="0"
  ['lang.rust']="0"
  ['lang.go']="0"
  ['lang.nvm']="0"
  ['tools.atuin']="0"
  ['tools.zoxide']="0"
  ['tools.ast_grep']="0"
  ['agents.claude']="0"
  ['agents.codex']="0"
  ['agents.gemini']="1"
  ['agents.antigravity']="0"
  ['agents.opencode']="1"
  ['agents.omp']="1"
  ['agents.grok']="1"
  ['tools.vault']="1"
  ['db.postgres18']="1"
  ['cloud.wrangler']="1"
  ['cloud.supabase']="1"
  ['cloud.vercel']="1"
  ['stack.ntm']="0"
  ['stack.mcp_agent_mail']="0"
  ['stack.meta_skill']="0"
  ['stack.automated_plan_reviser']="1"
  ['stack.jeffreysprompts']="1"
  ['stack.process_triage']="1"
  ['stack.ultimate_bug_scanner']="0"
  ['stack.beads_rust']="0"
  ['stack.beads_viewer']="0"
  ['stack.cass']="0"
  ['stack.cm']="0"
  ['stack.caam']="0"
  ['stack.slb']="1"
  ['stack.dcg']="0"
  ['stack.ru']="0"
  ['stack.brenner_bot']="1"
  ['stack.rch']="1"
  ['stack.wezterm_automata']="1"
  ['stack.srps']="1"
  ['stack.frankensearch']="1"
  ['stack.storage_ballast_helper']="1"
  ['stack.cross_agent_session_resumer']="1"
  ['stack.doodlestein_self_releaser']="1"
  ['stack.agent_settings_backup']="1"
  ['stack.pcr']="1"
  ['stack.eidetic_engine_cli']="1"
  ['stack.franken_markdown']="1"
  ['stack.pi_agent_rust']="1"
  ['stack.power_failure_resumer']="1"
  ['utils.giil']="1"
  ['utils.csctf']="1"
  ['utils.xf']="1"
  ['utils.toon_rust']="1"
  ['utils.rano']="1"
  ['utils.mdwb']="1"
  ['utils.s2p']="1"
  ['utils.rust_proxy']="1"
  ['utils.aadc']="1"
  ['utils.caut']="1"
  ['acfs.workspace']="1"
  ['acfs.onboard']="0"
  ['acfs.update']="0"
  ['acfs.nightly']="1"
  ['acfs.doctor']="0"
)

# checksums.yaml tool key of every module installed through a verified
# upstream installer (#389). Modules without one have no entry.
declare -gA ACFS_MODULE_VERIFIED_INSTALLER_TOOL=(
  ['shell.omz']="ohmyzsh"
  ['lang.bun']="bun"
  ['lang.uv']="uv"
  ['lang.rust']="rust"
  ['lang.nvm']="nvm"
  ['tools.atuin']="atuin"
  ['tools.zoxide']="zoxide"
  ['agents.claude']="claude"
  ['agents.antigravity']="antigravity"
  ['agents.opencode']="opencode"
  ['agents.omp']="omp"
  ['agents.grok']="grok"
  ['stack.ntm']="ntm"
  ['stack.mcp_agent_mail']="mcp_agent_mail"
  ['stack.meta_skill']="ms"
  ['stack.automated_plan_reviser']="apr"
  ['stack.jeffreysprompts']="jfp"
  ['stack.process_triage']="pt"
  ['stack.ultimate_bug_scanner']="ubs"
  ['stack.beads_rust']="br"
  ['stack.beads_viewer']="bv"
  ['stack.cass']="cass"
  ['stack.cm']="cm"
  ['stack.caam']="caam"
  ['stack.slb']="slb"
  ['stack.dcg']="dcg"
  ['stack.ru']="ru"
  ['stack.brenner_bot']="brenner_bot"
  ['stack.rch']="rch"
  ['stack.srps']="srps"
  ['stack.frankensearch']="fsfs"
  ['stack.storage_ballast_helper']="sbh"
  ['stack.cross_agent_session_resumer']="casr"
  ['stack.doodlestein_self_releaser']="dsr"
  ['stack.agent_settings_backup']="asb"
  ['stack.pcr']="pcr"
  ['stack.eidetic_engine_cli']="ee"
  ['stack.franken_markdown']="fmd"
  ['stack.pi_agent_rust']="pi"
  ['stack.power_failure_resumer']="pfr"
  ['utils.giil']="giil"
  ['utils.csctf']="csctf"
  ['utils.xf']="xf"
  ['utils.toon_rust']="tru"
  ['utils.rano']="rano"
  ['utils.mdwb']="mdwb"
  ['utils.s2p']="s2p"
)

# Space-separated distro families a module applies to (#385).
# A module with no entry here applies to every family.
declare -gA ACFS_MODULE_FAMILIES=(
  ['stack.srps']="ubuntu"
)

ACFS_PROFILES_IN_ORDER=(
  "full"
  "safe"
  "vibe"
  "minimal"
  "agents-only"
  "cloud-only"
  "stack-only"
)

declare -gA ACFS_PROFILE_LABEL=(
  ['full']="Full"
  ['safe']="Safe"
  ['vibe']="Vibe"
  ['minimal']="Minimal"
  ['agents-only']="Agents only"
  ['cloud-only']="Cloud only"
  ['stack-only']="Stack only"
)

declare -gA ACFS_PROFILE_MODE=(
  ['safe']="safe"
  ['vibe']="vibe"
)

declare -gA ACFS_PROFILE_ONLY_MODULES=(
  ['minimal']="shell.omz,cli.modern,lang.bun,lang.uv,agents.claude,agents.codex,agents.antigravity,stack.ntm,stack.mcp_agent_mail,stack.ultimate_bug_scanner,stack.beads_rust,stack.beads_viewer,stack.cass,stack.cm,stack.dcg,stack.ru,stack.rch,acfs.workspace,acfs.onboard,acfs.update,acfs.doctor"
  ['cloud-only']="cloud.wrangler,cloud.supabase,cloud.vercel"
)

declare -gA ACFS_PROFILE_ONLY_PHASES=(
  ['agents-only']="agents"
  ['stack-only']="stack"
)

ACFS_MANIFEST_INDEX_LOADED=true
