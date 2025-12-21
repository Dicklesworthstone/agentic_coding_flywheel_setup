# SSH Basics

**Goal:** Understand how to stay connected to your VPS.

---

## What Is SSH?

SSH (Secure Shell) is how you're connected to this VPS right now.

It's an encrypted tunnel between your laptop and this server.

---

## The SSH Command

From your **laptop** (not here), you connected with:

```bash
ssh -i ~/.ssh/acfs_ed25519 ubuntu@YOUR_SERVER_IP
```

Breaking it down:
- `ssh` - the command
- `-i ~/.ssh/acfs_ed25519` - your private key
- `ubuntu` - the username on the VPS
- `@YOUR_SERVER_IP` - the server address

---

## If Your Connection Drops

No worries! SSH connections drop sometimes. Just reconnect:

1. On your laptop, run the ssh command again
2. Your work is safe in tmux (next lesson)

---

## SSH Keys vs Passwords

You're using **key-based authentication**:
- Your **private key** stays on your laptop (`~/.ssh/acfs_ed25519`)
- Your **public key** is on the VPS (`~/.ssh/authorized_keys`)

This is more secure than passwords and lets you connect without typing anything.

---

## Keeping Connections Alive

Add this to your laptop's `~/.ssh/config`:

```
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

This sends keepalive packets every 60 seconds.

---

## Quick Connect Alias

On your laptop, add to `~/.zshrc` or `~/.bashrc`:

```bash
alias vps='ssh -i ~/.ssh/acfs_ed25519 ubuntu@YOUR_SERVER_IP'
```

Then just type `vps` to connect!

---

## Verify You Understand

Answer these:
1. Where does your private key live? (`~/.ssh/acfs_ed25519` on your laptop)
2. What happens if SSH drops? (Reconnect; tmux saves your work)
3. What's the quick way to reconnect? (Use an alias)

---

## Next

This is why tmux is essential:

```bash
onboard 3
```
