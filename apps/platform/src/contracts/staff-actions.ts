import type { CaseId, ClaimId, CompanyId, EnquiryId, UserId } from "./ids";
import type { LeadStatus } from "./enums";

/**
 * Staff actions are values that describe an audited operation. Every action that reveals private data carries a
 * mandatory purpose (>= 5 characters, mirroring the Edge Function). Creating the audit row is the database's job;
 * this type is the application-side request.
 */
export const MIN_PURPOSE_LENGTH = 5;

type Base = { readonly actorId: UserId; readonly at: string };
export type StaffAction =
  | (Base & { type: "lead.update"; caseId: CaseId; toStatus: LeadStatus; note: string | null })
  | (Base & { type: "lead.assign"; caseId: CaseId; assigneeId: UserId })
  | (Base & { type: "contact.open_supplier"; companyId: CompanyId; caseId: CaseId | null; claimId: ClaimId | null; purpose: string })
  | (Base & { type: "contact.open_buyer"; enquiryId: EnquiryId; purpose: string })
  | (Base & { type: "evidence.request_link"; claimId: ClaimId; evidenceIds: readonly string[]; purpose: string })
  | (Base & { type: "claim.review"; claimId: ClaimId; decision: "approved" | "rejected" | "evidence_requested"; reason: string })
  | (Base & { type: "verification.set"; companyId: CompanyId; to: "verified" | "rejected" | "pending" | "not_verified" | "expired"; reason: string });

export const ACTIONS_REQUIRING_PURPOSE = ["contact.open_supplier", "contact.open_buyer", "evidence.request_link"] as const;

export function hasValidPurpose(purpose: string | undefined | null): purpose is string {
  return typeof purpose === "string" && purpose.trim().length >= MIN_PURPOSE_LENGTH;
}
