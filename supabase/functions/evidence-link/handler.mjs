// evidence-link: issue short-lived signed URLs for claim evidence to ASSIGNED staff only.
// Pure handler: all I/O is injected (deps), so it is unit-testable without Deno or Supabase.
// STATUS: design + local unit tests only. Hosted Storage / signed-URL behaviour is NOT verified.
export const MAX_TTL = 600, DEFAULT_TTL = 120;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const json = (status, body) => ({ status, body });

export async function handle(req, deps) {
  // 1. authentication: caller's own JWT is forwarded; the function never uses a service key to decide access
  if (!req.jwt) return json(401, { error: 'authentication required' });
  const { claimId, evidenceIds, purpose } = req.body || {};
  let ttl = req.body?.ttlSeconds ?? DEFAULT_TTL;
  // 2. input validation
  if (!UUID.test(claimId || '')) return json(400, { error: 'invalid claimId' });
  if (!Array.isArray(evidenceIds) || evidenceIds.length < 1 || evidenceIds.length > 10 || !evidenceIds.every(i => UUID.test(i)))
    return json(400, { error: 'evidenceIds must be 1-10 uuids' });
  if (!Number.isInteger(ttl) || ttl < 1 || ttl > MAX_TTL) return json(400, { error: `ttlSeconds must be 1..${MAX_TTL}` });
  if (typeof purpose !== 'string' || purpose.trim().length < 5) return json(400, { error: 'purpose (min 5 chars) required' });
  // 3. authorisation + grant: SQL function re-checks staff role, reviewer assignment, open claim; logs purpose; creates 10-min grant
  let rows;
  try { rows = await deps.openEvidence(req.jwt, claimId, purpose.trim()); }
  catch (e) { return json(403, { error: 'not authorised for this claim' }); }   // no detail leaked
  const allowed = new Map(rows.map(r => [r.evidence_id, r.storage_path]));
  const unknown = evidenceIds.filter(i => !allowed.has(i));
  if (unknown.length) return json(404, { error: 'evidence not found on this claim' });  // cross-claim ids rejected
  // 4. signed URLs generated with the CALLER's JWT so Storage RLS (grant + assignment re-check) is the enforcement point
  const links = [];
  for (const id of evidenceIds) {
    let url;
    try { url = await deps.sign(req.jwt, allowed.get(id), ttl); }
    catch (e) { return json(502, { error: 'could not create link' }); }   // fail closed, nothing partial returned
    if (!url) return json(403, { error: 'storage refused (grant expired or revoked)' });
    links.push({ evidenceId: id, url, expiresInSeconds: ttl });
  }
  // 5. audit issuance (grant must still be active; SQL function enforces ttl<=600)
  try { await deps.recordIssued(req.jwt, claimId, evidenceIds, ttl); }
  catch (e) { return json(403, { error: 'grant no longer active' }); }       // links are discarded, not returned
  return json(200, { links, note: 'links expire; reopening requires a new audited call' });
}
