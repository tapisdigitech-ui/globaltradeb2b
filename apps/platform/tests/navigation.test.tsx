import "./helpers";
import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { SiteHeader } from "@/components/layout/SiteHeader";
import { navigationFor } from "@/lib/roles";
import { ROLES } from "@/lib/domain";

describe("navigation", () => {
  it("anonymous visitors see only public links and Sign in", () => {
    render(<SiteHeader role="anonymous" />);
    const nav = screen.getByRole("navigation", { name: "Main" });
    const names = within(nav).getAllByRole("link").map((a) => a.textContent);
    expect(names).toEqual(["Home", "Suppliers", "Post a requirement", "List your company", "Sign in"]);
    expect(within(nav).queryByText(/Lead Desk|dashboard/i)).toBeNull();
  });
  it("marks the current page", () => {
    render(<SiteHeader />);
    expect(screen.getByRole("link", { name: "Suppliers" })).toHaveAttribute("aria-current", "page");
    expect(screen.getByRole("link", { name: "Home" })).not.toHaveAttribute("aria-current");
  });
  it("mobile menu toggle exposes expanded state", async () => {
    render(<SiteHeader />);
    const btn = screen.getByRole("button", { name: "Menu" });
    expect(btn).toHaveAttribute("aria-expanded", "false");
    await userEvent.click(btn);
    expect(screen.getByRole("button", { name: "Close menu" })).toHaveAttribute("aria-expanded", "true");
  });
  it("every nav link resolves to an existing route", () => {
    const routes = new Set(["/", "/suppliers", "/requirements/new", "/register/supplier", "/login", "/dashboard", "/admin/lead-desk", "/register"]);
    for (const r of ROLES) for (const i of navigationFor(r)) expect(routes.has(i.href)).toBe(true);
  });
});

describe("role-based presentation", () => {
  it("only seller sees dashboard; only staff see Lead Desk; buyer/anonymous see neither", () => {
    const has = (r: (typeof ROLES)[number], href: string) => navigationFor(r).some((i) => i.href === href);
    expect(has("anonymous", "/dashboard") || has("buyer", "/dashboard")).toBe(false);
    expect(has("anonymous", "/admin/lead-desk") || has("buyer", "/admin/lead-desk") || has("seller", "/admin/lead-desk")).toBe(false);
    expect(has("seller", "/dashboard")).toBe(true);
    expect(has("reviewer", "/admin/lead-desk") && has("admin", "/admin/lead-desk")).toBe(true);
    expect(has("reviewer", "/dashboard") || has("admin", "/dashboard")).toBe(false);
  });
  it("the real layout always renders anonymous navigation (no session exists)", async () => {
    const fs = await import("node:fs");
    const src = fs.readFileSync("src/app/layout.tsx", "utf8");
    expect(src).toContain('<SiteHeader role="anonymous" />');
  });
});
