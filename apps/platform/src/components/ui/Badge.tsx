import type { ReactNode } from "react";
import { cn } from "@/lib/cn";
import type { BadgeTone } from "@/lib/labels";

const tones: Record<BadgeTone, string> = {
  success: "bg-success-100 text-success-700",
  warning: "bg-warning-100 text-warning-800",
  neutral: "bg-navy-100 text-navy-900",
  info: "bg-info-100 text-info-700",
  sample: "border border-dashed border-accent-700 bg-surface text-accent-700 italic",
};

export function Badge({ tone = "neutral", children, className }: { tone?: BadgeTone; children: ReactNode; className?: string }) {
  return <span className={cn("inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold whitespace-normal", tones[tone], className)}>{children}</span>;
}

/** Marks synthetic content. Present on every demo card/page. */
export function DemoBadge({ className }: { className?: string }) {
  return <span data-demo-badge className={cn("inline-flex items-center rounded-sm border border-dashed border-accent-700 bg-accent-100 px-1.5 py-0.5 text-xs font-bold tracking-wide text-accent-700 uppercase", className)}>Demo data</span>;
}
