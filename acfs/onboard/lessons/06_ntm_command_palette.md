# NTM Command Palette

**Goal:** Discover the pre-built prompts that supercharge your agents.

---

## What Is The Command Palette?

NTM ships with a **command palette** - a collection of battle-tested prompts
for common development tasks.

These aren't just prompts. They're carefully crafted instructions that get
the best results from coding agents.

---

## View The Palette

```bash
ntm palette
```

This opens an interactive browser of all available prompts.

---

## Palette Categories

The prompts are organized into categories:

### Architecture & Design
- System design analysis
- Architecture review
- API design patterns

### Code Quality
- Code review prompts
- Refactoring suggestions
- Bug hunting strategies

### Testing
- Test generation
- Coverage analysis
- Edge case discovery

### Documentation
- README generation
- API documentation
- Inline comment review

### Debugging
- Error analysis
- Performance profiling
- Memory leak detection

---

## Using Palette Prompts

### Option 1: Copy and Send

1. Open the palette: `ntm palette`
2. Select a prompt
3. Copy it
4. Use `ntm send` or paste directly

### Option 2: Direct Send (Power Move)

```bash
ntm palette myproject --send
```

This lets you select a prompt and immediately send it to all agents!

---

## Example Prompts

Here are a few examples from the palette:

### Code Review
```
Review this code with an emphasis on:
1. Security vulnerabilities
2. Performance issues
3. Code readability
4. Edge cases not handled

For each issue, provide:
- The specific problem
- Why it matters
- A suggested fix
```

### Architecture Analysis
```
Analyze the architecture of this codebase:
1. Identify the main components
2. Map the data flow
3. Note any anti-patterns
4. Suggest improvements

Create a simple diagram if helpful.
```

---

## Customizing The Palette

You can add your own prompts:

```bash
# Location of custom prompts
~/.acfs/palette/custom/
```

Create `.md` files with your prompts, and they'll appear in the palette.

---

## Pro Tips

1. **Start broad, then narrow** - Use high-level prompts first
2. **Combine agents** - Send different prompts to different agents
3. **Build on responses** - Use agent output in follow-up prompts
4. **Save good prompts** - Add working prompts to your custom palette

---

## Try It Now

```bash
# Open the palette
ntm palette

# Browse the categories
# Select something interesting
# Try sending it to your test session
```

---

## Next

Now let's put it all together - the complete flywheel workflow:

```bash
onboard 7
```
