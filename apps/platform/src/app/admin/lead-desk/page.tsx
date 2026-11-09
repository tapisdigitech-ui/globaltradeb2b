import type { Metadata } from "next";
import { PreviewShell } from "@/components/layout/PreviewShell";
import { Alert } from "@/components/ui/States";
import { DataTable, Td, Th } from "@/components/ui/Table";
import { DEMO_LEADS } from "@/data/demo";
import { DELIVERY_COPY } from "@/lib/labels";

export const metadata: Metadata = { title: "Admin Lead Desk (preview shell)" };

export default function LeadDeskPage() {
  return (
    <PreviewShell role="admin" title="Admin Lead Desk" lead="Layout of the internal desk that handles requirements. All rows are synthetic."
      nav={[{ label: "Overview", current: true }, { label: "Unassigned" }, { label: "My cases" }, { label: "Claims" }, { label: "Settings" }]}>
      <Alert tone="info" title="Privacy by design">Buyer and supplier contact details are never listed here. Staff open them one case at a time, with a stated purpose, and each access is logged.</Alert>
      <DataTable caption="Requirements (synthetic)">
        <thead><tr><Th>Reference</Th><Th>Product</Th><Th>Quantity</Th><Th>Destination</Th><Th>Matched verified suppliers</Th><Th>Status</Th></tr></thead>
        <tbody>
          {DEMO_LEADS.map((l) => (
            <tr key={l.ref}><Td className="font-mono text-xs">{l.ref}</Td><Td>{l.product}</Td><Td>{l.qty}</Td><Td>{l.destination}</Td><Td>{l.matched}</Td><Td>{DELIVERY_COPY[l.state].title}</Td></tr>
          ))}
        </tbody>
      </DataTable>
      <p className="text-sm text-muted">&ldquo;Visible to the supplier&rdquo; means the lead shows in an eligible supplier&rsquo;s account. It does not mean the supplier has read or answered it.</p>
    </PreviewShell>
  );
}
