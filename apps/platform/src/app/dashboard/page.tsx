import type { Metadata } from "next";
import { PreviewShell } from "@/components/layout/PreviewShell";
import { Card, EmptyState } from "@/components/ui/States";
import { Badge } from "@/components/ui/Badge";
import { DataTable, Td, Th } from "@/components/ui/Table";
import { ButtonLink } from "@/components/ui/Button";
import { SUPPLIERS } from "@/data/demo";
import { supplierBadge } from "@/lib/labels";

export const metadata: Metadata = { title: "Supplier dashboard (preview shell)" };

export default function DashboardPage() {
  const s = SUPPLIERS[2]!; // claimed, NOT verified: shows why leads are withheld
  const b = supplierBadge(s);
  return (
    <PreviewShell role="seller" title="Supplier dashboard" lead="Layout of the area a supplier will use. All content is synthetic."
      nav={[{ label: "Overview", current: true }, { label: "Company profile" }, { label: "Products" }, { label: "Leads" }, { label: "Verification" }]}>
      <Card as="section">
        <h2 className="text-lg">Company status</h2>
        <p className="mt-1">{s.name}</p>
        <div className="mt-2 flex flex-wrap items-center gap-2"><Badge tone={b.tone}>{b.text}</Badge></div>
        <p className="mt-2 text-sm text-muted">Leads are delivered only to verified companies. This company is not verified, so it would not receive leads directly.</p>
        <div className="mt-3"><ButtonLink href="/register/supplier" variant="secondary">Start verification</ButtonLink></div>
      </Card>
      <section aria-labelledby="ld"><h2 id="ld" className="text-lg">Leads visible to your company</h2>
        <div className="mt-2"><EmptyState title="No leads yet">Leads appear here only when the server shows them as visible to your verified company. Nothing here means nothing has been delivered.</EmptyState></div>
      </section>
      <section aria-labelledby="pr"><h2 id="pr" className="text-lg">Products</h2>
        <div className="mt-2"><DataTable caption="Your products (synthetic)">
          <thead><tr><Th>Product</Th><Th>Review status</Th><Th>Minimum order</Th></tr></thead>
          <tbody>{s.products.map((p) => <tr key={p.id}><Td>{p.name}</Td><Td>Pending review (sample)</Td><Td>{p.moq}</Td></tr>)}</tbody>
        </DataTable></div>
      </section>
    </PreviewShell>
  );
}
