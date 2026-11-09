import "server-only";
import type { PublicSupplierProfile } from "@/contracts/public-supplier";
import type { BusinessClaim, CompanyState } from "@/contracts/claims";
import type { BuyerPrivateContact, EvidenceLink, SupplierPrivateContact } from "@/contracts/private";
import type { BuyerRequirement, LeadAssignment, LeadCaseSummary, RequirementInput, SellerLeadView } from "@/contracts/requirements";
import type { StaffAction } from "@/contracts/staff-actions";
import type { CaseId, ClaimId, CompanyId, EnquiryId, UserId } from "@/contracts/ids";
import type { LeadStatus } from "@/contracts/enums";

/**
 * DATA-ACCESS INTERFACES. A future Supabase implementation will call PostgREST views/RPCs with the USER's JWT (never the
 * service-role key). Today the only implementation performs no I/O. Every method that is not public takes the verified
 * `userId` explicitly so that a repository can never be called "as nobody".
 */
export interface SupplierRepository {
  /** Anonymous-safe. Backend: GET public_companies (+ public_company_categories). Returns the strict public DTO only. */
  listPublic(query: { q?: string; categoryId?: number; label?: string }): Promise<readonly PublicSupplierProfile[]>;
  getPublicBySlug(slug: string): Promise<PublicSupplierProfile | null>;
  /** Members only. Backend: companies + company_private under RLS. */
  getOwnCompanyState(userId: UserId, companyId: CompanyId): Promise<CompanyState | null>;
  /** Staff only, purpose-logged. Backend: rpc staff_get_contacts. */
  openSupplierContacts(userId: UserId, input: { companyId: CompanyId; caseId: CaseId | null; claimId: ClaimId | null; purpose: string }): Promise<readonly SupplierPrivateContact[]>;
}

export interface ClaimRepository {
  /** Backend: rpc create_company_request / submit_claim. */
  submitClaim(userId: UserId, input: { companyId: CompanyId; title: string; statement: string }): Promise<BusinessClaim>;
  /** Null when the claim is not visible to this user (not theirs / not assigned). Backend: claims_read policy. */
  getClaimFacts(userId: UserId, claimId: ClaimId): Promise<{ claimantId: UserId; companyId: CompanyId } | null>;
  listOwnClaims(userId: UserId): Promise<readonly BusinessClaim[]>;
  /** Assigned reviewer or admin. Backend: rpc review_claim. */
  reviewClaim(userId: UserId, input: { claimId: ClaimId; decision: "approved" | "rejected" | "evidence_requested"; reason: string }): Promise<void>;
  /** Backend: Edge function evidence-link. Links are short-lived and are never stored. */
  requestEvidenceLinks(userId: UserId, input: { claimId: ClaimId; evidenceIds: readonly string[]; purpose: string; ttlSeconds?: number }): Promise<readonly EvidenceLink[]>;
}

export interface RequirementRepository {
  /** Backend: rpc submit_enquiry(kind=requirement) then create_requirement. Contact details are passed once and never returned. */
  create(userId: UserId, input: RequirementInput, contact: { name: string; phone: string; email?: string }): Promise<BuyerRequirement>;
  listOwn(userId: UserId): Promise<readonly BuyerRequirement[]>;
}

export interface LeadRepository {
  /** Verified seller. Backend: enquiries/requirement_details/requirement_matches via a view WITHOUT buyer_id (F-I). */
  /**
   * Facts the policy needs, loaded by the SERVER for this exact (user, enquiry, company). Must return null when the lead is
   * not visible to that company (cross-tenant ids look identical to non-existent ones). Backend: seller_match_visible() + lead_responses.
   */
  getLeadAccessFacts(userId: UserId, enquiryId: EnquiryId, companyId: CompanyId): Promise<{ deliveredDirectly: boolean; companyVerified: boolean; responded: boolean } | null>;
  listDeliveredToCompany(userId: UserId, companyId: CompanyId): Promise<readonly SellerLeadView[]>;
  respond(userId: UserId, input: { enquiryId: EnquiryId; companyId: CompanyId }): Promise<void>;
  /** Backend: rpc reveal_buyer_contact (logged, rate limited). Result must be rendered transiently. */
  revealBuyerContact(userId: UserId, input: { enquiryId: EnquiryId; companyId: CompanyId }): Promise<BuyerPrivateContact>;
  /** Staff. Backend: rpc staff_my_leads (assigned) or admin_lead_overview. */
  listCases(userId: UserId, scope: "assigned" | "all"): Promise<readonly LeadCaseSummary[]>;
  updateCase(userId: UserId, input: { caseId: CaseId; toStatus: LeadStatus; note: string | null }): Promise<void>;
  assignCase(userId: UserId, input: { caseId: CaseId; assigneeId: UserId }): Promise<LeadAssignment>;
  openBuyerContact(userId: UserId, input: { enquiryId: EnquiryId; caseId: CaseId; purpose: string }): Promise<BuyerPrivateContact>;
}

export interface StaffActionRepository {
  /** The database writes the authoritative audit row inside each RPC; this reads them for the desk. */
  listRecent(userId: UserId, limit: number): Promise<readonly StaffAction[]>;
}

export interface DataAccess {
  readonly suppliers: SupplierRepository;
  readonly claims: ClaimRepository;
  readonly requirements: RequirementRepository;
  readonly leads: LeadRepository;
  readonly staffActions: StaffActionRepository;
}
