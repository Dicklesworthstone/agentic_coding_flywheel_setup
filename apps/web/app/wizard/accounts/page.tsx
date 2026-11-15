"use client";

import {
  BookOpen,
  Bot,
  Check,
  ChevronDown,
  Cloud,
  DollarSign,
  ExternalLink,
  Shield,
  Sparkles,
  Terminal,
  Users,
} from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useMemo, useState } from "react";
import { AgentRoster } from "@/components/agent-roster";
import { AlertCard } from "@/components/alert-card";
import { Jargon } from "@/components/jargon";
import {
  GuideExplain,
  GuideSection,
  GuideStep,
  GuideTip,
  SimplerGuide,
} from "@/components/simpler-guide";
import { TrackedLink } from "@/components/tracked-link";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { manifestSelectionProfiles } from "@/lib/generated/manifest-modules";
import { manifestAgents } from "@/lib/generated/manifest-web-index";
import { useWizardAnalytics } from "@/lib/hooks/useWizardAnalytics";
import { resolveModuleSelection } from "@/lib/moduleSelection";
import {
  getSelectedAuthServices,
  type Service,
  type ServiceTier,
} from "@/lib/services";
import { useCheckedServices, useModuleProfile, useModuleSelection } from "@/lib/userPreferences";
import { withCurrentSearch } from "@/lib/utils";
import { useWizardInstallation } from "@/lib/wizardInstallation";
import { markStepComplete, useWizardForwardNav } from "@/lib/wizardSteps";

const TIER_META: Record<
  ServiceTier,
  {
    title: string;
    description: string;
    icon: React.ReactNode;
    accentClass: string;
    defaultOpen: boolean;
  }
> = {
  essential: {
    title: "Essential (Start here)",
    description: "Core services for the tools in your selected setup.",
    icon: <Shield className="h-5 w-5" />,
    accentClass: "bg-green/20 text-green",
    defaultOpen: true,
  },
  recommended: {
    title: "Recommended (After your first project)",
    description: "Add more AI agents when you want extra coverage.",
    icon: <Bot className="h-5 w-5" />,
    accentClass: "bg-primary/20 text-primary",
    defaultOpen: false,
  },
  optional: {
    title: "Optional (When you need them)",
    description: "Deployment, databases, and infrastructure extras.",
    icon: <Cloud className="h-5 w-5" />,
    accentClass: "bg-muted text-muted-foreground",
    defaultOpen: false,
  },
};

function sortByOrder(a: Service, b: Service) {
  return a.sortOrder - b.sortOrder;
}

interface ServiceCardProps {
  service: Service;
  isChecked: boolean;
  onToggle: () => void;
}

function getSignupCheckboxLabel(service: Service): string {
  return service.tier === "essential" ? "Signed up" : "Optional signup";
}

function ServiceCard({ service, isChecked, onToggle }: ServiceCardProps) {
  const checkboxId = `service-${service.id}`;
  const checkboxLabel = getSignupCheckboxLabel(service);

  return (
    <div
      className={`group rounded-xl border p-4 transition ${
        isChecked
          ? "border-green/50 bg-green/5"
          : "border-border/50 bg-card/50 hover:border-primary/30"
      }`}
    >
      {/* Checkbox + service name share one label, so the whole header row
          (min 44px tall) toggles the box instead of a detached 16px target. */}
      <label htmlFor={checkboxId} className="flex min-h-11 cursor-pointer items-center gap-3 py-1">
        <Checkbox id={checkboxId} checked={isChecked} onCheckedChange={onToggle} />
        <span className="flex min-w-0 flex-1 flex-wrap items-center gap-x-2 gap-y-1">
          <span className="font-semibold text-foreground">{service.name}</span>
          <span className="text-xs text-muted-foreground">by {service.provider}</span>
          {service.requiresSubscription && (
            <span
              className="inline-flex items-center gap-1 rounded-full bg-amber/10 px-2 py-0.5 text-xs font-medium text-amber"
              title={service.subscriptionNote ?? "Paid plan required"}
            >
              <DollarSign className="h-3 w-3" />
              {service.subscriptionNote ?? "Paid plan required"}
            </span>
          )}
        </span>
        <span className="shrink-0 text-xs text-muted-foreground">{checkboxLabel}</span>
        {isChecked && <Check className="h-5 w-5 shrink-0 text-green" />}
      </label>
      <div className="min-w-0 space-y-2 pl-7">
        <p className="text-sm text-muted-foreground">{service.shortDescription}</p>
        {service.requiresSubscription && (
          <p className="text-xs text-amber">
            Paid plan needed to actually use this service on your VPS.
          </p>
        )}
        <p className="text-xs text-muted-foreground/80">{service.whyNeeded}</p>
        <div className="flex flex-wrap gap-2 pt-1">
          {service.supportsGoogleSso && (
            <TrackedLink
              href={service.googleSsoUrl || service.signupUrl}
              trackingId={`service-google-sso-${service.id}`}
              className="inline-flex items-center gap-1.5 rounded-lg border border-green/30 bg-green/10 px-2.5 py-2.5 text-xs font-medium text-green transition-colors hover:bg-green/20"
            >
              <Sparkles className="h-3 w-3" />
              Sign up with Google
              <ExternalLink className="h-2.5 w-2.5" />
            </TrackedLink>
          )}
          <TrackedLink
            href={service.signupUrl}
            trackingId={`service-signup-${service.id}`}
            className="inline-flex items-center gap-1 rounded-lg border border-border/50 bg-card/50 px-2.5 py-2.5 text-xs font-medium text-muted-foreground transition-colors hover:border-primary/30 hover:text-foreground"
          >
            {service.supportsGoogleSso ? "Other signup options" : "Sign up"}
            <ExternalLink className="h-2.5 w-2.5" />
          </TrackedLink>
          <TrackedLink
            href={service.docsUrl}
            trackingId={`service-docs-${service.id}`}
            className="inline-flex items-center gap-1 px-1.5 py-2.5 text-xs text-muted-foreground hover:text-foreground"
          >
            Docs
            <ExternalLink className="h-2.5 w-2.5" />
          </TrackedLink>
        </div>
        {/* Post-install command preview */}
        {service.postInstallCommand && (
          <div className="flex items-center gap-2 pt-2 text-xs text-muted-foreground">
            <Terminal className="h-3 w-3 shrink-0" />
            <span>
              After install:{" "}
              <code className="rounded bg-muted/50 px-1.5 py-0.5 font-mono text-xs text-muted-foreground">
                {service.postInstallCommand}
              </code>
            </span>
          </div>
        )}
      </div>
    </div>
  );
}

interface TierSectionProps {
  tier: ServiceTier;
  services: Service[];
  checkedServices: Set<string>;
  onToggleService: (serviceId: string) => void;
}

function TierSection({ tier, services, checkedServices, onToggleService }: TierSectionProps) {
  const [isOpen, setIsOpen] = useState(TIER_META[tier].defaultOpen);
  const checkedCount = services.filter((service) => checkedServices.has(service.id)).length;
  const meta = TIER_META[tier];

  if (services.length === 0) return null;

  return (
    <div className="overflow-hidden rounded-2xl border border-border/50 bg-card/50">
      <button
        type="button"
        onClick={() => setIsOpen((prev) => !prev)}
        className="flex w-full items-center justify-between gap-4 p-5 text-left transition-colors hover:bg-muted/30"
        aria-expanded={isOpen}
      >
        <div className="flex items-center gap-3">
          <div
            className={`flex h-10 w-10 items-center justify-center rounded-xl ${meta.accentClass}`}
          >
            {meta.icon}
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h2 className="text-lg font-semibold">{meta.title}</h2>
              <span className="text-xs text-muted-foreground">
                {checkedCount}/{services.length}
              </span>
            </div>
            <p className="text-sm text-muted-foreground">{meta.description}</p>
          </div>
        </div>
        <ChevronDown
          className={`h-4 w-4 text-muted-foreground transition-transform ${
            isOpen ? "rotate-180" : ""
          }`}
        />
      </button>
      {isOpen && (
        <div className="space-y-3 border-t border-border/40 p-4">
          {services.map((service) => (
            <ServiceCard
              key={service.id}
              service={service}
              isChecked={checkedServices.has(service.id)}
              onToggle={() => onToggleService(service.id)}
            />
          ))}
        </div>
      )}
    </div>
  );
}

export default function AccountsPage() {
  const router = useRouter();
  const [isNavigating, setIsNavigating] = useState(false);
  const [checkedServiceIds, toggleService, checkedServicesLoaded] = useCheckedServices();
  const checkedServices = useMemo(() => new Set(checkedServiceIds), [checkedServiceIds]);
  const [moduleProfile, setModuleProfile, moduleProfileLoaded] = useModuleProfile();
  const [moduleSelection, moduleSelectionLoaded] = useModuleSelection();
  const installationSession = useWizardInstallation();
  const reviewedInstallation =
    installationSession?.status === "active" ? installationSession.installation : null;
  const ready =
    checkedServicesLoaded &&
    moduleProfileLoaded &&
    moduleSelectionLoaded &&
    (!installationSession || ["saved", "active"].includes(installationSession.status));
  const modulePlan = useMemo(
    () => (ready ? resolveModuleSelection(moduleSelection) : null),
    [ready, moduleSelection],
  );
  const canContinue = ready && modulePlan?.ok === true && modulePlan.selectedCount > 0;
  const selectedModules = useMemo(
    () => new Set(modulePlan?.included.map((module) => module.id) ?? []),
    [modulePlan],
  );
  // The same dependency-complete plan supplies signup guidance and the later
  // Status Check authentication cards. A profile label alone loses exact skips.
  const selectedServices = useMemo(
    () => Object.values(getSelectedAuthServices(selectedModules)).flat(),
    [selectedModules],
  );
  const selectedAgents = manifestAgents.filter((agent) => selectedModules.has(agent.moduleId));
  const subscriptionServices = selectedServices.filter((service) => service.requiresSubscription);
  const selectedCheckedIds = useMemo(
    () => selectedServices.filter((service) => checkedServices.has(service.id))
      .map((service) => service.id),
    [selectedServices, checkedServices],
  );

  // Analytics tracking for this wizard step
  const { markComplete } = useWizardAnalytics({
    step: "accounts",
    stepNumber: 7,
    stepTitle: "Set Up Accounts",
  });

  const handleContinue = useCallback(() => {
    if (!canContinue || isNavigating) return;
    markComplete({
      accounts_checked: selectedCheckedIds,
      accounts_count: selectedCheckedIds.length,
    });
    markStepComplete(7);
    setIsNavigating(true);
    router.push(withCurrentSearch("/wizard/preflight-check"));
  }, [router, markComplete, selectedCheckedIds, canContinue, isNavigating]);

  const handleSkip = useCallback(() => {
    if (!canContinue || isNavigating) return;
    markComplete({ skipped: true });
    markStepComplete(7);
    setIsNavigating(true);
    router.push(withCurrentSearch("/wizard/preflight-check"));
  }, [router, markComplete, canContinue, isNavigating]);

  // Dock "Next" = Continue; "Skip for now" stays an explicit inline choice.
  const forwardCtaRef = useWizardForwardNav({
    onContinue: handleContinue,
    disabled: isNavigating || !canContinue,
    loading: isNavigating,
    label: "Continue to pre-flight check",
  });

  const tieredServices: Record<ServiceTier, Service[]> = {
    essential: selectedServices.filter((service) => service.tier === "essential").sort(sortByOrder),
    recommended: selectedServices.filter((service) => service.tier === "recommended").sort(sortByOrder),
    optional: selectedServices.filter((service) => service.tier === "optional").sort(sortByOrder),
  };

  const essentialServices = tieredServices.essential;
  const essentialChecked = essentialServices.filter((s) => checkedServices.has(s.id));

  if (!ready) {
    return (
      <p role="status" className="py-8">
        Loading your selected setup before showing account guidance...
      </p>
    );
  }

  const selectionControl = (
    <section
      aria-labelledby="accounts-selection-heading"
      className="space-y-3 rounded-xl border border-border/50 bg-card/50 p-4"
    >
      <h2 id="accounts-selection-heading" className="text-lg font-semibold">
        Choose your tools before signing up
      </h2>
      {reviewedInstallation ? (
        <p role="status" className="text-sm text-muted-foreground">
          Using reviewed team profile: {reviewedInstallation.displayName}. These accounts follow
          its exact module selection. Discard the reviewed installation above before changing it.
        </p>
      ) : (
        <>
          <label htmlFor="accounts-profile" className="block text-sm font-medium">
            Installation profile
          </label>
          <select
            id="accounts-profile"
            value={moduleProfile}
            onChange={(event) => {
              const profile = manifestSelectionProfiles.find(
                (item) => item.id === event.target.value && !item.mode,
              );
              if (profile) setModuleProfile(profile.id);
            }}
            className="min-h-11 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
          >
            {manifestSelectionProfiles.filter((profile) => !profile.mode).map((profile) => (
              <option key={profile.id} value={profile.id}>{profile.label}</option>
            ))}
          </select>
          <p className="text-sm text-muted-foreground">
            This choice also applies to Run Installer. Account checkboxes only record your progress;
            they do not add or remove tools from the installation.
          </p>
        </>
      )}
      <p role="status" className="text-sm text-muted-foreground">
        {canContinue
          ? `${modulePlan.selectedCount} modules selected, including dependencies.`
          : "This selection cannot produce an installation plan. Choose a valid profile before continuing."}
      </p>
    </section>
  );

  if (!canContinue) {
    return (
      <div className="space-y-6">
        <h1 className="text-2xl font-bold">Set up your accounts</h1>
        {selectionControl}
        <AlertCard variant="error" title="Account guidance unavailable">
          Review the selected modules before creating accounts. No signup or authentication
          commands are shown for an invalid or empty installation.
        </AlertCard>
      </div>
    );
  }

  return (
    <div className="space-y-8">
      {/* Header */}
      <div className="space-y-2">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary/20">
            <Users className="h-5 w-5 text-primary" />
          </div>
          <div>
            <h1 className="bg-gradient-to-r from-foreground via-foreground to-muted-foreground bg-clip-text text-2xl font-bold tracking-tight text-transparent sm:text-3xl">
              Set up your accounts
            </h1>
            <p className="text-sm text-muted-foreground">~5-10 min</p>
          </div>
        </div>
        <p className="text-muted-foreground">
          Set up accounts for the tools selected for your <Jargon term="vps">VPS</Jargon>.
          You can wait until installation is complete to sign in.
        </p>
      </div>

      {selectionControl}

      {/* Cost warning - prominent placement for subscription services */}
      {subscriptionServices.length > 0 && <AlertCard variant="warning" icon={DollarSign} title="Check account access before subscribing">
        Review the plan requirements for the selected agents you intend to use:
        <ul className="mt-2 list-inside list-disc space-y-1 text-sm">
          {subscriptionServices.map((service) => (
            <li key={service.id}><strong>{service.name}</strong>: {service.subscriptionNote ?? service.shortDescription}</li>
          ))}
        </ul>
        <p className="mt-2 text-sm">
          Start with the agent you plan to use. Installing an agent does not require signing up
          for every service, and an existing eligible account may be sufficient.
        </p>
      </AlertCard>}

      {/* Count only accounts that belong to the current installation. */}
      {selectedServices.some((service) => service.supportsGoogleSso) && <AlertCard variant="tip" icon={Sparkles} title="Quick signup with Google">
        {selectedServices.filter((service) => service.supportsGoogleSso).length} of {selectedServices.length} selected services support Google SSO. Use the
        same Google account for all of them to streamline your setup. That makes that one account
        worth protecting:{" "}
        <Link href="/docs/security" className="font-medium text-primary hover:underline">
          how to secure it, and what to do if it is compromised
        </Link>
        .
      </AlertCard>}

      {/* Progress indicator */}
      {essentialServices.length > 0 && <div className="rounded-xl border border-border/50 bg-card/50 p-4">
        <div className="flex items-center justify-between">
          <span className="text-sm text-muted-foreground">Essential accounts:</span>
          <span className="font-medium">
            {essentialChecked.length} / {essentialServices.length}
          </span>
        </div>
        <div className="mt-2 h-2 overflow-hidden rounded-full bg-muted">
          <div
            className="h-full bg-green transition-[width]"
            style={{
              width: `${
                essentialServices.length > 0
                  ? (essentialChecked.length / essentialServices.length) * 100
                  : 0
              }%`,
            }}
          />
        </div>
      </div>}

      {selectedServices.length === 0 && (
        <AlertCard
          variant="info"
          title={selectedAgents.length > 0
            ? "Review your selected agents' sign-in options"
            : "No listed accounts needed for this selection"}
        >
          {selectedAgents.length > 0 ? (
            <>
              Use the agent documentation below to choose the accounts or providers you need.
              After installation, Status Check will show sign-in guidance for these selected agents.
            </>
          ) : (
            <>
              Your selected modules do not use the services listed in this step. Continue to
              pre-flight checks; you can create additional accounts later if you add tools that
              need them.
            </>
          )}
        </AlertCard>
      )}

      {/* Service tiers */}
      <div className="space-y-4">
        {(["essential", "recommended", "optional"] as ServiceTier[]).map((tier) => (
          <TierSection
            key={tier}
            tier={tier}
            services={tieredServices[tier]}
            checkedServices={checkedServices}
            onToggleService={toggleService}
          />
        ))}
      </div>

      {/* Compatible agents roster - generated from acfs.manifest.yaml so the
          accounts you sign up for always match the agents ACFS can install. */}
      {selectedAgents.length > 0 && <section aria-labelledby="compatible-agents-heading" className="space-y-3">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary/20">
            <Bot className="h-5 w-5 text-primary" />
          </div>
          <div>
            <h2 id="compatible-agents-heading" className="text-lg font-semibold">
              Coding agents in your selection
            </h2>
            <p className="text-sm text-muted-foreground">
              Your plan includes {selectedAgents.length} coding agents. Use their sign-in commands
              after installation, and create accounts only for the agents you intend to use.
            </p>
          </div>
        </div>
        <AgentRoster variant="surface" agents={selectedAgents} />
      </section>}

      {/* Beginner Guide */}
      {selectedServices.length > 0 && <SimplerGuide>
        <div className="space-y-6">
          <GuideExplain term="Which accounts do I need?">
            This page lists services for your selected tools, including their dependencies.
            Set up the accounts you expect to use; signing up can wait until after installation.
            {essentialServices.length > 0 && (
              <p className="mt-3">
                <strong>Start here:</strong> {essentialServices.map((service) => service.name).join(" and ")}.
                The other listed services can wait until your project needs them.
              </p>
            )}
          </GuideExplain>

          <GuideSection title="How to Sign Up Efficiently">
            <div className="space-y-4">
              <GuideStep number={1} title="Use Google SSO when available">
                Click the green &quot;Sign up with Google&quot; button. This is fastest and you
                won&apos;t need to remember extra passwords.
              </GuideStep>

              <GuideStep number={2} title="Check the box after signing up">
                Check the box next to each account you already have or create. These are progress
                notes; they do not change the tools you selected.
              </GuideStep>

              <GuideStep number={3} title="Start with the tools you plan to use">
                Create accounts for your immediate work. You can return for the remaining
                services when you need them.
              </GuideStep>

              <GuideStep number={4} title="You can come back later">
                Don&apos;t want to create all accounts now? That&apos;s fine! Click &quot;Skip for
                now&quot; and create them after installation.
              </GuideStep>
            </div>
          </GuideSection>

          <GuideTip>
            <strong>Pro tip:</strong> Open each signup link in a new tab (Cmd+click on Mac,
            Ctrl+click on Linux/Windows). That way you can create multiple accounts quickly without
            losing your place here.
          </GuideTip>

          {selectedAgents.length > 0 && <div className="rounded-lg border border-primary/20 bg-primary/5 p-4">
            <Link href="/learn/agent-commands" className="flex items-center gap-3 text-sm">
              <BookOpen className="h-5 w-5 text-primary" />
              <div>
                <span className="font-medium text-foreground">Need help with agent logins?</span>
                <p className="text-muted-foreground">
                  See the Agent Commands lesson for auth tips and shortcuts →
                </p>
              </div>
            </Link>
          </div>}
        </div>
      </SimplerGuide>}

      {/* Skip reassurance note */}
      <div className="rounded-xl border border-muted bg-muted/30 p-4">
        <p className="text-sm text-muted-foreground">
          <strong className="text-foreground">Don&apos;t want to create accounts now?</strong>{" "}
          That&apos;s completely fine! You can skip this step and create accounts after
          installation. The ACFS installer follows your selected modules; authenticate the tools
          you need when you&apos;re ready to use them.
        </p>
      </div>

      {/* Action buttons */}
      <div className="flex flex-col gap-3 pt-4 sm:flex-row sm:justify-end">
        <Button variant="outline" onClick={handleSkip} disabled={isNavigating || !canContinue}>
          Skip for now
        </Button>
        <Button
          ref={forwardCtaRef}
          data-wizard-primary-cta
          onClick={handleContinue}
          disabled={isNavigating || !canContinue}
          size="lg"
          disableMotion
        >
          {isNavigating ? "Loading..." : "Continue to pre-flight check"}
        </Button>
      </div>
    </div>
  );
}
