# Dotfiles & Secrets Management Guide for ACFS

## Overview

This guide shows you how to save your configuration files on GitHub so you don't have to reconfigure every time you set up a new environment.

---

## 🔓 Non-Sensitive Configuration Files

### What Qualifies as Non-Sensitive?
- Shell aliases (`.zshrc`, `.bashrc`)
- Shell configuration (oh-my-zsh settings)
- Editor settings (`.vimrc`, `nvim/init.lua`)
- Git config (name, email, aliases) - **NOT tokens**
- Terminal settings (tmux, WezTerm)
- Tool configurations (`.ripgreprc`, `.fdignore`, etc.)

### Solution: Create a Dotfiles Repository

```bash
# 1. Initialize dotfiles repo
mkdir -p ~/dotfiles
cd ~/dotfiles
git init

# 2. Move existing configs (examples)
cp ~/.zshrc ./zshrc
cp ~/.gitconfig ./gitconfig
cp ~/.config/nvim/init.lua ./nvim-init.lua
cp ~/.tmux.conf ./tmux.conf

# 3. Create a README
cat > README.md << 'EOF'
# My Dotfiles

Personal configuration files for development environment.

## Installation

```bash
./install.sh
```
EOF

# 4. Create an install script
cat > install.sh << 'EOF'
#!/usr/bin/env bash
set -e

# Symlink dotfiles
ln -sf "$PWD/zshrc" "$HOME/.zshrc"
ln -sf "$PWD/gitconfig" "$HOME/.gitconfig"
ln -sf "$PWD/tmux.conf" "$HOME/.tmux.conf"

# Create config directories if needed
mkdir -p "$HOME/.config/nvim"
ln -sf "$PWD/nvim-init.lua" "$HOME/.config/nvim/init.lua"

echo "Dotfiles installed!"
EOF

chmod +x install.sh

# 5. Commit and push to GitHub
git add .
git commit -m "Initial dotfiles setup"
gh repo create my-dotfiles --public --source=. --remote=origin --push
```

### On New Machines

```bash
cd ~
git clone https://github.com/YOUR_USERNAME/my-dotfiles dotfiles
cd dotfiles
./install.sh
```

---

## 🔐 Secrets & Authentication Tokens

### What Qualifies as Sensitive?
- API keys (OpenAI, Anthropic, Google)
- Auth tokens (`gh auth token`, OAuth tokens)
- SSH private keys
- `.env` files with credentials
- Database passwords
- Cloud provider credentials (AWS, GCP, Azure)

### ⚠️ NEVER commit these directly to GitHub!

---

## Secure Secret Management Options

### **Option 1: Git-Crypt (Recommended for Teams)**

Git-crypt enables transparent encryption/decryption of files in a Git repo.

```bash
# Install git-crypt
sudo apt install git-crypt

# Initialize in your private dotfiles repo
cd ~/dotfiles-private
git init
git-crypt init

# Specify which files to encrypt
cat > .gitattributes << 'EOF'
.env* filter=git-crypt diff=git-crypt
*secret* filter=git-crypt diff=git-crypt
*.key filter=git-crypt diff=git-crypt
auth_tokens.sh filter=git-crypt diff=git-crypt
EOF

# Export your encryption key (STORE SECURELY!)
git-crypt export-key ~/git-crypt-key
# Back up git-crypt-key to USB drive or password manager!

# Add encrypted files
cp ~/.env ./env.encrypted
git add .
git commit -m "Add encrypted secrets"
gh repo create dotfiles-private --private --source=. --remote=origin --push

# On new machine, unlock with your key:
git clone https://github.com/YOUR_USERNAME/dotfiles-private
cd dotfiles-private
git-crypt unlock ~/git-crypt-key
```

### **Option 2: Mozilla SOPS (Industry Standard)**

SOPS (Secrets OPerationS) encrypts values in YAML/JSON files while keeping keys readable.

```bash
# Install SOPS
wget https://github.com/getsops/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops
sudo chmod +x /usr/local/bin/sops

# Install age for encryption (simpler than GPG)
sudo apt install age

# Generate age key
age-keygen -o ~/.config/sops/age/keys.txt
# BACKUP THIS FILE SECURELY!

# Create secrets file
cat > secrets.yaml << EOF
openai_api_key: sk-...your-key...
anthropic_api_key: sk-ant-...
github_token: ghp_...
EOF

# Encrypt it (specify your age public key)
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
sops --encrypt --age $(age-keygen -y ~/.config/sops/age/keys.txt) secrets.yaml > secrets.enc.yaml

# Commit encrypted version
git add secrets.enc.yaml .sops.yaml
git commit -m "Add encrypted secrets"

# Decrypt when needed
sops --decrypt secrets.enc.yaml > secrets.yaml
source secrets.yaml
```

### **Option 3: GitHub Secrets (For CI/CD Only)**

GitHub Secrets are ONLY available to GitHub Actions, not for general use.

```bash
# Add secrets via GitHub CLI
gh secret set OPENAI_API_KEY --body "sk-..."
gh secret set ANTHROPIC_API_KEY --body "sk-ant-..."

# Access in workflows
# .github/workflows/deploy.yml
env:
  OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
```

### **Option 4: HashiCorp Vault (Already Installed in ACFS!)**

Vault is enterprise-grade secret management, already available in your setup.

```bash
# Vault is installed via ACFS (optional module)
# Check if installed
which vault

# Start Vault dev server (for local development)
vault server -dev &
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='your-dev-token'

# Store secrets
vault kv put secret/ai-agents \
  openai_key=sk-... \
  anthropic_key=sk-ant-... \
  github_token=ghp_...

# Retrieve secrets
vault kv get secret/ai-agents
vault kv get -field=openai_key secret/ai-agents

# Add to shell profile
cat >> ~/.zshrc << 'EOF'
# Load secrets from Vault
export OPENAI_API_KEY=$(vault kv get -field=openai_key secret/ai-agents 2>/dev/null)
export ANTHROPIC_API_KEY=$(vault kv get -field=anthropic_key secret/ai-agents 2>/dev/null)
EOF
```

### **Option 5: Simple Encrypted Archive (Quick & Dirty)**

For personal use, encrypt a tarball with GPG or age.

```bash
# Collect secrets
mkdir ~/secrets-backup
cp ~/.env ~/secrets-backup/
cp ~/.ssh/config ~/secrets-backup/
cp ~/.config/gh/hosts.yml ~/secrets-backup/
# Add other auth configs...

# Create encrypted archive
cd ~
tar czf - secrets-backup/ | age -r $(cat ~/.config/sops/age/keys.txt.pub) > secrets.tar.gz.age

# Upload to private GitHub repo
cd ~
mkdir dotfiles-secrets
cd dotfiles-secrets
mv ~/secrets.tar.gz.age .
git init
git add secrets.tar.gz.age
git commit -m "Encrypted secrets backup"
gh repo create dotfiles-secrets --private --source=. --remote=origin --push

# On new machine
git clone https://github.com/YOUR_USERNAME/dotfiles-secrets
cd dotfiles-secrets
age -d -i ~/.config/sops/age/keys.txt secrets.tar.gz.age | tar xzf -
```

---

## 🎯 Recommended Workflow for ACFS

### Structure

```
~/dotfiles/                    # Public repo
├── zshrc
├── gitconfig (NO tokens)
├── tmux.conf
├── aliases.sh
└── install.sh

~/dotfiles-private/            # Private repo with git-crypt
├── .gitattributes
├── env.production            # Encrypted
├── api_tokens.sh             # Encrypted
├── gh_auth_backup.sh         # Encrypted
└── install-secrets.sh
```

### Export Current ACFS Config

```bash
# Export tool versions and module list (NON-SENSITIVE)
cd ~/dotfiles
bash /home/user/agentic-lxc/scripts/lib/export-config.sh --yaml > acfs-config.yaml
git add acfs-config.yaml
git commit -m "Update ACFS config snapshot"
git push
```

### Backup Auth Tokens

```bash
# Create secrets backup script
cat > ~/backup-auth-tokens.sh << 'EOF'
#!/usr/bin/env bash
BACKUP_DIR="$HOME/dotfiles-private"
mkdir -p "$BACKUP_DIR"

# GitHub CLI auth
gh auth status > "$BACKUP_DIR/gh_auth_status.txt" 2>&1
gh auth token > "$BACKUP_DIR/gh_token.txt" 2>/dev/null

# Claude Code auth
if [ -f "$HOME/.config/claude/config.json" ]; then
    cp "$HOME/.config/claude/config.json" "$BACKUP_DIR/claude_config.json"
fi

# OpenAI/Codex
if [ -f "$HOME/.config/codex/config.json" ]; then
    cp "$HOME/.config/codex/config.json" "$BACKUP_DIR/codex_config.json"
fi

# Environment variables
cat > "$BACKUP_DIR/env_vars.sh" << 'ENVEOF'
export OPENAI_API_KEY="${OPENAI_API_KEY}"
export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}"
# Add other env vars...
ENVEOF

echo "Auth tokens backed up to $BACKUP_DIR"
EOF

chmod +x ~/backup-auth-tokens.sh
```

---

## 🚀 Quick Start Checklist

### Initial Setup (One Time)

- [ ] Create public `dotfiles` repo for non-sensitive configs
- [ ] Create private `dotfiles-private` repo with git-crypt
- [ ] Install git-crypt and initialize encryption
- [ ] Generate age keys and backup securely
- [ ] Export current ACFS config with `export-config.sh`
- [ ] Backup auth tokens to encrypted repo
- [ ] Document your setup in README

### On New Machine

- [ ] Clone dotfiles repo and run install script
- [ ] Clone dotfiles-private repo and unlock with git-crypt
- [ ] Run ACFS installer: `curl ... | bash`
- [ ] Restore secrets from encrypted backup
- [ ] Verify all auth tokens work (`gh auth status`, `claude auth status`)

---

## 🛡️ Security Best Practices

1. **Never commit plaintext secrets** - Use `.gitignore` aggressively
2. **Use different tokens per environment** - Don't reuse production keys
3. **Rotate tokens regularly** - Especially after sharing machines
4. **Encrypt backups** - Use git-crypt, SOPS, or age
5. **Store encryption keys securely** - USB drive + password manager
6. **Use 2FA everywhere** - GitHub, cloud providers, etc.
7. **Review commits before pushing** - Check for accidentally committed secrets
8. **Use secret scanning tools** - `truffleHog`, `gitleaks`, `git-secrets`

---

## 🔍 Detect Accidentally Committed Secrets

```bash
# Install gitleaks (secret scanner)
wget https://github.com/gitleaks/gitleaks/releases/download/v8.18.1/gitleaks_8.18.1_linux_x64.tar.gz
tar xzf gitleaks_8.18.1_linux_x64.tar.gz
sudo mv gitleaks /usr/local/bin/

# Scan your repo
cd ~/dotfiles
gitleaks detect --no-git

# Add pre-commit hook
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/sh
gitleaks protect --staged --verbose
EOF
chmod +x .git/hooks/pre-commit
```

---

## 📚 Additional Resources

- [Dotfiles Guide](https://dotfiles.github.io/)
- [Git-Crypt Documentation](https://github.com/AGWA/git-crypt)
- [Mozilla SOPS](https://github.com/getsops/sops)
- [Age Encryption](https://github.com/FiloSottile/age)
- [HashiCorp Vault](https://www.vaultproject.io/)
- [GitHub Security Best Practices](https://docs.github.com/en/code-security/getting-started/best-practices-for-preventing-data-leaks-in-your-organization)

---

## Need Help?

- Check ACFS docs: `/home/user/agentic-lxc/docs/`
- GitHub issues: https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/issues
- Run ACFS doctor: `acfs doctor`
