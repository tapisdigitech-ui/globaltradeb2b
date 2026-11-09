import "server-only";
import type { AppRole } from "@/contracts/enums";
import type { CompanyMembership } from "@/contracts/claims";
import type { CaseId, ClaimId, UserId } from "@/contracts/ids";

/**
 * What a verified session carries. A Session may only ever be produced by a SessionProvider that validated the token
 * with the Auth server (see docs: getUser(), never a decoded cookie). Nothing in this codebase constructs one outside tests.
 */
export type StaffScope = {
  /** Lead cases assigned to this reviewer. Admins are not limited by assignment (see policy). */
  readonly assignedCaseIds: readonly CaseId[];
  readonly assignedClaimIds: readonly ClaimId[];
};

export type Session = {
  readonly userId: UserId;
  readonly appRole: AppRole;
  readonly memberships: readonly CompanyMembership[];
  readonly staffScope: StaffScope;
};

/**
 * Result of asking "who is calling?".
 *  - anonymous: no valid session.
 *  - authenticated: a validated session.
 *  - unavailable: the auth system cannot answer (not connected, outage). MUST be treated as DENY, never as anonymous-allowed.
 */
export type AuthState =
  | { readonly status: "anonymous" }
  | { readonly status: "authenticated"; readonly session: Session }
  | { readonly status: "unavailable" };

export interface SessionProvider {
  getAuthState(): Promise<AuthState>;
}

/** Actor seen by the policy engine. */
export type Actor =
  | { readonly kind: "anonymous" }
  | { readonly kind: "user"; readonly session: Session };

export function actorFrom(state: AuthState): Actor | null {
  if (state.status === "authenticated") return { kind: "user", session: state.session };
  if (state.status === "anonymous") return { kind: "anonymous" };
  return null; // unavailable: no actor can be formed
}
