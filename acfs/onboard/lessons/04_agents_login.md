# Your Agent Commands

**Goal:** Login to your coding agents and understand the shortcuts.

---

## The Three Agents

You have three powerful coding agents installed:

| Agent | Command | Alias | Company |
|-------|---------|-------|---------|
| Claude Code | `claude` | `cc` | Anthropic |
| Codex CLI | `codex` | `cod` | OpenAI |
| Gemini CLI | `gemini` | `gmi` | Google |

---

## What The Aliases Do

The aliases are configured for **maximum power** (vibe mode):

### `cc` (Claude Code)
```bash
NODE_OPTIONS="--max-old-space-size=32768" \
  claude --dangerously-skip-permissions
```
- Extra memory for large projects
- No permission prompts

### `cod` (Codex CLI)
```bash
codex --dangerously-bypass-approvals-and-sandbox
```
- Bypass safety prompts
- No approval/sandbox checks

### `gmi` (Gemini CLI)
```bash
gemini --yolo
```
- YOLO mode (no confirmations)

---

## First Login

Each agent needs to be authenticated once:

### Claude Code
```bash
claude auth login
```
Follow the browser link to authenticate with your Anthropic account.

### Codex CLI

**On a headless VPS**, Codex requires special handling because its OAuth callback expects `localhost:1455`:

**Option 1: Device Auth (Recommended)**
```bash
# First: Enable "Device code login" in ChatGPT Settings → Security
# Then:
codex login --device-auth
```

**Option 2: SSH Tunnel**
```bash
# On your laptop, create a tunnel:
ssh -L 1455:localhost:1455 ubuntu@YOUR_VPS_IP

# Then on the VPS:
codex login
```

**Option 3: Standard Login** (if you have a desktop/browser)
```bash
codex login
```
Follow the browser prompts to authenticate with your **ChatGPT Pro/Plus/Team account**.

> **⚠️ OpenAI Has TWO Account Types:**
>
> | Account Type | For | Auth Method | How to Get |
> |--------------|-----|-------------|------------|
> | **ChatGPT** (Pro/Plus/Team) | Codex CLI, ChatGPT web | OAuth via `codex login` | [chat.openai.com](https://chat.openai.com) subscription |
> | **API** (pay-as-you-go) | OpenAI API, libraries | `OPENAI_API_KEY` env var | [platform.openai.com](https://platform.openai.com) billing |
>
> Codex CLI uses **ChatGPT OAuth**, not API keys. If you have an `OPENAI_API_KEY`, that's for the API—different system!
>
> **If login fails:** Check ChatGPT Settings → Security → "API/Device access"

### Gemini CLI
```bash
gemini
```
Follow the prompts to authenticate with your Google account.

---

## Backup Your Credentials!

After logging in, **immediately** back up your credentials:

```bash
caam backup claude my-main-account
caam backup codex my-main-account
caam backup gemini my-main-account
```

Now you can switch accounts later with:
```bash
caam activate claude my-other-account
```

This is incredibly useful when you hit rate limits!

---

## Test Your Agents

Try each one:

```bash
cc "Hello! Please confirm you're working."
```

```bash
cod "Hello! Please confirm you're working."
```

```bash
gmi "Hello! Please confirm you're working."
```

---

## Quick Tips

1. **Start simple** - Let agents do small tasks first
2. **Be specific** - Clear instructions get better results
3. **Check the output** - Agents can make mistakes
4. **Use multiple agents** - Different agents have different strengths

---

## Practice This Now

Let's verify your agents are ready:

```bash
# Check which agents are installed
which claude codex gemini

# Check your agent credential backups
caam ls

# If you haven't logged in yet, start with Claude:
claude auth login
```

**Pro tip:** If you set up your accounts during the wizard (Step 7: Set Up Accounts), you already have the credentials ready—just run the login commands!

---

## Next

Now let's learn NTM - the tool that orchestrates all these agents:

```bash
onboard 5
```
