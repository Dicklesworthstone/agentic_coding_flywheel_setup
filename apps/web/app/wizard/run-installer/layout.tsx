import type { ReactNode } from "react";
import { TeamProfileImportPanel } from "@/components/team-profile-import-panel";

export default function RunInstallerLayout({ children }: { children: ReactNode }) {
  return <div className="space-y-8">
    {children}
    <TeamProfileImportPanel />
  </div>;
}
