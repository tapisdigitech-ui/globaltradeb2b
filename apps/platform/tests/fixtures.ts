// TEST-ONLY synthetic fixtures. These are not sessions and not users: ids are random-looking placeholders and there is no
// credential, token, name, phone or email anywhere. Nothing here is importable from src/.
import type { CompanyMembership } from "@/contracts/claims";
import type { AppRole, MemberRole } from "@/contracts/enums";
import { caseId, claimId, companyId, enquiryId, userId } from "@/contracts/ids";
import type { Session, StaffScope } from "@/server/auth/types";

export const U = {
  buyerA: userId("00000000-0000-4000-8000-0000000000a1"),
  buyerB: userId("00000000-0000-4000-8000-0000000000b1"),
  sellerA: userId("00000000-0000-4000-8000-0000000000a2"),
  sellerB: userId("00000000-0000-4000-8000-0000000000b2"),
  reviewer1: userId("00000000-0000-4000-8000-0000000000c1"),
  reviewer2: userId("00000000-0000-4000-8000-0000000000c2"),
  admin: userId("00000000-0000-4000-8000-0000000000d1"),
};
export const C = { acme: companyId("11111111-1111-4111-8111-111111111111"), globex: companyId("22222222-2222-4222-8222-222222222222"), unverified: companyId("33333333-3333-4333-8333-333333333333") };
export const E = { lead1: enquiryId("44444444-4444-4444-8444-444444444441"), lead2: enquiryId("44444444-4444-4444-8444-444444444442") };
export const K = { case1: caseId("55555555-5555-4555-8555-555555555551"), case2: caseId("55555555-5555-4555-8555-555555555552") };
export const CL = { claim1: claimId("66666666-6666-4666-8666-666666666661"), claim2: claimId("66666666-6666-4666-8666-666666666662") };

export const member = (id: typeof C.acme, role: MemberRole, o: Partial<CompanyMembership> = {}): CompanyMembership =>
  ({ companyId: id, role, status: "active", companyClaimStatus: "approved", companyVerified: true, ...o });

export function session(userIdV: typeof U.buyerA, appRole: AppRole, memberships: CompanyMembership[] = [], scope: Partial<StaffScope> = {}): Session {
  return { userId: userIdV, appRole, memberships, staffScope: { assignedCaseIds: [], assignedClaimIds: [], ...scope } };
}
export const sellerAcme = (role: MemberRole = "owner") => session(U.sellerA, "seller", [member(C.acme, role)]);
export const sellerGlobex = (role: MemberRole = "owner") => session(U.sellerB, "seller", [member(C.globex, role)]);
export const buyer = session(U.buyerA, "buyer");
export const reviewer1 = session(U.reviewer1, "reviewer", [], { assignedCaseIds: [K.case1], assignedClaimIds: [CL.claim1] });
export const admin = session(U.admin, "admin");
