"use client";

import {
  Calculator,
  Check,
  CheckSquare,
  ChevronDown,
  Clipboard,
  Cpu,
  Database,
  Eye,
  EyeOff,
  File,
  FileCode,
  Filter,
  FlaskConical,
  Folder,
  FolderOpen,
  Gauge,
  Globe,
  Hash,
  Layers,
  ListFilter,
  Package,
  Play,
  Server,
  Square,
  Terminal,
  Zap,
} from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { AnimatePresence, motion } from "@/components/motion";
import {
  CodeBlock,
  CommandList,
  Divider,
  FeatureCard,
  FeatureGrid,
  GoalBanner,
  Highlight,
  Paragraph,
  Section,
  TipBox,
} from "./lesson-components";

export function S2pLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Combine source code files into LLM-ready prompts with interactive file selection and token
        counting.
      </GoalBanner>

      {/* Section 1: What Is S2P */}
      <Section title="What Is S2P?" icon={<FileCode className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>S2P (Source to Prompt TUI)</Highlight> is a terminal-based tool for combining
          source code files into a single, LLM-ready prompt. It provides an interactive file browser
          where you can select exactly which files to include, see the combined output in real-time,
          and track your token count as you go.
        </Paragraph>
        <Paragraph>
          Crafting prompts with code context is tedious when done manually. S2P lets you
          interactively navigate your codebase, toggle files on/off, preview the combined output,
          and copy everything to your clipboard in one keystroke. It respects your .gitignore
          automatically.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<FolderOpen className="h-5 w-5" />}
              title="Interactive Selection"
              description="Browse and toggle files visually"
              gradient="from-green-500/20 to-emerald-500/20"
            />
            <FeatureCard
              icon={<Calculator className="h-5 w-5" />}
              title="Token Counting"
              description="tiktoken-accurate, real-time"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<Clipboard className="h-5 w-5" />}
              title="Clipboard Copy"
              description="One keystroke to copy output"
              gradient="from-purple-500/20 to-violet-500/20"
            />
            <FeatureCard
              icon={<ListFilter className="h-5 w-5" />}
              title="Gitignore-Aware"
              description="Respects .gitignore automatically"
              gradient="from-amber-500/20 to-orange-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Section 2: Essential Commands */}
      <Section title="Essential Commands" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <CommandList
          commands={[
            { command: "s2p", description: "Launch interactive TUI in current directory" },
            { command: "s2p /path/to/project", description: "Open specific directory" },
            { command: "s2p --help", description: "Show all options" },
          ]}
        />

        <TipBox variant="info">
          S2P is built with React and Ink, giving you a beautiful terminal UI. Use arrow keys to
          navigate, Space to toggle files, and Enter to confirm your selection.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: TUI Navigation */}
      <Section title="TUI Navigation" icon={<Zap className="h-5 w-5" />} delay={0.3}>
        <Paragraph>
          Once you launch S2P, you get an interactive file browser. Here are the key controls:
        </Paragraph>
        <CodeBlock
          code={`# Keyboard Controls
↑/↓          Navigate between files
Space        Toggle file selection
Enter        Expand/collapse directories
a            Select all files
n            Deselect all files
c            Copy to clipboard
q / Esc      Quit`}
        />

        <Paragraph>
          The interface shows you the total token count in real-time as you select files. This helps
          you stay within Claude&apos;s or GPT&apos;s context window limits.
        </Paragraph>
      </Section>

      <Divider />

      {/* Interactive Source Combiner Demo */}
      <Section
        title="Try It: Source Bundling Laboratory"
        icon={<Gauge className="h-5 w-5" />}
        delay={0.35}
      >
        <Paragraph>
          Explore different project types below. Toggle source files, apply glob filters, and watch
          S2P scan, measure, and combine them into a single LLM-ready prompt.
        </Paragraph>
        <InteractiveSourceCombiner />
      </Section>

      <Divider />

      {/* Section 4: Example Workflow */}
      <Section title="Example Workflow" icon={<Play className="h-5 w-5" />} delay={0.4}>
        <CodeBlock
          code={`# Navigate to your project
cd /data/projects/my-app

# Launch S2P
s2p

# In the TUI:
# 1. Navigate to src/ directory
# 2. Select relevant TypeScript files
# 3. Watch token count update
# 4. Press 'c' to copy to clipboard

# Now paste into Claude/GPT with your question:
# "Here's my source code. Can you help me..."`}
        />

        <TipBox variant="tip">
          S2P formats the output with clear file path headers and syntax-appropriate code blocks,
          making it easy for LLMs to understand the code structure.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 5: Synergies */}
      <Section
        title="Synergies with Other Tools"
        icon={<FileCode className="h-5 w-5" />}
        delay={0.5}
      >
        <Paragraph>S2P works great alongside other flywheel tools:</Paragraph>
        <ul className="list-disc pl-6 space-y-2 text-muted-foreground">
          <li>
            <strong>CASS:</strong> The prompts you create with S2P can be searched later in your
            agent session history.
          </li>
          <li>
            <strong>CM (CASS Memory):</strong> Use S2P outputs as reference material when extracting
            rules for your memory playbook.
          </li>
          <li>
            <strong>NTM:</strong> Launch S2P in a dedicated tmux pane while your agent works in
            another.
          </li>
        </ul>
      </Section>
    </div>
  );
}

// =============================================================================
// PROJECT TYPE DATA
// =============================================================================

interface ProjectFile {
  name: string;
  path: string;
  tokens: number;
  language: string;
  content: string;
  /** Depth in the tree (0 = root) */
  depth: number;
  /** Whether it's a directory */
  isDir: boolean;
  /** Matches current glob filter? */
  excluded?: boolean;
}

interface ProjectType {
  id: string;
  label: string;
  icon: typeof Globe;
  color: string;
  contextLimit: number;
  globFilter: string;
  description: string;
  files: ProjectFile[];
}

const PROJECT_TYPES: ProjectType[] = [
  {
    id: "react",
    label: "React App",
    icon: Globe,
    color: "text-cyan-400",
    contextLimit: 32000,
    globFilter: "**/*.{tsx,ts}",
    description: "Next.js frontend with components and hooks",
    files: [
      { name: "src/", path: "src/", tokens: 0, language: "", content: "", depth: 0, isDir: true },
      {
        name: "app.tsx",
        path: "src/app.tsx",
        tokens: 1800,
        language: "tsx",
        depth: 1,
        isDir: false,
        content: `import { Routes, Route } from 'react-router-dom';\nimport { AuthProvider } from './context/auth';\nimport { Dashboard } from './pages/dashboard';\nimport { Login } from './pages/login';\n\nexport function App() {\n  return (\n    <AuthProvider>\n      <Routes>\n        <Route path="/login" element={<Login />} />\n        <Route path="/*" element={<Dashboard />} />\n      </Routes>\n    </AuthProvider>\n  );\n}`,
      },
      {
        name: "hooks/",
        path: "src/hooks/",
        tokens: 0,
        language: "",
        content: "",
        depth: 1,
        isDir: true,
      },
      {
        name: "useAuth.ts",
        path: "src/hooks/useAuth.ts",
        tokens: 2400,
        language: "ts",
        depth: 2,
        isDir: false,
        content: `import { useContext, useCallback } from 'react';\nimport { AuthContext } from '../context/auth';\n\nexport function useAuth() {\n  const ctx = useContext(AuthContext);\n  const login = useCallback(async (email: string, pass: string) => {\n    const res = await fetch('/api/auth/login', {\n      method: 'POST',\n      body: JSON.stringify({ email, pass }),\n    });\n    const { token } = await res.json();\n    ctx.setToken(token);\n  }, [ctx]);\n  return { ...ctx, login };\n}`,
      },
      {
        name: "useQuery.ts",
        path: "src/hooks/useQuery.ts",
        tokens: 3100,
        language: "ts",
        depth: 2,
        isDir: false,
        content: `import { useState, useEffect } from 'react';\n\nexport function useQuery<T>(url: string) {\n  const [data, setData] = useState<T | null>(null);\n  const [loading, setLoading] = useState(true);\n  const [error, setError] = useState<Error | null>(null);\n  useEffect(() => {\n    fetch(url)\n      .then(r => r.json())\n      .then(setData)\n      .catch(setError)\n      .finally(() => setLoading(false));\n  }, [url]);\n  return { data, loading, error };\n}`,
      },
      {
        name: "components/",
        path: "src/components/",
        tokens: 0,
        language: "",
        content: "",
        depth: 1,
        isDir: true,
      },
      {
        name: "Button.tsx",
        path: "src/components/Button.tsx",
        tokens: 1200,
        language: "tsx",
        depth: 2,
        isDir: false,
        content: `interface ButtonProps {\n  variant?: 'primary' | 'secondary';\n  children: React.ReactNode;\n  onClick?: () => void;\n}\n\nexport function Button({ variant = 'primary', children, onClick }: ButtonProps) {\n  return (\n    <button\n      className={\`btn btn-\${variant}\`}\n      onClick={onClick}\n    >\n      {children}\n    </button>\n  );\n}`,
      },
      {
        name: "DataTable.tsx",
        path: "src/components/DataTable.tsx",
        tokens: 4500,
        language: "tsx",
        depth: 2,
        isDir: false,
        content: `import { useQuery } from '../hooks/useQuery';\nimport { Spinner } from './Spinner';\n\ninterface Column<T> {\n  key: keyof T;\n  header: string;\n  render?: (val: T[keyof T]) => React.ReactNode;\n}\n\nexport function DataTable<T extends Record<string, unknown>>({\n  url, columns\n}: { url: string; columns: Column<T>[] }) {\n  const { data, loading } = useQuery<T[]>(url);\n  if (loading) return <Spinner />;\n  return (\n    <table>\n      <thead><tr>{columns.map(c => <th key={String(c.key)}>{c.header}</th>)}</tr></thead>\n      <tbody>{data?.map((row, i) => (\n        <tr key={i}>{columns.map(c => <td key={String(c.key)}>{c.render ? c.render(row[c.key]) : String(row[c.key])}</td>)}</tr>\n      ))}</tbody>\n    </table>\n  );\n}`,
      },
      {
        name: "package.json",
        path: "package.json",
        tokens: 650,
        language: "json",
        depth: 0,
        isDir: false,
        content: `{\n  "name": "react-dashboard",\n  "version": "1.0.0",\n  "dependencies": {\n    "react": "^19.0.0",\n    "react-router-dom": "^7.0.0"\n  }\n}`,
      },
      {
        name: "tsconfig.json",
        path: "tsconfig.json",
        tokens: 420,
        language: "json",
        depth: 0,
        isDir: false,
        content: `{\n  "compilerOptions": {\n    "target": "ES2022",\n    "jsx": "react-jsx",\n    "strict": true\n  }\n}`,
      },
    ],
  },
  {
    id: "go-service",
    label: "Go Service",
    icon: Server,
    color: "text-sky-400",
    contextLimit: 32000,
    globFilter: "**/*.go",
    description: "HTTP API service with middleware and handlers",
    files: [
      { name: "cmd/", path: "cmd/", tokens: 0, language: "", content: "", depth: 0, isDir: true },
      {
        name: "main.go",
        path: "cmd/main.go",
        tokens: 1600,
        language: "go",
        depth: 1,
        isDir: false,
        content: `package main\n\nimport (\n\t"log"\n\t"net/http"\n\t"myapp/internal/handler"\n\t"myapp/internal/middleware"\n)\n\nfunc main() {\n\tmux := http.NewServeMux()\n\tmux.HandleFunc("/api/users", handler.ListUsers)\n\tmux.HandleFunc("/api/health", handler.Health)\n\n\tstack := middleware.Chain(\n\t\tmiddleware.Logger,\n\t\tmiddleware.CORS,\n\t\tmiddleware.Auth,\n\t)\n\tlog.Fatal(http.ListenAndServe(":8080", stack(mux)))\n}`,
      },
      {
        name: "internal/",
        path: "internal/",
        tokens: 0,
        language: "",
        content: "",
        depth: 0,
        isDir: true,
      },
      {
        name: "handler/",
        path: "internal/handler/",
        tokens: 0,
        language: "",
        content: "",
        depth: 1,
        isDir: true,
      },
      {
        name: "users.go",
        path: "internal/handler/users.go",
        tokens: 2800,
        language: "go",
        depth: 2,
        isDir: false,
        content: `package handler\n\nimport (\n\t"encoding/json"\n\t"net/http"\n\t"myapp/internal/store"\n)\n\nfunc ListUsers(w http.ResponseWriter, r *http.Request) {\n\tusers, err := store.DB.ListUsers(r.Context())\n\tif err != nil {\n\t\thttp.Error(w, err.Error(), 500)\n\t\treturn\n\t}\n\tw.Header().Set("Content-Type", "application/json")\n\tjson.NewEncoder(w).Encode(users)\n}`,
      },
      {
        name: "health.go",
        path: "internal/handler/health.go",
        tokens: 800,
        language: "go",
        depth: 2,
        isDir: false,
        content: `package handler\n\nimport "net/http"\n\nfunc Health(w http.ResponseWriter, _ *http.Request) {\n\tw.WriteHeader(http.StatusOK)\n\tw.Write([]byte("ok"))\n}`,
      },
      {
        name: "middleware/",
        path: "internal/middleware/",
        tokens: 0,
        language: "",
        content: "",
        depth: 1,
        isDir: true,
      },
      {
        name: "auth.go",
        path: "internal/middleware/auth.go",
        tokens: 3200,
        language: "go",
        depth: 2,
        isDir: false,
        content: `package middleware\n\nimport (\n\t"context"\n\t"net/http"\n\t"strings"\n\t"myapp/internal/auth"\n)\n\nfunc Auth(next http.Handler) http.Handler {\n\treturn http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {\n\t\ttoken := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")\n\t\tclaims, err := auth.Verify(token)\n\t\tif err != nil {\n\t\t\thttp.Error(w, "unauthorized", 401)\n\t\t\treturn\n\t\t}\n\t\tctx := context.WithValue(r.Context(), "claims", claims)\n\t\tnext.ServeHTTP(w, r.WithContext(ctx))\n\t})\n}`,
      },
      {
        name: "go.mod",
        path: "go.mod",
        tokens: 350,
        language: "go",
        depth: 0,
        isDir: false,
        content: `module myapp\n\ngo 1.22\n\nrequire (\n\tgithub.com/lib/pq v1.10.9\n)`,
      },
      {
        name: "Makefile",
        path: "Makefile",
        tokens: 480,
        language: "makefile",
        depth: 0,
        isDir: false,
        content: `build:\n\tgo build -o bin/server ./cmd\n\ntest:\n\tgo test ./...\n\nlint:\n\tgolangci-lint run`,
      },
    ],
  },
  {
    id: "rust-cli",
    label: "Rust CLI",
    icon: Cpu,
    color: "text-orange-400",
    contextLimit: 32000,
    globFilter: "**/*.rs",
    description: "CLI tool with clap argument parsing",
    files: [
      { name: "src/", path: "src/", tokens: 0, language: "", content: "", depth: 0, isDir: true },
      {
        name: "main.rs",
        path: "src/main.rs",
        tokens: 1900,
        language: "rust",
        depth: 1,
        isDir: false,
        content: `use clap::Parser;\nmod commands;\nmod config;\n\n#[derive(Parser)]\n#[command(name = "mytool", about = "A fast CLI tool")]\nenum Cli {\n    Init { path: Option<String> },\n    Run { #[arg(short, long)] verbose: bool },\n    Check,\n}\n\nfn main() -> anyhow::Result<()> {\n    let cli = Cli::parse();\n    match cli {\n        Cli::Init { path } => commands::init(path),\n        Cli::Run { verbose } => commands::run(verbose),\n        Cli::Check => commands::check(),\n    }\n}`,
      },
      {
        name: "commands/",
        path: "src/commands/",
        tokens: 0,
        language: "",
        content: "",
        depth: 1,
        isDir: true,
      },
      {
        name: "mod.rs",
        path: "src/commands/mod.rs",
        tokens: 600,
        language: "rust",
        depth: 2,
        isDir: false,
        content: `pub mod init;\npub mod run;\npub mod check;\n\npub use init::init;\npub use run::run;\npub use check::check;`,
      },
      {
        name: "init.rs",
        path: "src/commands/init.rs",
        tokens: 2200,
        language: "rust",
        depth: 2,
        isDir: false,
        content: `use std::fs;\nuse std::path::PathBuf;\nuse crate::config::Config;\n\npub fn init(path: Option<String>) -> anyhow::Result<()> {\n    let dir = path.map(PathBuf::from).unwrap_or_else(|| {\n        std::env::current_dir().expect("no cwd")\n    });\n    let config = Config::default();\n    let toml = toml::to_string_pretty(&config)?;\n    fs::write(dir.join("config.toml"), toml)?;\n    println!("Initialized in {}", dir.display());\n    Ok(())\n}`,
      },
      {
        name: "run.rs",
        path: "src/commands/run.rs",
        tokens: 3400,
        language: "rust",
        depth: 2,
        isDir: false,
        content: `use crate::config::Config;\nuse std::process::Command;\n\npub fn run(verbose: bool) -> anyhow::Result<()> {\n    let config = Config::load()?;\n    for task in &config.tasks {\n        if verbose {\n            eprintln!("Running: {}", task.name);\n        }\n        let status = Command::new(&task.command)\n            .args(&task.args)\n            .status()?;\n        if !status.success() {\n            anyhow::bail!("Task '{}' failed", task.name);\n        }\n    }\n    Ok(())\n}`,
      },
      {
        name: "config.rs",
        path: "src/config.rs",
        tokens: 1800,
        language: "rust",
        depth: 1,
        isDir: false,
        content: `use serde::{Deserialize, Serialize};\n\n#[derive(Debug, Serialize, Deserialize)]\npub struct Config {\n    pub name: String,\n    pub tasks: Vec<Task>,\n}\n\n#[derive(Debug, Serialize, Deserialize)]\npub struct Task {\n    pub name: String,\n    pub command: String,\n    pub args: Vec<String>,\n}\n\nimpl Config {\n    pub fn load() -> anyhow::Result<Self> {\n        let text = std::fs::read_to_string("config.toml")?;\n        Ok(toml::from_str(&text)?)\n    }\n}`,
      },
      {
        name: "Cargo.toml",
        path: "Cargo.toml",
        tokens: 520,
        language: "toml",
        depth: 0,
        isDir: false,
        content: `[package]\nname = "mytool"\nversion = "0.1.0"\nedition = "2021"\n\n[dependencies]\nclap = { version = "4", features = ["derive"] }\nanyhow = "1"\ntoml = "0.8"\nserde = { version = "1", features = ["derive"] }`,
      },
    ],
  },
  {
    id: "python-ml",
    label: "Python ML",
    icon: FlaskConical,
    color: "text-yellow-400",
    contextLimit: 128000,
    globFilter: "**/*.py",
    description: "ML training pipeline with data loaders",
    files: [
      { name: "src/", path: "src/", tokens: 0, language: "", content: "", depth: 0, isDir: true },
      {
        name: "train.py",
        path: "src/train.py",
        tokens: 4200,
        language: "python",
        depth: 1,
        isDir: false,
        content: `import torch\nfrom torch.utils.data import DataLoader\nfrom model import TransformerModel\nfrom data import TextDataset\nfrom config import TrainConfig\n\ndef train(cfg: TrainConfig):\n    dataset = TextDataset(cfg.data_path, cfg.seq_len)\n    loader = DataLoader(dataset, batch_size=cfg.batch_size, shuffle=True)\n    model = TransformerModel(cfg).cuda()\n    optimizer = torch.optim.AdamW(model.parameters(), lr=cfg.lr)\n\n    for epoch in range(cfg.epochs):\n        for batch in loader:\n            loss = model(batch.cuda()).loss\n            loss.backward()\n            optimizer.step()\n            optimizer.zero_grad()\n        print(f"Epoch {epoch}: loss={loss.item():.4f}")`,
      },
      {
        name: "model.py",
        path: "src/model.py",
        tokens: 5800,
        language: "python",
        depth: 1,
        isDir: false,
        content: `import torch\nimport torch.nn as nn\nimport math\n\nclass TransformerModel(nn.Module):\n    def __init__(self, cfg):\n        super().__init__()\n        self.embed = nn.Embedding(cfg.vocab_size, cfg.d_model)\n        self.pos = nn.Embedding(cfg.seq_len, cfg.d_model)\n        layer = nn.TransformerEncoderLayer(\n            d_model=cfg.d_model,\n            nhead=cfg.n_heads,\n            dim_feedforward=cfg.d_ff,\n            dropout=cfg.dropout,\n            batch_first=True,\n        )\n        self.transformer = nn.TransformerEncoder(layer, cfg.n_layers)\n        self.head = nn.Linear(cfg.d_model, cfg.vocab_size)\n\n    def forward(self, x):\n        pos = torch.arange(x.size(1), device=x.device)\n        h = self.embed(x) + self.pos(pos)\n        h = self.transformer(h)\n        return self.head(h)`,
      },
      {
        name: "data.py",
        path: "src/data.py",
        tokens: 2900,
        language: "python",
        depth: 1,
        isDir: false,
        content: `import torch\nfrom torch.utils.data import Dataset\nfrom pathlib import Path\n\nclass TextDataset(Dataset):\n    def __init__(self, path: str, seq_len: int):\n        text = Path(path).read_text()\n        self.tokens = [ord(c) for c in text]  # simple char encoding\n        self.seq_len = seq_len\n\n    def __len__(self):\n        return len(self.tokens) - self.seq_len\n\n    def __getitem__(self, idx):\n        chunk = self.tokens[idx:idx + self.seq_len + 1]\n        return torch.tensor(chunk[:-1]), torch.tensor(chunk[1:])`,
      },
      {
        name: "config.py",
        path: "src/config.py",
        tokens: 1100,
        language: "python",
        depth: 1,
        isDir: false,
        content: `from dataclasses import dataclass\n\n@dataclass\nclass TrainConfig:\n    data_path: str = "data/corpus.txt"\n    seq_len: int = 512\n    batch_size: int = 32\n    d_model: int = 256\n    n_heads: int = 8\n    n_layers: int = 6\n    d_ff: int = 1024\n    dropout: float = 0.1\n    vocab_size: int = 256\n    lr: float = 3e-4\n    epochs: int = 10`,
      },
      {
        name: "evaluate.py",
        path: "src/evaluate.py",
        tokens: 2100,
        language: "python",
        depth: 1,
        isDir: false,
        content: `import torch\nfrom model import TransformerModel\nfrom config import TrainConfig\n\ndef evaluate(checkpoint: str):\n    cfg = TrainConfig()\n    model = TransformerModel(cfg)\n    model.load_state_dict(torch.load(checkpoint))\n    model.eval()\n    # Run evaluation metrics\n    print("Model loaded, running eval...")`,
      },
      {
        name: "requirements.txt",
        path: "requirements.txt",
        tokens: 180,
        language: "txt",
        depth: 0,
        isDir: false,
        content: `torch>=2.2\nnumpy>=1.26\ntqdm>=4.66`,
      },
      {
        name: "pyproject.toml",
        path: "pyproject.toml",
        tokens: 340,
        language: "toml",
        depth: 0,
        isDir: false,
        content: `[project]\nname = "ml-pipeline"\nversion = "0.1.0"\nrequires-python = ">=3.11"\n\n[tool.ruff]\nline-length = 100`,
      },
    ],
  },
  {
    id: "monorepo",
    label: "Monorepo",
    icon: Layers,
    color: "text-violet-400",
    contextLimit: 200000,
    globFilter: "**/*.{ts,tsx}",
    description: "Turborepo monorepo with shared packages",
    files: [
      {
        name: "packages/",
        path: "packages/",
        tokens: 0,
        language: "",
        content: "",
        depth: 0,
        isDir: true,
      },
      {
        name: "ui/",
        path: "packages/ui/",
        tokens: 0,
        language: "",
        content: "",
        depth: 1,
        isDir: true,
      },
      {
        name: "Button.tsx",
        path: "packages/ui/Button.tsx",
        tokens: 1400,
        language: "tsx",
        depth: 2,
        isDir: false,
        content: `import { forwardRef } from 'react';\nimport { cn } from '@repo/utils';\n\nexport const Button = forwardRef<\n  HTMLButtonElement,\n  React.ButtonHTMLAttributes<HTMLButtonElement> & { variant?: 'primary' | 'ghost' }\n>(({ variant = 'primary', className, ...props }, ref) => (\n  <button ref={ref} className={cn('btn', variant, className)} {...props} />\n));`,
      },
      {
        name: "index.ts",
        path: "packages/ui/index.ts",
        tokens: 300,
        language: "ts",
        depth: 2,
        isDir: false,
        content: `export { Button } from './Button';\nexport { Input } from './Input';\nexport { Modal } from './Modal';`,
      },
      {
        name: "utils/",
        path: "packages/utils/",
        tokens: 0,
        language: "",
        content: "",
        depth: 1,
        isDir: true,
      },
      {
        name: "cn.ts",
        path: "packages/utils/cn.ts",
        tokens: 450,
        language: "ts",
        depth: 2,
        isDir: false,
        content: `import { clsx, type ClassValue } from 'clsx';\nimport { twMerge } from 'tailwind-merge';\n\nexport function cn(...inputs: ClassValue[]) {\n  return twMerge(clsx(inputs));\n}`,
      },
      { name: "apps/", path: "apps/", tokens: 0, language: "", content: "", depth: 0, isDir: true },
      {
        name: "web/",
        path: "apps/web/",
        tokens: 0,
        language: "",
        content: "",
        depth: 1,
        isDir: true,
      },
      {
        name: "page.tsx",
        path: "apps/web/page.tsx",
        tokens: 2200,
        language: "tsx",
        depth: 2,
        isDir: false,
        content: `import { Button } from '@repo/ui';\nimport { useQuery } from './hooks/useQuery';\n\nexport default function Home() {\n  const { data } = useQuery('/api/dashboard');\n  return (\n    <main>\n      <h1>Dashboard</h1>\n      <Button onClick={() => console.log('clicked')}>Action</Button>\n      <pre>{JSON.stringify(data, null, 2)}</pre>\n    </main>\n  );\n}`,
      },
      {
        name: "api/",
        path: "apps/api/",
        tokens: 0,
        language: "",
        content: "",
        depth: 1,
        isDir: true,
      },
      {
        name: "server.ts",
        path: "apps/api/server.ts",
        tokens: 3100,
        language: "ts",
        depth: 2,
        isDir: false,
        content: `import Fastify from 'fastify';\nimport { z } from 'zod';\n\nconst app = Fastify({ logger: true });\n\napp.get('/api/dashboard', async () => {\n  return { status: 'ok', uptime: process.uptime() };\n});\n\napp.listen({ port: 3001 });`,
      },
      {
        name: "turbo.json",
        path: "turbo.json",
        tokens: 380,
        language: "json",
        depth: 0,
        isDir: false,
        content: `{\n  "pipeline": {\n    "build": { "dependsOn": ["^build"] },\n    "dev": { "cache": false },\n    "lint": {}\n  }\n}`,
      },
    ],
  },
  {
    id: "api-server",
    label: "API Server",
    icon: Database,
    color: "text-emerald-400",
    contextLimit: 32000,
    globFilter: "**/*.ts",
    description: "Express + Prisma REST API with auth",
    files: [
      { name: "src/", path: "src/", tokens: 0, language: "", content: "", depth: 0, isDir: true },
      {
        name: "server.ts",
        path: "src/server.ts",
        tokens: 2400,
        language: "typescript",
        depth: 1,
        isDir: false,
        content: `import express from 'express';\nimport { authRouter } from './routes/auth';\nimport { apiRouter } from './routes/api';\nimport { errorHandler } from './middleware/error';\n\nconst app = express();\napp.use(express.json());\napp.use('/auth', authRouter);\napp.use('/api', apiRouter);\napp.use(errorHandler);\napp.listen(3000);`,
      },
      {
        name: "routes/",
        path: "src/routes/",
        tokens: 0,
        language: "",
        content: "",
        depth: 1,
        isDir: true,
      },
      {
        name: "auth.ts",
        path: "src/routes/auth.ts",
        tokens: 4800,
        language: "typescript",
        depth: 2,
        isDir: false,
        content: `import { Router } from 'express';\nimport { hash, verify } from '../lib/crypto';\nimport { signToken, verifyToken } from '../lib/jwt';\nimport { db } from '../db';\n\nexport const authRouter = Router();\nauthRouter.post('/login', async (req, res) => {\n  const user = await db.users.findByEmail(req.body.email);\n  if (!user || !await verify(req.body.password, user.hash))\n    return res.status(401).json({ error: 'Invalid' });\n  const token = signToken({ sub: user.id, role: user.role });\n  res.json({ token });\n});`,
      },
      {
        name: "api.ts",
        path: "src/routes/api.ts",
        tokens: 3600,
        language: "typescript",
        depth: 2,
        isDir: false,
        content: `import { Router } from 'express';\nimport { requireAuth } from '../middleware/auth';\nimport { db } from '../db';\n\nexport const apiRouter = Router();\napiRouter.use(requireAuth);\n\napiRouter.get('/users', async (_, res) => {\n  const users = await db.users.list();\n  res.json(users);\n});\n\napiRouter.get('/users/:id', async (req, res) => {\n  const user = await db.users.findById(req.params.id);\n  res.json(user);\n});`,
      },
      { name: "db/", path: "src/db/", tokens: 0, language: "", content: "", depth: 1, isDir: true },
      {
        name: "index.ts",
        path: "src/db/index.ts",
        tokens: 3200,
        language: "typescript",
        depth: 2,
        isDir: false,
        content: `import { Pool } from 'pg';\n\nconst pool = new Pool({\n  connectionString: process.env.DATABASE_URL,\n  max: 20,\n  idleTimeoutMillis: 30000,\n});\n\nexport const db = {\n  query: (text: string, params?: unknown[]) =>\n    pool.query(text, params),\n  users: {\n    findByEmail: (email: string) =>\n      pool.query('SELECT * FROM users WHERE email = $1', [email])\n        .then(r => r.rows[0]),\n    list: () => pool.query('SELECT * FROM users').then(r => r.rows),\n  },\n};`,
      },
      {
        name: "schema.prisma",
        path: "prisma/schema.prisma",
        tokens: 1800,
        language: "prisma",
        depth: 0,
        isDir: false,
        content: `generator client {\n  provider = "prisma-client-js"\n}\n\ndatasource db {\n  provider = "postgresql"\n  url      = env("DATABASE_URL")\n}\n\nmodel User {\n  id        String   @id @default(uuid())\n  email     String   @unique\n  hash      String\n  role      String   @default("user")\n  createdAt DateTime @default(now())\n}`,
      },
      {
        name: "package.json",
        path: "package.json",
        tokens: 550,
        language: "json",
        depth: 0,
        isDir: false,
        content: `{\n  "name": "api-server",\n  "scripts": {\n    "dev": "tsx watch src/server.ts",\n    "build": "tsc"\n  },\n  "dependencies": {\n    "express": "^5.0.0",\n    "pg": "^8.12.0"\n  }\n}`,
      },
    ],
  },
];

// =============================================================================
// HELPER: Get language badge color
// =============================================================================
function getLangColor(lang: string): string {
  const map: Record<string, string> = {
    tsx: "text-cyan-400 bg-cyan-500/10",
    ts: "text-blue-400 bg-blue-500/10",
    typescript: "text-blue-400 bg-blue-500/10",
    go: "text-sky-400 bg-sky-500/10",
    rust: "text-orange-400 bg-orange-500/10",
    python: "text-yellow-400 bg-yellow-500/10",
    sql: "text-pink-400 bg-pink-500/10",
    prisma: "text-pink-400 bg-pink-500/10",
    json: "text-amber-400 bg-amber-500/10",
    yaml: "text-amber-400 bg-amber-500/10",
    toml: "text-amber-400 bg-amber-500/10",
    makefile: "text-gray-400 bg-gray-500/10",
    txt: "text-gray-400 bg-gray-500/10",
  };
  return map[lang] ?? "text-white/40 bg-white/5";
}

// =============================================================================
// HELPER: Check if a file matches a glob pattern (simplified frontend check)
// =============================================================================
function matchesGlob(filePath: string, glob: string): boolean {
  // Extract extensions from pattern like **/*.{ts,tsx} or **/*.go
  const extMatch = glob.match(/\*\.(?:\{([^}]+)\}|(\w+))$/);
  if (!extMatch) return true; // no ext filter means match all
  const extensions = extMatch[1]
    ? extMatch[1].split(",").map((e) => `.${e.trim()}`)
    : [`.${extMatch[2]}`];
  return extensions.some((ext) => filePath.endsWith(ext));
}

// =============================================================================
// INTERACTIVE SOURCE COMBINER - Bundling Laboratory
// =============================================================================

function InteractiveSourceCombiner() {
  const [activeProjectIdx, setActiveProjectIdx] = useState(0);
  const [selected, setSelected] = useState<Record<string, boolean>>({});
  const [expandedDirs, setExpandedDirs] = useState<Record<string, boolean>>({});
  const [filterActive, setFilterActive] = useState(false);
  const [flyingFiles, setFlyingFiles] = useState<string[]>([]);
  const [scanningFile, setScanningFile] = useState<string | null>(null);
  const [showTerminal, setShowTerminal] = useState(false);
  const flyTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const scanTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const project = PROJECT_TYPES[activeProjectIdx];
  const sourceFiles = project.files.filter((f) => !f.isDir);

  // Cleanup timers on unmount
  useEffect(() => {
    return () => {
      if (flyTimerRef.current) clearTimeout(flyTimerRef.current);
      if (scanTimerRef.current) clearTimeout(scanTimerRef.current);
    };
  }, []);

  // Reset selections when switching projects, then auto-expand dirs
  useEffect(() => {
    const timer = setTimeout(() => {
      setSelected({});
      setFilterActive(false);
      setFlyingFiles([]);
      setScanningFile(null);
      setShowTerminal(false);
      // Auto-expand all dirs for the new project
      const dirs: Record<string, boolean> = {};
      for (const f of project.files) {
        if (f.isDir) dirs[f.path] = true;
      }
      setExpandedDirs(dirs);
    }, 0);
    return () => clearTimeout(timer);
  }, [activeProjectIdx, project.files]);

  const visibleFiles = useMemo(() => {
    return project.files.filter((f) => {
      if (f.isDir) return true;
      if (filterActive && !matchesGlob(f.path, project.globFilter)) return false;
      return true;
    });
  }, [project.files, filterActive, project.globFilter]);

  const filteredOutCount = useMemo(() => {
    if (!filterActive) return 0;
    return sourceFiles.filter((f) => !matchesGlob(f.path, project.globFilter)).length;
  }, [sourceFiles, filterActive, project.globFilter]);

  const toggleFile = useCallback((path: string) => {
    setSelected((prev) => {
      const next = { ...prev };
      const wasSelected = !!next[path];
      next[path] = !wasSelected;

      if (!wasSelected) {
        // Animate scanning
        setScanningFile(path);
        if (scanTimerRef.current) clearTimeout(scanTimerRef.current);
        scanTimerRef.current = setTimeout(() => {
          setScanningFile(null);
          scanTimerRef.current = null;
        }, 400);

        // Animate flying
        setFlyingFiles((prev2) => [...prev2, path]);
        if (flyTimerRef.current) clearTimeout(flyTimerRef.current);
        flyTimerRef.current = setTimeout(() => {
          setFlyingFiles([]);
          flyTimerRef.current = null;
        }, 700);
      }

      return next;
    });
  }, []);

  const toggleDir = useCallback((path: string) => {
    setExpandedDirs((prev) => ({ ...prev, [path]: !prev[path] }));
  }, []);

  const selectAll = useCallback(() => {
    const next: Record<string, boolean> = {};
    for (const f of visibleFiles) {
      if (!f.isDir) next[f.path] = true;
    }
    setSelected(next);
  }, [visibleFiles]);

  const deselectAll = useCallback(() => {
    setSelected({});
  }, []);

  const selectedFiles = useMemo(
    () => sourceFiles.filter((f) => selected[f.path]),
    [sourceFiles, selected],
  );

  const totalTokens = useMemo(
    () => selectedFiles.reduce((sum, f) => sum + f.tokens, 0),
    [selectedFiles],
  );

  const usagePercent = useMemo(
    () => Math.min((totalTokens / project.contextLimit) * 100, 100),
    [totalTokens, project.contextLimit],
  );

  const barColor = useMemo(() => {
    if (usagePercent > 80) return "from-red-500 to-rose-500";
    if (usagePercent > 50) return "from-yellow-500 to-amber-500";
    return "from-emerald-500 to-green-500";
  }, [usagePercent]);

  const barTextColor = useMemo(() => {
    if (usagePercent > 80) return "text-red-400";
    if (usagePercent > 50) return "text-yellow-400";
    return "text-emerald-400";
  }, [usagePercent]);

  const combinedPreview = useMemo(() => {
    if (selectedFiles.length === 0) return "";
    return selectedFiles
      .map((f) => `// ── ${f.path} ${"─".repeat(Math.max(0, 40 - f.path.length))}\n${f.content}`)
      .join("\n\n");
  }, [selectedFiles]);

  const contextLabel = useMemo(() => {
    if (project.contextLimit >= 200000) return "200K";
    if (project.contextLimit >= 128000) return "128K";
    return "32K";
  }, [project.contextLimit]);

  // Per-file bar max (for comparison bars)
  const maxFileTokens = useMemo(() => {
    return Math.max(...sourceFiles.map((f) => f.tokens), 1);
  }, [sourceFiles]);

  return (
    <div className="relative rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
      {/* Decorative glows */}
      <div className="absolute top-0 left-1/4 w-48 h-48 bg-emerald-500/10 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-1/4 w-32 h-32 bg-primary/10 rounded-full blur-3xl pointer-events-none" />

      <div className="relative p-4 sm:p-6 space-y-5">
        {/* ─── Project Type Stepper ─── */}
        <div className="space-y-3">
          <div className="flex items-center gap-2 mb-2">
            <Package className="h-4 w-4 text-white/40" />
            <span className="text-sm font-medium text-white/60">Select Project Type</span>
          </div>

          <div className="flex flex-wrap gap-2">
            {PROJECT_TYPES.map((pt, idx) => {
              const Icon = pt.icon;
              const isActive = idx === activeProjectIdx;
              return (
                <motion.button
                  key={pt.id}
                  onClick={() => setActiveProjectIdx(idx)}
                  whileHover={{ scale: 1.04 }}
                  whileTap={{ scale: 0.97 }}
                  transition={{ type: "spring", stiffness: 200, damping: 25 }}
                  className={`flex items-center gap-2 px-3 py-2 rounded-xl text-sm font-medium border transition-colors duration-200 ${
                    isActive
                      ? "bg-white/[0.08] border-white/[0.2] text-white"
                      : "bg-white/[0.02] border-white/[0.06] text-white/40 hover:text-white/60 hover:border-white/[0.1]"
                  }`}
                >
                  <Icon className={`h-4 w-4 ${isActive ? pt.color : ""}`} />
                  <span>{pt.label}</span>
                </motion.button>
              );
            })}
          </div>

          {/* Project description */}
          <AnimatePresence mode="wait">
            <motion.p
              key={project.id}
              initial={{ opacity: 0, y: 6 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -6 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
              className="text-xs text-white/40 font-mono pl-1"
            >
              {project.description} &mdash; context: {contextLabel}
            </motion.p>
          </AnimatePresence>
        </div>

        {/* ─── Token Budget Gauge ─── */}
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Hash className="h-4 w-4 text-white/40" />
              <span className="text-sm font-medium text-white/60">Token Budget</span>
            </div>
            <div className="flex items-center gap-2 font-mono text-sm">
              <motion.span
                key={totalTokens}
                initial={{ opacity: 0, y: -8 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ type: "spring", stiffness: 200, damping: 25 }}
                className={barTextColor}
              >
                {totalTokens.toLocaleString()}
              </motion.span>
              <span className="text-white/30">/</span>
              <span className="text-white/40">{project.contextLimit.toLocaleString()}</span>
            </div>
          </div>

          {/* Segmented progress bar showing per-file contribution */}
          <div className="h-4 rounded-full bg-white/[0.06] overflow-hidden relative">
            <motion.div
              className={`h-full rounded-full bg-gradient-to-r ${barColor}`}
              initial={{ width: 0 }}
              animate={{ width: `${usagePercent}%` }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
            />
            {/* Segment markers for each file */}
            {selectedFiles.length > 1 && (
              <div className="absolute inset-0 flex">
                {selectedFiles.map((f, idx) => {
                  const pct = (f.tokens / project.contextLimit) * 100;
                  const cumulativeBefore = selectedFiles
                    .slice(0, idx)
                    .reduce((s, ff) => s + ff.tokens, 0);
                  const leftPct = (cumulativeBefore / project.contextLimit) * 100;
                  return (
                    <motion.div
                      key={f.path}
                      className="absolute top-0 bottom-0 border-r border-black/30"
                      initial={{ opacity: 0 }}
                      animate={{ opacity: 0.6 }}
                      style={{
                        left: `${leftPct + pct}%`,
                      }}
                    />
                  );
                })}
              </div>
            )}
          </div>

          <div className="flex items-center justify-between text-xs text-white/30 font-mono">
            <span>
              {selectedFiles.length} file{selectedFiles.length !== 1 ? "s" : ""} selected
            </span>
            <span>
              {usagePercent.toFixed(1)}% of {contextLabel} context
            </span>
          </div>
        </div>

        {/* ─── Filter & Action Bar ─── */}
        <div className="flex flex-wrap items-center gap-2">
          <motion.button
            onClick={() => setFilterActive((p) => !p)}
            whileHover={{ scale: 1.04 }}
            whileTap={{ scale: 0.97 }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
            className={`flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs font-mono border transition-colors duration-200 ${
              filterActive
                ? "bg-violet-500/15 border-violet-500/30 text-violet-300"
                : "bg-white/[0.03] border-white/[0.08] text-white/40 hover:text-white/60"
            }`}
          >
            <Filter className="h-3 w-3" />
            <span>{project.globFilter}</span>
            {filterActive ? <Eye className="h-3 w-3" /> : <EyeOff className="h-3 w-3" />}
          </motion.button>

          {filterActive && filteredOutCount > 0 && (
            <motion.span
              initial={{ opacity: 0, scale: 0.8 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
              className="text-xs text-white/30 font-mono"
            >
              {filteredOutCount} file{filteredOutCount !== 1 ? "s" : ""} filtered out
            </motion.span>
          )}

          <div className="flex-1" />

          <motion.button
            onClick={selectAll}
            whileHover={{ scale: 1.04 }}
            whileTap={{ scale: 0.97 }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
            className="px-3 py-1.5 rounded-lg text-xs font-mono border bg-white/[0.03] border-white/[0.08] text-white/40 hover:text-emerald-300 hover:border-emerald-500/30 transition-colors duration-200"
          >
            Select All
          </motion.button>
          <motion.button
            onClick={deselectAll}
            whileHover={{ scale: 1.04 }}
            whileTap={{ scale: 0.97 }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
            className="px-3 py-1.5 rounded-lg text-xs font-mono border bg-white/[0.03] border-white/[0.08] text-white/40 hover:text-red-300 hover:border-red-500/30 transition-colors duration-200"
          >
            Clear
          </motion.button>
          <motion.button
            onClick={() => setShowTerminal((p) => !p)}
            whileHover={{ scale: 1.04 }}
            whileTap={{ scale: 0.97 }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
            className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-mono border transition-colors duration-200 ${
              showTerminal
                ? "bg-emerald-500/10 border-emerald-500/20 text-emerald-300"
                : "bg-white/[0.03] border-white/[0.08] text-white/40 hover:text-white/60"
            }`}
          >
            <Terminal className="h-3 w-3" />
            s2p
          </motion.button>
        </div>

        {/* ─── Mini Terminal ─── */}
        <AnimatePresence>
          {showTerminal && (
            <motion.div
              initial={{ opacity: 0, height: 0 }}
              animate={{ opacity: 1, height: "auto" }}
              exit={{ opacity: 0, height: 0 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
              className="overflow-hidden"
            >
              <div className="rounded-xl border border-white/[0.08] bg-black/60 p-4 font-mono text-xs space-y-1.5">
                <div className="flex items-center gap-2 text-white/30 mb-2">
                  <div className="flex gap-1.5">
                    <div className="w-2.5 h-2.5 rounded-full bg-red-500/60" />
                    <div className="w-2.5 h-2.5 rounded-full bg-yellow-500/60" />
                    <div className="w-2.5 h-2.5 rounded-full bg-green-500/60" />
                  </div>
                  <span>~/{project.id}-project</span>
                </div>
                <div>
                  <span className="text-emerald-400">$</span>{" "}
                  <span className="text-white/80">s2p .</span>
                </div>
                <div className="text-white/40">Scanning {sourceFiles.length} files...</div>
                {selectedFiles.length > 0 && (
                  <>
                    <div className="text-white/40">
                      Selected: {selectedFiles.map((f) => f.name).join(", ")}
                    </div>
                    <div className="text-emerald-400">
                      Total: {totalTokens.toLocaleString()} tokens ({usagePercent.toFixed(1)}% of{" "}
                      {contextLabel})
                    </div>
                    <div>
                      <span className="text-emerald-400">$</span>{" "}
                      <span className="text-white/80">
                        s2p --include=&quot;{project.globFilter}&quot; --copy
                      </span>
                    </div>
                    <div className="text-yellow-400">
                      Copied {selectedFiles.length} files to clipboard!
                    </div>
                  </>
                )}
                {selectedFiles.length === 0 && (
                  <div className="text-white/30">Toggle files to see s2p output...</div>
                )}
              </div>
            </motion.div>
          )}
        </AnimatePresence>

        {/* ─── Two-Panel Layout ─── */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          {/* ─── Left Panel: File Tree ─── */}
          <div className="rounded-xl border border-white/[0.08] bg-black/40 overflow-hidden flex flex-col">
            <div className="flex items-center justify-between px-4 py-3 border-b border-white/[0.06]">
              <div className="flex items-center gap-2">
                <FolderOpen className="h-4 w-4 text-amber-400" />
                <span className="text-sm font-medium text-white/70">Source Files</span>
              </div>
              <span className="text-xs text-white/30 font-mono">
                {visibleFiles.filter((f) => !f.isDir).length} files
              </span>
            </div>

            <div className="p-2 space-y-0.5 max-h-[460px] overflow-y-auto">
              <AnimatePresence mode="popLayout">
                {visibleFiles.map((file) => {
                  if (file.isDir) {
                    const isExpanded = !!expandedDirs[file.path];
                    return (
                      <motion.button
                        key={file.path}
                        layout
                        initial={{ opacity: 0, x: -12 }}
                        animate={{ opacity: 1, x: 0 }}
                        exit={{ opacity: 0, x: -12 }}
                        transition={{ type: "spring", stiffness: 200, damping: 25 }}
                        onClick={() => toggleDir(file.path)}
                        className="w-full flex items-center gap-2 px-3 py-1.5 rounded-lg text-left hover:bg-white/[0.04] transition-colors duration-150"
                        style={{ paddingLeft: `${file.depth * 16 + 12}px` }}
                      >
                        <motion.div
                          animate={{ rotate: isExpanded ? 0 : -90 }}
                          transition={{ type: "spring", stiffness: 200, damping: 25 }}
                        >
                          <ChevronDown className="h-3 w-3 text-white/30" />
                        </motion.div>
                        <Folder className="h-3.5 w-3.5 text-amber-400/70" />
                        <span className="text-xs font-mono text-white/50">{file.name}</span>
                      </motion.button>
                    );
                  }

                  // Check if parent dir is expanded
                  const parentDir = file.path.substring(0, file.path.lastIndexOf("/") + 1);
                  const parentIsExpanded = !parentDir || expandedDirs[parentDir];
                  if (!parentIsExpanded) return null;

                  const isSelected = !!selected[file.path];
                  const isScanning = scanningFile === file.path;
                  const isFlying = flyingFiles.includes(file.path);

                  return (
                    <motion.button
                      key={file.path}
                      layout
                      initial={{ opacity: 0, x: -12 }}
                      animate={{ opacity: 1, x: 0 }}
                      exit={{ opacity: 0, x: -12 }}
                      transition={{ type: "spring", stiffness: 200, damping: 25 }}
                      onClick={() => toggleFile(file.path)}
                      className={`w-full flex items-center gap-2 px-3 py-2 rounded-lg text-left transition-colors duration-150 relative ${
                        isSelected
                          ? "bg-emerald-500/10 border border-emerald-500/20"
                          : "hover:bg-white/[0.04] border border-transparent"
                      } ${isScanning ? "ring-1 ring-cyan-400/40" : ""}`}
                      style={{ paddingLeft: `${file.depth * 16 + 12}px` }}
                    >
                      {/* Scanning highlight sweep */}
                      <AnimatePresence>
                        {isScanning && (
                          <motion.div
                            initial={{ left: 0, opacity: 0.5 }}
                            animate={{ left: "100%", opacity: 0 }}
                            exit={{ opacity: 0 }}
                            transition={{ duration: 0.4, ease: "easeOut" }}
                            className="absolute inset-y-0 w-12 bg-gradient-to-r from-cyan-400/20 to-transparent pointer-events-none rounded-lg"
                          />
                        )}
                      </AnimatePresence>

                      {/* Checkbox */}
                      <motion.div
                        animate={{
                          scale: isSelected ? [1, 1.2, 1] : 1,
                        }}
                        transition={{
                          type: "spring",
                          stiffness: 200,
                          damping: 25,
                        }}
                        className="shrink-0"
                      >
                        {isSelected ? (
                          <CheckSquare className="h-3.5 w-3.5 text-emerald-400" />
                        ) : (
                          <Square className="h-3.5 w-3.5 text-white/25" />
                        )}
                      </motion.div>

                      {/* File icon */}
                      <File className="h-3.5 w-3.5 text-white/30 shrink-0" />

                      {/* File info */}
                      <div className="flex-1 min-w-0 flex items-center gap-2">
                        <span
                          className={`text-xs font-mono truncate ${
                            isSelected ? "text-emerald-300" : "text-white/60"
                          }`}
                        >
                          {file.name}
                        </span>

                        {/* Language badge */}
                        {file.language && (
                          <span
                            className={`text-[10px] px-1.5 py-0.5 rounded font-mono shrink-0 ${getLangColor(file.language)}`}
                          >
                            {file.language}
                          </span>
                        )}
                      </div>

                      {/* Token count + mini bar */}
                      <div className="flex items-center gap-2 shrink-0">
                        <div className="w-16 h-1.5 rounded-full bg-white/[0.06] overflow-hidden hidden sm:block">
                          <motion.div
                            className={`h-full rounded-full ${
                              isSelected ? "bg-emerald-500/60" : "bg-white/[0.15]"
                            }`}
                            initial={{ width: 0 }}
                            animate={{
                              width: `${(file.tokens / maxFileTokens) * 100}%`,
                            }}
                            transition={{
                              type: "spring",
                              stiffness: 200,
                              damping: 25,
                            }}
                          />
                        </div>
                        <span className="text-[10px] text-white/30 font-mono w-10 text-right">
                          {file.tokens.toLocaleString()}t
                        </span>
                      </div>

                      {/* Flying file animation */}
                      <AnimatePresence>
                        {isFlying && (
                          <motion.div
                            initial={{ opacity: 1, x: 0, y: 0, scale: 1 }}
                            animate={{
                              opacity: 0,
                              x: 80,
                              y: -20,
                              scale: 0.6,
                            }}
                            exit={{ opacity: 0 }}
                            transition={{
                              type: "spring",
                              stiffness: 200,
                              damping: 25,
                            }}
                            className="absolute right-2 pointer-events-none"
                          >
                            <File className="h-4 w-4 text-emerald-400" />
                          </motion.div>
                        )}
                      </AnimatePresence>
                    </motion.button>
                  );
                })}
              </AnimatePresence>
            </div>
          </div>

          {/* ─── Right Panel: Combined Prompt Preview ─── */}
          <div className="rounded-xl border border-white/[0.08] bg-black/40 overflow-hidden flex flex-col">
            <div className="flex items-center justify-between px-4 py-3 border-b border-white/[0.06]">
              <div className="flex items-center gap-2">
                <Clipboard className="h-4 w-4 text-primary" />
                <span className="text-sm font-medium text-white/70">Combined Prompt</span>
              </div>
              {selectedFiles.length > 0 && (
                <motion.div
                  initial={{ opacity: 0, scale: 0.8 }}
                  animate={{ opacity: 1, scale: 1 }}
                  transition={{ type: "spring", stiffness: 200, damping: 25 }}
                  className="flex items-center gap-1.5 text-xs text-emerald-400 font-mono"
                >
                  <Check className="h-3 w-3" />
                  Ready
                </motion.div>
              )}
            </div>

            {/* Size comparison bars */}
            {selectedFiles.length > 0 && (
              <div className="px-4 py-3 border-b border-white/[0.06] space-y-1.5">
                <div className="text-[10px] font-mono text-white/30 uppercase tracking-wider mb-2">
                  Token Breakdown
                </div>
                {selectedFiles.map((f) => {
                  const pct = (f.tokens / project.contextLimit) * 100;
                  return (
                    <motion.div
                      key={f.path}
                      initial={{ opacity: 0, x: -10 }}
                      animate={{ opacity: 1, x: 0 }}
                      transition={{
                        type: "spring",
                        stiffness: 200,
                        damping: 25,
                      }}
                      className="flex items-center gap-2"
                    >
                      <span className="text-[10px] font-mono text-white/40 w-28 truncate shrink-0">
                        {f.name}
                      </span>
                      <div className="flex-1 h-2 rounded-full bg-white/[0.06] overflow-hidden">
                        <motion.div
                          className="h-full rounded-full bg-gradient-to-r from-emerald-500/60 to-cyan-500/60"
                          initial={{ width: 0 }}
                          animate={{ width: `${Math.max(pct * 3, 2)}%` }}
                          transition={{
                            type: "spring",
                            stiffness: 200,
                            damping: 25,
                          }}
                        />
                      </div>
                      <span className="text-[10px] font-mono text-white/30 w-12 text-right shrink-0">
                        {f.tokens.toLocaleString()}
                      </span>
                    </motion.div>
                  );
                })}
                {/* Total bar */}
                <div className="flex items-center gap-2 pt-1 border-t border-white/[0.04] mt-1">
                  <span className="text-[10px] font-mono text-emerald-400 w-28 shrink-0">
                    Total
                  </span>
                  <div className="flex-1 h-2 rounded-full bg-white/[0.06] overflow-hidden">
                    <motion.div
                      className={`h-full rounded-full bg-gradient-to-r ${barColor}`}
                      initial={{ width: 0 }}
                      animate={{
                        width: `${Math.max(usagePercent * 3, 2)}%`,
                      }}
                      transition={{
                        type: "spring",
                        stiffness: 200,
                        damping: 25,
                      }}
                    />
                  </div>
                  <span
                    className={`text-[10px] font-mono w-12 text-right shrink-0 ${barTextColor}`}
                  >
                    {totalTokens.toLocaleString()}
                  </span>
                </div>
              </div>
            )}

            {/* Prompt preview */}
            <div className="flex-1 p-3 min-h-[240px] max-h-[340px] overflow-auto">
              <AnimatePresence mode="wait">
                {selectedFiles.length === 0 ? (
                  <motion.div
                    key="empty"
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    exit={{ opacity: 0 }}
                    transition={{ type: "spring", stiffness: 200, damping: 25 }}
                    className="flex flex-col items-center justify-center h-full min-h-[220px] text-white/20"
                  >
                    <FileCode className="h-10 w-10 mb-3" />
                    <p className="text-sm">Select files to preview prompt</p>
                    <p className="text-xs mt-1 text-white/15">
                      Toggle files in the tree or use Select All
                    </p>
                  </motion.div>
                ) : (
                  <motion.pre
                    key={`preview-${selectedFiles.map((f) => f.path).join(",")}`}
                    initial={{ opacity: 0, y: 8 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0, y: -8 }}
                    transition={{ type: "spring", stiffness: 200, damping: 25 }}
                    className="font-mono text-[11px] text-white/60 whitespace-pre-wrap leading-relaxed break-all"
                  >
                    {combinedPreview}
                  </motion.pre>
                )}
              </AnimatePresence>
            </div>
          </div>
        </div>

        {/* ─── Tip ─── */}
        <TipBox variant="tip">
          In the real S2P TUI, press <strong>Space</strong> to toggle files, <strong>Enter</strong>{" "}
          to expand directories, and <strong>c</strong> to copy the combined prompt to your
          clipboard. Use <strong>--include</strong> for glob filtering.
        </TipBox>
      </div>
    </div>
  );
}
