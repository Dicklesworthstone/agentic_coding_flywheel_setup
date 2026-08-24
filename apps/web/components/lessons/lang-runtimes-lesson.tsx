"use client";

import {
  Layers,
  Zap,
  Package,
  Cog,
  Cloud,
  Server,
} from "lucide-react";
import {
  Section,
  Paragraph,
  CodeBlock,
  TipBox,
  Divider,
  GoalBanner,
  FeatureCard,
  FeatureGrid,
  InlineCode,
} from "./lesson-components";

export function LangRuntimesLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Master five language runtimes installed by ACFS &mdash; Bun for
        TypeScript, uv for Python, Rust/cargo for systems code, Go for cloud
        tooling, and nvm for Node.js compatibility.
      </GoalBanner>

      {/* Section 1: Your Language Stack */}
      <Section
        title="Your Language Stack"
        icon={<Layers className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph>
          ACFS installs 5 language runtimes, each chosen for a specific role in
          the agentic coding workflow.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Zap className="h-5 w-5" />}
              title="Bun"
              description="JS/TS runtime — fast, replaces npm/yarn/pnpm"
              gradient="from-orange-500/20 to-yellow-500/20"
            />
            <FeatureCard
              icon={<Package className="h-5 w-5" />}
              title="uv"
              description="Python tooling — 10-100x faster than pip"
              gradient="from-blue-500/20 to-cyan-500/20"
            />
            <FeatureCard
              icon={<Cog className="h-5 w-5" />}
              title="Rust"
              description="Systems language — cargo for the Agent Flywheel stack"
              gradient="from-red-500/20 to-orange-500/20"
            />
            <FeatureCard
              icon={<Cloud className="h-5 w-5" />}
              title="Go"
              description="Cloud tooling — many DevOps tools written in Go"
              gradient="from-emerald-500/20 to-green-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Section 2: Bun: The JS/TS Runtime */}
      <Section
        title="Bun: The JS/TS Runtime"
        icon={<Zap className="h-5 w-5" />}
        delay={0.15}
      >
        <Paragraph>
          Bun replaces Node.js + npm + npx for most tasks. ACFS uses Bun
          exclusively &mdash; never use npm/yarn/pnpm.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Run TypeScript directly (no build step)
bun run src/index.ts

# Install dependencies (reads package.json)
bun install

# Install a global CLI tool
bun install -g turbo

# Run package.json scripts
bun run dev
bun run build
bun run test

# Execute a package binary (like npx)
bunx create-next-app@latest

# Bun as a test runner
bun test

# Check Bun version
bun --version`}
            showLineNumbers
          />
        </div>

        <div className="mt-8">
          <TipBox variant="tip">
            <InlineCode>bun install -g</InlineCode> is valid syntax (alias for{" "}
            <InlineCode>bun add -g</InlineCode>). Don&apos;t &ldquo;fix&rdquo;
            it &mdash; this is intentional and documented in AGENTS.md.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Section 3: uv: Fast Python */}
      <Section
        title="uv: Fast Python"
        icon={<Package className="h-5 w-5" />}
        delay={0.2}
      >
        <Paragraph>
          uv is a Rust-powered Python package manager that&apos;s 10-100x faster
          than pip. It handles virtual environments, dependency resolution, and
          Python version management.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Create a new Python project
uv init my-project
cd my-project

# Add dependencies (automatically creates venv)
uv add requests fastapi sqlalchemy

# Run a Python script (uses project's venv)
uv run python main.py

# Install a CLI tool globally
uv tool install ruff

# Create and manage virtual environments
uv venv .venv
source .venv/bin/activate

# Install from requirements.txt
uv pip install -r requirements.txt

# Python version management
uv python install 3.12
uv python list`}
            showLineNumbers
          />
        </div>

        <div className="mt-8">
          <TipBox variant="tip">
            uv automatically creates and manages virtual environments. You
            rarely need to manually create a venv &mdash; just{" "}
            <InlineCode>uv add</InlineCode> and{" "}
            <InlineCode>uv run</InlineCode>.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Section 4: Rust & Cargo */}
      <Section
        title="Rust & Cargo"
        icon={<Cog className="h-5 w-5" />}
        delay={0.25}
      >
        <Paragraph>
          The Agent Flywheel stack (NTM, BV, CAAM, DCG, etc.) is built in
          Rust. Cargo is the build system, package manager, and test runner.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Build a project
cargo build
cargo build --release    # Optimized build

# Run tests
cargo test
cargo test -- --nocapture  # Show println output

# Check for issues without building
cargo clippy -- -D warnings

# Format code
cargo fmt

# Run a binary
cargo run -- --help

# Add a dependency
cargo add serde --features derive
cargo add tokio --features full

# Update dependencies
cargo update

# RCH: offload builds to remote workers
rch exec -- cargo build --release
rch exec -- cargo test`}
            showLineNumbers
          />
        </div>

        <div className="mt-8">
          <TipBox variant="tip">
            When multiple agents build simultaneously, use RCH to offload
            compilation to remote workers. This prevents CPU contention on your
            development VPS.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Section 5: Go for Cloud Tools */}
      <Section
        title="Go for Cloud Tools"
        icon={<Cloud className="h-5 w-5" />}
        delay={0.3}
      >
        <Paragraph>
          Many DevOps and cloud tools are written in Go (lazygit, lazydocker,
          goreleaser). Go is also used to build some Agent Flywheel tools
          (SLB, DSR).
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Check Go installation
go version

# Build a Go project
go build ./...

# Run tests
go test ./...

# Install a Go binary from source
go install github.com/charmbracelet/gum@latest

# Download dependencies
go mod download
go mod tidy

# Cross-compile for different platforms
GOOS=linux GOARCH=amd64 go build -o myapp-linux
GOOS=darwin GOARCH=arm64 go build -o myapp-macos

# Common Go tools installed by ACFS
# lazygit, lazydocker, goreleaser, gum`}
            showLineNumbers
          />
        </div>
      </Section>

      <Divider />

      {/* Section 6: nvm & Node.js */}
      <Section
        title="nvm & Node.js"
        icon={<Server className="h-5 w-5" />}
        delay={0.35}
      >
        <Paragraph>
          nvm manages Node.js versions for tools that require Node (not Bun).
          Some CI tools and older packages still need Node.js.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# List installed Node versions
nvm ls

# Install latest LTS
nvm install --lts

# Use a specific version
nvm use 22

# Set default version
nvm alias default 22

# When to use Node vs Bun:
# Bun: all ACFS development, Next.js, TypeScript
# Node: CI environments, tools that don't support Bun yet

# Check which runtime you're using
which node    # Should be nvm-managed
which bun     # Should be ~/.bun/bin/bun`}
            showLineNumbers
          />
        </div>

        <div className="mt-8">
          <TipBox variant="info">
            Five runtimes, each with a clear role. Bun for daily TypeScript
            work, uv for Python, Rust for the core tools, Go for cloud
            infrastructure, and Node.js as a compatibility fallback.
          </TipBox>
        </div>
      </Section>
    </div>
  );
}
