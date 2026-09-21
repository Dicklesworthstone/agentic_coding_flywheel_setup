"use client";

import { Clock, Eye, GitBranch, Navigation, Search, Terminal } from "lucide-react";
import {
  CodeBlock,
  Divider,
  FeatureCard,
  FeatureGrid,
  GoalBanner,
  Highlight,
  InlineCode,
  Paragraph,
  Section,
  TipBox,
} from "./lesson-components";

export function ModernCliLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Level up your terminal with lazygit, atuin, zoxide, fzf, bat, and lsd &mdash; the modern CLI
        tools that make every command faster and every workflow smoother.
      </GoalBanner>

      {/* Section 1: Your Upgraded Terminal */}
      <Section title="Your Upgraded Terminal" icon={<Terminal className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          ACFS installs a curated set of modern CLI replacements. These tools are drop-in
          replacements that feel familiar but do more &mdash; better output, smarter defaults, and
          features you didn&apos;t know you were missing.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<GitBranch className="h-5 w-5" />}
              title="lazygit"
              description="Git TUI with staging, branching, rebasing"
              gradient="from-orange-500/20 to-red-500/20"
            />
            <FeatureCard
              icon={<Clock className="h-5 w-5" />}
              title="atuin"
              description="Shell history with Ctrl-R search across machines"
              gradient="from-blue-500/20 to-cyan-500/20"
            />
            <FeatureCard
              icon={<Navigation className="h-5 w-5" />}
              title="zoxide"
              description="Smart cd that learns your habits"
              gradient="from-emerald-500/20 to-green-500/20"
            />
            <FeatureCard
              icon={<Search className="h-5 w-5" />}
              title="fzf + bat + lsd"
              description="Fuzzy finder, better cat, better ls"
              gradient="from-violet-500/20 to-purple-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Section 2: lazygit */}
      <Section
        title="lazygit: Git Without Pain"
        icon={<GitBranch className="h-5 w-5" />}
        delay={0.15}
      >
        <Paragraph>
          A full-featured Git TUI for staging, committing, branching, and rebasing &mdash; all
          without leaving the terminal.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Launch lazygit in current directory
lazygit

# Key bindings inside lazygit:
# Space    — stage/unstage file
# c        — commit staged changes
# p        — push
# P        — pull
# b        — checkout branch
# n        — new branch
# M        — merge
# r        — rebase
# ?        — full keybinding help

# Launch for a specific repo
lazygit --path /path/to/repo

# Custom config location
lazygit --use-config-dir ~/.config/lazygit`}
            showLineNumbers
          />
        </div>

        <div className="mt-8">
          <TipBox variant="tip">
            lazygit shows diffs inline as you navigate files. Press <Highlight>Enter</Highlight> on
            a file to see its diff, then <Highlight>Space</Highlight> to stage individual hunks
            &mdash; far more precise than <InlineCode>git add -p</InlineCode>.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Section 3: atuin */}
      <Section title="atuin: Never Lose a Command" icon={<Clock className="h-5 w-5" />} delay={0.2}>
        <Paragraph>
          Shell history search that syncs across machines with a SQLite backend. It replaces Ctrl-R
          with a fuzzy, context-aware search.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Search history (replaces Ctrl-R)
# Press Ctrl-R, then type to fuzzy-search

# Search from command line
atuin search "docker build"

# Show statistics about your command usage
atuin stats

# Filter by directory
atuin search --cwd /path/to/project "cargo"

# Filter by exit code (find failed commands)
atuin search --exit 1

# Filter by time
atuin search --after "2024-01-01" "deploy"

# Import existing shell history
atuin import auto`}
            showLineNumbers
          />
        </div>

        <div className="mt-8">
          <TipBox variant="tip">
            atuin stores full command context: working directory, exit code, duration, and
            timestamp. Search for &ldquo;that docker command I ran last week in the api
            project&rdquo; and actually find it.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Section 4: zoxide */}
      <Section
        title="zoxide: cd That Learns"
        icon={<Navigation className="h-5 w-5" />}
        delay={0.25}
      >
        <Paragraph>
          A smart directory jumper that ranks destinations by frequency and recency. After a few
          days of use, you&apos;ll never type a full path again.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Jump to a directory by partial name
z project     # → /home/ubuntu/projects/my-project
z web         # → /data/projects/acfs/apps/web
z api         # → /data/projects/my-api

# Interactive selection when ambiguous
zi            # Opens fzf picker for all known directories

# Add a directory manually
zoxide add /path/to/important/dir

# List all known directories with scores
zoxide query --list

# Remove a stale directory
zoxide remove /path/that/no/longer/exists

# How it works:
# 1. Every cd is recorded with a frecency score
# 2. Frequent + recent directories rank highest
# 3. "z proj" matches the highest-scored dir containing "proj"`}
            showLineNumbers
          />
        </div>

        <div className="mt-8">
          <TipBox variant="tip">
            zoxide uses &ldquo;frecency&rdquo; (frequency x recency). A directory you visit 10 times
            daily scores higher than one you visited once last month. After a week of normal use,{" "}
            <InlineCode>z</InlineCode> becomes muscle memory.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Section 5: fzf */}
      <Section title="fzf: Fuzzy Find Everything" icon={<Search className="h-5 w-5" />} delay={0.3}>
        <Paragraph>
          A universal fuzzy finder that integrates with everything. Pipe any list of strings into it
          and get instant, interactive filtering.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Interactive file finder
fzf

# Find and open a file in your editor
vim $(fzf)

# Preview files while browsing
fzf --preview 'bat --color=always {}'

# Search file contents (ripgrep + fzf)
rg --line-number "" | fzf --delimiter : --preview 'bat --color=always {1} --highlight-line {2}'

# Git branch picker
git branch | fzf | xargs git checkout

# Process killer
ps aux | fzf | awk '{print $2}' | xargs kill

# Environment variable browser
env | fzf

# Ctrl-T: paste selected file path
# Ctrl-R: search command history (overlaps with atuin)
# Alt-C: cd into selected directory`}
            showLineNumbers
          />
        </div>

        <div className="mt-8">
          <TipBox variant="tip">
            fzf&apos;s real power is piping. Any list of strings can be fuzzy-searched:{" "}
            <InlineCode>docker images | fzf</InlineCode>,{" "}
            <InlineCode>kubectl get pods | fzf</InlineCode>,{" "}
            <InlineCode>brew list | fzf</InlineCode>. If it outputs lines, fzf can filter it.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Section 6: bat & lsd */}
      <Section title="bat & lsd: See More" icon={<Eye className="h-5 w-5" />} delay={0.35}>
        <Paragraph>
          <InlineCode>bat</InlineCode> is <InlineCode>cat</InlineCode> with syntax highlighting and
          line numbers. <InlineCode>lsd</InlineCode> is <InlineCode>ls</InlineCode> with colors and
          icons. Both are drop-in replacements.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# bat: cat with syntax highlighting and line numbers
bat src/main.rs
bat --diff src/main.rs        # Show git changes inline
bat -l json config.yaml       # Force language detection
bat --style=plain file.txt    # No line numbers or grid

# lsd: ls with colors and icons
lsd                           # List current directory
lsd -la                       # Long format with hidden files
lsd --tree                    # Tree view
lsd --tree --depth 2          # Tree with depth limit

# ACFS aliases (already configured):
# cat → bat (automatic)
# ls  → lsd (automatic)
# ll  → lsd -la
# tree → lsd --tree`}
            showLineNumbers
          />
        </div>

        <div className="mt-8">
          <TipBox variant="info">
            These six tools replace the defaults you&apos;ve been using for decades. After a week,
            you&apos;ll wonder how you ever navigated without zoxide or read files without bat.
          </TipBox>
        </div>
      </Section>
    </div>
  );
}
