/**
 * Domain types for the frontend foundation.
 * Mirrors the read contract in docs/FRONTEND_BACKEND_INTEGRATION_CONTRACT.md (§5).
 * Deliberately has NO phone / email / street-address fields on public types:
 * a public page cannot render what its data type does not contain.
 */

/** Server-provided public labels (public_companies.public_label). The client never computes its own badge. */
export const VERIFICATION_LABELS = [
  "Verified",
  "Verification Pending",
  "Claimed — Not Verified",
  "Claim Requested",
  "Unclaimed — Not Verified",
] as const;
export type VerificationLabel = (typeof VERIFICATION_LABELS)[number];

export type Category = { slug: string; name: string };

export type PublicProduct = {
  id: string;
  name: string;
  summary: string;
  moq: string;
  isDemo: boolean;
};

export type PublicSupplier = {
  id: string;
  slug: string;
  name: string;
  businessType: "Manufacturer" | "Exporter" | "Trader" | "Service provider";
  about: string;
  city: string;
  state: string;
  country: string;
  categorySlugs: string[];
  label: VerificationLabel;
  isClaimed: boolean;
  isVerified: boolean;
  dataAsOf: string;
  /** True for every synthetic record. Real records must never set this. */
  isDemo: boolean;
  products: PublicProduct[];
};

/** Roles known to the UI. "seller" is derived from company membership on the server; the others are profiles.app_role. */
export const ROLES = ["anonymous", "buyer", "seller", "reviewer", "admin"] as const;
export type Role = (typeof ROLES)[number];

/** submit_enquiry().delivery values (contract §4). */
export const DELIVERY_STATES = ["stored", "awaiting_admin", "visible_to_seller"] as const;
export type DeliveryState = (typeof DELIVERY_STATES)[number];
