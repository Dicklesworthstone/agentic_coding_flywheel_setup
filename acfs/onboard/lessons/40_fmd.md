# Lesson 40: Rendering Markdown with FMD

skills:
  - fmd
  - documentation
  - rendering

---

# What is FMD?

Ever needed a polished HTML or PDF version of a README without wrestling with browsers, LaTeX, or Node? FMD does it in one command.

**FMD (Franken Markdown)** is a pure-Rust, zero-dependency Markdown engine. From a single AST it renders self-contained HTML (inlined CSS, embedded fonts, data-URI images, dark mode) and tagged, compact PDF. Output is deterministic — the same input always produces the same bytes.

---

# Checking Installation

Verify FMD is installed:

```bash
fmd --version
```

---

# Rendering HTML

Turn a Markdown file into a single self-contained HTML file:

```bash
fmd README.md --out README.html
```

The result needs no external assets — CSS, fonts, and images are all embedded, and dark mode is built in.

---

# Rendering PDF

Produce a tagged, compact PDF from the same document:

```bash
fmd README.md --to pdf
```

The `fmdpdf` alias does the same thing. No browser, LaTeX, or Node required — plus syntax highlighting for ~16 languages and Mermaid diagrams.

---

# Why FMD Matters for Agents

Agents constantly produce Markdown that humans need in shareable form. FMD provides:

- Deterministic output, so CI can diff rendered artifacts byte-for-byte
- `fmd render FILE --to both --json` for CI pipelines with machine-readable status
- Zero runtime dependencies — one binary, no toolchain sprawl
- Machine-readable introspection for agent workflows

---

# Common Scenarios

```bash
# Render a doc to both HTML and PDF for CI, with JSON status
fmd render README.md --to both --json

# Check health and discover what the binary can do
fmd doctor --json
fmd capabilities --json

# Agent-oriented triage output
fmd --robot-triage
```

---

# Summary

You've learned:
1. **fmd FILE --out FILE.html** - Render self-contained HTML
2. **fmd FILE --to pdf** - Render tagged, compact PDF
3. **fmd render FILE --to both --json** - Deterministic CI rendering with JSON status
4. How one AST yields both HTML and PDF with no browser or LaTeX
