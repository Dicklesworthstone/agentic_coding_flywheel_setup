# shellcheck shell=bash disable=SC2034,SC1091
# ~/.acfs/zsh/acfs.zshrc
# ACFS canonical zsh config (managed). Safe, fast, minimal duplication.
#
# SC2034: ZSH_THEME, plugins, PROMPT, RPROMPT are used by zsh/omz (not bash)
# SC1091: Dynamic source paths can't be followed by shellcheck

# --- SSH stty guard (prevents weird remote terminal settings) ---
if [[ -n "$SSH_CONNECTION" ]]; then
  stty() {
    case "$1" in
      *:*:*) return 0 ;;  # ignore colon-separated terminal settings
      *) command stty "$@" ;;
    esac
  }
fi

# --- Terminal type fallback (Ghostty, Kitty, etc.) ---
# Fall back to xterm-256color if current $TERM is unknown to the system.
# This fixes "unknown terminal type" errors with modern terminals like Ghostty.
if [[ -n "$TERM" ]] && ! infocmp "$TERM" &>/dev/null; then
  export TERM="xterm-256color"
fi

# --- Paths (early) ---
export PATH="$HOME/.cargo/bin:$PATH"

# Go (support both apt-style and /usr/local/go)
export PATH="$HOME/go/bin:$PATH"
[[ -d /usr/local/go/bin ]] && export PATH="/usr/local/go/bin:$PATH"

# Bun
export BUN_INSTALL="$HOME/.bun"
[[ -d "$BUN_INSTALL/bin" ]] && export PATH="$BUN_INSTALL/bin:$PATH"
[[ -s "$HOME/.bun/_bun" ]] && source "$HOME/.bun/_bun"

# Atuin (installer default)
[[ -d "$HOME/.atuin/bin" ]] && export PATH="$HOME/.atuin/bin:$PATH"

# Ensure user-local binaries take precedence (e.g., native Claude install).
export PATH="$HOME/.local/bin:$PATH"

# --- Oh My Zsh ---
export ZSH="$HOME/.oh-my-zsh"

# Theme
ZSH_THEME="powerlevel10k/powerlevel10k"

# Disable p10k configuration wizard - we provide a pre-configured ~/.p10k.zsh
# This is a fallback in case the config file is missing for some reason
typeset -g POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true

# Oh My Zsh auto-update
zstyle ':omz:update' mode auto
zstyle ':omz:update' frequency 1

# Plugins
plugins=(
  git
  sudo
  colored-man-pages
  command-not-found
  docker
  docker-compose
  python
  pip
  tmux
  tmuxinator
  systemd
  rsync
  zsh-autosuggestions
  zsh-syntax-highlighting
)

# Load OMZ if installed
if [[ -f "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
fi

# --- Editor preference ---
if [[ -n "$SSH_CONNECTION" ]]; then
  export EDITOR='vim'
else
  export EDITOR='nvim'
fi

# --- Modern CLI aliases (only if present) ---
if command -v lsd &>/dev/null; then
  alias ls='lsd --inode --long --all'
  alias ll='lsd -l'
  alias la='lsd -la'
  alias l='lsd'
  alias tree='lsd --tree'
elif command -v eza &>/dev/null; then
  alias ls='eza --icons'
  alias ll='eza -l --icons'
  alias la='eza -la --icons'
  alias l='eza --icons --classify'
  alias tree='eza --tree --icons'
else
  alias ll='ls -alF'
  alias la='ls -A'
  alias l='ls -CF'
fi

# Prefer bat over batcat (Debian/Ubuntu names it batcat)
if command -v bat &>/dev/null; then
  alias cat='bat'
elif command -v batcat &>/dev/null; then
  alias cat='batcat'
fi
# Prefer fd over fdfind (Debian/Ubuntu names it fdfind)
if command -v fd &>/dev/null; then
  alias find='fd'
elif command -v fdfind &>/dev/null; then
  alias find='fdfind'
fi
command -v rg &>/dev/null && alias grep='rg'
command -v dust &>/dev/null && alias du='dust'
command -v btop &>/dev/null && alias top='btop'
command -v nvim &>/dev/null && alias vim='nvim'
command -v lazygit &>/dev/null && alias lg='lazygit'
command -v lazydocker &>/dev/null && alias lzd='lazydocker'

# --- Git aliases ---
alias gs='git status'
alias gd='git diff'
alias gdc='git diff --cached'
alias gp='git push'
alias gpu='git pull'
alias gco='git checkout'
alias gcm='git commit -m'
alias gca='git commit -a -m'
alias gb='git branch'
alias glog='git log --oneline --graph --decorate'

# --- Docker aliases ---
alias dc='docker compose'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias dimg='docker images'
alias dex='docker exec -it'

# --- Directory shortcuts ---
alias dev='cd ~/Development'
alias proj='cd ~/Projects'
alias dots='cd ~/dotfiles'
alias p='cd /data/projects'

# --- Ubuntu/Debian convenience ---
alias update='sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y'
alias install='sudo apt install'
alias search='apt search'

# Update agent CLIs
alias uca='~/.local/bin/claude update && bun install -g --trust @openai/codex@latest && bun install -g --trust @google/gemini-cli@latest'

# --- Custom functions ---
mkcd() { mkdir -p "$1" && cd "$1" || return; }

extract() {
  if [[ -f "$1" ]]; then
    case "$1" in
      *.tar.bz2) tar xjf "$1" ;;
      *.tar.gz)  tar xzf "$1" ;;
      *.bz2)     bunzip2 "$1" ;;
      *.rar)     unrar x "$1" ;;
      *.gz)      gunzip "$1" ;;
      *.tar)     tar xf "$1" ;;
      *.tbz2)    tar xjf "$1" ;;
      *.tgz)     tar xzf "$1" ;;
      *.zip)     unzip "$1" ;;
      *.Z)       uncompress "$1" ;;
      *.7z)      7z x "$1" ;;
      *)         echo "'$1' cannot be extracted" ;;
    esac
  else
    echo "'$1' is not a valid file"
  fi
}

# --- Safe "ls after cd" via chpwd hook (no overriding cd) ---
autoload -U add-zsh-hook
_acfs_ls_after_cd() {
  # only in interactive shells
  [[ -o interactive ]] || return
  if command -v lsd &>/dev/null; then
    lsd
  elif command -v eza &>/dev/null; then
    eza --icons
  else
    ls
  fi
}
add-zsh-hook chpwd _acfs_ls_after_cd

# --- Tool settings ---
export UV_LINK_MODE=copy

# Cargo env (if present)
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

# nvm (Node Version Manager)
export NVM_DIR="$HOME/.nvm"
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
[[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"

# Atuin init (after PATH)
if command -v atuin &>/dev/null; then
  eval "$(atuin init zsh)"
fi

# Zoxide (better cd)
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"

# direnv
command -v direnv &>/dev/null && eval "$(direnv hook zsh)"

# fzf integration (optional)
export FZF_DISABLE_KEYBINDINGS=1
[[ -f "$HOME/.fzf.zsh" ]] && source "$HOME/.fzf.zsh"

# --- Prompt config ---
if [[ "$TERM_PROGRAM" == "vscode" ]]; then
  PROMPT='%n@%m:%~%# '
  RPROMPT=''
else
  [[ -f "$HOME/.p10k.zsh" ]] && source "$HOME/.p10k.zsh"
fi

# --- Local overrides ---
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"

# --- Force Atuin bindings (must be last) ---
bindkey -e
if command -v atuin &>/dev/null; then
  bindkey -M emacs '^R' atuin-search 2>/dev/null
  bindkey -M viins '^R' atuin-search-viins 2>/dev/null
  bindkey -M vicmd '^R' atuin-search-vicmd 2>/dev/null
fi

# --- ACFS env shim (optional) ---
[[ -f "$HOME/.local/bin/env" ]] && source "$HOME/.local/bin/env"

# --- ACFS CLI ---
# Provides `acfs <subcommand>` for post-install utilities
acfs() {
  local acfs_home="${ACFS_HOME:-$HOME/.acfs}"
  local acfs_bin="$HOME/.local/bin/acfs"
  local cmd="${1:-help}"
  shift 1 2>/dev/null || true

  case "$cmd" in
    services-setup|services|setup)
      if [[ -f "$acfs_home/scripts/services-setup.sh" ]]; then
        bash "$acfs_home/scripts/services-setup.sh" "$@"
      elif [[ -x "$acfs_bin" ]]; then
        "$acfs_bin" services-setup "$@"
      else
        echo "Error: services-setup.sh not found"
        echo "Re-run the ACFS installer to get the latest scripts"
        return 1
      fi
      ;;
    doctor|check)
      if [[ -f "$acfs_home/scripts/lib/doctor.sh" ]]; then
        bash "$acfs_home/scripts/lib/doctor.sh" "$@"
      elif [[ -x "$acfs_bin" ]]; then
        "$acfs_bin" doctor "$@"
      else
        echo "Error: doctor.sh not found"
        echo "Re-run the ACFS installer to get the latest scripts"
        return 1
      fi
      ;;
    session|sessions)
      if [[ -f "$acfs_home/scripts/lib/session.sh" ]]; then
        bash "$acfs_home/scripts/lib/session.sh" "$@"
      elif [[ -x "$acfs_bin" ]]; then
        "$acfs_bin" session "$@"
      else
        echo "Error: session.sh not found"
        echo "Re-run the ACFS installer to get the latest scripts"
        return 1
      fi
      ;;
    update)
      if [[ -f "$acfs_home/scripts/lib/update.sh" ]]; then
        bash "$acfs_home/scripts/lib/update.sh" "$@"
      elif [[ -x "$acfs_bin" ]]; then
        "$acfs_bin" update "$@"
      else
        echo "Error: update.sh not found"
        echo "Re-run the ACFS installer to get the latest scripts"
        return 1
      fi
      ;;
    continue|status|progress)
      if [[ -f "$acfs_home/scripts/lib/continue.sh" ]]; then
        bash "$acfs_home/scripts/lib/continue.sh" "$@"
      elif [[ -x "$acfs_bin" ]]; then
        "$acfs_bin" continue "$@"
      else
        echo "Error: continue.sh not found"
        echo "Re-run the ACFS installer to get the latest scripts"
        return 1
      fi
      ;;
    info|i)
      if [[ -f "$acfs_home/scripts/lib/info.sh" ]]; then
        bash "$acfs_home/scripts/lib/info.sh" "$@"
      elif [[ -x "$acfs_bin" ]]; then
        "$acfs_bin" info "$@"
      else
        echo "Error: info.sh not found"
        echo "Re-run the ACFS installer to get the latest scripts"
        return 1
      fi
      ;;
    cheatsheet|cs)
      if [[ -f "$acfs_home/scripts/lib/cheatsheet.sh" ]]; then
        bash "$acfs_home/scripts/lib/cheatsheet.sh" "$@"
      elif [[ -x "$acfs_bin" ]]; then
        "$acfs_bin" cheatsheet "$@"
      else
        echo "Error: cheatsheet.sh not found"
        echo "Re-run the ACFS installer to get the latest scripts"
        return 1
      fi
      ;;
    dashboard|dash)
      if [[ -f "$acfs_home/scripts/lib/dashboard.sh" ]]; then
        bash "$acfs_home/scripts/lib/dashboard.sh" "$@"
      elif [[ -x "$acfs_bin" ]]; then
        "$acfs_bin" dashboard "$@"
      else
        echo "Error: dashboard.sh not found"
        echo "Re-run the ACFS installer to get the latest scripts"
        return 1
      fi
      ;;
    version|-v|--version)
      if [[ -f "$acfs_home/VERSION" ]]; then
        cat "$acfs_home/VERSION"
      else
        echo "ACFS version unknown"
      fi
      ;;
    help|-h|--help|*)
      echo "ACFS - Agentic Coding Flywheel Setup"
      echo ""
      echo "Usage: acfs <command>"
      echo ""
      echo "Commands:"
      echo "  info            Quick system overview (hostname, IP, uptime, progress)"
      echo "  cheatsheet      Command reference (aliases, shortcuts)"
      echo "  dashboard, dash <generate|serve> - Static HTML dashboard"
      echo "  continue        View installation progress (after Ubuntu upgrade)"
      echo "  services-setup  Configure AI agents and cloud services"
      echo "  doctor          Check system health and tool status"
      echo "  session         List/export/import agent sessions (cass)"
      echo "  update          Update ACFS tools to latest versions"
      echo "  version         Show ACFS version"
      echo "  help            Show this help message"
      echo ""
      echo "Output formats (for info/doctor/cheatsheet):"
      echo "  --json          JSON output for scripting"
      echo "  --html          Self-contained HTML dashboard (info only)"
      echo "  --minimal       Just the essentials (info only)"
      ;;
  esac
}

# --- Agent aliases (dangerously enabled by design) ---
alias cc='NODE_OPTIONS="--max-old-space-size=32768" ~/.local/bin/claude --dangerously-skip-permissions'
alias cod='codex --dangerously-bypass-approvals-and-sandbox'
alias gmi='gemini --yolo'

# bun project helpers (common)
alias br='bun run dev'
alias bl='bun run lint'
alias bt='bun run type-check'

# MCP Agent Mail helper (installer usually adds `am`, but keep a fallback)
alias am='cd ~/mcp_agent_mail 2>/dev/null && scripts/run_server_with_token.sh || echo "mcp_agent_mail not found in ~/mcp_agent_mail"'

# --- Keybindings (quality of life) ---
# Ctrl+Arrow for word movement
bindkey "^[[1;5C" forward-word
bindkey "^[[1;5D" backward-word

# Alt+Arrow for word movement
bindkey "^[[1;3C" forward-word
bindkey "^[[1;3D" backward-word
bindkey "^[^[[C" forward-word
bindkey "^[^[[D" backward-word

# Ctrl+Backspace and Ctrl+Delete
bindkey "^H" backward-kill-word
bindkey "^[[3;5~" kill-word

# Home/End keys
bindkey "^[[H" beginning-of-line
bindkey "^[[F" end-of-line
bindkey "^[[1~" beginning-of-line
bindkey "^[[4~" end-of-line
