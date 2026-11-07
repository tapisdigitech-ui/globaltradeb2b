-- DOWN for the PROPOSAL 0008_admin_message_audit. Restores the 0006 policies (admin shortcut) and drops the proposal objects.
begin;
drop policy dt_read on public.direct_threads;
create policy dt_read on public.direct_threads for select using (buyer_id = auth.uid() or has_company_role(company_id, array['owner'::member_role,'manager'::member_role,'sales'::member_role]) or is_admin() or public.staff_thread_comms_ok(id));
drop policy dm_read on public.direct_messages;
create policy dm_read on public.direct_messages for select using (thread_buyer(thread_id) = auth.uid() or has_company_role(thread_company(thread_id), array['owner'::member_role,'manager'::member_role,'sales'::member_role]) or is_admin() or public.staff_thread_comms_ok(thread_id));
drop policy replies_read on public.enquiry_replies;
create policy replies_read on public.enquiry_replies for select using (enquiry_buyer(enquiry_id) = auth.uid() or seller_can_reply(enquiry_id) or is_admin() or public.comms_grant_active(enquiry_id));
drop policy quotes_read on public.quotations;
create policy quotes_read on public.quotations for select using (has_company_role(company_id, array['owner'::member_role,'manager'::member_role,'sales'::member_role]) or is_admin() or public.comms_grant_active(enquiry_id) or ((enquiry_buyer(enquiry_id) = auth.uid()) and (status = any (array['sent'::quote_status,'accepted'::quote_status,'declined'::quote_status,'expired'::quote_status]) or (status = 'withdrawn'::quote_status and sent_at is not null))));
drop function public.admin_open_comms(text, uuid, text);
drop function public.admin_comms_grant_active(text, uuid);
drop table public.admin_comms_grants;
drop table public.admin_comms_access_log;   -- audit history of admin message access under the proposal is lost: export first
commit;
