import type { SellerLeadView } from "@/contracts/requirements";
import { createServices } from "@/server/services";
import { services as shippedServices } from "@/server";
import { notConnectedDataAccess } from "@/server/data/not-connected";
import type { AuthState, SessionProvider } from "@/server/auth/types";
import type { DataAccess } from "@/server/data/repositories";
import { C, CL, E, K, U, admin, buyer, reviewer1, sellerAcme, sellerGlobex, session } from "../fixtures";

// ---- TEST-ONLY in-memory repositories with two tenants and synthetic data (no real people, no I/O) ----
type LeadFact = { deliveredDirectly: boolean; companyVerified: boolean; responded: boolean };
function makeData() {
  const facts = new Map<string, LeadFact>([[`${E.lead1}|${C.acme}`, { deliveredDirectly: true, companyVerified: true, responded: false }]]);
  const claims = new Map([[CL.claim1, { claimantId: U.sellerA, companyId: C.acme }], [CL.claim2, { claimantId: U.sellerB, companyId: C.globex }]]);
  const calls: string[] = [];
  const spy = <T>(name: string, v: T) => async () => { calls.push(name); return v; };
  const data: DataAccess = {
    suppliers: { listPublic: spy("listPublic", []), getPublicBySlug: spy("getPublicBySlug", null), getOwnCompanyState: spy("getOwnCompanyState", null), openSupplierContacts: spy("openSupplierContacts", []) },
    claims: {
      getClaimFacts: async (_u, id) => claims.get(id as never) ?? null,
      submitClaim: spy("submitClaim", {} as never), listOwnClaims: spy("listOwnClaims", []), reviewClaim: spy("reviewClaim", undefined),
      requestEvidenceLinks: async () => { calls.push("requestEvidenceLinks"); return [{ evidenceId: "e1", url: "https://example.invalid/x", expiresInSeconds: 60 }]; },
    },
    requirements: { create: async (u) => { calls.push("create"); return { id: E.lead1, ref: "REF-1", buyerId: u, product: "p", quantity: "1", destination: "d", delivery: "stored", notice: "Recorded. No supplier has been contacted yet.", createdAt: "2026-11-09" }; }, listOwn: spy("listOwn", []) },
    leads: {
      getLeadAccessFacts: async (_u, e, c) => facts.get(`${e}|${c}`) ?? null, // cross-tenant pairs are simply absent
      listDeliveredToCompany: spy("listDelivered", []), respond: async () => { calls.push("respond"); const k = `${E.lead1}|${C.acme}`; facts.set(k, { ...facts.get(k)!, responded: true }); },
      revealBuyerContact: async () => { calls.push("reveal"); return { enquiryId: E.lead1, buyerName: "Test Buyer", buyerPhone: null, buyerEmail: null, buyerCompany: null }; },
      listCases: spy("listCases", []), updateCase: spy("updateCase", undefined), assignCase: spy("assignCase", {} as never), openBuyerContact: async () => { calls.push("openBuyerContact"); return { enquiryId: E.lead1, buyerName: "Test Buyer", buyerPhone: null, buyerEmail: null, buyerCompany: null }; },
    },
    staffActions: { listRecent: spy("listRecent", []) },
  };
  return { data, calls };
}
const asState = (s: ReturnType<typeof session> | null): SessionProvider => ({ getAuthState: async (): Promise<AuthState> => s ? { status: "authenticated", session: s } : { status: "anonymous" } });
const svc = (s: ReturnType<typeof session> | null) => { const m = makeData(); return { ...m, s: createServices(asState(s), m.data) }; };

describe("shipped wiring is not connected and fails closed", () => {
  it("every protected service returns auth_unavailable; nothing touches data", async () => {
    const rs = await Promise.all([
      shippedServices.createRequirement({}, {}), shippedServices.listOwnRequirements(), shippedServices.listLeads(C.acme), shippedServices.respondToLead(E.lead1, C.acme),
      shippedServices.revealBuyerContact(E.lead1, C.acme), shippedServices.listCases("all"), shippedServices.updateCase(K.case1, "contacted", null), shippedServices.assignCase(K.case1, U.reviewer1),
      shippedServices.openBuyerContact(E.lead1, K.case1, "valid purpose"), shippedServices.requestEvidenceLinks(CL.claim1, ["e"], "valid purpose"), shippedServices.reviewClaim(CL.claim1, "approved", "ok"), shippedServices.listOwnClaims(),
    ]);
    // createRequirement validates input first (no session needed to say "invalid"); every other call is denied by auth
    expect(rs[0]).toEqual({ ok: false, error: "invalid_input" });
    for (const r of rs.slice(1)) expect(r).toEqual({ ok: false, error: "auth_unavailable" });
  });
  it("public reads report not_connected, never fake data", async () => {
    expect(await shippedServices.listPublicSuppliers({})).toEqual({ ok: false, error: "not_connected" });
    expect(await shippedServices.getPublicSupplier("x")).toEqual({ ok: false, error: "not_connected" });
  });
  it("the not-connected data layer rejects every method without side effects", async () => {
    const all = Object.values(notConnectedDataAccess).flatMap((repo) => Object.values(repo) as (() => Promise<unknown>)[]);
    expect(all.length).toBeGreaterThan(15);
    for (const f of all) await expect(f()).rejects.toMatchObject({ code: "NOT_CONNECTED" });
  });
});

describe("unauthorised access", () => {
  it("anonymous callers are refused and the repository is never called", async () => {
    const { s, calls } = svc(null);
    expect((await s.listOwnRequirements())).toEqual({ ok: false, error: "unauthenticated" });
    expect((await s.listLeads(C.acme))).toEqual({ ok: false, error: "unauthenticated" });
    expect((await s.listCases("all"))).toEqual({ ok: false, error: "unauthenticated" });
    expect(calls).toEqual([]);
  });
  it("a buyer cannot use seller, staff or admin services", async () => {
    const { s, calls } = svc(buyer);
    for (const r of [await s.listLeads(C.acme), await s.respondToLead(E.lead1, C.acme), await s.listCases("all"), await s.listCases("assigned"), await s.assignCase(K.case1, U.reviewer1)]) expect(r.ok).toBe(false);
    expect(calls).toEqual([]);
  });
  it("invalid requirement input is rejected before any repository call", async () => {
    const { s, calls } = svc(buyer);
    expect(await s.createRequirement({ product: "x" }, { name: "A", phone: "abc" })).toEqual({ ok: false, error: "invalid_input" });
    expect(await s.createRequirement({ product: "Rugs", quantity: "5", destination: "Sample", consentNoticeVersion: "v0", evil: 1 }, { name: "Test Buyer", phone: "+91 90000 00000" })).toEqual({ ok: false, error: "invalid_input" }); // strict: unknown key
    expect(calls).toEqual([]);
  });
  it("valid requirement passes through to the repository exactly once", async () => {
    const { s, calls } = svc(buyer);
    const r = await s.createRequirement({ product: "Rugs", quantity: "5", destination: "Sample", consentNoticeVersion: "draft-0" }, { name: "Test Buyer", phone: "+91 90000 00000" });
    expect(r.ok).toBe(true); expect(calls).toEqual(["create"]);
  });
});

describe("cross-tenant scenarios", () => {
  it("Globex cannot list, respond to, or reveal Acme's lead (indistinguishable from not found)", async () => {
    const { s, calls } = svc(sellerGlobex());
    expect(await s.listLeads(C.acme)).toEqual({ ok: false, error: "forbidden" });
    expect(await s.respondToLead(E.lead1, C.acme)).toEqual({ ok: false, error: "forbidden" });
    expect(await s.revealBuyerContact(E.lead1, C.acme)).toEqual({ ok: false, error: "forbidden" });
    expect(await s.respondToLead(E.lead1, C.globex)).toEqual({ ok: false, error: "forbidden" }); // own company id, foreign lead
    expect(calls).toEqual([]);
  });
  it("Acme sales: reveal is blocked until responding; then allowed once", async () => {
    const { s, calls } = svc(sellerAcme("sales"));
    expect(await s.revealBuyerContact(E.lead1, C.acme)).toEqual({ ok: false, error: "precondition_failed" });
    expect((await s.respondToLead(E.lead1, C.acme)).ok).toBe(true);
    expect((await s.revealBuyerContact(E.lead1, C.acme)).ok).toBe(true);
    expect(calls).toEqual(["respond", "reveal"]);
  });
  it("viewer role in Acme cannot respond", async () => {
    const { s, calls } = svc(sellerAcme("viewer"));
    expect(await s.respondToLead(E.lead1, C.acme)).toEqual({ ok: false, error: "forbidden" });
    expect(calls).toEqual([]);
  });
  it("unverified company cannot read leads even as owner", async () => {
    const m = makeData();
    const s = createServices(asState(session(U.sellerA, "seller", [{ companyId: C.unverified, role: "owner", status: "active", companyClaimStatus: "approved", companyVerified: false }])), m.data);
    expect(await s.listLeads(C.unverified)).toEqual({ ok: false, error: "precondition_failed" });
    expect(m.calls).toEqual([]);
  });
  it("evidence of Globex's claim is invisible to a reviewer not assigned to it; assigned reviewer needs a purpose", async () => {
    const { s, calls } = svc(reviewer1);
    expect(await s.requestEvidenceLinks(CL.claim2, ["e1"], "check registration")).toEqual({ ok: false, error: "forbidden" });
    expect(await s.requestEvidenceLinks(CL.claim1, ["e1"], "")).toEqual({ ok: false, error: "purpose_required" });
    expect((await s.requestEvidenceLinks(CL.claim1, ["e1"], "check registration")).ok).toBe(true);
    expect(calls).toEqual(["requestEvidenceLinks"]);
  });
  it("a claim id nobody can see yields forbidden, same as a real one the caller lacks", async () => {
    const { s } = svc(reviewer1);
    const unknown = "66666666-6666-4666-8666-666666666699" as typeof CL.claim1;
    expect(await s.requestEvidenceLinks(unknown, ["e1"], "check registration")).toEqual(await s.requestEvidenceLinks(CL.claim2, ["e1"], "check registration"));
  });
  it("reviewer cannot update a case they are not assigned to; admin can", async () => {
    expect(await svc(reviewer1).s.updateCase(K.case2, "contacted", null)).toEqual({ ok: false, error: "forbidden" });
    expect((await svc(reviewer1).s.updateCase(K.case1, "contacted", null)).ok).toBe(true);
    expect((await svc(admin).s.updateCase(K.case2, "contacted", null)).ok).toBe(true);
  });
  it("buyer contact for staff needs purpose + assignment; admin still needs purpose", async () => {
    expect(await svc(reviewer1).s.openBuyerContact(E.lead1, K.case1, "")).toEqual({ ok: false, error: "purpose_required" });
    expect(await svc(reviewer1).s.openBuyerContact(E.lead1, K.case2, "valid purpose")).toEqual({ ok: false, error: "forbidden" });
    expect((await svc(reviewer1).s.openBuyerContact(E.lead1, K.case1, "valid purpose")).ok).toBe(true);
    expect(await svc(admin).s.openBuyerContact(E.lead1, K.case2, "")).toEqual({ ok: false, error: "purpose_required" });
  });
  it("only an administrator may assign cases; reviewers may not", async () => {
    expect(await svc(reviewer1).s.assignCase(K.case1, U.reviewer2)).toEqual({ ok: false, error: "forbidden" });
    expect((await svc(admin).s.assignCase(K.case1, U.reviewer2)).ok).toBe(true);
  });
});

describe("public data cannot leak through the services", () => {
  it("a repository that returns an extra private column makes the public service fail instead of exposing it", async () => {
    const m = makeData();
    m.data.suppliers.listPublic = async () => [{ id: "11111111-1111-4111-8111-111111111111", slug: "a", name: "A", businessType: null, about: null, city: null, state: null, country: null, website: null, logoPath: null, publicLabel: "Unclaimed — Not Verified", isClaimed: false, isVerified: false, dataAsOf: null, updatedAt: "x", phone: "+000" } as never];
    const r = await createServices(asState(null), m.data).listPublicSuppliers({});
    expect(r.ok).toBe(false);
  });
  it("seller lead view type carries no buyer identity or contact (compile-time + runtime)", () => {
    expectTypeOf<SellerLeadView>().not.toHaveProperty("buyerId");
    expectTypeOf<SellerLeadView>().not.toHaveProperty("buyerPhone");
    expectTypeOf<SellerLeadView>().not.toHaveProperty("buyerEmail");
    const view: SellerLeadView = { enquiryId: E.lead1, companyId: C.acme, product: "p", quantity: "1", destination: "d", details: "", matchReasons: [], responded: false, receivedAt: "t" };
    expect(Object.keys(view).join(" ")).not.toMatch(/buyer|phone|email|contact/i);
  });

});
