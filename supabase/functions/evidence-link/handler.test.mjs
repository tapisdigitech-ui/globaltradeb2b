import test from 'node:test'; import assert from 'node:assert/strict';
import { handle, MAX_TTL } from './handler.mjs';
const C='a1a00000-0000-0000-0000-000000000007', E1='e7e00000-0000-0000-0000-000000000001', E2='e7e00000-0000-0000-0000-000000000002';
const b64=o=>Buffer.from(JSON.stringify(o)).toString('base64url');
const JWT=(o={})=>`h.${b64({role:'authenticated',sub:'u1',exp:Math.floor(Date.now()/1000)+3600,...o})}.s`;
const mk=(o={})=>{const calls=[];return {calls,deps:{
  requestLinks:async(...a)=>{calls.push(['req',...a]); if(o.throw) throw o.throw;
    if(o.outcome) return [{outcome:o.outcome}];
    return (o.rows||[{evidence_id:E1,storage_path:o.path||C+'/e.pdf'}]).map(r=>({outcome:'ok',access_expires_at:new Date(Date.now()+(o.grantMs??600000)).toISOString(),ttl_seconds:a[4],...r}));},
  sign:async(...a)=>{calls.push(['sign',...a]); if(o.signFail) throw new Error('s'); return o.refuse?null:'https://signed/'+a[1];}}};};
const req=(b,jwt=JWT())=>({jwt,body:{claimId:C,evidenceIds:[E1],purpose:'review identity doc',...b}});
test('401 without/with bad JWT (anon key, expired, malformed)',async()=>{const {deps}=mk();for(const j of [null,JWT({role:'anon'}),JWT({exp:1}),'garbage',JWT({sub:undefined})])assert.equal((await handle(req({},j),deps)).status,401);});
test('400 bad input never reaches the database',async()=>{const {deps,calls}=mk();for(const b of [{claimId:'x'},{evidenceIds:[]},{evidenceIds:['x']},{purpose:'abc'},{ttlSeconds:0},{ttlSeconds:MAX_TTL+1},{ttlSeconds:1.5}])assert.equal((await handle(req(b),deps)).status,400,JSON.stringify(b));assert.equal(calls.length,0);});
test('denied -> generic 403, no ids/paths/reason in body',async()=>{const {deps,calls}=mk({outcome:'denied'});const r=await handle(req({}),deps);assert.equal(r.status,403);assert.deepEqual(r.body,{error:'not authorised'});assert.ok(!calls.some(c=>c[0]==='sign'));});
test('rate limited -> 429, invalid -> 400, nothing signed',async()=>{for(const [o,s] of [['rate_limited',429],['invalid',400]]){const {deps,calls}=mk({outcome:o});assert.equal((await handle(req({}),deps)).status,s);assert.ok(!calls.some(c=>c[0]==='sign'));}});
test('non-staff -> 403; database outage -> 503',async()=>{assert.equal((await handle(req({}),mk({throw:{kind:'not_staff'}}).deps)).status,403);assert.equal((await handle(req({}),mk({throw:{kind:'db'}}).deps)).status,503);});
test('200 default ttl 120, JWT forwarded, 2 ids',async()=>{const {deps,calls}=mk({rows:[{evidence_id:E1,storage_path:C+'/e1.pdf'},{evidence_id:E2,storage_path:C+'/e2.pdf'}]});const r=await handle(req({evidenceIds:[E1,E2]}),deps);assert.equal(r.status,200);assert.equal(r.body.links.length,2);assert.equal(r.body.links[0].expiresInSeconds,120);assert.ok(calls.every(c=>typeof c[1]==='string'));});
test('600 s accepted as maximum',async()=>{const r=await handle(req({ttlSeconds:600}),mk().deps);assert.equal(r.status,200);assert.ok(r.body.links[0].expiresInSeconds<=600);});
test('ttl clamped to remaining grant; expired grant refused',async()=>{let r=await handle(req({ttlSeconds:600}),mk({grantMs:30000}).deps);assert.ok(r.body.links[0].expiresInSeconds<=30);r=await handle(req({}),mk({grantMs:-1000}).deps);assert.equal(r.status,403);});
test('database result that differs from the request is rejected (defence in depth)',async()=>{assert.equal((await handle(req({}),mk({rows:[{evidence_id:E2,storage_path:C+'/e2.pdf'}]}).deps)).status,502);});
test('unsafe storage paths are never signed',async()=>{for(const p of [C+'/../x/e.pdf','other/e.pdf',C+'/a/b.pdf',C+'/']){const {deps,calls}=mk({path:p});assert.equal((await handle(req({}),deps)).status,502);assert.ok(!calls.some(c=>c[0]==='sign'));}});
test('storage refusal -> 403 and no partial links; sign error -> 502',async()=>{const r=await handle(req({}),mk({refuse:true}).deps);assert.equal(r.status,403);assert.ok(!r.body.links);assert.equal((await handle(req({}),mk({signFail:true}).deps)).status,502);});
