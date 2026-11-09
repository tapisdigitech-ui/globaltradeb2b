import Link from "next/link";

export function SiteFooter() {
  return (
    <footer className="mt-12 border-t border-line bg-surface">
      <div className="container-page flex flex-col gap-2 py-6 text-sm text-muted sm:flex-row sm:justify-between">
        <p>GlobalTradeB2B &middot; prototype foundation &middot; synthetic data only.</p>
        <ul className="flex flex-wrap gap-4">
          <li><Link href="/suppliers">Supplier directory</Link></li>
          <li><Link href="/requirements/new">Post a requirement</Link></li>
          <li><Link href="/register/supplier">List your company</Link></li>
        </ul>
      </div>
    </footer>
  );
}
