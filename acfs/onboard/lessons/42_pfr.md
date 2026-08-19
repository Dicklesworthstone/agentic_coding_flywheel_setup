# Lesson 42: Power Failure Recovery with PFR

skills:
  - pfr
  - reliability
  - session-management

---

# What is PFR?

Ever had a hard power cut kill a dozen running coding-agent sessions at once? PFR gets the whole fleet back.

**PFR (Power Failure Resumer)** recovers crashed local coding-agent sessions after a power failure. It detects the crash by clustering session files whose writes all stopped just before boot, scores its confidence (high/medium/low) with printed reasons, and skips sessions you already resumed by hand.

---

# Checking Installation

PFR has no `--version` flag, so check it this way:

```bash
command -v pfr
pfr --help
```

---

# Previewing a Recovery

Always start with a dry run:

```bash
pfr --dry-run
```

The `pfrd` alias does the same thing. This shows which sessions PFR believes crashed, with confidence scores and reasons, without touching anything.

---

# Executing the Recovery

When the plan looks right, run it for real:

```bash
pfr -y
```

PFR freezes its decisions into last-plan.json, reopens each victim with its recorded model (`cod resume <id>` / `cc --resume <id>`), verifies against `ps`, and writes last-report.json — exiting non-zero on silent failures.

---

# Why PFR Matters for Agents

When you run fleets of agents, one power cut is a mass casualty event. PFR provides:

- Automatic crash detection by clustering write timestamps against boot time
- Confidence scoring with printed reasons, not silent guesses
- Verified resumes — it checks `ps` instead of assuming success
- Selective restore when you only want some sessions back

Note: PFR is mainly for local workstations with a terminal emulator (Ghostty). On a headless VPS it can plan and inspect, but not reopen tabs.

---

# Common Scenarios

```bash
# Preview what would be recovered
pfr --dry-run

# Restore only selected sessions from the saved plan
pfr --last-plan --pick

# Check PFR health
pfr --doctor --json
```

---

# Summary

You've learned:
1. **pfr --dry-run** - Preview the recovery plan safely
2. **pfr -y** - Execute a verified fleet recovery
3. **pfr --last-plan --pick** - Selective restore from a frozen plan
4. How write-time clustering detects power-cut casualties automatically
