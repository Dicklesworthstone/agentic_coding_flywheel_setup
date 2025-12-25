"use client";

import { WelcomeLesson } from "./welcome-lesson";
import { LinuxBasicsLesson } from "./linux-basics-lesson";
import { SSHBasicsLesson } from "./ssh-basics-lesson";
import { TmuxBasicsLesson } from "./tmux-basics-lesson";
import { AgentsLoginLesson } from "./agents-login-lesson";
import { NtmCoreLesson } from "./ntm-core-lesson";
import { NtmPaletteLesson } from "./ntm-palette-lesson";
import { FlywheelLoopLesson } from "./flywheel-loop-lesson";
import { KeepingUpdatedLesson } from "./keeping-updated-lesson";

// Map lesson slugs to their custom components
export const LESSON_COMPONENTS: Record<string, React.ComponentType> = {
  welcome: WelcomeLesson,
  "linux-basics": LinuxBasicsLesson,
  "ssh-basics": SSHBasicsLesson,
  "tmux-basics": TmuxBasicsLesson,
  "agent-commands": AgentsLoginLesson,
  "ntm-core": NtmCoreLesson,
  "ntm-palette": NtmPaletteLesson,
  "flywheel-loop": FlywheelLoopLesson,
  "keeping-updated": KeepingUpdatedLesson,
};

// Get the component for a given slug
export function getLessonComponent(slug: string): React.ComponentType | null {
  return LESSON_COMPONENTS[slug] ?? null;
}

// Export all lesson components
export {
  WelcomeLesson,
  LinuxBasicsLesson,
  SSHBasicsLesson,
  TmuxBasicsLesson,
  AgentsLoginLesson,
  NtmCoreLesson,
  NtmPaletteLesson,
  FlywheelLoopLesson,
  KeepingUpdatedLesson,
};
