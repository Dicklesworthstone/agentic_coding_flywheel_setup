"use client";

import { motion, AnimatePresence } from "@/components/motion";
import { useState, useCallback, useMemo } from "react";
import {
  FolderOpen,
  Eye,
  Move,
  Plus,
  Trash2,
  Search,
  CheckCircle2,
  MapPin,
  ChevronRight,
  Folder,
  FileText,
  Home,
  Terminal,
  Shield,
  Clock,
  User,
  Users,
  Globe,
  FileCode,
  FileJson,
  FileLock,
  Settings,
  Key,
  HardDrive,
  Database,
  ScrollText,
  Lock,
  Play,
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
        <div className="mt-8">
          <InteractiveFilesystemTree />
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
// INTERACTIVE FILESYSTEM TREE - Immersive filesystem explorer
// =============================================================================

type FileKind =
  | "folder"
  | "file"
  | "config"
  | "script"
  | "key"
  | "log"
  | "json"
  | "lock"
  | "binary";

interface TreeNode {
  name: string;
  type: "folder" | "file";
  kind?: FileKind;
  children?: TreeNode[];
  isHome?: boolean;
  permissions?: string;
  owner?: string;
  group?: string;
  size?: string;
  modified?: string;
  description?: string;
}

interface ScenarioDef {
  id: string;
  label: string;
  icon: React.ReactNode;
  description: string;
  tree: TreeNode;
  defaultExpanded: string[];
  defaultSelected: string;
  terminalLines: string[];
  color: string;
}

// ---- Scenario data ----

const HOME_TREE: TreeNode = {
  name: "/",
  type: "folder",
  permissions: "drwxr-xr-x",
  owner: "root",
  group: "root",
  size: "4.0K",
  modified: "2026-01-15",
  children: [
    {
      name: "home",
      type: "folder",
      permissions: "drwxr-xr-x",
      owner: "root",
      group: "root",
      size: "4.0K",
      modified: "2026-01-15",
      children: [
        {
          name: "ubuntu",
          type: "folder",
          isHome: true,
          permissions: "drwxr-x---",
          owner: "ubuntu",
          group: "ubuntu",
          size: "4.0K",
          modified: "2026-03-12",
          description: "Your home directory. This is where you start.",
          children: [
            {
              name: ".acfs",
              type: "folder",
              permissions: "drwxr-xr-x",
              owner: "ubuntu",
              group: "ubuntu",
              size: "4.0K",
              modified: "2026-03-10",
              description: "ACFS configuration and scripts.",
              children: [
                { name: "config.yaml", type: "file", kind: "config", permissions: "-rw-r--r--", owner: "ubuntu", group: "ubuntu", size: "1.2K", modified: "2026-03-10", description: "Main ACFS configuration." },
                { name: "scripts", type: "folder", permissions: "drwxr-xr-x", owner: "ubuntu", group: "ubuntu", size: "4.0K", modified: "2026-03-08", children: [] },
              ],
            },
            {
              name: ".ssh",
              type: "folder",
              permissions: "drwx------",
              owner: "ubuntu",
              group: "ubuntu",
              size: "4.0K",
              modified: "2026-02-20",
              description: "SSH keys and configuration. Permissions must be strict!",
              children: [
                { name: "authorized_keys", type: "file", kind: "key", permissions: "-rw-------", owner: "ubuntu", group: "ubuntu", size: "580", modified: "2026-02-20", description: "Public keys allowed to connect." },
                { name: "acfs_ed25519", type: "file", kind: "key", permissions: "-rw-------", owner: "ubuntu", group: "ubuntu", size: "411", modified: "2026-02-20", description: "Private SSH key (never share!)." },
                { name: "acfs_ed25519.pub", type: "file", kind: "key", permissions: "-rw-r--r--", owner: "ubuntu", group: "ubuntu", size: "97", modified: "2026-02-20", description: "Public SSH key (safe to share)." },
                { name: "config", type: "file", kind: "config", permissions: "-rw-r--r--", owner: "ubuntu", group: "ubuntu", size: "245", modified: "2026-02-18", description: "SSH client configuration." },
              ],
            },
            {
              name: ".local",
              type: "folder",
              permissions: "drwxr-xr-x",
              owner: "ubuntu",
              group: "ubuntu",
              size: "4.0K",
              modified: "2026-03-01",
              children: [
                { name: "bin", type: "folder", permissions: "drwxr-xr-x", owner: "ubuntu", group: "ubuntu", size: "4.0K", modified: "2026-03-01", description: "User-local executables (on your PATH).", children: [] },
              ],
            },
            { name: ".bashrc", type: "file", kind: "config", permissions: "-rw-r--r--", owner: "ubuntu", group: "ubuntu", size: "3.7K", modified: "2026-03-05", description: "Bash startup script." },
            { name: ".zshrc", type: "file", kind: "config", permissions: "-rw-r--r--", owner: "ubuntu", group: "ubuntu", size: "4.1K", modified: "2026-03-11", description: "Zsh startup script (loaded by ACFS)." },
            { name: ".gitconfig", type: "file", kind: "config", permissions: "-rw-r--r--", owner: "ubuntu", group: "ubuntu", size: "312", modified: "2026-02-28", description: "Git user configuration." },
          ],
        },
      ],
    },
    {
      name: "data",
      type: "folder",
      permissions: "drwxr-xr-x",
      owner: "root",
      group: "root",
      size: "4.0K",
      modified: "2026-03-12",
      children: [
        {
          name: "projects",
          type: "folder",
          permissions: "drwxrwxr-x",
          owner: "ubuntu",
          group: "ubuntu",
          size: "4.0K",
          modified: "2026-03-12",
          description: "All your coding projects live here.",
          children: [
            { name: "my-first-project", type: "folder", permissions: "drwxrwxr-x", owner: "ubuntu", group: "ubuntu", size: "4.0K", modified: "2026-03-12", children: [] },
          ],
        },
      ],
    },
  ],
};

const ETC_TREE: TreeNode = {
  name: "/",
  type: "folder",
  permissions: "drwxr-xr-x",
  owner: "root",
  group: "root",
  size: "4.0K",
  modified: "2026-01-15",
  children: [
    {
      name: "etc",
      type: "folder",
      permissions: "drwxr-xr-x",
      owner: "root",
      group: "root",
      size: "12K",
      modified: "2026-03-12",
      description: "System-wide configuration files.",
      children: [
        { name: "hostname", type: "file", kind: "config", permissions: "-rw-r--r--", owner: "root", group: "root", size: "12", modified: "2026-01-15", description: "Machine hostname." },
        { name: "hosts", type: "file", kind: "config", permissions: "-rw-r--r--", owner: "root", group: "root", size: "221", modified: "2026-01-15", description: "Static hostname-to-IP mappings." },
        { name: "passwd", type: "file", kind: "config", permissions: "-rw-r--r--", owner: "root", group: "root", size: "1.8K", modified: "2026-02-10", description: "User account information." },
        { name: "shadow", type: "file", kind: "lock", permissions: "-rw-r-----", owner: "root", group: "shadow", size: "1.1K", modified: "2026-02-10", description: "Encrypted passwords (restricted!)." },
        { name: "fstab", type: "file", kind: "config", permissions: "-rw-r--r--", owner: "root", group: "root", size: "570", modified: "2026-01-15", description: "Filesystem mount table." },
        {
          name: "ssh",
          type: "folder",
          permissions: "drwxr-xr-x",
          owner: "root",
          group: "root",
          size: "4.0K",
          modified: "2026-01-15",
          description: "SSH daemon configuration.",
          children: [
            { name: "sshd_config", type: "file", kind: "config", permissions: "-rw-r--r--", owner: "root", group: "root", size: "3.3K", modified: "2026-02-15", description: "SSH server settings." },
            { name: "ssh_host_ed25519_key", type: "file", kind: "key", permissions: "-rw-------", owner: "root", group: "root", size: "419", modified: "2026-01-15", description: "Host private key." },
            { name: "ssh_host_ed25519_key.pub", type: "file", kind: "key", permissions: "-rw-r--r--", owner: "root", group: "root", size: "95", modified: "2026-01-15", description: "Host public key." },
          ],
        },
        {
          name: "nginx",
          type: "folder",
          permissions: "drwxr-xr-x",
          owner: "root",
          group: "root",
          size: "4.0K",
          modified: "2026-03-01",
          description: "Nginx web server configuration.",
          children: [
            { name: "nginx.conf", type: "file", kind: "config", permissions: "-rw-r--r--", owner: "root", group: "root", size: "1.5K", modified: "2026-03-01", description: "Main nginx config." },
            { name: "sites-enabled", type: "folder", permissions: "drwxr-xr-x", owner: "root", group: "root", size: "4.0K", modified: "2026-03-01", children: [] },
          ],
        },
        {
          name: "systemd",
          type: "folder",
          permissions: "drwxr-xr-x",
          owner: "root",
          group: "root",
          size: "4.0K",
          modified: "2026-02-20",
          description: "Systemd service unit files.",
          children: [
            { name: "system", type: "folder", permissions: "drwxr-xr-x", owner: "root", group: "root", size: "4.0K", modified: "2026-02-20", children: [] },
          ],
        },
      ],
    },
  ],
};

const VAR_LOG_TREE: TreeNode = {
  name: "/",
  type: "folder",
  permissions: "drwxr-xr-x",
  owner: "root",
  group: "root",
  size: "4.0K",
  modified: "2026-01-15",
  children: [
    {
      name: "var",
      type: "folder",
      permissions: "drwxr-xr-x",
      owner: "root",
      group: "root",
      size: "4.0K",
      modified: "2026-03-12",
      children: [
        {
          name: "log",
          type: "folder",
          permissions: "drwxr-xr-x",
          owner: "root",
          group: "syslog",
          size: "4.0K",
          modified: "2026-03-12",
          description: "System log files. Check here to debug issues.",
          children: [
            { name: "syslog", type: "file", kind: "log", permissions: "-rw-r-----", owner: "syslog", group: "adm", size: "245K", modified: "2026-03-12", description: "Main system log." },
            { name: "auth.log", type: "file", kind: "log", permissions: "-rw-r-----", owner: "syslog", group: "adm", size: "18K", modified: "2026-03-12", description: "Authentication and authorization log." },
            { name: "kern.log", type: "file", kind: "log", permissions: "-rw-r-----", owner: "syslog", group: "adm", size: "67K", modified: "2026-03-12", description: "Kernel messages." },
            { name: "dpkg.log", type: "file", kind: "log", permissions: "-rw-r--r--", owner: "root", group: "root", size: "124K", modified: "2026-03-11", description: "Package install/remove history." },
            { name: "ufw.log", type: "file", kind: "log", permissions: "-rw-r-----", owner: "syslog", group: "adm", size: "8.2K", modified: "2026-03-12", description: "Firewall log entries." },
            {
              name: "nginx",
              type: "folder",
              permissions: "drwxr-x---",
              owner: "www-data",
              group: "adm",
              size: "4.0K",
              modified: "2026-03-12",
              description: "Nginx access and error logs.",
              children: [
                { name: "access.log", type: "file", kind: "log", permissions: "-rw-r-----", owner: "www-data", group: "adm", size: "512K", modified: "2026-03-12", description: "HTTP request log." },
                { name: "error.log", type: "file", kind: "log", permissions: "-rw-r-----", owner: "www-data", group: "adm", size: "3.4K", modified: "2026-03-11", description: "Nginx error log." },
              ],
            },
          ],
        },
      ],
    },
  ],
};

const NAVIGATION_TREE: TreeNode = {
  name: "/",
  type: "folder",
  permissions: "drwxr-xr-x",
  owner: "root",
  group: "root",
  size: "4.0K",
  modified: "2026-01-15",
  children: [
    {
      name: "home",
      type: "folder",
      permissions: "drwxr-xr-x",
      owner: "root",
      group: "root",
      size: "4.0K",
      modified: "2026-01-15",
      children: [
        {
          name: "ubuntu",
          type: "folder",
          isHome: true,
          permissions: "drwxr-x---",
          owner: "ubuntu",
          group: "ubuntu",
          size: "4.0K",
          modified: "2026-03-12",
          children: [],
        },
      ],
    },
    {
      name: "data",
      type: "folder",
      permissions: "drwxr-xr-x",
      owner: "root",
      group: "root",
      size: "4.0K",
      modified: "2026-03-12",
      children: [
        {
          name: "projects",
          type: "folder",
          permissions: "drwxrwxr-x",
          owner: "ubuntu",
          group: "ubuntu",
          size: "4.0K",
          modified: "2026-03-12",
          description: "Your project workspace.",
          children: [
            {
              name: "my-app",
              type: "folder",
              permissions: "drwxrwxr-x",
              owner: "ubuntu",
              group: "ubuntu",
              size: "4.0K",
              modified: "2026-03-12",
              children: [
                { name: "package.json", type: "file", kind: "json", permissions: "-rw-rw-r--", owner: "ubuntu", group: "ubuntu", size: "1.1K", modified: "2026-03-12" },
                { name: "src", type: "folder", permissions: "drwxrwxr-x", owner: "ubuntu", group: "ubuntu", size: "4.0K", modified: "2026-03-12", children: [
                  { name: "index.ts", type: "file", kind: "script", permissions: "-rw-rw-r--", owner: "ubuntu", group: "ubuntu", size: "340", modified: "2026-03-12" },
                  { name: "utils.ts", type: "file", kind: "script", permissions: "-rw-rw-r--", owner: "ubuntu", group: "ubuntu", size: "890", modified: "2026-03-11" },
                ] },
              ],
            },
          ],
        },
      ],
    },
    { name: "tmp", type: "folder", permissions: "drwxrwxrwt", owner: "root", group: "root", size: "4.0K", modified: "2026-03-12", description: "Temporary files. Cleared on reboot.", children: [] },
    { name: "usr", type: "folder", permissions: "drwxr-xr-x", owner: "root", group: "root", size: "4.0K", modified: "2026-01-15", children: [
      { name: "local", type: "folder", permissions: "drwxr-xr-x", owner: "root", group: "root", size: "4.0K", modified: "2026-02-28", children: [
        { name: "bin", type: "folder", permissions: "drwxr-xr-x", owner: "root", group: "root", size: "4.0K", modified: "2026-02-28", description: "Locally installed programs.", children: [] },
      ] },
    ] },
  ],
};

const SEARCH_TREE: TreeNode = {
  name: "/",
  type: "folder",
  permissions: "drwxr-xr-x",
  owner: "root",
  group: "root",
  size: "4.0K",
  modified: "2026-01-15",
  children: [
    {
      name: "data",
      type: "folder",
      permissions: "drwxr-xr-x",
      owner: "root",
      group: "root",
      size: "4.0K",
      modified: "2026-03-12",
      children: [
        {
          name: "projects",
          type: "folder",
          permissions: "drwxrwxr-x",
          owner: "ubuntu",
          group: "ubuntu",
          size: "4.0K",
          modified: "2026-03-12",
          children: [
            {
              name: "webapp",
              type: "folder",
              permissions: "drwxrwxr-x",
              owner: "ubuntu",
              group: "ubuntu",
              size: "4.0K",
              modified: "2026-03-12",
              children: [
                { name: "README.md", type: "file", kind: "file", permissions: "-rw-rw-r--", owner: "ubuntu", group: "ubuntu", size: "2.1K", modified: "2026-03-10" },
                { name: "package.json", type: "file", kind: "json", permissions: "-rw-rw-r--", owner: "ubuntu", group: "ubuntu", size: "1.4K", modified: "2026-03-12" },
                { name: "tsconfig.json", type: "file", kind: "json", permissions: "-rw-rw-r--", owner: "ubuntu", group: "ubuntu", size: "580", modified: "2026-03-09" },
                {
                  name: "src",
                  type: "folder",
                  permissions: "drwxrwxr-x",
                  owner: "ubuntu",
                  group: "ubuntu",
                  size: "4.0K",
                  modified: "2026-03-12",
                  children: [
                    { name: "app.tsx", type: "file", kind: "script", permissions: "-rw-rw-r--", owner: "ubuntu", group: "ubuntu", size: "1.8K", modified: "2026-03-12", description: 'Contains "TODO: add auth"' },
                    { name: "config.ts", type: "file", kind: "script", permissions: "-rw-rw-r--", owner: "ubuntu", group: "ubuntu", size: "620", modified: "2026-03-11", description: 'Contains "TODO: env vars"' },
                    { name: "utils.ts", type: "file", kind: "script", permissions: "-rw-rw-r--", owner: "ubuntu", group: "ubuntu", size: "440", modified: "2026-03-10" },
                  ],
                },
                {
                  name: "tests",
                  type: "folder",
                  permissions: "drwxrwxr-x",
                  owner: "ubuntu",
                  group: "ubuntu",
                  size: "4.0K",
                  modified: "2026-03-11",
                  children: [
                    { name: "app.test.tsx", type: "file", kind: "script", permissions: "-rw-rw-r--", owner: "ubuntu", group: "ubuntu", size: "980", modified: "2026-03-11" },
                  ],
                },
              ],
            },
          ],
        },
      ],
    },
  ],
};

const PERMS_TREE: TreeNode = {
  name: "/",
  type: "folder",
  permissions: "drwxr-xr-x",
  owner: "root",
  group: "root",
  size: "4.0K",
  modified: "2026-01-15",
  children: [
    {
      name: "home",
      type: "folder",
      permissions: "drwxr-xr-x",
      owner: "root",
      group: "root",
      size: "4.0K",
      modified: "2026-01-15",
      children: [
        {
          name: "ubuntu",
          type: "folder",
          isHome: true,
          permissions: "drwxr-x---",
          owner: "ubuntu",
          group: "ubuntu",
          size: "4.0K",
          modified: "2026-03-12",
          description: "Owner: full access. Group: read+exec. Others: none.",
          children: [
            { name: "deploy.sh", type: "file", kind: "script", permissions: "-rwxr-xr-x", owner: "ubuntu", group: "ubuntu", size: "2.3K", modified: "2026-03-10", description: "Executable script. Everyone can run it." },
            { name: "secrets.env", type: "file", kind: "lock", permissions: "-rw-------", owner: "ubuntu", group: "ubuntu", size: "180", modified: "2026-03-08", description: "Only owner can read/write. No one else." },
            { name: "notes.txt", type: "file", kind: "file", permissions: "-rw-r--r--", owner: "ubuntu", group: "ubuntu", size: "540", modified: "2026-03-11", description: "Owner: read+write. Everyone else: read only." },
            { name: "shared-doc.md", type: "file", kind: "file", permissions: "-rw-rw-r--", owner: "ubuntu", group: "devteam", size: "1.2K", modified: "2026-03-12", description: "Owner + group: read+write. Others: read." },
            {
              name: ".ssh",
              type: "folder",
              permissions: "drwx------",
              owner: "ubuntu",
              group: "ubuntu",
              size: "4.0K",
              modified: "2026-02-20",
              description: "Locked down: only owner has any access.",
              children: [
                { name: "id_ed25519", type: "file", kind: "key", permissions: "-rw-------", owner: "ubuntu", group: "ubuntu", size: "411", modified: "2026-02-20", description: "Private key: owner read/write only (required by SSH)." },
                { name: "id_ed25519.pub", type: "file", kind: "key", permissions: "-rw-r--r--", owner: "ubuntu", group: "ubuntu", size: "97", modified: "2026-02-20", description: "Public key: readable by all." },
              ],
            },
          ],
        },
      ],
    },
  ],
};

function buildScenarios(): ScenarioDef[] {
  return [
    {
      id: "home",
      label: "Home Tour",
      icon: <Home className="h-3.5 w-3.5" />,
      description: "Explore your home directory and its dotfiles",
      tree: HOME_TREE,
      defaultExpanded: ["/", "/home", "/home/ubuntu"],
      defaultSelected: "/home/ubuntu",
      terminalLines: ["$ cd ~", "$ ls -la", "# Your home directory contains dotfiles and configs"],
      color: "text-amber-400",
    },
    {
      id: "etc",
      label: "/etc Config",
      icon: <Settings className="h-3.5 w-3.5" />,
      description: "System configuration files in /etc",
      tree: ETC_TREE,
      defaultExpanded: ["/", "/etc"],
      defaultSelected: "/etc",
      terminalLines: ["$ ls /etc/", "# System-wide configuration lives here", "# Most files owned by root"],
      color: "text-blue-400",
    },
    {
      id: "varlog",
      label: "/var/log",
      icon: <ScrollText className="h-3.5 w-3.5" />,
      description: "System logs for debugging",
      tree: VAR_LOG_TREE,
      defaultExpanded: ["/", "/var", "/var/log"],
      defaultSelected: "/var/log",
      terminalLines: ["$ tail -f /var/log/syslog", "# Watch logs in real time", "# Press Ctrl+C to stop"],
      color: "text-emerald-400",
    },
    {
      id: "navigate",
      label: "cd & ls",
      icon: <Move className="h-3.5 w-3.5" />,
      description: "Navigate directories with cd and ls",
      tree: NAVIGATION_TREE,
      defaultExpanded: ["/", "/data", "/data/projects"],
      defaultSelected: "/data/projects",
      terminalLines: ["$ cd /data/projects/my-app", "$ ls -la", "$ cd ..   # go up one level", "$ cd -    # go to previous dir"],
      color: "text-violet-400",
    },
    {
      id: "search",
      label: "find & rg",
      icon: <Search className="h-3.5 w-3.5" />,
      description: "Find files and search contents with find/rg",
      tree: SEARCH_TREE,
      defaultExpanded: ["/", "/data", "/data/projects", "/data/projects/webapp", "/data/projects/webapp/src"],
      defaultSelected: "/data/projects/webapp/src/app.tsx",
      terminalLines: ['$ rg "TODO" /data/projects/webapp/', "src/app.tsx:  // TODO: add auth", "src/config.ts: // TODO: env vars", '$ fd ".tsx" /data/projects/webapp/'],
      color: "text-pink-400",
    },
    {
      id: "permissions",
      label: "Permissions",
      icon: <Shield className="h-3.5 w-3.5" />,
      description: "Understand rwx permission bits",
      tree: PERMS_TREE,
      defaultExpanded: ["/", "/home", "/home/ubuntu"],
      defaultSelected: "/home/ubuntu/deploy.sh",
      terminalLines: ["$ ls -la ~/", "# drwxr-x--- = dir, owner:rwx, group:r-x, other:---", "$ chmod 600 secrets.env", "$ chmod +x deploy.sh"],
      color: "text-orange-400",
    },
  ];
}

function InteractiveFilesystemTree() {
  const scenarios = useMemo(() => buildScenarios(), []);
  const [activeScenarioId, setActiveScenarioId] = useState("home");
  const activeScenario = useMemo(
    () => scenarios.find((s) => s.id === activeScenarioId) ?? scenarios[0],
    [scenarios, activeScenarioId],
  );

  const [expanded, setExpanded] = useState<Set<string>>(
    () => new Set(scenarios[0].defaultExpanded),
  );
  const [selectedPath, setSelectedPath] = useState(scenarios[0].defaultSelected);
  const [terminalHistory, setTerminalHistory] = useState<string[]>(
    () => [...scenarios[0].terminalLines],
  );
  const [showDetail, setShowDetail] = useState(true);

  const switchScenario = useCallback(
    (id: string) => {
      const sc = scenarios.find((s) => s.id === id);
      if (!sc) return;
      setActiveScenarioId(id);
      setExpanded(new Set(sc.defaultExpanded));
      setSelectedPath(sc.defaultSelected);
      setTerminalHistory([...sc.terminalLines]);
    },
    [scenarios],
  );

  const toggleExpand = useCallback((path: string) => {
    setExpanded((prev) => {
      const next = new Set(prev);
      if (next.has(path)) {
        next.delete(path);
      } else {
        next.add(path);
      }
      return next;
    });
  }, []);

  const handleSelect = useCallback(
    (path: string, node: TreeNode) => {
      setSelectedPath(path);
      if (node.type === "folder") {
        toggleExpand(path);
        setTerminalHistory((prev) => [...prev.slice(-5), `$ cd ${path}`, `$ ls`]);
      } else {
        const dir = path.substring(0, path.lastIndexOf("/")) || "/";
        setTerminalHistory((prev) => [...prev.slice(-5), `$ ls -la ${dir}/${node.name}`]);
      }
    },
    [toggleExpand],
  );

  const selectedNode = useMemo(
    () => findNode(activeScenario.tree, selectedPath),
    [activeScenario.tree, selectedPath],
  );

  // Build breadcrumb segments from the selected path
  const breadcrumbs = useMemo(() => {
    if (selectedPath === "/") return ["/"];
    return ["/", ...selectedPath.split("/").filter(Boolean)];
  }, [selectedPath]);

  return (
    <motion.div
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: 0.2, duration: 0.5 }}
      className="rounded-2xl border border-white/10 bg-white/[0.03] backdrop-blur-xl overflow-hidden"
    >
      {/* Header */}
      <div className="flex items-center justify-between border-b border-white/10 px-5 py-3">
        <div className="flex items-center gap-2">
          <FolderOpen className="h-4 w-4 text-primary" />
          <span className="text-sm font-medium text-white/80">
            Filesystem Explorer
          </span>
          <span className="text-[10px] text-white/30 ml-1">
            Click directories to explore
          </span>
        </div>
        <div className="flex items-center gap-1.5">
          <div className="h-2.5 w-2.5 rounded-full bg-red-500/60" />
          <div className="h-2.5 w-2.5 rounded-full bg-yellow-500/60" />
          <div className="h-2.5 w-2.5 rounded-full bg-green-500/60" />
        </div>
      </div>

      {/* Scenario selector tabs */}
      <div className="border-b border-white/[0.06] px-3 py-2 flex gap-1.5 overflow-x-auto scrollbar-hide">
        {scenarios.map((sc) => {
          const isActive = sc.id === activeScenarioId;
          return (
            <button
              key={sc.id}
              onClick={() => switchScenario(sc.id)}
              className={`flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-medium whitespace-nowrap transition duration-200 ${
                isActive
                  ? "bg-white/10 text-white border border-white/15 shadow-sm"
                  : "text-white/40 hover:text-white/70 hover:bg-white/[0.04] border border-transparent"
              }`}
            >
              <span className={isActive ? sc.color : ""}>{sc.icon}</span>
              {sc.label}
            </button>
          );
        })}
      </div>

      {/* Scenario description */}
      <AnimatePresence mode="wait">
        <motion.div
          key={activeScenarioId}
          initial={{ opacity: 0, height: 0 }}
          animate={{ opacity: 1, height: "auto" }}
          exit={{ opacity: 0, height: 0 }}
          transition={{ duration: 0.2 }}
          className="overflow-hidden"
        >
          <div className="px-5 py-2 border-b border-white/[0.04] bg-white/[0.01]">
            <p className="text-xs text-white/40">{activeScenario.description}</p>
          </div>
        </motion.div>
      </AnimatePresence>

      {/* Breadcrumb trail */}
      <div className="border-b border-white/5 px-5 py-2.5 flex items-center gap-1 overflow-x-auto scrollbar-hide">
        <span className="text-xs text-white/40 mr-1 shrink-0">Path:</span>
        <AnimatePresence mode="popLayout">
          {breadcrumbs.map((segment, i) => (
            <motion.span
              key={`${activeScenarioId}-${segment}-${i}`}
              initial={{ opacity: 0, x: -8 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: 8 }}
              transition={{ delay: i * 0.04, duration: 0.15 }}
              className="flex items-center gap-1 shrink-0"
            >
              {i > 0 && (
                <ChevronRight className="h-3 w-3 text-white/20" />
              )}
              <span
                className={`text-xs font-mono px-1.5 py-0.5 rounded ${
                  i === breadcrumbs.length - 1
                    ? "text-primary bg-primary/10 border border-primary/20"
                    : "text-white/50 hover:text-white/70 cursor-default"
                }`}
              >
                {segment}
              </span>
            </motion.span>
          ))}
        </AnimatePresence>
      </div>

      {/* Main content area: tree + detail panel */}
      <div className="flex flex-col md:flex-row">
        {/* Tree view */}
        <div className="flex-1 p-4 font-mono text-sm max-h-96 overflow-y-auto border-r border-white/[0.06]">
          <AnimatePresence mode="wait">
            <motion.div
              key={activeScenarioId}
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.15 }}
            >
              <TreeNodeRow
                node={activeScenario.tree}
                path="/"
                depth={0}
                expanded={expanded}
                selectedPath={selectedPath}
                onSelect={handleSelect}
              />
            </motion.div>
          </AnimatePresence>
        </div>

        {/* Detail panel */}
        <AnimatePresence>
          {showDetail && selectedNode && (
            <motion.div
              initial={{ width: 0, opacity: 0 }}
              animate={{ width: "auto", opacity: 1 }}
              exit={{ width: 0, opacity: 0 }}
              transition={{ duration: 0.25 }}
              className="w-full md:w-72 shrink-0 overflow-hidden"
            >
              <FileDetailPanel
                node={selectedNode}
                path={selectedPath}
                isPermissionsScenario={activeScenarioId === "permissions"}
              />
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      {/* Toggle detail panel */}
      <div className="border-t border-white/[0.06] px-5 py-1.5 flex justify-end">
        <button
          onClick={() => setShowDetail((p) => !p)}
          className="text-[10px] text-white/30 hover:text-white/60 transition-colors"
        >
          {showDetail ? "Hide details" : "Show details"}
        </button>
      </div>

      {/* Terminal simulation */}
      <div className="border-t border-white/10 bg-black/30 px-5 py-3">
        <div className="flex items-center gap-2 mb-2">
          <Terminal className="h-3.5 w-3.5 text-emerald-500/60" />
          <span className="text-xs text-white/30 font-mono">terminal</span>
          <div className="flex-1" />
          <button
            onClick={() => setTerminalHistory([...activeScenario.terminalLines])}
            className="text-[10px] text-white/20 hover:text-white/50 transition-colors flex items-center gap-1"
          >
            <Play className="h-2.5 w-2.5" />
            reset
          </button>
        </div>
        <div className="space-y-0.5 max-h-28 overflow-y-auto">
          <AnimatePresence initial={false}>
            {terminalHistory.slice(-6).map((line, i) => (
              <motion.div
                key={`${line}-${terminalHistory.length - 6 + i}`}
                initial={{ opacity: 0, y: 6 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.12, delay: i * 0.03 }}
                className={`font-mono text-xs ${
                  line.startsWith("$")
                    ? "text-emerald-400/80"
                    : line.startsWith("#")
                      ? "text-white/25 italic"
                      : "text-white/50"
                }`}
              >
                {line}
              </motion.div>
            ))}
          </AnimatePresence>
        </div>
      </div>
    </motion.div>
  );
}

// =============================================================================
// FILE DETAIL PANEL - Shows metadata for the selected file/folder
// =============================================================================

function FileDetailPanel({
  node,
  path,
  isPermissionsScenario,
}: {
  node: TreeNode;
  path: string;
  isPermissionsScenario: boolean;
}) {
  return (
    <div className="p-4 space-y-4 h-full bg-white/[0.01]">
      {/* File/folder name and icon */}
      <div className="flex items-center gap-2.5">
        <div className={`flex h-9 w-9 items-center justify-center rounded-xl ${
          node.type === "folder"
            ? "bg-amber-500/15 text-amber-400"
            : "bg-blue-500/15 text-blue-400"
        }`}>
          {getFileIcon(node, true)}
        </div>
        <div className="min-w-0 flex-1">
          <p className="text-sm font-semibold text-white truncate">{node.name}</p>
          <p className="text-[10px] text-white/30 truncate">{path}</p>
        </div>
      </div>

      {/* Description */}
      {node.description && (
        <motion.p
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          className="text-xs text-white/50 leading-relaxed border-l-2 border-primary/30 pl-3"
        >
          {node.description}
        </motion.p>
      )}

      {/* Metadata rows */}
      <div className="space-y-2">
        {node.permissions && (
          <DetailRow icon={<Shield className="h-3 w-3" />} label="Perms" value={node.permissions} />
        )}
        {node.owner && (
          <DetailRow icon={<User className="h-3 w-3" />} label="Owner" value={`${node.owner}:${node.group ?? ""}`} />
        )}
        {node.size && (
          <DetailRow icon={<HardDrive className="h-3 w-3" />} label="Size" value={node.size} />
        )}
        {node.modified && (
          <DetailRow icon={<Clock className="h-3 w-3" />} label="Modified" value={node.modified} />
        )}
      </div>

      {/* Permissions breakdown (detailed in permissions scenario) */}
      {node.permissions && isPermissionsScenario && (
        <PermissionsBreakdown permissions={node.permissions} />
      )}
    </div>
  );
}

function DetailRow({
  icon,
  label,
  value,
}: {
  icon: React.ReactNode;
  label: string;
  value: string;
}) {
  return (
    <div className="flex items-center gap-2 text-xs">
      <span className="text-white/25">{icon}</span>
      <span className="text-white/40 w-14 shrink-0">{label}</span>
      <span className="text-white/70 font-mono truncate">{value}</span>
    </div>
  );
}

// =============================================================================
// PERMISSIONS BREAKDOWN - Visual rwx display
// =============================================================================

function PermissionsBreakdown({ permissions }: { permissions: string }) {
  // e.g. "-rwxr-xr--" or "drwxr-x---"
  const chars = permissions.split("");
  if (chars.length < 10) return null;

  const typeChar = chars[0];
  const owner = chars.slice(1, 4);
  const group = chars.slice(4, 7);
  const other = chars.slice(7, 10);

  const labels = ["r", "w", "x"];
  const descriptions: Record<string, string> = {
    r: "read",
    w: "write",
    x: "execute",
  };

  return (
    <motion.div
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.25, delay: 0.1 }}
      className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-3 space-y-3"
    >
      <div className="flex items-center gap-2 mb-1">
        <Lock className="h-3 w-3 text-orange-400/70" />
        <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">
          Permission Breakdown
        </span>
      </div>

      {/* Type indicator */}
      <div className="text-[10px] text-white/30">
        Type: <span className="text-white/60 font-mono">{typeChar}</span>
        {" = "}
        <span className="text-white/50">
          {typeChar === "d" ? "directory" : typeChar === "l" ? "symlink" : "file"}
        </span>
      </div>

      {/* Three columns: owner, group, other */}
      <div className="grid grid-cols-3 gap-2">
        <PermColumn label="Owner" bits={owner} labels={labels} descriptions={descriptions} color="text-emerald-400" icon={<User className="h-3 w-3" />} />
        <PermColumn label="Group" bits={group} labels={labels} descriptions={descriptions} color="text-blue-400" icon={<Users className="h-3 w-3" />} />
        <PermColumn label="Other" bits={other} labels={labels} descriptions={descriptions} color="text-orange-400" icon={<Globe className="h-3 w-3" />} />
      </div>
    </motion.div>
  );
}

function PermColumn({
  label,
  bits,
  labels,
  descriptions,
  color,
  icon,
}: {
  label: string;
  bits: string[];
  labels: string[];
  descriptions: Record<string, string>;
  color: string;
  icon: React.ReactNode;
}) {
  return (
    <div className="space-y-1.5">
      <div className={`flex items-center gap-1 text-[10px] font-semibold ${color}`}>
        {icon}
        {label}
      </div>
      {bits.map((bit, i) => {
        const isSet = bit !== "-";
        return (
          <div
            key={`${labels[i]}-${i}`}
            className={`flex items-center gap-1 text-[10px] rounded px-1 py-0.5 ${
              isSet ? "bg-white/[0.04]" : ""
            }`}
          >
            <span
              className={`font-mono font-bold w-3 text-center ${
                isSet ? color : "text-white/15"
              }`}
            >
              {bit}
            </span>
            <span className={`${isSet ? "text-white/50" : "text-white/15"}`}>
              {descriptions[labels[i]]}
            </span>
          </div>
        );
      })}
    </div>
  );
}

// =============================================================================
// TREE NODE ROW - Individual row in the file tree
// =============================================================================

function TreeNodeRow({
  node,
  path,
  depth,
  expanded,
  selectedPath,
  onSelect,
}: {
  node: TreeNode;
  path: string;
  depth: number;
  expanded: Set<string>;
  selectedPath: string;
  onSelect: (path: string, node: TreeNode) => void;
}) {
  const isExpanded = expanded.has(path);
  const isSelected = selectedPath === path;
  const isFolder = node.type === "folder";
  const hasChildren = isFolder && node.children && node.children.length > 0;

  return (
    <div>
      <motion.button
        onClick={() => onSelect(path, node)}
        whileHover={{ x: 2 }}
        transition={{ duration: 0.1 }}
        className={`flex w-full items-center gap-2 rounded-lg px-2 py-1 text-left transition-colors ${
          isSelected
            ? "bg-primary/10 text-primary"
            : "text-white/70 hover:bg-white/5 hover:text-white"
        }`}
        style={{ paddingLeft: `${depth * 18 + 8}px` }}
      >
        {/* Expand/collapse chevron for folders */}
        {isFolder ? (
          <motion.span
            animate={{ rotate: isExpanded ? 90 : 0 }}
            transition={{ duration: 0.15 }}
            className="flex shrink-0 items-center"
          >
            <ChevronRight className="h-3 w-3 text-white/30" />
          </motion.span>
        ) : (
          <span className="w-3 shrink-0" />
        )}

        {/* Icon */}
        {getFileIcon(node, false, isSelected)}

        {/* Name */}
        <span
          className={`truncate ${
            isFolder ? "font-medium" : "font-normal"
          } ${node.isHome ? "text-amber-300" : ""}`}
        >
          {node.name}
          {isFolder && "/"}
        </span>

        {/* Home badge */}
        {node.isHome && (
          <span className="ml-1 rounded-full bg-amber-500/15 px-2 py-0.5 text-[10px] font-medium text-amber-400/80 border border-amber-500/20">
            ~ home
          </span>
        )}

        {/* File size hint (compact) */}
        {!isFolder && node.size && (
          <span className="ml-auto text-[10px] text-white/20 font-mono shrink-0">
            {node.size}
          </span>
        )}

        {/* Permission hint on folder */}
        {isFolder && node.permissions && (
          <span className="ml-auto text-[10px] text-white/15 font-mono shrink-0 hidden sm:inline">
            {node.permissions}
          </span>
        )}
      </motion.button>

      {/* Children with animated expand/collapse */}
      <AnimatePresence initial={false}>
        {isExpanded && hasChildren && (
          <motion.div
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: "auto", opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={{ duration: 0.2, ease: "easeInOut" }}
            className="overflow-hidden"
          >
            {/* Tree line */}
            <div
              className="relative"
              style={{ marginLeft: `${depth * 18 + 19}px` }}
            >
              <div className="absolute left-0 top-0 bottom-0 w-px bg-white/[0.06]" />
              <div className="pl-0">
                {node.children!.map((child) => {
                  const childPath =
                    path === "/"
                      ? `/${child.name}`
                      : `${path}/${child.name}`;
                  return (
                    <TreeNodeRow
                      key={childPath}
                      node={child}
                      path={childPath}
                      depth={depth + 1}
                      expanded={expanded}
                      selectedPath={selectedPath}
                      onSelect={onSelect}
                    />
                  );
                })}
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

// =============================================================================
// FILE ICON HELPER
// =============================================================================

function getFileIcon(node: TreeNode, large: boolean, isSelected?: boolean) {
  const size = large ? "h-4.5 w-4.5" : "h-3.5 w-3.5";
  const selectedColor = "text-primary";

  if (node.type === "folder") {
    if (node.isHome) {
      return <Home className={`${size} shrink-0 ${isSelected ? selectedColor : "text-amber-400/80"}`} />;
    }
    return <Folder className={`${size} shrink-0 ${isSelected ? selectedColor : "text-amber-400/80"}`} />;
  }

  const kind = node.kind ?? "file";
  switch (kind) {
    case "config":
      return <Settings className={`${size} shrink-0 ${isSelected ? selectedColor : "text-blue-400/70"}`} />;
    case "script":
      return <FileCode className={`${size} shrink-0 ${isSelected ? selectedColor : "text-green-400/70"}`} />;
    case "key":
      return <Key className={`${size} shrink-0 ${isSelected ? selectedColor : "text-yellow-400/70"}`} />;
    case "log":
      return <ScrollText className={`${size} shrink-0 ${isSelected ? selectedColor : "text-emerald-400/70"}`} />;
    case "json":
      return <FileJson className={`${size} shrink-0 ${isSelected ? selectedColor : "text-orange-400/70"}`} />;
    case "lock":
      return <FileLock className={`${size} shrink-0 ${isSelected ? selectedColor : "text-red-400/70"}`} />;
    case "binary":
      return <Database className={`${size} shrink-0 ${isSelected ? selectedColor : "text-purple-400/70"}`} />;
    default:
      return <FileText className={`${size} shrink-0 ${isSelected ? selectedColor : "text-white/40"}`} />;
  }
}

// =============================================================================
// FIND NODE UTILITY
// =============================================================================

function findNode(root: TreeNode, targetPath: string): TreeNode | null {
  if (targetPath === "/") return root;
  const segments = targetPath.split("/").filter(Boolean);
  let current: TreeNode | undefined = root;
  for (const seg of segments) {
    current = current?.children?.find((c) => c.name === seg);
    if (!current) return null;
  }
  return current ?? null;
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
      className="group relative rounded-2xl border border-emerald-500/30 bg-gradient-to-br from-emerald-500/10 to-teal-500/10 p-6 backdrop-blur-xl overflow-hidden transition duration-300 hover:border-emerald-500/50 hover:shadow-lg hover:shadow-emerald-500/20"
    >
      {/* Decorative elements */}
      <div className="absolute top-0 right-0 w-32 h-32 bg-emerald-500/20 rounded-full blur-3xl group-hover:bg-emerald-500/30 transition-colors duration-500" />

      <div className="relative flex items-center gap-4">
        <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-gradient-to-br from-emerald-500 to-teal-500 shadow-lg shadow-emerald-500/30 group-hover:shadow-emerald-500/50 group-hover:scale-110 transition duration-300">
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
