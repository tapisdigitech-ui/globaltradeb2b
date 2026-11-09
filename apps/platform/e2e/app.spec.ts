import { test, expect, type Page } from "@playwright/test";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
const req = createRequire(process.cwd() + "/package.json");

const axeSource = readFileSync(req.resolve("axe-core/axe.min.js"), "utf8");
const ROUTES = ["/", "/suppliers", "/suppliers/sample-loom-works", "/suppliers/illustrative-steel-fabricators", "/requirements/new", "/register/supplier", "/register", "/login", "/dashboard", "/admin/lead-desk", "/legal/terms", "/legal/privacy"];
const WIDTHS = [320, 360, 390, 768, 1280];

// The app must never need the network: block everything that is not the local server.
test.beforeEach(async ({ page }) => {
  await page.route(/^https?:\/\/(?!127\.0\.0\.1)/, (r) => r.abort());
});

async function axe(page: Page) {
  await page.evaluate(axeSource);
  return page.evaluate(async () => {
    // @ts-expect-error injected global
    const r = await window.axe.run(document, { runOnly: ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"] });
    return r.violations.map((v: { id: string; impact: string; nodes: { target: unknown }[] }) => `${v.id} (${v.impact}) x${v.nodes.length}`);
  });
}

for (const w of WIDTHS) {
  test(`responsive: no horizontal overflow at ${w}px`, async ({ page }) => {
    await page.setViewportSize({ width: w, height: 800 });
    for (const r of ROUTES) {
      await page.goto(r);
      const over = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
      expect(over, `${r} at ${w}px`).toBeLessThanOrEqual(0);
    }
  });
}

test("accessibility: no WCAG 2.2 AA violations on any route (axe, incl. colour contrast and target size)", async ({ page }) => {
  for (const r of ROUTES) {
    await page.goto(r);
    expect(await axe(page), r).toEqual([]);
  }
});

test("every route has one h1, lang, title, skip link and a main landmark", async ({ page }) => {
  for (const r of ROUTES) {
    await page.goto(r);
    await expect(page.locator("h1")).toHaveCount(1);
    await expect(page.locator("html")).toHaveAttribute("lang", "en");
    expect(await page.title()).toContain("GlobalTradeB2B");
    await expect(page.locator("main#main")).toHaveCount(1);
    await expect(page.getByRole("link", { name: "Skip to main content" })).toHaveCount(1);
    await expect(page.locator("[data-demo-banner]")).toHaveCount(1);
  }
});

test("navigation: header links reach their pages", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto("/");
  const nav = page.getByRole("navigation", { name: "Main" });
  for (const [name, url] of [["Suppliers", "/suppliers"], ["Post a requirement", "/requirements/new"], ["List your company", "/register/supplier"], ["Sign in", "/login"]] as const) {
    await nav.getByRole("link", { name }).click();
    await expect(page).toHaveURL(new RegExp(url + "$"));
    await expect(nav.getByRole("link", { name })).toHaveAttribute("aria-current", "page");
  }
  await page.goto("/suppliers");
  await page.getByRole("link", { name: "Sample Loom Works" }).click();
  await expect(page).toHaveURL(/\/suppliers\/sample-loom-works$/);
});

test("mobile menu opens and closes", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 800 });
  await page.goto("/");
  const nav = page.getByRole("navigation", { name: "Main" });
  await expect(nav).toBeHidden();
  await page.getByRole("button", { name: "Menu" }).click();
  await expect(nav).toBeVisible();
  await page.getByRole("button", { name: "Close menu" }).click();
  await expect(nav).toBeHidden();
});

test("directory: filters work and an empty result shows the empty state", async ({ page }) => {
  await page.goto("/suppliers?label=Verified");
  await expect(page.getByRole("article")).toHaveCount(0); // no sample record is labelled Verified
  await expect(page.getByText("No suppliers match")).toBeVisible();
  await page.goto("/suppliers?label=Claim%20Requested");
  await expect(page.getByRole("article")).toHaveCount(2);
  await page.goto("/suppliers?q=zzzzzz");
  await expect(page.getByText("No suppliers match")).toBeVisible();
});

test("unknown supplier returns the not-found page", async ({ page }) => {
  const res = await page.goto("/suppliers/does-not-exist");
  expect(res?.status()).toBe(404);
  await expect(page.getByText("Page not found")).toBeVisible();
});

test("public pages expose no contact data in the rendered DOM", async ({ page }) => {
  for (const r of ROUTES.filter((x) => x.startsWith("/suppliers") || x === "/")) {
    await page.goto(r);
    const html = await page.content();
    expect(html).not.toMatch(/href="(mailto|tel):/i);
    const text = await page.locator("body").innerText();
    expect(text).not.toMatch(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i);
    expect(text).not.toMatch(/(\+\d[\d\s().-]{7,}\d)|(\b\d{10}\b)/);
  }
});

test("requirement form: validation, focus, and preview-only success", async ({ page }) => {
  await page.goto("/requirements/new");
  await page.getByRole("button", { name: "Preview requirement" }).click();
  await expect(page.getByLabel(/Product or service needed/)).toBeFocused();
  await expect(page.getByLabel(/Product or service needed/)).toHaveAttribute("aria-invalid", "true");
  await page.getByLabel(/Product or service needed/).fill("Hand tufted rugs");
  await page.getByLabel(/^Quantity/).fill("500 pieces");
  await page.getByLabel(/Delivery city/).fill("Sample City");
  await page.getByLabel(/Your name/).fill("Asha Rao");
  await page.getByLabel(/Mobile number/).fill("+91 98765 43210");
  await page.getByRole("checkbox").check();
  const requests: string[] = [];
  page.on("request", (q) => { if (q.method() !== "GET") requests.push(q.url()); });
  await page.getByRole("button", { name: "Preview requirement" }).click();
  await expect(page.getByText(/Preview complete/)).toBeVisible();
  expect(requests).toEqual([]);
  await expect(page.getByLabel(/Mobile number/)).toHaveValue("");
});

test("shells state they are not access-controlled and show demo markers", async ({ page }) => {
  for (const r of ["/dashboard", "/admin/lead-desk"]) {
    await page.goto(r);
    await expect(page.getByText("Preview shell — access control is not connected")).toBeVisible();
    await expect(page.locator("[data-demo-badge]").first()).toBeVisible();
    await expect(page.getByRole("link", { name: /Lead Desk|Supplier dashboard/ })).toHaveCount(0); // nav is anonymous
  }
});

test("security headers and a nonce-based CSP are served on every route", async ({ request }) => {
  for (const r of ROUTES) {
    const res = await request.get(r);
    const h = res.headers();
    const csp = h["content-security-policy"] ?? "";
    expect(csp, r).toMatch(/script-src 'self' 'nonce-[A-Za-z0-9+/=]+' 'strict-dynamic'/);
    expect(csp, r).not.toMatch(/unsafe-inline|unsafe-eval/);
    expect(csp).toContain("frame-ancestors 'none'");
    expect(h["x-content-type-options"]).toBe("nosniff");
    expect(h["x-frame-options"]).toBe("DENY");
    expect(h["referrer-policy"]).toBe("strict-origin-when-cross-origin");
    expect(h["cross-origin-opener-policy"]).toBe("same-origin");
    expect(h["strict-transport-security"]).toMatch(/max-age=/);
    expect(h["x-powered-by"]).toBeUndefined();
  }
});

test("nonce differs per request and is applied to scripts", async ({ request }) => {
  const nonceOf = async () => /'nonce-([^']+)'/.exec((await request.get("/")).headers()["content-security-policy"] ?? "")?.[1];
  const a = await nonceOf(), b = await nonceOf();
  expect(a).toBeTruthy(); expect(a).not.toBe(b);
  const html = await (await request.get("/")).text();
  const scripts = [...html.matchAll(/<script\b[^>]*>/g)].map((m) => m[0]);
  expect(scripts.length).toBeGreaterThan(0);
  for (const t of scripts) expect(t, t).toMatch(/nonce="|src="\/_next\//);
});

test("no CSP violations, console errors or external requests while browsing and submitting forms", async ({ page }) => {
  const problems: string[] = [];
  page.on("console", (m) => { if (m.type() === "error" || m.type() === "warning") problems.push(`${m.type()}: ${m.text()}`); });
  page.on("pageerror", (e) => problems.push(`pageerror: ${e.message}`));
  await page.addInitScript(() => document.addEventListener("securitypolicyviolation", (e) => console.error("CSP violation: " + e.violatedDirective + " " + e.blockedURI)));
  const external: string[] = [];
  page.on("request", (q) => { if (!q.url().startsWith("http://127.0.0.1:3100")) external.push(q.url()); });
  for (const r of ROUTES) { await page.goto(r); await page.waitForLoadState("networkidle"); }
  await page.goto("/requirements/new");
  await page.getByRole("button", { name: "Preview requirement" }).click();
  await page.getByRole("button", { name: "Menu" }).isVisible();
  expect(problems).toEqual([]);
  expect(external).toEqual([]);
});

test("keyboard: skip link is first tab stop and moves focus to main", async ({ page }) => {
  await page.goto("/suppliers");
  await page.keyboard.press("Tab");
  const skip = page.getByRole("link", { name: "Skip to main content" });
  await expect(skip).toBeFocused();
  await expect(skip).toBeVisible();
  await page.keyboard.press("Enter");
  await expect(page.locator("main#main")).toBeFocused();
});

test("mobile touch targets: header controls and form controls are at least 44px tall", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 800 });
  await page.goto("/requirements/new");
  const menu = await page.getByRole("button", { name: "Menu" }).boundingBox();
  expect(menu!.height).toBeGreaterThanOrEqual(44);
  for (const loc of [page.getByLabel(/Product or service needed/), page.getByLabel(/^Quantity/), page.getByRole("button", { name: "Preview requirement" })]) {
    expect((await loc.boundingBox())!.height).toBeGreaterThanOrEqual(44);
  }
});

test("demo badges are dashed 'Sample label' and never the green Verified style; no demo record is labelled Verified", async ({ page }) => {
  await page.goto("/suppliers");
  const badges = page.getByRole("article").locator("span", { hasText: "Sample label:" });
  await expect(badges).toHaveCount(6);
  for (let i = 0; i < 6; i++) {
    const style = await badges.nth(i).evaluate((el) => { const c = getComputedStyle(el); return { border: c.borderTopStyle, bg: c.backgroundColor, font: c.fontStyle }; });
    expect(style.border).toBe("dashed");
    expect(style.font).toBe("italic");
    expect(style.bg).not.toBe("rgb(220, 252, 231)"); // success-100
  }
  const text = await page.getByRole("article").allInnerTexts();
  for (const t of text) expect(t.replace(/Not Verified/g, "")).not.toMatch(/\bVerified\b/);
});

test("legal pages are labelled draft, not legal advice; consent boxes link to them", async ({ page }) => {
  for (const r of ["/legal/terms", "/legal/privacy"]) {
    await page.goto(r);
    await expect(page.getByText("DRAFT placeholder — not legal advice")).toBeVisible();
  }
  await page.goto("/requirements/new");
  await expect(page.getByText("[Draft wording — pending legal review]")).toBeVisible();
  await expect(page.getByRole("link", { name: "privacy notice" })).toHaveAttribute("href", "/legal/privacy");
});

test("zoom/reflow: 320px wide with 200% text size has no horizontal page overflow on any route", async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 640 });
  for (const r of ROUTES) {
    await page.goto(r);
    await page.evaluate(() => { document.documentElement.style.fontSize = "32px"; }); // CSSOM change: allowed under style-src
    expect(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth), r).toBeLessThanOrEqual(0);
  }
});
