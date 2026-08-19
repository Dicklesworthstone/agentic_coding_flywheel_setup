"use client";

import { WelcomeLesson } from "./welcome-lesson";
import { LinuxBasicsLesson } from "./linux-basics-lesson";
import { SSHBasicsLesson } from "./ssh-basics-lesson";
import { TmuxBasicsLesson } from "./tmux-basics-lesson";
import { GitBasicsLesson } from "./git-basics-lesson";
import { GithubCliLesson } from "./github-cli-lesson";
import { AgentsLoginLesson } from "./agents-login-lesson";
import { NtmCoreLesson } from "./ntm-core-lesson";
import { NtmPaletteLesson } from "./ntm-palette-lesson";
import { FlywheelLoopLesson } from "./flywheel-loop-lesson";
import { KeepingUpdatedLesson } from "./keeping-updated-lesson";
import { UbsLesson } from "./ubs-lesson";
import { AgentMailLesson } from "./agent-mail-lesson";
import { CassLesson } from "./cass-lesson";
import { CmLesson } from "./cm-lesson";
import { BeadsLesson } from "./beads-lesson";
import { SafetyToolsLesson } from "./safety-tools-lesson";
import { DcgLesson } from "./dcg-lesson";
import { PromptEngineeringLesson } from "./prompt-engineering-lesson";
import { RealWorldCaseStudyLesson } from "./real-world-case-study-lesson";
import { SlbCaseStudyLesson } from "./slb-case-study-lesson";
import { RuLesson } from "./ru-lesson";
import { MsLesson } from "./ms-lesson";
import { AprLesson } from "./apr-lesson";
import { JfpLesson } from "./jfp-lesson";
import { PtLesson } from "./pt-lesson";
import { XfLesson } from "./xf-lesson";
import { SrpsLesson } from "./srps-lesson";
import { RchLesson } from "./rch-lesson";
import { WaLesson } from "./wa-lesson";
import { BrennerLesson } from "./brenner-lesson";
import { GiilLesson } from "./giil-lesson";
import { S2pLesson } from "./s2p-lesson";
import { FsfsLesson } from "./fsfs-lesson";
import { SbhLesson } from "./sbh-lesson";
import { CasrLesson } from "./casr-lesson";
import { DsrLesson } from "./dsr-lesson";
import { AsbLesson } from "./asb-lesson";
import { PcrLesson } from "./pcr-lesson";
import { CsctfLesson } from "./csctf-lesson";
import { TruLesson } from "./tru-lesson";
import { MdwbLesson } from "./mdwb-lesson";
import { RanoLesson } from "./rano-lesson";
import { CautLesson } from "./caut-lesson";
import { AadcLesson } from "./aadc-lesson";
import { RustProxyLesson } from "./rust-proxy-lesson";
import { BvLesson } from "./bv-lesson";
import { CaamLesson } from "./caam-lesson";
import { SwarmCoordinationLesson } from "./swarm-coordination-lesson";
import { DebuggingAgentsLesson } from "./debugging-agents-lesson";
import { ContextMasteryLesson } from "./context-mastery-lesson";
import { CiCdLesson } from "./ci-cd-lesson";
import { ProjectBootstrapLesson } from "./project-bootstrap-lesson";
import { AstGrepLesson } from "./ast-grep-lesson";
import { AgentsMdLesson } from "./agents-md-lesson";
import { ModernCliLesson } from "./modern-cli-lesson";
import { TailscaleLesson } from "./tailscale-lesson";
import { LangRuntimesLesson } from "./lang-runtimes-lesson";
import { CloudInfraLesson } from "./cloud-infra-lesson";
import { SecurityLayersLesson } from "./security-layers-lesson";
import { AcfsDoctorLesson } from "./acfs-doctor-lesson";
import { EeLesson } from "./ee-lesson";
import { FmdLesson } from "./fmd-lesson";
import { PiLesson } from "./pi-lesson";
import { PfrLesson } from "./pfr-lesson";

// Render the lesson content for a given slug.
// This intentionally uses a static switch so ESLint can guarantee components are not created during render.
export function renderLessonComponent(slug: string): React.ReactNode | null {
  switch (slug) {
    case "welcome":
      return <WelcomeLesson />;
    case "linux-basics":
      return <LinuxBasicsLesson />;
    case "ssh-basics":
      return <SSHBasicsLesson />;
    case "tmux-basics":
      return <TmuxBasicsLesson />;
    case "git-basics":
      return <GitBasicsLesson />;
    case "github-cli":
      return <GithubCliLesson />;
    case "agent-commands":
      return <AgentsLoginLesson />;
    case "ntm-core":
      return <NtmCoreLesson />;
    case "ntm-palette":
      return <NtmPaletteLesson />;
    case "flywheel-loop":
      return <FlywheelLoopLesson />;
    case "keeping-updated":
      return <KeepingUpdatedLesson />;
    case "ubs":
      return <UbsLesson />;
    case "agent-mail":
      return <AgentMailLesson />;
    case "cass":
      return <CassLesson />;
    case "cm":
      return <CmLesson />;
    case "beads":
      return <BeadsLesson />;
    case "safety-tools":
      return <SafetyToolsLesson />;
    case "dcg":
      return <DcgLesson />;
    case "prompt-engineering":
      return <PromptEngineeringLesson />;
    case "real-world-case-study":
      return <RealWorldCaseStudyLesson />;
    case "slb-case-study":
      return <SlbCaseStudyLesson />;
    case "ru":
      return <RuLesson />;
    case "ms":
      return <MsLesson />;
    case "apr":
      return <AprLesson />;
    case "jfp":
      return <JfpLesson />;
    case "pt":
      return <PtLesson />;
    case "xf":
      return <XfLesson />;
    case "srps":
      return <SrpsLesson />;
    case "rch":
      return <RchLesson />;
    case "wa":
      return <WaLesson />;
    case "brenner":
      return <BrennerLesson />;
    case "giil":
      return <GiilLesson />;
    case "s2p":
      return <S2pLesson />;
    case "fsfs":
      return <FsfsLesson />;
    case "sbh":
      return <SbhLesson />;
    case "casr":
      return <CasrLesson />;
    case "dsr":
      return <DsrLesson />;
    case "asb":
      return <AsbLesson />;
    case "pcr":
      return <PcrLesson />;
    case "csctf":
      return <CsctfLesson />;
    case "tru":
      return <TruLesson />;
    case "mdwb":
      return <MdwbLesson />;
    case "rano":
      return <RanoLesson />;
    case "caut":
      return <CautLesson />;
    case "aadc":
      return <AadcLesson />;
    case "rust-proxy":
      return <RustProxyLesson />;
    case "bv":
      return <BvLesson />;
    case "caam":
      return <CaamLesson />;
    case "swarm-coordination":
      return <SwarmCoordinationLesson />;
    case "debugging-agents":
      return <DebuggingAgentsLesson />;
    case "context-mastery":
      return <ContextMasteryLesson />;
    case "ci-cd":
      return <CiCdLesson />;
    case "project-bootstrap":
      return <ProjectBootstrapLesson />;
    case "ast-grep":
      return <AstGrepLesson />;
    case "agents-md":
      return <AgentsMdLesson />;
    case "modern-cli":
      return <ModernCliLesson />;
    case "tailscale":
      return <TailscaleLesson />;
    case "lang-runtimes":
      return <LangRuntimesLesson />;
    case "cloud-infra":
      return <CloudInfraLesson />;
    case "security-layers":
      return <SecurityLayersLesson />;
    case "acfs-doctor":
      return <AcfsDoctorLesson />;
    case "ee":
      return <EeLesson />;
    case "fmd":
      return <FmdLesson />;
    case "pi":
      return <PiLesson />;
    case "pfr":
      return <PfrLesson />;
    default:
      return null;
  }
}

// Export all lesson components
export {
  WelcomeLesson,
  LinuxBasicsLesson,
  SSHBasicsLesson,
  TmuxBasicsLesson,
  GitBasicsLesson,
  GithubCliLesson,
  AgentsLoginLesson,
  NtmCoreLesson,
  NtmPaletteLesson,
  FlywheelLoopLesson,
  KeepingUpdatedLesson,
  UbsLesson,
  AgentMailLesson,
  CassLesson,
  CmLesson,
  BeadsLesson,
  SafetyToolsLesson,
  DcgLesson,
  PromptEngineeringLesson,
  RealWorldCaseStudyLesson,
  SlbCaseStudyLesson,
  RuLesson,
  MsLesson,
  AprLesson,
  JfpLesson,
  PtLesson,
  XfLesson,
  SrpsLesson,
  RchLesson,
  WaLesson,
  BrennerLesson,
  GiilLesson,
  S2pLesson,
  FsfsLesson,
  SbhLesson,
  CasrLesson,
  DsrLesson,
  AsbLesson,
  PcrLesson,
  CsctfLesson,
  TruLesson,
  MdwbLesson,
  RanoLesson,
  CautLesson,
  AadcLesson,
  RustProxyLesson,
  BvLesson,
  CaamLesson,
  SwarmCoordinationLesson,
  DebuggingAgentsLesson,
  ContextMasteryLesson,
  CiCdLesson,
  ProjectBootstrapLesson,
  AstGrepLesson,
  AgentsMdLesson,
  ModernCliLesson,
  TailscaleLesson,
  LangRuntimesLesson,
  CloudInfraLesson,
  SecurityLayersLesson,
  AcfsDoctorLesson,
  EeLesson,
  FmdLesson,
  PiLesson,
  PfrLesson,
};
