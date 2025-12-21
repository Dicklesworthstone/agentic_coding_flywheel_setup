"use client";

import { useCallback, useState } from "react";
import { useRouter } from "next/navigation";
import { Apple, Monitor, Sparkles, Laptop, ChevronRight } from "lucide-react";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { markStepComplete } from "@/lib/wizardSteps";
import { useWizardAnalytics } from "@/lib/hooks/useWizardAnalytics";
import {
  SimplerGuide,
  GuideSection,
  GuideExplain,
  GuideTip,
} from "@/components/simpler-guide";
import {
  useUserOS,
  useDetectedOS,
  type OperatingSystem,
} from "@/lib/userPreferences";
import { withCurrentSearch } from "@/lib/utils";

interface OSCardProps {
  icon: React.ReactNode;
  title: string;
  description: string;
  selected: boolean;
  detected?: boolean;
  onClick: () => void;
}

function OSCard({ icon, title, description, selected, detected, onClick }: OSCardProps) {
  return (
    <button
      type="button"
      className={cn(
        "group relative flex w-full flex-col items-center gap-4 rounded-2xl border p-8 text-center transition-all duration-300",
        selected
          ? "border-primary bg-primary/10 shadow-lg shadow-primary/10"
          : "border-border/50 bg-card/50 hover:border-primary/30 hover:bg-card/80 hover:shadow-md"
      )}
      onClick={onClick}
      role="radio"
      tabIndex={0}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          onClick();
        }
      }}
      aria-checked={selected}
    >
      {/* Detected badge */}
      {detected && (
        <div className={cn(
          "absolute -top-2 left-1/2 -translate-x-1/2 rounded-full px-3 py-0.5 text-xs font-medium transition-all",
          selected
            ? "bg-primary text-primary-foreground"
            : "bg-primary/20 text-primary"
        )}>
          {selected ? "Selected" : "Detected"}
        </div>
      )}

      {/* Selected glow */}
      {selected && (
        <>
          <div className="absolute inset-0 rounded-2xl bg-gradient-to-b from-primary/20 to-transparent opacity-50" />
          <div className="absolute -inset-px rounded-2xl bg-gradient-to-b from-primary/50 to-primary/0 opacity-0 transition-opacity group-hover:opacity-100" />
        </>
      )}

      {/* Icon */}
      <div
        className={cn(
          "relative flex h-20 w-20 items-center justify-center rounded-2xl transition-all duration-300",
          selected
            ? "bg-primary text-primary-foreground shadow-lg shadow-primary/30"
            : "bg-muted text-muted-foreground group-hover:bg-muted/80 group-hover:text-foreground"
        )}
      >
        {icon}
        {selected && (
          <Sparkles className="absolute -right-1 -top-1 h-5 w-5 text-[oklch(0.78_0.16_75)] animate-pulse" />
        )}
      </div>

      {/* Text */}
      <div className="relative">
        <h3 className="text-xl font-bold tracking-tight transition-colors text-foreground">
          {title}
        </h3>
        <p className="mt-1 text-sm text-muted-foreground">
          {description}
        </p>
      </div>

      {/* Selection indicator */}
      {selected && (
        <div className="absolute bottom-4 right-4 flex h-6 w-6 items-center justify-center rounded-full bg-primary text-primary-foreground animate-scale-in">
          <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={3}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
          </svg>
        </div>
      )}
    </button>
  );
}

export default function OSSelectionPage() {
  const router = useRouter();
  const [storedOS, setStoredOS] = useUserOS();
  const detectedOS = useDetectedOS();
  const [isNavigating, setIsNavigating] = useState(false);

  // Analytics tracking for this wizard step
  const { markComplete } = useWizardAnalytics({
    step: "os_selection",
    stepNumber: 1,
    stepTitle: "OS Selection",
  });

  // Use stored OS if available, otherwise use detected OS
  const selectedOS = storedOS ?? detectedOS;
  const hasDetection = detectedOS !== null;

  // Select OS without navigating
  const handleSelectOS = useCallback(
    (os: OperatingSystem) => {
      setStoredOS(os);
    },
    [setStoredOS]
  );

  // Navigate only when Continue is clicked
  const handleContinue = useCallback(() => {
    if (selectedOS) {
      // Confirm the selection explicitly so subsequent steps can rely on it.
      setStoredOS(selectedOS);
      markComplete({ selected_os: selectedOS });
      markStepComplete(1);
      setIsNavigating(true);
      router.push(withCurrentSearch("/wizard/install-terminal"));
    }
  }, [selectedOS, router, markComplete, setStoredOS]);

  return (
    <div className="space-y-8">
      {/* Header */}
      <div className="space-y-2">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary/20">
            <Laptop className="h-5 w-5 text-primary" />
          </div>
          <div>
            <h1 className="bg-gradient-to-r from-foreground via-foreground to-muted-foreground bg-clip-text text-2xl font-bold tracking-tight text-transparent sm:text-3xl">
              What computer are you using?
            </h1>
            <p className="text-sm text-muted-foreground">
              ~30 sec
            </p>
          </div>
        </div>
        <p className="text-muted-foreground">
          This helps us show you the right commands and instructions.
        </p>
      </div>

      {/* OS Options */}
      <div data-os-selection className="grid gap-6 sm:grid-cols-2" role="radiogroup" aria-label="Select your operating system">
        <OSCard
          icon={<Apple className="h-10 w-10" />}
          title="Mac"
          description="macOS, MacBook, iMac, Mac Mini, Mac Studio"
          selected={selectedOS === "mac"}
          detected={detectedOS === "mac"}
          onClick={() => handleSelectOS("mac")}
        />
        <OSCard
          icon={<Monitor className="h-10 w-10" />}
          title="Windows"
          description="Windows 10, Windows 11"
          selected={selectedOS === "windows"}
          detected={detectedOS === "windows"}
          onClick={() => handleSelectOS("windows")}
        />
      </div>

      {/* Tip */}
      <div className="rounded-xl border border-border/30 bg-muted/30 p-4">
        <p className="text-sm text-muted-foreground">
          <span className="font-medium text-foreground">Tip:</span>{" "}
          {hasDetection ? (
            <>We guessed your OS from your browser. If that&apos;s wrong, pick the other option. Otherwise just hit Continue.</>
          ) : (
            <>If you&apos;re on a phone/tablet, pick the computer you&apos;ll use for the next steps (Mac or Windows).</>
          )}
        </p>
      </div>

      {/* Simpler Guide for beginners */}
      <SimplerGuide>
        <div className="space-y-6">
          <GuideSection title="What is this asking?">
            <p>
              We need to know what type of computer you&apos;re using so we can show you
              the right instructions. Different computers need slightly different steps.
            </p>
          </GuideSection>

          <GuideExplain term="Operating System">
            An operating system (or &quot;OS&quot;) is the main software that runs your
            computer. It&apos;s like the foundation that everything else runs on top of.
            <br /><br />
            <strong>Mac</strong> = Apple computers (MacBook, iMac, Mac Mini, Mac Studio).
            If you see an Apple logo  when your computer starts, you have a Mac.
            <br /><br />
            <strong>Windows</strong> = Most non-Apple computers (Dell, HP, Lenovo, etc.).
            If you see a Windows logo (four colored squares) when your computer starts,
            you have Windows.
          </GuideExplain>

          <GuideSection title="How do I know which one I have?">
            <ul className="list-disc space-y-2 pl-5">
              <li>
                <strong>Mac:</strong> Look at the top-left corner of your screen. Do you
                see an Apple icon ()? Click it and select &quot;About This Mac&quot; and
                it will say something like &quot;macOS Sonoma&quot; or &quot;macOS Ventura&quot;.
              </li>
              <li>
                <strong>Windows:</strong> Look at the bottom-left corner of your screen.
                Do you see a Windows icon (four blue squares)? That means you have Windows.
                You can also press the Windows key on your keyboard (between Ctrl and Alt).
              </li>
            </ul>
          </GuideSection>

          <GuideTip>
            {hasDetection ? (
              <>
                We tried to detect your computer type automatically. If it looks right, you can just click
                &quot;Continue&quot;. If it looks wrong, click the other option first.
              </>
            ) : (
              <>
                If you&apos;re reading this on your phone, choose the computer you&apos;ll use next (Mac or Windows),
                then click &quot;Continue&quot;.
              </>
            )}
          </GuideTip>
        </div>
      </SimplerGuide>

      {/* Continue button */}
      <div className="flex justify-end pt-4">
        <Button
          onClick={handleContinue}
          disabled={!selectedOS || isNavigating}
          size="lg"
          className="group"
          disableMotion
        >
          {isNavigating ? (
            <>
              <div className="mr-2 h-4 w-4 animate-spin rounded-full border-2 border-primary-foreground border-t-transparent" />
              Loading...
            </>
          ) : (
            <>
              Continue
              <ChevronRight className="ml-1 h-4 w-4 transition-transform group-hover:translate-x-0.5" />
            </>
          )}
        </Button>
      </div>
    </div>
  );
}
