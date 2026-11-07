begin;
drop function if exists public.staff_add_contact(uuid,text,text,public.source_type,text,text,text,uuid,uuid), public.staff_get_contacts(uuid,text,uuid,uuid), public.staff_set_contact_status(uuid,text,text,uuid,uuid);
commit;
