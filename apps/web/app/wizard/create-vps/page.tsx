"use client";

import { useState, useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import { useForm } from "@tanstack/react-form";
import { Check, AlertCircle, Server, ChevronDown, HardDrive } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { cn } from "@/lib/utils";
import { markStepComplete } from "@/lib/wizardSteps";
import { useWizardAnalytics } from "@/lib/hooks/useWizardAnalytics";
import { useVPSIP, isValidIP } from "@/lib/userPreferences";
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
  { id: "ubuntu", label: "Selected Ubuntu 25.x (or newest Ubuntu available)" },
  { id: "ssh", label: "Pasted my SSH public key" },
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
      'Go to contabo.com/en/vps and find "Cloud VPS L" (32GB RAM)',
      'Click "Configure" and select your preferred region (US or EU)',
      'Under "Image", select Ubuntu 24.04 or 25.x',
      'In the order form, paste your SSH public key when prompted',
      "Complete checkout — servers activate within minutes",
      'Go to "Your services" > "VPS control" to find your IP address',
    ],
  },
  {
    name: "OVH",
    steps: [
      'Click "Order" on VPS Comfort (16GB) or VPS Elite (32GB)',
      'Under "Image", select Ubuntu 25.04 (or latest)',
      'Under "SSH Key", click "Add a key" and paste your public key',
      "Complete the order — activation is usually instant",
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
      router.push("/wizard/ssh-connect");
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
              Create your <Jargon term="vps">VPS</Jargon> instance
            </h1>
            <p className="text-sm text-muted-foreground">
              ~5 min
            </p>
          </div>
        </div>
        <p className="text-muted-foreground">
          Launch your <Jargon term="vps">VPS</Jargon> and attach your <Jargon term="ssh">SSH</Jargon> key. Follow the checklist below.
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
        <div className="rounded-xl border border-border/50 bg-card/50 p-4">
          <h2 className="mb-4 flex items-center gap-2 font-semibold text-foreground">
            <Server className="h-5 w-5 text-primary" />
            Setup checklist
          </h2>
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
            <GuideExplain term="IP Address">
              An IP address is like a phone number for computers. It&apos;s a series
              of numbers (like 192.168.1.100) that identifies your VPS on the internet.
              <br /><br />
              You&apos;ll need this address to connect to your VPS from your computer.
              It&apos;s like knowing someone&apos;s phone number so you can call them.
            </GuideExplain>

            <GuideSection title="Detailed Steps for Creating Your VPS">
              <div className="space-y-4">
                <GuideStep number={1} title="Log into your VPS provider">
                  Go to the website where you created your account (Hetzner, OVH, or Contabo)
                  and sign in with the email and password you created earlier.
                </GuideStep>

                <GuideStep number={2} title="Find the 'Create Server' or 'Add VPS' button">
                  Look for a button that says something like:
                  <ul className="mt-2 list-disc space-y-1 pl-5">
                    <li><strong>Hetzner:</strong> Click &quot;Add Server&quot; (big blue button)</li>
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
                  <strong>Look for:</strong> Ubuntu 25.04 or Ubuntu 24.04 LTS
                  <br />
                  <em className="text-xs">
                    LTS stands for &quot;Long Term Support&quot; — it means the version
                    is stable and well-supported.
                  </em>
                </GuideStep>

                <GuideStep number={5} title="Add your SSH key">
                  This is VERY important! Look for a section called &quot;SSH Keys&quot; or
                  &quot;Authentication&quot;.
                  <ul className="mt-2 list-disc space-y-1 pl-5">
                    <li>Click &quot;Add SSH Key&quot; or &quot;Add Key&quot;</li>
                    <li>Give it a name like &quot;My Laptop&quot; or &quot;Agent Flywheel Key&quot;</li>
                    <li><strong>Paste your public key</strong> (the text you copied earlier that starts with ssh-ed25519)</li>
                    <li>Click Save or Add</li>
                  </ul>
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
                  <strong>Copy this number</strong> — you&apos;ll paste it in the box below!
                </GuideStep>
              </div>
            </GuideSection>

            <GuideTip>
              The IP address should be 4 groups of numbers separated by periods,
              like <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">192.168.1.100</code>.
              Don&apos;t include any letters or extra characters!
            </GuideTip>

            <GuideCaution>
              <strong>Make sure you added your SSH key!</strong> If you skip this step,
              you won&apos;t be able to connect to your VPS. Go back and add it before
              continuing.
            </GuideCaution>
          </div>
        </SimplerGuide>

        {/* IP Address input */}
        <div className="space-y-3">
          <h2 className="font-semibold text-foreground">Your VPS IP address</h2>
          <p className="text-sm text-muted-foreground">
            Enter the IP address of your new VPS. You&apos;ll find this in your
            provider&apos;s control panel after the VPS is created.
          </p>
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
