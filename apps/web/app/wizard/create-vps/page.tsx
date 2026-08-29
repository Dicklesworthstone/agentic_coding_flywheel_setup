"use client";

import { useCallback, useState, useEffect, useMemo, useRef } from "react";
import { useRouter } from "next/navigation";
import Image from "next/image";
import { useForm, useStore } from "@tanstack/react-form";
import { Check, AlertCircle, Server, ChevronDown, HardDrive, ShieldCheck, ExternalLink } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { cn } from "@/lib/utils";
import { markStepComplete, useWizardForwardNav } from "@/lib/wizardSteps";
import { useWizardAnalytics } from "@/lib/hooks/useWizardAnalytics";
import {
  CREATE_VPS_REQUIRED_CHECKLIST_ITEMS,
  isCreateVPSChecklistComplete,
  isValidIP,
  type CreateVPSChecklistItemId,
  useCreateVPSChecklist,
  useVPSIP,
} from "@/lib/userPreferences";
import { withCurrentSearch } from "@/lib/utils";
import {
  ACFS_RECOMMENDED_MIN_RAM_GB,
  VPS_PROVIDERS,
  VPS_TOP_PICK,
  describePlan,
} from "@/lib/vpsProviders";
import {
  SimplerGuide,
  GuideSection,
  GuideStep,
  GuideExplain,
  GuideTip,
  GuideCaution,
} from "@/components/simpler-guide";
import { Jargon } from "@/components/jargon";

type ScreenshotSpec = {
  file: string;
  alt: string;
  caption: string;
};

// Screenshots ship with the site (research_screenshots/ is gitignored, so
// raw.githubusercontent.com URLs 404 — issue #363).
const SCREENSHOT_BASE = "/screenshots";

function screenshotUrl(file: string): string {
  return `${SCREENSHOT_BASE}/${file}`;
}

function ScreenshotFigure({ file, alt, caption }: ScreenshotSpec) {
  const src = screenshotUrl(file);
  return (
    <figure className="space-y-1">
      <a
        href={src}
        target="_blank"
        rel="noopener noreferrer"
        className="block overflow-hidden rounded-xl border border-border/50 bg-muted/10 transition hover:border-primary/30"
      >
        <Image
          src={src}
          alt={alt}
          width={1440}
          height={1000}
          unoptimized
          loading="lazy"
          sizes="(min-width: 640px) 50vw, 100vw"
          className="h-auto w-full"
        />
      </a>
      <figcaption className="text-xs text-muted-foreground">
        {caption}{" "}
        <span className="sr-only">(opens full size in a new tab)</span>
      </figcaption>
    </figure>
  );
}

const CHECKLIST_ITEMS = [
  { id: "ubuntu", label: "Selected Ubuntu (22.04 or newer; 25.10 preferred)" },
  { id: "region", label: "Picked a region close to me" },
  { id: "password", label: "Set a root password (or received one via email)" },
  { id: "created", label: "Created the VPS and waited for it to start" },
] as const satisfies readonly { id: CreateVPSChecklistItemId; label: string }[];

type ChecklistItemId = CreateVPSChecklistItemId;
const CHECKLIST_ITEM_IDS = new Set<ChecklistItemId>(CREATE_VPS_REQUIRED_CHECKLIST_ITEMS);

interface ProviderGuideProps {
  name: string;
  steps: string[];
  screenshots?: ScreenshotSpec[];
  isExpanded: boolean;
  onToggle: () => void;
}

function ProviderGuide({
  name,
  steps,
  screenshots,
  isExpanded,
  onToggle,
}: ProviderGuideProps) {
  return (
    <div className={cn(
      "rounded-xl border transition duration-200",
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
          {screenshots && screenshots.length > 0 && (
            <div className="mt-3 grid gap-3 sm:grid-cols-2">
              {screenshots.map((shot) => (
                <ScreenshotFigure
                  key={shot.file}
                  file={shot.file}
                  alt={shot.alt}
                  caption={shot.caption}
                />
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

// Plan names, specs, and prices come from VPS_PROVIDERS so these steps cannot
// drift from the data table.
const CONTABO = VPS_PROVIDERS.find((provider) => provider.id === "contabo") ?? VPS_TOP_PICK;
const OVH = VPS_PROVIDERS.find((provider) => provider.id === "ovh") ?? VPS_TOP_PICK;

const PROVIDER_GUIDES = [
  {
    name: "Contabo",
    steps: [
      `Go to contabo.com/en-us/vps and select ${describePlan(CONTABO.recommended)} or ${describePlan(CONTABO.budget)} (USD approximate; Contabo lists EUR)`,
      'Click "Configure" and select your preferred region (US recommended for best latency)',
      'Under "Image", select Ubuntu 25.10 (or newest available; 24.04 LTS is fine too)',
      'Leave add-ons at their free/default values unless you specifically want them: no private networking, no object storage, unmanaged server, monitoring none',
      'In "Login & password for your server", keep Username as root, enter a strong root password, and save it - you\'ll need it once',
      "Complete checkout (servers activate within minutes, occasionally up to 1 hour)",
      'Go to "Your services" > "VPS control" to find your IP address',
    ],
    screenshots: [
      {
        file: "contabo_us_03_order_page.png",
        alt: "Contabo order/configure page with region and Ubuntu image selections",
        caption: "Contabo order page — select region + Ubuntu image here.",
      },
    ],
  },
  {
    name: "OVH",
    steps: [
      `Click "Order" on ${describePlan(OVH.recommended)} - the largest VPS OVH sells, below the ${ACFS_RECOMMENDED_MIN_RAM_GB}GB ACFS target; use Contabo if you want 48-64GB`,
      'Under "Image", select Ubuntu 25.10 (or latest available)',
      "Pick the data center/region closest to you (US-East, US-West, or EU)",
      'Choose "Password" authentication (skip SSH key section for now)',
      "Set a strong root password and save it somewhere safe",
      "Complete the order (activation is usually instant)",
      "Copy the IP address from your control panel",
    ],
    screenshots: [
      {
        file: "ovh_us_03_order.png",
        alt: "OVH order/configuration flow showing OS and region selections",
        caption: "OVH order flow — select Ubuntu + region during configuration.",
      },
    ],
  },
];

export default function CreateVPSPage() {
  const router = useRouter();
  const [storedIP, setStoredIP] = useVPSIP();
  const [storedChecklist, setStoredChecklist] = useCreateVPSChecklist();
  const [expandedProvider, setExpandedProvider] = useState<string | null>(null);
  const [isNavigating, setIsNavigating] = useState(false);
  const checkedItems = useMemo(() => {
    const next = new Set<ChecklistItemId>();
    for (const item of storedChecklist) {
      if (CHECKLIST_ITEM_IDS.has(item as ChecklistItemId)) {
        next.add(item as ChecklistItemId);
      }
    }
    return next;
  }, [storedChecklist]);
  const allChecked = isCreateVPSChecklistComplete(storedChecklist);

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
      const normalizedIP = value.ipAddress.trim();
      if (!allChecked || !isValidIP(normalizedIP)) {
        return;
      }

      markCompleteRef.current({ ip_entered: true });
      setStoredIP(normalizedIP);
      markStepComplete(5);
      setIsNavigating(true);
      router.push(withCurrentSearch("/wizard/ssh-connect"));
    },
  });

  // The mobile dock's "Next" submits this form, with the same gate as the
  // inline "Continue to SSH" button (checklist complete + valid IP).
  const ipAddress = useStore(form.store, (state) => state.values.ipAddress);
  const submitForm = useCallback(() => {
    void form.handleSubmit();
  }, [form]);
  const forwardCtaRef = useWizardForwardNav({
    onContinue: submitForm,
    disabled: !allChecked || !isValidIP(ipAddress.trim()) || isNavigating,
    loading: isNavigating,
    label: "Continue to SSH",
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
    const next = new Set(checkedItems);
    if (checked) {
      next.add(itemId);
    } else {
      next.delete(itemId);
    }
    setStoredChecklist(
      CHECKLIST_ITEMS.filter((item) => next.has(item.id)).map((item) => item.id)
    );
  };

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
        <div
          className={cn(
            "rounded-xl border p-4 transition-colors",
            allChecked
              ? "border-green/50 bg-green/5"
              : "border-border/50 bg-card/50"
          )}
          data-create-vps-checklist
          // Focus target for the step-validation hook (focusSelector); a plain
          // <div> is not focusable without tabIndex.
          tabIndex={-1}
        >
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
                ? "bg-green/15 text-green"
                : "bg-muted text-muted-foreground"
            )}>
              {checkedItems.size} of {CHECKLIST_ITEMS.length}
            </div>
          </div>
          <div className="space-y-3">
            {CHECKLIST_ITEMS.map((item) => (
              <label
                key={item.id}
                // 44px minimum touch target around the 16px checkbox.
                className="flex min-h-[44px] cursor-pointer items-center gap-3 py-2"
              >
                <Checkbox
                  checked={checkedItems.has(item.id)}
                  onCheckedChange={(checked) =>
                    handleCheckItem(item.id, checked === true)
                  }
                />
                <span
                  className={cn(
                    "text-sm transition",
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

          {/* Prompt to enter IP when checklist is complete */}
          {allChecked && (
            <div className="mt-4 flex items-center gap-2 rounded-lg bg-primary/10 px-3 py-2 text-sm font-medium text-primary">
              <Check className="h-4 w-4" />
              <span>Great! Now enter your VPS IP address below to continue</span>
            </div>
          )}
        </div>

        {/* IP Address input - placed prominently after checklist */}
        <div className="space-y-4">
          <div className="space-y-2">
            <h2 id="vps-ip-heading" className="font-semibold text-foreground">Your VPS IP address</h2>
            <p className="text-sm text-muted-foreground">
              Enter the IP address of your new VPS. You&apos;ll find this in your
              provider&apos;s control panel after the VPS is created.
            </p>
          </div>

          {/* Privacy assurance card */}
          <div className="flex gap-3 rounded-xl border border-green/25 bg-green/5 p-3 sm:p-4">
            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-green/15 sm:h-9 sm:w-9">
              <ShieldCheck className="h-4 w-4 text-green sm:h-5 sm:w-5" />
            </div>
            <div className="min-w-0 space-y-1">
              <p className="text-[13px] font-medium leading-tight text-green sm:text-sm">
                Your data stays on your device
              </p>
              <p className="text-[12px] leading-relaxed text-muted-foreground sm:text-[13px]">
                This IP address is stored <strong className="text-foreground/80">in your browser&apos;s local storage</strong>.
                If browser storage is blocked, the wizard keeps it in memory for this tab only — you&apos;ll be asked again after a reload. The{" "}
                <a
                  href="https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-0.5 font-medium text-primary hover:underline"
                >
                  entire codebase is open source
                  <ExternalLink className="h-3 w-3" aria-hidden="true" />
                  <span className="sr-only"> (opens in new tab)</span>
                </a>{" "}
                so you can verify this yourself.
              </p>
            </div>
          </div>

          <form.Field
            name="ipAddress"
            validators={{
              // Errors surface on blur/submit only (not on every keystroke);
              // the live "Valid IP address" hint is derived from the value.
              onBlur: ({ value }) => {
                if (!value) return undefined;
                if (!isValidIP(value)) {
                  return "Please enter a valid IP address (e.g., 203.0.113.42)";
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
              const isValid = isValidIP(field.state.value);
              // Errors come from the blur/submit validators. Once the value is
              // valid again the stale message is hidden immediately (without
              // waiting for the next blur) so the field never shows "invalid"
              // and "Valid IP address" at the same time.
              const showError = field.state.meta.errors.length > 0 && !isValid;
              const canSubmit = allChecked && isValid && !isNavigating;

              return (
                <div className="space-y-2">
                  <label htmlFor="vps-ip-input" className="block text-sm font-medium text-foreground">
                    IP address
                  </label>
                  <input
                    id="vps-ip-input"
                    data-vps-ip-input
                    type="text"
                    // "text" (not "decimal"): the validator accepts IPv6, which
                    // needs ":" and hex letters the decimal keypad lacks.
                    inputMode="text"
                    autoComplete="off"
                    autoCapitalize="none"
                    spellCheck={false}
                    aria-invalid={showError || undefined}
                    aria-describedby={showError ? "vps-ip-error" : undefined}
                    value={field.state.value}
                    onChange={(e) => field.handleChange(e.target.value)}
                    onBlur={field.handleBlur}
                    placeholder="e.g., 203.0.113.42"
                    className={cn(
                      "w-full rounded-xl border bg-background px-4 py-3 font-mono text-sm outline-none transition",
                      "focus:border-primary focus:ring-2 focus:ring-primary/20",
                      showError
                        ? "border-destructive focus:border-destructive focus:ring-destructive/20"
                        : "border-border/50"
                    )}
                  />
                  {showError && (
                    <p
                      id="vps-ip-error"
                      role="alert"
                      className="flex items-center gap-1 text-sm text-destructive"
                    >
                      <AlertCircle className="h-4 w-4" aria-hidden="true" />
                      {field.state.meta.errors[0]}
                    </p>
                  )}
                  {isValid && (
                    <p className="flex items-center gap-1 text-sm text-green">
                      <Check className="h-4 w-4" aria-hidden="true" />
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

                  {/* Hint when checklist is complete but IP is missing */}
                  {allChecked && !field.state.value && (
                    <p className="flex items-center gap-1 text-sm text-muted-foreground">
                      <AlertCircle className="h-4 w-4" />
                      Enter your VPS IP address above to continue
                    </p>
                  )}

                  {/* Continue button - rendered inside field for access to validation state */}
                  <div className="flex justify-end pt-6">
                    <Button
                      ref={forwardCtaRef}
                      data-wizard-primary-cta
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

        {/* Region selection tip - prominent placement */}
        <div className="rounded-xl border border-primary/30 bg-primary/5 p-4">
          <h3 className="font-medium text-foreground mb-2">💡 Why region matters</h3>
          <p className="text-sm text-muted-foreground">
            Closer servers = faster response times. When you type, commands reach your VPS faster.
            When AI generates code, it appears on your screen faster.
          </p>
          <div className="mt-3 grid gap-2 sm:grid-cols-2 text-sm">
            <div className="rounded-lg bg-background/50 px-3 py-2">
              <span className="font-medium text-foreground">🇺🇸 USA:</span>{" "}
              <span className="text-muted-foreground">Pick US-West (California) or US-East (Virginia)</span>
            </div>
            <div className="rounded-lg bg-background/50 px-3 py-2">
              <span className="font-medium text-foreground">🇪🇺 Europe:</span>{" "}
              <span className="text-muted-foreground">Pick Germany, France, or Finland</span>
            </div>
            <div className="rounded-lg bg-background/50 px-3 py-2">
              <span className="font-medium text-foreground">🌏 Asia-Pacific:</span>{" "}
              <span className="text-muted-foreground">Pick Singapore, Sydney, or Tokyo</span>
            </div>
            <div className="rounded-lg bg-background/50 px-3 py-2">
              <span className="font-medium text-foreground">🤷 Unsure?</span>{" "}
              <span className="text-muted-foreground">Any region works fine—pick one!</span>
            </div>
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
              screenshots={provider.screenshots}
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
              of numbers (like 203.0.113.42) that identifies your VPS on the internet.
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
                  Pick a data center close to you for faster speeds. The closer the server,
                  the faster your typing appears and AI responses stream back. This matters
                  because you&apos;ll be interacting with your VPS constantly.
                  <ul className="mt-2 list-disc space-y-1 pl-5">
                    <li><strong>USA West Coast:</strong> Pick US-West, Los Angeles, or Seattle</li>
                    <li><strong>USA East Coast:</strong> Pick US-East, Virginia, or New York</li>
                    <li><strong>Europe:</strong> Pick Germany (Nuremberg/Frankfurt), France, or Finland</li>
                    <li><strong>Asia-Pacific:</strong> Pick Singapore, Sydney, or Tokyo</li>
                    <li><strong>If unsure:</strong> Just pick one! Any region works, and the difference is small.</li>
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
                    <li>If the provider asks for a username, keep it as <strong>root</strong></li>
                    <li>Set a strong root password</li>
                    <li><strong>Save this password!</strong> You&apos;ll need it once to connect</li>
                  </ul>
                  <p className="mt-2 text-xs italic">
                    Some providers email you a password instead - that&apos;s fine too!
                  </p>
                </GuideStep>

                <GuideTip>
                  <strong>Contabo add-ons:</strong> In the &quot;Additional Features&quot; section, the default/free options are fine:
                  no private networking, unlimited traffic, one IPv4 address, no object storage, unmanaged server, and monitoring none.
                </GuideTip>

                <GuideStep number={6} title="Choose your plan size">
                  Look for a plan with:
                  <ul className="mt-2 list-disc space-y-1 pl-5">
                    <li>12-16 vCPU (virtual CPUs)</li>
                    <li>48-64 GB RAM (each AI agent uses ~2GB, you want to run 10+)</li>
                    <li>250GB+ NVMe storage</li>
                    <li>Cost: ~${VPS_TOP_PICK.recommended.priceUSD}/month for 64GB (worth it!)</li>
                  </ul>
                  <p className="mt-2 text-xs text-muted-foreground">
                    64GB is strongly recommended. You&apos;re investing $400+/month in AI subscriptions,
                    so don&apos;t bottleneck that with insufficient RAM.
                  </p>
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
                    <li>It looks like: <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">203.0.113.42</code></li>
                  </ul>
                  <br />
                  <strong>Copy this number</strong> and paste it in the &quot;Your VPS IP address&quot; box above!
                </GuideStep>
              </div>
            </GuideSection>

            <GuideTip>
              Your address will be either IPv4 like{" "}
              <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">203.0.113.42</code>{" "}
              (four numbers separated by periods) or IPv6 like{" "}
              <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">2001:db8::7</code>{" "}
              (groups separated by colons). Copy it exactly as your provider shows it, with no
              spaces or extra characters.
            </GuideTip>

            <GuideCaution>
              <strong>Save your password!</strong> You&apos;ll need it once to connect
              for the first time. After that, the installer will set up SSH key access
              so you won&apos;t need the password anymore.
            </GuideCaution>
          </div>
        </SimplerGuide>
      </form>
    </div>
  );
}
