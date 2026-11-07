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
    openEvidence: async (j, claimId, purpose) => { const { data, error } = await client(j).rpc('staff_open_claim_evidence', { p_claim: claimId, p_purpose: purpose }); if (error) throw error; return data; },
    sign: async (j, path, ttl) => { const { data, error } = await client(j).storage.from('verification-docs').createSignedUrl(path, ttl); if (error) return null; return data.signedUrl; },
    recordIssued: async (j, claimId, ids, ttl) => { const { error } = await client(j).rpc('staff_record_evidence_links', { p_claim: claimId, p_evidence_ids: ids, p_ttl: ttl }); if (error) throw error; },
  });
  return new Response(JSON.stringify(out.body), { status: out.status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });
});
