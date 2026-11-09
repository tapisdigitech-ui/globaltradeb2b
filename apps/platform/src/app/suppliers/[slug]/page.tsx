import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { SUPPLIERS, categoryName, getSupplier } from "@/data/demo";
import { supplierBadge } from "@/lib/labels";
import { Badge, DemoBadge } from "@/components/ui/Badge";
import { Alert, Card, EmptyState } from "@/components/ui/States";
import { ButtonLink } from "@/components/ui/Button";

export const dynamicParams = false;
export function generateStaticParams() { return SUPPLIERS.map((s) => ({ slug: s.slug })); }
type P = Promise<{ slug: string }>;

export async function generateMetadata({ params }: { params: P }): Promise<Metadata> {
  const s = getSupplier((await params).slug);
  return { title: s ? `${s.name} (demo)` : "Supplier" };
}

export default async function SupplierPage({ params }: { params: P }) {
  const s = getSupplier((await params).slug);
  if (!s) notFound();
  const badge = supplierBadge(s);
  return (
    <div className="container-page py-6">
      <nav aria-label="Breadcrumb" className="text-sm"><Link href="/suppliers">&larr; All suppliers</Link></nav>
      <div className="mt-3 flex flex-wrap items-center gap-2">
        <h1>{s.name}</h1><DemoBadge />
      </div>
      <p className="mt-1 text-muted">{s.businessType} &middot; {s.city}, {s.state}, {s.country}</p>
      <div className="mt-3 flex flex-wrap items-center gap-2">
        <Badge tone={badge.tone}>{badge.text}</Badge>
        <span className="text-xs text-muted">Data as of {s.dataAsOf}</span>
      </div>

      <div className="mt-6 grid gap-6 lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)]">
        <div className="space-y-6">
          <Card as="section"><h2>About</h2><p className="mt-2">{s.about}</p>
            <ul className="mt-3 flex flex-wrap gap-1" aria-label="Categories">
              {s.categorySlugs.map((c) => <li key={c} className="rounded-sm bg-navy-50 px-2 py-0.5 text-xs">{categoryName(c)}</li>)}
            </ul>
          </Card>
          <section aria-labelledby="prods">
            <h2 id="prods">Products</h2>
            {s.products.length === 0 ? (
              <div className="mt-3"><EmptyState title="No products listed">This company has not listed products.</EmptyState></div>
            ) : (
              <ul className="mt-3 grid gap-3 sm:grid-cols-2">
                {s.products.map((p) => (
                  <li key={p.id}><Card className="h-full"><div className="flex flex-wrap items-center gap-2"><h3>{p.name}</h3><DemoBadge /></div><p className="mt-1 text-sm text-muted">{p.summary}</p><p className="mt-2 text-sm">Minimum order: {p.moq}</p></Card></li>
                ))}
              </ul>
            )}
          </section>
        </div>

        <aside aria-label="Contact and enquiries" className="space-y-4">
          <Card as="section">
            <h2 className="text-lg">Contact</h2>
            <p className="mt-2 text-sm">Contact details are not shown on public pages. Post a requirement and, where eligible, it is passed on through the platform.</p>
            <div className="mt-3"><ButtonLink href="/requirements/new" className="w-full">Post a requirement</ButtonLink></div>
          </Card>
          {s.isVerified ? (
            <Alert tone="info" title="Verified profile (sample)">In the live service, a requirement can become visible in this supplier&rsquo;s account. We cannot confirm that they have read it.</Alert>
          ) : (
            <Alert tone="warning" title="Not verified">This company is not verified, so requirements are not passed to it directly. They are held by our team.</Alert>
          )}
        </aside>
      </div>
    </div>
  );
}
