# Linux Basics

**Goal:** Navigate the filesystem like a pro in 3 minutes.

---

## Where Am I?

```bash
pwd
```

This prints your current directory. You should see `/home/ubuntu`.

---

## What's Here?

```bash
ls
```

With ACFS, this is aliased to `lsd` which shows beautiful icons.

Try these variations:
- `ll` - long format with details
- `la` - show hidden files
- `tree` - tree view of directories

---

## Moving Around

```bash
cd /data/projects    # Go to the projects directory
cd ~                 # Go home (shortcut)
cd ..                # Go up one level
cd -                 # Go to previous directory
```

**Pro tip:** With zoxide installed, you can use `z projects` to jump to `/data/projects` after visiting it once!

---

## Creating Things

```bash
mkdir my-project     # Create a directory
mkcd my-project      # Create AND cd into it (ACFS function)
touch file.txt       # Create an empty file
```

---

## Viewing Files

```bash
cat file.txt         # Print entire file (aliased to bat)
less file.txt        # Scroll through file (q to quit)
head -20 file.txt    # First 20 lines
tail -20 file.txt    # Last 20 lines
```

---

## Deleting Things (Careful!)

```bash
rm file.txt          # Delete a file
rm -rf directory/    # Delete a directory (DANGEROUS!)
```

**Warning:** There's no trash can in Linux. Deleted = gone.

---

## Searching

```bash
rg "search term"     # Search file contents (ripgrep)
fd "pattern"         # Find files by name (fd)
```

---

## Verify You Learned It

Try this sequence:

```bash
cd /data/projects
mkcd acfs-test
pwd
touch hello.txt
ls
cat hello.txt
cd ..
ls
```

If that all worked, you're ready for the next lesson!

---

## Next

```bash
onboard 2
```
