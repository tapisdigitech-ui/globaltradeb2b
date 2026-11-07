-- 0009_url_validation_PROPOSAL.sql — PROPOSAL ONLY (not in migrations_draft/, applied nowhere). Database-boundary URL rules; see docs/URL_FIELD_INVENTORY.md.
-- All constraints are NOT VALID: new/updated rows are checked, legacy rows are not scanned (VALIDATE later, after a read-only count of violators).
begin;
-- Rule 1 "web link": http(s) only, no whitespace/control characters, 8..500 chars. Used where the value may be rendered as a clickable link.
create function public.is_http_url(u text) returns boolean language sql immutable parallel safe set search_path = '' as $$
  select u is not null and length(u) between 8 and 500 and u ~* '^https?://[^[:space:][:cntrl:]<>"'']+$' and u !~* '^https?://[^/]*@' $$;   -- no userinfo (user:pass@host phishing form)
-- Rule 2 "website": tolerates the scheme-less form the UI already normalises (example.com) but never another scheme.
create function public.is_website_value(u text) returns boolean language sql immutable parallel safe set search_path = '' as $$
  select u is not null and length(u) between 3 and 500 and u !~ '[[:space:][:cntrl:]<>"'']' and (public.is_http_url(u) or u !~* '^[a-z][a-z0-9+.-]*:') $$;
revoke all on function public.is_http_url(text), public.is_website_value(text) from public;
grant execute on function public.is_http_url(text), public.is_website_value(text) to anon, authenticated, service_role;   -- pure, no data access

alter table public.companies              add constraint companies_website_safe        check (website is null or public.is_website_value(website)) not valid;
alter table public.products               add constraint products_source_url_safe      check (source_url is null or public.is_http_url(source_url)) not valid;
alter table public.company_sources        add constraint company_sources_url_safe      check (source_url is null or public.is_http_url(source_url) or source_url ~ '^direct-submission:[0-9a-f-]{36}$') not valid;
alter table public.company_contacts       add constraint company_contacts_url_safe     check (source_url is null or public.is_http_url(source_url)) not valid;
alter table public.company_images         add constraint company_images_url_safe       check (source_url is null or public.is_http_url(source_url)) not valid;
alter table public.product_images         add constraint product_images_url_safe       check (image_source_url is null or public.is_http_url(image_source_url)) not valid;
alter table public.company_import_batches add constraint import_batches_url_safe       check (source_url is null or public.is_http_url(source_url)) not valid;
alter table public.company_import_rows    add constraint import_rows_website_safe      check (website is null or public.is_website_value(website)) not valid;
-- company_data_corrections.evidence_url already has the 0007 http(s) check (kept; the stricter is_http_url could replace it in a later step).
commit;
