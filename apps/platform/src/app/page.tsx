import Link from "next/link";
import { CATEGORIES, SUPPLIERS } from "@/data/demo";
import { SupplierCard } from "@/features/suppliers/SupplierCard";
import { ButtonLink } from "@/components/ui/Button";
import { Card } from "@/components/ui/States";
import { DemoBadge } from "@/components/ui/Badge";

export default function HomePage() {
  const featured = SUPPLIERS.slice(0, 3);
  return (
    <>
      <section className="bg-navy-900 text-white">
        <div className="container-page grid gap-6 py-10 md:grid-cols-[3fr_2fr] md:items-center md:py-14">
          <div>
            <h1 className="text-white">Find verified suppliers. Post what you need.</h1>
            <p className="mt-3 max-w-prose text-navy-100">
              A directory-first B2B marketplace. Every supplier shows its real verification status, and a requirement is passed on only to suppliers that have been verified.
            </p>
            <div className="mt-6 flex flex-wrap gap-3">
              <ButtonLink href="/suppliers">Browse suppliers</ButtonLink>
              <ButtonLink href="/requirements/new" variant="secondary" className="border-white">Post a requirement</ButtonLink>
            </div>
          </div>
          <Card className="text-ink">
            <h2 className="text-lg">How status labels work</h2>
            <ul className="mt-2 space-y-1 text-sm">
              <li><strong>Verified</strong>: reviewed by our team.</li>
              <li><strong>Pending / Claimed</strong>: not verified yet.</li>
              <li><strong>Unclaimed</strong>: listed from public sources; nobody has confirmed it.</li>
            </ul>
          </Card>
        </div>
      </section>

      <section className="container-page py-8" aria-labelledby="cats">
        <h2 id="cats">Browse by category</h2>
        <ul className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-4">
          {CATEGORIES.map((c) => (
            <li key={c.slug}>
              <Link href={`/suppliers?category=${c.slug}`} className="block rounded-md border border-line bg-surface px-3 py-3 text-sm font-semibold no-underline hover:border-navy-700">{c.name}</Link>
            </li>
          ))}
        </ul>
      </section>

      <section className="container-page py-4" aria-labelledby="feat">
        <div className="flex flex-wrap items-center gap-2"><h2 id="feat">Sample suppliers</h2><DemoBadge /></div>
        <ul className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {featured.map((s) => <li key={s.id}><SupplierCard supplier={s} /></li>)}
        </ul>
      </section>

      <section className="container-page py-8" aria-labelledby="how">
        <h2 id="how">How it works</h2>
        <ol className="mt-4 grid gap-4 md:grid-cols-3">
          {[
            ["1. Post a requirement", "Describe what you need. Your contact details stay private."],
            ["2. We check eligibility", "Only verified suppliers can receive a requirement directly. Our team handles the rest."],
            ["3. Suppliers respond", "A supplier sees your requirement in their account and may respond. You are told only what is confirmed."],
          ].map(([t, b]) => (
            <li key={t}><Card className="h-full"><h3>{t}</h3><p className="mt-1 text-sm text-muted">{b}</p></Card></li>
          ))}
        </ol>
      </section>
    </>
  );
}
