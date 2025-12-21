/**
 * Jargon Dictionary
 *
 * Defines technical terms with simple, intuitive explanations
 * for both experts and beginners. Each term includes:
 * - A one-liner for quick tooltips
 * - A longer explanation in plain language
 * - An optional analogy ("think of it like...")
 * - Why we use it / what problem it solves
 * - Related terms for context
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
  /** Optional: Why we use it / what problem it solves */
  why?: string;
  /** Optional: related terms */
  related?: string[];
}

/**
 * Dictionary of technical terms used throughout the site.
 * Keys are lowercase with hyphens for easy lookup.
 */
export const jargonDictionary: Record<string, JargonTerm> = {
  // ═══════════════════════════════════════════════════════════════
  // CORE INFRASTRUCTURE CONCEPTS
  // ═══════════════════════════════════════════════════════════════

  vps: {
    term: "VPS",
    short: "Virtual Private Server — a remote computer you rent by the hour",
    long: "A VPS is like renting a computer that lives in a data center somewhere in the world. You connect to it over the internet and control it as if you were sitting right in front of it. Unlike your laptop, it's always on, always connected, and you have full administrator access. Companies like DigitalOcean, Hetzner, and Linode rent these out starting around $5-20/month.",
    analogy: "Think of it like renting an apartment instead of buying a house. You get your own private space (the server) inside a big building (the data center). Someone else handles the electricity, internet, and physical maintenance — you just use it.",
    why: "We use a VPS because AI coding agents work best with lots of CPU power, memory, and a stable internet connection. Your laptop could work, but a VPS gives you a dedicated workspace that's always running — even when your laptop is closed.",
    related: ["ssh", "cloud-server", "ubuntu"],
  },

  "cloud-server": {
    term: "Cloud Server",
    short: "A computer running 24/7 in a data center that you access remotely",
    long: "A cloud server is essentially a VPS — a virtual computer running in a data center. You never see the physical hardware; you just connect to it over the internet. These servers are called 'cloud' because they seem to exist 'somewhere out there' rather than on your desk. Major providers include AWS (Amazon), Google Cloud, Azure (Microsoft), DigitalOcean, and Hetzner.",
    analogy: "Imagine if you could rent a really powerful computer that lived in a building with perfect electricity, super-fast internet, and 24/7 security guards — and you could access it from anywhere in the world using just your laptop and an internet connection.",
    why: "Cloud servers give you predictable, powerful computing resources without buying and maintaining hardware. For AI coding, they provide the consistent environment that agents need to work reliably.",
    related: ["vps", "ssh", "ubuntu"],
  },

  ssh: {
    term: "SSH",
    short: "Secure Shell — the encrypted tunnel you use to control remote computers",
    long: "SSH (Secure Shell) is the standard way to securely log into and control a remote computer. When you 'SSH into your VPS,' you're opening an encrypted connection that lets you type commands as if you were sitting at that computer. Everything you type is encrypted, so nobody can spy on what you're doing — not even your internet provider.",
    analogy: "Imagine a secret, soundproof phone line between you and your VPS. When you pick up the phone (SSH), you can talk directly to your remote computer. Nobody can eavesdrop, and you can give it commands as if you were right there.",
    why: "SSH is the secure way to access remote servers. It's been the industry standard for over 25 years because it's simple, reliable, and incredibly secure. Every system administrator and developer uses it daily.",
    related: ["terminal", "vps", "bash"],
  },

  terminal: {
    term: "Terminal",
    short: "A text-based interface to control your computer by typing commands",
    long: "The terminal (also called command line, console, or shell) is a way to control your computer by typing text commands instead of clicking icons. It might look intimidating at first — just a blinking cursor waiting for input — but it's actually incredibly powerful. Most professional developers spend significant time in the terminal because it's faster and more precise than clicking through menus.",
    analogy: "Instead of pointing and clicking, you're texting your computer. You type what you want ('show me all my files'), press Enter, and it does it. It's like having a conversation with your computer in a very specific language.",
    why: "AI coding agents work primarily through the terminal because it's the most direct way to tell a computer what to do. Commands are precise, repeatable, and can be automated — exactly what AI agents need.",
    related: ["bash", "zsh", "cli"],
  },

  // ═══════════════════════════════════════════════════════════════
  // COMMAND LINE & SHELL
  // ═══════════════════════════════════════════════════════════════

  curl: {
    term: "curl",
    short: "A command to download files and web pages from the internet",
    long: "curl is a command-line tool that fetches content from URLs — like a text-based web browser. When you see 'curl ... | bash', it means: download a script from the internet and immediately run it. It's a common pattern for one-line installers. For example, 'curl https://example.com/install.sh | bash' downloads the install script and runs it in one step.",
    analogy: "It's like right-clicking a link and choosing 'Save As...' but without the clicking. You just tell it the URL and it fetches the content for you.",
    why: "curl makes installation simple — one command downloads and runs the installer. We use it because it works on virtually every Linux/Mac system and requires no setup.",
    related: ["bash", "terminal"],
  },

  bash: {
    term: "bash",
    short: "The default command interpreter on most Linux systems",
    long: "Bash (Bourne Again SHell) is the program that interprets what you type in the terminal and tells the computer what to do. When you type 'ls' to list files, bash is what understands that command and executes it. It's the default shell on most Linux systems and macOS (though Mac now defaults to zsh). Beyond running commands, bash also lets you write scripts — files full of commands that run automatically.",
    analogy: "Bash is like a translator between you and your computer. You speak in human-readable commands, and bash converts them into actions the computer understands.",
    why: "Bash is universal — it's on virtually every Linux server and Mac. Scripts written for bash work almost everywhere, making it the foundation of system automation.",
    related: ["zsh", "terminal", "cli"],
  },

  zsh: {
    term: "zsh",
    short: "A modern, feature-rich shell that's nicer to use than bash",
    long: "Zsh (Z Shell) is a shell like bash, but with many quality-of-life improvements: better tab completion (it can complete file names, git branches, command options), spelling correction, shared command history across terminals, and thousands of plugins. Most commands that work in bash also work in zsh, so you're not learning a new language — just getting a nicer experience.",
    analogy: "If bash is a reliable Honda Civic, zsh is a Tesla — same basic purpose (driving/running commands), but with lots of smart features that make the experience much more pleasant.",
    why: "We install zsh because developers spend hours in the terminal, and every improvement adds up. Better completions, theming, and plugins make you faster and happier.",
    related: ["bash", "oh-my-zsh", "powerlevel10k"],
  },

  "oh-my-zsh": {
    term: "oh-my-zsh",
    short: "A framework that makes zsh beautiful and adds hundreds of plugins",
    long: "Oh My Zsh is a community-driven framework for managing your zsh configuration. It comes with 300+ plugins (git shortcuts, syntax highlighting, autosuggestions) and 150+ themes. Instead of manually configuring everything, you just enable the plugins you want. For example, the git plugin adds shortcuts like 'gst' for 'git status' and 'gco' for 'git checkout'.",
    analogy: "Think of it as the app store for your terminal. Want syntax highlighting? There's a plugin. Git shortcuts? Plugin. Auto-suggestions as you type? Plugin. Oh My Zsh manages them all.",
    why: "Oh My Zsh transforms the terminal from a bare command line into a productive, colorful, feature-rich environment. It's one of the most popular developer tools for good reason.",
    related: ["zsh", "powerlevel10k"],
  },

  powerlevel10k: {
    term: "powerlevel10k",
    short: "A beautiful, fast theme that shows you useful info at a glance",
    long: "Powerlevel10k (p10k) is a theme for zsh that makes your terminal prompt incredibly informative. It can show: current directory, git branch and status, Python/Node version, command execution time, background jobs, and much more — all color-coded and with icons. Despite showing all this info, it's designed to be extremely fast (instant prompt).",
    analogy: "It's like a dashboard for your terminal. Instead of a plain blinking cursor, you get a heads-up display showing everything relevant about your current state.",
    why: "At a glance, you can see which git branch you're on, whether you have uncommitted changes, how long your last command took, and more. This context awareness makes development faster.",
    related: ["zsh", "oh-my-zsh", "git"],
  },

  cli: {
    term: "CLI",
    short: "Command Line Interface — programs you control by typing commands",
    long: "A CLI (Command Line Interface) is any program you interact with by typing commands rather than clicking buttons. Examples: 'git' (version control), 'npm' (package management), 'docker' (containers). CLI tools are popular with developers because they're scriptable (you can automate them), precise (exact commands, exact results), and fast (no waiting for graphics to load).",
    analogy: "If a GUI (graphical interface) is like driving with a steering wheel and pedals, a CLI is like typing exact coordinates to a self-driving car. More precise, more automatable, but requires learning the commands.",
    why: "AI agents work primarily through CLIs because commands are unambiguous. Instead of 'click the blue button,' you say 'run npm install' — there's no confusion about what should happen.",
    related: ["terminal", "bash"],
  },

  // ═══════════════════════════════════════════════════════════════
  // DEVELOPER TOOLS
  // ═══════════════════════════════════════════════════════════════

  tmux: {
    term: "tmux",
    short: "Terminal multiplexer — run multiple terminals in one window, even after disconnecting",
    long: "tmux lets you split your terminal into multiple panes and windows, and — critically — keeps everything running even if you disconnect. You can have one pane running a server, another for editing, and a third for logs. If your internet drops or you close your laptop, tmux keeps everything running. When you reconnect, it's all still there exactly as you left it.",
    analogy: "Imagine browser tabs, but for your terminal. And unlike browser tabs, they keep running even when you close the browser (or lose your internet connection).",
    why: "For AI agents, tmux is essential. We can have multiple agents running in different panes, monitor their progress, and never worry about losing work if the connection drops. It's the cockpit for managing agentic workflows.",
    related: ["terminal", "ntm"],
  },

  git: {
    term: "Git",
    short: "Version control — track every change to your code and undo mistakes",
    long: "Git tracks every change you make to your code. Every save (called a 'commit') is recorded forever, with a message explaining what changed. If something breaks, you can go back to any previous version. Git also enables collaboration: multiple people can work on the same codebase without overwriting each other's work. It's used by virtually every software company.",
    analogy: "Imagine 'undo' on steroids. Every save is remembered forever, you can name your saves ('Fixed login bug'), compare any two versions, and branch off to try experiments without affecting the main code.",
    why: "Git is non-negotiable for professional development. It prevents disasters ('I accidentally deleted everything'), enables collaboration, and provides a complete history of how code evolved.",
    related: ["lazygit"],
  },

  lazygit: {
    term: "lazygit",
    short: "A visual interface for Git — see everything at once, use keyboard shortcuts",
    long: "lazygit is a terminal UI for Git that shows you staged/unstaged files, commits, branches, and stashes all in one view. Instead of memorizing Git commands, you see everything and use keyboard shortcuts. Press 's' to stage a file, 'c' to commit, 'space' to toggle. It makes Git visual and fast without leaving the terminal.",
    analogy: "If Git commands are like typing GPS coordinates, lazygit is like a visual map where you can see and click on where you want to go.",
    why: "Git has hundreds of commands with subtle differences. lazygit surfaces the 20% of commands you use 80% of the time, making you much faster.",
    related: ["git", "terminal"],
  },

  ripgrep: {
    term: "ripgrep",
    short: "Lightning-fast code search — find text across thousands of files instantly",
    long: "ripgrep (command: 'rg') searches through files incredibly fast. It's like grep or Ctrl+F, but for your entire codebase. It automatically ignores files in .gitignore, searches recursively, shows line numbers and context, and can handle massive codebases. Finding 'TODO' across 10,000 files? Takes milliseconds.",
    analogy: "It's like having Sherlock Holmes with super-speed searching through every file in your project. You describe what you're looking for, and instantly get all matches with context.",
    why: "When debugging or refactoring, you constantly need to find where something is used. ripgrep makes this nearly instant, even on huge projects.",
    related: ["fzf"],
  },

  fzf: {
    term: "fzf",
    short: "Fuzzy finder — search by typing just a few characters",
    long: "fzf (fuzzy finder) lets you search through lists by typing only a few characters. Looking for 'configuration.settings.json'? Just type 'config set' and it finds it. Works with files, command history, git branches, and anything else you pipe into it. The 'fuzzy' part means it matches even if your characters aren't consecutive.",
    analogy: "Like autocomplete, but smarter. Type 'foo' and it finds 'my-foobar-file.txt', 'config-food.json', anything with those letters in that order.",
    why: "Remembering exact file names is tedious. fzf lets you find things by rough memory — incredibly useful when jumping around large codebases.",
    related: ["ripgrep", "zoxide"],
  },

  zoxide: {
    term: "zoxide",
    short: "Smart directory navigation — jump to any folder by typing a few letters",
    long: "zoxide learns which directories you visit frequently and lets you jump to them instantly. Instead of 'cd /very/long/path/to/my/project', just type 'z project'. It uses 'frecency' (frequency + recency) to rank directories, so your recent and frequent folders are always one command away.",
    analogy: "Like browser bookmarks that write themselves. Visit a folder a few times and zoxide remembers it. Then jump there from anywhere with just a few keystrokes.",
    why: "Navigating file systems is surprisingly time-consuming. zoxide eliminates the need to remember or type full paths — just jump directly to where you want to be.",
    related: ["fzf", "terminal"],
  },

  atuin: {
    term: "atuin",
    short: "Smart shell history — search every command you've ever run",
    long: "atuin replaces basic command history with a searchable database. It records every command with context (directory, exit code, duration), syncs across machines, and provides a beautiful UI to search your history. Forgot that docker command from last month? Search for 'docker' and find it, even if you ran it on a different computer.",
    analogy: "Your terminal commands become like Google search history — fully searchable, synced everywhere, with the full context of when and where you ran them.",
    why: "We all re-run commands. atuin makes finding previous commands instant, even complex ones you ran months ago.",
    related: ["zsh", "terminal"],
  },

  lsd: {
    term: "lsd",
    short: "Modern 'ls' with colors, icons, and better formatting",
    long: "lsd is a modern replacement for the 'ls' command (which lists files). It adds colors to distinguish file types, icons for visual recognition, tree views, git status indicators, and smart formatting. Instead of a wall of text, you get a beautiful, scannable view of your files.",
    analogy: "If 'ls' shows you a plain text list, lsd shows you the same information but color-coded and organized like a nice file manager.",
    why: "We spend a lot of time looking at file listings. lsd makes it easier to find what you're looking for at a glance.",
    related: ["terminal", "zsh"],
  },

  direnv: {
    term: "direnv",
    short: "Automatic environment variables when you enter a directory",
    long: "direnv automatically sets environment variables when you enter a directory and unsets them when you leave. This means each project can have its own configuration (API keys, database URLs, tool versions) that activates automatically. No more 'forgot to source .env' errors.",
    analogy: "Like your computer knowing to switch to 'work mode' when you enter your office and 'home mode' when you get home — but for software configuration.",
    why: "Different projects need different configurations. direnv makes this automatic and error-proof.",
    related: ["terminal", "bash"],
  },

  // ═══════════════════════════════════════════════════════════════
  // PROGRAMMING LANGUAGES & RUNTIMES
  // ═══════════════════════════════════════════════════════════════

  bun: {
    term: "bun",
    short: "A super-fast JavaScript runtime and package manager (10-100x faster than npm)",
    long: "Bun is an all-in-one JavaScript toolkit: it runs JavaScript/TypeScript code (like Node.js), manages packages (like npm), bundles code (like webpack), and runs tests (like Jest). It's written in a low-level language (Zig) for speed, making it 10-100x faster than traditional tools for many operations. Installing packages that took 30 seconds now takes 2 seconds.",
    analogy: "Imagine if your car was also a gas station, repair shop, and car wash — all in one, and everything worked 10x faster than the separate shops.",
    why: "Speed matters when you're iterating quickly. Bun's speed improvements compound: faster installs, faster tests, faster builds. It makes the development loop feel instant.",
    related: ["uv", "node"],
  },

  uv: {
    term: "uv",
    short: "Lightning-fast Python package manager (100x faster than pip)",
    long: "uv is a Python package installer written in Rust that's 100x faster than pip. It replaces pip, pip-tools, and virtualenv with a single, blazing-fast tool. Installing a Python project's dependencies that took 2 minutes with pip takes 2 seconds with uv. It's fully compatible with existing Python projects.",
    analogy: "Like upgrading from a dial-up modem to fiber internet — same websites, but everything loads instantly.",
    why: "Python dependency installation has always been painfully slow. uv eliminates that friction, making Python development feel as snappy as modern JavaScript tooling.",
    related: ["bun", "python"],
  },

  rust: {
    term: "Rust",
    short: "A fast, safe programming language for building reliable software",
    long: "Rust is a systems programming language focused on safety, speed, and concurrency. It prevents common bugs (memory leaks, null pointer errors) at compile time. Many modern CLI tools (ripgrep, lsd, zoxide, fd) are written in Rust, which is why they're so fast. Rust is also used for performance-critical parts of web browsers, databases, and cloud infrastructure.",
    analogy: "Rust is like having a very strict but helpful editor who catches your mistakes before you publish — preventing bugs before they can happen.",
    why: "We don't write Rust directly, but many tools we install are written in Rust, which is why they're blazingly fast and rock-solid.",
    related: ["go"],
  },

  go: {
    term: "Go",
    short: "A simple, efficient language for building networked services",
    long: "Go (Golang) is a language created by Google for building fast, reliable services. It's known for simplicity — there's usually one obvious way to do things. Many cloud tools (Docker, Kubernetes, Terraform) are written in Go. It compiles to a single binary with no dependencies, making deployment simple.",
    analogy: "If Rust is a Swiss Army knife with 50 tools, Go is a really well-designed hammer. Fewer features, but exactly what you need for most jobs.",
    why: "Go is popular for building services and CLI tools because it compiles fast, runs fast, and the resulting programs are easy to distribute.",
    related: ["rust"],
  },

  python: {
    term: "Python",
    short: "A beginner-friendly language popular for AI, data science, and automation",
    long: "Python is one of the most popular programming languages, known for its readable syntax (it looks almost like English). It's the dominant language for AI/ML, data science, and automation scripts. Most AI tools and libraries (OpenAI, LangChain, PyTorch) have Python as their primary interface.",
    analogy: "Python is the English of programming languages — not always the most efficient, but widely understood and great for getting things done.",
    why: "Many AI agents and tools are written in Python or have Python interfaces. Understanding basic Python helps you customize and extend AI workflows.",
    related: ["uv"],
  },

  node: {
    term: "Node.js",
    short: "JavaScript runtime that lets you run JavaScript outside the browser",
    long: "Node.js lets you run JavaScript on servers instead of just in web browsers. Before Node, JavaScript was limited to websites. Now it powers backend services, command-line tools, and desktop apps. npm (Node Package Manager) is the world's largest software registry with over 2 million packages.",
    analogy: "JavaScript used to be confined to web pages. Node broke it out of that prison, letting it run anywhere.",
    why: "Many web development tools and some AI integrations use Node.js. We install Bun as a faster alternative, but Node knowledge is still valuable.",
    related: ["bun"],
  },

  // ═══════════════════════════════════════════════════════════════
  // AI & AGENTS
  // ═══════════════════════════════════════════════════════════════

  agentic: {
    term: "Agentic",
    short: "AI that takes autonomous action instead of just answering questions",
    long: "Agentic AI doesn't just respond to prompts — it takes actions. It can write code, run commands, edit files, search the web, and complete multi-step tasks with minimal supervision. You give it a goal ('fix this bug'), and it figures out the steps: read the code, understand the error, write a fix, run tests, commit the change. This is a fundamental shift from AI as a Q&A tool to AI as a capable assistant.",
    analogy: "Regular AI is like asking a librarian for information — they tell you things. Agentic AI is like hiring an assistant who goes and does the work themselves.",
    why: "Agentic AI lets you operate at a higher level. Instead of 'how do I fix this bug?' you say 'fix this bug.' The AI handles the details while you focus on what to build next.",
    related: ["ai-agents", "claude-code", "codex"],
  },

  "ai-agents": {
    term: "AI Agents",
    short: "AI programs that can take actions autonomously to complete tasks",
    long: "AI agents are programs powered by large language models (like GPT-4 or Claude) that can do things in the world: write and run code, browse files, make API calls, execute shell commands. They're called 'agents' because they have agency — they can decide what to do next based on results, handle errors, and pursue goals across multiple steps.",
    analogy: "Think of AI agents as very capable interns who can follow complex instructions, use tools, and figure things out when they hit obstacles. They're not perfect, but they can do real work.",
    why: "AI agents are why this setup exists. Once configured, they can write code, fix bugs, run tests, and build features while you focus on higher-level decisions.",
    related: ["agentic", "claude-code", "codex", "gemini-cli"],
  },

  "claude-code": {
    term: "Claude Code",
    short: "Anthropic's AI coding assistant — runs in your terminal, edits your files",
    long: "Claude Code is an agentic coding assistant from Anthropic (the company behind Claude). It runs in your terminal and can: read and edit files, run shell commands, search code, install packages, write tests, and complete complex multi-step coding tasks. It's designed to be helpful while avoiding harmful actions.",
    analogy: "Imagine a brilliant junior developer who's incredibly fast, never gets tired, and can read and understand any codebase in seconds. That's Claude Code.",
    why: "Claude Code is one of the most capable AI coding assistants available. It can handle substantial coding tasks autonomously, from bug fixes to feature implementation.",
    related: ["ai-agents", "codex", "gemini-cli", "agentic"],
  },

  codex: {
    term: "Codex CLI",
    short: "OpenAI's command-line coding assistant",
    long: "Codex CLI is OpenAI's terminal-based coding assistant. Built on GPT-4, it can write code, explain concepts, debug issues, and help with development tasks. It integrates directly into your terminal workflow and can understand context from your codebase.",
    analogy: "Like having an OpenAI-powered expert who lives in your terminal and understands your code.",
    why: "Having multiple AI assistants gives you options — different models have different strengths. Codex brings OpenAI's capabilities to your terminal.",
    related: ["ai-agents", "claude-code", "gemini-cli"],
  },

  "gemini-cli": {
    term: "Gemini CLI",
    short: "Google's AI assistant for your terminal",
    long: "Gemini CLI brings Google's Gemini AI model to your command line. It can help with coding questions, generate code, explain concepts, and assist with development tasks. Part of Google's AI ecosystem, it offers another powerful option for AI-assisted development.",
    analogy: "Like having a Google engineer available in your terminal to help with coding questions.",
    why: "Different AI models excel at different tasks. Having Gemini available gives you another perspective and capability for your coding work.",
    related: ["ai-agents", "claude-code", "codex"],
  },

  // ═══════════════════════════════════════════════════════════════
  // SECURITY & TECHNICAL CONCEPTS
  // ═══════════════════════════════════════════════════════════════

  idempotent: {
    term: "Idempotent",
    short: "Safe to run multiple times — same result every time",
    long: "An idempotent operation produces the same result no matter how many times you run it. If you run our installer twice, you don't get two copies of everything — the second run just verifies everything is in place. This is critical for reliability: if something fails halfway, you can re-run from the beginning without breaking anything.",
    analogy: "Like pressing an elevator button. Pressing it once calls the elevator. Pressing it 10 more times doesn't call 10 more elevators — the outcome is the same.",
    why: "Installers often fail partway through (network issues, permissions, etc.). Idempotent design means you can safely re-run until it succeeds, without cleanup or worry.",
    related: ["sha256"],
  },

  sha256: {
    term: "SHA256",
    short: "A cryptographic fingerprint that verifies files haven't been tampered with",
    long: "SHA256 is an algorithm that creates a unique 256-bit 'fingerprint' for any file. If even a single character in the file changes, the fingerprint changes completely. We use this to verify that installer scripts we download are exactly what the author intended — not modified by an attacker.",
    analogy: "Like a wax seal on a letter. If the seal is intact and matches what you expect, you know nobody opened or modified the letter.",
    why: "Running code from the internet is inherently risky. SHA256 verification ensures the scripts we run are authentic and unmodified.",
    related: ["idempotent"],
  },

  sudo: {
    term: "sudo",
    short: "Run a command as administrator (superuser)",
    long: "sudo ('superuser do') runs a command with administrator privileges. Some actions — installing system software, modifying system files — require elevated permissions. When you prefix a command with 'sudo', you're saying 'run this as the all-powerful root user.' You'll be asked for your password to confirm.",
    analogy: "It's like a master key that opens any door. Most of the time you use your regular key, but sometimes you need the master key to access restricted areas.",
    why: "Installing development tools requires system-level access. sudo provides that access while still requiring confirmation, balancing convenience and security.",
    related: ["bash", "terminal"],
  },

  api: {
    term: "API",
    short: "Application Programming Interface — how programs talk to each other",
    long: "An API is a defined way for programs to communicate. When Claude Code needs to send a message to the AI model, it uses an API. When your code needs weather data, it calls a weather API. APIs define what requests you can make and what responses you'll get — like a menu at a restaurant.",
    analogy: "A restaurant menu is an API: it lists what you can order (requests) and what you'll receive (responses). You don't need to know how the kitchen works — just what's on the menu.",
    why: "AI agents work by calling APIs — sending prompts and receiving responses. Understanding APIs helps you understand how these tools work together.",
    related: ["cli"],
  },

  // ═══════════════════════════════════════════════════════════════
  // OPERATING SYSTEMS & PLATFORMS
  // ═══════════════════════════════════════════════════════════════

  ubuntu: {
    term: "Ubuntu",
    short: "A popular, beginner-friendly version of Linux",
    long: "Ubuntu is one of the most popular Linux distributions. It's free, well-documented, has a huge community, and is the default choice on most cloud providers. Ubuntu releases new versions every 6 months (with 'LTS' versions every 2 years that get 5 years of support). Most online tutorials and AI training data assume Ubuntu, making it easier to get help.",
    analogy: "If Linux is 'operating systems that aren't Windows or Mac,' Ubuntu is the most popular, well-supported flavor — like choosing Toyota when you want a reliable car.",
    why: "We target Ubuntu because it's the most common server OS. Scripts tested on Ubuntu work on the vast majority of VPS providers.",
    related: ["linux", "vps"],
  },

  linux: {
    term: "Linux",
    short: "A free, open-source operating system that powers most of the internet",
    long: "Linux is an operating system (like Windows or macOS) that's free and open-source. It powers most web servers, cloud platforms, Android phones, and even the Mars rovers. Unlike Windows/Mac, Linux is developed by a global community. While it's less common on desktops, it dominates servers because it's free, stable, and highly customizable.",
    analogy: "If Windows and Mac are proprietary restaurants owned by companies, Linux is like a community potluck — everyone contributes recipes, anyone can cook, and the food is free.",
    why: "We use Linux because that's what cloud servers run. It's the foundation for all modern backend development and cloud computing.",
    related: ["ubuntu", "bash"],
  },

  // ═══════════════════════════════════════════════════════════════
  // FLYWHEEL ECOSYSTEM
  // ═══════════════════════════════════════════════════════════════

  ntm: {
    term: "NTM",
    short: "Named Tmux Manager — your cockpit for running multiple AI agents",
    long: "NTM (Named Tmux Manager) is a tool for organizing and managing multiple tmux sessions. In agentic workflows, you often have several agents running simultaneously — NTM gives you a unified interface to see what's running, switch between agents, and manage the whole operation. It's like a control center for your AI assistants.",
    analogy: "Air traffic control for AI agents. You see all the planes (agents) on your radar (NTM), can communicate with any of them, and keep everything organized.",
    why: "When running multiple AI agents, organization becomes critical. NTM prevents the chaos of scattered terminal windows and lost sessions.",
    related: ["tmux", "ai-agents"],
  },

  "agent-mail": {
    term: "Agent Mail",
    short: "A messaging system that lets AI agents coordinate with each other",
    long: "Agent Mail provides an inbox/outbox system for AI agents to communicate. When multiple agents work on the same project, they can leave messages for each other, claim files they're working on (to avoid conflicts), and coordinate tasks. It's like email for AI assistants.",
    analogy: "Imagine a shared bulletin board where AI agents can leave notes for each other: 'I'm working on the login page, don't touch it' or 'I finished the API, someone please write tests.'",
    why: "Multiple agents working on the same codebase can step on each other's toes. Agent Mail enables coordination, preventing conflicts and duplicated work.",
    related: ["ai-agents", "ntm"],
  },

  flywheel: {
    term: "Flywheel",
    short: "A self-reinforcing system where each part makes the others work better",
    long: "A flywheel is a heavy wheel that stores energy — once spinning, it's hard to stop. In business, a 'flywheel' describes a system where each part reinforces the others: better tools attract more users, more users provide feedback, feedback improves tools, and so on. Our 'Agentic Coding Flywheel' means each tool (search, memory, coordination, etc.) makes the others more powerful.",
    analogy: "Like a snowball rolling downhill — it picks up more snow and rolls faster, which helps it pick up even more snow. Success breeds success.",
    why: "The flywheel concept explains why we install this specific set of tools. They're not random — each one amplifies the others, creating a powerful combined effect.",
    related: ["agentic", "ai-agents"],
  },

  "open-source": {
    term: "Open-source",
    short: "Software with publicly available code that anyone can inspect, modify, and share",
    long: "Open-source software has its source code freely available. Anyone can read it (verify it's not malicious), modify it (customize for their needs), and share improvements. Major open-source projects include Linux, Firefox, Python, and most development tools. It's developed by communities, not companies, though companies often contribute.",
    analogy: "Like a recipe that anyone can read, modify, and share. No secrets, no license fees, and if you want to make changes, you're free to fork off and cook your own version.",
    why: "All tools in Agent Flywheel are open-source. You can verify they're safe, they're free to use, and they have active communities maintaining and improving them.",
    related: ["linux", "git"],
  },

  // ═══════════════════════════════════════════════════════════════
  // ADDITIONAL TERMS FOR CLARITY
  // ═══════════════════════════════════════════════════════════════

  "one-liner": {
    term: "One-liner",
    short: "A single command that does everything — just copy, paste, and run",
    long: "A one-liner is a complete operation condensed into a single command you can copy and paste. Instead of running 50 separate commands, one well-crafted one-liner does everything automatically. For example, our install command downloads the script, sets up your environment, installs all tools, and configures everything — all from one paste.",
    analogy: "Like ordering a complete meal deal instead of ordering the burger, fries, and drink separately. One action, complete result.",
    why: "One-liners remove friction. Instead of following 50 steps where you might make a typo or miss something, you just paste one command and everything works.",
    related: ["curl", "bash"],
  },

  dependency: {
    term: "Dependency",
    short: "A tool or library that other software needs to work",
    long: "A dependency is something your software relies on. If you're building a house, lumber is a dependency — you can't build without it. In software, dependencies are libraries, tools, or programs that your code needs. 'Dependency hell' happens when different programs need conflicting versions of the same dependency.",
    analogy: "Like a recipe that requires flour. Flour is a dependency — you can't make the recipe without it. Some recipes share ingredients, others conflict (you can't use the same flour for two recipes at once).",
    why: "Agent Flywheel installs dependencies automatically so you don't have to. Our installer handles the complex web of requirements so everything just works together.",
    related: ["bun", "uv"],
  },

  "package-manager": {
    term: "Package Manager",
    short: "A tool that automatically downloads, installs, and updates software",
    long: "A package manager is like an app store for developers. Instead of manually downloading software from websites, you run a command like 'bun install' or 'uv pip install' and it automatically downloads the right version, handles dependencies, and configures everything. Examples: npm/bun for JavaScript, pip/uv for Python, apt for Ubuntu system packages.",
    analogy: "Like the App Store on your phone. You say 'I want this app' and it handles downloading, installing, and updating automatically.",
    why: "Package managers prevent 'works on my machine' problems. Everyone gets the exact same versions, installed the same way.",
    related: ["bun", "uv", "dependency"],
  },

  runtime: {
    term: "Runtime",
    short: "The engine that actually runs your code",
    long: "A runtime is the program that executes your code. JavaScript code needs a JavaScript runtime (like Node.js or Bun) to run. Python code needs a Python runtime. The runtime handles memory management, I/O operations, and translates your high-level code into actions the computer understands.",
    analogy: "If your code is a script for a play, the runtime is the stage, actors, and director that actually perform it.",
    why: "Different runtimes have different performance characteristics. Bun is much faster than Node.js for JavaScript. We install the fastest, most modern runtimes.",
    related: ["bun", "node", "python"],
  },

  llm: {
    term: "LLM",
    short: "Large Language Model — the AI brain behind ChatGPT, Claude, and Gemini",
    long: "An LLM (Large Language Model) is the neural network that powers AI assistants like ChatGPT, Claude, and Gemini. It's trained on vast amounts of text and learns to predict what comes next in a conversation. LLMs can understand context, follow instructions, write code, explain concepts, and reason through problems. They're called 'large' because they have billions of parameters (adjustable values the AI learned during training).",
    analogy: "Like a very well-read assistant who has read billions of documents and can draw on all that knowledge to help with almost any task. They don't 'know' things like humans do — they predict what a helpful response would look like.",
    why: "AI coding agents are powered by LLMs. Understanding what an LLM is helps you understand what AI agents can (and can't) do.",
    related: ["ai-agents", "agentic", "claude-code"],
  },

  prompt: {
    term: "Prompt",
    short: "The message or instruction you give to an AI",
    long: "A prompt is what you type to tell an AI what you want. It can be a question ('How do I...'), a command ('Write a function that...'), or context ('Given this code, find the bug...'). Better prompts get better results — being specific, providing context, and clearly stating what you want helps the AI help you better.",
    analogy: "Like giving instructions to a very capable assistant who takes things literally. 'Make dinner' might get you something random; 'Make spaghetti carbonara for four people' gets you exactly what you want.",
    why: "AI agents are only as good as their prompts. Learning to write clear prompts makes you more effective with AI tools.",
    related: ["llm", "ai-agents"],
  },

  token: {
    term: "Token",
    short: "A chunk of text that AI processes — roughly 4 characters",
    long: "AI models don't read text character by character — they process 'tokens,' which are roughly 4 characters or one word on average. 'Hello world' is about 2 tokens. Understanding tokens matters because AI has context limits (like 128K tokens) and costs are often per-token. A 100K token limit means roughly 75,000 words of conversation history.",
    analogy: "Like a speed-reader who doesn't read letter by letter but glances at word-sized chunks. Tokens are the AI's 'chunks' of understanding.",
    why: "Knowing about tokens helps you understand context limits. Long conversations may need summarization to fit within token limits.",
    related: ["llm", "prompt"],
  },

  "context-window": {
    term: "Context Window",
    short: "How much text an AI can 'remember' in a single conversation",
    long: "The context window is the AI's working memory — everything it can consider at once. Claude has a 200K token context window, meaning it can process about 150,000 words in one conversation. Older models had much smaller windows (4K-8K tokens). A larger context window means the AI can understand more code, longer documents, and more conversation history.",
    analogy: "Like a desk — a bigger desk lets you spread out more papers and work with more information at once. A small desk means you have to put some things away to make room for others.",
    why: "Context window size determines how much code an AI agent can analyze at once. Larger windows = better understanding of complex codebases.",
    related: ["llm", "token"],
  },

  "data-center": {
    term: "Data Center",
    short: "A warehouse full of computers that power cloud services",
    long: "A data center is a specialized building filled with thousands of servers, all connected to very fast internet with multiple power backups. When you rent a VPS, your virtual server lives in a data center. These facilities have 24/7 security, redundant power supplies, advanced cooling systems, and connections to major internet backbones. Major data centers are run by companies like Equinix, AWS, Google, and Microsoft.",
    analogy: "Like a massive hotel for computers. Each computer gets its own space, power, internet, and cooling. Staff are on-site 24/7 to handle any issues.",
    why: "Your VPS lives in a data center, which is why it has better uptime and faster internet than your home computer. Data centers are designed for reliability.",
    related: ["vps", "cloud-server"],
  },

  repository: {
    term: "Repository",
    short: "A folder containing your project's code, tracked by Git",
    long: "A repository (or 'repo') is a project folder that Git manages. It contains your code, configuration files, and the complete history of every change ever made. Repositories can be local (on your computer) or remote (on GitHub/GitLab). When you 'clone a repository,' you're downloading a complete copy including all history. A single project = one repository.",
    analogy: "Like a project folder with a time machine attached. You can see every version of every file, who changed what, and when — all the way back to the project's beginning.",
    why: "All serious software lives in repositories. Git repos enable collaboration, backup, and deployment. If your code isn't in a repo, it's at risk.",
    related: ["git", "lazygit"],
  },

  webhook: {
    term: "Webhook",
    short: "An automatic notification sent when something happens",
    long: "A webhook is like a doorbell that rings automatically when something happens. Instead of constantly checking 'did anything change?' (polling), webhooks let a service notify you instantly. For example, GitHub can send a webhook when code is pushed, Stripe when a payment is made, or a monitoring service when a server goes down.",
    analogy: "Instead of repeatedly checking your mailbox to see if mail arrived, it's like having a doorbell that rings the moment mail is delivered.",
    why: "Webhooks enable automation. AI agents can be triggered by webhooks — for example, automatically reviewing code when a pull request is opened.",
    related: ["api"],
  },

  deployment: {
    term: "Deployment",
    short: "Making your code live and available to users",
    long: "Deployment is the process of taking code from development and making it available in production (the real world). This might involve building the code, running tests, uploading to servers, updating databases, and verifying everything works. Modern deployments are often automated — push code to Git and everything happens automatically.",
    analogy: "Like a restaurant's process for serving a new dish: test the recipe, prepare ingredients, train staff, then officially add it to the menu. Deployment is the moment your code goes 'on the menu.'",
    why: "Agent Flywheel includes deployment tools like Vercel CLI so you can deploy instantly. No more manual FTP uploads or complex server configurations.",
    related: ["git", "repository"],
  },

  environment: {
    term: "Environment",
    short: "A complete setup where code runs — like development, staging, or production",
    long: "An environment is everything needed to run your code: the operating system, installed tools, configuration, databases, and settings. 'Development environment' is your local setup for building. 'Production environment' is the live system users see. 'Staging' is a test copy of production. Agent Flywheel creates a complete development environment on your VPS.",
    analogy: "Like different kitchens for different purposes: a test kitchen for experiments, a prep kitchen for practice, and the main kitchen for serving customers. Same recipes, different environments.",
    why: "Having a consistent environment prevents 'works on my machine' problems. Agent Flywheel gives everyone the same, reproducible development environment.",
    related: ["vps", "deployment"],
  },

  script: {
    term: "Script",
    short: "A file containing commands that run automatically in sequence",
    long: "A script is a text file containing a series of commands that execute one after another. Instead of typing commands manually, you run the script and it does everything for you. Shell scripts (ending in .sh) run in the terminal. The Agent Flywheel install script contains hundreds of commands that set up your entire development environment automatically.",
    analogy: "Like a recipe that a robot chef can follow automatically. You give it the recipe once, and it executes every step in order without you having to supervise each one.",
    why: "Scripts automate repetitive tasks and ensure consistency. Our install script means you don't have to manually type hundreds of commands — one script does everything perfectly every time.",
    related: ["bash", "one-liner", "curl"],
  },

  "root-user": {
    term: "Root User",
    short: "The superuser account with unlimited control over a Linux system",
    long: "The root user (also called 'superuser') has complete control over a Linux system — it can modify any file, install any software, and change any setting. Root access is powerful but dangerous; a mistake as root can break your entire system. That's why we switch to a regular 'ubuntu' user for day-to-day work, only using root powers when absolutely necessary.",
    analogy: "Like the master key to a building. The janitor with the master key can open any door, but you wouldn't use it for everyday access — too risky if it gets lost or misused.",
    why: "The installer runs as root to set everything up, then creates a safer 'ubuntu' user for your actual work. This follows security best practices.",
    related: ["sudo", "ubuntu-user"],
  },

  "ubuntu-user": {
    term: "Ubuntu User",
    short: "A regular user account for safe day-to-day work",
    long: "The 'ubuntu' user is a standard Linux account created during VPS setup. Unlike root, it has limited permissions — you need to explicitly ask for admin powers (using 'sudo') to make system changes. This prevents accidental damage and follows security best practices. After Agent Flywheel installs, you'll reconnect as the ubuntu user for all your coding work.",
    analogy: "Like having a regular office key that opens your own office but not the server room. You can request access to the server room (using sudo), but you have to be deliberate about it.",
    why: "Using a regular user account is safer. If something goes wrong, the damage is limited to your user space, not the entire system.",
    related: ["root-user", "sudo"],
  },

  "public-key": {
    term: "Public Key",
    short: "The shareable half of your SSH key pair — like your email address",
    long: "Your public key is one half of an SSH key pair. It's designed to be shared freely — you give it to servers you want to access. The public key can only encrypt data; it cannot decrypt. When you add your public key to a VPS, you're telling that server 'trust the person who has the matching private key.' Your public key typically starts with 'ssh-ed25519' or 'ssh-rsa'.",
    analogy: "Like your email address: you share it with everyone who needs to contact you. Anyone can send you encrypted messages using your public key, but only you (with your private key) can read them.",
    why: "Public keys enable passwordless, secure authentication. You share this with every VPS provider; they use it to verify you're really you.",
    related: ["private-key", "ssh", "ssh-key"],
  },

  "private-key": {
    term: "Private Key",
    short: "The secret half of your SSH key pair — NEVER share this",
    long: "Your private key is the secret half of your SSH key pair. It lives on your computer (in ~/.ssh/) and should NEVER be shared, copied to servers, or shown to anyone. When you connect to a VPS, your computer uses the private key to prove your identity. If someone gets your private key, they can access all your servers. Keep it secret!",
    analogy: "Like the PIN to your bank card: anyone can know your card number (public key), but only you should know the PIN (private key). Together, they prove you're authorized.",
    why: "The private key is your proof of identity. Guard it carefully — it's the only thing standing between your servers and unauthorized access.",
    related: ["public-key", "ssh", "ssh-key"],
  },

  "ip-address": {
    term: "IP Address",
    short: "A unique number that identifies a computer on the internet (like 192.168.1.100)",
    long: "An IP address is a numerical label assigned to every device connected to the internet. It's like a phone number for computers — when you want to connect to your VPS, you use its IP address. IPv4 addresses look like '192.168.1.100' (four numbers 0-255, separated by dots). When you create a VPS, the provider gives you an IP address to use for SSH connections.",
    analogy: "Like a street address for your house. When you want to send mail (data), you need to know the exact address. Every house (computer) on the internet has a unique address.",
    why: "You need your VPS's IP address to connect to it. The wizard asks you to enter it so we can generate the correct SSH command for you.",
    related: ["vps", "ssh"],
  },

  configuration: {
    term: "Configuration",
    short: "Settings that control how software behaves",
    long: "Configuration (or 'config') refers to settings that customize how software works. Config files are text files (often ending in .conf, .json, or .yaml) that tell programs what to do. For example, your shell config (~/.zshrc) controls your terminal's appearance and behavior. Agent Flywheel sets up optimal configurations for all installed tools.",
    analogy: "Like the settings app on your phone. You configure your phone's behavior (ringtone, wallpaper, notifications) through settings. Software config is the same concept.",
    why: "Good configuration makes tools more productive. Agent Flywheel pre-configures everything with power-user settings so you get the best experience immediately.",
    related: ["zsh", "environment"],
  },

  cargo: {
    term: "Cargo",
    short: "Rust's package manager and build tool",
    long: "Cargo is the official tool for Rust projects. It handles downloading dependencies, compiling code, running tests, and publishing packages. 'cargo install' is how you install Rust-based command-line tools. Many modern developer tools are installed via Cargo because it produces fast, native executables.",
    analogy: "Cargo is to Rust what npm is to JavaScript — the central hub for getting packages and building projects.",
    why: "With Cargo installed, you can install any Rust-based tool with a single command. The Rust ecosystem has many excellent developer tools.",
    related: ["rust", "package-manager"],
  },

  postgresql: {
    term: "PostgreSQL",
    short: "Powerful open-source database for storing and querying data",
    long: "PostgreSQL (often 'Postgres') is a robust, open-source relational database. It stores data in tables with rows and columns, supporting complex queries, transactions, and data integrity. It's the database of choice for many production applications. We install PostgreSQL 18, the latest version with enhanced performance and features.",
    analogy: "Like a highly organized filing cabinet for your application's data. You can store millions of records and find any specific one instantly using queries.",
    why: "Most real applications need a database. Having PostgreSQL ready means you can build full applications with persistent data storage.",
    related: ["supabase", "deployment"],
  },

  supabase: {
    term: "Supabase",
    short: "Open-source Firebase alternative — database + auth + APIs instantly",
    long: "Supabase gives you a PostgreSQL database plus authentication, real-time subscriptions, storage, and auto-generated APIs — all in one platform. It's 'backend-as-a-service' that lets you build full applications without writing backend code. You get an admin dashboard, client libraries, and can self-host or use their cloud.",
    analogy: "Like getting a pre-built backend for your app instead of building it from scratch. Database, user login, file storage — it's all there, ready to use.",
    why: "Supabase CLI lets you manage your Supabase projects from the terminal. Combined with AI coding agents, you can rapidly build full-stack applications.",
    related: ["postgresql", "deployment"],
  },

  wrangler: {
    term: "Wrangler",
    short: "Cloudflare's CLI for deploying serverless functions worldwide",
    long: "Wrangler is Cloudflare's command-line tool for building and deploying Workers — serverless functions that run at the edge (close to users worldwide). Workers start in milliseconds and scale automatically. Wrangler handles local development, testing, and deployment. Cloudflare's free tier is generous enough for most projects.",
    analogy: "Like having tiny restaurants in every city serving your app's logic, instead of one central kitchen. Users get served by the nearest location, making everything faster.",
    why: "Edge functions are the future of fast, scalable web apps. Wrangler makes deploying them as easy as 'wrangler deploy'.",
    related: ["deployment", "cli-tools"],
  },

  vault: {
    term: "Vault",
    short: "HashiCorp's secret management tool for storing passwords and API keys",
    long: "Vault is a tool for securely storing and accessing secrets — passwords, API keys, certificates, and other sensitive data. Instead of putting secrets in config files or environment variables (which can leak), you store them in Vault and fetch them when needed. Vault provides access control, audit logs, and automatic secret rotation.",
    analogy: "Like a bank vault for your passwords and API keys. Instead of keeping them in your pocket (config files), you store them securely and retrieve them only when needed, with full audit trail.",
    why: "As you build real applications, secret management becomes critical. Vault is the industry standard for secure secret storage.",
    related: ["configuration", "deployment"],
  },
};

/**
 * Get a term definition by key (case-insensitive, handles spaces and underscores)
 */
export function getJargon(key: string): JargonTerm | undefined {
  const normalized = key.toLowerCase().replace(/[\s_]+/g, "-");
  return jargonDictionary[normalized];
}

/**
 * Check if a term exists in the dictionary
 */
export function hasJargon(key: string): boolean {
  const normalized = key.toLowerCase().replace(/[\s_]+/g, "-");
  return normalized in jargonDictionary;
}

/**
 * Get all terms in a category
 */
export function getAllTerms(): JargonTerm[] {
  return Object.values(jargonDictionary);
}
