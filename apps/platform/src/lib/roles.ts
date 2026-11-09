import type { Role } from "./domain";

export type NavItem = { href: string; label: string };

const PUBLIC: NavItem[] = [
  { href: "/", label: "Home" },
  { href: "/suppliers", label: "Suppliers" },
  { href: "/requirements/new", label: "Post a requirement" },
];

/**
 * What each role would be shown. This is PRESENTATION only (contract §1.2):
 * the database decides what a role may read or write. Until a real session exists,
 * the app only ever renders the "anonymous" navigation; other roles are used for
 * previews and tests.
 */
export function navigationFor(role: Role): NavItem[] {
  switch (role) {
    case "anonymous":
      return [...PUBLIC, { href: "/register/supplier", label: "List your company" }];
    case "buyer":
      return [...PUBLIC];
    case "seller":
      return [...PUBLIC, { href: "/dashboard", label: "Supplier dashboard" }];
    case "reviewer":
    case "admin":
      return [...PUBLIC, { href: "/admin/lead-desk", label: "Lead Desk" }];
  }
}

export const ROLE_DESCRIPTION: Record<Role, string> = {
  anonymous: "Public visitor: directory and requirement form only.",
  buyer: "Buyer: own requirements and replies.",
  seller: "Supplier member of a claimed company: own listings and verified-only leads.",
  reviewer: "Staff reviewer: only assigned cases; purpose-logged access.",
  admin: "Administrator: all Lead Desk operations; audited.",
};
