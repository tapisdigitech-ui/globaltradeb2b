import type { Metadata } from "next";
import { SUPPLIERS } from "@/data/demo";
import { DirectoryFilters } from "@/features/suppliers/DirectoryFilters";
import { SupplierCard } from "@/features/suppliers/SupplierCard";
import { filterSuppliers } from "@/features/suppliers/filter";
import { EmptyState, PageHeader } from "@/components/ui/States";
import { ButtonLink } from "@/components/ui/Button";
import { DemoBadge } from "@/components/ui/Badge";

export const metadata: Metadata = { title: "Supplier directory" };
type SP = Promise<Record<string, string | string[] | undefined>>;
const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? "";

export default async function SuppliersPage({ searchParams }: { searchParams: SP }) {
  const sp = await searchParams;
  const q = one(sp.q).slice(0, 80), category = one(sp.category), label = one(sp.label);
  const results = filterSuppliers(SUPPLIERS, { q, category, label });
  return (
    <div className="container-page pb-8">
      <PageHeader title="Supplier directory" lead="Public profiles only. Phone numbers and email addresses are never shown here." actions={<DemoBadge />} />
      <DirectoryFilters q={q} category={category} label={label} />
      <p className="mt-4 text-sm text-muted" role="status" aria-live="polite">{results.length} of {SUPPLIERS.length} sample suppliers shown</p>
      {results.length === 0 ? (
        <div className="mt-4"><EmptyState title="No suppliers match" action={<ButtonLink href="/suppliers" variant="secondary">Clear filters</ButtonLink>}>Try a different search or remove a filter.</EmptyState></div>
      ) : (
        <ul className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {results.map((s) => <li key={s.id}><SupplierCard supplier={s} /></li>)}
        </ul>
      )}
    </div>
  );
}
