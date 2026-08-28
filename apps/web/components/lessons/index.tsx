"use client";

import dynamic from "next/dynamic";
import type { ComponentType, ReactNode } from "react";
import { Skeleton, SkeletonText } from "@/components/ui/skeleton";

// Shared lightweight fallback shown while a lesson chunk streams in on
// client-side navigation. SSR still renders the real lesson, so this only
// appears between route transitions.
function LessonLoading() {
  return (
    <div
      role="status"
      aria-live="polite"
      aria-busy="true"
      aria-label="Loading lesson"
      className="space-y-8"
    >
      <Skeleton className="h-8 w-2/3 bg-white/[0.06]" />
      <SkeletonText lines={3} className="[&>*]:bg-white/[0.05]" />
      <Skeleton className="h-40 w-full rounded-2xl bg-white/[0.04]" />
      <SkeletonText lines={2} className="[&>*]:bg-white/[0.05]" />
    </div>
  );
}

// Each lesson is code-split into its own chunk via next/dynamic (SSR stays on).
// Keeping the map at module scope means no component is created during render,
// which is what the previous static switch guaranteed. The `loading` option is
// repeated inline because next/dynamic requires an object literal there.
const LESSON_COMPONENTS = new Map<string, ComponentType>([
  ["welcome", dynamic(() => import("./welcome-lesson").then((m) => ({ default: m.WelcomeLesson })), { loading: LessonLoading })],
  ["linux-basics", dynamic(() => import("./linux-basics-lesson").then((m) => ({ default: m.LinuxBasicsLesson })), { loading: LessonLoading })],
  ["ssh-basics", dynamic(() => import("./ssh-basics-lesson").then((m) => ({ default: m.SSHBasicsLesson })), { loading: LessonLoading })],
  ["tmux-basics", dynamic(() => import("./tmux-basics-lesson").then((m) => ({ default: m.TmuxBasicsLesson })), { loading: LessonLoading })],
  ["git-basics", dynamic(() => import("./git-basics-lesson").then((m) => ({ default: m.GitBasicsLesson })), { loading: LessonLoading })],
  ["github-cli", dynamic(() => import("./github-cli-lesson").then((m) => ({ default: m.GithubCliLesson })), { loading: LessonLoading })],
  ["agent-commands", dynamic(() => import("./agents-login-lesson").then((m) => ({ default: m.AgentsLoginLesson })), { loading: LessonLoading })],
  ["ntm-core", dynamic(() => import("./ntm-core-lesson").then((m) => ({ default: m.NtmCoreLesson })), { loading: LessonLoading })],
  ["ntm-palette", dynamic(() => import("./ntm-palette-lesson").then((m) => ({ default: m.NtmPaletteLesson })), { loading: LessonLoading })],
  ["flywheel-loop", dynamic(() => import("./flywheel-loop-lesson").then((m) => ({ default: m.FlywheelLoopLesson })), { loading: LessonLoading })],
  ["keeping-updated", dynamic(() => import("./keeping-updated-lesson").then((m) => ({ default: m.KeepingUpdatedLesson })), { loading: LessonLoading })],
  ["ubs", dynamic(() => import("./ubs-lesson").then((m) => ({ default: m.UbsLesson })), { loading: LessonLoading })],
  ["agent-mail", dynamic(() => import("./agent-mail-lesson").then((m) => ({ default: m.AgentMailLesson })), { loading: LessonLoading })],
  ["cass", dynamic(() => import("./cass-lesson").then((m) => ({ default: m.CassLesson })), { loading: LessonLoading })],
  ["cm", dynamic(() => import("./cm-lesson").then((m) => ({ default: m.CmLesson })), { loading: LessonLoading })],
  ["beads", dynamic(() => import("./beads-lesson").then((m) => ({ default: m.BeadsLesson })), { loading: LessonLoading })],
  ["safety-tools", dynamic(() => import("./safety-tools-lesson").then((m) => ({ default: m.SafetyToolsLesson })), { loading: LessonLoading })],
  ["dcg", dynamic(() => import("./dcg-lesson").then((m) => ({ default: m.DcgLesson })), { loading: LessonLoading })],
  ["prompt-engineering", dynamic(() => import("./prompt-engineering-lesson").then((m) => ({ default: m.PromptEngineeringLesson })), { loading: LessonLoading })],
  ["real-world-case-study", dynamic(() => import("./real-world-case-study-lesson").then((m) => ({ default: m.RealWorldCaseStudyLesson })), { loading: LessonLoading })],
  ["slb-case-study", dynamic(() => import("./slb-case-study-lesson").then((m) => ({ default: m.SlbCaseStudyLesson })), { loading: LessonLoading })],
  ["ru", dynamic(() => import("./ru-lesson").then((m) => ({ default: m.RuLesson })), { loading: LessonLoading })],
  ["ms", dynamic(() => import("./ms-lesson").then((m) => ({ default: m.MsLesson })), { loading: LessonLoading })],
  ["apr", dynamic(() => import("./apr-lesson").then((m) => ({ default: m.AprLesson })), { loading: LessonLoading })],
  ["jfp", dynamic(() => import("./jfp-lesson").then((m) => ({ default: m.JfpLesson })), { loading: LessonLoading })],
  ["pt", dynamic(() => import("./pt-lesson").then((m) => ({ default: m.PtLesson })), { loading: LessonLoading })],
  ["xf", dynamic(() => import("./xf-lesson").then((m) => ({ default: m.XfLesson })), { loading: LessonLoading })],
  ["srps", dynamic(() => import("./srps-lesson").then((m) => ({ default: m.SrpsLesson })), { loading: LessonLoading })],
  ["rch", dynamic(() => import("./rch-lesson").then((m) => ({ default: m.RchLesson })), { loading: LessonLoading })],
  ["wa", dynamic(() => import("./wa-lesson").then((m) => ({ default: m.WaLesson })), { loading: LessonLoading })],
  ["brenner", dynamic(() => import("./brenner-lesson").then((m) => ({ default: m.BrennerLesson })), { loading: LessonLoading })],
  ["giil", dynamic(() => import("./giil-lesson").then((m) => ({ default: m.GiilLesson })), { loading: LessonLoading })],
  ["s2p", dynamic(() => import("./s2p-lesson").then((m) => ({ default: m.S2pLesson })), { loading: LessonLoading })],
  ["fsfs", dynamic(() => import("./fsfs-lesson").then((m) => ({ default: m.FsfsLesson })), { loading: LessonLoading })],
  ["sbh", dynamic(() => import("./sbh-lesson").then((m) => ({ default: m.SbhLesson })), { loading: LessonLoading })],
  ["casr", dynamic(() => import("./casr-lesson").then((m) => ({ default: m.CasrLesson })), { loading: LessonLoading })],
  ["dsr", dynamic(() => import("./dsr-lesson").then((m) => ({ default: m.DsrLesson })), { loading: LessonLoading })],
  ["asb", dynamic(() => import("./asb-lesson").then((m) => ({ default: m.AsbLesson })), { loading: LessonLoading })],
  ["pcr", dynamic(() => import("./pcr-lesson").then((m) => ({ default: m.PcrLesson })), { loading: LessonLoading })],
  ["csctf", dynamic(() => import("./csctf-lesson").then((m) => ({ default: m.CsctfLesson })), { loading: LessonLoading })],
  ["tru", dynamic(() => import("./tru-lesson").then((m) => ({ default: m.TruLesson })), { loading: LessonLoading })],
  ["mdwb", dynamic(() => import("./mdwb-lesson").then((m) => ({ default: m.MdwbLesson })), { loading: LessonLoading })],
  ["rano", dynamic(() => import("./rano-lesson").then((m) => ({ default: m.RanoLesson })), { loading: LessonLoading })],
  ["caut", dynamic(() => import("./caut-lesson").then((m) => ({ default: m.CautLesson })), { loading: LessonLoading })],
  ["aadc", dynamic(() => import("./aadc-lesson").then((m) => ({ default: m.AadcLesson })), { loading: LessonLoading })],
  ["rust-proxy", dynamic(() => import("./rust-proxy-lesson").then((m) => ({ default: m.RustProxyLesson })), { loading: LessonLoading })],
  ["bv", dynamic(() => import("./bv-lesson").then((m) => ({ default: m.BvLesson })), { loading: LessonLoading })],
  ["caam", dynamic(() => import("./caam-lesson").then((m) => ({ default: m.CaamLesson })), { loading: LessonLoading })],
  ["swarm-coordination", dynamic(() => import("./swarm-coordination-lesson").then((m) => ({ default: m.SwarmCoordinationLesson })), { loading: LessonLoading })],
  ["debugging-agents", dynamic(() => import("./debugging-agents-lesson").then((m) => ({ default: m.DebuggingAgentsLesson })), { loading: LessonLoading })],
  ["context-mastery", dynamic(() => import("./context-mastery-lesson").then((m) => ({ default: m.ContextMasteryLesson })), { loading: LessonLoading })],
  ["ci-cd", dynamic(() => import("./ci-cd-lesson").then((m) => ({ default: m.CiCdLesson })), { loading: LessonLoading })],
  ["project-bootstrap", dynamic(() => import("./project-bootstrap-lesson").then((m) => ({ default: m.ProjectBootstrapLesson })), { loading: LessonLoading })],
  ["ast-grep", dynamic(() => import("./ast-grep-lesson").then((m) => ({ default: m.AstGrepLesson })), { loading: LessonLoading })],
  ["agents-md", dynamic(() => import("./agents-md-lesson").then((m) => ({ default: m.AgentsMdLesson })), { loading: LessonLoading })],
  ["modern-cli", dynamic(() => import("./modern-cli-lesson").then((m) => ({ default: m.ModernCliLesson })), { loading: LessonLoading })],
  ["tailscale", dynamic(() => import("./tailscale-lesson").then((m) => ({ default: m.TailscaleLesson })), { loading: LessonLoading })],
  ["lang-runtimes", dynamic(() => import("./lang-runtimes-lesson").then((m) => ({ default: m.LangRuntimesLesson })), { loading: LessonLoading })],
  ["cloud-infra", dynamic(() => import("./cloud-infra-lesson").then((m) => ({ default: m.CloudInfraLesson })), { loading: LessonLoading })],
  ["security-layers", dynamic(() => import("./security-layers-lesson").then((m) => ({ default: m.SecurityLayersLesson })), { loading: LessonLoading })],
  ["acfs-doctor", dynamic(() => import("./acfs-doctor-lesson").then((m) => ({ default: m.AcfsDoctorLesson })), { loading: LessonLoading })],
  ["ee", dynamic(() => import("./ee-lesson").then((m) => ({ default: m.EeLesson })), { loading: LessonLoading })],
  ["fmd", dynamic(() => import("./fmd-lesson").then((m) => ({ default: m.FmdLesson })), { loading: LessonLoading })],
  ["pi", dynamic(() => import("./pi-lesson").then((m) => ({ default: m.PiLesson })), { loading: LessonLoading })],
  ["pfr", dynamic(() => import("./pfr-lesson").then((m) => ({ default: m.PfrLesson })), { loading: LessonLoading })],
]);

// Render the lesson content for a given slug. Returns null for unknown slugs.
export function renderLessonComponent(slug: string): ReactNode | null {
  const LessonComponent = LESSON_COMPONENTS.get(slug);
  if (!LessonComponent) {
    return null;
  }
  return <LessonComponent />;
}
