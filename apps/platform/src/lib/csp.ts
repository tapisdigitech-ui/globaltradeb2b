/**
 * Content-Security-Policy builder (pure, unit-tested). Used by src/proxy.ts with a per-request nonce.
 *
 * Why this shape (Next.js 16 guide "Content Security Policy"):
 *  - script-src 'self' + nonce + 'strict-dynamic': Next attaches the request nonce to framework/page scripts;
 *    no 'unsafe-inline' in production. 'unsafe-eval' is added in development only (React debugging).
 *  - style-src 'self' + nonce: compiled Tailwind is a same-origin stylesheet; the app uses no inline style attributes.
 *  - img-src 'self' data: blob:; font-src 'self': no third-party images or fonts exist today.
 *  - connect-src 'self': no backend call exists. WHEN the backend is wired, add the exact Supabase project origin here
 *    (and nothing broader) in the same change that adds the first request.
 *  - frame-ancestors 'none', object-src 'none', base-uri 'self', form-action 'self'.
 * upgrade-insecure-requests is intentionally omitted (breaks plain-http local testing); HSTS covers production.
 */
export function buildCsp(nonce: string, isDev: boolean): string {
  const directives = [
    "default-src 'self'",
    `script-src 'self' 'nonce-${nonce}' 'strict-dynamic'${isDev ? " 'unsafe-eval'" : ""}`,
    `style-src 'self' 'nonce-${nonce}'`,
    "img-src 'self' data: blob:",
    "font-src 'self'",
    "connect-src 'self'",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    "manifest-src 'self'",
  ];
  return directives.join("; ");
}

export function newNonce(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  let bin = "";
  bytes.forEach((b) => { bin += String.fromCharCode(b); });
  return btoa(bin);
}
