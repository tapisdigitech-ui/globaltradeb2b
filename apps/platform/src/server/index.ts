import "server-only";
import { notConnectedSessionProvider } from "./auth/provider";
import { notConnectedDataAccess } from "./data/not-connected";
import { createServices } from "./services";

export { evaluate, can } from "./access/policy";
export { decideRoute, guardRoute, AUTHENTICATED_PAGE_CACHE } from "./access/route-guards";
export type { RouteRequirement, RouteDecision } from "./access/route-guards";
export type { AuthState, Session, SessionProvider } from "./auth/types";
export { createServices } from "./services";

/** The only wiring that exists today: nothing is connected, so every protected call returns an error code. */
export const services = createServices(notConnectedSessionProvider, notConnectedDataAccess);
