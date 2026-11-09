import "./helpers";
import { render, screen } from "@testing-library/react";
import { existsSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { SUPPLIERS, DEMO_LEADS } from "@/data/demo";
import { SupplierCard } from "@/features/suppliers/SupplierCard";
import { filterSuppliers } from "@/features/suppliers/filter";
import { supplierBadge, DELIVERY_COPY, PREVIEW_NOTICE } from "@/lib/labels";
import { DELIVERY_STATES, VERIFICATION_LABELS } from "@/lib/domain";
import { DeliveryStatus } from "@/features/requirements/DeliveryStatus";
import SupplierPage from "@/app/suppliers/[slug]/page";
import LeadDeskPage from "@/app/admin/lead-desk/page";
import DashboardPage from "@/app/dashboard/page";
import HomePage from "@/app/page";
import RequirementPage from "@/app/requirements/new/page";

const EMAIL = /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i;
const PHONE = /(\+\d[\d\s().-]{7,}\d)|(\b\d{3}[\s.-]\d{3,4}[\s.-]\d{4}\b)|(\b\d{10}\b)/;

async function allPublicHtml(): Promise<string[]> {
  const out = [renderToStaticMarkup(HomePage()), renderToStaticMarkup(<SupplierCard supplier={SUPPLIERS[0]!} />)];
  for (const s of SUPPLIERS) out.push(renderToStaticMarkup(await SupplierPage({ params: Promise.resolve({ slug: s.slug }) })));
  out.push(renderToStaticMarkup(RequirementPage()));
  return out;
}

describe("public contact-data protection", () => {
  it("public types and data carry no contact fields", () => {
    for (const s of SUPPLIERS) {
      const keys = Object.keys(s).join(" ").toLowerCase();
      expect(keys).not.toMatch(/phone|mobile|email|mail|tel|address|whatsapp|contact/);
    }
  });
  it("no public page contains an email, phone number, mailto: or tel: link", async () => {
    for (const html of await allPublicHtml()) {
      const text = html.replace(/<[^>]+>/g, " ");
      expect(text).not.toMatch(EMAIL);
      expect(text).not.toMatch(PHONE);
      expect(html).not.toMatch(/href="(mailto|tel|sms|whatsapp):/i);
    }
  });
  it("supplier profile explains that contact details are not public", async () => {
    const html = renderToStaticMarkup(await SupplierPage({ params: Promise.resolve({ slug: "sample-loom-works" }) }));
    expect(html).toMatch(/Contact details are not shown on public pages/);
  });
  it("lead desk shell lists no buyer or supplier contact", () => {
    const text = renderToStaticMarkup(LeadDeskPage()).replace(/<[^>]+>/g, " ");
    expect(text).not.toMatch(EMAIL); expect(text).not.toMatch(PHONE);
    expect(JSON.stringify(DEMO_LEADS)).not.toMatch(/phone|email|mobile|buyerName/i);
  });
  it("directory URL filters never carry personal data (search only)", () => {
    expect(filterSuppliers(SUPPLIERS, { q: "loom" }).map((s) => s.slug)).toEqual(["sample-loom-works"]);
  });
});

describe("verification honesty", () => {
  it("only isVerified records can show Verified; inconsistent data degrades to not verified", () => {
    expect(supplierBadge({ label: "Verified", isVerified: false, isDemo: false }).text).toBe("Unclaimed — Not Verified");
    expect(supplierBadge({ label: "Verified", isVerified: true, isDemo: false }).text).toBe("Verified");
  });
  it("demo data is internally consistent", () => {
    for (const s of SUPPLIERS) {
      expect(VERIFICATION_LABELS).toContain(s.label);
      expect(s.isVerified).toBe(s.label === "Verified");
      if (s.label.startsWith("Unclaimed") || s.label === "Claim Requested") expect(s.isClaimed).toBe(false);
      expect(s.isDemo).toBe(true);
    }
  });
  it("unclaimed / unverified cards never contain the word Verified without 'not'", () => {
    for (const s of SUPPLIERS.filter((x) => !x.isVerified)) {
      const html = renderToStaticMarkup(<SupplierCard supplier={s} />).replace(/<[^>]+>/g, " ");
      expect(html.replace(/Not Verified/gi, "").replace(/Verification Pending/gi, "")).not.toMatch(/verified/i);
    }
  });
  it("unverified supplier profile says requirements are held, not passed on", async () => {
    const html = renderToStaticMarkup(await SupplierPage({ params: Promise.resolve({ slug: "illustrative-steel-fabricators" }) }));
    expect(html).toMatch(/not verified, so requirements are not passed to it directly/);
  });
});

describe("delivery wording", () => {
  it("never claims sent / delivered / received / contacted-as-fact", () => {
    for (const d of DELIVERY_STATES) {
      const t = `${DELIVERY_COPY[d].title} ${DELIVERY_COPY[d].body}`.toLowerCase();
      expect(t).not.toMatch(/\b(sent|delivered|received|has received|were sent)\b/);
    }
    expect(DELIVERY_COPY.visible_to_seller.body).toMatch(/cannot confirm/i);
    expect(DELIVERY_COPY.stored.body).toMatch(/No supplier has been contacted/);
  });
  it("renders the server wording", () => {
    render(<DeliveryStatus state="awaiting_admin" />);
    expect(screen.getByText(/not been passed to any company directly/)).toBeInTheDocument();
  });
  it("dashboard shell makes no delivery claim", () => {
    const text = renderToStaticMarkup(DashboardPage()).replace(/<[^>]+>/g, " ");
    expect(text).toMatch(/Nothing here means nothing has been delivered/);
    expect(text).not.toMatch(/\bwas delivered\b|\bhas been sent\b/i);
  });
  it("preview notice states nothing was sent", () => { expect(PREVIEW_NOTICE).toMatch(/nothing was sent/); });
});

describe("demo-data labelling", () => {
  it("every supplier card carries a Demo marker", () => {
    for (const s of SUPPLIERS) expect(renderToStaticMarkup(<SupplierCard supplier={s} />)).toContain("data-demo-badge");
  });
  it("every supplier profile and shell carries a Demo marker", async () => {
    for (const s of SUPPLIERS) expect(renderToStaticMarkup(await SupplierPage({ params: Promise.resolve({ slug: s.slug }) }))).toContain("data-demo-badge");
    expect(renderToStaticMarkup(DashboardPage())).toContain("data-demo-badge");
    expect(renderToStaticMarkup(LeadDeskPage())).toContain("data-demo-badge");
  });
  it("shells state that access control is not connected", () => {
    expect(renderToStaticMarkup(DashboardPage())).toMatch(/access control is not connected/);
    expect(renderToStaticMarkup(LeadDeskPage())).toMatch(/access control is not connected/);
  });
  it("demo badges are never a status tone and always say Sample label", () => {
    for (const s of SUPPLIERS) {
      const b = supplierBadge(s);
      expect(b.tone).toBe("sample");
      expect(b.text).toMatch(/^Sample label: /);
      expect(b.text).toMatch(/illustrative, not a real status/);
    }
  });
  it("no demo record carries the Verified label, and no demo card uses the success style or a bare 'Verified'", () => {
    for (const s of SUPPLIERS) {
      expect(s.label).not.toBe("Verified");
      expect(s.isVerified).toBe(false);
      const html = renderToStaticMarkup(<SupplierCard supplier={s} />);
      expect(html).toContain("border-dashed");
      expect(html).not.toContain("bg-success-100");
      expect(html.replace(/<[^>]+>/g, " ").replace(/Not Verified/g, "")).not.toMatch(/\bVerified\b/);
    }
  });
  it("the only way to get the green Verified badge is a real, non-demo verified record", () => {
    expect(supplierBadge({ label: "Verified", isVerified: true, isDemo: false })).toEqual({ text: "Verified", tone: "success" });
  });
  it("sample profile says nothing was checked", async () => {
    const html = renderToStaticMarkup(await SupplierPage({ params: Promise.resolve({ slug: "sample-loom-works" }) }));
    expect(html).toMatch(/Invented sample — no real verification/);
    expect(html).not.toMatch(/Verified profile/);
  });
});

describe("source hygiene", () => {
  it("app source has no backend wiring, secrets or storage use", async () => {
    const { execSync } = await import("node:child_process");
    const files = execSync("git ls-files -co --exclude-standard src", { encoding: "utf8" }).split("\n").filter((f) => /\.(ts|tsx)$/.test(f) && existsSync(f)); // tracked-but-deleted files are skipped
    expect(files.length).toBeGreaterThan(10);
    const fs = await import("node:fs");
    for (const f of files) {
      const t = fs.readFileSync(f, "utf8").replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");
      expect(t, f).not.toMatch(/supabase|createClient|service_role|process\.env(?!\.NODE_ENV)|localStorage|sessionStorage|document\.cookie|dangerouslySetInnerHTML|fetch\(/i);
    }
  });
});
