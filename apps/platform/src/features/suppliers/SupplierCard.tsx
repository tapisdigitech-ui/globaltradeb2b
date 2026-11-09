import Link from "next/link";
import type { PublicSupplier } from "@/lib/domain";
import { supplierBadge } from "@/lib/labels";
import { Badge, DemoBadge } from "@/components/ui/Badge";
import { Card } from "@/components/ui/States";
import { categoryName } from "@/data/demo";

export function SupplierCard({ supplier: s }: { supplier: PublicSupplier }) {
  const badge = supplierBadge(s);
  return (
    <Card as="article" className="flex h-full flex-col gap-2">
      <div className="flex flex-wrap items-center gap-2">
        <Badge tone={badge.tone}>{badge.text}</Badge>
        {s.isDemo ? <DemoBadge /> : null}
      </div>
      <h3><Link href={`/suppliers/${s.slug}`}>{s.name}</Link></h3>
      <p className="text-sm text-muted">{s.businessType} &middot; {s.city}, {s.country}</p>
      <p className="line-clamp-3 text-sm">{s.about}</p>
      <ul className="mt-auto flex flex-wrap gap-1 pt-2" aria-label="Categories">
        {s.categorySlugs.map((c) => (
          <li key={c} className="rounded-sm bg-navy-50 px-2 py-0.5 text-xs text-navy-900">{categoryName(c)}</li>
        ))}
      </ul>
    </Card>
  );
}
