"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { ExternalLink, Terminal, Check } from "lucide-react";
import { Button } from "@/components/ui/button";
import { CommandCard } from "@/components/command-card";
import { AlertCard } from "@/components/alert-card";
import { cn } from "@/lib/utils";
import { markStepComplete } from "@/lib/wizardSteps";
import { useWizardAnalytics } from "@/lib/hooks/useWizardAnalytics";
import { useUserOS } from "@/lib/userPreferences";
import {
  SimplerGuide,
  GuideSection,
  GuideStep,
  GuideExplain,
  GuideTip,
  GuideCaution,
  DirectDownloadButton,
} from "@/components/simpler-guide";
import { Jargon } from "@/components/jargon";

interface TerminalCardProps {
  name: string;
  description: string;
  href: string;
}

function TerminalCard({ name, description, href }: TerminalCardProps) {
  return (
    <a
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      className={cn(
        "group relative flex items-center justify-between rounded-xl border p-4 transition-all duration-200",
        "border-border/50 bg-card/50 hover:border-primary/30 hover:bg-card/80 hover:shadow-md"
      )}
    >
      <div>
        <h3 className="font-semibold text-foreground group-hover:text-primary transition-colors">{name}</h3>
        <p className="text-sm text-muted-foreground">{description}</p>
      </div>
      <ExternalLink className="h-4 w-4 text-muted-foreground group-hover:text-primary transition-colors" />
    </a>
  );
}

// Direct download URLs for Mac terminals
const GHOSTTY_MAC_DMG = "https://release.files.ghostty.org/1.1.3/Ghostty.dmg";
const WEZTERM_MAC_DMG = "https://github.com/wez/wezterm/releases/download/20240203-110809-5046fc22/WezTerm-macos-20240203-110809-5046fc22.dmg";

function MacContent() {
  return (
    <div className="space-y-6">
      <div className="space-y-4">
        <p className="text-muted-foreground">
          Install <strong className="text-foreground">Ghostty</strong> or <strong className="text-foreground">WezTerm</strong> — either
          is a great choice. Open it once after installing to make sure it works.
        </p>

        <div className="grid gap-3 sm:grid-cols-2">
          <TerminalCard
            name="Ghostty"
            description="Fast, native terminal"
            href="https://ghostty.org/download"
          />
          <TerminalCard
            name="WezTerm"
            description="GPU-accelerated terminal"
            href="https://wezfurlong.org/wezterm/installation.html"
          />
        </div>
      </div>

      <AlertCard variant="success" icon={Check} title="SSH is already installed">
        macOS includes <Jargon term="ssh">SSH</Jargon> by default, so you&apos;re ready to connect to
        your <Jargon term="vps">VPS</Jargon>.
      </AlertCard>

      {/* Beginner Guide for Mac */}
      <SimplerGuide>
        <div className="space-y-6">
          <GuideExplain term="Terminal">
            A terminal is a program that lets you type commands to control your computer.
            Instead of clicking buttons and icons, you type text commands. It&apos;s like
            having a conversation with your computer!
            <br /><br />
            Think of it like texting your computer instead of tapping on apps.
            You type a command, press Enter, and the computer does what you asked.
            <br /><br />
            We&apos;ll be using the terminal to connect to your remote server (<Jargon term="vps">VPS</Jargon>)
            and run programs on it.
          </GuideExplain>

          <GuideSection title="Quick Download — Click to Start">
            <p className="mb-4">
              Click one of these buttons to immediately download the installer.
              We recommend <strong>Ghostty</strong> — it&apos;s fast and simple.
            </p>
            <div className="flex flex-col gap-3 sm:flex-row">
              <DirectDownloadButton
                href={GHOSTTY_MAC_DMG}
                filename="Ghostty.dmg"
                label="Download Ghostty"
                sublabel="Recommended • Fast & Simple"
              />
              <DirectDownloadButton
                href={WEZTERM_MAC_DMG}
                filename="WezTerm.dmg"
                label="Download WezTerm"
                sublabel="Alternative • More Features"
              />
            </div>
          </GuideSection>

          <GuideSection title="Step-by-Step Installation">
            <div className="space-y-4">
              <GuideStep number={1} title="Find the downloaded file">
                Look at the bottom of your web browser. You should see
                &quot;Ghostty.dmg&quot; or &quot;WezTerm.dmg&quot;.
                Click on it to open it.
                <br /><br />
                <em className="text-xs">
                  If you don&apos;t see it, open Finder, then click &quot;Downloads&quot;
                  in the left sidebar. Double-click the .dmg file.
                </em>
              </GuideStep>

              <GuideStep number={2} title="Install the app">
                A new window will open showing the app icon and an &quot;Applications&quot;
                folder. <strong>Drag the app icon onto the Applications folder.</strong>
                <br /><br />
                This copies the app to your computer. Wait for the copy to finish
                (you&apos;ll see a progress bar).
              </GuideStep>

              <GuideStep number={3} title="Open the app">
                <ul className="list-disc space-y-2 pl-5">
                  <li>Press <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">⌘</kbd> + <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Space</kbd> to open Spotlight (the search)</li>
                  <li>Type &quot;Ghostty&quot; or &quot;WezTerm&quot;</li>
                  <li>Press <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Enter</kbd> to open it</li>
                </ul>
              </GuideStep>

              <GuideStep number={4} title="Allow the app to run (if asked)">
                Mac might say the app is from an &quot;unidentified developer&quot;.
                This is normal for apps downloaded outside the App Store.
                <br /><br />
                If this happens:
                <ul className="mt-2 list-disc space-y-1 pl-5">
                  <li>Click &quot;Cancel&quot; on the popup</li>
                  <li>Open <strong>System Settings</strong> (click the Apple menu → System Settings)</li>
                  <li>Click &quot;Privacy &amp; Security&quot;</li>
                  <li>Scroll down and click &quot;Open Anyway&quot; next to the app name</li>
                </ul>
              </GuideStep>
            </div>
          </GuideSection>

          <GuideTip>
            You&apos;ll know it worked when you see a window with a blinking cursor
            and some text (usually your username and a $ symbol). That&apos;s your terminal!
            You can close it for now — we&apos;ll use it in the next steps.
          </GuideTip>

          <GuideCaution>
            If you see an error or the app won&apos;t open, try the other terminal
            option (if you downloaded Ghostty, try WezTerm instead). Both work great!
          </GuideCaution>
        </div>
      </SimplerGuide>
    </div>
  );
}

function WindowsContent() {
  return (
    <div className="space-y-6">
      <div className="space-y-4">
        <p className="text-muted-foreground">
          Install <strong className="text-foreground">Windows Terminal</strong> from the Microsoft Store.
          Open it once after installing.
        </p>

        <TerminalCard
          name="Windows Terminal"
          description="Microsoft Store (free)"
          href="ms-windows-store://pdp/?ProductId=9N0DX20HK701"
        />
      </div>

      <div className="space-y-3">
        <h3 className="font-medium">Verify SSH is available</h3>
        <p className="text-sm text-muted-foreground">
          Open Windows Terminal and run this command. You should see a version
          number.
        </p>
        <CommandCard
          command="ssh -V"
          description="Check SSH version"
          showCheckbox
          persistKey="verify-ssh-windows"
        />
      </div>

      {/* Beginner Guide for Windows */}
      <SimplerGuide>
        <div className="space-y-6">
          <GuideExplain term="Terminal">
            A terminal is a program that lets you type commands to control your computer.
            Instead of clicking buttons and icons, you type text commands. It&apos;s like
            having a conversation with your computer!
            <br /><br />
            Think of it like texting your computer instead of tapping on apps.
            You type a command, press Enter, and the computer does what you asked.
            <br /><br />
            Windows Terminal is Microsoft&apos;s modern terminal app. It&apos;s free and
            works great for what we need.
          </GuideExplain>

          <GuideSection title="Step-by-Step Installation">
            <div className="space-y-4">
              <GuideStep number={1} title="Open the Microsoft Store">
                <ul className="list-disc space-y-2 pl-5">
                  <li>Click the <strong>Start button</strong> (Windows icon in the bottom-left corner, or press the Windows key on your keyboard)</li>
                  <li>Type <strong>&quot;Microsoft Store&quot;</strong></li>
                  <li>Click on the Microsoft Store app to open it</li>
                </ul>
              </GuideStep>

              <GuideStep number={2} title="Search for Windows Terminal">
                <ul className="list-disc space-y-2 pl-5">
                  <li>In the Microsoft Store, click the <strong>Search box</strong> at the top</li>
                  <li>Type <strong>&quot;Windows Terminal&quot;</strong></li>
                  <li>Press <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Enter</kbd></li>
                  <li>Click on <strong>&quot;Windows Terminal&quot;</strong> by Microsoft Corporation</li>
                </ul>
              </GuideStep>

              <GuideStep number={3} title="Install the app">
                <ul className="list-disc space-y-2 pl-5">
                  <li>Click the <strong>blue &quot;Get&quot; or &quot;Install&quot; button</strong></li>
                  <li>Wait for it to download and install (this takes 1-2 minutes)</li>
                  <li>When done, the button will change to &quot;Open&quot;</li>
                </ul>
              </GuideStep>

              <GuideStep number={4} title="Open Windows Terminal">
                <ul className="list-disc space-y-2 pl-5">
                  <li>Click the <strong>&quot;Open&quot; button</strong> in the Microsoft Store, OR</li>
                  <li>Click Start, type &quot;Terminal&quot;, and click on Windows Terminal</li>
                </ul>
              </GuideStep>
            </div>
          </GuideSection>

          <GuideSection title="Check that SSH works">
            <p className="mb-3">
              Windows 10 and 11 come with SSH already installed. Let&apos;s verify it works:
            </p>
            <div className="space-y-4">
              <GuideStep number={1} title="Type the command">
                In the Windows Terminal window, type exactly:
                <code className="mt-2 block rounded bg-muted px-3 py-2 font-mono text-sm">
                  ssh -V
                </code>
                <em className="mt-1 block text-xs">
                  That&apos;s &quot;ssh&quot; (lowercase), a space, a dash, and a capital &quot;V&quot;
                </em>
              </GuideStep>

              <GuideStep number={2} title="Press Enter">
                Press the <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Enter</kbd> key
                on your keyboard.
              </GuideStep>

              <GuideStep number={3} title="Check the result">
                You should see something like:
                <code className="mt-2 block rounded bg-muted px-3 py-2 font-mono text-sm">
                  OpenSSH_for_Windows_8.6p1, LibreSSL 3.4.3
                </code>
                The exact numbers don&apos;t matter — as long as you see &quot;OpenSSH&quot;,
                you&apos;re good!
              </GuideStep>
            </div>
          </GuideSection>

          <GuideTip>
            If SSH isn&apos;t installed, you may need to enable it. Go to Settings → Apps →
            Optional Features → Add a feature → search for &quot;OpenSSH Client&quot; and install it.
            Then try the ssh -V command again.
          </GuideTip>

          <GuideCaution>
            Make sure you&apos;re typing commands in the Windows Terminal window, not in
            the search bar or a web browser. The terminal has a black background with
            white or colored text.
          </GuideCaution>
        </div>
      </SimplerGuide>
    </div>
  );
}

export default function InstallTerminalPage() {
  const router = useRouter();
  const [os, , osLoaded] = useUserOS();
  const [isNavigating, setIsNavigating] = useState(false);
  const ready = osLoaded;

  // Analytics tracking for this wizard step
  const { markComplete } = useWizardAnalytics({
    step: "install_terminal",
    stepNumber: 2,
    stepTitle: "Install Terminal",
  });

  // Redirect if no OS selected (after hydration)
  useEffect(() => {
    if (!ready) return;
    if (os === null) {
      router.push("/wizard/os-selection");
    }
  }, [ready, os, router]);

  const handleContinue = useCallback(() => {
    markComplete({ selected_os: os });
    markStepComplete(2);
    setIsNavigating(true);
    router.push("/wizard/generate-ssh-key");
  }, [router, os, markComplete]);

  // Show loading state while detecting OS or during SSR
  if (!ready || !os) {
    return (
      <div className="flex items-center justify-center py-12">
        <Terminal className="h-8 w-8 animate-pulse text-muted-foreground" />
      </div>
    );
  }

  return (
    <div className="space-y-8">
      {/* Header */}
      <div className="space-y-2">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary/20">
            <Terminal className="h-5 w-5 text-primary" />
          </div>
          <div>
            <h1 className="bg-gradient-to-r from-foreground via-foreground to-muted-foreground bg-clip-text text-2xl font-bold tracking-tight text-transparent sm:text-3xl">
              Install a terminal you&apos;ll love
            </h1>
            <p className="text-sm text-muted-foreground">
              ~2 min
            </p>
          </div>
        </div>
        <p className="text-muted-foreground">
          A good terminal makes everything easier.
        </p>
      </div>

      {/* OS-specific content */}
      {os === "mac" ? <MacContent /> : <WindowsContent />}

      {/* Continue button */}
      <div className="flex justify-end pt-4">
        <Button onClick={handleContinue} disabled={isNavigating} size="lg">
          {isNavigating ? "Loading..." : "I installed it, continue"}
        </Button>
      </div>
    </div>
  );
}
