import "./helpers";
import { renderToStaticMarkup } from "react-dom/server";
import { render, screen } from "@testing-library/react";
import { buildCsp, newNonce } from "@/lib/csp";
import TermsPage from "@/app/legal/terms/page";
import PrivacyPage from "@/app/legal/privacy/page";
import { RequirementForm } from "@/features/requirements/RequirementForm";
import { AccountForm } from "@/features/auth/AccountForm";
import { SupplierRegistrationForm } from "@/features/suppliers/SupplierRegistrationForm";
import config from "../next.config";

describe("CSP builder", () => {
  const prod = buildCsp("abc123", false);
  const dev = buildCsp("abc123", true);
  it("production policy has nonce, strict-dynamic and no unsafe-inline/eval", () => {
    expect(prod).toContain("script-src 'self' 'nonce-abc123' 'strict-dynamic'");
    expect(prod).not.toMatch(/unsafe-inline|unsafe-eval/);
    expect(prod).toContain("style-src 'self' 'nonce-abc123'");
  });
  it("development alone allows unsafe-eval", () => { expect(dev).toContain("'unsafe-eval'"); });
  it("locks down framing, plugins, base, forms and network", () => {
    for (const d of ["default-src 'self'", "frame-ancestors 'none'", "object-src 'none'", "base-uri 'self'", "form-action 'self'", "connect-src 'self'", "img-src 'self' data: blob:", "font-src 'self'"])
      expect(prod).toContain(d);
    expect(prod).not.toMatch(/https?:|\*/);
  });
  it("nonces are unique, unguessable-length and base64", () => {
    const a = newNonce(), b = newNonce();
    expect(a).not.toBe(b); expect(a).toMatch(/^[A-Za-z0-9+/]{22}==$/);
  });
});

describe("static security headers", () => {
  it("are configured for every path", async () => {
    const rules = await config.headers!();
    const h = Object.fromEntries(rules.find((r) => r.source === "/:path*")!.headers.map((x) => [x.key, x.value]));
    expect(h["X-Content-Type-Options"]).toBe("nosniff");
    expect(h["X-Frame-Options"]).toBe("DENY");
    expect(h["Referrer-Policy"]).toBe("strict-origin-when-cross-origin");
    expect(h["Cross-Origin-Opener-Policy"]).toBe("same-origin");
    expect(h["Strict-Transport-Security"]).toMatch(/^max-age=\d+$/);
    expect(h["Permissions-Policy"]).toMatch(/camera=\(\)/);
  });
});

describe("legal content is draft only", () => {
  it("terms and privacy pages say draft / not legal advice and contain no invented policy", () => {
    for (const P of [TermsPage, PrivacyPage]) {
      const html = renderToStaticMarkup(P());
      expect(html).toMatch(/DRAFT placeholder — not legal advice/);
      expect(html).toMatch(/counsel/i);
      expect(html).not.toMatch(/\bwe (will|shall|may) (not )?(sell|share|retain|delete)\b/i);
      expect(html).not.toMatch(/governed by the laws of/i);
    }
  });
  it("every consent checkbox is tagged draft and links to a draft page", () => {
    for (const C of [RequirementForm, AccountForm, SupplierRegistrationForm]) {
      const { unmount } = render(<C />);
      const cb = screen.getByRole("checkbox");
      const label = document.querySelector(`label[for="${cb.id}"]`)!;
      expect(label.textContent).toMatch(/Draft wording — pending legal review/);
      expect(label.querySelector('a[href^="/legal/"]')).not.toBeNull();
      unmount();
    }
  });
});
