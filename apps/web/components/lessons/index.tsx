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
};
