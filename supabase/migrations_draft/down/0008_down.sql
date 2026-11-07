-- DOWN for 0008_sequence_privileges: restores the staging ACLs (authenticated SELECT+USAGE on the six serial-style sequences; identity sequences owner-only).
-- The ALTER DEFAULT PRIVILEGES revoke is not reversed: the previous default ACL is platform state that this migration cannot know; leaving it narrow is the safe direction.
begin;
grant select, usage on sequence public.audit_log_id_seq, public.categories_id_seq, public.company_membership_audit_id_seq,
  public.enquiry_contact_access_id_seq, public.product_view_events_id_seq, public.rate_events_id_seq to authenticated;
commit;
