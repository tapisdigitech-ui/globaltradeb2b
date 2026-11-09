import type { ReactNode } from "react";
import { cn } from "@/lib/cn";

export function EmptyState({ title, children, action }: { title: string; children?: ReactNode; action?: ReactNode }) {
  return (
    <div role="status" className="rounded-lg border border-dashed border-line bg-surface px-4 py-10 text-center">
      <h2 className="text-lg">{title}</h2>
      {children ? <p className="mx-auto mt-2 max-w-prose text-muted">{children}</p> : null}
      {action ? <div className="mt-4 flex justify-center">{action}</div> : null}
    </div>
  );
}

export function LoadingState({ label = "Loading" }: { label?: string }) {
  return (
    <div role="status" aria-live="polite" aria-busy="true" className="space-y-3">
      <span className="sr-only">{label}…</span>
      {[0, 1, 2].map((i) => (
        <div key={i} aria-hidden="true" className="h-16 animate-pulse rounded-md bg-navy-100" />
      ))}
    </div>
  );
}

type Tone = "info" | "success" | "warning" | "danger";
const tones: Record<Tone, string> = {
  info: "border-info-700 bg-info-100 text-navy-950",
  success: "border-success-700 bg-success-100 text-navy-950",
  warning: "border-warning-800 bg-warning-100 text-navy-950",
  danger: "border-danger-700 bg-danger-100 text-navy-950",
};
export function Alert({ tone = "info", title, children, alert }: { tone?: Tone; title?: string; children: ReactNode; alert?: boolean }) {
  return (
    <div role={alert ? "alert" : "status"} className={cn("rounded-md border-l-4 px-4 py-3 text-sm", tones[tone])}>
      {title ? <p className="font-bold">{title}</p> : null}
      <div>{children}</div>
    </div>
  );
}

export function Card({ children, className, as: Tag = "div" }: { children: ReactNode; className?: string; as?: "div" | "section" | "article" | "li" }) {
  return <Tag className={cn("rounded-lg border border-line bg-surface p-4 shadow-card", className)}>{children}</Tag>;
}

export function PageHeader({ title, lead, actions }: { title: string; lead?: string; actions?: ReactNode }) {
  return (
    <div className="flex flex-col gap-3 py-6 sm:flex-row sm:items-end sm:justify-between">
      <div className="max-w-prose">
        <h1>{title}</h1>
        {lead ? <p className="mt-1 text-muted">{lead}</p> : null}
      </div>
      {actions ? <div className="flex flex-wrap gap-2">{actions}</div> : null}
    </div>
  );
}
