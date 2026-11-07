// B4: platform-gateway (verify_jwt) vs function-enforced checks. The gateway is EMULATED here (HS256 signature + exp, as the Supabase Edge gateway does when verify_jwt=true);
// the real gateway cannot run locally. All tokens are synthetic and signed with a throw-away secret.
import test from 'node:test'; import assert from 'node:assert/strict'; import crypto from 'node:crypto'; import fs from 'node:fs';
import { handle } from './handler.mjs';
const SECRET = 'local-throwaway-secret-not-a-supabase-key', NOW = () => Math.floor(Date.now() / 1000);
const b = o => Buffer.from(JSON.stringify(o)).toString('base64url');
const mint = (claims, secret = SECRET, alg = 'HS256') => { const seg = b({ alg, typ: 'JWT' }) + '.' + b(claims); return seg + '.' + (alg === 'none' ? '' : crypto.createHmac('sha256', secret).update(seg).digest('base64url')); };
const U = { buyer: 'b0000000-0000-0000-0000-00000000e001', rev: 'b0000000-0000-0000-0000-00000000e0b1', rev2: 'b0000000-0000-0000-0000-00000000e0b2', admin: 'b0000000-0000-0000-0000-00000000e0a1' };
const tok = (sub, o = {}) => mint({ role: 'authenticated', aud: 'authenticated', sub, exp: NOW() + 600, ...o });
// gateway emulation: returns null when the request may proceed, else a response
function gateway(jwt, { verify_jwt = true } = {}) {
  if (!verify_jwt) return null;
  if (!jwt) return { status: 401, body: { msg: 'Missing authorization header' } };
  const p = jwt.split('.'); if (p.length !== 3) return { status: 401, body: { msg: 'Invalid JWT' } };
  let h; try { h = JSON.parse(Buffer.from(p[0], 'base64url')); } catch { return { status: 401, body: { msg: 'Invalid JWT' } }; }
  if (h.alg !== 'HS256') return { status: 401, body: { msg: 'Invalid JWT' } };
  const good = crypto.createHmac('sha256', SECRET).update(p[0] + '.' + p[1]).digest('base64url');
  if (good.length !== p[2].length || !crypto.timingSafeEqual(Buffer.from(good), Buffer.from(p[2]))) return { status: 401, body: { msg: 'Invalid JWT' } };
  const c = JSON.parse(Buffer.from(p[1], 'base64url')); if (c.exp && c.exp <= NOW()) return { status: 401, body: { msg: 'JWT expired' } };
  return null;
}
// fake PostgREST+DB behind the function: staff/assignment/grant decisions mirror what the SQL matrix proves (tests/jwt/test_evidence_link_db.py)
const C = 'a1a00000-0000-0000-0000-0000000e0c01', E1 = 'e7e00000-0000-0000-0000-0000000e0001';
function world({ staff = [], assigned = [], revoked = [], grantMs = 600000, dbVerifies = true } = {}) {
  const calls = []; return { calls, deps: {
    requestLinks: async (jwt, claimId, ids) => {
      calls.push('rpc');
      const p = jwt.split('.'); const good = crypto.createHmac('sha256', SECRET).update(p[0] + '.' + p[1]).digest('base64url');
      if (dbVerifies && good !== p[2]) { const e = new Error('jwt'); e.kind = 'unauthenticated'; throw e; }
      const sub = JSON.parse(Buffer.from(p[1], 'base64url')).sub;
      if (!staff.includes(sub)) { const e = new Error('x'); e.kind = 'not_staff'; throw e; }
      if (revoked.includes(sub) || !(assigned.includes(sub) || sub === U.admin)) return [{ outcome: 'denied' }];
      return ids.map(id => ({ outcome: 'ok', evidence_id: id, storage_path: C + '/e1.pdf', access_expires_at: new Date(Date.now() + grantMs).toISOString(), ttl_seconds: 120 }));
    },
    sign: async () => { calls.push('sign'); return 'https://signed.invalid/x'; } } };
}
const body = { claimId: C, evidenceIds: [E1], purpose: 'matrix review check' };
async function edge(jwt, w, opts) { const g = gateway(jwt, opts); if (g) return { ...g, viaGateway: true }; return handle({ jwt, body }, w.deps); }
const full = () => world({ staff: [U.rev, U.rev2, U.admin], assigned: [U.rev] });

test('config.toml pins verify_jwt=true for evidence-link explicitly', () => {
  const t = fs.readFileSync(new URL('../../config.toml', import.meta.url), 'utf8');
  const sec = t.split('[functions.evidence-link]')[1]?.split(/\n\[/)[0] || '';
  assert.match(sec, /^\s*verify_jwt\s*=\s*true\s*$/m);
});
test('missing token: gateway 401, function never invoked', async () => { const w = full(); const r = await edge(null, w); assert.equal(r.status, 401); assert.ok(r.viaGateway); assert.deepEqual(w.calls, []); });
test('invalid tokens (malformed, bad signature, alg none, HS512): gateway 401', async () => {
  for (const j of ['abc', 'a.b.c', tok(U.rev, {}).slice(0, -3) + 'AAA', mint({ role: 'authenticated', sub: U.rev, exp: NOW() + 60 }, SECRET, 'none'), tok(U.rev, {}).replace(/^[^.]+/, b({ alg: 'HS512', typ: 'JWT' }))]) {
    const w = full(); const r = await edge(j, w); assert.equal(r.status, 401, j); assert.ok(r.viaGateway); assert.deepEqual(w.calls, []); } });
test('forged signature on an assigned reviewer sub: gateway 401', async () => { const w = full(); const r = await edge(mint({ role: 'authenticated', sub: U.rev, aud: 'authenticated', exp: NOW() + 60 }, 'attacker-secret'), w); assert.equal(r.status, 401); assert.deepEqual(w.calls, []); });
test('expired token: gateway 401; and with the gateway OFF the function itself still returns 401 (independent expiry check)', async () => {
  const j = tok(U.rev, { exp: NOW() - 10 });
  let w = full(); assert.equal((await edge(j, w)).status, 401); assert.deepEqual(w.calls, []);
  w = full(); const r = await edge(j, w, { verify_jwt: false }); assert.equal(r.status, 401); assert.ok(!r.viaGateway); assert.deepEqual(w.calls, []); });
test('anonymous (public anon-key JWT) PASSES the gateway but the function rejects it (gateway proves a platform key, not a user)', async () => {
  const j = mint({ role: 'anon', aud: 'anon', exp: NOW() + 600 }); assert.equal(gateway(j), null);
  const w = full(); const r = await edge(j, w); assert.equal(r.status, 401); assert.ok(!r.viaGateway); assert.deepEqual(w.calls, []); });
test('service_role JWT passes the gateway; function rejects it (role must be authenticated, sub required) -- no service key is ever used to decide access', async () => {
  const j = mint({ role: 'service_role', exp: NOW() + 600 }); assert.equal(gateway(j), null);
  const w = full(); assert.equal((await edge(j, w)).status, 401); assert.deepEqual(w.calls, []); });
test('authenticated but non-staff (buyer/claimant): 403, nothing signed', async () => { const w = full(); const r = await edge(tok(U.buyer), w); assert.equal(r.status, 403); assert.ok(!w.calls.includes('sign')); });
test('metadata claiming staff does not help a non-staff caller (authority is database state)', async () => { const w = full(); const r = await edge(tok(U.buyer, { app_metadata: { role: 'admin' }, user_metadata: { app_role: 'admin' } }), w); assert.equal(r.status, 403); assert.ok(!w.calls.includes('sign')); });
test('authenticated staff NOT assigned: generic 403 (denied outcome), nothing signed', async () => { const w = full(); const r = await edge(tok(U.rev2), w); assert.equal(r.status, 403); assert.deepEqual(r.body, { error: 'not authorised' }); assert.ok(!w.calls.includes('sign')); });
test('assigned reviewer: 200 with signed link', async () => { const w = full(); const r = await edge(tok(U.rev), w); assert.equal(r.status, 200); assert.equal(r.body.links.length, 1); assert.ok(w.calls.includes('sign')); });
test('administrator: 200 with signed link', async () => { const w = full(); const r = await edge(tok(U.admin), w); assert.equal(r.status, 200); assert.ok(w.calls.includes('sign')); });
test('revoked assignment: 403 even with a valid unexpired JWT, nothing signed', async () => { const w = world({ staff: [U.rev], assigned: [U.rev], revoked: [U.rev] }); const r = await edge(tok(U.rev), w); assert.equal(r.status, 403); assert.ok(!w.calls.includes('sign')); });
test('expired evidence grant (remaining lifetime <= 0): 403, nothing signed; short remaining grant clamps ttl', async () => {
  let w = world({ staff: [U.rev], assigned: [U.rev], grantMs: -1000 }); assert.equal((await edge(tok(U.rev), w)).status, 403); assert.ok(!w.calls.includes('sign'));
  w = world({ staff: [U.rev], assigned: [U.rev], grantMs: 20000 }); const r = await edge(tok(U.rev), w); assert.equal(r.status, 200); assert.ok(r.body.links[0].expiresInSeconds <= 20); });
test('defence in depth with verify_jwt=false: a forged-signature token passes the function’s own claim checks but the DATABASE layer rejects it -> 401, nothing signed', async () => {
  const forged = mint({ role: 'authenticated', aud: 'authenticated', sub: U.rev, exp: NOW() + 600 }, 'attacker-secret');
  const w = full(); const r = await edge(forged, w, { verify_jwt: false }); assert.equal(r.status, 401); assert.deepEqual(w.calls, ['rpc']);
});
test('LIMIT (documented): with verify_jwt=false AND a database layer that did not verify, the function alone would trust unsigned claims -> that is why verify_jwt must stay true', async () => {
  const forged = mint({ role: 'authenticated', aud: 'authenticated', sub: U.rev, exp: NOW() + 600 }, 'attacker-secret');
  const w = world({ staff: [U.rev], assigned: [U.rev], dbVerifies: false }); const r = await edge(forged, w, { verify_jwt: false });
  assert.equal(r.status, 200, 'function does not verify signatures itself; this is the documented residual reliance on the gateway + PostgREST');
});
