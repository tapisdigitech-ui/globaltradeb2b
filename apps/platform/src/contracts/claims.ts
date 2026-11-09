import type { ClaimId, CompanyId, UserId } from "./ids";
import type { ClaimStatus, DirectoryStatus, MemberRole, VerificationStatus } from "./enums";

/** A claimant's own view of their claim (no reviewer notes, no evidence paths). */
export type BusinessClaim = {
  readonly id: ClaimId;
  readonly companyId: CompanyId;
  readonly claimantId: UserId;
  readonly status: ClaimStatus;
  readonly submittedAt: string | null;
  readonly decidedAt: string | null;
};

/** Company state as the owning company's members see it. */
export type CompanyState = {
  readonly companyId: CompanyId;
  readonly claimStatus: ClaimStatus;
  readonly verificationStatus: VerificationStatus;
  readonly directoryStatus: DirectoryStatus;
};

export type CompanyMembership = {
  readonly companyId: CompanyId;
  readonly role: MemberRole;
  readonly status: "invited" | "active" | "removed";
  /** Mirrors SQL is_company_member(): a membership counts only while the company claim is approved. */
  readonly companyClaimStatus: ClaimStatus;
  readonly companyVerified: boolean;
};

/** "Verified" can only be derived from the server state; the client never decides it. */
export function isEffectiveMember(m: CompanyMembership): boolean {
  return m.status === "active" && m.companyClaimStatus === "approved";
}
