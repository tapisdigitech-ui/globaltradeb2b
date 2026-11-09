import type { Category, PublicSupplier } from "@/lib/domain";

/**
 * SYNTHETIC DEMONSTRATION DATA. Every company, product and place below is invented.
 * No record is registered, claimed or verified by this platform. There are deliberately
 * no phone numbers, email addresses or street addresses in this file.
 */
export const DEMO_AS_OF = "2026-11-09";

export const CATEGORIES: Category[] = [
  { slug: "industrial-plants-machinery", name: "Industrial Plants & Machinery" },
  { slug: "architecture-interiors", name: "Architecture & Interiors" },
  { slug: "consumer-electronics", name: "Consumer Electronics" },
  { slug: "carpets-rugs-home-furnishing", name: "Carpets, Rugs & Home Furnishing" },
  { slug: "textiles-garments", name: "Textiles & Garments" },
  { slug: "food-agro-products", name: "Food & Agro Products" },
  { slug: "building-construction", name: "Building & Construction" },
  { slug: "packaging-printing", name: "Packaging & Printing" },
  { slug: "medical-healthcare", name: "Medical & Healthcare" },
  { slug: "automotive-spare-parts", name: "Automotive & Spare Parts" },
  { slug: "handicrafts-gifts", name: "Handicrafts & Gifts" },
  { slug: "renewable-energy", name: "Renewable Energy" },
  { slug: "chemicals-dyes", name: "Chemicals & Dyes" },
  { slug: "safety-security", name: "Safety & Security" },
];

const p = (id: string, name: string, summary: string, moq: string) => ({ id, name, summary, moq, isDemo: true });

export const SUPPLIERS: PublicSupplier[] = [
  {
    id: "demo-1", slug: "sample-loom-works", name: "Sample Loom Works", businessType: "Manufacturer",
    about: "Invented example of a hand-knotted rug manufacturer. Used only to show how a profile page is laid out. Someone has asked to claim this profile; nothing is confirmed.",
    city: "Sampletown", state: "Demo State", country: "India", categorySlugs: ["carpets-rugs-home-furnishing", "handicrafts-gifts"],
    label: "Claim Requested", isClaimed: false, isVerified: false, dataAsOf: DEMO_AS_OF, isDemo: true,
    products: [p("demo-1-a", "Sample hand-knotted rug", "Illustrative product entry.", "50 pieces"), p("demo-1-b", "Sample flatweave runner", "Illustrative product entry.", "100 pieces")],
  },
  {
    id: "demo-2", slug: "example-textile-mills", name: "Example Textile Mills", businessType: "Manufacturer",
    about: "Invented example of a cotton fabric mill. Claim submitted but review not finished.",
    city: "Exampleville", state: "Demo State", country: "India", categorySlugs: ["textiles-garments"],
    label: "Verification Pending", isClaimed: true, isVerified: false, dataAsOf: DEMO_AS_OF, isDemo: true,
    products: [p("demo-2-a", "Sample cotton fabric", "Illustrative product entry.", "500 metres")],
  },
  {
    id: "demo-3", slug: "placeholder-pack-industries", name: "Placeholder Pack Industries", businessType: "Manufacturer",
    about: "Invented example of a packaging company that has claimed its profile but is not verified.",
    city: "Mockpur", state: "Demo State", country: "India", categorySlugs: ["packaging-printing"],
    label: "Claimed — Not Verified", isClaimed: true, isVerified: false, dataAsOf: DEMO_AS_OF, isDemo: true,
    products: [p("demo-3-a", "Sample corrugated box", "Illustrative product entry.", "1,000 pieces")],
  },
  {
    id: "demo-4", slug: "specimen-agro-exports", name: "Specimen Agro Exports", businessType: "Exporter",
    about: "Invented example of an exporter. Someone has asked to claim this profile; nothing is confirmed.",
    city: "Testgarh", state: "Demo State", country: "India", categorySlugs: ["food-agro-products"],
    label: "Claim Requested", isClaimed: false, isVerified: false, dataAsOf: DEMO_AS_OF, isDemo: true,
    products: [],
  },
  {
    id: "demo-5", slug: "illustrative-steel-fabricators", name: "Illustrative Steel Fabricators", businessType: "Manufacturer",
    about: "Invented example of a listing compiled from public sources. Nobody has claimed it.",
    city: "Fictionnagar", state: "Demo State", country: "India", categorySlugs: ["industrial-plants-machinery", "building-construction"],
    label: "Unclaimed — Not Verified", isClaimed: false, isVerified: false, dataAsOf: DEMO_AS_OF, isDemo: true,
    products: [],
  },
  {
    id: "demo-6", slug: "mock-chem-traders", name: "Mock Chem Traders", businessType: "Trader",
    about: "Invented example of a trader in dyes. Nobody has claimed it.",
    city: "Sampletown", state: "Demo State", country: "India", categorySlugs: ["chemicals-dyes"],
    label: "Unclaimed — Not Verified", isClaimed: false, isVerified: false, dataAsOf: DEMO_AS_OF, isDemo: true,
    products: [],
  },
];

export function getSupplier(slug: string) {
  return SUPPLIERS.find((s) => s.slug === slug);
}
export function categoryName(slug: string) {
  return CATEGORIES.find((c) => c.slug === slug)?.name ?? slug;
}

/** Synthetic Lead Desk rows. "state" is the server delivery value; no row claims delivery. */
export const DEMO_LEADS = [
  { ref: "DEMO-L-001", product: "Sample hand-knotted rug", qty: "200 pieces", destination: "Sample City", state: "awaiting_admin" as const, matched: 3 },
  { ref: "DEMO-L-002", product: "Sample cotton fabric", qty: "2,000 metres", destination: "Example Port", state: "stored" as const, matched: 0 },
  { ref: "DEMO-L-003", product: "Sample corrugated box", qty: "5,000 pieces", destination: "Mockburg", state: "visible_to_seller" as const, matched: 1 },
];
