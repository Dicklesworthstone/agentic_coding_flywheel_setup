"use client";

/**
 * VPSComparison — Side-by-side provider comparison table for the wizard.
 *
 * Shows key specs (RAM, vCPU, storage, price) for recommended and budget
 * plans across providers. Responsive: table on desktop, stacked cards on
 * mobile.
 *
 * @see bd-w8fx
 */

import { useState } from "react";
import { ExternalLink, Star, Clock } from "lucide-react";
import { TrackedLink } from "@/components/tracked-link";
import { cn } from "@/lib/utils";
import {
  VPS_PROVIDERS,
  PRICING_LAST_UPDATED,
  type VPSProvider,
} from "@/lib/vpsProviders";

type PlanTier = "recommended" | "budget";

function formatPrice(usd: number): string {
  return `$${usd}/mo`;
}

function ProviderMobileCard({
  provider,
  tier,
}: {
  provider: VPSProvider;
  tier: PlanTier;
}) {
  const plan = provider[tier];
  return (
    <div
      className={cn(
        "rounded-xl border p-4 space-y-3",
        provider.isTopPick
          ? "border-primary/30 bg-primary/5"
          : "border-border/50 bg-card/50"
      )}
    >
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <span className="font-semibold text-foreground">{provider.name}</span>
          {provider.isTopPick && (
            <span className="inline-flex items-center gap-1 rounded-full bg-primary/20 px-2 py-0.5 text-xs font-medium text-primary">
              <Star className="h-3 w-3" />
              Top pick
            </span>
          )}
        </div>
        <span className="text-lg font-bold text-foreground">
          {formatPrice(plan.priceUSD)}
        </span>
      </div>

      <div className="grid grid-cols-2 gap-2 text-sm">
        <div>
          <span className="text-muted-foreground">Plan:</span>{" "}
          <span className="font-medium text-foreground">{plan.name}</span>
        </div>
        <div>
          <span className="text-muted-foreground">RAM:</span>{" "}
          <span className="font-medium text-foreground">{plan.ramGB}GB</span>
        </div>
        <div>
          <span className="text-muted-foreground">vCPU:</span>{" "}
          <span className="font-medium text-foreground">{plan.vCPU}</span>
        </div>
        <div>
          <span className="text-muted-foreground">Storage:</span>{" "}
          <span className="font-medium text-foreground">{plan.storageGB}GB</span>
        </div>
      </div>

      <div className="flex items-center justify-between border-t border-border/30 pt-2 text-sm">
        <div className="flex items-center gap-1 text-muted-foreground">
          <Clock className="h-3.5 w-3.5" />
          {provider.activationTime}
        </div>
        <TrackedLink
          href={provider.url}
          trackingId={`vps-compare-${provider.id}`}
          className="inline-flex min-h-6 items-center gap-1 font-medium text-primary hover:underline"
        >
          Visit site
          <ExternalLink className="h-3.5 w-3.5" />
        </TrackedLink>
      </div>

      {provider.note && (
        <p className="text-xs text-muted-foreground">{provider.note}</p>
      )}
    </div>
  );
}

export function VPSComparison() {
  const [tier, setTier] = useState<PlanTier>("recommended");

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h2 className="font-semibold text-foreground">
          Quick comparison
        </h2>
        {/* Tier toggle */}
        <div className="flex rounded-lg border border-border/50 bg-muted/30 p-0.5 text-sm">
          <button
            type="button"
            onClick={() => setTier("recommended")}
            aria-pressed={tier === "recommended"}
            className={cn(
              "rounded-md px-3 py-1 font-medium transition-colors",
              tier === "recommended"
                ? "bg-background text-foreground shadow-sm"
                : "text-muted-foreground hover:text-foreground"
            )}
          >
            64 GB
          </button>
          <button
            type="button"
            onClick={() => setTier("budget")}
            aria-pressed={tier === "budget"}
            className={cn(
              "rounded-md px-3 py-1 font-medium transition-colors",
              tier === "budget"
                ? "bg-background text-foreground shadow-sm"
                : "text-muted-foreground hover:text-foreground"
            )}
          >
            48 GB
          </button>
        </div>
      </div>

      {/* Desktop table — hidden on mobile. Eight columns do not fit between
          ~640px and ~900px, so the outer wrapper scrolls horizontally instead
          of clipping the Price/Activation/Link columns; the inner wrapper
          keeps the rounded border. */}
      <div className="hidden overflow-x-auto sm:block">
        <div className="min-w-[44rem] overflow-hidden rounded-xl border border-border/50">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-border/50 bg-muted/30">
              <th className="px-4 py-3 text-left font-medium text-muted-foreground">
                Provider
              </th>
              <th className="px-4 py-3 text-left font-medium text-muted-foreground">
                Plan
              </th>
              <th className="px-4 py-3 text-right font-medium text-muted-foreground">
                RAM
              </th>
              <th className="px-4 py-3 text-right font-medium text-muted-foreground">
                vCPU
              </th>
              <th className="px-4 py-3 text-right font-medium text-muted-foreground">
                Storage
              </th>
              <th className="px-4 py-3 text-right font-medium text-muted-foreground">
                Price
              </th>
              <th className="px-4 py-3 text-left font-medium text-muted-foreground">
                Activation
              </th>
              <th className="px-4 py-3 text-center font-medium text-muted-foreground">
                Link
              </th>
            </tr>
          </thead>
          <tbody>
            {VPS_PROVIDERS.map((provider, i) => {
              const plan = provider[tier];
              return (
                <tr
                  key={provider.id}
                  className={cn(
                    "border-b border-border/30 last:border-0 transition-colors",
                    provider.isTopPick
                      ? "bg-primary/5"
                      : i % 2 === 1
                        ? "bg-muted/10"
                        : ""
                  )}
                >
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-2">
                      <span className="font-medium text-foreground">
                        {provider.name}
                      </span>
                      {provider.isTopPick && (
                        <span className="inline-flex items-center gap-0.5 rounded-full bg-primary/20 px-1.5 py-0.5 text-xs font-medium text-primary">
                          <Star className="h-2.5 w-2.5" />
                          Top pick
                        </span>
                      )}
                    </div>
                    <p className="text-xs text-muted-foreground">
                      {provider.bestFor}
                    </p>
                  </td>
                  <td className="px-4 py-3 text-foreground">{plan.name}</td>
                  <td className="px-4 py-3 text-right font-mono text-foreground">
                    {plan.ramGB}GB
                  </td>
                  <td className="px-4 py-3 text-right font-mono text-foreground">
                    {plan.vCPU}
                  </td>
                  <td className="px-4 py-3 text-right font-mono text-foreground">
                    {plan.storageGB}GB
                  </td>
                  <td className="px-4 py-3 text-right font-mono font-semibold text-foreground">
                    {formatPrice(plan.priceUSD)}
                  </td>
                  <td className="px-4 py-3 text-muted-foreground">
                    {provider.activationTime}
                  </td>
                  <td className="px-4 py-3 text-center">
                    <TrackedLink
                      href={provider.url}
                      trackingId={`vps-table-${provider.id}`}
                      className="inline-flex items-center gap-1 text-primary hover:underline"
                    >
                      Visit
                      <ExternalLink className="h-3.5 w-3.5" />
                    </TrackedLink>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
        </div>
      </div>

      {/* Mobile cards — hidden on desktop */}
      <div className="space-y-3 sm:hidden">
        {VPS_PROVIDERS.map((provider) => (
          <ProviderMobileCard
            key={provider.id}
            provider={provider}
            tier={tier}
          />
        ))}
      </div>

      {/* Footer note */}
      <p className="text-xs text-muted-foreground">
        Prices are month-to-month, no commitment.
        Last updated {PRICING_LAST_UPDATED}. Longer commitments may offer 5-20%
        discounts.
      </p>
    </div>
  );
}
