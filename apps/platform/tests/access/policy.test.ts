import { evaluate } from "@/server/access/policy";
import { PERMISSIONS, type Permission, type Resource } from "@/server/access/permissions";
import type { Actor } from "@/server/auth/types";
import { C, CL, K, U, admin, buyer, member, reviewer1, session, sellerAcme, sellerGlobex } from "../fixtures";

const user = (s: ReturnType<typeof session>): Actor => ({ kind: "user", session: s });
const anon: Actor = { kind: "anonymous" };
const lead = (o: Partial<Extract<Resource, { type: "lead" }>> = {}): Resource => ({ type: "lead", companyId: C.acme, deliveredDirectly: true, companyVerified: true, responded: false, ...o });
const allowed = (a: Actor | null, p: Permission, r: Resource = { type: "none" }, purpose?: string) => evaluate(a, p, r, { purpose });
const code = (a: Actor | null, p: Permission, r: Resource = { type: "none" }, purpose?: string) => { const d = allowed(a, p, r, purpose); return d.allow ? "ALLOW" : d.code; };

describe("authentication state", () => {
  it("unavailable auth (null actor) denies everything, even public-looking operations except public reads", () => {
    for (const p of PERMISSIONS) {
      if (p === "supplier:read-public") continue;
      expect(code(null, p)).toBe("auth_unavailable");
    }
  });
  it("anonymous may read public suppliers and nothing else", () => {
    expect(code(anon, "supplier:read-public")).toBe("ALLOW");
    for (const p of PERMISSIONS.filter((x) => x !== "supplier:read-public")) expect(code(anon, p)).toBe("unauthenticated");
  });
});

describe("buyers", () => {
  it("can create requirements and read only their own", () => {
    expect(code(user(buyer), "requirement:create")).toBe("ALLOW");
    expect(code(user(buyer), "requirement:read-own", { type: "requirement", buyerId: U.buyerA })).toBe("ALLOW");
    expect(code(user(buyer), "requirement:read-own", { type: "requirement", buyerId: U.buyerB })).toBe("forbidden");
  });
  it("have no seller, staff or admin power", () => {
    for (const p of PERMISSIONS.filter((x) => /^(company|catalogue|lead|staff|admin):/.test(x))) expect(code(user(buyer), p, lead(), "valid purpose")).not.toBe("ALLOW");
  });
});

describe("sellers: tenant isolation (cross-tenant scenarios)", () => {
  it("owner of Acme reads Acme private data; Globex owner cannot", () => {
    const r: Resource = { type: "company", companyId: C.acme };
    expect(code(user(sellerAcme()), "company:read-private", r)).toBe("ALLOW");
    expect(code(user(sellerGlobex()), "company:read-private", r)).toBe("forbidden");
  });
  it("role matrix inside one company", () => {
    const r: Resource = { type: "company", companyId: C.acme };
    const exp: Record<string, [boolean, boolean, boolean]> = { // [edit-profile, edit-catalogue, read-private]
      owner: [true, true, true], manager: [true, true, true], sales: [false, false, false], catalogue_editor: [false, true, false], viewer: [false, false, false],
    };
    for (const [role, [prof, cat, priv]] of Object.entries(exp)) {
      const a = user(sellerAcme(role as never));
      expect(allowed(a, "company:edit-profile", r).allow, `${role} edit-profile`).toBe(prof);
      expect(allowed(a, "catalogue:edit", r).allow, `${role} catalogue`).toBe(cat);
      expect(allowed(a, "company:read-private", r).allow, `${role} read-private`).toBe(priv);
    }
  });
  it("invited, removed, or not-approved-company memberships grant nothing", () => {
    const r: Resource = { type: "company", companyId: C.acme };
    for (const m of [member(C.acme, "owner", { status: "invited" }), member(C.acme, "owner", { status: "removed" }), member(C.acme, "owner", { companyClaimStatus: "under_review" }), member(C.acme, "owner", { companyClaimStatus: "rejected" })]) {
      expect(code(user(session(U.sellerA, "seller", [m])), "company:edit-profile", r)).toBe("forbidden");
    }
  });
  it("a profile with app_role seller but NO effective membership has no company power", () => {
    expect(code(user(session(U.sellerA, "seller")), "company:read-private", { type: "company", companyId: C.acme })).toBe("forbidden");
  });
  it("membership of company A never opens company B", () => {
    const a = user(session(U.sellerA, "seller", [member(C.acme, "owner")]));
    expect(code(a, "lead:read-delivered", lead({ companyId: C.globex }))).toBe("forbidden");
    expect(code(a, "catalogue:edit", { type: "company", companyId: C.globex })).toBe("forbidden");
  });
});

describe("verified-only lead delivery", () => {
  it("delivered + verified + selling role is required to read or respond", () => {
    const a = user(sellerAcme("sales"));
    expect(code(a, "lead:read-delivered", lead())).toBe("ALLOW");
    expect(code(a, "lead:respond", lead())).toBe("ALLOW");
    expect(code(a, "lead:read-delivered", lead({ companyVerified: false }))).toBe("precondition_failed");
    expect(code(a, "lead:respond", lead({ deliveredDirectly: false }))).toBe("precondition_failed");
  });
  it("viewer and catalogue_editor cannot read leads", () => {
    for (const role of ["viewer", "catalogue_editor"] as const) expect(code(user(sellerAcme(role)), "lead:read-delivered", lead())).toBe("forbidden");
  });
  it("buyer contact is revealed only after responding", () => {
    const a = user(sellerAcme("manager"));
    expect(code(a, "lead:reveal-buyer-contact", lead({ responded: false }))).toBe("precondition_failed");
    expect(code(a, "lead:reveal-buyer-contact", lead({ responded: true }))).toBe("ALLOW");
    expect(code(a, "lead:reveal-buyer-contact", lead({ responded: true, companyVerified: false }))).toBe("precondition_failed");
    expect(code(user(sellerGlobex()), "lead:reveal-buyer-contact", lead({ responded: true }))).toBe("forbidden");
  });
});

describe("staff: reviewers are assignment-scoped, admins are not", () => {
  it("reviewer can read/update only assigned cases", () => {
    const a = user(reviewer1);
    expect(code(a, "staff:lead:update", { type: "lead-case", caseId: K.case1 })).toBe("ALLOW");
    expect(code(a, "staff:lead:update", { type: "lead-case", caseId: K.case2 })).toBe("forbidden");
    expect(code(a, "staff:lead:read", { type: "none" })).toBe("forbidden");
  });
  it("private contact reveal needs a valid purpose AND assignment", () => {
    const a = user(reviewer1);
    const r: Resource = { type: "enquiry-contact", caseId: K.case1 };
    expect(code(a, "staff:contact:open-buyer", r)).toBe("purpose_required");
    expect(code(a, "staff:contact:open-buyer", r, "  ab ")).toBe("purpose_required");
    expect(code(a, "staff:contact:open-buyer", r, "verify requirement details")).toBe("ALLOW");
    expect(code(a, "staff:contact:open-buyer", { type: "enquiry-contact", caseId: K.case2 }, "verify requirement details")).toBe("forbidden");
  });
  it("evidence links: assigned claim + purpose; other claims forbidden", () => {
    const a = user(reviewer1);
    expect(code(a, "staff:evidence:request-link", { type: "claim", claimId: CL.claim1, claimantId: U.sellerA, companyId: C.acme }, "check registration")).toBe("ALLOW");
    expect(code(a, "staff:evidence:request-link", { type: "claim", claimId: CL.claim2, claimantId: U.sellerB, companyId: C.globex }, "check registration")).toBe("forbidden");
    expect(code(a, "staff:evidence:request-link", { type: "claim", claimId: CL.claim1, claimantId: U.sellerA, companyId: C.acme })).toBe("purpose_required");
  });
  it("reviewers cannot use admin permissions", () => {
    for (const p of PERMISSIONS.filter((x) => x.startsWith("admin:"))) expect(code(user(reviewer1), p)).toBe("forbidden");
  });
  it("admin has desk-wide power, still needs a purpose to open private contacts", () => {
    const a = user(admin);
    for (const p of PERMISSIONS.filter((x) => x.startsWith("admin:"))) expect(code(a, p)).toBe("ALLOW");
    expect(code(a, "staff:contact:open-buyer", { type: "enquiry-contact", caseId: K.case2 })).toBe("purpose_required");
    expect(code(a, "staff:contact:open-buyer", { type: "enquiry-contact", caseId: K.case2 }, "support request 12")).toBe("ALLOW");
  });
  it("staff gain no seller power over a company they are not members of", () => {
    expect(code(user(admin), "lead:respond", lead())).toBe("forbidden");
    expect(code(user(reviewer1), "company:read-private", { type: "company", companyId: C.acme })).toBe("forbidden");
    expect(code(user(admin), "lead:reveal-buyer-contact", lead({ responded: true }))).toBe("forbidden");
  });
  it("sellers cannot use staff or admin permissions", () => {
    for (const p of PERMISSIONS.filter((x) => /^(staff|admin):/.test(x))) expect(code(user(sellerAcme()), p, { type: "lead-case", caseId: K.case1 }, "valid purpose")).toBe("forbidden");
  });
});

describe("deny by default", () => {
  it("an unknown permission string is denied", () => {
    expect(evaluate(user(admin), "does:not-exist" as Permission, { type: "none" }).allow).toBe(false);
  });
  it("wrong resource type for a permission is denied", () => {
    expect(code(user(sellerAcme()), "company:read-private", { type: "none" })).toBe("forbidden");
    expect(code(user(buyer), "requirement:read-own", { type: "none" })).toBe("forbidden");
  });
  it("every permission has at least one role that can be allowed (no dead permissions) and anonymous is allowed only the public one", () => {
    const sample = [user(buyer), user(sellerAcme()), user(reviewer1), user(admin)];
    const res: Resource[] = [{ type: "none" }, lead({ responded: true }), { type: "company", companyId: C.acme }, { type: "requirement", buyerId: U.buyerA }, { type: "lead-case", caseId: K.case1 }, { type: "enquiry-contact", caseId: K.case1 }, { type: "claim", claimId: CL.claim1, claimantId: U.buyerA, companyId: C.acme }];
    for (const p of PERMISSIONS) {
      const any = sample.some((a) => res.some((r) => allowed(a, p, r, "valid purpose").allow));
      expect(any, p).toBe(true);
      if (p !== "supplier:read-public") expect(allowed(anon, p, res[1]!, "valid purpose").allow).toBe(false);
    }
  });
});
