import type { CompanyId, EnquiryId, UserId } from "./ids";

/**
 * PRIVATE contact contracts. These types may be used ONLY on the server (see src/server). They are intentionally not
 * re-exported from any module a client component can import, and every function returning them is audited by the
 * database (purpose / access log). Values must be shown transiently and never cached, logged, put in URLs or stored.
 */
export type SupplierPrivateContact = {
  readonly companyId: CompanyId;
  readonly contactId: string;
  readonly kind: "phone" | "email" | "person";
  readonly value: string;
  /** Why this was opened: required by staff_get_contacts (purpose is mandatory and logged). */
  readonly purpose: string;
};

export type BuyerPrivateContact = {
  readonly enquiryId: EnquiryId;
  readonly buyerName: string;
  readonly buyerPhone: string | null;
  readonly buyerEmail: string | null;
  readonly buyerCompany: string | null;
};

/** Evidence is reached only through short-lived signed links from the evidence-link Edge Function; paths are never exposed. */
export type EvidenceLink = { readonly evidenceId: string; readonly url: string; readonly expiresInSeconds: number };

export type { UserId };
