// evidence-link: issue short-lived signed URLs for claim evidence to ASSIGNED staff only.
// Pure handler: all I/O is injected (deps), so it is unit-testable without Deno or Supabase.
// STATUS: design + local unit tests only. Hosted Storage / signed-URL behaviour is NOT verified.
export const MAX_TTL = 600, DEFAULT_TTL = 120;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const json = (status, body) => ({ status, body });
export function decodeJwt(t) {
  try { const p = String(t).split('.'); if (p.length !== 3) return null; return JSON.parse(Buffer.from(p[1].replace(/-/g,'+').replace(/_/g,'/'), 'base64').toString('utf8')); } catch { return null; }
}
const SAFE_NAME = /^[A-Za-z0-9._-]{1,120}$/;

export async function handle(req, deps) {
  // 1. authentication: caller's own JWT is forwarded; the function never uses a service key to decide access
  const claims = decodeJwt(req.jwt);   // shape/expiry/role sanity only; SIGNATURE is verified by the platform (verify_jwt=true) and by auth.uid() inside the RPCs
  if (!claims || claims.role !== 'authenticated' || !claims.sub || (claims.exp && claims.exp * 1000 < (deps.now?.() ?? Date.now())))
    return json(401, { error: 'authentication required' });   // also rejects the public anon-key JWT
  const { claimId, evidenceIds, purpose } = req.body || {};
  let ttl = req.body?.ttlSeconds ?? DEFAULT_TTL;
  // 2. input validation
  if (!UUID.test(claimId || '')) return json(400, { error: 'invalid claimId' });
  if (!Array.isArray(evidenceIds) || evidenceIds.length < 1 || evidenceIds.length > 10 || !evidenceIds.every(i => UUID.test(i)))
    return json(400, { error: 'evidenceIds must be 1-10 uuids' });
  if (!Number.isInteger(ttl) || ttl < 1 || ttl > MAX_TTL) return json(400, { error: `ttlSeconds must be 1..${MAX_TTL}` });
  if (typeof purpose !== 'string' || purpose.trim().length < 5) return json(400, { error: 'purpose (min 5 chars) required' });
  // 3. ONE database call performs authorisation (assignment), rate limiting, id-ownership validation, grant creation and audit
  //    BEFORE any URL exists. Denials/rate limits are audited inside the database (non-raising), the response is deliberately generic.
  let rows;
  try { rows = await deps.requestLinks(req.jwt, claimId, evidenceIds, purpose.trim(), ttl); }
  catch (e) { return json(e?.kind === 'not_staff' ? 403 : 503, { error: e?.kind === 'not_staff' ? 'not authorised' : 'service unavailable' }); }
  const outcome = rows?.[0]?.outcome;
  if (outcome === 'rate_limited') return json(429, { error: 'too many requests, try later' });
  if (outcome === 'invalid') return json(400, { error: 'invalid request' });
  if (outcome !== 'ok') return json(403, { error: 'not authorised' });            // no ids, paths or reasons
  // 4. defence in depth: the returned set must be exactly what was asked for, and paths must be <claimId>/<plain name>
  const okPath = p => typeof p === 'string' && p.startsWith(claimId + '/') && SAFE_NAME.test(p.slice(claimId.length + 1)) && !p.includes('..');
  if (rows.length !== evidenceIds.length || !rows.every(r => evidenceIds.includes(r.evidence_id) && okPath(r.storage_path)))
    return json(502, { error: 'unexpected response' });
  // link lifetime never exceeds the audited grant (a signed URL is NOT re-checked when used)
  const grantLeft = Math.floor((Date.parse(rows[0].access_expires_at) - (deps.now?.() ?? Date.now())) / 1000);
  ttl = Math.min(ttl, rows[0].ttl_seconds ?? ttl, MAX_TTL, Number.isFinite(grantLeft) ? grantLeft : ttl);
  if (ttl < 1) return json(403, { error: 'not authorised' });
  // 5. signed URLs are created with the CALLER's JWT, so Storage policy (grant + assignment) is evaluated at creation
  const links = [];
  for (const r of rows) {
    let url;
    try { url = await deps.sign(req.jwt, r.storage_path, ttl); } catch (e) { return json(502, { error: 'could not create link' }); }
    if (!url) return json(403, { error: 'not authorised' });
    links.push({ evidenceId: r.evidence_id, url, expiresInSeconds: ttl });
  }
  return json(200, { links, note: 'links expire and cannot be revoked once issued; reopening requires a new audited call' });
}
