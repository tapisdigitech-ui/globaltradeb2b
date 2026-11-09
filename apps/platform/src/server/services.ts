import "server-only";
import { z } from "zod";
import { isEffectiveMember } from "@/contracts/claims";
import type { BusinessClaim } from "@/contracts/claims";
import type { CaseId, ClaimId, CompanyId, EnquiryId, UserId } from "@/contracts/ids";
import { publicSupplierSchema, type PublicSupplierProfile } from "@/contracts/public-supplier";
import type { BuyerPrivateContact, EvidenceLink } from "@/contracts/private";
import { requirementInputSchema, type BuyerRequirement, type LeadCaseSummary, type SellerLeadView } from "@/contracts/requirements";
import type { LeadStatus } from "@/contracts/enums";
import { evaluate } from "./access/policy";
import type { AccessContext, DenyCode, Permission, Resource } from "./access/permissions";
import { actorFrom, type Session, type SessionProvider } from "./auth/types";
import { NotConnectedError } from "./data/not-connected";
import type { DataAccess } from "./data/repositories";

export type ServiceError = DenyCode | "not_connected" | "invalid_input" | "not_found";
export type Result<T> = { readonly ok: true; readonly value: T } | { readonly ok: false; readonly error: ServiceError };
const ok = <T>(value: T): Result<T> => ({ ok: true, value });
const err = (error: ServiceError): Result<never> => ({ ok: false, error });

const contactSchema = z.strictObject({ name: z.string().trim().min(2).max(120), phone: z.string().trim().regex(/^[0-9+\-\s()]{7,16}$/), email: z.string().trim().email().optional() });

/**
 * Application services = policy check THEN repository call. The facade is the only thing pages and server actions should
 * use. Errors are coarse codes: no ids, no reasons, no data. A thrown NotConnectedError becomes "not_connected".
 */
export function createServices(provider: SessionProvider, data: DataAccess) {
  async function session(): Promise<{ s: Session } | { e: ServiceError }> {
    const state = await provider.getAuthState();
    const actor = actorFrom(state);
    if (actor === null) return { e: "auth_unavailable" };
    if (actor.kind === "anonymous") return { e: "unauthenticated" };
    return { s: actor.session };
  }

  async function run<T>(permission: Permission, resource: Resource, ctx: AccessContext | undefined, call: (s: Session) => Promise<T>): Promise<Result<T>> {
    const got = await session();
    if ("e" in got) return err(got.e);
    const d = evaluate({ kind: "user", session: got.s }, permission, resource, ctx);
    if (!d.allow) return err(d.code);
    try { return ok(await call(got.s)); }
    catch (e) { return err(e instanceof NotConnectedError ? "not_connected" : "forbidden"); }
  }

  return {
    // ---------- public (no session needed; but still fails closed on repository errors)
    async listPublicSuppliers(query: { q?: string; categoryId?: number; label?: string }): Promise<Result<readonly PublicSupplierProfile[]>> {
      try {
        const rows = await data.suppliers.listPublic(query);
        return ok(rows.map((r) => publicSupplierSchema.parse(r))); // strict: a leaked extra column throws
      } catch (e) { return err(e instanceof NotConnectedError ? "not_connected" : "forbidden"); }
    },
    async getPublicSupplier(slug: string): Promise<Result<PublicSupplierProfile>> {
      try {
        const r = await data.suppliers.getPublicBySlug(slug);
        return r ? ok(publicSupplierSchema.parse(r)) : err("not_found");
      } catch (e) { return err(e instanceof NotConnectedError ? "not_connected" : "forbidden"); }
    },

    // ---------- buyer
    async createRequirement(input: unknown, contact: unknown): Promise<Result<BuyerRequirement>> {
      const a = requirementInputSchema.safeParse(input), b = contactSchema.safeParse(contact);
      if (!a.success || !b.success) return err("invalid_input");
      return run("requirement:create", { type: "none" }, undefined, (s) => data.requirements.create(s.userId, a.data, b.data));
    },
    async listOwnRequirements(): Promise<Result<readonly BuyerRequirement[]>> {
      // Repository filters by userId; the policy needs an owner fact, which is the caller themself.
      const got = await session();
      if ("e" in got) return err(got.e);
      return run("requirement:read-own", { type: "requirement", buyerId: got.s.userId }, undefined, (s) => data.requirements.listOwn(s.userId));
    },

    // ---------- seller (tenant = company the caller is an EFFECTIVE member of)
    async listLeads(companyId: CompanyId): Promise<Result<readonly SellerLeadView[]>> {
      const got = await session();
      if ("e" in got) return err(got.e);
      const m = got.s.memberships.find((x) => x.companyId === companyId && isEffectiveMember(x));
      // deliveredDirectly=true is an assertion about the repository contract: it returns only directly delivered leads.
      return run("lead:read-delivered", { type: "lead", companyId, deliveredDirectly: true, companyVerified: !!m?.companyVerified, responded: false }, undefined, (s) => data.leads.listDeliveredToCompany(s.userId, companyId));
    },
    async respondToLead(enquiryId: EnquiryId, companyId: CompanyId): Promise<Result<void>> {
      return withLeadFacts("lead:respond", enquiryId, companyId, undefined, (s) => data.leads.respond(s.userId, { enquiryId, companyId }));
    },
    async revealBuyerContact(enquiryId: EnquiryId, companyId: CompanyId): Promise<Result<BuyerPrivateContact>> {
      return withLeadFacts("lead:reveal-buyer-contact", enquiryId, companyId, undefined, (s) => data.leads.revealBuyerContact(s.userId, { enquiryId, companyId }));
    },

    // ---------- staff / admin
    async listCases(scope: "assigned" | "all"): Promise<Result<readonly LeadCaseSummary[]>> {
      // "all" is the administrator overview; "assigned" is any staff member's own queue (the database filters it).
      const permission: Permission = scope === "all" ? "admin:lead:overview" : "staff:lead:list-assigned";
      return run(permission, { type: "none" }, undefined, (s) => data.leads.listCases(s.userId, scope));
    },
    async updateCase(caseId: CaseId, toStatus: LeadStatus, note: string | null): Promise<Result<void>> {
      return run("staff:lead:update", { type: "lead-case", caseId }, undefined, (s) => data.leads.updateCase(s.userId, { caseId, toStatus, note }));
    },
    async assignCase(caseId: CaseId, assigneeId: UserId) {
      return run("admin:lead:assign", { type: "none" }, undefined, (s) => data.leads.assignCase(s.userId, { caseId, assigneeId }));
    },
    async openBuyerContact(enquiryId: EnquiryId, caseId: CaseId, purpose: string): Promise<Result<BuyerPrivateContact>> {
      return run("staff:contact:open-buyer", { type: "enquiry-contact", caseId }, { purpose }, (s) => data.leads.openBuyerContact(s.userId, { enquiryId, caseId, purpose }));
    },
    async requestEvidenceLinks(claimId: ClaimId, evidenceIds: readonly string[], purpose: string): Promise<Result<readonly EvidenceLink[]>> {
      return withClaimFacts("staff:evidence:request-link", claimId, { purpose }, (s) => data.claims.requestEvidenceLinks(s.userId, { claimId, evidenceIds, purpose }));
    },
    async reviewClaim(claimId: ClaimId, decision: "approved" | "rejected" | "evidence_requested", reason: string): Promise<Result<void>> {
      return withClaimFacts("staff:claim:review", claimId, undefined, (s) => data.claims.reviewClaim(s.userId, { claimId, decision, reason }));
    },
    async listOwnClaims(): Promise<Result<readonly BusinessClaim[]>> {
      return run("claim:submit", { type: "none" }, undefined, (s) => data.claims.listOwnClaims(s.userId));
    },
  };

  async function withClaimFacts<T>(permission: Permission, claimId: ClaimId, ctx: AccessContext | undefined, call: (s: Session) => Promise<T>): Promise<Result<T>> {
    const got = await session();
    if ("e" in got) return err(got.e);
    let facts;
    try { facts = await data.claims.getClaimFacts(got.s.userId, claimId); }
    catch (e) { return err(e instanceof NotConnectedError ? "not_connected" : "forbidden"); }
    if (!facts) return err("forbidden"); // invisible == forbidden: no existence oracle
    return run(permission, { type: "claim", claimId, claimantId: facts.claimantId, companyId: facts.companyId }, ctx, call);
  }

  async function withLeadFacts<T>(permission: Permission, enquiryId: EnquiryId, companyId: CompanyId, ctx: AccessContext | undefined, call: (s: Session) => Promise<T>): Promise<Result<T>> {
    const got = await session();
    if ("e" in got) return err(got.e);
    let facts;
    try { facts = await data.leads.getLeadAccessFacts(got.s.userId, enquiryId, companyId); }
    catch (e) { return err(e instanceof NotConnectedError ? "not_connected" : "forbidden"); }
    if (!facts) return err("forbidden"); // cross-tenant ids are indistinguishable from missing ones
    return run(permission, { type: "lead", companyId, ...facts }, ctx, call);
  }
}
export type Services = ReturnType<typeof createServices>;
