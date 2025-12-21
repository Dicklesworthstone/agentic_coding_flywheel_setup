/**
 * Jargon Dictionary
 *
 * Defines technical terms with simple, intuitive explanations
 * for both experts and beginners.
 */

export interface JargonTerm {
  /** The technical term */
  term: string;
  /** One-line definition (for quick reference) */
  short: string;
  /** Longer explanation in simple language */
  long: string;
  /** Optional: "Think of it like..." analogy */
  analogy?: string;
  /** Optional: related terms */
  related?: string[];
}

/**
 * Dictionary of technical terms used throughout the site.
 * Keys are lowercase for easy lookup.
 */
export const jargonDictionary: Record<string, JargonTerm> = {
  // Core concepts
  vps: {
    term: "VPS",
    short: "Virtual Private Server — a remote computer you rent",
    long: "A VPS is like renting a computer that lives in a data center somewhere. You connect to it over the internet and use it as if it were sitting right in front of you. It's always on, always connected, and you have full control.",
    analogy: "Think of it like renting an apartment instead of buying a house. You get your own private space (the server) in a big building (the data center), and someone else handles the maintenance.",
  },

  ssh: {
    term: "SSH",
    short: "Secure Shell — how you securely connect to remote computers",
    long: "SSH is a way to securely log into another computer over the internet. When you SSH into your VPS, it's like opening a window into that remote computer. Everything you type happens there, not on your laptop.",
    analogy: "Imagine a secure phone line that lets you talk directly to your VPS. Nobody can eavesdrop, and you can give it commands as if you were sitting right there.",
  },

  terminal: {
    term: "Terminal",
    short: "A text-based interface to control your computer",
    long: "The terminal (also called command line or console) is a way to control your computer by typing commands instead of clicking buttons. It might look old-school, but it's incredibly powerful once you learn the basics.",
    analogy: "Instead of pointing and clicking, you type what you want. It's like texting your computer instead of using a touch screen.",
  },

  curl: {
    term: "curl",
    short: "A tool to download things from the internet via command line",
    long: "curl is a command that fetches content from URLs. When you see 'curl ... | bash', it means: download a script from the internet and run it immediately. It's like clicking a download link and running the installer in one step.",
  },

  bash: {
    term: "bash",
    short: "The default program that runs commands on Linux",
    long: "Bash is a shell — the program that interprets what you type and tells the computer what to do. When you open a terminal, you're usually talking to bash (or a similar shell like zsh).",
    analogy: "Bash is like a translator between you and your computer. You type in human-readable commands, and bash converts them into actions.",
  },

  zsh: {
    term: "zsh",
    short: "A modern, feature-rich shell (alternative to bash)",
    long: "Zsh is like bash but with more features: better auto-completion, spelling correction, and thousands of plugins. We install it because it makes working in the terminal much more pleasant.",
    related: ["bash", "oh-my-zsh"],
  },

  "oh-my-zsh": {
    term: "oh-my-zsh",
    short: "A framework that makes zsh beautiful and powerful",
    long: "Oh My Zsh is a collection of themes, plugins, and helpers for zsh. It adds colors, icons, Git status, and hundreds of shortcuts that make the terminal experience much nicer.",
    related: ["zsh", "powerlevel10k"],
  },

  powerlevel10k: {
    term: "powerlevel10k",
    short: "A beautiful, fast theme for zsh",
    long: "Powerlevel10k makes your terminal prompt look amazing — showing the current folder, Git branch, and more, all with colors and icons. It's highly customizable and won't slow you down.",
    related: ["zsh", "oh-my-zsh"],
  },

  tmux: {
    term: "tmux",
    short: "Terminal multiplexer — multiple windows in one terminal",
    long: "tmux lets you split your terminal into multiple panes and windows, and keeps them running even if you disconnect. You can have one pane for coding, another for running tests, and switch between them instantly.",
    analogy: "Like having multiple browser tabs, but for your terminal. And unlike browser tabs, they keep running even if you close your laptop.",
  },

  // Languages and tools
  bun: {
    term: "bun",
    short: "A super-fast JavaScript runtime and package manager",
    long: "Bun is like Node.js but much faster. It runs JavaScript code and manages packages (libraries of code). We use it because it's blazing fast and combines several tools into one.",
    related: ["npm", "node"],
  },

  uv: {
    term: "uv",
    short: "A lightning-fast Python package manager",
    long: "uv replaces pip (Python's default package manager) with something 10-100x faster. Installing Python libraries that used to take minutes now takes seconds.",
    related: ["pip", "python"],
  },

  rust: {
    term: "Rust",
    short: "A fast, safe programming language",
    long: "Rust is a modern programming language focused on speed and safety. Many of the tools we install (like ripgrep) are written in Rust, which is why they're so fast.",
  },

  go: {
    term: "Go",
    short: "A simple, efficient programming language by Google",
    long: "Go (also called Golang) is a language designed for building fast, reliable software. It's popular for backend services and command-line tools.",
  },

  ripgrep: {
    term: "ripgrep",
    short: "Super-fast code search tool",
    long: "Ripgrep (command: rg) searches through your code files incredibly fast. It's like the search function in your text editor, but it works across thousands of files in milliseconds.",
    analogy: "Imagine Control+F, but for your entire codebase, and 10x faster.",
  },

  lazygit: {
    term: "lazygit",
    short: "A visual interface for Git",
    long: "Lazygit gives you a visual way to work with Git — staging files, making commits, viewing history. Instead of memorizing Git commands, you can see everything and use keyboard shortcuts.",
    related: ["git"],
  },

  fzf: {
    term: "fzf",
    short: "Fuzzy finder — search anything by typing part of it",
    long: "fzf lets you search through lists by typing just a few characters. Looking for a file? Type a few letters and it shows matching files instantly. Works with files, command history, and more.",
    analogy: "Like autocomplete, but smarter. Type 'foo' and it finds 'my-foo-file.txt'.",
  },

  zoxide: {
    term: "zoxide",
    short: "Smart directory navigation — jump to folders instantly",
    long: "Zoxide remembers which folders you visit and lets you jump to them by typing just part of the name. Instead of 'cd /very/long/path/to/project', just type 'z project'.",
    analogy: "Like browser bookmarks, but for folders. And it learns your favorites automatically.",
  },

  atuin: {
    term: "atuin",
    short: "Smart shell history search",
    long: "Atuin replaces the basic command history with a searchable, synced database. Find that command you ran last week by typing a few keywords. Works across multiple machines.",
  },

  lsd: {
    term: "lsd",
    short: "Modern 'ls' replacement with colors and icons",
    long: "lsd is like the 'ls' command (which lists files) but with colors, icons, and better formatting. It makes it easier to see what's in a folder at a glance.",
  },

  direnv: {
    term: "direnv",
    short: "Automatic environment variables per directory",
    long: "direnv automatically loads environment variables when you enter a directory. This means each project can have its own settings without you having to remember to set them up.",
  },

  // Security & technical concepts
  idempotent: {
    term: "Idempotent",
    short: "Safe to run multiple times with the same result",
    long: "An idempotent operation gives the same result no matter how many times you run it. Our installer is idempotent — you can run it twice and it won't break anything or duplicate work.",
    analogy: "Like pressing an elevator button multiple times. The elevator comes once, regardless of how many times you press.",
  },

  sha256: {
    term: "SHA256",
    short: "A security fingerprint for files",
    long: "SHA256 creates a unique 'fingerprint' for any file. If even one character changes, the fingerprint changes completely. We use this to verify that downloaded files haven't been tampered with.",
    analogy: "Like a wax seal on a letter — if it's broken, you know someone opened it.",
  },

  sudo: {
    term: "sudo",
    short: "Run a command as administrator",
    long: "Sudo means 'super-user do'. It lets you run commands with administrator (root) privileges. Some operations — like installing software — require these elevated permissions.",
    analogy: "It's like saying 'pretty please with admin powers' to your computer.",
  },

  // AI concepts
  agentic: {
    term: "Agentic",
    short: "AI that takes action on your behalf",
    long: "Agentic AI doesn't just answer questions — it takes actions. It can write code, run commands, edit files, and complete tasks with minimal supervision. You give it a goal, and it figures out the steps.",
    analogy: "Regular AI is like asking a librarian for information. Agentic AI is like hiring an assistant who actually does the work.",
  },

  "ai-agents": {
    term: "AI Agents",
    short: "AI programs that can take actions autonomously",
    long: "AI agents are programs powered by large language models (like GPT or Claude) that can write code, run commands, browse files, and complete complex tasks. They're like having a tireless coding assistant.",
    related: ["agentic", "claude-code", "codex"],
  },

  "claude-code": {
    term: "Claude Code",
    short: "Anthropic's AI coding assistant",
    long: "Claude Code is an AI agent from Anthropic (the company behind Claude). It can write code, edit files, run tests, and help you build software. It's designed to be helpful, harmless, and honest.",
    related: ["ai-agents", "codex", "gemini-cli"],
  },

  codex: {
    term: "Codex CLI",
    short: "OpenAI's AI coding tool",
    long: "Codex CLI is OpenAI's command-line coding assistant. Built on GPT models, it can write code, explain concepts, and help debug issues. Works directly in your terminal.",
    related: ["ai-agents", "claude-code"],
  },

  "gemini-cli": {
    term: "Gemini CLI",
    short: "Google's AI coding assistant",
    long: "Gemini CLI brings Google's Gemini AI model to your terminal. It can help write code, answer questions, and assist with development tasks.",
    related: ["ai-agents", "claude-code", "codex"],
  },

  // Other tools
  git: {
    term: "Git",
    short: "Version control — track changes to your code",
    long: "Git tracks every change you make to your code. You can see what changed, when, and by whom. If something breaks, you can go back to a working version. It's essential for any serious development.",
    analogy: "Like 'undo' on steroids. Every save is remembered forever, and you can go back to any point.",
  },

  "cloud-server": {
    term: "Cloud Server",
    short: "A computer running in a data center you access remotely",
    long: "A cloud server is a computer that runs 24/7 in a data center. You rent it by the hour or month from providers like DigitalOcean, Hetzner, or AWS. You connect to it over the internet using SSH.",
    related: ["vps", "ssh"],
  },

  ubuntu: {
    term: "Ubuntu",
    short: "A popular, beginner-friendly Linux operating system",
    long: "Ubuntu is one of the most popular versions of Linux. It's free, well-documented, and has a huge community. Most VPS providers offer it as a default option, and it's what our installer is designed for.",
    related: ["linux", "vps"],
  },

  linux: {
    term: "Linux",
    short: "A free, open-source operating system",
    long: "Linux is the operating system that powers most servers on the internet. Unlike Windows or macOS, it's free and open-source. The terminal is central to how you use it.",
    related: ["ubuntu", "bash"],
  },

  // Flywheel-specific
  ntm: {
    term: "NTM",
    short: "Named Tmux Manager — agent orchestration cockpit",
    long: "NTM (Named Tmux Manager) makes it easy to organize and run multiple AI agents in tmux sessions. It's like a control center for your AI assistants, letting you see what each one is doing.",
    related: ["tmux", "ai-agents"],
  },

  "agent-mail": {
    term: "Agent Mail",
    short: "Coordination system for multiple AI agents",
    long: "Agent Mail provides a messaging system for AI agents to communicate with each other. When you have multiple agents working on a project, they can coordinate through Agent Mail to avoid conflicts.",
    related: ["ai-agents", "ntm"],
  },

  flywheel: {
    term: "Flywheel",
    short: "A self-reinforcing system that builds momentum",
    long: "A flywheel is a concept where each component makes the others work better. Our 'Agentic Coding Flywheel' means each tool enhances the others — better search makes agents smarter, smarter agents find more, and so on.",
    analogy: "Like a spinning wheel that gets faster with each push. Once it's going, it takes less effort to keep it moving.",
  },

  api: {
    term: "API",
    short: "Application Programming Interface — how programs talk to each other",
    long: "An API is a set of rules that lets different programs communicate. When the AI agent needs to look something up or perform an action, it often uses APIs to connect to other services.",
    analogy: "Like a menu at a restaurant. It tells you what you can order (request) and what you'll get back (response).",
  },

  cli: {
    term: "CLI",
    short: "Command Line Interface — a text-based program",
    long: "A CLI is a program you interact with by typing commands rather than clicking buttons. Most developer tools are CLIs because they're faster to use once you learn them.",
    related: ["terminal", "bash"],
  },

  "open-source": {
    term: "Open-source",
    short: "Software with publicly available source code",
    long: "Open-source software has its code freely available for anyone to view, modify, and share. All the tools we install are open-source, which means they're free and you can trust what they do.",
    analogy: "Like a recipe that anyone can read, modify, and share — no secrets.",
  },
};

/**
 * Get a term definition by key (case-insensitive)
 */
export function getJargon(key: string): JargonTerm | undefined {
  return jargonDictionary[key.toLowerCase().replace(/\s+/g, "-")];
}

/**
 * Check if a term exists in the dictionary
 */
export function hasJargon(key: string): boolean {
  return key.toLowerCase().replace(/\s+/g, "-") in jargonDictionary;
}
