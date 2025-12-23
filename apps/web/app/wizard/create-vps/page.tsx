"use client";

import { useState, useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import { useForm } from "@tanstack/react-form";
import { Check, AlertCircle, Server, ChevronDown, HardDrive, ShieldCheck, ExternalLink } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { cn } from "@/lib/utils";
import { markStepComplete } from "@/lib/wizardSteps";
import { useWizardAnalytics } from "@/lib/hooks/useWizardAnalytics";
import { useVPSIP, isValidIP } from "@/lib/userPreferences";
import { withCurrentSearch } from "@/lib/utils";
import {
  SimplerGuide,
  GuideSection,
  GuideStep,
  GuideExplain,
  GuideTip,
  GuideCaution,
} from "@/components/simpler-guide";
import { Jargon } from "@/components/jargon";

const CHECKLIST_ITEMS = [
  { id: "ubuntu", label: "Selected Ubuntu 24.04+ (25.10 preferred)" },
  { id: "region", label: "Picked a region close to me" },
  { id: "password", label: "Set a root password (or received one via email)" },
  { id: "created", label: "Created the VPS and waited for it to start" },
  { id: "copied-ip", label: "Copied the IP address" },
] as const;

type ChecklistItemId = typeof CHECKLIST_ITEMS[number]["id"];

interface ProviderGuideProps {
  name: string;
  steps: string[];
  isExpanded: boolean;
  onToggle: () => void;
}

function ProviderGuide({
  name,
  steps,
  isExpanded,
  onToggle,
}: ProviderGuideProps) {
  return (
    <div className={cn(
      "rounded-xl border transition-all duration-200",
      isExpanded
        ? "border-primary/30 bg-card/80"
        : "border-border/50 bg-card/50"
    )}>
      <button
        type="button"
        onClick={onToggle}
        aria-expanded={isExpanded}
        className="flex w-full items-center justify-between p-3 text-left"
      >
        <span className="font-medium text-foreground">{name} specific steps</span>
        <ChevronDown
          className={cn(
            "h-4 w-4 text-muted-foreground transition-transform duration-200",
            isExpanded && "rotate-180"
          )}
        />
      </button>
      {isExpanded && (
        <div className="border-t border-border/50 px-3 pb-3 pt-2">
          <ol className="list-decimal space-y-1 pl-5 text-sm text-muted-foreground">
            {steps.map((step, i) => (
              <li key={i}>{step}</li>
            ))}
          </ol>
        </div>
      )}
    </div>
  );
}

const PROVIDER_GUIDES = [
  {
    name: "Contabo",
    steps: [
      "Go to contabo.com/en/vps and pick a plan with at least 16GB RAM (32GB ideal)",
      'Click "Configure" and select your preferred region (US or EU)',
      'Under "Image", select Ubuntu 25.10 (or newest available)',
      'Set a root password when prompted (save it - you\'ll need it once)',
      "Complete checkout (servers activate within minutes)",
      'Go to "Your services" > "VPS control" to find your IP address',
    ],
  },
  {
    name: "OVH",
    steps: [
      'Click "Order" on VPS Comfort (16GB) or VPS Elite (32GB)',
      'Under "Image", select Ubuntu 25.10 (or latest)',
      "Pick the data center/region closest to you",
      'Choose "Password" authentication (skip SSH key section)',
      "Set a strong root password and save it",
      "Complete the order (activation is usually instant)",
      "Copy the IP address from your control panel",
    ],
  },
];

export default function CreateVPSPage() {
  const router = useRouter();
  const [storedIP, setStoredIP] = useVPSIP();
  const [expandedProvider, setExpandedProvider] = useState<string | null>(null);
  const [isNavigating, setIsNavigating] = useState(false);

  // Track checklist state locally for simpler form handling
  const [checkedItems, setCheckedItems] = useState<Set<ChecklistItemId>>(new Set());

  // Analytics tracking for this wizard step
  const { markComplete } = useWizardAnalytics({
    step: "create_vps",
    stepNumber: 5,
    stepTitle: "Create VPS Instance",
  });

  // Store markComplete in a ref for use in form's onSubmit
  const markCompleteRef = useRef(markComplete);
  useEffect(() => {
    markCompleteRef.current = markComplete;
  }, [markComplete]);

  const form = useForm({
    defaultValues: {
      ipAddress: storedIP ?? "",
    },
    onSubmit: async ({ value }) => {
      markCompleteRef.current({ ip_entered: true });
      setStoredIP(value.ipAddress);
      markStepComplete(5);
      setIsNavigating(true);
      router.push(withCurrentSearch("/wizard/ssh-connect"));
    },
  });

  // Track if we've synced the stored IP to avoid overwriting user edits
  const hasSyncedStoredIP = useRef(false);

  // Sync stored IP to form after hydration (storedIP is null during SSR)
  useEffect(() => {
    if (storedIP && !hasSyncedStoredIP.current && !form.state.values.ipAddress) {
      form.setFieldValue("ipAddress", storedIP);
      hasSyncedStoredIP.current = true;
    }
  }, [storedIP, form]);

  const handleCheckItem = (itemId: ChecklistItemId, checked: boolean) => {
    setCheckedItems((prev) => {
      const next = new Set(prev);
      if (checked) {
        next.add(itemId);
      } else {
        next.delete(itemId);
      }
      return next;
    });
  };

  const allChecked = CHECKLIST_ITEMS.every((item) => checkedItems.has(item.id));

  return (
    <div className="space-y-8">
      {/* Header */}
      <div className="space-y-2">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary/20">
            <HardDrive className="h-5 w-5 text-primary" />
          </div>
          <div>
            <h1 className="bg-gradient-to-r from-foreground via-foreground to-muted-foreground bg-clip-text text-2xl font-bold tracking-tight text-transparent sm:text-3xl">
              Create your <Jargon term="vps" gradientHeading>VPS</Jargon> instance
            </h1>
            <p className="text-sm text-muted-foreground">
              ~5 min
            </p>
          </div>
        </div>
        <p className="text-muted-foreground">
          You have an account with your VPS provider. Now let&apos;s create the actual server
          (the VPS instance) that will run your development environment.
        </p>
      </div>

      <form
        onSubmit={(e) => {
          e.preventDefault();
          e.stopPropagation();
          form.handleSubmit();
        }}
        className="space-y-8"
      >
        {/* Universal checklist */}
        <div className={cn(
          "rounded-xl border p-4 transition-colors",
          allChecked
            ? "border-[oklch(0.72_0.19_145/0.5)] bg-[oklch(0.72_0.19_145/0.05)]"
            : "border-border/50 bg-card/50"
        )}>
          <div className="mb-4 flex items-start justify-between gap-4">
            <div>
              <h2 className="flex items-center gap-2 font-semibold text-foreground">
                <Server className="h-5 w-5 text-primary" />
                Setup checklist
              </h2>
              <p className="mt-1 text-sm text-muted-foreground">
                Check each item as you complete it to unlock the next step
              </p>
            </div>
            <div className={cn(
              "shrink-0 rounded-full px-3 py-1 text-xs font-medium",
              allChecked
                ? "bg-[oklch(0.72_0.19_145/0.15)] text-[oklch(0.72_0.19_145)]"
                : "bg-muted text-muted-foreground"
            )}>
              {checkedItems.size} of {CHECKLIST_ITEMS.length}
            </div>
          </div>
          <div className="space-y-3">
            {CHECKLIST_ITEMS.map((item) => (
              <label
                key={item.id}
                className="flex cursor-pointer items-center gap-3"
              >
                <Checkbox
                  checked={checkedItems.has(item.id)}
                  onCheckedChange={(checked) =>
                    handleCheckItem(item.id, checked === true)
                  }
                />
                <span
                  className={cn(
                    "text-sm transition-all",
                    checkedItems.has(item.id)
                      ? "text-muted-foreground line-through"
                      : "text-foreground"
                  )}
                >
                  {item.label}
                </span>
              </label>
            ))}
          </div>
        </div>

        {/* Provider-specific guides */}
        <div className="space-y-3">
          <h2 className="font-semibold">Need help with your provider?</h2>
          {PROVIDER_GUIDES.map((provider) => (
            <ProviderGuide
              key={provider.name}
              name={provider.name}
              steps={provider.steps}
              isExpanded={expandedProvider === provider.name}
              onToggle={() =>
                setExpandedProvider((prev) =>
                  prev === provider.name ? null : provider.name
                )
              }
            />
          ))}
        </div>

        {/* Beginner Guide */}
        <SimplerGuide>
          <div className="space-y-6">
            <GuideExplain term="an IP Address">
              An IP address is like a phone number for computers. It&apos;s a series
              of numbers (like 192.168.1.100) that identifies your VPS on the internet.
              <br /><br />
              You&apos;ll need this address to connect to your VPS from your computer.
              It&apos;s like knowing someone&apos;s phone number so you can call them.
            </GuideExplain>

            <GuideTip>
              <strong>Why password first?</strong> Adding SSH keys in the provider website is
              confusing and easy to mess up. Instead, we connect once with a password, then
              the installer sets up your SSH key the right way.
            </GuideTip>

            <GuideSection title="Detailed Steps for Creating Your VPS">
              <div className="space-y-4">
                <GuideStep number={1} title="Log into your VPS provider">
                  Go to the website where you created your account (OVH or Contabo)
                  and sign in with the email and password you created earlier.
                </GuideStep>

                <GuideStep number={2} title="Find the 'Create Server' or 'Add VPS' button">
                  Look for a button that says something like:
                  <ul className="mt-2 list-disc space-y-1 pl-5">
                    <li><strong>OVH:</strong> Click &quot;Create an instance&quot; or &quot;Order&quot;</li>
                    <li><strong>Contabo:</strong> Go to &quot;Your services&quot; → click the VPS you ordered</li>
                  </ul>
                </GuideStep>

                <GuideStep number={3} title="Choose your server location">
                  Pick a data center close to you for faster speeds:
                  <ul className="mt-2 list-disc space-y-1 pl-5">
                    <li>USA: Choose US-West or US-East</li>
                    <li>Europe: Choose Germany (FSN) or Finland (HEL)</li>
                    <li>If unsure, any location works fine!</li>
                  </ul>
                </GuideStep>

                <GuideStep number={4} title="Select Ubuntu as the operating system">
                  You&apos;ll see a list of &quot;images&quot; or &quot;operating systems&quot;.
                  <br /><br />
                  <strong>Look for:</strong> Ubuntu 25.10 (or newest available)
                  <br />
                  <em className="text-xs">
                    If only Ubuntu 24.04 LTS is offered, that&apos;s fine. The installer
                    automatically upgrades to 25.10 before ACFS installs.
                  </em>
                </GuideStep>

                <GuideStep number={5} title="Set a root password">
                  Look for a section called &quot;Authentication&quot; or &quot;Password&quot;.
                  <ul className="mt-2 list-disc space-y-1 pl-5">
                    <li>If asked about SSH keys, <strong>skip that section</strong></li>
                    <li>Choose &quot;Password&quot; authentication</li>
                    <li>Set a strong root password</li>
                    <li><strong>Save this password!</strong> You&apos;ll need it once to connect</li>
                  </ul>
                  <p className="mt-2 text-xs italic">
                    Some providers email you a password instead - that&apos;s fine too!
                  </p>
                </GuideStep>

                <GuideStep number={6} title="Choose your plan size">
                  Look for a plan with:
                  <ul className="mt-2 list-disc space-y-1 pl-5">
                    <li>4-8 vCPU (virtual CPUs)</li>
                    <li>8-16 GB RAM (memory)</li>
                    <li>100GB+ storage</li>
                    <li>Cost should be around $30-60/month</li>
                  </ul>
                </GuideStep>

                <GuideStep number={7} title="Create and wait">
                  Click the &quot;Create&quot;, &quot;Deploy&quot;, or &quot;Order&quot; button.
                  <br /><br />
                  Your VPS will take 1-5 minutes to start up. You&apos;ll see a status like
                  &quot;Running&quot; or a green indicator when it&apos;s ready.
                </GuideStep>

                <GuideStep number={8} title="Find and copy the IP address">
                  Once your VPS is running, look for the IP address. It&apos;s usually shown:
                  <ul className="mt-2 list-disc space-y-1 pl-5">
                    <li>On the main server overview page</li>
                    <li>In a &quot;Network&quot; or &quot;IP Addresses&quot; section</li>
                    <li>It looks like: <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">123.45.67.89</code></li>
                  </ul>
                  <br />
                  <strong>Copy this number</strong> and paste it in the box below!
                </GuideStep>
              </div>
            </GuideSection>

            <GuideTip>
              The IP address should be 4 groups of numbers separated by periods,
              like <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">192.168.1.100</code>.
              Don&apos;t include any letters or extra characters!
            </GuideTip>

            <GuideCaution>
              <strong>Save your password!</strong> You&apos;ll need it once to connect
              for the first time. After that, the installer will set up SSH key access
              so you won&apos;t need the password anymore.
            </GuideCaution>
          </div>
        </SimplerGuide>

        {/* IP Address input */}
        <div className="space-y-4">
          <div className="space-y-2">
            <h2 className="font-semibold text-foreground">Your VPS IP address</h2>
            <p className="text-sm text-muted-foreground">
              Enter the IP address of your new VPS. You&apos;ll find this in your
              provider&apos;s control panel after the VPS is created.
            </p>
          </div>

          {/* Privacy assurance card */}
          <div className="flex gap-3 rounded-xl border border-[oklch(0.72_0.19_145/0.25)] bg-[oklch(0.72_0.19_145/0.05)] p-3 sm:p-4">
            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-[oklch(0.72_0.19_145/0.15)] sm:h-9 sm:w-9">
              <ShieldCheck className="h-4 w-4 text-[oklch(0.72_0.19_145)] sm:h-5 sm:w-5" />
            </div>
            <div className="min-w-0 space-y-1">
              <p className="text-[13px] font-medium leading-tight text-[oklch(0.82_0.12_145)] sm:text-sm">
                Your data stays on your device
              </p>
              <p className="text-[12px] leading-relaxed text-muted-foreground sm:text-[13px]">
                This IP address is stored <strong className="text-foreground/80">only in your browser&apos;s local storage</strong>. It&apos;s
                never sent to our servers or any third party. The{" "}
                <a
                  href="https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-0.5 font-medium text-[oklch(0.75_0.18_195)] hover:underline"
                >
                  entire codebase is open source
                  <ExternalLink className="h-3 w-3" />
                </a>{" "}
                so you can verify this yourself.
              </p>
            </div>
          </div>

          <form.Field
            name="ipAddress"
            validators={{
              onChange: ({ value }) => {
                if (!value) return undefined;
                if (!isValidIP(value)) {
                  return "Please enter a valid IP address (e.g., 192.168.1.1)";
                }
                return undefined;
              },
              onBlur: ({ value }) => {
                // Duplicate validation on blur for Firefox/Safari compatibility
                if (!value) return undefined;
                if (!isValidIP(value)) {
                  return "Please enter a valid IP address (e.g., 192.168.1.1)";
                }
                return undefined;
              },
              onSubmit: ({ value }) => {
                if (!value) {
                  return "Please enter your VPS IP address";
                }
                if (!isValidIP(value)) {
                  return "Please enter a valid IP address";
                }
                return undefined;
              },
            }}
          >
            {(field) => {
              const hasErrors = field.state.meta.errors.length > 0;
              const isValid = field.state.value && !hasErrors && isValidIP(field.state.value);
              const canSubmit = allChecked && isValid && !isNavigating;

              return (
                <div className="space-y-2">
                  <input
                    data-vps-ip-input
                    type="text"
                    value={field.state.value}
                    onChange={(e) => field.handleChange(e.target.value)}
                    onBlur={field.handleBlur}
                    placeholder="e.g., 192.168.1.100"
                    className={cn(
                      "w-full rounded-xl border bg-background px-4 py-3 font-mono text-sm outline-none transition-all",
                      "focus:border-primary focus:ring-2 focus:ring-primary/20",
                      hasErrors
                        ? "border-destructive focus:border-destructive focus:ring-destructive/20"
                        : "border-border/50"
                    )}
                  />
                  {hasErrors && (
                    <p className="flex items-center gap-1 text-sm text-destructive">
                      <AlertCircle className="h-4 w-4" />
                      {field.state.meta.errors[0]}
                    </p>
                  )}
                  {isValid && (
                    <p className="flex items-center gap-1 text-sm text-[oklch(0.72_0.19_145)]">
                      <Check className="h-4 w-4" />
                      Valid IP address
                    </p>
                  )}

                  {/* Hint when IP is valid but checklist isn't complete */}
                  {isValid && !allChecked && (
                    <p className="flex items-center gap-1 text-sm text-muted-foreground">
                      <AlertCircle className="h-4 w-4" />
                      Complete the checklist above to continue
                    </p>
                  )}

                  {/* Continue button - rendered inside field for access to validation state */}
                  <div className="flex justify-end pt-6">
                    <Button
                      type="submit"
                      disabled={!canSubmit}
                      size="lg"
                    >
                      {isNavigating ? "Loading..." : "Continue to SSH"}
                    </Button>
                  </div>
                </div>
              );
            }}
          </form.Field>
        </div>
      </form>
    </div>
  );
}
