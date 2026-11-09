import { readFileSync } from "node:fs";
import { decideRoute, guardRoute, type RouteRequirement } from "@/server/access/route-guards";
import { notConnectedSessionProvider } from "@/server/auth/provider";
import type { AuthState, SessionProvider } from "@/server/auth/types";
import { C, U, admin, buyer, member, reviewer1, session, sellerAcme } from "../fixtures";

const REQS: RouteRequirement[] = [{ kind: "seller-dashboard" }, { kind: "lead-desk" }];
const auth = (s: ReturnType<typeof session>): AuthState => ({ status: "authenticated", session: s });

describe("route guard decisions", () => {
  it("unavailable auth never allows and never redirects to login: it reports unavailable", () => {
    for (const r of REQS) expect(decideRoute({ status: "unavailable" }, r)).toEqual({ outcome: "unavailable" });
  });
  it("anonymous is sent to login for both areas", () => {
    for (const r of REQS) expect(decideRoute({ status: "anonymous" }, r)).toEqual({ outcome: "redirect-login" });
  });
  it("seller dashboard: effective member allowed; buyer, staff-without-membership, removed/unapproved members get not-found", () => {
    const r: RouteRequirement = { kind: "seller-dashboard" };
    expect(decideRoute(auth(sellerAcme("viewer")), r).outcome).toBe("allow");
    expect(decideRoute(auth(buyer), r).outcome).toBe("not-found");
    expect(decideRoute(auth(admin), r).outcome).toBe("not-found");
    expect(decideRoute(auth(session(U.sellerA, "seller")), r).outcome).toBe("not-found");
    expect(decideRoute(auth(session(U.sellerA, "seller", [member(C.acme, "owner", { status: "removed" })])), r).outcome).toBe("not-found");
    expect(decideRoute(auth(session(U.sellerA, "seller", [member(C.acme, "owner", { companyClaimStatus: "claim_submitted" })])), r).outcome).toBe("not-found");
  });
  it("lead desk: only reviewer and admin; sellers and buyers get not-found (route existence is not revealed)", () => {
    const r: RouteRequirement = { kind: "lead-desk" };
    expect(decideRoute(auth(reviewer1), r).outcome).toBe("allow");
    expect(decideRoute(auth(admin), r).outcome).toBe("allow");
    expect(decideRoute(auth(sellerAcme()), r).outcome).toBe("not-found");
    expect(decideRoute(auth(buyer), r).outcome).toBe("not-found");
  });
  it("the shipped (not connected) provider makes every guard answer unavailable", async () => {
    for (const r of REQS) expect(await guardRoute(notConnectedSessionProvider, r)).toEqual({ outcome: "unavailable" });
  });
  it("a provider that throws is not treated as allow", async () => {
    const boom: SessionProvider = { getAuthState: async () => { throw new Error("down"); } };
    await expect(guardRoute(boom, { kind: "lead-desk" })).rejects.toThrow(); // callers must treat rejection as an error page, never as allow
  });
});

describe("honesty about protection", () => {
  const dash = readFileSync("src/app/dashboard/page.tsx", "utf8");
  const desk = readFileSync("src/app/admin/lead-desk/page.tsx", "utf8");
  it("the demo shell pages do NOT call a guard (so they must keep saying they are unprotected)", () => {
    for (const src of [dash, desk]) { expect(src).not.toMatch(/guardRoute|decideRoute|@\/server/); expect(src).toContain("PreviewShell"); }
  });
  it("PreviewShell still announces that access control is not connected", () => {
    expect(readFileSync("src/components/layout/PreviewShell.tsx", "utf8")).toMatch(/access control is not connected/);
  });
  it("no page claims that a route is secured", () => {
    const files = [dash, desk, readFileSync("src/components/layout/PreviewShell.tsx", "utf8")].join("\n");
    expect(files).not.toMatch(/\b(secure|secured|protected by|authenticated as|logged in as|signed in as)\b/i);
  });
});
