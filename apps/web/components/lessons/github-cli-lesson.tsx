"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import { motion, AnimatePresence } from "@/components/motion";
import {
  Github,
  KeyRound,
  CircleDot,
  GitPullRequest,
  Tag,
  Workflow,
  Eye,
  CheckCircle,
  Zap,
  ChevronLeft,
  ChevronRight,
  Play,
  Pause,
  GitBranch,
  Loader2,
  GitMerge,
  MessageSquare,
  FileCode,
  FilePlus,
  FileEdit,
  Shield,
  Users,
  Clock,
  ArrowRight,
  Terminal,
  Rocket,
  XCircle,
  AlertCircle,
  Check,
  ChevronDown,
  ChevronUp,
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

export function GithubCliLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Manage GitHub issues, PRs, releases, and actions from the command line.
      </GoalBanner>

      {/* What Is GitHub CLI */}
      <Section
        title="What Is GitHub CLI?"
        icon={<Github className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph>
          <Highlight>GitHub CLI (gh)</Highlight> lets you interact with GitHub
          directly from your terminal. No more switching between your editor and
          browser for common tasks.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<CircleDot className="h-5 w-5" />}
              title="Issues"
              description="Create, view, and close issues"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<GitPullRequest className="h-5 w-5" />}
              title="Pull Requests"
              description="Create, review, and merge PRs"
              gradient="from-primary/20 to-violet-500/20"
            />
            <FeatureCard
              icon={<Tag className="h-5 w-5" />}
              title="Releases"
              description="Create tags and releases"
              gradient="from-amber-500/20 to-orange-500/20"
            />
            <FeatureCard
              icon={<Workflow className="h-5 w-5" />}
              title="Actions"
              description="View and manage workflows"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
          </FeatureGrid>
        </div>

        <div className="mt-8"><InteractiveGitHubWorkflow /></div>

        <div className="mt-6">
          <TipBox variant="info">
            AI agents use <InlineCode>gh</InlineCode> extensively for
            GitHub operations. Understanding these commands helps you review
            what agents propose.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Authentication */}
      <Section
        title="Authentication"
        icon={<KeyRound className="h-5 w-5" />}
        delay={0.15}
      >
        <Paragraph>
          First, authenticate with your GitHub account:
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Interactive login (recommended)
$ gh auth login

# Check your auth status
$ gh auth status

# View current user
$ gh api user --jq '.login'`}
            language="bash"
          />
        </div>

        <div className="mt-6">
          <TipBox variant="tip">
            The interactive login will guide you through browser-based OAuth.
            Choose HTTPS for the git protocol unless you have SSH keys set up.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Issues */}
      <Section
        title="Working with Issues"
        icon={<CircleDot className="h-5 w-5" />}
        delay={0.2}
      >
        <CommandList
          commands={[
            {
              command: "gh issue list",
              description: "List open issues",
            },
            {
              command: "gh issue list --state all",
              description: "List all issues (open and closed)",
            },
            {
              command: "gh issue view 123",
              description: "View issue #123 details",
            },
            {
              command: 'gh issue create --title "Bug" --body "Description"',
              description: "Create a new issue",
            },
            {
              command: "gh issue close 123",
              description: "Close issue #123",
            },
            {
              command: 'gh issue comment 123 --body "Comment text"',
              description: "Add a comment to issue #123",
            },
          ]}
        />

        <div className="mt-6">
          <CodeBlock
            code={`# Create an issue interactively
$ gh issue create

# Create with labels and assignee
$ gh issue create \\
  --title "Fix login bug" \\
  --body "Users can't login with email" \\
  --label bug \\
  --assignee @me`}
            language="bash"
          />
        </div>
      </Section>

      <Divider />

      {/* Pull Requests */}
      <Section
        title="Pull Requests"
        icon={<GitPullRequest className="h-5 w-5" />}
        delay={0.25}
      >
        <Paragraph>
          Create and manage pull requests without leaving your terminal:
        </Paragraph>

        <div className="mt-6">
          <CommandList
            commands={[
              {
                command: "gh pr list",
                description: "List open pull requests",
              },
              {
                command: "gh pr view 456",
                description: "View PR #456 details",
              },
              {
                command: "gh pr create",
                description: "Create a PR (interactive)",
              },
              {
                command: "gh pr checkout 456",
                description: "Check out PR #456 locally",
              },
              {
                command: "gh pr merge 456",
                description: "Merge PR #456",
              },
              {
                command: "gh pr diff 456",
                description: "View PR diff",
              },
            ]}
          />
        </div>

        <div className="mt-6">
          <CodeBlock
            code={`# Create a PR with title and body
$ gh pr create \\
  --title "Add user authentication" \\
  --body "## Summary
Implements OAuth2 login flow.

## Test plan
- [x] Unit tests pass
- [ ] Manual testing on staging"

# Create a draft PR
$ gh pr create --draft

# Request review
$ gh pr edit 456 --add-reviewer username

# View PR checks status
$ gh pr checks 456`}
            language="bash"
          />
        </div>

        <div className="mt-6">
          <TipBox variant="tip">
            Agents often create PRs using heredocs for the body. This format
            is common: <InlineCode>--body &quot;$(cat &lt;&lt;&apos;EOF&apos; ... EOF)&quot;</InlineCode>
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Releases and Tags */}
      <Section
        title="Releases & Tags"
        icon={<Tag className="h-5 w-5" />}
        delay={0.3}
      >
        <CommandList
          commands={[
            {
              command: "gh release list",
              description: "List releases",
            },
            {
              command: "gh release view v1.2.0",
              description: "View release details",
            },
            {
              command: 'gh release create v1.2.0 --notes "Release notes"',
              description: "Create a release with tag",
            },
            {
              command: "gh release create v1.2.0 --generate-notes",
              description: "Auto-generate notes from commits",
            },
            {
              command: "gh release download v1.2.0",
              description: "Download release assets",
            },
          ]}
        />

        <div className="mt-6">
          <CodeBlock
            code={`# Create a release with assets
$ gh release create v2.0.0 \\
  --title "Version 2.0.0" \\
  --notes "Major update with new features" \\
  ./dist/*.zip

# Create a pre-release
$ gh release create v2.1.0-beta --prerelease

# Delete a release (be careful!)
$ gh release delete v1.0.0-test --yes`}
            language="bash"
          />
        </div>
      </Section>

      <Divider />

      {/* GitHub Actions */}
      <Section
        title="GitHub Actions"
        icon={<Workflow className="h-5 w-5" />}
        delay={0.35}
      >
        <Paragraph>
          Monitor and interact with your CI/CD workflows:
        </Paragraph>

        <div className="mt-6">
          <CommandList
            commands={[
              {
                command: "gh workflow list",
                description: "List all workflows",
              },
              {
                command: "gh run list",
                description: "List recent workflow runs",
              },
              {
                command: "gh run view 123456",
                description: "View run details",
              },
              {
                command: "gh run view 123456 --log",
                description: "View run logs",
              },
              {
                command: "gh run watch 123456",
                description: "Watch a run in real-time",
              },
              {
                command: "gh run rerun 123456",
                description: "Re-run a failed workflow",
              },
            ]}
          />
        </div>

        <div className="mt-6">
          <CodeBlock
            code={`# View failed runs
$ gh run list --status failure

# Trigger a workflow manually
$ gh workflow run build.yml

# Trigger with inputs
$ gh workflow run deploy.yml -f environment=staging

# View job logs for a specific job
$ gh run view 123456 --job 789 --log`}
            language="bash"
          />
        </div>
      </Section>

      <Divider />

      {/* Repository Info */}
      <Section
        title="Repository Operations"
        icon={<Github className="h-5 w-5" />}
        delay={0.4}
      >
        <CommandList
          commands={[
            {
              command: "gh repo view",
              description: "View current repo info",
            },
            {
              command: "gh repo clone owner/repo",
              description: "Clone a repository",
            },
            {
              command: "gh repo fork",
              description: "Fork current repo",
            },
            {
              command: "gh repo create my-project --public",
              description: "Create a new repository",
            },
            {
              command: "gh browse",
              description: "Open repo in browser",
            },
            {
              command: "gh browse issues",
              description: "Open issues page in browser",
            },
          ]}
        />
      </Section>

      <Divider />

      {/* API Access */}
      <Section
        title="Direct API Access"
        icon={<Zap className="h-5 w-5" />}
        delay={0.45}
      >
        <Paragraph>
          For advanced use cases, access the GitHub API directly:
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Get repo info as JSON
$ gh api repos/owner/repo

# List PR comments
$ gh api repos/owner/repo/pulls/123/comments

# Use jq to extract specific fields
$ gh api user --jq '.login, .email'

# POST to create something
$ gh api repos/owner/repo/issues \\
  -f title="API created issue" \\
  -f body="Created via gh api"`}
            language="bash"
          />
        </div>

        <div className="mt-6">
          <TipBox variant="info">
            Agents use <InlineCode>gh api</InlineCode> for operations not
            covered by the standard commands. Review these carefully as they
            have full API access.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Best Practices */}
      <Section
        title="Best Practices"
        icon={<CheckCircle className="h-5 w-5" />}
        delay={0.5}
      >
        <div className="space-y-4">
          <BestPractice
            title="Always review PR details before merging"
            description="Use gh pr view and gh pr diff to understand changes."
          />
          <BestPractice
            title="Use --dry-run where available"
            description="Some commands support --dry-run to preview actions."
          />
          <BestPractice
            title="Check workflow status before deploying"
            description="Run gh run list to ensure CI passed before releasing."
          />
          <BestPractice
            title="Use labels and milestones"
            description="Organize issues with --label and --milestone flags."
          />
          <BestPractice
            title="Review agent-created PRs carefully"
            description="Agents may create PRs automatically. Always review before merging."
          />
        </div>
      </Section>

      <Divider />

      {/* Try It Now */}
      <Section
        title="Try It Now"
        icon={<Eye className="h-5 w-5" />}
        delay={0.55}
      >
        <CodeBlock
          code={`# Check if gh is installed and authenticated
$ gh auth status

# View the current repository
$ gh repo view

# List recent issues
$ gh issue list --limit 5

# List recent PRs
$ gh pr list --limit 5

# Check recent workflow runs
$ gh run list --limit 5`}
          showLineNumbers
        />
      </Section>
    </div>
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

// =============================================================================
// WORKFLOW DATA
// =============================================================================

interface WorkflowStage {
  id: string;
  label: string;
  command: string;
  color: string;
  iconType: string;
  description: string;
  detail: string;
}

const WORKFLOW_STAGES: WorkflowStage[] = [
  {
    id: "branch",
    label: "Create Branch",
    command: "git checkout -b feat/add-auth",
    color: "blue",
    iconType: "branch",
    description: "Create a feature branch from main",
    detail: "Isolate your work on a dedicated branch so main stays stable.",
  },
  {
    id: "changes",
    label: "Make Changes",
    command: "claude --task 'Implement auth module'",
    color: "violet",
    iconType: "code",
    description: "Agent implements the feature",
    detail: "AI agent writes code, tests, and documentation for the auth feature.",
  },
  {
    id: "create-pr",
    label: "Create PR",
    command: 'gh pr create --title "Add auth" --body "Closes #42"',
    color: "purple",
    iconType: "pr",
    description: "Open a pull request for review",
    detail: "Push changes and create a PR linking to the original issue.",
  },
  {
    id: "review",
    label: "Code Review",
    command: "gh pr review 43 --approve",
    color: "amber",
    iconType: "review",
    description: "Team reviews the code changes",
    detail: "Reviewers leave comments, request changes, or approve the PR.",
  },
  {
    id: "ci",
    label: "CI Checks",
    command: "gh pr checks 43 --watch",
    color: "cyan",
    iconType: "ci",
    description: "Automated tests and checks run",
    detail: "Lint, type-check, unit tests, and build all run in parallel.",
  },
  {
    id: "merge",
    label: "Merge & Deploy",
    command: "gh pr merge 43 --squash --delete-branch",
    color: "emerald",
    iconType: "merge",
    description: "Merge to main and deploy",
    detail: "Squash-merge into main, delete the feature branch, and trigger deployment.",
  },
];

// =============================================================================
// INTERACTIVE GITHUB WORKFLOW - MAIN COMPONENT
// =============================================================================
function InteractiveGitHubWorkflow() {
  const [activeStage, setActiveStage] = useState(0);
  const [isPlaying, setIsPlaying] = useState(false);
  const [expandedPanel, setExpandedPanel] = useState<string | null>("timeline");
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // CI sub-animation states
  const [ciJobStates, setCiJobStates] = useState<Record<string, "pending" | "running" | "passed">>({
    lint: "pending",
    typecheck: "pending",
    tests: "pending",
    build: "pending",
  });

  // Review thread states
  const [reviewCommentIndex, setReviewCommentIndex] = useState(0);

  // Terminal history
  const [terminalLines, setTerminalLines] = useState<string[]>([]);

  const totalStages = WORKFLOW_STAGES.length;

  const resetCiJobs = useCallback(() => {
    setCiJobStates({
      lint: "pending",
      typecheck: "pending",
      tests: "pending",
      build: "pending",
    });
  }, []);

  // Auto-play timer
  useEffect(() => {
    if (!isPlaying) return;
    const delay = activeStage === 4 ? 4000 : 2800;
    timerRef.current = setTimeout(() => {
      if (activeStage >= totalStages - 1) {
        setIsPlaying(false);
      } else {
        setActiveStage((s) => s + 1);
      }
    }, delay);
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, [isPlaying, activeStage, totalStages]);

  // CI job animations when on CI stage
  useEffect(() => {
    if (activeStage !== 4) {
      setTimeout(() => {
        resetCiJobs();
      }, 0);
      return;
    }
    // Stagger the CI jobs through running -> passed
    const jobs = ["lint", "typecheck", "tests", "build"];
    const timers: ReturnType<typeof setTimeout>[] = [];

    jobs.forEach((job, i) => {
      // Start running
      timers.push(
        setTimeout(() => {
          setCiJobStates((prev) => ({ ...prev, [job]: "running" }));
        }, i * 400)
      );
      // Finish
      timers.push(
        setTimeout(() => {
          setCiJobStates((prev) => ({ ...prev, [job]: "passed" }));
        }, i * 400 + 800 + i * 200)
      );
    });

    return () => {
      timers.forEach(clearTimeout);
    };
  }, [activeStage, resetCiJobs]);

  // Review comments animation
  useEffect(() => {
    if (activeStage !== 3) {
      setTimeout(() => {
        setReviewCommentIndex(0);
      }, 0);
      return;
    }
    const t1 = setTimeout(() => {
      setReviewCommentIndex(1);
    }, 600);
    const t2 = setTimeout(() => {
      setReviewCommentIndex(2);
    }, 1400);
    const t3 = setTimeout(() => {
      setReviewCommentIndex(3);
    }, 2200);
    return () => {
      clearTimeout(t1);
      clearTimeout(t2);
      clearTimeout(t3);
    };
  }, [activeStage]);

  // Update terminal lines when stage changes
  useEffect(() => {
    const stage = WORKFLOW_STAGES[activeStage];
    setTimeout(() => {
      setTerminalLines((prev) => {
        const next = [...prev, `$ ${stage.command}`];
        // Keep only the last 4 lines
        return next.slice(-4);
      });
    }, 0);
  }, [activeStage]);

  const goPrev = useCallback(() => {
    resetCiJobs();
    setActiveStage((s) => Math.max(s - 1, 0));
  }, [resetCiJobs]);

  const goNext = useCallback(() => {
    resetCiJobs();
    setActiveStage((s) => Math.min(s + 1, totalStages - 1));
  }, [resetCiJobs, totalStages]);

  const togglePlay = useCallback(() => {
    if (activeStage >= totalStages - 1) {
      resetCiJobs();
      setActiveStage(0);
      setTimeout(() => {
        setTerminalLines([]);
      }, 0);
      setIsPlaying(true);
    } else {
      setIsPlaying((p) => !p);
    }
  }, [activeStage, totalStages, resetCiJobs]);

  const togglePanel = useCallback((panel: string) => {
    setExpandedPanel((prev) => (prev === panel ? null : panel));
  }, []);

  return (
    <div className="relative rounded-3xl border border-white/[0.08] bg-gradient-to-br from-white/[0.03] to-transparent backdrop-blur-xl overflow-hidden">
      {/* Background decorative elements */}
      <div className="absolute top-0 left-1/4 w-80 h-80 bg-violet-500/[0.06] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-1/4 w-60 h-60 bg-emerald-500/[0.06] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute top-1/2 left-1/2 w-40 h-40 bg-blue-500/[0.04] rounded-full blur-3xl pointer-events-none" />

      <div className="relative p-6 sm:p-8 space-y-6">
        {/* Header */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-gradient-to-br from-violet-500/20 to-purple-500/20 border border-violet-500/20">
              <Workflow className="h-5 w-5 text-violet-400" />
            </div>
            <div>
              <h3 className="text-sm font-semibold text-white">PR Lifecycle Automation</h3>
              <p className="text-xs text-white/40">Full workflow with gh CLI</p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <span className="text-[10px] font-mono text-white/30 px-2 py-1 rounded-lg bg-white/[0.04] border border-white/[0.06]">
              {activeStage + 1}/{totalStages}
            </span>
          </div>
        </div>

        {/* Mini terminal showing command history */}
        <MiniTerminal
          lines={terminalLines}
          currentCommand={WORKFLOW_STAGES[activeStage].command}
          stage={activeStage}
        />

        {/* GitHub-style PR timeline */}
        <PRTimeline
          stages={WORKFLOW_STAGES}
          activeStage={activeStage}
          onStageClick={(i) => {
            resetCiJobs();
            setActiveStage(i);
            setIsPlaying(false);
          }}
        />

        {/* Main visual area */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          {/* Left: Stage visualization */}
          <div className="min-h-[280px] rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl p-5 flex flex-col">
            <AnimatePresence mode="wait">
              <motion.div
                key={activeStage}
                initial={{ opacity: 0, y: 12 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -12 }}
                transition={{ type: "spring", stiffness: 200, damping: 25 }}
                className="flex-1 flex flex-col"
              >
                <StageVisual
                  stage={WORKFLOW_STAGES[activeStage]}
                  stageIndex={activeStage}
                  ciJobStates={ciJobStates}
                  reviewCommentIndex={reviewCommentIndex}
                />
              </motion.div>
            </AnimatePresence>
          </div>

          {/* Right: Collapsible detail panels */}
          <div className="space-y-3">
            {/* Branch visualization panel */}
            <CollapsiblePanel
              id="branch"
              title="Branch Flow"
              icon={<GitBranch className="h-3.5 w-3.5" />}
              expanded={expandedPanel === "branch"}
              onToggle={() => togglePanel("branch")}
              color="blue"
            >
              <BranchFlowVisualization activeStage={activeStage} />
            </CollapsiblePanel>

            {/* PR detail panel */}
            <CollapsiblePanel
              id="pr-detail"
              title="PR Details"
              icon={<GitPullRequest className="h-3.5 w-3.5" />}
              expanded={expandedPanel === "pr-detail"}
              onToggle={() => togglePanel("pr-detail")}
              color="violet"
            >
              <PRDetailPanel activeStage={activeStage} ciJobStates={ciJobStates} />
            </CollapsiblePanel>

            {/* Timeline panel */}
            <CollapsiblePanel
              id="timeline"
              title="Activity Feed"
              icon={<Clock className="h-3.5 w-3.5" />}
              expanded={expandedPanel === "timeline"}
              onToggle={() => togglePanel("timeline")}
              color="emerald"
            >
              <ActivityFeed activeStage={activeStage} />
            </CollapsiblePanel>
          </div>
        </div>

        {/* Stage description bar */}
        <div className="text-center">
          <AnimatePresence mode="wait">
            <motion.div
              key={activeStage}
              initial={{ opacity: 0, y: 6 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -6 }}
              transition={{ type: "spring", stiffness: 300, damping: 30 }}
            >
              <p className="text-sm font-semibold text-white/80">
                {WORKFLOW_STAGES[activeStage].label}
              </p>
              <p className="text-xs text-white/40 mt-1 max-w-md mx-auto">
                {WORKFLOW_STAGES[activeStage].detail}
              </p>
            </motion.div>
          </AnimatePresence>
        </div>

        {/* Playback controls */}
        <div className="flex items-center justify-center gap-4 pt-1">
          <button
            type="button"
            onClick={goPrev}
            disabled={activeStage <= 0}
            className="flex h-9 w-9 items-center justify-center rounded-xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl text-white/60 transition hover:border-white/20 hover:text-white disabled:opacity-30 disabled:cursor-not-allowed"
          >
            <ChevronLeft className="h-4 w-4" />
          </button>

          <button
            type="button"
            onClick={togglePlay}
            className="flex h-9 w-9 items-center justify-center rounded-xl border border-primary/30 bg-primary/10 text-primary transition hover:bg-primary/20"
          >
            {isPlaying ? (
              <Pause className="h-4 w-4" />
            ) : (
              <Play className="h-4 w-4 ml-0.5" />
            )}
          </button>

          <button
            type="button"
            onClick={goNext}
            disabled={activeStage >= totalStages - 1}
            className="flex h-9 w-9 items-center justify-center rounded-xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl text-white/60 transition hover:border-white/20 hover:text-white disabled:opacity-30 disabled:cursor-not-allowed"
          >
            <ChevronRight className="h-4 w-4" />
          </button>
        </div>

        {/* Stage indicator dots */}
        <div className="flex items-center justify-center gap-2">
          {WORKFLOW_STAGES.map((s, i) => (
            <button
              type="button"
              key={s.id}
              onClick={() => {
                resetCiJobs();
                setActiveStage(i);
                setIsPlaying(false);
              }}
              className={`h-2 rounded-full transition-[width,background-color] duration-300 ${
                i === activeStage
                  ? "w-6 bg-primary"
                  : i < activeStage
                    ? "w-2 bg-primary/40"
                    : "w-2 bg-white/20"
              }`}
            />
          ))}
        </div>
      </div>
    </div>
  );
}

// =============================================================================
// MINI TERMINAL
// =============================================================================
function MiniTerminal({
  lines,
  currentCommand,
  stage,
}: {
  lines: string[];
  currentCommand: string;
  stage: number;
}) {
  return (
    <div className="rounded-xl border border-white/[0.08] bg-black/50 backdrop-blur-xl overflow-hidden">
      {/* Title bar */}
      <div className="flex items-center gap-2 px-4 py-2 border-b border-white/[0.06] bg-white/[0.02]">
        <div className="flex gap-1.5">
          <div className="h-2.5 w-2.5 rounded-full bg-red-500/60" />
          <div className="h-2.5 w-2.5 rounded-full bg-amber-500/60" />
          <div className="h-2.5 w-2.5 rounded-full bg-emerald-500/60" />
        </div>
        <div className="flex items-center gap-2 ml-2">
          <Terminal className="h-3 w-3 text-white/30" />
          <span className="text-[10px] font-mono text-white/30">gh-workflow ~/my-project</span>
        </div>
      </div>
      {/* Command history + current */}
      <div className="px-4 py-3 space-y-1 min-h-[72px]">
        {/* Previous lines (faded) */}
        {lines.slice(0, -1).map((line, i) => (
          <div key={`${stage}-prev-${i}`} className="font-mono text-xs text-white/25 truncate">
            {line}
          </div>
        ))}
        {/* Current command with animation */}
        <AnimatePresence mode="wait">
          <motion.div
            key={stage}
            initial={{ opacity: 0, x: 8 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -8 }}
            transition={{ type: "spring", stiffness: 300, damping: 30 }}
            className="flex items-center gap-2"
          >
            <span className="text-emerald-400 font-mono text-xs shrink-0">$</span>
            <span className="font-mono text-xs text-white/80 truncate">{currentCommand}</span>
            <motion.span
              animate={{ opacity: [1, 0] }}
              transition={{ duration: 0.8, repeat: Infinity, repeatType: "reverse" }}
              className="inline-block w-1.5 h-4 bg-white/60 shrink-0"
            />
          </motion.div>
        </AnimatePresence>
      </div>
    </div>
  );
}

// =============================================================================
// PR TIMELINE (GitHub-style horizontal timeline)
// =============================================================================
function PRTimeline({
  stages,
  activeStage,
  onStageClick,
}: {
  stages: WorkflowStage[];
  activeStage: number;
  onStageClick: (i: number) => void;
}) {
  const colorMap: Record<string, string> = {
    blue: "bg-blue-500 border-blue-400 shadow-blue-500/30",
    violet: "bg-violet-500 border-violet-400 shadow-violet-500/30",
    purple: "bg-purple-500 border-purple-400 shadow-purple-500/30",
    amber: "bg-amber-500 border-amber-400 shadow-amber-500/30",
    cyan: "bg-cyan-500 border-cyan-400 shadow-cyan-500/30",
    emerald: "bg-emerald-500 border-emerald-400 shadow-emerald-500/30",
  };

  const inactiveColor = "bg-white/10 border-white/20";
  const completedColor = "bg-emerald-500/60 border-emerald-400/60";

  const getIcon = (iconType: string, isActive: boolean, isCompleted: boolean) => {
    const className = `h-3 w-3 ${isActive ? "text-white" : isCompleted ? "text-white/90" : "text-white/40"}`;
    switch (iconType) {
      case "branch": return <GitBranch className={className} />;
      case "code": return <FileCode className={className} />;
      case "pr": return <GitPullRequest className={className} />;
      case "review": return <MessageSquare className={className} />;
      case "ci": return <Shield className={className} />;
      case "merge": return <GitMerge className={className} />;
      default: return <CircleDot className={className} />;
    }
  };

  return (
    <div className="relative overflow-x-auto py-2 scrollbar-none">
      <div className="flex items-center gap-0 min-w-fit mx-auto justify-center">
        {stages.map((stage, i) => {
          const isActive = i === activeStage;
          const isCompleted = i < activeStage;

          return (
            <div key={stage.id} className="flex items-center">
              {/* Node */}
              <button
                type="button"
                onClick={() => onStageClick(i)}
                className="relative group flex flex-col items-center gap-1.5"
              >
                <motion.div
                  animate={{
                    scale: isActive ? 1.15 : 1,
                  }}
                  transition={{ type: "spring", stiffness: 200, damping: 25 }}
                  className={`relative flex h-8 w-8 items-center justify-center rounded-full border-2 transition duration-300 cursor-pointer ${
                    isActive
                      ? `${colorMap[stage.color]} shadow-lg`
                      : isCompleted
                        ? completedColor
                        : inactiveColor
                  }`}
                >
                  {isCompleted && !isActive ? (
                    <Check className="h-3 w-3 text-white/90" />
                  ) : (
                    getIcon(stage.iconType, isActive, isCompleted)
                  )}
                  {isActive && (
                    <motion.div
                      layoutId="timeline-ring"
                      className="absolute inset-[-4px] rounded-full border-2 border-white/20"
                      transition={{ type: "spring", stiffness: 200, damping: 25 }}
                    />
                  )}
                </motion.div>
                <span className={`text-[9px] font-medium transition-colors whitespace-nowrap max-w-[60px] truncate ${
                  isActive ? "text-white/90" : "text-white/30"
                }`}>
                  {stage.label}
                </span>
              </button>

              {/* Connector line */}
              {i < stages.length - 1 && (
                <div className="relative w-8 sm:w-12 h-0.5 mx-1 mb-5">
                  <div className="absolute inset-0 bg-white/10 rounded-full" />
                  <motion.div
                    initial={false}
                    animate={{
                      scaleX: isCompleted ? 1 : 0,
                    }}
                    transition={{ type: "spring", stiffness: 200, damping: 25 }}
                    className="absolute inset-0 bg-emerald-500/50 rounded-full origin-left"
                  />
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

// =============================================================================
// COLLAPSIBLE PANEL
// =============================================================================
function CollapsiblePanel({
  id,
  title,
  icon,
  expanded,
  onToggle,
  color,
  children,
}: {
  id: string;
  title: string;
  icon: React.ReactNode;
  expanded: boolean;
  onToggle: () => void;
  color: string;
  children: React.ReactNode;
}) {
  const borderColors: Record<string, string> = {
    blue: "border-blue-500/20 hover:border-blue-500/30",
    violet: "border-violet-500/20 hover:border-violet-500/30",
    emerald: "border-emerald-500/20 hover:border-emerald-500/30",
  };
  const textColors: Record<string, string> = {
    blue: "text-blue-400",
    violet: "text-violet-400",
    emerald: "text-emerald-400",
  };

  return (
    <div
      className={`rounded-xl border ${borderColors[color] ?? "border-white/[0.08]"} bg-white/[0.02] backdrop-blur-xl overflow-hidden transition-colors`}
    >
      <button
        type="button"
        onClick={onToggle}
        className="w-full flex items-center justify-between px-4 py-3 text-left"
      >
        <div className="flex items-center gap-2">
          <span className={textColors[color] ?? "text-white/60"}>{icon}</span>
          <span className="text-xs font-medium text-white/70">{title}</span>
        </div>
        {expanded ? (
          <ChevronUp className="h-3.5 w-3.5 text-white/30" />
        ) : (
          <ChevronDown className="h-3.5 w-3.5 text-white/30" />
        )}
      </button>
      <AnimatePresence initial={false}>
        {expanded && (
          <motion.div
            key={`panel-${id}`}
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: "auto", opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
            className="overflow-hidden"
          >
            <div className="px-4 pb-4">
              {children}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

// =============================================================================
// STAGE VISUALS
// =============================================================================
function StageVisual({
  stageIndex,
  ciJobStates,
  reviewCommentIndex,
}: {
  stage: WorkflowStage;
  stageIndex: number;
  ciJobStates: Record<string, "pending" | "running" | "passed">;
  reviewCommentIndex: number;
}) {
  switch (stageIndex) {
    case 0:
      return <CreateBranchVisual />;
    case 1:
      return <MakeChangesVisual />;
    case 2:
      return <CreatePRVisual />;
    case 3:
      return <CodeReviewVisual commentIndex={reviewCommentIndex} />;
    case 4:
      return <CIPipelineVisual jobStates={ciJobStates} />;
    case 5:
      return <MergeDeployVisual />;
    default:
      return null;
  }
}

// Stage 0: Create Branch
function CreateBranchVisual() {
  return (
    <div className="flex-1 flex flex-col items-center justify-center gap-5">
      <div className="flex items-center gap-4">
        {/* Main branch */}
        <motion.div
          initial={{ opacity: 0, x: -20 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ type: "spring", stiffness: 200, damping: 25 }}
          className="flex items-center gap-2 rounded-full border border-blue-500/30 bg-blue-500/10 px-4 py-2"
        >
          <div className="h-3 w-3 rounded-full bg-blue-400" />
          <span className="text-xs font-mono text-blue-400 font-semibold">main</span>
        </motion.div>

        {/* Animated connector */}
        <motion.div
          initial={{ scaleX: 0 }}
          animate={{ scaleX: 1 }}
          transition={{ type: "spring", stiffness: 200, damping: 25, delay: 0.2 }}
          className="w-16 h-0.5 origin-left"
        >
          <div className="h-full bg-gradient-to-r from-blue-500/60 to-violet-500/60 rounded-full" />
        </motion.div>

        {/* Feature branch */}
        <motion.div
          initial={{ opacity: 0, scale: 0.8 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ type: "spring", stiffness: 200, damping: 25, delay: 0.4 }}
          className="flex items-center gap-2 rounded-full border border-violet-500/30 bg-violet-500/10 px-4 py-2"
        >
          <GitBranch className="h-3.5 w-3.5 text-violet-400" />
          <span className="text-xs font-mono text-violet-400 font-semibold">feat/add-auth</span>
        </motion.div>
      </div>

      {/* Git log visualization */}
      <motion.div
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ type: "spring", stiffness: 200, damping: 25, delay: 0.6 }}
        className="flex items-center gap-2"
      >
        {/* Main commits */}
        {[0, 1, 2].map((i) => (
          <div key={`main-${i}`} className="flex items-center gap-2">
            <div className="h-4 w-4 rounded-full bg-blue-500/30 border border-blue-500/40 flex items-center justify-center">
              <div className="h-1.5 w-1.5 rounded-full bg-blue-400" />
            </div>
            {i < 2 && <div className="w-4 h-0.5 bg-blue-500/20 rounded-full" />}
          </div>
        ))}
        {/* Branch point */}
        <div className="relative">
          <div className="w-4 h-0.5 bg-blue-500/20 rounded-full" />
          <motion.div
            initial={{ scaleY: 0 }}
            animate={{ scaleY: 1 }}
            transition={{ type: "spring", stiffness: 200, damping: 25, delay: 0.7 }}
            className="absolute left-1/2 top-0 w-0.5 h-6 bg-gradient-to-b from-blue-500/40 to-violet-500/40 origin-top"
          />
          <motion.div
            initial={{ opacity: 0, scale: 0 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ type: "spring", stiffness: 200, damping: 25, delay: 0.9 }}
            className="absolute left-1/2 top-6 -translate-x-1/2"
          >
            <div className="h-4 w-4 rounded-full bg-violet-500/30 border border-violet-500/40 flex items-center justify-center">
              <div className="h-1.5 w-1.5 rounded-full bg-violet-400" />
            </div>
          </motion.div>
        </div>
      </motion.div>

      <motion.p
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 1 }}
        className="text-[10px] text-white/30 font-mono"
      >
        HEAD now at feat/add-auth
      </motion.p>
    </div>
  );
}

// Stage 1: Make Changes
function MakeChangesVisual() {
  const files = [
    { name: "src/auth/login.ts", type: "added" as const, lines: "+84" },
    { name: "src/auth/session.ts", type: "added" as const, lines: "+127" },
    { name: "src/auth/middleware.ts", type: "added" as const, lines: "+43" },
    { name: "src/config.ts", type: "modified" as const, lines: "+12 -3" },
    { name: "tests/auth.test.ts", type: "added" as const, lines: "+96" },
  ];

  return (
    <div className="flex-1 flex flex-col gap-3">
      <div className="flex items-center gap-2 mb-1">
        <Zap className="h-4 w-4 text-violet-400" />
        <span className="text-xs font-semibold text-violet-400">Agent Working</span>
        <motion.span
          animate={{ opacity: [0.3, 1, 0.3] }}
          transition={{ duration: 1.5, repeat: Infinity }}
          className="text-[10px] text-white/30"
        >
          writing code...
        </motion.span>
      </div>

      <div className="space-y-1.5">
        {files.map((file, i) => (
          <motion.div
            key={file.name}
            initial={{ opacity: 0, x: -12 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ type: "spring", stiffness: 200, damping: 25, delay: i * 0.15 }}
            className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-white/[0.03] border border-white/[0.05]"
          >
            {file.type === "added" ? (
              <FilePlus className="h-3.5 w-3.5 text-emerald-400 shrink-0" />
            ) : (
              <FileEdit className="h-3.5 w-3.5 text-amber-400 shrink-0" />
            )}
            <span className="text-xs font-mono text-white/60 truncate">{file.name}</span>
            <span className={`text-[10px] font-mono ml-auto shrink-0 ${
              file.type === "added" ? "text-emerald-400/70" : "text-amber-400/70"
            }`}>
              {file.lines}
            </span>
          </motion.div>
        ))}
      </div>

      {/* Typing animation */}
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 0.8 }}
        className="mt-1 rounded-lg bg-black/30 border border-white/[0.06] px-3 py-2"
      >
        <div className="flex items-center gap-1 font-mono text-[10px]">
          <span className="text-violet-400/60">export</span>
          <span className="text-blue-400/60">async function</span>
          <span className="text-amber-400/60">authenticate</span>
          <span className="text-white/30">(</span>
          <span className="text-white/30">)</span>
          <motion.span
            animate={{ opacity: [1, 0] }}
            transition={{ duration: 0.6, repeat: Infinity, repeatType: "reverse" }}
            className="inline-block w-1 h-3 bg-violet-400/80"
          />
        </div>
      </motion.div>
    </div>
  );
}

// Stage 2: Create PR
function CreatePRVisual() {
  return (
    <div className="flex-1 flex flex-col gap-4">
      <motion.div
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        transition={{ type: "spring", stiffness: 200, damping: 25 }}
        className="rounded-xl border border-purple-500/30 bg-purple-500/5 p-4"
      >
        <div className="flex items-center gap-3 mb-3">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-purple-500/20">
            <GitPullRequest className="h-4 w-4 text-purple-400" />
          </div>
          <div>
            <p className="text-xs font-semibold text-purple-400">PR #43</p>
            <p className="text-[10px] text-white/40">feat/add-auth → main</p>
          </div>
          <span className="ml-auto inline-flex items-center rounded-full bg-emerald-500/15 px-2 py-0.5 text-[10px] font-medium text-emerald-400 border border-emerald-500/20">
            Open
          </span>
        </div>

        <p className="text-sm font-medium text-white/90 mb-1">Add authentication module</p>
        <p className="text-[11px] text-white/40 mb-3">Implements OAuth2 login flow with session management. Closes #42</p>

        {/* Diff stats */}
        <div className="flex items-center gap-3 mb-3">
          <div className="flex items-center gap-1.5">
            <FileCode className="h-3 w-3 text-white/40" />
            <span className="text-[10px] text-white/40">5 files changed</span>
          </div>
          <span className="text-[10px] text-emerald-400 font-mono">+362</span>
          <span className="text-[10px] text-red-400 font-mono">-3</span>
        </div>

        {/* Labels */}
        <div className="flex flex-wrap gap-1.5">
          <motion.span
            initial={{ opacity: 0, scale: 0.8 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ delay: 0.2 }}
            className="inline-flex items-center rounded-full bg-violet-500/20 px-2 py-0.5 text-[10px] font-medium text-violet-400 border border-violet-500/20"
          >
            feature
          </motion.span>
          <motion.span
            initial={{ opacity: 0, scale: 0.8 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ delay: 0.3 }}
            className="inline-flex items-center rounded-full bg-blue-500/20 px-2 py-0.5 text-[10px] font-medium text-blue-400 border border-blue-500/20"
          >
            auth
          </motion.span>
          <motion.span
            initial={{ opacity: 0, scale: 0.8 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ delay: 0.4 }}
            className="inline-flex items-center rounded-full bg-amber-500/20 px-2 py-0.5 text-[10px] font-medium text-amber-400 border border-amber-500/20"
          >
            needs-review
          </motion.span>
        </div>
      </motion.div>

      {/* Reviewers requested */}
      <motion.div
        initial={{ opacity: 0, y: 8 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ type: "spring", stiffness: 200, damping: 25, delay: 0.5 }}
        className="flex items-center gap-2"
      >
        <Users className="h-3.5 w-3.5 text-white/30" />
        <span className="text-[10px] text-white/40">Review requested from</span>
        <div className="flex -space-x-1">
          {["bg-blue-500", "bg-emerald-500"].map((bg, i) => (
            <div
              key={bg}
              className={`h-5 w-5 rounded-full ${bg} border-2 border-black/50 flex items-center justify-center`}
            >
              <span className="text-[8px] text-white font-bold">
                {i === 0 ? "A" : "B"}
              </span>
            </div>
          ))}
        </div>
      </motion.div>
    </div>
  );
}

// Stage 3: Code Review
function CodeReviewVisual({ commentIndex }: { commentIndex: number }) {
  const comments = [
    {
      author: "alice",
      color: "bg-blue-500",
      initial: "A",
      text: "Looks clean! The OAuth2 flow is well-structured.",
      type: "comment" as const,
    },
    {
      author: "bob",
      color: "bg-emerald-500",
      initial: "B",
      text: "Consider adding rate limiting to the login endpoint.",
      type: "suggestion" as const,
    },
    {
      author: "you",
      color: "bg-violet-500",
      initial: "Y",
      text: "Good call! Added rate limiting middleware.",
      type: "reply" as const,
    },
  ];

  return (
    <div className="flex-1 flex flex-col gap-3">
      <div className="flex items-center gap-2 mb-1">
        <MessageSquare className="h-4 w-4 text-amber-400" />
        <span className="text-xs font-semibold text-amber-400">Review Comments</span>
      </div>

      <div className="space-y-2.5">
        {comments.map((comment, i) => (
          <AnimatePresence key={comment.author}>
            {i < commentIndex && (
              <motion.div
                initial={{ opacity: 0, y: 8, scale: 0.95 }}
                animate={{ opacity: 1, y: 0, scale: 1 }}
                transition={{ type: "spring", stiffness: 200, damping: 25 }}
                className={`rounded-lg border p-3 ${
                  comment.type === "suggestion"
                    ? "border-amber-500/20 bg-amber-500/5"
                    : comment.type === "reply"
                      ? "border-violet-500/20 bg-violet-500/5 ml-6"
                      : "border-white/[0.08] bg-white/[0.02]"
                }`}
              >
                <div className="flex items-center gap-2 mb-1.5">
                  <div className={`h-5 w-5 rounded-full ${comment.color} flex items-center justify-center`}>
                    <span className="text-[8px] text-white font-bold">{comment.initial}</span>
                  </div>
                  <span className="text-[10px] font-semibold text-white/60">@{comment.author}</span>
                  {comment.type === "suggestion" && (
                    <span className="text-[9px] text-amber-400 bg-amber-500/10 px-1.5 py-0.5 rounded border border-amber-500/20">
                      suggestion
                    </span>
                  )}
                </div>
                <p className="text-[11px] text-white/50 leading-relaxed">{comment.text}</p>
              </motion.div>
            )}
          </AnimatePresence>
        ))}
      </div>

      {/* Approval badge */}
      <AnimatePresence>
        {commentIndex >= 3 && (
          <motion.div
            initial={{ opacity: 0, scale: 0.8 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
            className="flex items-center gap-2 rounded-lg border border-emerald-500/30 bg-emerald-500/10 px-3 py-2 mt-1"
          >
            <CheckCircle className="h-4 w-4 text-emerald-400" />
            <span className="text-xs font-semibold text-emerald-400">Changes approved</span>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

// Stage 4: CI Pipeline
function CIPipelineVisual({
  jobStates,
}: {
  jobStates: Record<string, "pending" | "running" | "passed">;
}) {
  const jobs = [
    { id: "lint", label: "Lint", icon: <AlertCircle className="h-3 w-3" />, duration: "12s" },
    { id: "typecheck", label: "Type Check", icon: <FileCode className="h-3 w-3" />, duration: "28s" },
    { id: "tests", label: "Unit Tests (48)", icon: <Shield className="h-3 w-3" />, duration: "1m 14s" },
    { id: "build", label: "Build", icon: <Rocket className="h-3 w-3" />, duration: "45s" },
  ];

  const allPassed = Object.values(jobStates).every((s) => s === "passed");

  return (
    <div className="flex-1 flex flex-col gap-3">
      <div className="flex items-center justify-between mb-1">
        <div className="flex items-center gap-2">
          <Shield className="h-4 w-4 text-cyan-400" />
          <span className="text-xs font-semibold text-cyan-400">CI Pipeline</span>
        </div>
        {allPassed && (
          <motion.span
            initial={{ opacity: 0, scale: 0.8 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
            className="text-[10px] text-emerald-400 bg-emerald-500/10 px-2 py-0.5 rounded-full border border-emerald-500/20"
          >
            All checks passed
          </motion.span>
        )}
      </div>

      {/* Parallel job lanes */}
      <div className="grid grid-cols-2 gap-2">
        {jobs.map((job) => {
          const state = jobStates[job.id] ?? "pending";
          return (
            <motion.div
              key={job.id}
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
              className={`rounded-lg border p-2.5 transition-colors ${
                state === "passed"
                  ? "border-emerald-500/30 bg-emerald-500/5"
                  : state === "running"
                    ? "border-cyan-500/30 bg-cyan-500/5"
                    : "border-white/[0.08] bg-white/[0.02]"
              }`}
            >
              <div className="flex items-center gap-2 mb-1.5">
                <CIJobStatusIcon state={state} />
                <span className={`text-[10px] font-mono font-semibold ${
                  state === "passed"
                    ? "text-emerald-400"
                    : state === "running"
                      ? "text-cyan-400"
                      : "text-white/40"
                }`}>
                  {job.label}
                </span>
              </div>

              {/* Progress bar */}
              <div className="h-1 rounded-full bg-white/[0.06] overflow-hidden">
                <motion.div
                  initial={{ width: "0%" }}
                  animate={{
                    width: state === "passed" ? "100%" : state === "running" ? "60%" : "0%",
                  }}
                  transition={{
                    duration: state === "running" ? 1 : 0.4,
                    ease: state === "running" ? "linear" : "easeOut",
                  }}
                  className={`h-full rounded-full ${
                    state === "passed"
                      ? "bg-emerald-500"
                      : state === "running"
                        ? "bg-cyan-500"
                        : "bg-white/10"
                  }`}
                />
              </div>

              {state === "passed" && (
                <motion.span
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  className="text-[9px] text-white/30 mt-1 block"
                >
                  {job.duration}
                </motion.span>
              )}
            </motion.div>
          );
        })}
      </div>
    </div>
  );
}

function CIJobStatusIcon({ state }: { state: "pending" | "running" | "passed" }) {
  if (state === "running") {
    return (
      <motion.div
        animate={{ rotate: 360 }}
        transition={{ duration: 1, repeat: Infinity, ease: "linear" }}
      >
        <Loader2 className="h-3 w-3 text-cyan-400" />
      </motion.div>
    );
  }
  if (state === "passed") {
    return (
      <motion.div
        initial={{ scale: 0 }}
        animate={{ scale: 1 }}
        transition={{ type: "spring", stiffness: 400, damping: 20 }}
      >
        <CheckCircle className="h-3 w-3 text-emerald-400" />
      </motion.div>
    );
  }
  return <CircleDot className="h-3 w-3 text-white/20" />;
}

// Stage 5: Merge & Deploy
function MergeDeployVisual() {
  return (
    <div className="flex-1 flex flex-col items-center justify-center gap-4">
      {/* Merge animation */}
      <div className="flex items-center gap-3">
        <motion.div
          initial={{ opacity: 0, x: -20 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ type: "spring", stiffness: 200, damping: 25 }}
          className="flex items-center gap-2 rounded-full border border-violet-500/20 bg-violet-500/5 px-3 py-1.5"
        >
          <GitBranch className="h-3 w-3 text-violet-400/50" />
          <span className="text-[10px] font-mono text-violet-400/50 line-through">feat/add-auth</span>
        </motion.div>

        <motion.div
          initial={{ scaleX: 0 }}
          animate={{ scaleX: 1 }}
          transition={{ type: "spring", stiffness: 200, damping: 25, delay: 0.2 }}
          className="flex items-center gap-0"
        >
          <div className="w-6 h-0.5 bg-gradient-to-r from-violet-500/40 to-emerald-500/40 rounded-full" />
          <ArrowRight className="h-3 w-3 text-emerald-400/60" />
        </motion.div>

        <motion.div
          initial={{ opacity: 0, scale: 0.8 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ type: "spring", stiffness: 200, damping: 25, delay: 0.3 }}
          className="flex items-center gap-2 rounded-full border border-emerald-500/30 bg-emerald-500/10 px-3 py-1.5"
        >
          <div className="h-3 w-3 rounded-full bg-emerald-400" />
          <span className="text-[10px] font-mono text-emerald-400 font-semibold">main</span>
        </motion.div>
      </div>

      {/* Merged badge */}
      <motion.div
        initial={{ opacity: 0, scale: 0.8 }}
        animate={{ opacity: 1, scale: 1 }}
        transition={{ type: "spring", stiffness: 200, damping: 25, delay: 0.5 }}
        className="flex items-center gap-2.5 rounded-xl border border-purple-500/30 bg-purple-500/10 px-5 py-2.5"
      >
        <GitMerge className="h-4 w-4 text-purple-400" />
        <span className="text-xs font-semibold text-purple-400">PR #43 merged</span>
        <CheckCircle className="h-3.5 w-3.5 text-emerald-400" />
      </motion.div>

      {/* Deploy status */}
      <motion.div
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ type: "spring", stiffness: 200, damping: 25, delay: 0.7 }}
        className="flex items-center gap-3 rounded-lg border border-emerald-500/20 bg-emerald-500/5 px-4 py-2"
      >
        <Rocket className="h-3.5 w-3.5 text-emerald-400" />
        <span className="text-[10px] font-mono text-emerald-400">Deployed to production</span>
        <motion.div
          animate={{ scale: [1, 1.3, 1] }}
          transition={{ duration: 2, repeat: Infinity }}
          className="h-2 w-2 rounded-full bg-emerald-400"
        />
      </motion.div>

      <motion.p
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 0.9 }}
        className="text-[10px] text-white/30 font-mono"
      >
        Issue #42 automatically closed -- Branch deleted
      </motion.p>
    </div>
  );
}

// =============================================================================
// BRANCH FLOW VISUALIZATION (collapsible panel content)
// =============================================================================
function BranchFlowVisualization({ activeStage }: { activeStage: number }) {
  // Branch states per stage
  const branchState = activeStage <= 0 ? "creating" : activeStage <= 4 ? "active" : "merged";

  return (
    <div className="space-y-3">
      {/* Visual branch diagram */}
      <div className="relative h-20">
        {/* Main branch line */}
        <div className="absolute top-4 left-0 right-0 h-0.5 bg-blue-500/30 rounded-full" />

        {/* Commits on main */}
        {[0, 1, 2].map((i) => (
          <motion.div
            key={`main-node-${i}`}
            initial={{ scale: 0 }}
            animate={{ scale: 1 }}
            transition={{ delay: i * 0.1 }}
            className="absolute top-2.5 h-3 w-3 rounded-full bg-blue-500/40 border border-blue-500/60"
            style={{ left: `${10 + i * 15}%` }}
          />
        ))}

        {/* Branch diverge point */}
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: branchState !== "creating" ? 1 : 0.5 }}
          className="absolute top-2.5 h-3 w-3 rounded-full bg-violet-500/60 border border-violet-500/80"
          style={{ left: "55%" }}
        />

        {/* Feature branch line */}
        {branchState !== "creating" && (
          <motion.div
            initial={{ scaleX: 0 }}
            animate={{ scaleX: 1 }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
            className="absolute top-4 h-8 origin-top-left"
            style={{ left: "55%" }}
          >
            {/* Diagonal line done with a rotated div */}
            <svg width="120" height="32" className="absolute">
              <motion.path
                d="M 0 0 Q 20 0 30 16 L 100 16"
                stroke="rgba(139, 92, 246, 0.4)"
                strokeWidth="2"
                fill="none"
                initial={{ pathLength: 0 }}
                animate={{ pathLength: 1 }}
                transition={{ duration: 0.6, delay: 0.2 }}
              />
            </svg>
          </motion.div>
        )}

        {/* Feature branch commits */}
        {branchState !== "creating" && (
          <>
            {[0, 1].map((i) => (
              <motion.div
                key={`feat-node-${i}`}
                initial={{ scale: 0 }}
                animate={{ scale: activeStage >= 1 ? 1 : 0 }}
                transition={{ delay: 0.5 + i * 0.15 }}
                className="absolute top-[26px] h-3 w-3 rounded-full bg-violet-500/40 border border-violet-500/60"
                style={{ left: `${68 + i * 10}%` }}
              />
            ))}
          </>
        )}

        {/* Merge point */}
        {branchState === "merged" && (
          <motion.div
            initial={{ scale: 0, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
          >
            <svg width="60" height="32" className="absolute" style={{ left: "82%", top: "16px" }}>
              <motion.path
                d="M 0 16 Q 20 16 30 0"
                stroke="rgba(139, 92, 246, 0.3)"
                strokeWidth="2"
                fill="none"
                initial={{ pathLength: 0 }}
                animate={{ pathLength: 1 }}
                transition={{ duration: 0.4 }}
              />
            </svg>
            <div
              className="absolute top-2.5 h-3 w-3 rounded-full bg-emerald-500/60 border border-emerald-500/80"
              style={{ left: "90%" }}
            />
          </motion.div>
        )}
      </div>

      {/* Branch status text */}
      <div className="flex items-center justify-between text-[10px]">
        <span className="text-blue-400/60 font-mono">main</span>
        <span className={`font-mono ${
          branchState === "merged" ? "text-emerald-400/60 line-through" : "text-violet-400/60"
        }`}>
          feat/add-auth
        </span>
        <span className={`px-1.5 py-0.5 rounded text-[9px] ${
          branchState === "merged"
            ? "bg-emerald-500/10 text-emerald-400"
            : branchState === "active"
              ? "bg-violet-500/10 text-violet-400"
              : "bg-blue-500/10 text-blue-400"
        }`}>
          {branchState === "merged" ? "merged" : branchState === "active" ? "active" : "creating"}
        </span>
      </div>
    </div>
  );
}

// =============================================================================
// PR DETAIL PANEL (collapsible panel content)
// =============================================================================
function PRDetailPanel({
  activeStage,
  ciJobStates,
}: {
  activeStage: number;
  ciJobStates: Record<string, "pending" | "running" | "passed">;
}) {
  const prCreated = activeStage >= 2;
  const hasReview = activeStage >= 3;
  const ciComplete = activeStage >= 5 || Object.values(ciJobStates).every((s) => s === "passed");
  const merged = activeStage >= 5;

  if (!prCreated) {
    return (
      <div className="flex flex-col items-center justify-center py-6 text-center">
        <GitPullRequest className="h-8 w-8 text-white/10 mb-2" />
        <p className="text-[10px] text-white/30">PR not yet created</p>
        <p className="text-[9px] text-white/20 mt-1">Advance to stage 3 to see PR details</p>
      </div>
    );
  }

  return (
    <div className="space-y-3">
      {/* PR header */}
      <div className="flex items-center gap-2">
        <GitPullRequest className={`h-4 w-4 ${merged ? "text-purple-400" : "text-emerald-400"}`} />
        <span className="text-xs font-semibold text-white/80">Add authentication module</span>
        <span className={`text-[9px] px-1.5 py-0.5 rounded-full border ${
          merged
            ? "bg-purple-500/10 text-purple-400 border-purple-500/20"
            : "bg-emerald-500/10 text-emerald-400 border-emerald-500/20"
        }`}>
          {merged ? "Merged" : "Open"}
        </span>
      </div>

      {/* Stats row */}
      <div className="grid grid-cols-3 gap-2">
        <div className="rounded-lg bg-white/[0.03] border border-white/[0.06] p-2 text-center">
          <p className="text-[10px] text-white/30">Files</p>
          <p className="text-sm font-semibold text-white/70">5</p>
        </div>
        <div className="rounded-lg bg-emerald-500/5 border border-emerald-500/10 p-2 text-center">
          <p className="text-[10px] text-emerald-400/60">Added</p>
          <p className="text-sm font-semibold text-emerald-400">+362</p>
        </div>
        <div className="rounded-lg bg-red-500/5 border border-red-500/10 p-2 text-center">
          <p className="text-[10px] text-red-400/60">Removed</p>
          <p className="text-sm font-semibold text-red-400">-3</p>
        </div>
      </div>

      {/* Checks summary */}
      <div className="space-y-1.5">
        <PRCheckRow
          label="Review"
          status={hasReview ? "passed" : "pending"}
          detail={hasReview ? "Approved by alice" : "Awaiting review"}
        />
        <PRCheckRow
          label="CI / Lint"
          status={activeStage >= 4 ? (ciJobStates["lint"] === "passed" ? "passed" : ciJobStates["lint"] === "running" ? "running" : "pending") : "pending"}
          detail={activeStage >= 4 && ciJobStates["lint"] === "passed" ? "12s" : ""}
        />
        <PRCheckRow
          label="CI / Tests"
          status={activeStage >= 4 ? (ciJobStates["tests"] === "passed" ? "passed" : ciJobStates["tests"] === "running" ? "running" : "pending") : "pending"}
          detail={activeStage >= 4 && ciJobStates["tests"] === "passed" ? "48/48 passed" : ""}
        />
        <PRCheckRow
          label="CI / Build"
          status={activeStage >= 4 ? (ciJobStates["build"] === "passed" ? "passed" : ciJobStates["build"] === "running" ? "running" : "pending") : "pending"}
          detail={activeStage >= 4 && ciJobStates["build"] === "passed" ? "45s" : ""}
        />
      </div>

      {/* Merge readiness */}
      {ciComplete && hasReview && (
        <motion.div
          initial={{ opacity: 0, y: 4 }}
          animate={{ opacity: 1, y: 0 }}
          className={`flex items-center gap-2 rounded-lg px-3 py-2 text-[10px] font-medium ${
            merged
              ? "bg-purple-500/10 text-purple-400 border border-purple-500/20"
              : "bg-emerald-500/10 text-emerald-400 border border-emerald-500/20"
          }`}
        >
          {merged ? (
            <>
              <GitMerge className="h-3 w-3" />
              <span>Squash merged into main</span>
            </>
          ) : (
            <>
              <CheckCircle className="h-3 w-3" />
              <span>Ready to merge -- all checks passed</span>
            </>
          )}
        </motion.div>
      )}
    </div>
  );
}

function PRCheckRow({
  label,
  status,
  detail,
}: {
  label: string;
  status: "pending" | "running" | "passed" | "failed";
  detail: string;
}) {
  return (
    <div className="flex items-center gap-2 py-1">
      {status === "passed" && <CheckCircle className="h-3 w-3 text-emerald-400 shrink-0" />}
      {status === "running" && (
        <motion.div
          animate={{ rotate: 360 }}
          transition={{ duration: 1, repeat: Infinity, ease: "linear" }}
        >
          <Loader2 className="h-3 w-3 text-amber-400 shrink-0" />
        </motion.div>
      )}
      {status === "pending" && <CircleDot className="h-3 w-3 text-white/20 shrink-0" />}
      {status === "failed" && <XCircle className="h-3 w-3 text-red-400 shrink-0" />}
      <span className={`text-[10px] font-mono ${
        status === "passed" ? "text-emerald-400/80" : status === "running" ? "text-amber-400/80" : "text-white/40"
      }`}>
        {label}
      </span>
      {detail && (
        <span className="text-[9px] text-white/20 ml-auto">{detail}</span>
      )}
    </div>
  );
}

// =============================================================================
// ACTIVITY FEED (collapsible panel content)
// =============================================================================
function ActivityFeed({ activeStage }: { activeStage: number }) {
  const events = [
    {
      stage: 0,
      icon: <GitBranch className="h-3 w-3" />,
      color: "text-blue-400",
      bgColor: "bg-blue-500/10",
      text: "Branch feat/add-auth created from main",
      time: "2m ago",
    },
    {
      stage: 1,
      icon: <FileCode className="h-3 w-3" />,
      color: "text-violet-400",
      bgColor: "bg-violet-500/10",
      text: "5 files changed (+362 -3)",
      time: "1m ago",
    },
    {
      stage: 2,
      icon: <GitPullRequest className="h-3 w-3" />,
      color: "text-purple-400",
      bgColor: "bg-purple-500/10",
      text: "PR #43 opened: Add authentication module",
      time: "45s ago",
    },
    {
      stage: 3,
      icon: <MessageSquare className="h-3 w-3" />,
      color: "text-amber-400",
      bgColor: "bg-amber-500/10",
      text: "alice approved -- 2 comments resolved",
      time: "30s ago",
    },
    {
      stage: 4,
      icon: <Shield className="h-3 w-3" />,
      color: "text-cyan-400",
      bgColor: "bg-cyan-500/10",
      text: "All 4 CI checks passed",
      time: "15s ago",
    },
    {
      stage: 5,
      icon: <GitMerge className="h-3 w-3" />,
      color: "text-emerald-400",
      bgColor: "bg-emerald-500/10",
      text: "PR #43 merged -- deployed to production",
      time: "just now",
    },
  ];

  const visibleEvents = events.filter((e) => e.stage <= activeStage);

  return (
    <div className="space-y-0 relative">
      {/* Vertical line */}
      <div className="absolute left-[11px] top-2 bottom-2 w-0.5 bg-white/[0.06]" />

      {visibleEvents.map((event, i) => (
        <motion.div
          key={event.stage}
          initial={{ opacity: 0, x: -8 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ type: "spring", stiffness: 200, damping: 25, delay: i * 0.05 }}
          className="relative flex items-start gap-3 py-1.5"
        >
          <div className={`relative z-10 flex h-6 w-6 shrink-0 items-center justify-center rounded-full ${event.bgColor} border border-white/[0.06]`}>
            <span className={event.color}>{event.icon}</span>
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-[10px] text-white/50 leading-relaxed truncate">{event.text}</p>
            <p className="text-[9px] text-white/20">{event.time}</p>
          </div>
        </motion.div>
      ))}

      {visibleEvents.length === 0 && (
        <div className="text-center py-4">
          <p className="text-[10px] text-white/20">No activity yet</p>
        </div>
      )}
    </div>
  );
}
