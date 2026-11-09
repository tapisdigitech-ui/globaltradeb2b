import { z } from "zod";
import { PUBLIC_LABELS, type PublicLabel } from "./enums";

/**
 * PUBLIC supplier contract. Mirrors the columns of the `public_companies` view (contract §5) and nothing else.
 * It has NO phone, email, street address, WhatsApp, contact person, registration number or internal status field.
 * `.strict()` makes parsing FAIL if a source row carries any extra key, so a future view change that leaks a private
 * column is caught at the boundary instead of rendered.
 */
export const publicSupplierSchema = z.strictObject({
  id: z.string().uuid(),
  slug: z.string().min(1).max(120),
  name: z.string().min(1).max(200),
  businessType: z.string().min(1).max(60).nullable(),
  about: z.string().max(4000).nullable(),
  city: z.string().max(80).nullable(),
  state: z.string().max(80).nullable(),
  country: z.string().max(80).nullable(),
  /** Public website of the company, if the company publishes one. Not a contact detail of a person. */
  website: z.url({ protocol: /^https?$/ }).nullable(),
  logoPath: z.string().max(300).nullable(),
  publicLabel: z.enum(PUBLIC_LABELS),
  isClaimed: z.boolean(),
  isVerified: z.boolean(),
  dataAsOf: z.string().nullable(),
  updatedAt: z.string(),
});
export type PublicSupplierProfile = z.infer<typeof publicSupplierSchema>;

/** Shape of a row returned by `select * from public_companies` (snake_case). */
export type PublicCompaniesRow = {
  id: string; slug: string; name: string; business_type: string | null; about: string | null;
  city: string | null; state: string | null; country: string | null; website: string | null; logo_path: string | null;
  public_label: PublicLabel; is_claimed: boolean; is_verified: boolean; data_as_of: string | null; updated_at: string;
};

/**
 * Allow-list mapper. It copies named fields only (never spreads), then validates with the strict schema.
 * Consistency rules enforced here, not left to the view alone:
 *  - "Verified" label requires isVerified; isVerified requires isClaimed.
 */
export function toPublicSupplier(row: PublicCompaniesRow): PublicSupplierProfile {
  const dto = publicSupplierSchema.parse({
    id: row.id, slug: row.slug, name: row.name, businessType: row.business_type, about: row.about,
    city: row.city, state: row.state, country: row.country, website: row.website, logoPath: row.logo_path,
    publicLabel: row.public_label, isClaimed: row.is_claimed, isVerified: row.is_verified,
    dataAsOf: row.data_as_of, updatedAt: row.updated_at,
  });
  if ((dto.publicLabel === "Verified") !== dto.isVerified) throw new TypeError("inconsistent verification label");
  if (dto.isVerified && !dto.isClaimed) throw new TypeError("verified supplier must be claimed");
  return dto;
}

/** Fields that must never appear in any public DTO, used by tests and by a runtime tripwire. */
export const FORBIDDEN_PUBLIC_KEYS = [
  "phone", "mobile", "email", "whatsapp", "contact", "contactName", "contactPhone", "contactEmail", "address",
  "street", "pincode", "gst", "gstin", "pan", "registrationNumber", "buyerId", "userId", "claimantId", "evidence", "storagePath",
] as const;

export function assertNoForbiddenKeys(value: unknown, path = "$"): void {
  if (Array.isArray(value)) { value.forEach((v, i) => assertNoForbiddenKeys(v, `${path}[${i}]`)); return; }
  if (value && typeof value === "object") {
    for (const [k, v] of Object.entries(value)) {
      if ((FORBIDDEN_PUBLIC_KEYS as readonly string[]).some((f) => f.toLowerCase() === k.toLowerCase())) throw new TypeError(`forbidden public key ${path}.${k}`);
      assertNoForbiddenKeys(v, `${path}.${k}`);
    }
  }
}
