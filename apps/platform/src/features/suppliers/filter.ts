import type { PublicSupplier } from "@/lib/domain";

export function filterSuppliers(list: PublicSupplier[], f: { q?: string; category?: string; label?: string }) {
  const q = (f.q ?? "").trim().toLowerCase();
  return list.filter((s) => {
    if (f.category && !s.categorySlugs.includes(f.category)) return false;
    if (f.label && s.label !== f.label) return false;
    if (q && !(s.name.toLowerCase().includes(q) || s.products.some((p) => p.name.toLowerCase().includes(q)))) return false;
    return true;
  });
}
