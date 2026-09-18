import type { ReactNode } from "react";
import { DoctorReportPanel } from "@/components/doctor-report-panel";

export default function StatusCheckLayout({ children }: { children: ReactNode }) {
  return <div className="space-y-8">
    {children}
    <DoctorReportPanel />
  </div>;
}
