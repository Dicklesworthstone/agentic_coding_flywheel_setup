"use client";

import { useState, useCallback, useMemo } from "react";
import { motion, AnimatePresence } from "@/components/motion";
import {
  GitBranch,
  GitCommit,
  GitMerge,
  History,
  Terminal,
  AlertTriangle,
  Shield,
  FileX,
  Undo2,
  Eye,
  CheckCircle,
  RotateCcw,
  ChevronRight,
  Play,
  X,
  Circle,
  Plus,
  Minus,
  Edit3,
  User,
} from "lucide-react";
import {
  Section,
  Paragraph,
  CodeBlock,
  TipBox,
  Highlight,
  Divider,
  GoalBanner,
  CommandList,
  FeatureCard,
  FeatureGrid,
  InlineCode,
} from "./lesson-components";

export function GitBasicsLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Master git basics and recognize dangerous operations before they happen.
      </GoalBanner>

      {/* What Is Git */}
      <Section
        title="What Is Git?"
        icon={<GitBranch className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph>
          <Highlight>Git</Highlight> is a version control system that tracks
          changes to your code over time. Think of it like a detailed history
          of every change you&apos;ve ever made, with the ability to go back to
          any point.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<History className="h-5 w-5" />}
              title="Full History"
              description="Every change is recorded and reversible"
              gradient="from-primary/20 to-violet-500/20"
            />
            <FeatureCard
              icon={<GitBranch className="h-5 w-5" />}
              title="Branching"
              description="Work on features without affecting main code"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<GitMerge className="h-5 w-5" />}
              title="Collaboration"
              description="Multiple people can work on the same project"
              gradient="from-amber-500/20 to-orange-500/20"
            />
            <FeatureCard
              icon={<Shield className="h-5 w-5" />}
              title="Safety Net"
              description="Recover from mistakes (if you know how)"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Core Concepts */}
      <Section
        title="Core Concepts"
        icon={<GitCommit className="h-5 w-5" />}
        delay={0.15}
      >
        <div className="space-y-6">
          <ConceptCard
            term="Repository"
            definition="A project folder tracked by git (contains a .git directory)"
            example="git init creates a new repository"
          />
          <ConceptCard
            term="Commit"
            definition="A snapshot of your code at a point in time"
            example="Like saving a checkpoint in a game"
          />
          <ConceptCard
            term="Staging Area"
            definition="Where you prepare changes before committing"
            example="git add puts files in staging"
          />
          <ConceptCard
            term="Branch"
            definition="An independent line of development"
            example="main, feature/login, bugfix/auth"
          />
          <ConceptCard
            term="Remote"
            definition="A copy of your repository on a server (like GitHub)"
            example="origin is the default remote name"
          />
        </div>

        <div className="mt-8">
          <h3 className="text-lg font-semibold text-white mb-4">
            Try It: Interactive Staging Area
          </h3>
          <InteractiveGitFlow />
        </div>
      </Section>

      <Divider />

      {/* Essential Commands */}
      <Section
        title="Essential Commands"
        icon={<Terminal className="h-5 w-5" />}
        delay={0.2}
      >
        <CommandList
          commands={[
            {
              command: "git status",
              description: "See what's changed (run this often!)",
            },
            {
              command: "git add <file>",
              description: "Stage a file for commit",
            },
            {
              command: "git add .",
              description: "Stage all changes",
            },
            {
              command: 'git commit -m "message"',
              description: "Create a commit with a message",
            },
            {
              command: "git push",
              description: "Upload commits to remote",
            },
            {
              command: "git pull",
              description: "Download and merge remote changes",
            },
            {
              command: "git log --oneline",
              description: "View commit history",
            },
            {
              command: "git diff",
              description: "See uncommitted changes",
            },
          ]}
        />
      </Section>

      <Divider />

      {/* .gitignore */}
      <Section
        title="Understanding .gitignore"
        icon={<FileX className="h-5 w-5" />}
        delay={0.25}
      >
        <Paragraph>
          The <InlineCode>.gitignore</InlineCode> file tells git which files to
          ignore. This is <strong>critical for security</strong> because you
          never want to commit:
        </Paragraph>

        <div className="mt-6 space-y-3">
          <IgnoreItem
            pattern=".env"
            reason="Contains API keys and secrets"
            critical
          />
          <IgnoreItem
            pattern="node_modules/"
            reason="Dependencies (huge, regeneratable)"
          />
          <IgnoreItem
            pattern=".venv/"
            reason="Python virtual environments"
          />
          <IgnoreItem
            pattern="*.log"
            reason="Log files with potentially sensitive data"
          />
          <IgnoreItem
            pattern="credentials.json"
            reason="Service account keys"
            critical
          />
          <IgnoreItem
            pattern=".claude/"
            reason="Claude Code session data"
          />
        </div>

        <div className="mt-6">
          <TipBox variant="warning">
            <strong>Never commit secrets!</strong> If you accidentally commit an
            API key, consider it compromised. Rotate it immediately.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Branches */}
      <Section
        title="Working with Branches"
        icon={<GitBranch className="h-5 w-5" />}
        delay={0.3}
      >
        <CommandList
          commands={[
            {
              command: "git branch",
              description: "List all local branches",
            },
            {
              command: "git branch <name>",
              description: "Create a new branch",
            },
            {
              command: "git checkout <branch>",
              description: "Switch to a branch",
            },
            {
              command: "git checkout -b <name>",
              description: "Create and switch in one command",
            },
            {
              command: "git merge <branch>",
              description: "Merge branch into current branch",
            },
            {
              command: "git branch -d <name>",
              description: "Delete a merged branch",
            },
          ]}
        />

        <div className="mt-6">
          <TipBox variant="tip">
            Always create a new branch for features or experiments. Keep{" "}
            <InlineCode>main</InlineCode> stable.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* DANGEROUS OPERATIONS - THE CRITICAL SECTION */}
      <Section
        title="Dangerous Operations"
        icon={<AlertTriangle className="h-5 w-5" />}
        delay={0.35}
      >
        <Paragraph>
          <strong className="text-red-400">
            AI agents may propose these commands.
          </strong>{" "}
          Know what they do before approving them:
        </Paragraph>

        <div className="mt-6 space-y-4">
          <DangerousCommand
            command="git reset --hard"
            effect="Destroys all uncommitted changes permanently"
            alternative="git stash (saves changes for later)"
          />
          <DangerousCommand
            command="git clean -fd"
            effect="Deletes all untracked files permanently"
            alternative="Review with git clean -n first (dry run)"
          />
          <DangerousCommand
            command="git push --force"
            effect="Overwrites remote history, can delete teammates' work"
            alternative="git push --force-with-lease (safer)"
          />
          <DangerousCommand
            command="git checkout ."
            effect="Discards all uncommitted changes to tracked files"
            alternative="git stash or commit first"
          />
          <DangerousCommand
            command="git rebase main"
            effect="Rewrites commit history (can cause conflicts)"
            alternative="Only rebase unpushed commits"
          />
          <DangerousCommand
            command="rm -rf .git"
            effect="Destroys entire repository history forever"
            alternative="There is no alternative. Never do this."
          />
        </div>

        <div className="mt-8">
          <TipBox variant="warning">
            <strong>Before approving any git command from an agent:</strong>
            <br />
            1. Run <InlineCode>git status</InlineCode> to see current state
            <br />
            2. Run <InlineCode>git stash</InlineCode> to save uncommitted work
            <br />
            3. Only then proceed with destructive commands
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Recovery Tools */}
      <Section
        title="Recovery Tools"
        icon={<Undo2 className="h-5 w-5" />}
        delay={0.4}
      >
        <Paragraph>
          When things go wrong, these commands can help:
        </Paragraph>

        <CommandList
          commands={[
            {
              command: "git stash",
              description: "Temporarily save uncommitted changes",
            },
            {
              command: "git stash pop",
              description: "Restore stashed changes",
            },
            {
              command: "git reflog",
              description: "View history of HEAD (find lost commits)",
            },
            {
              command: "git reset --soft HEAD~1",
              description: "Undo last commit, keep changes staged",
            },
            {
              command: "git checkout <file>",
              description: "Discard changes to a specific file",
            },
            {
              command: "git revert <commit>",
              description: "Create new commit that undoes a previous one",
            },
          ]}
        />

        <div className="mt-6">
          <CodeBlock
            code={`# Lost a commit after reset --hard? Find it!
$ git reflog
# Look for your commit hash, then:
$ git checkout <hash>
# Or create a branch at that commit:
$ git branch recovery <hash>`}
            language="bash"
          />
        </div>
      </Section>

      <Divider />

      {/* Best Practices */}
      <Section
        title="Best Practices with Agents"
        icon={<Shield className="h-5 w-5" />}
        delay={0.45}
      >
        <div className="space-y-4">
          <BestPractice
            title="Commit early and often"
            description="Small commits are easier to revert. Agents work better with clear history."
          />
          <BestPractice
            title="Always run git status before destructive commands"
            description="Know what you're about to lose before you lose it."
          />
          <BestPractice
            title="Use git stash as your safety net"
            description="Stash uncommitted work before letting agents run risky operations."
          />
          <BestPractice
            title="Review agent-proposed git commands"
            description="Agents may suggest --force or reset --hard. Always understand before approving."
          />
          <BestPractice
            title="Push your work frequently"
            description="Remote backups protect against local disasters."
          />
        </div>
      </Section>

      <Divider />

      {/* Try It Now */}
      <Section
        title="Try It Now"
        icon={<Eye className="h-5 w-5" />}
        delay={0.5}
      >
        <CodeBlock
          code={`# Check your repository status
$ git status

# View recent commits
$ git log --oneline -5

# See what's in your .gitignore
$ cat .gitignore

# Practice stashing (safe to try!)
$ echo "test" > temp.txt
$ git stash
$ git stash pop
$ rm temp.txt`}
          showLineNumbers
        />
      </Section>
    </div>
  );
}

// =============================================================================
// INTERACTIVE GIT FLOW V2 - Visual Branch Graph + Staging Area
// =============================================================================

const SPRING = { type: "spring" as const, stiffness: 200, damping: 25 };
const SPRING_SNAPPY = { type: "spring" as const, stiffness: 400, damping: 30 };

interface GitGraphCommit {
  id: string;
  hash: string;
  message: string;
  branch: "main" | "feature";
  author: string;
  filesChanged: { name: string; status: "added" | "modified" | "deleted" }[];
  isMerge?: boolean;
  parentIds: string[];
}

interface StagingFile {
  id: string;
  name: string;
  status: "added" | "modified" | "deleted";
  zone: "working" | "staging" | "committed";
}

type FlowStep = 0 | 1 | 2 | 3 | 4 | 5;

const STEP_LABELS: Record<FlowStep, string> = {
  0: "Start: main branch with initial commits",
  1: "Create feature branch (git checkout -b feature/auth)",
  2: "Make commits on feature branch",
  3: "Meanwhile, a commit lands on main",
  4: "Merge feature back into main",
  5: "Clean merged history",
};

const DANGER_COMMANDS = [
  { cmd: "git push --force", desc: "Overwrites remote history" },
  { cmd: "git reset --hard", desc: "Destroys uncommitted changes" },
];

function buildCommitsForStep(step: FlowStep): GitGraphCommit[] {
  const base: GitGraphCommit[] = [
    {
      id: "c1",
      hash: "a1b2c3d",
      message: "Initial commit",
      branch: "main",
      author: "dev",
      filesChanged: [
        { name: "package.json", status: "added" },
        { name: "README.md", status: "added" },
      ],
      parentIds: [],
    },
    {
      id: "c2",
      hash: "e4f5g6h",
      message: "Add project structure",
      branch: "main",
      author: "dev",
      filesChanged: [
        { name: "src/index.ts", status: "added" },
        { name: "tsconfig.json", status: "added" },
      ],
      parentIds: ["c1"],
    },
  ];

  if (step < 2) return base;

  const featureCommits: GitGraphCommit[] = [
    {
      id: "f1",
      hash: "i7j8k9l",
      message: "Add auth module",
      branch: "feature",
      author: "dev",
      filesChanged: [
        { name: "src/auth.ts", status: "added" },
        { name: "src/types.ts", status: "added" },
      ],
      parentIds: ["c2"],
    },
    {
      id: "f2",
      hash: "m0n1o2p",
      message: "Add login endpoint",
      branch: "feature",
      author: "dev",
      filesChanged: [
        { name: "src/routes/login.ts", status: "added" },
        { name: "src/auth.ts", status: "modified" },
      ],
      parentIds: ["f1"],
    },
    {
      id: "f3",
      hash: "q3r4s5t",
      message: "Add auth tests",
      branch: "feature",
      author: "dev",
      filesChanged: [
        { name: "tests/auth.test.ts", status: "added" },
        { name: "package.json", status: "modified" },
      ],
      parentIds: ["f2"],
    },
  ];

  const result = [...base, ...featureCommits];

  if (step >= 3) {
    result.push({
      id: "c3",
      hash: "u6v7w8x",
      message: "Fix README typo",
      branch: "main",
      author: "teammate",
      filesChanged: [{ name: "README.md", status: "modified" }],
      parentIds: ["c2"],
    });
  }

  if (step >= 4) {
    result.push({
      id: "m1",
      hash: "y9z0a1b",
      message: "Merge feature/auth into main",
      branch: "main",
      author: "dev",
      filesChanged: [
        { name: "src/auth.ts", status: "added" },
        { name: "src/routes/login.ts", status: "added" },
        { name: "tests/auth.test.ts", status: "added" },
      ],
      isMerge: true,
      parentIds: ["c3", "f3"],
    });
  }

  return result;
}

function buildStagingFilesForStep(step: FlowStep): StagingFile[] {
  if (step === 0) {
    return [
      { id: "s1", name: "src/auth.ts", status: "added", zone: "working" },
      { id: "s2", name: "src/types.ts", status: "added", zone: "working" },
      { id: "s3", name: ".env.local", status: "added", zone: "working" },
    ];
  }
  if (step === 1) {
    return [
      { id: "s1", name: "src/auth.ts", status: "added", zone: "working" },
      { id: "s2", name: "src/types.ts", status: "added", zone: "working" },
      { id: "s3", name: ".env.local", status: "added", zone: "working" },
    ];
  }
  if (step === 2) {
    return [
      { id: "s1", name: "src/auth.ts", status: "added", zone: "staging" },
      { id: "s2", name: "src/types.ts", status: "added", zone: "staging" },
      { id: "s3", name: ".env.local", status: "added", zone: "working" },
    ];
  }
  if (step === 3) {
    return [
      { id: "s1", name: "src/auth.ts", status: "added", zone: "committed" },
      { id: "s2", name: "src/types.ts", status: "added", zone: "committed" },
      { id: "s4", name: "src/routes/login.ts", status: "modified", zone: "staging" },
      { id: "s3", name: ".env.local", status: "added", zone: "working" },
    ];
  }
  if (step === 4) {
    return [
      { id: "s1", name: "src/auth.ts", status: "added", zone: "committed" },
      { id: "s2", name: "src/types.ts", status: "added", zone: "committed" },
      { id: "s4", name: "src/routes/login.ts", status: "modified", zone: "committed" },
      { id: "s5", name: "tests/auth.test.ts", status: "added", zone: "committed" },
    ];
  }
  return [
    { id: "s1", name: "src/auth.ts", status: "added", zone: "committed" },
    { id: "s2", name: "src/types.ts", status: "added", zone: "committed" },
    { id: "s4", name: "src/routes/login.ts", status: "modified", zone: "committed" },
    { id: "s5", name: "tests/auth.test.ts", status: "added", zone: "committed" },
    { id: "s6", name: "package.json", status: "modified", zone: "committed" },
  ];
}

function InteractiveGitFlow() {
  const [currentStep, setCurrentStep] = useState<FlowStep>(0);
  const [selectedCommit, setSelectedCommit] = useState<string | null>(null);
  const [showDangerOverlay, setShowDangerOverlay] = useState(false);

  const commits = useMemo(() => buildCommitsForStep(currentStep), [currentStep]);
  const stagingFiles = useMemo(
    () => buildStagingFilesForStep(currentStep),
    [currentStep]
  );
  const headCommitId = useMemo(() => {
    if (currentStep >= 4) return "m1";
    if (currentStep >= 3) return "c3";
    if (currentStep >= 2) return "f3";
    return "c2";
  }, [currentStep]);

  const selectedCommitData = useMemo(
    () => commits.find((c) => c.id === selectedCommit) ?? null,
    [commits, selectedCommit]
  );

  const advanceStep = useCallback(() => {
    setCurrentStep((prev) => (prev < 5 ? ((prev + 1) as FlowStep) : prev));
    setSelectedCommit(null);
  }, []);

  const goBack = useCallback(() => {
    setCurrentStep((prev) => (prev > 0 ? ((prev - 1) as FlowStep) : prev));
    setSelectedCommit(null);
  }, []);

  const resetFlow = useCallback(() => {
    setCurrentStep(0);
    setSelectedCommit(null);
    setShowDangerOverlay(false);
  }, []);

  // Separate commits by branch for graph layout
  const mainCommits = commits.filter((c) => c.branch === "main");
  const featureCommits = commits.filter((c) => c.branch === "feature");
  const showFeatureBranch = currentStep >= 1;

  return (
    <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between border-b border-white/[0.06] px-5 py-3">
        <div className="flex items-center gap-2">
          <GitBranch className="h-4 w-4 text-primary" />
          <span className="text-sm font-semibold text-white">
            Interactive Git Graph
          </span>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setShowDangerOverlay(true)}
            className="flex items-center gap-1.5 rounded-lg border border-red-500/30 bg-red-500/10 px-2.5 py-1 text-[11px] font-mono text-red-400 transition hover:bg-red-500/20 hover:border-red-500/50"
          >
            <AlertTriangle className="h-3 w-3" />
            Danger Ops
          </button>
          <button
            onClick={resetFlow}
            className="flex items-center gap-1.5 rounded-lg border border-white/[0.1] bg-white/[0.04] px-2.5 py-1 text-[11px] text-white/50 transition hover:bg-white/[0.08] hover:text-white/70"
          >
            <RotateCcw className="h-3 w-3" />
            Reset
          </button>
        </div>
      </div>

      {/* Main content: Graph + Staging area */}
      <div className="grid grid-cols-1 lg:grid-cols-[1fr_280px] divide-y lg:divide-y-0 lg:divide-x divide-white/[0.06]">
        {/* Left: Git Graph */}
        <div className="p-5 min-h-[340px]">
          {/* Branch labels */}
          <div className="flex items-center gap-4 mb-5">
            <div className="flex items-center gap-2">
              <div className="h-2.5 w-2.5 rounded-full bg-blue-400" />
              <span className="text-xs font-mono text-blue-400">main</span>
            </div>
            <AnimatePresence>
              {showFeatureBranch && (
                <motion.div
                  initial={{ opacity: 0, x: -10 }}
                  animate={{ opacity: 1, x: 0 }}
                  exit={{ opacity: 0, x: -10 }}
                  transition={SPRING}
                  className="flex items-center gap-2"
                >
                  <div className="h-2.5 w-2.5 rounded-full bg-purple-400" />
                  <span className="text-xs font-mono text-purple-400">
                    feature/auth
                  </span>
                </motion.div>
              )}
            </AnimatePresence>
            <motion.div
              className="flex items-center gap-1.5 ml-auto"
              initial={false}
              animate={{ opacity: 1 }}
            >
              <span className="text-[10px] text-white/40 uppercase tracking-wider">
                HEAD
              </span>
              <motion.div
                layout
                transition={SPRING}
                className="h-2 w-2 rounded-full bg-amber-400 shadow-lg shadow-amber-400/40"
              />
            </motion.div>
          </div>

          {/* Graph visualization */}
          <div className="relative">
            {/* Main branch lane */}
            <div className="relative mb-4">
              <div className="flex items-center gap-3 flex-wrap">
                {mainCommits.map((commit, idx) => (
                  <div key={commit.id} className="flex items-center gap-3">
                    {idx > 0 && (
                      <div className="h-[2px] w-6 bg-blue-400/40" />
                    )}
                    <CommitNode
                      commit={commit}
                      isHead={headCommitId === commit.id}
                      isSelected={selectedCommit === commit.id}
                      onClick={() =>
                        setSelectedCommit(
                          selectedCommit === commit.id ? null : commit.id
                        )
                      }
                      color="blue"
                    />
                  </div>
                ))}
              </div>
            </div>

            {/* Feature branch lane */}
            <AnimatePresence>
              {showFeatureBranch && featureCommits.length > 0 && (
                <motion.div
                  initial={{ opacity: 0, y: -10 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: -10 }}
                  transition={SPRING}
                  className="relative ml-12 mb-4"
                >
                  {/* Fork connector */}
                  <div className="absolute -top-4 left-3 h-4 w-[2px] bg-purple-400/40" />

                  <div className="flex items-center gap-3 flex-wrap">
                    {featureCommits.map((commit, idx) => (
                      <div
                        key={commit.id}
                        className="flex items-center gap-3"
                      >
                        {idx > 0 && (
                          <div className="h-[2px] w-6 bg-purple-400/40" />
                        )}
                        <CommitNode
                          commit={commit}
                          isHead={headCommitId === commit.id}
                          isSelected={selectedCommit === commit.id}
                          onClick={() =>
                            setSelectedCommit(
                              selectedCommit === commit.id ? null : commit.id
                            )
                          }
                          color="purple"
                        />
                      </div>
                    ))}
                  </div>

                  {/* Merge connector */}
                  {currentStep >= 4 && (
                    <motion.div
                      initial={{ opacity: 0 }}
                      animate={{ opacity: 1 }}
                      transition={{ delay: 0.3, ...SPRING }}
                      className="absolute -bottom-4 right-0 h-4 w-[2px] bg-purple-400/40"
                    />
                  )}
                </motion.div>
              )}
            </AnimatePresence>

            {/* Commit detail panel */}
            <AnimatePresence>
              {selectedCommitData && (
                <motion.div
                  initial={{ opacity: 0, y: 8, scale: 0.96 }}
                  animate={{ opacity: 1, y: 0, scale: 1 }}
                  exit={{ opacity: 0, y: 8, scale: 0.96 }}
                  transition={SPRING}
                  className="mt-5 rounded-xl border border-white/[0.08] bg-white/[0.03] p-4 backdrop-blur-xl"
                >
                  <div className="flex items-center justify-between mb-3">
                    <div className="flex items-center gap-2">
                      <code className="rounded bg-white/[0.06] px-2 py-0.5 text-xs font-mono text-amber-300">
                        {selectedCommitData.hash}
                      </code>
                      {selectedCommitData.isMerge && (
                        <span className="rounded bg-purple-500/20 px-1.5 py-0.5 text-[10px] font-semibold text-purple-300 uppercase">
                          Merge
                        </span>
                      )}
                    </div>
                    <button
                      onClick={() => setSelectedCommit(null)}
                      className="rounded-lg p-1 text-white/40 hover:text-white/70 hover:bg-white/[0.06] transition"
                    >
                      <X className="h-3.5 w-3.5" />
                    </button>
                  </div>
                  <p className="text-sm text-white/80 mb-2">
                    {selectedCommitData.message}
                  </p>
                  <div className="flex items-center gap-2 mb-3 text-xs text-white/40">
                    <User className="h-3 w-3" />
                    <span>{selectedCommitData.author}</span>
                  </div>
                  <div className="space-y-1">
                    {selectedCommitData.filesChanged.map((f) => (
                      <div
                        key={f.name}
                        className="flex items-center gap-2 text-xs"
                      >
                        <FileStatusIcon status={f.status} />
                        <span className="font-mono text-white/60">
                          {f.name}
                        </span>
                      </div>
                    ))}
                  </div>
                </motion.div>
              )}
            </AnimatePresence>
          </div>
        </div>

        {/* Right: Staging Area Panel */}
        <div className="p-4">
          <h4 className="text-xs font-semibold text-white/70 uppercase tracking-wider mb-4">
            Staging Area
          </h4>

          {/* Three zones */}
          <StagingZone
            title="Working Dir"
            color="red"
            files={stagingFiles.filter((f) => f.zone === "working")}
          />
          <div className="flex items-center justify-center py-1.5">
            <ChevronRight className="h-3 w-3 text-white/20" />
            <span className="text-[10px] text-white/20 mx-1">git add</span>
            <ChevronRight className="h-3 w-3 text-white/20" />
          </div>
          <StagingZone
            title="Staged"
            color="amber"
            files={stagingFiles.filter((f) => f.zone === "staging")}
          />
          <div className="flex items-center justify-center py-1.5">
            <ChevronRight className="h-3 w-3 text-white/20" />
            <span className="text-[10px] text-white/20 mx-1">commit</span>
            <ChevronRight className="h-3 w-3 text-white/20" />
          </div>
          <StagingZone
            title="Committed"
            color="emerald"
            files={stagingFiles.filter((f) => f.zone === "committed")}
          />
        </div>
      </div>

      {/* Step controls */}
      <div className="border-t border-white/[0.06] px-5 py-3">
        <div className="flex items-center justify-between mb-3">
          <p className="text-xs text-white/50 font-mono">
            <span className="text-primary font-semibold">
              Step {currentStep + 1}/6:
            </span>{" "}
            {STEP_LABELS[currentStep]}
          </p>
        </div>

        {/* Step progress */}
        <div className="flex items-center gap-1.5 mb-3">
          {([0, 1, 2, 3, 4, 5] as FlowStep[]).map((s) => (
            <motion.div
              key={s}
              className={`h-1.5 flex-1 rounded-full transition-colors duration-300 ${
                s <= currentStep
                  ? "bg-primary"
                  : "bg-white/[0.06]"
              }`}
              initial={false}
              animate={{
                scale: s === currentStep ? 1 : 1,
                opacity: s <= currentStep ? 1 : 0.4,
              }}
              transition={SPRING}
            />
          ))}
        </div>

        {/* Navigation buttons */}
        <div className="flex items-center gap-2">
          <button
            onClick={goBack}
            disabled={currentStep === 0}
            className="flex items-center gap-1.5 rounded-lg border border-white/[0.1] bg-white/[0.04] px-3 py-1.5 text-xs text-white/60 transition hover:bg-white/[0.08] hover:text-white/80 disabled:opacity-30 disabled:cursor-not-allowed"
          >
            <RotateCcw className="h-3 w-3" />
            Back
          </button>
          <button
            onClick={advanceStep}
            disabled={currentStep === 5}
            className="flex items-center gap-1.5 rounded-lg border border-primary/40 bg-primary/10 px-4 py-1.5 text-xs font-semibold text-primary transition hover:bg-primary/20 hover:border-primary/60 disabled:opacity-30 disabled:cursor-not-allowed"
          >
            <Play className="h-3 w-3" />
            {currentStep === 5 ? "Complete" : "Next Step"}
          </button>
        </div>
      </div>

      {/* Danger overlay */}
      <AnimatePresence>
        {showDangerOverlay && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.2 }}
            className="absolute inset-0 z-10 flex items-center justify-center rounded-2xl bg-red-950/80 backdrop-blur-md"
          >
            <motion.div
              initial={{ scale: 0.9, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              exit={{ scale: 0.9, opacity: 0 }}
              transition={SPRING}
              className="mx-6 max-w-sm rounded-2xl border border-red-500/40 bg-red-950/90 p-6 backdrop-blur-xl shadow-2xl shadow-red-500/20"
            >
              <div className="flex items-center gap-3 mb-4">
                <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-red-500/20">
                  <AlertTriangle className="h-5 w-5 text-red-400" />
                </div>
                <div>
                  <h4 className="text-sm font-bold text-red-300">
                    DCG: Dangerous Commands
                  </h4>
                  <p className="text-[11px] text-red-400/70">
                    Always review before approving
                  </p>
                </div>
              </div>
              <div className="space-y-2 mb-5">
                {DANGER_COMMANDS.map((d) => (
                  <div
                    key={d.cmd}
                    className="flex items-center gap-3 rounded-lg border border-red-500/20 bg-red-500/10 p-3"
                  >
                    <AlertTriangle className="h-3.5 w-3.5 text-red-400 shrink-0" />
                    <div>
                      <code className="text-xs font-mono text-red-300">
                        {d.cmd}
                      </code>
                      <p className="text-[11px] text-red-400/60 mt-0.5">
                        {d.desc}
                      </p>
                    </div>
                  </div>
                ))}
              </div>
              <button
                onClick={() => setShowDangerOverlay(false)}
                className="w-full rounded-lg border border-red-500/30 bg-red-500/10 py-2 text-xs font-semibold text-red-300 transition hover:bg-red-500/20"
              >
                Understood, close
              </button>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

// =============================================================================
// COMMIT NODE
// =============================================================================

function CommitNode({
  commit,
  isHead,
  isSelected,
  onClick,
  color,
}: {
  commit: GitGraphCommit;
  isHead: boolean;
  isSelected: boolean;
  onClick: () => void;
  color: "blue" | "purple";
}) {
  const colorMap = {
    blue: {
      ring: "ring-blue-400/60",
      bg: "bg-blue-400",
      bgDim: "bg-blue-400/20",
      border: "border-blue-400/40",
      text: "text-blue-300",
      glow: "shadow-blue-400/30",
    },
    purple: {
      ring: "ring-purple-400/60",
      bg: "bg-purple-400",
      bgDim: "bg-purple-400/20",
      border: "border-purple-400/40",
      text: "text-purple-300",
      glow: "shadow-purple-400/30",
    },
  };
  const c = colorMap[color];

  return (
    <motion.button
      initial={{ opacity: 0, scale: 0 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={SPRING_SNAPPY}
      onClick={onClick}
      className={`group relative flex flex-col items-center gap-1 ${
        isSelected ? "z-10" : ""
      }`}
    >
      {/* HEAD pointer */}
      <AnimatePresence>
        {isHead && (
          <motion.div
            layoutId="head-pointer"
            initial={{ opacity: 0, y: -4 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -4 }}
            transition={SPRING}
            className="absolute -top-6 left-1/2 -translate-x-1/2"
          >
            <span className="rounded bg-amber-400/20 px-1.5 py-0.5 text-[10px] font-bold text-amber-300 uppercase tracking-wider whitespace-nowrap">
              HEAD
            </span>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Node circle */}
      <motion.div
        whileHover={{ scale: 1.2 }}
        whileTap={{ scale: 0.9 }}
        className={`relative h-8 w-8 rounded-full border-2 ${c.border} ${
          isSelected ? `ring-2 ${c.ring} ${c.bg} shadow-lg ${c.glow}` : c.bgDim
        } flex items-center justify-center transition-colors cursor-pointer`}
      >
        {commit.isMerge ? (
          <GitMerge className={`h-3.5 w-3.5 ${isSelected ? "text-white" : c.text}`} />
        ) : (
          <Circle
            className={`h-2.5 w-2.5 ${isSelected ? "text-white fill-white" : `${c.text} fill-current`}`}
          />
        )}
      </motion.div>

      {/* Hash label */}
      <span
        className={`text-[10px] font-mono ${
          isSelected ? c.text : "text-white/30"
        } group-hover:text-white/60 transition-colors whitespace-nowrap`}
      >
        {commit.hash.slice(0, 7)}
      </span>
    </motion.button>
  );
}

// =============================================================================
// FILE STATUS ICON
// =============================================================================

function FileStatusIcon({ status }: { status: "added" | "modified" | "deleted" }) {
  if (status === "added")
    return <Plus className="h-3 w-3 text-emerald-400 shrink-0" />;
  if (status === "deleted")
    return <Minus className="h-3 w-3 text-red-400 shrink-0" />;
  return <Edit3 className="h-3 w-3 text-amber-400 shrink-0" />;
}

// =============================================================================
// STAGING ZONE
// =============================================================================

function StagingZone({
  title,
  color,
  files,
}: {
  title: string;
  color: "red" | "amber" | "emerald";
  files: StagingFile[];
}) {
  const colorMap = {
    red: {
      border: "border-red-500/20",
      bg: "bg-red-500/5",
      header: "text-red-400",
    },
    amber: {
      border: "border-amber-500/20",
      bg: "bg-amber-500/5",
      header: "text-amber-400",
    },
    emerald: {
      border: "border-emerald-500/20",
      bg: "bg-emerald-500/5",
      header: "text-emerald-400",
    },
  };
  const c = colorMap[color];

  return (
    <div
      className={`rounded-lg border ${c.border} ${c.bg} p-2.5 min-h-[64px]`}
    >
      <p
        className={`text-[10px] font-semibold ${c.header} uppercase tracking-wider mb-2`}
      >
        {title}
      </p>
      <div className="flex flex-wrap gap-1.5">
        <AnimatePresence mode="popLayout">
          {files.length === 0 ? (
            <motion.span
              key="empty"
              initial={{ opacity: 0 }}
              animate={{ opacity: 0.4 }}
              exit={{ opacity: 0 }}
              className="text-[10px] text-white/30 italic"
            >
              Empty
            </motion.span>
          ) : (
            files.map((f) => (
              <StagingFileChip key={f.id} file={f} />
            ))
          )}
        </AnimatePresence>
      </div>
    </div>
  );
}

// =============================================================================
// STAGING FILE CHIP
// =============================================================================

function StagingFileChip({ file }: { file: StagingFile }) {
  const statusColors = {
    added: "bg-emerald-500/15 text-emerald-300 border-emerald-500/25",
    modified: "bg-amber-500/15 text-amber-300 border-amber-500/25",
    deleted: "bg-red-500/15 text-red-300 border-red-500/25",
  };

  const isSensitive = file.name.includes(".env");

  return (
    <motion.div
      layout
      initial={{ opacity: 0, scale: 0.8 }}
      animate={{ opacity: 1, scale: 1 }}
      exit={{ opacity: 0, scale: 0.8 }}
      transition={SPRING_SNAPPY}
      className={`flex items-center gap-1 rounded-md border px-2 py-1 text-[10px] font-mono ${statusColors[file.status]} ${
        isSensitive ? "ring-1 ring-red-500/40" : ""
      }`}
    >
      <FileStatusIcon status={file.status} />
      <span className="truncate max-w-[120px]">{file.name}</span>
      {isSensitive && (
        <AlertTriangle className="h-2.5 w-2.5 text-red-400 shrink-0 ml-0.5" />
      )}
    </motion.div>
  );
}

// =============================================================================
// CONCEPT CARD
// =============================================================================
function ConceptCard({
  term,
  definition,
  example,
}: {
  term: string;
  definition: string;
  example: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -10 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4, scale: 1.01 }}
      className="group rounded-2xl border border-white/[0.08] bg-white/[0.02] p-5 backdrop-blur-xl transition duration-300 hover:border-white/[0.15] hover:bg-white/[0.04]"
    >
      <h4 className="font-bold text-primary text-lg">{term}</h4>
      <p className="text-white/70 mt-2">{definition}</p>
      <p className="text-sm text-white/50 mt-2 italic">Example: {example}</p>
    </motion.div>
  );
}

// =============================================================================
// IGNORE ITEM
// =============================================================================
function IgnoreItem({
  pattern,
  reason,
  critical,
}: {
  pattern: string;
  reason: string;
  critical?: boolean;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -10 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4 }}
      className={`group flex items-center gap-4 p-3 rounded-xl border transition duration-300 ${
        critical
          ? "border-red-500/30 bg-red-500/10 hover:border-red-500/50"
          : "border-white/[0.08] bg-white/[0.02] hover:border-white/[0.15]"
      }`}
    >
      <code className={`font-mono text-sm px-2 py-1 rounded ${critical ? "bg-red-500/20 text-red-400" : "bg-white/[0.05] text-primary"}`}>
        {pattern}
      </code>
      <span className="text-sm text-white/60">{reason}</span>
      {critical && (
        <span className="ml-auto text-xs font-medium text-red-400 uppercase">Security Risk</span>
      )}
    </motion.div>
  );
}

// =============================================================================
// DANGEROUS COMMAND
// =============================================================================
function DangerousCommand({
  command,
  effect,
  alternative,
}: {
  command: string;
  effect: string;
  alternative: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      whileHover={{ x: 4, scale: 1.01 }}
      className="group rounded-2xl border border-red-500/30 bg-red-500/5 p-5 backdrop-blur-xl transition duration-300 hover:border-red-500/50 hover:bg-red-500/10"
    >
      <div className="flex items-center gap-3 mb-3">
        <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-red-500/20">
          <AlertTriangle className="h-4 w-4 text-red-400" />
        </div>
        <code className="font-mono text-red-400 font-medium">{command}</code>
      </div>
      <p className="text-sm text-white/60 mb-2">
        <strong className="text-red-400">Effect:</strong> {effect}
      </p>
      <p className="text-sm text-emerald-400/80">
        <strong>Alternative:</strong> {alternative}
      </p>
    </motion.div>
  );
}

// =============================================================================
// BEST PRACTICE
// =============================================================================
function BestPractice({
  title,
  description,
}: {
  title: string;
  description: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -10 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4, scale: 1.01 }}
      className="group flex items-start gap-4 p-5 rounded-2xl border border-emerald-500/20 bg-emerald-500/5 backdrop-blur-xl transition duration-300 hover:border-emerald-500/40 hover:bg-emerald-500/10"
    >
      <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-emerald-500/20 text-emerald-400 shadow-lg shadow-emerald-500/10 group-hover:shadow-emerald-500/20 transition-shadow">
        <CheckCircle className="h-5 w-5" />
      </div>
      <div>
        <p className="font-semibold text-white group-hover:text-emerald-300 transition-colors">{title}</p>
        <p className="text-sm text-white/50 mt-1">{description}</p>
      </div>
    </motion.div>
  );
}
