import "server-only";
import type { CaseId, ClaimId, CompanyId, UserId } from "@/contracts/ids";

export const PERMISSIONS = [
  // public
  "supplier:read-public",
  // buyer (own data only)
  "requirement:create", "requirement:read-own",
  // company members
  "company:read-private", "company:edit-profile", "catalogue:edit",
  "claim:submit", "claim:read-own",
  "lead:read-delivered", "lead:respond", "lead:reveal-buyer-contact",
  // staff (assignment-scoped for reviewers)
  "staff:lead:list-assigned", "staff:lead:read", "staff:lead:update", "staff:contact:open-supplier", "staff:contact:open-buyer",
  "staff:claim:review", "staff:evidence:request-link",
  // administrators
  "admin:lead:overview", "admin:lead:assign", "admin:claim:assign-reviewer", "admin:verification:set", "admin:directory:publish", "admin:routing:settings",
] as const;
export type Permission = (typeof PERMISSIONS)[number];

/** The thing being accessed, described by facts the SERVER loaded from the database (never client input). */
export type Resource =
  | { readonly type: "none" }
  | { readonly type: "company"; readonly companyId: CompanyId }
  | { readonly type: "requirement"; readonly buyerId: UserId }
  | { readonly type: "claim"; readonly claimId: ClaimId; readonly claimantId: UserId; readonly companyId: CompanyId }
  | {
      readonly type: "lead";
      readonly companyId: CompanyId;
      /** server fact: routed directly to this company by the matcher (verified-only routing) */
      readonly deliveredDirectly: boolean;
      /** server fact: company is verified and still eligible now */
      readonly companyVerified: boolean;
      /** server fact: this company already responded (precondition for contact reveal) */
      readonly responded: boolean;
    }
  | { readonly type: "lead-case"; readonly caseId: CaseId; readonly companyId?: CompanyId }
  | { readonly type: "enquiry-contact"; readonly caseId: CaseId };

export type AccessContext = {
  /** Mandatory, free-text reason for permissions that reveal private data; >= 5 chars. */
  readonly purpose?: string;
};

export type DenyCode =
  | "auth_unavailable" // auth not connected / down: fail closed
  | "unauthenticated" // anonymous caller needs to sign in
  | "forbidden" // authenticated but not allowed (includes cross-tenant)
  | "purpose_required" // staff reveal without a valid purpose
  | "precondition_failed"; // e.g. lead not delivered directly / not verified / not responded

export type Decision = { readonly allow: true } | { readonly allow: false; readonly code: DenyCode };
