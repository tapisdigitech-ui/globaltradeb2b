import "server-only";
import type { AuthState, SessionProvider } from "./types";

/**
 * The only SessionProvider that exists today. Authentication is NOT connected, so it answers "unavailable" for every
 * request. It never returns anonymous or authenticated, so no code path can be tricked into believing a session exists.
 * Phase 2 replaces this with a provider that validates a Supabase Auth session server-side.
 */
export const notConnectedSessionProvider: SessionProvider = {
  async getAuthState(): Promise<AuthState> {
    return { status: "unavailable" };
  },
};
