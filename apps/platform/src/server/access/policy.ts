import "server-only";
import { isEffectiveMember } from "@/contracts/claims";
import type { MemberRole } from "@/contracts/enums";
import type { CompanyId } from "@/contracts/ids";
import { hasValidPurpose } from "@/contracts/staff-actions";
import { actorFrom, type Actor, type AuthState, type Session } from "../auth/types";
import type { AccessContext, Decision, Permission, Resource } from "./permissions";

/**
 * APPLICATION-LAYER ACCESS POLICY (defence in depth, not the authority).
 * The database (RLS, grants, SECURITY DEFINER RPCs) is the enforcement point; this policy decides what the app
 * attempts and shows, and gives tests a precise model to compare against Round 10's real-stack results.
 * Rules: deny by default; unknown permission = deny; resource facts come from the server; no implicit cross-role power.
 */
const allow: Decision = { allow: true };
const deny = (code: Exclude<Decision, { allow: true }>["code"]): Decision => ({ allow: false, code });

const SELLING: readonly MemberRole[] = ["owner", "manager", "sales"]; // respond_to_lead / reveal_buyer_contact in SQL
const EDIT_PROFILE: readonly MemberRole[] = ["owner", "manager"];
const EDIT_CATALOGUE: readonly MemberRole[] = ["owner", "manager", "catalogue_editor"];
const READ_PRIVATE: readonly MemberRole[] = ["owner", "manager"];

function memberRole(s: Session, companyId: CompanyId) {
  return s.memberships.find((m) => m.companyId === companyId && isEffectiveMember(m));
}
const hasRole = (s: Session, companyId: CompanyId, roles: readonly MemberRole[]) => {
  const m = memberRole(s, companyId);
  return !!m && roles.includes(m.role);
};
const isStaff = (s: Session) => s.appRole === "reviewer" || s.appRole === "admin";
const isAdmin = (s: Session) => s.appRole === "admin";

export function evaluate(actor: Actor | null, permission: Permission, resource: Resource, ctx: AccessContext = {}): Decision {
  if (actor === null) return deny("auth_unavailable");

  if (permission === "supplier:read-public") return allow; // public data, any caller (incl. anonymous)

  if (actor.kind === "anonymous") return deny("unauthenticated");
  const s = actor.session;

  switch (permission) {
    // ----- buyer: own data only. Any signed-in user may be a buyer; staff and sellers do not gain access to others' requirements here.
    case "requirement:create":
      return allow;
    case "requirement:read-own":
      return resource.type === "requirement" && resource.buyerId === s.userId ? allow : deny("forbidden");

    // ----- company members (tenant boundary = companyId + effective membership of an APPROVED company)
    case "company:read-private":
      return resource.type === "company" && hasRole(s, resource.companyId, READ_PRIVATE) ? allow : deny("forbidden");
    case "company:edit-profile":
      return resource.type === "company" && hasRole(s, resource.companyId, EDIT_PROFILE) ? allow : deny("forbidden");
    case "catalogue:edit":
      return resource.type === "company" && hasRole(s, resource.companyId, EDIT_CATALOGUE) ? allow : deny("forbidden");
    case "claim:submit":
      return allow; // any signed-in user may submit a claim; approval is staff-only
    case "claim:read-own":
      return resource.type === "claim" && resource.claimantId === s.userId ? allow : deny("forbidden");

    case "lead:read-delivered":
    case "lead:respond": {
      if (resource.type !== "lead" || !hasRole(s, resource.companyId, SELLING)) return deny("forbidden");
      // verified-only: the matcher must have routed it to THIS company directly and the company must be verified now
      return resource.deliveredDirectly && resource.companyVerified ? allow : deny("precondition_failed");
    }
    case "lead:reveal-buyer-contact": {
      if (resource.type !== "lead" || !hasRole(s, resource.companyId, SELLING)) return deny("forbidden");
      if (!(resource.deliveredDirectly && resource.companyVerified)) return deny("precondition_failed");
      return resource.responded ? allow : deny("precondition_failed"); // must respond first (SQL: 'respond to the lead first')
    }

    // ----- staff: reviewers only within assignment; administrators across the desk
    case "staff:lead:list-assigned":
      return isStaff(s) ? allow : deny("forbidden"); // the database returns only this user's assigned cases
    case "staff:lead:read":
    case "staff:lead:update": {
      if (!isStaff(s)) return deny("forbidden");
      if (isAdmin(s)) return allow;
      return resource.type === "lead-case" && s.staffScope.assignedCaseIds.includes(resource.caseId) ? allow : deny("forbidden");
    }
    case "staff:contact:open-supplier":
    case "staff:contact:open-buyer": {
      if (!isStaff(s)) return deny("forbidden");
      if (!hasValidPurpose(ctx.purpose)) return deny("purpose_required");
      if (isAdmin(s)) return allow;
      const caseId = resource.type === "lead-case" || resource.type === "enquiry-contact" ? resource.caseId : null;
      return caseId !== null && s.staffScope.assignedCaseIds.includes(caseId) ? allow : deny("forbidden");
    }
    case "staff:claim:review":
    case "staff:evidence:request-link": {
      if (!isStaff(s)) return deny("forbidden");
      if (permission === "staff:evidence:request-link" && !hasValidPurpose(ctx.purpose)) return deny("purpose_required");
      if (isAdmin(s)) return allow;
      return resource.type === "claim" && s.staffScope.assignedClaimIds.includes(resource.claimId) ? allow : deny("forbidden");
    }

    // ----- administrators only
    case "admin:lead:overview":
    case "admin:lead:assign":
    case "admin:claim:assign-reviewer":
    case "admin:verification:set":
    case "admin:directory:publish":
    case "admin:routing:settings":
      return isAdmin(s) ? allow : deny("forbidden");

    default: {
      const _exhaustive: never = permission;
      void _exhaustive;
      return deny("forbidden"); // unknown permission: deny
    }
  }
}

export const can = (state: AuthState, permission: Permission, resource: Resource, ctx?: AccessContext): Decision =>
  evaluate(actorFrom(state), permission, resource, ctx);
