/**
 * Jargon Dictionary
 *
 * Defines technical terms with plain-language explanations
 * aimed at newcomers without boring experienced readers. Each term includes:
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
  // HARDWARE & SERVER SPECIFICATIONS
  // ═══════════════════════════════════════════════════════════════

  vcpu: {
    term: "vCPU",
    short: "Virtual CPU, the unit of CPU parallelism you rent on a cloud server",
    long: "A vCPU (virtual CPU) is the CPU capacity allocated to your cloud server. Cloud providers run many virtual servers on one big physical machine and assign each server a certain number of vCPUs. A good mental model is: one vCPU lets your server make real progress on one CPU-heavy stream of work at a time. Add more vCPUs and the server can make progress on more things in parallel (multiple programs, builds, searches, or multiple AI sessions) instead of constantly taking turns. On most VPS plans the underlying machine is shared, so the exact speed of a single vCPU varies, but the vCPU count is still the clearest signal for how much parallel work the server can keep moving.",
    analogy: "Think of it like staffing on a case. One person can draft one document at a time. Four people can draft four documents in parallel. The work may still be in the same office building (shared hardware), but your staffing level (vCPU count) determines how many separate tasks can move forward at once.",
    why: "vCPUs matter most when you want parallelism: multiple agents working at the same time, plus background work like tests, builds, indexing, and search. If you mostly run one agent and lightweight commands, fewer vCPUs feel fine. If you want several agents working simultaneously (or you do lots of builds/tests), more vCPUs keeps the machine responsive.",
    related: ["ram", "vps", "nvme"],
  },

  ram: {
    term: "RAM",
    short: "Random Access Memory, the fast temporary storage your computer uses while working",
    long: "RAM (Random Access Memory) is your computer's short-term memory, measured in gigabytes (GB). Unlike your hard drive which stores files permanently (your photos, documents, and programs stay there even when power is off), RAM holds data that programs are actively using right now. When you open an application, it loads from permanent storage into RAM for fast access because RAM is much faster to read from. More RAM means you can run more programs simultaneously without slowdowns. When you close a program, its RAM is freed up for other uses; when you shut down, RAM is completely erased because it requires constant power to hold data. That's why you have to save your work before shutting down: anything only in RAM disappears.",
    analogy: "RAM is like your desk space while working. A bigger desk (more RAM) lets you spread out more documents and work on multiple things without constantly putting papers away and getting new ones from the filing cabinet. Your filing cabinet (the hard drive or SSD) stores everything permanently, but your desk is where active work happens. If your desk is too small, you spend all your time shuffling papers back and forth instead of actually working. Similarly, if you don't have enough RAM, your computer spends time constantly loading and unloading data, making everything feel sluggish.",
    why: "AI coding setups tend to run a lot at once: the agent, your editor, language tools, package installs, tests, and searches. If RAM runs out, the system uses disk as overflow (called swap), which is much slower and makes everything feel laggy. A solid baseline is 16 GB. If you plan to run several agents at once or work in larger projects, 32 GB+ gives you breathing room.",
    related: ["vcpu", "vps", "nvme"],
  },

  nvme: {
    term: "NVMe SSD",
    short: "Very fast solid-state storage that makes file-heavy work feel snappy",
    long: "NVMe (Non-Volatile Memory Express) SSDs are fast permanent storage. Traditional hard drives use spinning disks and a moving arm, which makes them slow for lots of small reads and writes. SSDs replace moving parts with chips, which is already a big speed jump. NVMe is the modern way to connect those chips directly over a high-speed bus, so the drive can move data with much less waiting. The practical effect is simple: opening projects, searching code, installing dependencies, and starting programs all feel much faster.",
    analogy: "Think of it like retrieving files. A hard drive is like sending someone to a records room to find a binder and bring it back. A SATA SSD is like having that binder on a rolling cart nearby. NVMe is like having the file cabinet right next to your desk, with multiple drawers you can open quickly. Same files, far less waiting.",
    why: "AI coding involves constant file operations: reading thousands of code files, writing changes, searching through entire projects for specific text, and downloading/installing software. NVMe storage makes all of this nearly instant. When searching 10,000 files for a specific phrase, NVMe means results appear in milliseconds instead of seconds. When installing software with many small files, they extract instantly instead of making you wait. Fast storage is one of those upgrades where you don't realize how much time you were losing until you experience the improvement. Most cloud servers now offer NVMe storage, and we recommend insisting on it when choosing a server.",
    related: ["vcpu", "ram", "vps"],
  },

  // ═══════════════════════════════════════════════════════════════
  // CORE INFRASTRUCTURE CONCEPTS
  // ═══════════════════════════════════════════════════════════════

  vps: {
    term: "VPS",
    short: "Virtual Private Server, a remote computer you rent by the hour or month",
    long: "A VPS (Virtual Private Server) is a computer that you rent from a company, but instead of being delivered to your house, it lives in a specialized building called a data center. You never touch it physically; instead, you connect to it over the internet and control it by typing commands, just as if you were sitting in front of it. The 'virtual' part means the physical machine is shared with other customers, but you each get your own isolated section that acts like a completely separate computer. You have full control over your section: you can install any software, run programs 24/7, and restart it whenever you want. Unlike your laptop which you close and carry around, a VPS stays on continuously, connected to very fast internet, ready to work. We recommend OVH and Contabo for their excellent value—you can get a capable VPS for around $10-25/month.",
    analogy: "Think of it like renting an apartment instead of buying a house. You get your own private space (your VPS) inside a large building (the data center). Someone else handles the electricity, internet connection, physical security, and maintenance of the building. You just move in and use your space however you want. You can decorate it (install software), have guests over (run services others can access), and leave your appliances running 24/7 (keep programs running continuously). If the building's power goes out, backup generators kick in automatically, something you probably don't have at home.",
    why: "We use a VPS because AI coding assistants work best with a stable, always-on environment with good resources. Your laptop could technically work, but it has drawbacks: it sleeps when you close it, its internet connection varies as you move around, and you need it for other things. A VPS gives you a dedicated workspace that keeps running even when your laptop is off. Your AI assistants can work through the night while you sleep. And if something goes wrong, you can wipe the VPS and start fresh without affecting your personal computer at all.",
    related: ["ssh", "cloud-server", "ubuntu"],
  },

  "cloud-server": {
    term: "Cloud Server",
    short: "A computer running 24/7 in a data center that you access remotely",
    long: "A cloud server is essentially the same idea as a VPS: a computer you rent that lives in a specialized facility and that you control over the internet. \"Cloud\" just means you don't manage the physical hardware yourself—you rent computing power from a provider, and you can access it from anywhere. Major cloud providers include AWS (Amazon Web Services), Google Cloud, and Microsoft Azure for enterprise use, while OVH and Contabo offer excellent value for individual developers. Prices range from around $10/month for a capable VPS to thousands for large, enterprise-grade systems.",
    analogy: "Imagine renting a really powerful computer that lives in a building specifically designed for computers: perfect climate control so nothing overheats, backup power generators so it never turns off, super-fast internet connections, and 24/7 security guards. You can access this computer from your laptop at a coffee shop, from your phone on a train, or from a friend's computer across the world. The computer is always there, always on, waiting for your commands.",
    why: "Cloud servers give you access to powerful computing resources without buying, housing, or maintaining physical hardware. You don't need a server closet in your home. You don't need to replace failed hard drives. You don't need to worry about power outages. For AI coding assistants, cloud servers provide the consistent, stable environment these tools need to work reliably. And if you mess something up badly, you can delete the whole server and create a fresh one in minutes.",
    related: ["vps", "ssh", "ubuntu"],
  },

  ssh: {
    term: "SSH",
    short: "Secure Shell, the encrypted tunnel you use to control remote computers",
    long: "SSH (Secure Shell) is the standard way to securely log into and control a remote computer over the internet. When you 'SSH into' your cloud server, you get a text session where you can type commands as if you were sitting at that server's keyboard. The \"Secure\" part matters: the contents of the session are encrypted, so people on the network can't read what you type or what the server sends back. (They can still see that you connected to a server—just not the content.) An SSH command typically looks like 'ssh ubuntu@203.0.113.10', which means 'connect to the computer at address 203.0.113.10 as the user named ubuntu.'",
    analogy: "Think of SSH like the lock icon (HTTPS) in your browser, but for a remote command line. You and the server can talk freely, and outsiders can't read the conversation.",
    why: "SSH is how you'll control your cloud server. Without SSH, you'd have no way to interact with a computer that's physically in a building hundreds of miles away. It's been the industry standard for over 25 years because it just works: it's simple to use, incredibly secure, and supported everywhere. When the wizard asks you to 'SSH into your server,' it's asking you to use this secure connection to start typing commands on your new cloud server.",
    related: ["terminal", "vps", "bash"],
  },

  terminal: {
    term: "Terminal",
    short: "A text-based interface to control your computer by typing commands",
    long: "The terminal (also called the command line, console, or command prompt) is a way to control your computer by typing text commands instead of clicking icons with a mouse. When you open a terminal, you see a mostly blank window with a blinking cursor waiting for you to type something. You type a command (like 'ls' to list files), press Enter, and the computer responds with text output. It might look intimidating at first, like something from an old movie about hackers, but it's actually incredibly powerful and, once you get used to it, often faster than clicking through folders and menus. Before graphical interfaces with icons and windows existed, the terminal was the only way to use a computer. It never went away because it's still the most efficient way to do many things.",
    analogy: "Instead of pointing and clicking at pictures (icons) on screen, you're having a text conversation with your computer. You type what you want in a specific format ('show me the files in this folder'), press Enter, and it responds in text. It's like texting with your computer rather than playing a point-and-click game. 'list all files' becomes 'ls', 'change to this folder' becomes 'cd foldername', and 'show me what's in this file' becomes 'cat filename'.",
    why: "AI coding assistants work primarily through the terminal because it's the most direct, precise way to tell a computer what to do. When you click icons, the computer has to interpret where you clicked and what you meant. With typed commands, there's no ambiguity. Commands can also be saved and replayed perfectly, which is how the automated installer works: it runs dozens of commands automatically that would take hours to click through manually. You don't need to master the terminal to use this setup; the wizard guides you through the exact commands to copy and paste.",
    related: ["bash", "zsh", "cli"],
  },

  // ═══════════════════════════════════════════════════════════════
  // COMMAND LINE & SHELL
  // ═══════════════════════════════════════════════════════════════

  curl: {
    term: "curl",
    short: "A command to download files and web pages from the internet",
    long: "curl (pronounced 'curl,' short for 'Client URL') is a command you type in the terminal to download content from the internet. When you visit a website in your browser, your browser is downloading that web page behind the scenes. curl does the same thing but without the visual browser; it just fetches the content and shows it as text or saves it to a file. You'll often see commands like 'curl https://example.com/install.sh | bash', which means 'download the file at that web address and immediately run it.' The vertical bar '|' (called a pipe) sends the downloaded content directly to bash (the command interpreter) to run it. This is convenient, but it's worth treating like running any downloaded program: only do it from a source you trust, and when in doubt download first and inspect.",
    analogy: "Imagine you could type a website address and have the page content instantly appear on your screen as text, rather than having to open a browser, wait for it to load, and click around. That's curl. It's like having a very fast, text-only web browser that can save what it downloads directly or pass it to other programs.",
    why: "curl makes installation simple: one command can download and run an installer without any clicking or file management. The Agent Flywheel installer uses curl to download the setup script and run it immediately. curl works on virtually every Mac and Linux system because it's been a standard tool for decades. When the wizard shows you a command starting with 'curl', that's the download-and-run step.",
    related: ["bash", "terminal"],
  },

  bash: {
    term: "bash",
    short: "The program that understands and runs your typed commands",
    long: "Bash (Bourne Again SHell) is the program that runs inside your terminal and interprets the commands you type. When you type 'ls' and press Enter, it's bash that understands you want to list files, tells the operating system to do it, and shows you the results. Think of the terminal window as a container, and bash as the intelligence inside it that actually understands what you're saying. Bash has been the default on most Linux systems since 1989 and was the Mac default until 2019. The word 'shell' is used because bash provides a 'shell' or interface around the computer's core; you interact with the shell, and the shell talks to the deeper parts of the system. Bash can run individual commands you type, but it can also run 'scripts,' which are text files containing many commands that execute automatically in sequence.",
    analogy: "Bash is like a translator who sits between you and someone who only speaks machine language. You say 'list all my files' (in a specific format like 'ls'), the translator (bash) understands what you mean, tells the computer in its native language, and translates the computer's response back into text you can read. Without this translator, you couldn't communicate with your computer through the terminal at all.",
    why: "Bash is nearly universal. Every Linux server, every Mac, every cloud server has bash installed and ready. Commands and scripts written for bash work almost everywhere without modification. When the installer runs commands, it's bash that executes them. Understanding that bash is the interpreter between you and the computer helps you understand what's happening when you paste commands into the terminal.",
    related: ["zsh", "terminal", "cli"],
  },

  zsh: {
    term: "zsh",
    short: "A more modern, feature-rich alternative to bash",
    long: "Zsh (Z Shell, pronounced 'zee-shell' or 'zed-shell') is a command interpreter like bash, but with many convenience improvements that make working in the terminal more pleasant. Key improvements include: smarter auto-completion (when you press Tab, it can suggest file names, folder names, command options, and even specific things like branch names if you use version control), spelling correction (if you type 'cd Destkop' it might ask 'did you mean Desktop?'), and shared history (commands you type in one terminal window appear in the history of other windows). Despite these additions, virtually every command that works in bash also works identically in zsh, so you're not learning a new language. Macs have used zsh as the default since 2019. The installer sets up zsh on your cloud server because the experience is noticeably better.",
    analogy: "If bash is a solid, no-nonsense tool, zsh is that same tool with better ergonomics: smarter suggestions, better completion, and quality-of-life features that save time all day long. You're not learning a new \"language\"—you're getting a nicer cockpit.",
    why: "People who work with AI coding assistants spend significant time in the terminal. Every convenience improvement, every saved keystroke, compounds over time. Zsh's smarter auto-completion alone can save minutes each day. Combined with themes and add-ons that the installer configures, your terminal becomes a genuinely pleasant place to work instead of a spartan text box.",
    related: ["bash", "oh-my-zsh", "powerlevel10k"],
  },

  "oh-my-zsh": {
    term: "oh-my-zsh",
    short: "A collection of enhancements that makes your terminal colorful and smart",
    long: "Oh My Zsh is a popular collection of improvements for zsh that makes your terminal experience dramatically better with minimal setup. It provides two main things: themes (which change how your terminal looks, adding colors, icons, and useful information displays) and plugins (which add new capabilities or shortcuts). For example, one plugin adds syntax highlighting so commands change color as you type them: valid commands turn green, invalid ones turn red, helping you catch typos before pressing Enter. Another plugin auto-suggests commands as you type based on your history, appearing in faded text that you can accept with the right arrow key. The installer sets up Oh My Zsh with a curated selection of the most useful enhancements so you get a great experience immediately.",
    analogy: "Think of your terminal like a plain text editor. Oh My Zsh is like adding a carefully chosen set of extensions: better visuals, helpful hints, and shortcuts that make the tool feel modern without changing what it fundamentally is.",
    why: "Oh My Zsh transforms the terminal from a minimal black-and-white text box into a productive, colorful, helpful environment. Commands that would take 20 keystrokes become 3-key shortcuts. Mistakes are highlighted before you make them. Information you need is displayed at a glance. This might seem superficial, but when you spend hours each day in the terminal, these improvements significantly reduce frustration and increase speed.",
    related: ["zsh", "powerlevel10k"],
  },

  powerlevel10k: {
    term: "powerlevel10k",
    short: "A theme that displays useful information right in your terminal prompt",
    long: "Powerlevel10k (often shortened to 'p10k') is a visual theme for zsh that transforms your terminal prompt from a simple blinking cursor into an informative dashboard. A normal terminal might just show 'user@computer:~$' and wait for you to type. With Powerlevel10k, that same area can show you: what folder you're in (with a shortened path so it fits nicely), whether you're in a version-controlled project and if you have unsaved changes (with color coding: green means clean, yellow means changes), how long your last command took to run, the current time, whether any background processes are running, and more. All of this appears in neatly organized, color-coded segments with small icons. Despite displaying so much information, Powerlevel10k is engineered to be extremely fast and never slows down your terminal.",
    analogy: "Think of a car dashboard versus a car with no gauges at all. Without a dashboard, you'd have to constantly guess how fast you're going, whether you're low on fuel, if the engine has a problem. With a dashboard, all that information is visible at a glance. Powerlevel10k is that dashboard for your terminal: instead of remembering 'what folder am I in? did I save my work? how long has this been running?', you just glance at the prompt and all that context is right there.",
    why: "When working on projects, context matters. Knowing which version-controlled branch you're on prevents mistakes (like accidentally changing the wrong version). Seeing that you have unsaved changes reminds you to save before switching tasks. Watching command execution time helps you realize when something is taking too long. This 'ambient awareness' makes you more efficient and prevents common mistakes, all without requiring you to actively check anything.",
    related: ["zsh", "oh-my-zsh", "git"],
  },

  cli: {
    term: "CLI",
    short: "Command Line Interface, a program you control by typing text commands",
    long: "A CLI (Command Line Interface) is any program you interact with by typing commands rather than clicking buttons and icons. You've probably used graphical programs where you click menus, drag items, and push buttons. CLI tools work differently: you type a command, press Enter, and the program runs and shows text output. For example, instead of opening a file manager and clicking through folders, you type 'ls' to list files. Instead of clicking through menus to save your project, you type 'git commit' to save a snapshot. Many professional tools are CLI-only or work best as CLIs because typing commands is faster than clicking, and commands can be saved and replayed automatically.",
    analogy: "A graphical interface is like navigating by clicking buttons and menus. A CLI is like writing precise instructions: once you know the vocabulary, it's faster, repeatable, and leaves a clear trail of exactly what was done.",
    why: "AI coding assistants work primarily through CLIs because typed commands are completely unambiguous. 'Click the blue button' is vague (which blue button?), but 'git push origin main' has exactly one meaning. Commands can also be logged, reviewed, and replayed, which helps with debugging and automation. When you see the installer running dozens of commands, it's using CLIs for everything because each command does exactly one precise thing.",
    related: ["terminal", "bash"],
  },

  // ═══════════════════════════════════════════════════════════════
  // DEVELOPER TOOLS
  // ═══════════════════════════════════════════════════════════════

  tmux: {
    term: "tmux",
    short: "A tool that keeps your terminal sessions running even when you disconnect",
    long: "tmux (terminal multiplexer) solves a critical problem: normally, when you close a terminal or lose your internet connection, anything running in that terminal stops. If you're running a long installation and your WiFi blips, you have to start over. tmux fixes this by running your terminal sessions inside a persistent container on the server itself. You can disconnect (intentionally or accidentally), reconnect hours later, and find everything exactly as you left it, still running. Beyond persistence, tmux also lets you split your terminal into multiple sections (called panes) so you can see several things at once: perhaps an AI assistant in one pane, its output logs in another, and a file editor in a third. You can create multiple tabs (called windows) for different tasks. And you can switch between these sessions at will.",
    analogy: "Think of tmux like leaving your work open on your desk at the office. You can go home (disconnect), come back later, and everything is still exactly where you left it—notes, processes, and all. A normal terminal connection is more like a phone call: if it drops, it's over.",
    why: "tmux is essential for AI coding assistants because they often run tasks that take hours. Without tmux, you'd have to sit and watch, keeping your connection stable the whole time. With tmux, you can start multiple AI assistants, close your laptop, go to dinner, and come back to find them still working. If one assistant finishes and you want to give it new instructions, it's right there waiting. The installer sets up tmux so you get this persistence automatically.",
    related: ["terminal", "ntm"],
  },

  git: {
    term: "Git",
    short: "Version control that tracks every change to your code and lets you undo mistakes",
    long: "Git is a version control system that tracks every change you make to your project files. Imagine writing a document and having an automatic save after every paragraph, where each save remembers exactly what the document looked like at that moment, who made the change, when they made it, and a note about why. With Git, you can go back to any of these saved moments (called 'commits') at any time. If you break something, you can revert to a version from yesterday, last week, or last year. Git also enables multiple people (or multiple AI assistants!) to work on the same project simultaneously without overwriting each other's work. Created in 2005 by Linus Torvalds (who also created Linux), Git is now used by virtually every software company and developer in the world. GitHub, GitLab, and similar services provide cloud storage for Git projects.",
    analogy: "Think of Git like version history for an entire project. Each \"commit\" is a labeled snapshot: what changed, when, and why. You can compare snapshots, roll back to an earlier one, or create a separate line of work (\"branch\") to experiment safely and merge it back when it's ready.",
    why: "Git prevents disasters ('I accidentally deleted everything') because committed changes can be recovered from history. It enables collaboration because people (and agents) can work in parallel and merge changes. And for AI-assisted development specifically, it's a safety net: if an AI makes a change you don't like, you can review exactly what changed and revert cleanly.",
    related: ["lazygit", "repository", "github"],
  },

  lazygit: {
    term: "lazygit",
    short: "A visual interface for Git that makes version control easier to understand and use",
    long: "lazygit is a visual, keyboard-driven interface for Git that runs inside your terminal. Instead of typing Git commands from memory and trying to visualize what's happening, lazygit shows you everything at once in organized panels: files you've changed, changes ready to be saved, your history of saves, and different versions you're working on. You navigate with the keyboard and perform common actions with single-key shortcuts. It makes version control feel concrete by turning it into a clear dashboard you can browse and operate.",
    analogy: "Using Git commands is like navigating a city by typing street addresses and turn-by-turn directions. Using lazygit is like having a visual map where you can see the whole city, click on your destination, and see the route highlighted. Both get you there, but the visual approach is much easier when you're learning or when the situation is complex.",
    why: "Git is powerful but has a steep learning curve. There are hundreds of commands with subtle differences, and it's easy to make mistakes. lazygit makes Git accessible by showing you what's happening instead of making you imagine it. AI coding assistants interact with Git constantly, and if you want to understand what they're doing or fix something they got wrong, lazygit helps you see and manage the situation visually.",
    related: ["git", "terminal", "repository"],
  },

  ripgrep: {
    term: "ripgrep",
    short: "Lightning-fast search tool that finds text across thousands of files instantly",
    long: "ripgrep (you type 'rg' to use it) searches through all your files for any text pattern incredibly fast. You've probably used Ctrl+F (or Cmd+F on Mac) to search within a single document. ripgrep does the same thing but across your entire project, potentially thousands of files, in milliseconds. Type 'rg login' and it shows you every file that contains the word 'login', with the matching line, its line number, and a few lines of surrounding context so you understand what you're seeing. It's smart enough to skip irrelevant files (like downloaded dependencies or compiled output) automatically. ripgrep is written in Rust, a language known for producing extremely fast programs, which is why it can search so quickly.",
    analogy: "Imagine needing to find every mention of a name in a library with 10,000 books. Normally, you'd have to open each book and scan through it, which would take months. ripgrep is like a librarian with superhuman speed who can check every book in seconds and hand you a list of exact page numbers with the surrounding sentences for context. What was once impractical becomes instant.",
    why: "When working on code, you constantly need to find things: where is this function used? where is this error message defined? what files reference this configuration? Without fast search, these questions take minutes of clicking around. With ripgrep, they take seconds. AI coding assistants use ripgrep behind the scenes to quickly understand codebases. And when you want to find something yourself, 'rg something' gets you answers instantly.",
    related: ["fzf", "terminal"],
  },

  fzf: {
    term: "fzf",
    short: "Fuzzy finder that lets you search lists by typing approximate matches",
    long: "fzf (fuzzy finder) helps you find items in a list by typing just a few letters from what you remember. The 'fuzzy' part means the letters don't have to be consecutive or exact. Looking for a file called 'user-configuration-settings.json'? Just type 'usrconf' or 'config set' and fzf finds it because those letters appear in that order somewhere in the name. It shows you matching options as you type, and you can arrow down to pick one. fzf works with any list: files in your project, commands you've run before, different versions of your code, or anything else. It's most commonly activated by pressing Ctrl+R to search your command history or Ctrl+T to search for files.",
    analogy: "Think of how Google Search works: you don't need to type the exact title of a webpage to find it; you type some related words and Google figures out what you meant. fzf does the same thing for finding files, commands, and other items on your computer. You type what you vaguely remember, and it shows you matches ranked by how well they match, letting you quickly pick the right one.",
    why: "Human memory is fuzzy. You remember 'that config file with settings' but not 'src/config/application-settings.json'. fzf bridges that gap by letting you type what you remember and quickly finding what you need. When jumping around a project with hundreds of files, this saves enormous amounts of time compared to manually navigating through folder structures.",
    related: ["ripgrep", "zoxide", "terminal"],
  },

  zoxide: {
    term: "zoxide",
    short: "Smart folder navigation that learns where you go and lets you jump there instantly",
    long: "zoxide is a smarter way to navigate between folders. Normally, to go to a folder, you type 'cd' followed by the full path, like 'cd /home/user/projects/my-website/src/components'. With zoxide, you just type 'z components' or even 'z comp', and it takes you there. zoxide works by learning your habits: it remembers folders you've visited and ranks them by 'frecency' (a combination of how frequently and how recently you've visited). So if you visit your project's components folder daily, just 'z comp' will jump straight there, even if you're in a completely different part of the system. First time you visit a folder, use the normal 'cd' command. After that, zoxide remembers and you can use 'z' with just a few letters.",
    analogy: "Imagine a taxi service that learns your routine. The first few times, you give full addresses. But after a while, you just say 'work' and the taxi knows exactly where to go. Say 'gym' and it takes you there. zoxide is that smart taxi for navigating your file system. It learns where you go and takes you there with minimal instructions.",
    why: "Navigating folder structures is surprisingly time-consuming when done traditionally. You have to remember exact paths, type them correctly, or click through folder after folder. With zoxide, folders you use regularly become two or three keystrokes away. Over days and weeks, this saves significant time and mental energy. It's one of those small improvements that makes the terminal feel effortless.",
    related: ["fzf", "terminal"],
  },

  atuin: {
    term: "atuin",
    short: "Enhanced command history that remembers every command you've ever run",
    long: "atuin dramatically upgrades your terminal's command history. Normally, pressing the up arrow cycles through recent commands, but it's hard to find something from weeks ago. atuin replaces this with a fully searchable database of every command you've ever run. Press Ctrl+R and type part of what you remember; atuin shows matching commands with context: which folder you were in, whether the command succeeded or failed, how long it took, and when you ran it. The killer feature: atuin can sync your history across multiple computers (optionally, encrypted), so a command you ran on your cloud server is searchable from your laptop.",
    analogy: "Think of how your phone remembers every text message you've sent, searchable by keywords, synced across devices. atuin does that for terminal commands. That complicated command you figured out three months ago on a different computer? Search for a word you remember, and atuin finds it. No more 'I know I did this before, but how?'",
    why: "Developers constantly re-run variations of complex commands. Without atuin, you might spend 10 minutes trying to reconstruct a command you've run before. With atuin, you search, find it in seconds, and run it again. The sync feature is particularly valuable when you work across multiple computers; your command knowledge follows you everywhere.",
    related: ["zsh", "terminal", "fzf"],
  },

  lsd: {
    term: "lsd",
    short: "A prettier way to list files with colors and icons",
    long: "lsd is an enhanced version of the 'ls' command, which shows you the files in a folder. The basic 'ls' command outputs a plain list of file names in white text. lsd transforms this into a color-coded, icon-enhanced display that's much easier to scan. Different file types get different colors: folders are blue, images are purple, code files are green. Each file type gets a small icon (a folder icon for directories, a picture icon for images, etc.). lsd can also show files as a tree structure to visualize folder hierarchies, and can display whether files have unsaved changes in version control. The result is that finding what you're looking for takes a fraction of a second instead of reading through a wall of text.",
    analogy: "Compare a printed list of ingredients (plain 'ls') to a cookbook photo with ingredients arranged beautifully and labeled (lsd). Both give you the same information, but one is far easier to scan quickly. lsd makes your file listings look organized and professional, saving you mental effort every time you look at a directory's contents.",
    why: "You list directory contents constantly when working in the terminal. Every small improvement in readability compounds across hundreds of daily uses. lsd makes it trivially easy to spot what you're looking for: the folder you want is visibly blue with a folder icon, the config file is yellow with a gear icon. This visual differentiation reduces mistakes and saves time.",
    related: ["terminal", "zsh"],
  },

  direnv: {
    term: "direnv",
    short: "Automatically loads project-specific settings when you enter a folder",
    long: "direnv solves a common problem: different projects need different settings, and it's easy to forget to load them. Environment variables are settings your computer uses to configure software (like 'use this database' or 'here's the password for that service'). Normally, you'd have to remember to load these settings each time you start working on a project. direnv automates this: it watches which folder you're in, and when you enter a project folder that has a settings file (called '.envrc'), it automatically loads those settings. When you leave that folder, it unloads them. This means you can have one project that uses one database and another project that uses a different database, and everything switches correctly just by navigating between folders.",
    analogy: "Think of those automatic doors that open when you approach and close when you leave. direnv is like that for project settings: walk into your project's folder and all its specific settings are automatically loaded; walk out and they disappear. You never have to remember to turn them on or off. This prevents the common mistake of working on one project but accidentally using another project's settings.",
    why: "Environment configuration errors are frustrating and time-consuming to debug. 'Why isn't this connecting to the database? Oh, I forgot to load the settings.' direnv eliminates this entire category of mistakes. Each project becomes self-contained: enter the folder and everything just works correctly.",
    related: ["terminal", "bash"],
  },

  // ═══════════════════════════════════════════════════════════════
  // PROGRAMMING LANGUAGES & RUNTIMES
  // ═══════════════════════════════════════════════════════════════

  bun: {
    term: "bun",
    short: "A very fast tool for running JavaScript and installing packages",
    long: "Bun is a tool for working with JavaScript (the programming language that powers interactive websites). It does several things that traditionally required separate tools: it runs JavaScript code, it downloads and installs code libraries (called packages) that your project depends on, it combines multiple code files into one for deployment, and it runs tests to check your code works. The key selling point is speed: Bun can be 10-100 times faster than the traditional tools it replaces. Installing packages that took 30 seconds with the older tool (npm) takes 2 seconds with Bun. This speed comes from Bun being written in a low-level language (Zig) that runs very close to the hardware, while older tools are written in JavaScript itself.",
    analogy: "Imagine going to a shopping center where the grocery store, hardware store, and pharmacy are all different buildings with separate checkouts, versus a single mega-store where everything is under one roof with express checkouts. That's the difference between the traditional JavaScript tools and Bun. Same result, but much less time walking around and waiting in lines.",
    why: "Speed improvements compound. When installing packages takes 2 seconds instead of 30, you don't mind experimenting with new libraries. When tests run instantly, you run them more often and catch bugs earlier. Bun makes the whole development experience feel snappy and responsive. AI coding assistants use Bun behind the scenes for JavaScript work because it gets things done faster.",
    related: ["uv", "node"],
  },

  uv: {
    term: "uv",
    short: "Very fast tool for installing Python packages (100x faster than the default)",
    long: "uv is a dramatically faster replacement for Python's package installation tools. Python programs often depend on libraries (pre-written code) that need to be downloaded and installed before your program can run. The traditional tool for this (called 'pip') works but is slow: installing a project's dependencies might take 2 minutes of waiting. uv does the same job but about 100 times faster; what took 2 minutes now takes about 2 seconds. This speed comes from uv being written in Rust (a fast, low-level language) and using smarter algorithms for figuring out which packages are compatible with each other.",
    analogy: "Imagine the difference between ordering books from a slow mail service (wait days for each book) versus having a personal assistant with a teleporter who can retrieve any book in seconds. The end result is the same (you have the books you need), but uv gets you there almost instantly while the old tool makes you wait.",
    why: "Python has historically had a reputation for slow package installation. This matters because modern projects can have hundreds of dependencies. With the traditional slow approach, setting up a new project or updating dependencies feels painful. With uv, it's so fast you barely notice. This removes friction from Python development and makes AI coding assistants faster when they need to install Python packages.",
    related: ["bun", "python"],
  },

  rust: {
    term: "Rust",
    short: "A programming language known for producing extremely fast, reliable software",
    long: "Rust is a programming language designed from the ground up to produce fast, reliable software without the common bugs that plague other languages. You won't write Rust directly in this setup, but you'll benefit from tools written in Rust (like ripgrep for searching, lsd for listing files, zoxide for navigation, and uv for Python packages). These tools are all notably faster and more reliable than their predecessors, largely because of Rust's design. Rust forces programmers to handle error cases properly and manages computer memory in a way that prevents entire categories of bugs before the program ever runs. Major tech companies like Mozilla, Amazon, Microsoft, and Google use Rust for critical infrastructure.",
    analogy: "Most programming languages are like building with regular tools where you can accidentally cut yourself or misuse something. Rust is like building with tools that have physical guards and interlocks: they're designed to make it very hard to injure yourself by mistake. You pay a bit more upfront in learning to use the tools, but you almost never have accidents. This is why Rust programs tend to be both fast and reliable.",
    why: "You benefit from Rust indirectly through the tools installed by this setup. When you use ripgrep and searches complete instantly, when you use uv and Python packages install in seconds, that's Rust behind the scenes. Understanding that Rust exists helps explain why these modern tools are so much faster than their predecessors; they're written in a language designed for performance.",
    related: ["go"],
  },

  go: {
    term: "Go",
    short: "A programming language designed for building reliable network services",
    long: "Go (also called Golang) is a programming language created by Google in 2009 specifically for building the kind of software that runs in the cloud: web services, networking tools, and systems that handle many simultaneous users. Go's key feature is simplicity: it has a small set of features that combine well, making code easy to read and maintain. Another key feature is that Go programs compile to a single file that runs without needing anything else installed, making deployment straightforward. Many widely-used infrastructure tools are written in Go: Docker (for running isolated software environments), Kubernetes (for managing many servers), Terraform (for managing cloud resources), and several tools in this setup.",
    analogy: "Different programming languages are like different types of vehicles. Python is a comfortable family SUV, good for many purposes but not the fastest. Rust is a precision racing car, extremely fast but demanding to drive. Go is a reliable work truck: it may not have every feature, but it's simple, sturdy, runs forever without problems, and gets the job done efficiently. For building things that need to run 24/7 handling network requests, Go is an excellent choice.",
    why: "Many of the tools installed by this setup are written in Go. Understanding this helps explain why they're reliable and self-contained. If you end up building web services or network tools with AI assistance, Go is a language worth considering because its simplicity makes code easier to verify and maintain.",
    related: ["rust", "python"],
  },

  python: {
    term: "Python",
    short: "A beginner-friendly programming language popular for AI and data analysis",
    long: "Python is one of the world's most popular programming languages, known for being readable and approachable. Unlike some languages that use lots of symbols and cryptic syntax, Python reads almost like English: 'if item in list: print(item)' does pretty much what it sounds like. This readability has made Python the dominant language for artificial intelligence, data science, and automation scripts. If you want to work with AI (beyond just using AI assistants), you'll likely encounter Python. Most AI tools and frameworks are written in Python or have Python as their primary way of being controlled. That said, you don't need to learn Python to use the Agent Flywheel setup; the AI assistants handle the coding for you.",
    analogy: "Python is the English of programming languages: not always the fastest or most efficient, but very widely understood and excellent for communicating ideas clearly. Just as English became the lingua franca for international business, Python became the lingua franca for AI and data science. When researchers publish AI work, it's almost always in Python.",
    why: "Understanding that Python exists and is the language of AI helps you make sense of what's happening behind the scenes. Many tools installed by this setup either are written in Python or interact with Python code. The AI assistants you use can write Python fluently, and many of the AI-related projects you might build will involve Python.",
    related: ["uv", "go", "rust"],
  },

  node: {
    term: "Node.js",
    short: "A tool that lets JavaScript run outside web browsers",
    long: "Node.js is what lets JavaScript (the programming language of the web) run on servers and computers outside of web browsers. Historically, JavaScript could only run inside web browsers and was used for making websites interactive. In 2009, Node.js changed this by creating a way to run JavaScript anywhere. This was revolutionary because web developers, who already knew JavaScript from building websites, could suddenly use the same language for server-side code, command-line tools, and more. The result is that JavaScript became one of the most versatile languages: the same skills work for websites, servers, mobile apps, and desktop applications. npm (Node Package Manager) provides access to millions of pre-built code libraries.",
    analogy: "Imagine if a language that could only be spoken in one country suddenly became speakable everywhere in the world. That's what Node did for JavaScript: it took a language confined to web browsers and made it universal. Now developers who learned JavaScript for websites can use those same skills to build almost anything.",
    why: "Many development tools and web applications are built with Node.js. While this setup uses Bun (a faster alternative) for running JavaScript, understanding Node helps you comprehend the JavaScript ecosystem. When AI assistants write JavaScript or TypeScript code, they're often writing code that could run on Node.js or Bun.",
    related: ["bun", "python"],
  },

  // ═══════════════════════════════════════════════════════════════
  // AI & AGENTS
  // ═══════════════════════════════════════════════════════════════

  agentic: {
    term: "Agentic",
    short: "AI that takes independent action rather than just answering questions",
    long: "Agentic AI goes beyond answering questions; it takes actions in the real world. Give it a goal ('fix this bug' or 'add a login page'), and it figures out the steps needed: read the relevant code, understand the problem, write a solution, test that it works, save the changes. This is a fundamental shift from AI as a question-answering tool to AI as a capable assistant that does work for you. The key difference is autonomy: instead of you making every decision and the AI just executing, the AI makes many intermediate decisions on its own. You stay in the loop for important choices, but the AI handles the routine problem-solving and execution.",
    analogy: "Traditional AI is like asking a knowledgeable friend for advice: 'What should I do about X?' They tell you, but you still have to do everything yourself. Agentic AI is like hiring a capable contractor: 'I want X done.' They figure out the steps, gather the materials, do the work, and come back with results. You're still the decision-maker, but you're operating at the level of goals rather than individual actions.",
    why: "Agentic AI is why this setup matters. Instead of spending hours writing code yourself with AI suggestions, you can describe what you want and let AI assistants build it while you focus on bigger-picture decisions. It's like having a team of skilled helpers who can execute while you direct. This doesn't mean you're not involved; you're deeply involved in deciding what to build and reviewing results, just not in every keystroke.",
    related: ["ai-agents", "claude-code", "codex"],
  },

  "ai-agents": {
    term: "AI Agents",
    short: "AI programs that can take actions to complete tasks on their own",
    long: "AI agents are programs that combine large AI models (the technology behind ChatGPT, Claude, etc.) with the ability to take actions in the real world: writing and modifying code, creating and editing files, running programs, searching the internet, and more. The word 'agent' emphasizes that these programs have agency; they can decide what to do next based on results, recover when something goes wrong, and pursue multi-step goals. For example, if you ask an AI agent to 'add user authentication to this application,' it might: search the codebase to understand its structure, decide which authentication approach fits best, write the necessary code across multiple files, test that it works, and report back with a summary. Each step involves decisions the agent makes independently.",
    analogy: "Regular AI is like a brilliant consultant who sits in a chair and answers questions. AI agents are like that same brilliant consultant, but now they can get up, walk around your office, use your computer, look through your files, and actually do work. They still need your guidance on what work to do, but they can execute tasks independently rather than just advising you on how to do them yourself.",
    why: "AI agents are the core of what this setup enables. Once your cloud server is configured with these tools, AI agents can work on your projects: writing code, fixing problems, running tests, and building features. You become like a manager directing a team, deciding priorities and reviewing work, rather than doing every task personally. This doesn't replace understanding what's being built; you're deeply involved in guiding and reviewing. But the agents handle execution.",
    related: ["agentic", "claude-code", "codex", "gemini-cli"],
  },

  "claude-code": {
    term: "Claude Code",
    short: "Anthropic's AI coding assistant that runs in your terminal and can edit your files",
    long: "Claude Code is an AI coding assistant made by Anthropic (the company behind Claude). Unlike chatbot interfaces where you copy and paste code back and forth, Claude Code runs directly in your terminal and can read your project files, write new code, edit existing files, run programs to test things, and search the web for information. When you give it a task like 'add a password reset feature,' it explores your project to understand how it's structured, writes the necessary code across potentially multiple files, and can run tests to verify the changes work. It's designed for substantial tasks, not just quick questions. Claude Code asks for your permission before making changes, so you stay in control while it does the detailed work.",
    analogy: "Most AI chatbots are like texting a smart friend for coding advice: they give you suggestions, but you still have to do everything yourself. Claude Code is more like having a developer join a video call where they can see your screen and you can say 'go ahead and make that change.' They understand your project, make the edits directly, and you can review what they did. The difference is between receiving instructions and receiving completed work.",
    why: "Claude Code is one of the primary AI assistants in the Agent Flywheel setup. It's known for producing high-quality code and being able to handle complex, multi-step tasks. When you have substantial work to do (implementing features, fixing complex bugs, restructuring code), Claude Code can often complete it with minimal guidance. The installer sets it up so you can start using it immediately after setup completes.",
    related: ["ai-agents", "codex", "gemini-cli", "agentic"],
  },

  codex: {
    term: "Codex CLI",
    short: "OpenAI's command-line coding assistant",
    long: "Codex CLI is OpenAI's terminal-based coding assistant, built on the same AI technology that powers ChatGPT. Like Claude Code, it runs in your terminal and can understand your project, write code, run commands, and help with development tasks. It integrates directly into your workflow, meaning you don't have to copy and paste back and forth. Different AI models have different strengths; some excel at certain types of problems or coding styles. Having Codex available alongside Claude Code gives you options when one approach isn't working or when you want a second opinion on a complex problem.",
    analogy: "If Claude Code is like having one brilliant developer available to help, Codex is like having a second brilliant developer from a different background. They might approach problems differently, have different knowledge, or excel at different types of tasks. Having both available means you can get diverse perspectives and choose the best solution.",
    why: "Having multiple AI assistants gives you flexibility. Sometimes one model produces better results for a particular task, or you want to compare approaches. The Agent Flywheel installs Codex alongside Claude Code so you can easily switch between them or even use them on different parts of a project.",
    related: ["ai-agents", "claude-code", "gemini-cli"],
  },

  "gemini-cli": {
    term: "Gemini CLI",
    short: "Google's AI assistant for your terminal",
    long: "Gemini CLI brings Google's Gemini 3 AI model to your command line, giving you a third AI assistant alongside Claude Code and Codex. Like the others, it runs in your terminal and can help with coding questions, generate code, explain concepts, and assist with development tasks. Gemini 3 is Google's latest AI system, offering capabilities that sometimes differ from what Claude Opus 4.5 or GPT-5.2 provide. Having multiple AI assistants is like having multiple experts with different backgrounds; they might approach problems differently or have different knowledge.",
    analogy: "If Claude Code and Codex are two brilliant developers on your team, Gemini CLI is a third developer from a completely different company with a different training background. They've read different things, excel at different problems, and sometimes one will have an insight the others miss. Having all three available means you can get diverse perspectives.",
    why: "Different AI models genuinely have different strengths. Some are better at explaining complex concepts, some at generating creative solutions, some at careful analysis. The Agent Flywheel installs all three major AI assistants so you can choose the best one for each situation, or compare their approaches when facing a tricky problem.",
    related: ["ai-agents", "claude-code", "codex"],
  },

  // ═══════════════════════════════════════════════════════════════
  // SECURITY & TECHNICAL CONCEPTS
  // ═══════════════════════════════════════════════════════════════

  idempotent: {
    term: "Idempotent",
    short: "Safe to run multiple times without causing duplicate effects",
    long: "An idempotent operation produces the same result no matter how many times you run it. The Agent Flywheel installer is designed to be idempotent: if you run it once, it installs everything. If you run it again, it checks what's already installed and only fixes what's missing. You don't end up with duplicate installations or corrupted settings. This is critical for reliability because installations often fail partway through (network interruptions, temporary server problems, etc.). With idempotent design, you can safely re-run the installer from the beginning whenever something goes wrong, without needing to clean up or uninstall first.",
    analogy: "Think about pressing an elevator button. Pressing it once calls the elevator to your floor. Pressing it ten more times doesn't call ten more elevators or make the first one arrive faster; the outcome is exactly the same regardless of how many times you press. Similarly, running an idempotent installer multiple times leaves your system in exactly the same correct state, not a more-installed or broken state.",
    why: "Real-world installations frequently fail partway through. Internet connections drop, servers have temporary outages, permissions sometimes need adjustment. Without idempotent design, a failed installation leaves your system in a broken half-installed state that's hard to fix. With idempotent design, you just run the installer again, and it picks up where it left off or verifies everything is correct. It removes the fear of 'what if something goes wrong?'",
    related: ["sha256"],
  },

  sha256: {
    term: "SHA256",
    short: "A digital fingerprint that proves a file hasn't been changed",
    long: "SHA256 is a mathematical formula that creates a unique 'fingerprint' (a long string of letters and numbers) for any file. This fingerprint has a special property: if even a single character in the file changes, the fingerprint becomes completely different. So you can check if a file has been tampered with by comparing its fingerprint to the expected one. The Agent Flywheel uses this to verify that installation scripts downloaded from the internet are exactly what the original authors intended, not versions modified by hackers. When you see something like 'SHA256: 3a7f9c2...' next to a download, that's the expected fingerprint you can compare against.",
    analogy: "Think of it like a tamper-evident seal on a package. The seal itself doesn't tell you who shipped it, but if you have the official seal number from a trusted source, you can tell whether the package arrived untouched.",
    why: "Running downloaded code is risky because a modified script can do anything your computer can do. SHA256 verification is a simple check that answers: \"Is this exactly the file I expected?\" When the expected hash comes from a trusted place, it's a strong defense against accidental corruption and many kinds of tampering.",
    related: ["idempotent", "fingerprint"],
  },

  passphrase: {
    term: "Passphrase",
    short: "An optional password that protects your SSH private key",
    long: "A passphrase is a password you can add to your SSH private key for extra security. Without a passphrase, anyone who gets your private key file can use it immediately. With a passphrase, they'd also need to know the password. When you set a passphrase, you'll be prompted to enter it each time you use the key (though SSH agents can remember it for your session). For AI coding workflows, we often skip the passphrase because agents need to connect non-interactively.",
    analogy: "Like a PIN on your phone. Even if someone steals your phone (gets your key file), they still need the PIN (passphrase) to access it. Without the PIN, the phone is useless to them.",
    why: "Passphrases add a second layer of security, but they require human interaction to enter. For automated workflows where agents connect to servers, passphrase-less keys are common. For personal use, a passphrase is recommended since you can use an SSH agent to remember it.",
    related: ["private-key", "ssh-key", "ssh"],
  },

  chmod: {
    term: "chmod",
    short: "Change file permissions, controlling who can read, write, or execute a file",
    long: "chmod (change mode) is a Linux command that sets file permissions. Every file has three permission types (read, write, execute) for three groups (owner, group, others). 'chmod 600' means only the owner can read and write. 'chmod 700' means only the owner can read, write, and execute. SSH private keys must be chmod 600 or 700, otherwise SSH refuses to use them (this is a security requirement).",
    analogy: "Like access levels in a building. Some rooms are 'employees only' (owner), some are 'department access' (group), and some are 'public' (others). chmod sets who can enter (read), who can modify things (write), and who can use the equipment (execute).",
    why: "When SSH says 'permissions too open,' it means your private key is readable by others and could be stolen. Running 'chmod 600 ~/.ssh/acfs_ed25519' fixes this by making it owner-only. This is one of the most common SSH troubleshooting steps.",
    related: ["private-key", "ssh", "terminal"],
  },

  ed25519: {
    term: "Ed25519",
    short: "A modern, fast, and secure type of SSH key (recommended over older RSA)",
    long: "Ed25519 is a modern cryptographic algorithm for SSH keys. It's faster, more secure, and produces shorter keys than the older RSA algorithm. Ed25519 keys are 256 bits but provide security equivalent to 3000-bit RSA keys. All modern SSH implementations support Ed25519, and it's now the recommended default for new SSH keys.",
    analogy: "Like the difference between a heavy old safe and a modern lightweight one. The new safe is actually more secure AND easier to carry around. Ed25519 is the 'new safe'; better security in a smaller package.",
    why: "We use Ed25519 for the SSH keys generated by the wizard because it's the most secure option that works everywhere. The key file is named 'acfs_ed25519' because it uses this algorithm. If a server doesn't accept it (very rare, usually ancient systems), RSA is the fallback.",
    related: ["ssh-key", "private-key", "public-key"],
  },

  lts: {
    term: "LTS",
    short: "Long Term Support, a version that receives security updates for 5+ years",
    long: "LTS (Long Term Support) versions of software get bug fixes and security updates for an extended period, typically 5 years for Ubuntu. Regular releases might only get 9 months of support. For example, Ubuntu 24.04 LTS will receive updates until 2029, while Ubuntu 23.10 (non-LTS) stopped receiving updates in mid-2024. LTS releases prioritize stability over cutting-edge features.",
    analogy: "Like buying a car with a 5-year warranty versus a 9-month warranty. The LTS car might not have the absolute latest features, but you know it'll be maintained and supported for years to come.",
    why: "We recommend Ubuntu LTS versions for VPS because servers need reliability. You don't want your production environment to suddenly need an OS upgrade because support ended. LTS gives you a stable, long-lived foundation.",
    related: ["ubuntu", "linux", "vps"],
  },

  sudo: {
    term: "sudo",
    short: "Run a command as administrator (superuser)",
    long: "sudo ('superuser do') runs a command with administrator privileges. Some actions like installing system software or modifying system files require elevated permissions. When you prefix a command with 'sudo', you're saying 'run this as the all-powerful root user.' You'll be asked for your password to confirm.",
    analogy: "It's like a master key that opens any door. Most of the time you use your regular key, but sometimes you need the master key to access restricted areas.",
    why: "Installing development tools requires system-level access. sudo provides that access while still requiring confirmation, balancing convenience and security.",
    related: ["bash", "terminal"],
  },

  api: {
    term: "API",
    short: "Application Programming Interface, a way for programs to exchange information",
    long: "An API (Application Programming Interface) is a structured way for programs to communicate with each other. Instead of humans clicking buttons, programs send precisely formatted requests and receive precisely formatted responses. For example, when Claude Code sends your prompt to the AI, it's making an API call: sending a message in a specific format and receiving the AI's response in a specific format. When an app shows you the weather, it asked a weather service's API 'what's the temperature in this city?' and received a structured answer. APIs are everywhere: payment processing, social media posting, file storage, AI models. They're the invisible communication layer that makes modern software work.",
    analogy: "A restaurant menu is an API. It lists what you can order (the requests the kitchen accepts) and describes what you'll receive (the responses). You don't need to know how the kitchen works, who the chefs are, or where they get ingredients. You just need to order from the menu correctly, and you'll get what you asked for. APIs work the same way: follow the specified format, and you get the expected result.",
    why: "AI assistants work almost entirely through APIs. When Claude Code helps you, it's sending your questions to an AI service's API and receiving responses. When it searches the web, that's another API. Understanding this helps you see how the pieces fit together, and why things like API keys (passwords for APIs) and rate limits (restrictions on how often you can call) matter.",
    related: ["cli", "rate-limits"],
  },

  // ═══════════════════════════════════════════════════════════════
  // OPERATING SYSTEMS & PLATFORMS
  // ═══════════════════════════════════════════════════════════════

  ubuntu: {
    term: "Ubuntu",
    short: "A popular, beginner-friendly version of Linux",
    long: "Ubuntu is one of the most popular versions ('distributions') of Linux. It's completely free, extremely well-documented, has a huge community ready to help with questions, and is the default choice on most cloud server providers. When you create a VPS, 'Ubuntu' will likely be the first operating system option listed. Ubuntu releases new versions every 6 months, with special 'LTS' (Long Term Support) versions every 2 years that receive security updates for 5 years. Because Ubuntu is so popular, most tutorials and guides assume you're using it, and AI assistants have seen so much Ubuntu-related training data that they're particularly good at helping with it.",
    analogy: "If Linux is a type of cuisine (like 'Italian food'), Ubuntu is a specific popular restaurant chain serving that cuisine. There are other Linux restaurants (Debian, Fedora, Arch), but Ubuntu is the one most people recognize, most delivery services support, and most recipes are written for. Choosing Ubuntu means you'll find the most help and the fewest surprises.",
    why: "The Agent Flywheel targets Ubuntu because it's the most common server operating system. Almost every cloud provider offers Ubuntu, almost every tutorial assumes Ubuntu, and almost every AI assistant can help with Ubuntu questions. When the installer runs, it's running commands designed and tested for Ubuntu.",
    related: ["linux", "vps", "lts"],
  },

  linux: {
    term: "Linux",
    short: "A free operating system that powers most of the internet",
    long: "Linux is an operating system, the fundamental software that controls your computer (like Windows on PCs or macOS on Macs). Unlike those commercial options, Linux is free and 'open source' (anyone can see and modify its code). Linux powers most of the internet's infrastructure: web servers, cloud platforms, Android phones, smart TVs, routers, and even NASA's Mars rovers and the International Space Station computers. While it's less common on personal desktops, Linux absolutely dominates servers because it's free (no licensing costs), extremely stable (servers often run for years without rebooting), and highly customizable (you can strip out what you don't need). Created in 1991 by Linus Torvalds, Linux is now developed by thousands of contributors worldwide.",
    analogy: "Windows and macOS are like apartments in buildings owned by Microsoft and Apple. You pay rent (licenses), you follow their rules, and they control what you can modify. Linux is like owning your own land: it's completely free, you can build whatever you want, and a global community of neighbors is happy to help you with construction advice. The tradeoff is you need to be comfortable with more hands-on management.",
    why: "Cloud servers run Linux because it's free, stable, and powerful. The commands you'll type during setup are Linux commands. The AI assistants were trained heavily on Linux systems. Understanding that you're entering the Linux world helps frame the whole experience: you're not clicking through Windows menus, you're typing commands that give you precise control over a powerful server operating system.",
    related: ["ubuntu", "bash", "terminal"],
  },

  // ═══════════════════════════════════════════════════════════════
  // FLYWHEEL ECOSYSTEM
  // ═══════════════════════════════════════════════════════════════

  ntm: {
    term: "NTM",
    short: "Named Tmux Manager, a control center for running multiple AI agents",
    long: "NTM (Named Tmux Manager) is a tool for organizing and managing multiple terminal sessions where AI agents are running. When you're working with several AI assistants simultaneously (perhaps one writing code, one running tests, one fixing bugs), keeping track of them becomes challenging. NTM provides a unified interface: you can see all your running sessions at a glance, switch between them instantly, and manage the whole operation from one place. It builds on top of tmux (the terminal persistence tool) by adding a layer of organization specifically designed for managing AI agent workflows.",
    analogy: "NTM is like air traffic control for AI agents. Instead of looking out the window and trying to spot planes (terminal windows scattered across your screen), you have a radar display showing all flights (agent sessions) with their status. You can communicate with any flight, see which ones are active, and keep everything organized even when many things are happening simultaneously.",
    why: "When running multiple AI agents, organization becomes critical. Without NTM, you'd have multiple terminal windows scattered around, possibly losing track of which agent is doing what. NTM prevents that chaos by giving you a single command center. You can start work, step away for hours, come back, and immediately see the status of all your agents and what they've accomplished.",
    related: ["tmux", "ai-agents", "parallel-agents"],
  },

  "agent-mail": {
    term: "Agent Mail",
    short: "A messaging system that lets AI agents coordinate with each other",
    long: "Agent Mail provides an inbox and outbox system for AI agents to communicate when working on the same project. Think about what happens when multiple people edit the same document without talking: chaos and conflicting changes. AI agents have the same problem. Agent Mail lets agents leave messages for each other ('I'm working on the login feature, don't touch those files'), claim files they're editing (so others know to stay away), and coordinate handoffs ('I finished the database changes, someone can now write the API'). It stores messages in a structured format that persists between sessions, so even if an agent shuts down and restarts, it can catch up on what happened.",
    analogy: "Imagine a shared bulletin board in an office where team members can leave notes for each other: 'Working on the Johnson account until 3 PM,' 'Budget report is ready for review,' 'Don't touch the printer, it's being serviced.' Agent Mail is that bulletin board for AI assistants. They check it before starting work, post updates about what they're doing, and leave messages for colleagues who might work on related things.",
    why: "Multiple AI agents working on the same codebase can easily step on each other's toes. One agent edits a file while another is trying to edit the same file, causing conflicts. Agent Mail prevents this by enabling coordination. Agents can claim ownership of files, signal when they're done, and leave context for whoever picks up the work next. It's essential for the 'parallel agents' workflow where multiple assistants tackle different parts of a project simultaneously.",
    related: ["ai-agents", "ntm", "parallel-agents"],
  },

  flywheel: {
    term: "Flywheel",
    short: "A self-reinforcing system where each part makes the others more effective",
    long: "A flywheel is a heavy wheel that stores rotational energy. Once you get it spinning, it wants to keep spinning; each push adds to its momentum. In business and product design, 'flywheel' describes a system where each component reinforces the others, creating a positive feedback loop. The 'Agentic Coding Flywheel' means the tools in this setup aren't random; each one makes the others more powerful. Fast search (ripgrep) helps agents understand code quickly. Task tracking (Beads) helps them know what to work on. Coordination (Agent Mail) prevents conflicts. Session persistence (tmux/NTM) lets work continue across time. Together, they create a system greater than the sum of its parts.",
    analogy: "Think of compound interest. A small improvement today doesn't just help once—it makes the next improvement easier and more valuable. The Agent Flywheel is built for that kind of compounding: each tool makes the others work better, so your overall output grows faster than any single change would suggest.",
    why: "Understanding the flywheel concept helps you see why this specific set of tools matters. We didn't pick them randomly; each one was chosen because it amplifies the effectiveness of the others. If you're wondering 'why so many tools?', the answer is that they work together as a system. Removing one would weaken the whole setup, like removing a spoke from a wheel.",
    related: ["agentic", "ai-agents", "parallel-agents"],
  },

  beads: {
    term: "Beads",
    short: "A task tracking system designed specifically for AI coding agents",
    long: "Beads is a task management system that solves a critical problem: AI agents lose their memory between sessions. When you close a session and come back later, the AI doesn't remember what was done, what's left to do, or what depends on what. Beads provides that memory. It stores tasks in a structured format within your project (in a .beads/ folder that's saved with your code). Each task has a unique ID, can list other tasks it depends on, and tracks its status. Crucially, Beads understands dependencies: if Task B depends on Task A, it won't show Task B as 'ready to work on' until Task A is complete. This makes complex, multi-step projects manageable across many sessions and multiple AI agents.",
    analogy: "Beads is like a project manager who never forgets anything and never goes home. They know every task, every dependency, every completion status. When a new AI agent shows up and asks 'what should I work on?', Beads can instantly answer: 'Task 14 and 17 are ready because their dependencies are complete, but Task 15 is blocked until Task 12 finishes.' This coordination happens automatically, without requiring humans to track everything manually.",
    why: "Beads is central to how the Agent Flywheel workflow operates. You start by planning (perhaps using ChatGPT 5.2 Pro for deep thinking), then break that plan into tasks tracked by Beads. AI agents check Beads to find available work. They mark tasks complete when done. Everything persists in your project's version control, so work is never lost. Commands like 'br ready' (show tasks ready to work on), 'br create' (add a new task), and 'br close' (mark a task done) make it easy to interact with.",
    related: ["ai-agents", "ntm", "agent-mail", "git"],
  },

  ru: {
    term: "RU",
    short: "Repo Updater, a tool for syncing and managing multiple GitHub repositories",
    long: "RU (Repo Updater) solves the multi-repo management problem. When you have 20+ GitHub repos to keep in sync, manually running 'cd repo; git pull' for each one is tedious and error-prone. RU syncs all your repos with one command, using parallel workers for speed. Even better, it has Agent Sweep: an AI-driven commit automation system that analyzes dirty repos, understands the changes, and creates intelligent commit messages. RU uses pure git plumbing (no string parsing), making it locale-safe and reliable.",
    analogy: "RU is like having a diligent assistant who manages all your filing cabinets. Every morning, they check each cabinet for updates, pull in any new documents, and flag anything that needs your attention. And when you've made changes to several cabinets, they can intelligently organize and label your work without you specifying every detail.",
    why: "Multi-repo workflows are common in serious development. A project might span a frontend repo, backend repo, shared libraries, deployment configs, and documentation. RU keeps them all synchronized and enables AI agents to commit across your entire fleet of repos intelligently.",
    related: ["git", "ntm", "agent-mail", "beads"],
  },

  "agent-sweep": {
    term: "Agent Sweep",
    short: "RU's AI-powered commit automation feature",
    long: "Agent Sweep is a three-phase AI workflow built into RU. Phase 1: Understand (agent reads AGENTS.md, explores codebase, learns conventions). Phase 2: Plan (agent produces a JSON commit plan with files and messages). Phase 3: Execute (RU validates the plan and executes with deterministic git commands). This lets you commit changes across many repos with intelligent, contextual messages without manually writing each commit message.",
    analogy: "Imagine an assistant who visits each of your workstations, reviews what you've been working on, understands the context, writes professional notes about the changes, and files everything properly. Agent Sweep does this for your dirty repos, creating thoughtful commits that explain what changed and why.",
    why: "Manual commit messages become a bottleneck when working across many repos. Agent Sweep removes that friction by intelligently analyzing changes and creating meaningful commits. Always run with '--dry-run' first to preview what it will do.",
    related: ["ru", "git", "ai-agents"],
  },

  "parallel-sync": {
    term: "Parallel Sync",
    short: "RU's ability to sync multiple repos simultaneously using worker threads",
    long: "When you run 'ru sync -j4', RU uses 4 parallel workers to sync repos simultaneously. Instead of waiting for each repo to finish before starting the next, it processes multiple repos at once using a work-stealing queue. This can make syncing 20+ repos take minutes instead of much longer. The number after -j controls how many parallel workers to use.",
    analogy: "Like having 4 assistants organizing filing cabinets instead of 1. Each assistant works on a different cabinet, and when they finish one, they grab the next from the queue. The whole job finishes much faster.",
    why: "Time adds up when managing many repos. Parallel sync dramatically reduces wait time when starting your day or when you need all repos current before a major operation.",
    related: ["ru"],
  },

  "open-source": {
    term: "Open-source",
    short: "Software whose code is publicly available for anyone to inspect, use, and improve",
    long: "Open-source software makes its underlying code freely available to the public. Unlike proprietary software where the code is secret, open-source lets anyone read the code (to verify it's not doing anything harmful), modify it (to fix bugs or add features), and share their improvements. This model has produced some of the world's most important software: Linux (operating system), Firefox (web browser), Python (programming language), Git (version control), and countless development tools. Open-source projects are typically maintained by communities of volunteers and companies who benefit from the shared infrastructure.",
    analogy: "Open-source is like a recipe that anyone can read, cook from, modify, and share. A restaurant might keep its recipes secret, but open-source is like a community cookbook where everyone contributes their best recipes. No secrets, no license fees, and if you want to add more garlic, you're free to fork off and make your own version.",
    why: "All tools in the Agent Flywheel are open-source. This matters for several reasons: (1) Security: you can verify the code isn't malicious, (2) Cost: there are no license fees, (3) Longevity: even if the original author disappears, the community can continue maintaining it, (4) Customization: if something doesn't work for you, you or others can fix it. Open-source is the foundation of modern software development.",
    related: ["linux", "git"],
  },

  // ═══════════════════════════════════════════════════════════════
  // ADDITIONAL TERMS FOR CLARITY
  // ═══════════════════════════════════════════════════════════════

  "one-liner": {
    term: "One-liner",
    short: "A single command that does everything; just copy, paste, and run",
    long: "A one-liner is a complete operation condensed into a single command you can copy and paste. Instead of running 50 separate commands, one well-crafted one-liner does everything automatically. For example, our install command downloads the script, sets up your environment, installs all tools, and configures everything from one paste.",
    analogy: "Like signing one well-prepared form instead of filling out fifty separate fields across a dozen pages. One action kicks off the whole process.",
    why: "One-liners remove friction. Instead of following 50 steps where you might make a typo or miss something, you just paste one command and everything works.",
    related: ["curl", "bash"],
  },

  dependency: {
    term: "Dependency",
    short: "A tool or library that other software needs to work",
    long: "A dependency is something your software relies on. If you're building a house, lumber is a dependency because you can't build without it. In software, dependencies are libraries, tools, or programs that your code needs. 'Dependency hell' happens when different programs need conflicting versions of the same dependency.",
    analogy: "Like a recipe that requires flour. Flour is a dependency because you can't make the recipe without it. Some recipes share ingredients, others conflict (you can't use the same flour for two recipes at once).",
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
    short: "The engine that actually executes your code",
    long: "A runtime is the program that takes your code and actually runs it. Code files are just text; they don't do anything on their own. A runtime reads that text, understands what it means, and makes it happen. JavaScript code needs a JavaScript runtime (like Node.js or Bun) to run. Python code needs a Python runtime. Think of the runtime as a translator and executor: it reads your instructions in a programming language and translates them into actions the computer can actually perform.",
    analogy: "If your code is sheet music, the runtime is the musician who actually plays it. The sheet music just sits there being paper until a musician reads it and produces sound. Different musicians (runtimes) might play the same piece at different speeds or with different styles.",
    why: "Different runtimes have dramatically different speeds. Bun runs JavaScript about 3-10 times faster than Node.js for many tasks. The Agent Flywheel installs the fastest, most modern runtimes so your AI agents and tools operate as quickly as possible.",
    related: ["bun", "node", "python"],
  },

  llm: {
    term: "LLM",
    short: "Large Language Model, the AI technology behind ChatGPT, Claude, and Gemini",
    long: "An LLM (Large Language Model) is the technology that powers AI assistants like ChatGPT, Claude, and Gemini. At a very high level, it's a sophisticated prediction system trained on vast amounts of text (books, websites, code, conversations) that learned patterns in how language works. When you ask it something, it predicts what a helpful response would look like based on those patterns. LLMs can understand context, follow complex instructions, write code, explain concepts, and reason through multi-step problems. They're called 'large' because modern ones involve hundreds of billions of learned patterns, making them much more capable than earlier AI systems.",
    analogy: "Imagine someone who has read billions of documents, every book ever written, vast amounts of code, countless conversations, and absorbed all the patterns of how helpful responses look. When you ask them a question, they draw on all that absorbed knowledge to predict what a helpful answer would be. They don't 'know' things the way humans do; they recognize patterns and generate responses that match those patterns.",
    why: "AI coding agents are powered by LLMs. Understanding this helps set realistic expectations: LLMs are incredibly capable at pattern recognition and language tasks, but they can sometimes generate plausible-sounding wrong answers because they're predicting what looks right, not recalling facts from memory. Verification and review of AI output remains important.",
    related: ["ai-agents", "agentic", "claude-code", "token"],
  },

  prompt: {
    term: "Prompt",
    short: "The message or instruction you give to an AI",
    long: "A prompt is what you type to tell an AI what you want. It can be a question ('How do I fix this error?'), a command ('Write a function that calculates sales tax'), or context plus a request ('Given this code, find the bug'). The quality of your prompt dramatically affects the quality of the response. Being specific, providing context, stating your goal clearly, and giving examples of what you want all help the AI produce better results. Vague prompts get vague results; detailed prompts get detailed results.",
    analogy: "Think of giving instructions to a very literal, very capable assistant who has never seen your project before. 'Make dinner' might produce something random because they don't know your preferences. 'Make spaghetti carbonara for four people, using the pancetta in the fridge' gets exactly what you want because you were specific. AI prompts work the same way: the more context and specificity you provide, the better the result.",
    why: "AI agents are only as effective as the prompts they receive. A well-crafted prompt can get an AI to produce production-ready code; a vague prompt might produce something that needs significant revision. Learning to write clear prompts is one of the highest-leverage skills for working with AI assistants.",
    related: ["llm", "ai-agents"],
  },

  token: {
    term: "Token",
    short: "A chunk of text that AI processes, roughly one word or 4 characters",
    long: "When AI reads text, it doesn't process individual letters. Instead, it breaks text into 'tokens,' which are roughly word-sized chunks. 'Hello' is one token. 'World' is one token. 'Unbelievable' might be split into two or three tokens. On average, one token equals about 4 characters or 0.75 words. This matters because AI systems have limits on how many tokens they can process at once, and API pricing is often based on tokens. When someone says 'Claude has a 200K token context window,' they mean it can process about 150,000 words at once.",
    analogy: "Tokens are like the 'words' in the AI's vocabulary. Just as you read text word by word rather than letter by letter, the AI processes text token by token. Some tokens are whole common words; some are pieces of less common words joined together. The AI learned these chunks during training.",
    why: "Understanding tokens helps you understand AI limitations. If an AI says 'context limit reached,' it means too many tokens. If you're comparing AI costs, you'll see pricing per thousand tokens. And if a codebase is very large, an AI might not be able to analyze all of it at once because of token limits.",
    related: ["llm", "context-window"],
  },

  "context-window": {
    term: "Context Window",
    short: "How much text an AI can 'see' and remember in a single conversation",
    long: "The context window is the AI's working memory for a conversation. Everything you've said, everything the AI has said, any code or documents you've shared, must fit within this window. Claude has a 200,000 token context window, meaning it can hold about 150,000 words in a single conversation. If you share a 500-page book plus ask questions about it, that all needs to fit in the window. When the conversation exceeds the window size, older parts get dropped and the AI no longer 'remembers' them. Newer AI models have much larger context windows than older ones, which is why they can analyze larger codebases and maintain longer conversations.",
    analogy: "Think of a whiteboard for a meeting. A small whiteboard means you can only see and work with a little information at once; you have to erase old notes to make room for new ones. A massive wall-sized whiteboard lets you keep everything visible and reference it all. Claude's 200K token window is like a very large whiteboard: you can share substantial amounts of code and conversation before anything needs to be erased.",
    why: "Context window size is crucial for coding work. A larger window means an AI can understand more of your codebase at once. It can hold the conversation history, the code you've shared, its previous responses, and still have room to reason about complex problems. This is why newer models with larger context windows are better at substantial coding tasks.",
    related: ["llm", "token", "prompt"],
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
    analogy: "Like a project folder with a time machine attached. You can see every version of every file, who changed what, and when, all the way back to the project's beginning.",
    why: "All serious software lives in repositories. Git repos enable collaboration, backup, and deployment. If your code isn't in a repo, it's at risk.",
    related: ["git", "lazygit", "github"],
  },

  github: {
    term: "GitHub",
    short: "The world's largest code hosting platform, owned by Microsoft",
    long: "GitHub is where most open-source code lives. It hosts Git repositories in the cloud, provides collaboration tools (pull requests, issues, code review), and offers GitHub Actions for CI/CD automation. Public repositories are free and unlimited. Private repositories are free for individuals (with some limits) but teams and heavy Actions usage may require a paid plan ($4-21/user/month). GitHub is the de facto standard; having your code on GitHub means it's backed up, shareable, and ready for collaboration.",
    analogy: "Like Google Drive but specifically for code, with built-in tools for collaboration, code review, and automation. It's where developers store, share, and work on code together.",
    why: "GitHub IS your backup strategy. If your VPS dies, your code is safe on GitHub. We use the 'gh' CLI to interact with GitHub from the terminal. For open-source projects, everything (repos, Actions, Pages) is free. Private projects may need GitHub Pro or Team for unlimited Actions minutes and advanced features.",
    related: ["git", "repository", "deployment"],
  },

  webhook: {
    term: "Webhook",
    short: "An automatic notification sent when something happens",
    long: "A webhook is like a doorbell that rings automatically when something happens. Instead of constantly checking 'did anything change?' (polling), webhooks let a service notify you instantly. For example, GitHub can send a webhook when code is pushed, Stripe when a payment is made, or a monitoring service when a server goes down.",
    analogy: "Instead of repeatedly checking your mailbox to see if mail arrived, it's like having a doorbell that rings the moment mail is delivered.",
    why: "Webhooks enable automation. AI agents can be triggered by webhooks, for example, automatically reviewing code when a pull request is opened.",
    related: ["api"],
  },

  deployment: {
    term: "Deployment",
    short: "Making your code live and available to users",
    long: "Deployment is the process of taking code from development and making it available in production (the real world). This might involve building the code, running tests, uploading to servers, updating databases, and verifying everything works. Modern deployments are often automated: push code to Git and everything happens automatically.",
    analogy: "Like a restaurant's process for serving a new dish: test the recipe, prepare ingredients, train staff, then officially add it to the menu. Deployment is the moment your code goes 'on the menu.'",
    why: "Agent Flywheel includes deployment tools like Vercel CLI so you can deploy instantly. No more manual FTP uploads or complex server configurations.",
    related: ["git", "repository"],
  },

  "ci-cd": {
    term: "CI/CD",
    short: "Continuous Integration/Continuous Deployment, automated testing and deployment",
    long: "CI/CD is a practice where code changes are automatically tested and deployed. Continuous Integration (CI) means every code push triggers automated tests, catching bugs immediately. Continuous Deployment (CD) means if tests pass, the code is automatically deployed to production. GitHub Actions, GitLab CI, and CircleCI are popular CI/CD tools. The goal is: push code, tests run automatically, and if everything passes, your changes go live without manual intervention.",
    analogy: "Like a conveyor belt at a factory. Parts (code) go in, automated quality checks (tests) happen at each station, and if everything passes, the finished product (deployment) comes out the other end. No human needed to manually inspect each piece.",
    why: "CI/CD prevents 'it works on my machine' problems by testing in a consistent environment. It also means deployments are fast and safe; push a button (or just push code) and your changes are live. AI agents can trigger CI/CD pipelines to test their own code.",
    related: ["github", "deployment", "git"],
  },

  "rate-limits": {
    term: "Rate Limits",
    short: "Restrictions on how many API requests you can make per minute/hour",
    long: "Rate limits are caps that API providers place on how many requests you can make in a given time period. For example, an AI API might allow 60 requests per minute. If you exceed this, you'll get an error (usually HTTP 429 'Too Many Requests') and have to wait before making more. Rate limits prevent abuse and ensure fair access for all users. Higher-tier API plans typically have higher rate limits.",
    analogy: "Like a buffet with a 'maximum 3 plates per person' rule. You can eat as much as you want from each plate, but you can only go up to the buffet so many times. Rate limits ensure everyone gets a turn.",
    why: "AI agents can make many API calls quickly, especially when running multiple agents in parallel. Understanding rate limits helps you plan your workflow: you might need multiple API keys, paid tiers, or pacing to avoid hitting limits. Rate limits are also why running your own VPS (for compute) matters, since you're not competing for API resources with other users.",
    related: ["api", "ai-agents"],
  },

  codebase: {
    term: "Codebase",
    short: "All the source code files that make up a software project",
    long: "A codebase is the complete collection of source code for a software project. It includes all the programming files, configuration, tests, documentation, and everything needed to build and run the software. 'Large codebase' typically means tens of thousands to millions of lines of code. 'Navigate the codebase' means finding your way around all these files to understand how things work.",
    analogy: "Like all the blueprints, wiring diagrams, plumbing plans, and material specs for a building. The codebase is everything needed to understand and modify the software 'building.'",
    why: "AI agents are particularly good at navigating large codebases. While humans get lost in thousands of files, agents with tools like ripgrep can search and understand code across the entire project in seconds.",
    related: ["repository", "git"],
  },

  production: {
    term: "Production",
    short: "The live environment where real users interact with your software",
    long: "Production (or 'prod') is the live, real-world version of your software that actual users see and use. It's opposed to 'development' (where you write code) and 'staging' (where you test before going live). 'Push to production' means deploying your code so users can see it. 'Production bug' is a bug affecting real users. Production environments have stricter requirements: they must be reliable, fast, and secure.",
    analogy: "Development is the dress rehearsal, staging is the preview performance, and production is opening night with a paying audience. Mistakes in production have real consequences.",
    why: "Understanding the dev/staging/prod distinction helps you work safely. You experiment in development, verify in staging, and only push to production when you're confident. AI agents should generally work in development, with human oversight before production changes.",
    related: ["deployment", "environment"],
  },

  environment: {
    term: "Environment",
    short: "A complete setup where code runs, like development, staging, or production",
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
    why: "Scripts automate repetitive tasks and ensure consistency. Our install script means you don't have to manually type hundreds of commands; one script does everything perfectly every time.",
    related: ["bash", "one-liner", "curl"],
  },

  "root-user": {
    term: "Root User",
    short: "The superuser account with unlimited control over a Linux system",
    long: "The root user (also called 'superuser') has complete control over a Linux system: it can modify any file, install any software, and change any setting. Root access is powerful but dangerous; a mistake as root can break your entire system. That's why we switch to a regular 'ubuntu' user for day-to-day work, only using root powers when absolutely necessary.",
    analogy: "Like the master key to a building. The janitor with the master key can open any door, but you wouldn't use it for everyday access since it's too risky if it gets lost or misused.",
    why: "The installer runs as root to set everything up, then creates a safer 'ubuntu' user for your actual work. This follows security best practices.",
    related: ["sudo", "ubuntu-user"],
  },

  "ubuntu-user": {
    term: "Ubuntu User",
    short: "A regular user account for safe day-to-day work",
    long: "The 'ubuntu' user is a standard Linux account created during VPS setup. Unlike root, it has limited permissions: you need to explicitly ask for admin powers (using 'sudo') to make system changes. This prevents accidental damage and follows security best practices. After Agent Flywheel installs, you'll reconnect as the ubuntu user for all your coding work.",
    analogy: "Like having a regular office key that opens your own office but not the server room. You can request access to the server room (using sudo), but you have to be deliberate about it.",
    why: "Using a regular user account is safer. If something goes wrong, the damage is limited to your user space, not the entire system.",
    related: ["root-user", "sudo"],
  },

  "public-key": {
    term: "Public Key",
    short: "The shareable half of your SSH key pair, like your email address",
    long: "Your public key is one half of an SSH key pair. It's designed to be shared freely: you give it to servers you want to access. When you add your public key to a VPS, you're telling that server: \"Allow logins from whoever can prove they have the matching private key.\" The server can use your public key to verify that proof, without ever needing your private key. Your public key typically starts with 'ssh-ed25519' or 'ssh-rsa'.",
    analogy: "Like your email address: you share it with everyone who needs to contact you. Anyone can send you encrypted messages using your public key, but only you (with your private key) can read them.",
    why: "Public keys enable passwordless, secure authentication. You share this with every VPS provider; they use it to verify you're really you.",
    related: ["private-key", "ssh", "ssh-key"],
  },

  "private-key": {
    term: "Private Key",
    short: "The secret half of your SSH key pair. NEVER share this.",
    long: "Your private key is the secret half of your SSH key pair. It lives on your computer (in ~/.ssh/) and should NEVER be shared, copied to servers, or shown to anyone. When you connect to a VPS, your computer uses the private key to prove your identity. If someone gets your private key, they can access all your servers. Keep it secret!",
    analogy: "Like the PIN to your bank card: anyone can know your card number (public key), but only you should know the PIN (private key). Together, they prove you're authorized.",
    why: "The private key is your proof of identity. Guard it carefully; it's the only thing standing between your servers and unauthorized access.",
    related: ["public-key", "ssh", "ssh-key"],
  },

  "ssh-key": {
    term: "SSH Key",
    short: "A cryptographic key pair used for secure, passwordless authentication",
    long: "An SSH key is a pair of cryptographic keys used for secure authentication: a public key (which you share) and a private key (which stays secret on your computer). Instead of typing passwords, SSH keys prove your identity mathematically. They're more secure than passwords and can't be guessed or brute-forced. When you 'add your SSH key' to a VPS, you're giving it your public key so it recognizes you.",
    analogy: "Like a special lock where you have the only key that fits. You give copies of the lock (public key) to servers, and they know anyone who can open it (with the private key) is really you.",
    why: "SSH keys are the standard for secure server access. They're faster than passwords (no typing), more secure (can't be guessed), and enable automation (scripts can authenticate without human input).",
    related: ["public-key", "private-key", "ssh"],
  },

  "ip-address": {
    term: "IP Address",
    short: "A unique number that identifies a computer on the internet (like 192.168.1.100)",
    long: "An IP address is a numerical label assigned to every device connected to the internet. It's like a phone number for computers: when you want to connect to your VPS, you use its IP address. IPv4 addresses look like '192.168.1.100' (four numbers 0-255, separated by dots). When you create a VPS, the provider gives you an IP address to use for SSH connections.",
    analogy: "Like a street address for your house. When you want to send mail (data), you need to know the exact address. Every house (computer) on the internet has a unique address.",
    why: "You need your VPS's IP address to connect to it. The wizard asks you to enter it so we can generate the correct SSH command for you.",
    related: ["vps", "ssh"],
  },

  hostname: {
    term: "Hostname",
    short: "The human-readable name of a computer on a network",
    long: "A hostname is a label assigned to a computer that identifies it on a network. While IP addresses are numbers (like 192.168.1.100), hostnames are words (like 'my-vps' or 'ubuntu-server'). When you see your terminal prompt showing 'ubuntu@vps-hostname', the part after @ is the hostname. You can set any hostname you like when creating a VPS; it's purely for your convenience and doesn't affect how the server works.",
    analogy: "If an IP address is like a phone number, a hostname is like a contact name. '555-0123' and 'Mom' refer to the same person; one is technical, one is human-friendly.",
    why: "Hostnames make it easier to identify which server you're connected to. When managing multiple VPS instances, meaningful hostnames like 'prod-server' or 'dev-agent-1' help you avoid mistakes.",
    related: ["ip-address", "vps", "ssh"],
  },

  port: {
    term: "Port",
    short: "A numbered endpoint for network connections (SSH uses port 22)",
    long: "A port is like a door number on a building. While an IP address identifies which computer to connect to, the port number identifies which service on that computer. Port 22 is for SSH, port 80 is for HTTP websites, port 443 is for HTTPS. When you SSH to a server, you're connecting to IP address + port 22. A single server can run many services, each listening on a different port.",
    analogy: "Imagine a large office building (the server) with many offices (ports). To reach the accounting department, you go to the building address (IP) and then office 22 (port). Different departments (services) have different office numbers.",
    why: "If SSH isn't working, one common issue is that port 22 is blocked by a firewall. Understanding ports helps you troubleshoot connection problems and understand how network services are organized.",
    related: ["ssh", "ip-address", "vps"],
  },

  fingerprint: {
    term: "Fingerprint",
    short: "A unique code that verifies a server's identity the first time you connect",
    long: "When you first SSH into a new server, you'll see a message asking you to verify the server's 'fingerprint' (also called host key). This is a unique cryptographic identifier for that server. By checking the fingerprint, you're confirming you're connecting to the real server and not an impostor. Your computer remembers fingerprints of servers you've connected to, so you only see this prompt once per server.",
    analogy: "Like checking someone's ID the first time you meet them. Once you've verified who they are (accepted the fingerprint), your computer remembers them. If someone tries to impersonate them later, the fingerprint won't match and you'll get a warning.",
    why: "Fingerprint verification prevents 'man-in-the-middle' attacks where someone intercepts your connection and pretends to be your server. The first time you connect, it's safe to accept if you just created the VPS. If you see a warning on a server you've connected to before, something may be wrong.",
    related: ["ssh", "ssh-key", "sha256"],
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
    analogy: "Cargo is to Rust what npm is to JavaScript: the central hub for getting packages and building projects.",
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
    short: "Open-source Firebase alternative with database, auth, and APIs instantly",
    long: "Supabase gives you a PostgreSQL database plus authentication, real-time subscriptions, storage, and auto-generated APIs in one platform. It's 'backend-as-a-service' that lets you build full applications without writing backend code. You get an admin dashboard, client libraries, and can self-host or use their cloud. Note: some Supabase projects expose the direct Postgres host over IPv6-only; if your VPS/network is IPv4-only, use the Supabase pooler connection string instead.",
    analogy: "Like getting a pre-built backend for your app instead of building it from scratch. Database, user login, file storage: it's all there, ready to use.",
    why: "Supabase CLI lets you manage your Supabase projects from the terminal. Combined with AI coding agents, you can rapidly build full-stack applications.",
    related: ["postgresql", "deployment"],
  },

  wrangler: {
    term: "Wrangler",
    short: "Cloudflare's CLI for deploying serverless functions worldwide",
    long: "Wrangler is Cloudflare's command-line tool for building and deploying Workers, which are serverless functions that run at the edge (close to users worldwide). Workers start in milliseconds and scale automatically. Wrangler handles local development, testing, and deployment. Cloudflare's free tier is generous enough for most projects.",
    analogy: "Like having tiny restaurants in every city serving your app's logic, instead of one central kitchen. Users get served by the nearest location, making everything faster.",
    why: "Edge functions are the future of fast, scalable web apps. Wrangler makes deploying them as easy as 'wrangler deploy'.",
    related: ["deployment", "cli"],
  },

  vault: {
    term: "Vault",
    short: "HashiCorp's secret management tool for storing passwords and API keys",
    long: "Vault is a tool for securely storing and accessing secrets like passwords, API keys, certificates, and other sensitive data. Instead of putting secrets in config files or environment variables (which can leak), you store them in Vault and fetch them when needed. Vault provides access control, audit logs, and automatic secret rotation.",
    analogy: "Like a bank vault for your passwords and API keys. Instead of keeping them in your pocket (config files), you store them securely and retrieve them only when needed, with full audit trail.",
    why: "As you build real applications, secret management becomes critical. Vault is the industry standard for secure secret storage.",
    related: ["configuration", "deployment"],
  },

  // ═══════════════════════════════════════════════════════════════
  // ADVANCED AGENTIC WORKFLOW CONCEPTS
  // ═══════════════════════════════════════════════════════════════

  "parallel-agents": {
    term: "Parallel Agents",
    short: "Multiple AI agents working simultaneously on different tasks",
    long: "Running agents in parallel means having multiple AI assistants work at the same time on different parts of a project. While one agent writes the API, another writes tests, and a third handles documentation. This dramatically speeds up development because tasks that would be sequential (one after another) happen simultaneously. The key challenge is coordination; agents need to know what others are working on to avoid conflicts.",
    analogy: "Like a kitchen with multiple chefs. One handles appetizers, one does mains, one makes desserts. They work faster together than one chef doing everything sequentially, but they need to communicate to avoid both reaching for the same pan.",
    why: "Parallel agents are the core of the Agent Flywheel. Tools like Agent Mail coordinate who's working on what, NTM manages multiple terminal sessions, and Beads tracks which tasks are ready. This lets you achieve in hours what would take days working sequentially.",
    related: ["ai-agents", "agent-mail", "ntm", "beads"],
  },

  "extended-thinking": {
    term: "Extended Thinking",
    short: "AI mode where the model 'thinks' longer for more complex reasoning",
    long: "Extended Thinking (also called 'Deep Think' or 'Chain of Thought') is a mode where AI models spend more time reasoning before responding. Instead of quickly generating an answer, the model works through the problem step by step, similar to how a human might sketch out their thought process. This produces better results for complex problems like architecture decisions, debugging tricky issues, or planning multi-step implementations. ChatGPT 5.2 Pro, Claude Opus 4.5, and Gemini 3 all offer extended thinking modes.",
    analogy: "Like the difference between answering '2+2' instantly versus working through a calculus problem on paper. Some questions benefit from the AI 'showing its work' internally before giving you the final answer.",
    why: "For planning complex features or debugging subtle bugs, extended thinking produces dramatically better results. The Agent Flywheel workflow uses ChatGPT 5.2 Pro's Extended Thinking, Claude Opus 4.5, or Gemini 3 Deep Think for high-level planning, then Claude Code or Codex CLI for execution. You pay more per query, but the quality difference is worth it for important decisions.",
    related: ["llm", "ai-agents", "prompt"],
  },

  "stream-deck": {
    term: "Stream Deck",
    short: "A physical button panel for triggering actions with one press",
    long: "A Stream Deck is a customizable keyboard with LCD buttons that can trigger any action: run a script, open a program, paste text, control smart home devices, or trigger AI agent prompts. Each button can display an icon and be programmed for any function. Content creators use them for streaming controls; developers use them for frequently-used commands. Pressing one button can execute a multi-step workflow that would otherwise require typing several commands.",
    analogy: "Like having a control panel with labeled buttons for your most common tasks. Instead of typing commands or navigating menus, you press the 'Deploy to Production' button and it just happens.",
    why: "In the Agent Flywheel workflow, Stream Deck buttons trigger pre-written prompts for AI agents. 'Plan feature X,' 'Review this PR,' 'Run the test suite'; all single button presses. This removes friction from the agentic workflow and lets you dispatch agents with a single tap.",
    related: ["cli", "prompt"],
  },

  "unix-philosophy": {
    term: "Unix Philosophy",
    short: "Design principle where each tool does one thing well and tools compose together",
    long: "The Unix Philosophy is a set of design principles from the 1970s that still guides modern software: (1) Make each program do one thing well, (2) Write programs to work together, (3) Write programs to handle text streams, because that's a universal interface. Instead of one giant program that does everything, you have small, focused tools that combine. 'ls | grep foo | wc -l' (list files, filter for 'foo', count lines) is Unix Philosophy in action.",
    analogy: "Like a well-designed kitchen where you have a great knife, a great pan, and a great cutting board, rather than one 'UltraCooker 3000' that tries to do everything but does nothing well. Simple, focused tools that combine elegantly.",
    why: "The Agent Flywheel tools follow Unix Philosophy. Each tool (NTM, Agent Mail, Beads) does one thing well. They communicate through standard formats (JSON, Git, text). This means tools can improve independently, and you can swap one out without breaking others.",
    related: ["cli", "json"],
  },

  json: {
    term: "JSON",
    short: "JavaScript Object Notation, a simple format for structured data",
    long: "JSON (JavaScript Object Notation) is a text format for representing structured data. It looks like: {\"name\": \"John\", \"age\": 30, \"languages\": [\"Python\", \"JavaScript\"]}. It's human-readable (you can open it in any text editor) and machine-parseable (programs can easily read and write it). JSON has become the standard way to exchange data between programs, APIs, and services. Nearly every programming language can read and write JSON.",
    analogy: "Like a standardized form that everyone agrees on. Instead of each program inventing its own way to describe data, JSON is the common language they all speak.",
    why: "Many Agent Flywheel tools communicate using JSON. Agent Mail sends JSON messages, APIs return JSON responses, configuration files use JSON. Understanding JSON helps you read logs, debug issues, and understand how tools communicate.",
    related: ["api", "configuration"],
  },

  mcp: {
    term: "MCP",
    short: "Model Context Protocol, a standard for connecting AI to external tools",
    long: "MCP (Model Context Protocol) is a standard that lets AI models connect to external tools and data sources. Instead of the AI only knowing what's in its training data, MCP lets it query databases, read files, call APIs, and use specialized tools in real-time. For example, an MCP server might expose your codebase, letting the AI search and understand your specific project. MCP is an open standard, so tools implementing it work with multiple AI providers.",
    analogy: "Like giving the AI a phone with different apps. Instead of just knowing what's in its head, it can 'call' different services: look up your database, check your file system, query your project management tool. MCP is the universal protocol those calls use.",
    why: "MCP servers extend AI capabilities. Agent Mail has an MCP server that lets AI agents send messages to each other. Other MCP servers provide web search, database access, or specialized tools. The Agent Flywheel uses MCP to connect tools into an integrated ecosystem.",
    related: ["ai-agents", "api", "json"],
  },

  autonomous: {
    term: "Autonomous",
    short: "Working independently without constant human supervision",
    long: "Autonomous operation means an AI agent can work on its own for extended periods, making decisions, handling errors, and completing tasks without needing human input at every step. This doesn't mean 'no supervision'; you set the goal, define boundaries, and review results. But between those checkpoints, the agent operates independently. An autonomous agent might work for hours, making dozens of commits, while you're away.",
    analogy: "Like giving instructions to a contractor rather than supervising every hammer swing. You define what you want built, check in periodically, and review the finished work, but you don't need to be present for every task.",
    why: "Autonomous operation is the goal of agentic AI. When agents can work unsupervised, you multiply your productivity; agents work while you sleep, think about other problems, or take breaks. The Agent Flywheel tools (Agent Mail, Beads, NTM) enable autonomous operation by providing coordination, task tracking, and session persistence.",
    related: ["agentic", "ai-agents", "parallel-agents"],
  },

  // ═══════════════════════════════════════════════════════════════
  // ADDITIONAL BEGINNER TERMS
  // ═══════════════════════════════════════════════════════════════

  session: {
    term: "Session",
    short: "A persistent terminal environment that keeps running even when you disconnect",
    long: "In the context of tmux and terminal work, a session is a saved terminal environment that persists on the server. When you start a tmux session, it creates a container for your terminal work. You can open multiple windows and panes within that session, run programs, and do your work. The key feature is persistence: if you disconnect (close your laptop, lose internet, or just log off), the session keeps running on the server. When you reconnect, you can 'attach' back to that same session and find everything exactly as you left it, with programs still running.",
    analogy: "It's like leaving your desk at work with papers spread out and programs open. When you come back the next day, everything is still there. A normal SSH connection is like a phone call; when you hang up, it's over. A tmux session is like your desk; it stays there waiting for you.",
    why: "Sessions are essential for AI coding assistants because they often run long tasks. Without sessions, if your internet blips or you close your laptop, all running work stops. With sessions, agents can work for hours or days, and you can check in whenever you want. The installer sets up ntm (nice tmux) to manage sessions easily.",
    related: ["tmux", "ntm", "ssh"],
  },

  "api-key": {
    term: "API Key",
    short: "A secret password that lets programs access a service on your behalf",
    long: "An API key is a unique string of characters (like 'sk-abc123xyz789...') that acts as a password for automated access to a service. When you sign up for a service like Anthropic (for Claude) or OpenAI (for ChatGPT), you can generate API keys in your account settings. You give this key to programs that need to use the service on your behalf. The program sends the key with each request to prove it's authorized. API keys should be kept secret; anyone with your key can use the service and potentially rack up charges on your account.",
    analogy: "It's like a valet key for your car. You give it to someone who needs to use your car (the program), and it lets them do specific things (access the AI service), but it's not your master key (your account password). If someone steals it, they can use your car, so you keep it private.",
    why: "AI coding assistants need API keys to access AI services like Claude or ChatGPT. The key proves you have an account and tracks usage for billing. You'll typically set API keys as environment variables so programs can find them without hardcoding secrets in code.",
    related: ["environment-variable", "claude-code", "api"],
  },

  sso: {
    term: "SSO",
    short: "Single Sign-On, logging into multiple services with one account (like Google)",
    long: "SSO (Single Sign-On) lets you use one login to access multiple different services. Instead of creating separate usernames and passwords for every website, you click 'Sign in with Google' (or GitHub, or Microsoft) and you're in. The service trusts your Google account to verify who you are. This is both convenient (one password to remember) and more secure (Google's security team is better at protecting accounts than most websites). Most developer services support Google SSO, which is why we recommend using it whenever available.",
    analogy: "Think of your Google account like a trusted ID card. Instead of each building (website) issuing you a new ID badge, they just check your universal ID at the door. One ID gets you into many buildings, and if you lose it, you only need to replace one card instead of dozens.",
    why: "We strongly recommend using Google SSO for all developer services that support it. It's more secure than creating unique passwords (which people often reuse or make weak), provides better account recovery options, and means fewer credentials to manage. When setting up accounts for Claude, GitHub, and other services, look for the 'Sign in with Google' button first.",
    related: ["api-key", "github"],
  },

  "environment-variable": {
    term: "Environment Variable",
    short: "A named setting stored in your system that programs can read",
    long: "Environment variables are named values stored in your system that programs can access. They're like settings that exist outside any specific program. For example, the PATH variable tells the system where to find executable programs. ANTHROPIC_API_KEY might store your Claude API key. Programs read these variables to find configuration without needing it hardcoded. You typically set them in shell config files (like .zshrc) so they're available every time you open a terminal.",
    analogy: "Think of environment variables like labels in a shared kitchen: 'COFFEE_MAKER_LOCATION = top shelf' or 'WIFI_PASSWORD = abc123'. Any program that needs to know can just check the label. You set it once, and every program can read it.",
    why: "Environment variables keep secrets out of code. Instead of putting your API key directly in a script (where anyone reading the script sees it), you put it in an environment variable. The script just reads the variable. If you share the script, your key stays private. The installer sets up common environment variables for the tools it installs.",
    related: ["api-key", "zsh", "bash"],
  },

  clone: {
    term: "Clone",
    short: "Download a complete copy of a Git repository including all its history",
    long: "Cloning is the Git operation that downloads a complete copy of a repository to your computer. When you 'git clone https://github.com/user/project', you download all the files, all the branches, and the entire history of changes. After cloning, you have a fully functional local copy that you can work with, make changes to, and later sync back. Unlike downloading a zip file of the code, cloning preserves the Git connection, so you can pull updates from the original and push your changes back.",
    analogy: "Like photocopying an entire filing cabinet including all the notes about who filed what and when. You get a complete working copy, not just the current contents.",
    why: "Cloning is how you start working on any Git-hosted project. The AI coding assistants often clone repositories to work on them. When the wizard mentions 'cloning a repo,' it means downloading a complete copy of a project to your VPS.",
    related: ["repository", "git", "github"],
  },

  // ═══════════════════════════════════════════════════════════════
  // DICKLESWORTHSTONE STACK TOOLS
  // ═══════════════════════════════════════════════════════════════

  dcg: {
    term: "DCG",
    short: "Destructive Command Guard, a Claude Code hook that blocks dangerous commands before execution",
    long: "DCG (Destructive Command Guard) is a safety tool that intercepts commands in Claude Code before they execute. It checks commands against 50+ protection packs covering git operations (like hard resets and force pushes), filesystem operations (like rm -rf), database commands (like DROP TABLE), Kubernetes operations, and cloud provider commands. When a dangerous command is detected, DCG blocks it immediately and suggests safer alternatives. It uses a fail-open design, meaning if DCG itself encounters an error or timeout, your workflow continues unblocked.",
    analogy: "Think of DCG like a safety guard at a factory machine. Before the machine (your AI agent) can operate, the guard checks if the action would be dangerous. If someone tries to stick their hand in the gears (run rm -rf /), the guard stops them and suggests using proper safety equipment (a safer command). But if the guard takes a break (DCG errors or times out), the machine keeps running rather than stopping everything.",
    why: "AI coding agents occasionally make mistakes or misunderstand instructions, leading to destructive commands that can destroy hours of uncommitted work in seconds. DCG provides a sub-50ms safety net that catches these mistakes before any damage occurs. It's especially important in 'vibe mode' where agents have more autonomy. DCG works alongside SLB (Simultaneous Launch Button) to provide layered safety: DCG blocks obvious destructive patterns instantly, while SLB handles contextual risks that need human judgment.",
    related: ["slb", "claude-code", "hook"],
  },

  "protection-pack": {
    term: "Protection Pack",
    short: "A collection of DCG rules targeting a specific category of dangerous commands",
    long: "Protection packs are modular sets of rules in DCG that each protect against a category of dangerous operations. The 'git' pack blocks hard resets and force pushes. The 'filesystem' pack blocks recursive force deletes. The 'database' pack catches DROP TABLE and TRUNCATE. Other packs cover Kubernetes, Terraform, Docker, AWS, and more. You can enable or disable packs based on what's relevant to your workflow. For example, if you never use Kubernetes, you can disable those packs to reduce false positives.",
    analogy: "Like different safety regulations for different industries. A construction site has rules about hard hats and fall protection. A chemical plant has rules about protective suits and ventilation. You apply the rules relevant to your work environment. DCG's protection packs work the same way: enable the packs for the technologies you use.",
    why: "Different projects use different technologies. A web project might need git and filesystem protection but not Kubernetes rules. A DevOps project might need everything. Protection packs let you customize DCG to your specific needs, reducing false positives while maintaining safety where it matters.",
    related: ["dcg", "hook"],
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
