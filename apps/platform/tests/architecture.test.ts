import { execSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { buildCsp } from "@/lib/csp";

const files = execSync("git ls-files -co --exclude-standard src", { encoding: "utf8" }).split("\n").filter((f) => /\.(ts|tsx)$/.test(f) && existsSync(f));
const read = (f: string) => readFileSync(f, "utf8");
const code = (f: string) => read(f).replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");

describe("architecture boundaries", () => {
  it("every module under src/server starts with the server-only marker", () => {
    const server = files.filter((f) => f.startsWith("src/server/"));
    expect(server.length).toBeGreaterThan(8);
    for (const f of server) expect(read(f), f).toMatch(/^import "server-only";/);
  });
  it("no 'use client' file imports server code or private contracts", () => {
    for (const f of files.filter((x) => /^\s*["']use client["']/.test(read(x)))) expect(code(f), f).not.toMatch(/@\/server|contracts\/private/);
  });
  it("private contracts are imported only from src/server", () => {
    for (const f of files.filter((x) => !x.startsWith("src/server/") && x !== "src/contracts/private.ts")) expect(code(f), f).not.toMatch(/contracts\/private/);
  });
  it("pages do not import src/server yet (no route is wired to a guard or to services)", () => {
    for (const f of files.filter((x) => x.startsWith("src/app/"))) expect(code(f), f).not.toMatch(/@\/server/);
  });
  it("no Supabase client, network call, storage or credential code anywhere in src", () => {
    for (const f of files) expect(code(f), f).not.toMatch(/@supabase|createClient|service_role|fetch\(|XMLHttpRequest|WebSocket|localStorage|sessionStorage|document\.cookie|cookies\(\)|headers\(\)|process\.env(?!\.NODE_ENV)/);
  });
  it("package.json has no Supabase or database dependency", () => {
    const pkg = JSON.parse(read("package.json")) as { dependencies: Record<string, string>; devDependencies: Record<string, string> };
    const names = Object.keys({ ...pkg.dependencies, ...pkg.devDependencies });
    expect(names.filter((n) => /supabase|^pg$|postgres|prisma|drizzle|mongoose|knex/i.test(n))).toEqual([]);
  });
  it("src never contains an auth token, key, session literal or credential-shaped string", () => {
    for (const f of files) expect(code(f), f).not.toMatch(/eyJ[A-Za-z0-9_-]{10,}|sb_(publishable|secret)_|Bearer\s+[A-Za-z0-9._-]{10,}|password\s*[:=]\s*["'][^"']+["']/i);
  });
  it("only the 'not connected' provider exists in src (no session factory outside tests)", () => {
    const impls = files.filter((f) => /async\s+getAuthState\s*\(|getAuthState\s*:\s*async/.test(code(f)));
    expect(impls).toEqual(["src/server/auth/provider.ts"]);
    expect(code("src/server/auth/provider.ts")).toContain('status: "unavailable"');
  });
});

describe("CSP is not weakened", () => {
  it("production policy is exactly the Phase 1.1 policy", () => {
    expect(buildCsp("N", false)).toBe(
      "default-src 'self'; script-src 'self' 'nonce-N' 'strict-dynamic'; style-src 'self' 'nonce-N'; img-src 'self' data: blob:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'; manifest-src 'self'",
    );
  });
  it("proxy.ts and next.config.ts are unchanged in behaviour (nonce CSP set, headers kept)", () => {
    expect(read("src/proxy.ts")).toContain("buildCsp(nonce");
    const cfg = read("next.config.ts");
    for (const h of ["X-Content-Type-Options", "X-Frame-Options", "Referrer-Policy", "Cross-Origin-Opener-Policy", "Strict-Transport-Security"]) expect(cfg).toContain(h);
  });
});
