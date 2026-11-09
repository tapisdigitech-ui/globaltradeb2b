import "server-only";
import { isEffectiveMember } from "@/contracts/claims";
import type { AuthState, SessionProvider } from "../auth/types";

/**
 * ROUTE-GUARD INTERFACES (not applied to any page yet).
 * A guard turns an AuthState into a decision. It does not authenticate anyone. With the only provider that exists today
 * ("not connected") EVERY guard denies, so wiring a page to a guard now would make that page unreachable, which is the
 * correct fail-closed behaviour. The demo shells at /dashboard and /admin/lead-desk are intentionally NOT guarded and
 * are labelled as unprotected previews; do not bind real data to them until they call a guard.
 */
export type RouteRequirement =
  | { readonly kind: "seller-dashboard" } // active member (owner/manager/sales/catalogue_editor/viewer) of an approved company
  | { readonly kind: "lead-desk" }; // reviewer or admin

export type RouteDecision =
  | { readonly outcome: "allow" }
  | { readonly outcome: "redirect-login" } // anonymous
  | { readonly outcome: "not-found" } // signed in but not entitled: do not reveal the route exists
  | { readonly outcome: "unavailable" }; // auth cannot answer: show an error page, never content

export function decideRoute(state: AuthState, req: RouteRequirement): RouteDecision {
  if (state.status === "unavailable") return { outcome: "unavailable" };
  if (state.status === "anonymous") return { outcome: "redirect-login" };
  const s = state.session;
  switch (req.kind) {
    case "seller-dashboard":
      return s.memberships.some(isEffectiveMember) ? { outcome: "allow" } : { outcome: "not-found" };
    case "lead-desk":
      return s.appRole === "reviewer" || s.appRole === "admin" ? { outcome: "allow" } : { outcome: "not-found" };
  }
}

/** What a page calls. Re-run on EVERY request (and again inside each server action / route handler). */
export async function guardRoute(provider: SessionProvider, req: RouteRequirement): Promise<RouteDecision> {
  return decideRoute(await provider.getAuthState(), req);
}

/** Cache rule for any page behind a guard. Never statically render or share-cache authenticated content. */
export const AUTHENTICATED_PAGE_CACHE = "private, no-store" as const;
