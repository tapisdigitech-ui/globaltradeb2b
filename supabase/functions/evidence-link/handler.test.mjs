import test from 'node:test'; import assert from 'node:assert/strict';
import { handle, MAX_TTL } from './handler.mjs';
const C='a1a00000-0000-0000-0000-000000000007', E1='e7e00000-0000-0000-0000-000000000001', E2='e7e00000-0000-0000-0000-000000000002';
const b64=o=>Buffer.from(JSON.stringify(o)).toString('base64url');
const JWT=(o={})=>`h.${b64({role:'authenticated',sub:'u1',exp:Math.floor(Date.now()/1000)+3600,...o})}.s`;
const mk = (o={}) => { const calls=[]; return { calls, deps: {
  openEvidence: async (...a)=>{calls.push(['open',...a]); if(o.deny) throw new Error('x'); return [{evidence_id:E1,storage_path:o.path||C+'/e.pdf',access_expires_at:new Date(Date.now()+(o.grantMs??600000)).toISOString()}];},
  sign: async (...a)=>{calls.push(['sign',...a]); if(o.signFail) throw new Error('s'); return o.refuse?null:'https://signed/'+a[1];},
  recordIssued: async (...a)=>{calls.push(['rec',...a]); if(o.recFail) throw new Error('r');} } }; };
const req = (b,jwt=JWT()) => ({ jwt, body: { claimId:C, evidenceIds:[E1], purpose:'review identity doc', ...b } });
test('401 without jwt', async()=>{ const {deps}=mk(); assert.equal((await handle(req({},null),deps)).status,401); });
test('400 bad ids/purpose/ttl', async()=>{ const {deps}=mk();
  for (const b of [{claimId:'x'},{evidenceIds:[]},{evidenceIds:['x']},{purpose:'abc'},{ttlSeconds:0},{ttlSeconds:MAX_TTL+1},{ttlSeconds:1.5}])
    assert.equal((await handle(req(b),deps)).status,400, JSON.stringify(b)); });
test('403 when SQL authorisation refuses; nothing signed', async()=>{ const {deps,calls}=mk({deny:true}); const r=await handle(req({}),deps);
  assert.equal(r.status,403); assert.ok(!calls.some(c=>c[0]==='sign')); });
test('404 cross-claim evidence id; nothing signed', async()=>{ const {deps,calls}=mk(); const r=await handle(req({evidenceIds:[E1,E2]}),deps);
  assert.equal(r.status,404); assert.ok(!calls.some(c=>c[0]==='sign')); });
test('200 default ttl 120, caller jwt forwarded, issuance recorded', async()=>{ const {deps,calls}=mk(); const r=await handle(req({}),deps);
  assert.equal(r.status,200); assert.equal(r.body.links[0].expiresInSeconds,120);
  assert.ok(calls.every(c=>typeof c[1]==='string')); assert.ok(calls.some(c=>c[0]==='rec'&&c[4]===120)); });
test('600 s accepted as maximum', async()=>{ const {deps}=mk(); assert.equal((await handle(req({ttlSeconds:600}),deps)).status,200); });
test('403 when storage refuses (grant expired/revoked); fail closed', async()=>{ const {deps}=mk({refuse:true}); const r=await handle(req({}),deps); assert.equal(r.status,403); assert.ok(!r.body.links); });
test('502 on signing error', async()=>{ const {deps}=mk({signFail:true}); assert.equal((await handle(req({}),deps)).status,502); });
test('links withheld when issuance cannot be audited', async()=>{ const {deps}=mk({recFail:true}); const r=await handle(req({}),deps); assert.equal(r.status,403); assert.ok(!r.body.links); });

test('401 for anon-key JWT, expired JWT, malformed token', async()=>{ const {deps}=mk();
  for (const j of [JWT({role:'anon'}),JWT({exp:1}),'garbage',JWT({sub:undefined})]) assert.equal((await handle(req({},j),deps)).status,401); });
test('ttl clamped to remaining grant lifetime', async()=>{ const {deps}=mk({grantMs:30000}); const r=await handle(req({ttlSeconds:600}),deps); assert.equal(r.status,200); assert.ok(r.body.links[0].expiresInSeconds<=30); });
test('403 when grant already expired', async()=>{ const {deps}=mk({grantMs:-1000}); assert.equal((await handle(req({}),deps)).status,403); });
test('unsafe storage paths are never signed', async()=>{ for (const p of [C+'/../x/e.pdf','other/e.pdf',C+'/a/b.pdf',C+'/']) { const {deps,calls}=mk({path:p}); const r=await handle(req({}),deps); assert.equal(r.status,404); assert.ok(!calls.some(c=>c[0]==='sign')); } });
