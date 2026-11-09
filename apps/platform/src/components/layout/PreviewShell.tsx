import type { ReactNode } from "react";
import type { Role } from "@/lib/domain";
import { ROLE_DESCRIPTION } from "@/lib/roles";
import { Alert } from "@/components/ui/States";
import { DemoBadge } from "@/components/ui/Badge";

/**
 * Wrapper for staff/seller areas. These pages are SHELLS: there is no sign-in, so they are not access-controlled
 * and contain only synthetic data. When a real session exists, the route must be gated on the server
 * (see docs/FRONTEND_BACKEND_INTEGRATION_CONTRACT.md §10) before any real data is bound here.
 */
export function PreviewShell({ role, title, lead, nav, children }: { role: Role; title: string; lead: string; nav: { label: string; current?: boolean }[]; children: ReactNode }) {
  return (
    <div className="container-page py-6">
      <div className="mb-4 flex flex-wrap items-center gap-2">
        <h1>{title}</h1>
        <DemoBadge />
      </div>
      <p className="mb-4 max-w-prose text-muted">{lead}</p>
      <Alert tone="warning" title="Preview shell — access control is not connected">
        There is no sign-in yet, so this page is not protected and shows synthetic data only. In the live service it will require a server-verified session for this role: <strong data-role-label={role}>{ROLE_DESCRIPTION[role]}</strong>
      </Alert>
      <div className="mt-6 grid gap-6 lg:grid-cols-[14rem_minmax(0,1fr)]">
        <nav aria-label={`${title} sections`} className="min-w-0">
          <ul className="flex gap-1 overflow-x-auto lg:flex-col">
            {nav.map((n) => (
              <li key={n.label}>
                <span aria-current={n.current ? "page" : undefined} className={`block rounded-md px-3 py-2 text-sm font-semibold whitespace-nowrap ${n.current ? "bg-navy-900 text-white" : "text-navy-900 bg-navy-50"}`}>
                  {n.label}
                </span>
              </li>
            ))}
          </ul>
          <p className="mt-2 hidden text-xs text-muted lg:block">Sections are placeholders; they link nowhere until the backend is wired.</p>
        </nav>
        <div className="min-w-0 space-y-6">{children}</div>
      </div>
    </div>
  );
}
