import { test, expect, type Page } from "@playwright/test";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
const req = createRequire(process.cwd() + "/package.json");

const axeSource = readFileSync(req.resolve("axe-core/axe.min.js"), "utf8");
const ROUTES = ["/", "/suppliers", "/suppliers/sample-loom-works", "/suppliers/illustrative-steel-fabricators", "/requirements/new", "/register/supplier", "/register", "/login", "/dashboard", "/admin/lead-desk"];
const WIDTHS = [320, 390, 768, 1280];

// The app must never need the network: block everything that is not the local server.
test.beforeEach(async ({ page }) => {
  await page.route(/^https?:\/\/(?!127\.0\.0\.1)/, (r) => r.abort());
});

async function axe(page: Page) {
  await page.evaluate(axeSource);
  return page.evaluate(async () => {
    // @ts-expect-error injected global
    const r = await window.axe.run(document, { runOnly: ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"] });
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

test("accessibility: no WCAG 2.1 AA violations on any route (axe, incl. colour contrast)", async ({ page }) => {
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
  await expect(page.getByRole("article")).toHaveCount(1);
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
