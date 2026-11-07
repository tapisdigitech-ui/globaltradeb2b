// Deno wiring for Supabase Edge Functions. NOT DEPLOYED. Not tested against hosted Supabase.
import { createClient } from 'npm:@supabase/supabase-js@2';
import { handle } from './handler.mjs';
const URL = Deno.env.get('SUPABASE_URL')!, ANON = Deno.env.get('SUPABASE_ANON_KEY')!;  // anon key only: no service role
const client = (jwt: string) => createClient(URL, ANON, { global: { headers: { Authorization: `Bearer ${jwt}` } }, auth: { persistSession: false } });
Deno.serve(async (r) => {
  if (r.method !== 'POST') return new Response('method not allowed', { status: 405 });
  const jwt = (r.headers.get('Authorization') || '').replace(/^Bearer /, '') || null;
  const body = await r.json().catch(() => null);
  const out = await handle({ jwt, body }, {
    requestLinks: async (j, claimId, ids, purpose, ttl) => { const { data, error } = await client(j).rpc('staff_request_evidence_links', { p_claim: claimId, p_evidence_ids: ids, p_purpose: purpose, p_ttl: ttl }); if (error) { const e: any = new Error('rpc'); const st = (error as any).status; e.kind = (st === 401 || /^PGRST30[0-9]$/.test((error as any).code || '') || /JWT/i.test(error.message || '')) ? 'unauthenticated' : error.message?.includes('staff only') ? 'not_staff' : 'db'; throw e; } return data; },
    sign: async (j, path, ttl) => { const { data, error } = await client(j).storage.from('verification-docs').createSignedUrl(path, ttl); if (error) return null; return data.signedUrl; },
  });
  return new Response(JSON.stringify(out.body), { status: out.status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });
});
