import type { ReactNode } from "react";
import { cn } from "@/lib/cn";

/** Responsive data table: horizontal scroll inside a labelled region, never page overflow. */
export function DataTable({ caption, children, className }: { caption: string; children: ReactNode; className?: string }) {
  return (
    <div role="region" aria-label={caption} tabIndex={0} className={cn("overflow-x-auto rounded-md border border-line bg-surface", className)}>
      <table className="w-full min-w-[32rem] border-collapse text-left text-sm">
        <caption className="sr-only">{caption}</caption>
        {children}
      </table>
    </div>
  );
}
export const Th = ({ children }: { children: ReactNode }) => (
  <th scope="col" className="border-b border-line bg-navy-50 px-3 py-2 text-xs font-bold tracking-wide text-navy-900 uppercase">{children}</th>
);
export const Td = ({ children, className }: { children: ReactNode; className?: string }) => (
  <td className={cn("border-b border-line px-3 py-2 align-top", className)}>{children}</td>
);
