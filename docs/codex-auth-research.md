# Codex CLI Authentication Research

> Research findings for bead wy1 (codex.4)
>
> Created: 2025-12-21 | Agent: BlueCastle

## Summary

OpenAI's Codex CLI is **OAuth-first** for ChatGPT accounts, with optional API-key login for pay-as-you-go usage. On a headless VPS, `codex login --device-auth` is the preferred path. This document describes the token storage location and format for use in doctor.sh checks.

## Token Storage Location

### Default Path
- **macOS/Linux**: `~/.codex/auth.json`
- **Windows**: `C:\Users\USERNAME\.codex\auth.json`

### Custom Path
The `CODEX_HOME` environment variable can override the default location:
```bash
export CODEX_HOME=/custom/path
# Tokens stored at $CODEX_HOME/auth.json
```

### Storage Options
The `auth-storage` config option controls how credentials are stored:
- `keyring` - Store in OS keychain (macOS Keychain, Linux Secret Service, Windows Credential Manager)
- `auto` - Use keyring when available, fallback to auth.json

## auth.json Structure

```json
{
  "OPENAI_API_KEY": null,
  "tokens": {
    "id_token": "eyJ...",
    "access_token": "eyJ...",
    "refresh_token": "eyJ...",
    "account_id": "user-..."
  },
  "last_refresh": "2024-12-18T16:51:02.123Z"
}
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `OPENAI_API_KEY` | `string\|null` | API key (legacy auth), null for OAuth |
| `tokens.id_token` | `string` | OAuth ID token (JWT) |
| `tokens.access_token` | `string` | OAuth access token (JWT) |
| `tokens.refresh_token` | `string` | OAuth refresh token for renewal |
| `tokens.account_id` | `string` | ChatGPT account identifier |
| `last_refresh` | `string` | ISO 8601 timestamp of last token refresh |

## Authentication Detection Logic

For doctor.sh to correctly detect Codex CLI authentication:

```bash
check_codex_auth() {
    local auth_file="${CODEX_HOME:-$HOME/.codex}/auth.json"

    # Check if auth file exists
    if [[ ! -f "$auth_file" ]]; then
        echo "FAIL: No auth.json found at $auth_file"
        echo "Suggestion: Run 'codex login --device-auth' to authenticate"
        return 1
    fi

    # Check for OAuth tokens
    if jq -e '.tokens.access_token' "$auth_file" >/dev/null 2>&1; then
        echo "PASS: OAuth authenticated"
        return 0
    fi

    # Check for API key (legacy)
    if jq -e '.OPENAI_API_KEY // empty' "$auth_file" 2>/dev/null | grep -q .; then
        echo "PASS: API key authenticated"
        return 0
    fi

    echo "FAIL: auth.json exists but no valid tokens found"
    echo "Suggestion: Run 'codex login --device-auth' to re-authenticate"
    return 1
}
```

## Authentication Methods

### 1. ChatGPT OAuth (Primary)
```bash
codex login --device-auth
# Recommended on headless VPS hosts
```

### 2. Browser / Localhost OAuth
```bash
codex login
# Opens browser for localhost callback flow
```

### 3. API Key (Optional / Pay-as-you-go)
```bash
# Safe method (doesn't expose key in shell history)
printenv OPENAI_API_KEY | codex login --with-api-key

# From file
codex login --with-api-key < my_key.txt
```

### 4. SSH Tunnel Fallback for Headless/Remote Machines
If device auth is unavailable on your account, use SSH port forwarding:
```bash
ssh -L 1455:localhost:1455 remote-host
# Then run 'codex login' on remote
```

## Key Differences from Previous Understanding

| Aspect | Previous (Wrong) | Correct |
|--------|-----------------|---------|
| Auth method | `OPENAI_API_KEY` env var | OAuth via device auth/browser, or API key login |
| Account type | API account (billing) | ChatGPT Pro/Plus consumer account |
| Detection | Check for env var | Check auth.json for tokens |
| Setup command | Export env var | Run `codex login --device-auth` on a VPS |

## Sources

- [Codex CLI Documentation](https://developers.openai.com/codex/cli)
- [Codex Authentication Docs](https://github.com/openai/codex/blob/main/docs/authentication.md)
- [Codex Config Docs](https://github.com/openai/codex/blob/main/docs/config.md)
- Local testing on macOS with codex-cli 0.76.0
