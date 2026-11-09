/**
 * Enumerations copied from the SQL enums in supabase/migrations/20261107120000_baseline_reconstructed.sql and
 * 20261107120200_requirements_matching_lead_desk.sql. If a migration changes an enum, `tests/contracts/enum-drift.test.ts`
 * fails until this file is updated deliberately.
 */
export const APP_ROLES = ["buyer", "seller", "reviewer", "admin"] as const;
export type AppRole = (typeof APP_ROLES)[number];

export const MEMBER_ROLES = ["owner", "manager", "sales", "catalogue_editor", "viewer"] as const;
export type MemberRole = (typeof MEMBER_ROLES)[number];

export const MEMBER_STATUSES = ["invited", "active", "removed"] as const;
export type MemberStatus = (typeof MEMBER_STATUSES)[number];

export const CLAIM_STATUSES = ["unclaimed", "claim_submitted", "evidence_requested", "under_review", "approved", "rejected", "withdrawn"] as const;
export type ClaimStatus = (typeof CLAIM_STATUSES)[number];

export const VERIFICATION_STATUSES = ["not_verified", "pending", "verified", "rejected", "expired"] as const;
export type VerificationStatus = (typeof VERIFICATION_STATUSES)[number];

export const DIRECTORY_STATUSES = ["draft", "pending_review", "published", "paused", "rejected", "suspended"] as const;
export type DirectoryStatus = (typeof DIRECTORY_STATUSES)[number];

export const ENQUIRY_KINDS = ["product", "requirement"] as const;
export type EnquiryKind = (typeof ENQUIRY_KINDS)[number];

export const ENQUIRY_DELIVERIES = ["stored", "awaiting_admin", "visible_to_seller", "sent_external", "failed"] as const;
export type EnquiryDelivery = (typeof ENQUIRY_DELIVERIES)[number];

export const LEAD_STATUSES = [
  "new", "assigned", "contact_pending", "contacted", "interested", "not_interested", "claim_invitation_sent",
  "registration_started", "verification_pending", "seller_activated", "follow_up_required", "no_suitable_supplier", "closed",
] as const;
export type LeadStatus = (typeof LEAD_STATUSES)[number];

export const LEAD_QUEUES = ["unclaimed_matches", "unverified_matches", "capped_eligible", "unmatched"] as const;
export type LeadQueue = (typeof LEAD_QUEUES)[number];

export const MATCH_ROUTES = ["direct", "admin"] as const;
export type MatchRoute = (typeof MATCH_ROUTES)[number];

/** Public labels produced only by the public_companies view (contract §4/§5). */
export const PUBLIC_LABELS = ["Verified", "Verification Pending", "Claimed — Not Verified", "Claim Requested", "Unclaimed — Not Verified"] as const;
export type PublicLabel = (typeof PUBLIC_LABELS)[number];
