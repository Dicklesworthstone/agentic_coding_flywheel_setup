"use client";

import { motion } from "@/components/motion";
import {
  FolderOpen,
  Eye,
  Move,
  Plus,
  Trash2,
  Search,
  CheckCircle2,
  MapPin,
} from "lucide-react";
import {
  Section,
  Paragraph,
  CodeBlock,
  CommandList,
  TipBox,
  Highlight,
  Divider,
  GoalBanner,
  InlineCode,
} from "./lesson-components";

export function LinuxBasicsLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Navigate the filesystem like a pro in 3 minutes.
      </GoalBanner>

      {/* Where Am I */}
      <Section
        title="Where Am I?"
        icon={<MapPin className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph>
          First, let&apos;s find out where you are in the filesystem:
        </Paragraph>
        <div className="mt-6">
          <CodeBlock code="$ pwd" />
        </div>
        <Paragraph>
          This prints your current directory. You should see{" "}
          <InlineCode>/home/ubuntu</InlineCode>.
        </Paragraph>
      </Section>

      <Divider />

      {/* What's Here */}
      <Section
        title="What's Here?"
        icon={<FolderOpen className="h-5 w-5" />}
        delay={0.15}
      >
        <Paragraph>
          List the contents of your current directory:
        </Paragraph>
        <div className="mt-6">
          <CodeBlock code="$ ls" />
        </div>
        <Paragraph>
          With ACFS, this is aliased to <InlineCode>lsd</InlineCode> which shows
          beautiful icons.
        </Paragraph>

        <div className="mt-8">
          <h4 className="text-lg font-semibold text-white mb-4">
            Try these variations:
          </h4>
          <CommandList
            commands={[
              { command: "ll", description: "Long format with details" },
              { command: "la", description: "Show hidden files" },
              { command: "tree", description: "Tree view of directories" },
            ]}
          />
        </div>
      </Section>

      <Divider />

      {/* Moving Around */}
      <Section
        title="Moving Around"
        icon={<Move className="h-5 w-5" />}
        delay={0.2}
      >
        <Paragraph>
          Navigate the filesystem with the <InlineCode>cd</InlineCode> command:
        </Paragraph>

        <div className="mt-6">
          <CommandList
            commands={[
              {
                command: "cd /data/projects",
                description: "Go to the projects directory",
              },
              { command: "cd ~", description: "Go home (shortcut)" },
              { command: "cd ..", description: "Go up one level" },
              { command: "cd -", description: "Go to previous directory" },
            ]}
          />
        </div>

        <div className="mt-8">
          <TipBox variant="tip">
            With <Highlight>zoxide</Highlight> installed, you can use{" "}
            <InlineCode>z projects</InlineCode> to jump to{" "}
            <InlineCode>/data/projects</InlineCode> after visiting it once!
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Creating Things */}
      <Section
        title="Creating Things"
        icon={<Plus className="h-5 w-5" />}
        delay={0.25}
      >
        <Paragraph>Create new directories and files:</Paragraph>

        <div className="mt-6">
          <CommandList
            commands={[
              { command: "mkdir my-project", description: "Create a directory" },
              {
                command: "mkcd my-project",
                description: "Create AND cd into it (ACFS function)",
              },
              { command: "touch file.txt", description: "Create an empty file" },
            ]}
          />
        </div>
      </Section>

      <Divider />

      {/* Viewing Files */}
      <Section
        title="Viewing Files"
        icon={<Eye className="h-5 w-5" />}
        delay={0.3}
      >
        <Paragraph>Read file contents in different ways:</Paragraph>

        <div className="mt-6">
          <CommandList
            commands={[
              {
                command: "cat file.txt",
                description: "Print entire file (aliased to bat)",
              },
              {
                command: "less file.txt",
                description: "Scroll through file (q to quit)",
              },
              { command: "head -20 file.txt", description: "First 20 lines" },
              { command: "tail -20 file.txt", description: "Last 20 lines" },
            ]}
          />
        </div>
      </Section>

      <Divider />

      {/* Deleting Things */}
      <Section
        title="Deleting Things"
        icon={<Trash2 className="h-5 w-5" />}
        delay={0.35}
      >
        <div className="mb-6">
          <TipBox variant="warning">
            There&apos;s no trash can in Linux. <strong>Deleted = gone.</strong>
          </TipBox>
        </div>

        <CommandList
          commands={[
            { command: "rm file.txt", description: "Delete a file" },
            {
              command: "rm -rf directory/",
              description: "Delete a directory (DANGEROUS!)",
            },
          ]}
        />
      </Section>

      <Divider />

      {/* Searching */}
      <Section
        title="Searching"
        icon={<Search className="h-5 w-5" />}
        delay={0.4}
      >
        <Paragraph>Find files and search their contents:</Paragraph>

        <div className="mt-6">
          <CommandList
            commands={[
              {
                command: 'rg "search term"',
                description: "Search file contents (ripgrep)",
              },
              { command: 'fd "pattern"', description: "Find files by name" },
            ]}
          />
        </div>
      </Section>

      <Divider />

      {/* Verify Section */}
      <Section
        title="Verify You Learned It"
        icon={<CheckCircle2 className="h-5 w-5" />}
        delay={0.45}
      >
        <Paragraph>Try this sequence to test your new skills:</Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`$ cd /data/projects
$ mkcd acfs-test
$ pwd
$ touch hello.txt
$ ls
$ cat hello.txt
$ cd ..
$ ls`}
            showLineNumbers
          />
        </div>

        <div className="mt-8">
          <VerificationCard />
        </div>
      </Section>
    </div>
  );
}

// =============================================================================
// VERIFICATION CARD - Success state indicator
// =============================================================================
function VerificationCard() {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      whileHover={{ y: -4, scale: 1.02 }}
      transition={{ delay: 0.6 }}
      className="group relative rounded-2xl border border-emerald-500/30 bg-gradient-to-br from-emerald-500/10 to-teal-500/10 p-6 backdrop-blur-xl overflow-hidden transition-all duration-300 hover:border-emerald-500/50 hover:shadow-lg hover:shadow-emerald-500/20"
    >
      {/* Decorative elements */}
      <div className="absolute top-0 right-0 w-32 h-32 bg-emerald-500/20 rounded-full blur-3xl group-hover:bg-emerald-500/30 transition-colors duration-500" />

      <div className="relative flex items-center gap-4">
        <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-gradient-to-br from-emerald-500 to-teal-500 shadow-lg shadow-emerald-500/30 group-hover:shadow-emerald-500/50 group-hover:scale-110 transition-all duration-300">
          <CheckCircle2 className="h-7 w-7 text-white" />
        </div>
        <div>
          <h4 className="text-lg font-bold text-white group-hover:text-emerald-300 transition-colors">All Commands Work?</h4>
          <p className="text-emerald-300/80 group-hover:text-emerald-200 transition-colors">
            You&apos;re ready for the next lesson!
          </p>
        </div>
      </div>
    </motion.div>
  );
}
