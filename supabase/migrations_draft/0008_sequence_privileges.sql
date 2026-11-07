-- 0008_sequence_privileges.sql — DRAFT, LOCAL ONLY. Not applied to any Supabase project. Round 9 / B5.
-- Explicit sequence ACLs; the result must not depend on the platform's default privileges.
-- Audit (docs/SEQUENCE_ACL_AUDIT.md): 13 sequences = 7 identity + 6 serial-style.
--   * Identity sequences: INSERT into an identity column does not need USAGE on its sequence, and every one of those tables is written only by
--     SECURITY DEFINER functions / triggers (owner postgres). No application role needs any privilege.
--   * Serial-style sequences: only categories.id is written by an application role (admin via PostgREST, RLS categories_admin) -> keep USAGE for authenticated.
--     The other five tables are written only by definer functions/triggers; staging currently grants authenticated SELECT+USAGE on them, which lets any
--     signed-in user read last_value (activity volume of audit_log / rate_events / ...) and burn ids with nextval(). Revoked.
-- Behaviour change (documented): authenticated loses SELECT on categories_id_seq and all rights on the five other serial sequences.
begin;
revoke all on sequence
  public.audit_log_id_seq, public.buyer_contact_access_log_id_seq, public.categories_id_seq, public.claim_evidence_access_log_id_seq,
  public.company_import_audit_id_seq, public.company_membership_audit_id_seq, public.contact_access_log_id_seq, public.enquiry_contact_access_id_seq,
  public.lead_distribution_events_id_seq, public.lead_status_history_id_seq, public.product_view_events_id_seq, public.rate_events_id_seq,
  public.staff_comms_access_log_id_seq
  from public, anon, authenticated, service_role;
grant usage on sequence public.categories_id_seq to authenticated;
-- sequences created later by postgres in public must not inherit grants to the API roles either (no-op on platforms whose defaults are already narrow)
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated, service_role;
commit;
