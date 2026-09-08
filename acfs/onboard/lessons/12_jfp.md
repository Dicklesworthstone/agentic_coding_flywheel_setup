# Lesson 12: Finding Prompts with JFP

skills:
  - jfp
  - prompts
  - skills

---

# What is JFP?

In Lesson 11, you learned how `ms` manages skills locally. But where do good skills come from?

**JFP (JeffreysPrompts.com CLI)** gives you access to a curated library of battle-tested prompts for Claude, GPT, and other AI coding agents. The CLI and website share the same prompt library.

Prompts are organized into bundles and workflows. You can browse, copy to clipboard, or install them as Claude Code skills through the sibling `jsm` CLI.

---

# Checking Installation

Let's verify `jfp` is installed:

```bash
jfp --help
```

You should see available commands and options.

---

# Browsing Prompts

List all available prompts in the collection:

```bash
jfp list
```

This shows every prompt with its ID, title, and brief description.

---

# Searching for Prompts

Need something specific? Search by keyword:

```bash
jfp search "code review"
```

This filters prompts matching your query. Try searching for topics relevant to your work.

---

# Viewing Prompt Details

Found something interesting? View the full details:

```bash
jfp show idea-wizard
```

This displays the complete prompt content, metadata, and usage examples.

---

# Copying to Clipboard

Want to paste a prompt into your chat? Copy it:

```bash
jfp copy idea-wizard
```

The prompt is now in your clipboard, ready to paste.

---

# Installing as a Skill

The real power: install a skill directly into your agents' skill
directories. Skill installation moved from `jfp` to its sibling CLI `jsm`
(jeffreys-skills.md); the old jfp subcommand now just points you there:

```bash
jsm install idea-wizard
```

List what is installed with `jsm list`. After installation, you can invoke
it in Claude Code:

```bash
/idea-wizard "build a REST API for user management"
```

---

# Web Alternative

Prefer a visual interface? Visit [jeffreysprompts.com](https://jeffreysprompts.com) for a beautiful UI to browse the same collection.

The CLI and website access the same prompt library.

---

# Summary

You've learned:
1. **jfp list** — Browse all available prompts
2. **jfp search** — Find prompts by keyword
3. **jfp show** — View full prompt details
4. **jfp copy** — Copy to clipboard
5. **jsm install** — Install as a Claude Code skill (`jsm list` shows installed ones)

Combined with `ms` from Lesson 11, you now have a complete skill management workflow: find prompts with `jfp`, manage them locally with `ms`.
