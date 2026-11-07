--
-- PostgreSQL database dump
--


-- Dumped from database version 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1)
-- Dumped by pg_dump version 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: pg_database_owner
--

CREATE SCHEMA public;


ALTER SCHEMA public OWNER TO pg_database_owner;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: pg_database_owner
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: storage; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA storage;


ALTER SCHEMA storage OWNER TO postgres;

--
-- Name: acquisition_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.acquisition_status AS ENUM (
    'not_contacted',
    'contact_attempted',
    'in_conversation',
    'invited_to_claim',
    'claim_started',
    'declined',
    'do_not_contact'
);


ALTER TYPE public.acquisition_status OWNER TO postgres;

--
-- Name: app_role; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.app_role AS ENUM (
    'buyer',
    'seller',
    'reviewer',
    'admin'
);


ALTER TYPE public.app_role OWNER TO postgres;

--
-- Name: assoc_basis; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.assoc_basis AS ENUM (
    'manufacturer',
    'brand_owner',
    'distributor',
    'reseller',
    'marketplace_seller',
    'unknown'
);


ALTER TYPE public.assoc_basis OWNER TO postgres;

--
-- Name: claim_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.claim_status AS ENUM (
    'unclaimed',
    'claim_submitted',
    'evidence_requested',
    'under_review',
    'approved',
    'rejected',
    'withdrawn'
);


ALTER TYPE public.claim_status OWNER TO postgres;

--
-- Name: directory_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.directory_status AS ENUM (
    'draft',
    'pending_review',
    'published',
    'paused',
    'rejected',
    'suspended'
);


ALTER TYPE public.directory_status OWNER TO postgres;

--
-- Name: enquiry_delivery; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.enquiry_delivery AS ENUM (
    'stored',
    'awaiting_admin',
    'visible_to_seller',
    'sent_external',
    'failed'
);


ALTER TYPE public.enquiry_delivery OWNER TO postgres;

--
-- Name: enquiry_kind; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.enquiry_kind AS ENUM (
    'product',
    'requirement'
);


ALTER TYPE public.enquiry_kind OWNER TO postgres;

--
-- Name: enquiry_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.enquiry_status AS ENUM (
    'new',
    'read',
    'replied',
    'quoted',
    'closed',
    'spam'
);


ALTER TYPE public.enquiry_status OWNER TO postgres;

--
-- Name: image_rights; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.image_rights AS ENUM (
    'unknown',
    'owned',
    'licensed',
    'permission_granted',
    'public_domain',
    'rejected'
);


ALTER TYPE public.image_rights OWNER TO postgres;

--
-- Name: member_role; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.member_role AS ENUM (
    'owner',
    'manager',
    'sales',
    'catalogue_editor',
    'viewer'
);


ALTER TYPE public.member_role OWNER TO postgres;

--
-- Name: member_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.member_status AS ENUM (
    'invited',
    'active',
    'removed'
);


ALTER TYPE public.member_status OWNER TO postgres;

--
-- Name: notif_kind; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.notif_kind AS ENUM (
    'system',
    'tip',
    'lead',
    'enquiry',
    'message',
    'moderation',
    'claim',
    'admin'
);


ALTER TYPE public.notif_kind OWNER TO postgres;

--
-- Name: outreach_delivery; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.outreach_delivery AS ENUM (
    'logged_manual',
    'queued',
    'sent',
    'failed'
);


ALTER TYPE public.outreach_delivery OWNER TO postgres;

--
-- Name: outreach_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.outreach_type AS ENUM (
    'call',
    'email',
    'message',
    'invitation',
    'follow_up',
    'note'
);


ALTER TYPE public.outreach_type OWNER TO postgres;

--
-- Name: review_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.review_status AS ENUM (
    'pending',
    'approved',
    'rejected'
);


ALTER TYPE public.review_status OWNER TO postgres;

--
-- Name: source_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.source_type AS ENUM (
    'official_website',
    'public_business_directory',
    'trade_association',
    'exhibitor_directory',
    'government_registry',
    'direct_submission',
    'licensed_data_provider',
    'other_approved'
);


ALTER TYPE public.source_type OWNER TO postgres;

--
-- Name: verification_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.verification_status AS ENUM (
    'not_verified',
    'pending',
    'verified',
    'rejected',
    'expired'
);


ALTER TYPE public.verification_status OWNER TO postgres;

--
-- Name: block_mutation(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.block_mutation() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$ begin raise exception 'immutable'; end $$;


ALTER FUNCTION public.block_mutation() OWNER TO postgres;

--
-- Name: check_rate(text, integer, interval); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_rate(p_action text, p_max integer, p_window interval) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$ begin if (select count(*) from rate_events where user_id=auth.uid() and action=p_action and at>now()-p_window)>=p_max then raise exception 'rate limit'; end if; insert into rate_events(user_id,action) values (auth.uid(),p_action); end $$;


ALTER FUNCTION public.check_rate(p_action text, p_max integer, p_window interval) OWNER TO postgres;

--
-- Name: claim_claimant(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.claim_claimant(cid uuid) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$ select claimant_id from company_claims where id=cid $$;


ALTER FUNCTION public.claim_claimant(cid uuid) OWNER TO postgres;

--
-- Name: claim_is_open_for_me(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.claim_is_open_for_me(cid uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$ select exists(select 1 from company_claims where id=cid and claimant_id=auth.uid() and status in ('claim_submitted','evidence_requested','under_review')) $$;


ALTER FUNCTION public.claim_is_open_for_me(cid uuid) OWNER TO postgres;

--
-- Name: enquiry_buyer(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.enquiry_buyer(eid uuid) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$ select buyer_id from enquiries where id=eid $$;


ALTER FUNCTION public.enquiry_buyer(eid uuid) OWNER TO postgres;

--
-- Name: has_company_role(uuid, public.member_role[]); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.has_company_role(cid uuid, roles public.member_role[]) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$ select exists(select 1 from company_members m where m.company_id=cid and m.user_id=auth.uid() and m.status='active' and m.role=any(roles)) $$;


ALTER FUNCTION public.has_company_role(cid uuid, roles public.member_role[]) OWNER TO postgres;

--
-- Name: is_admin(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.is_admin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$ select exists(select 1 from profiles where id=auth.uid() and app_role='admin') $$;


ALTER FUNCTION public.is_admin() OWNER TO postgres;

--
-- Name: is_company_member(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.is_company_member(cid uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$ select exists(select 1 from company_members m where m.company_id=cid and m.user_id=auth.uid() and m.status='active') $$;


ALTER FUNCTION public.is_company_member(cid uuid) OWNER TO postgres;

--
-- Name: is_staff(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.is_staff() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$ select exists(select 1 from profiles where id=auth.uid() and app_role in ('admin','reviewer')) $$;


ALTER FUNCTION public.is_staff() OWNER TO postgres;

--
-- Name: lead_matches_my_company(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.lead_matches_my_company(cat integer) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$ select exists(select 1 from company_members m join companies c on c.id=m.company_id where m.user_id=auth.uid() and m.status='active' and c.claim_status='approved' and c.directory_status='published' and m.role in ('owner','manager','sales') and (cat is null or exists(select 1 from company_categories cc where cc.company_id=c.id and cc.category_id=cat))) $$;


ALTER FUNCTION public.lead_matches_my_company(cat integer) OWNER TO postgres;

--
-- Name: norm_domain(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.norm_domain(t text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $_$ select lower(regexp_replace(regexp_replace(coalesce(t,''),'^https?://(www\.)?',''),'[/:?#].*$','')) $_$;


ALTER FUNCTION public.norm_domain(t text) OWNER TO postgres;

--
-- Name: review_claim(uuid, public.claim_status, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.review_claim(p_claim uuid, p_decision public.claim_status, p_reason text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$ begin if not is_staff() then raise exception 'staff only'; end if; update company_claims set status=p_decision, decided_by=auth.uid(), decided_at=now(), decision_reason=p_reason where id=p_claim; if p_decision='approved' then update companies set claim_status='approved' where id=(select company_id from company_claims where id=p_claim); end if; end $$;


ALTER FUNCTION public.review_claim(p_claim uuid, p_decision public.claim_status, p_reason text) OWNER TO postgres;

--
-- Name: safe_uuid(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.safe_uuid(t text) RETURNS uuid
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $$ begin return t::uuid; exception when others then return null; end $$;


ALTER FUNCTION public.safe_uuid(t text) OWNER TO postgres;

--
-- Name: seller_can_see_leads(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.seller_can_see_leads() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$ select exists(select 1 from company_members m join companies c on c.id=m.company_id where m.user_id=auth.uid() and m.status='active' and c.claim_status='approved' and c.directory_status='published' and m.role in ('owner','manager','sales')) $$;


ALTER FUNCTION public.seller_can_see_leads() OWNER TO postgres;

--
-- Name: staff_mark_enquiry(uuid, public.enquiry_delivery, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.staff_mark_enquiry(p_enquiry uuid, p_delivery public.enquiry_delivery, p_note text, p_provider_ref text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$ begin if not is_staff() then raise exception 'staff only' using errcode='42501'; end if; if p_delivery='sent_external' and coalesce(trim(p_provider_ref),'')='' then raise exception 'sent_external requires a provider reference'; end if; update enquiries set delivery=p_delivery, delivery_note=left(coalesce(p_note,'')||case when p_provider_ref is not null then ' [ref '||p_provider_ref||']' else '' end,500) where id=p_enquiry; if not found then raise exception 'enquiry not found'; end if; end $$;


ALTER FUNCTION public.staff_mark_enquiry(p_enquiry uuid, p_delivery public.enquiry_delivery, p_note text, p_provider_ref text) OWNER TO postgres;

--
-- Name: submit_claim(uuid, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.submit_claim(p_company uuid, p_title text, p_statement text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$ declare cl uuid; begin insert into company_claims(company_id,claimant_id,claimant_role_title,statement) values (p_company,auth.uid(),p_title,p_statement) returning id into cl; return cl; end $$;


ALTER FUNCTION public.submit_claim(p_company uuid, p_title text, p_statement text) OWNER TO postgres;

--
-- Name: foldername(text); Type: FUNCTION; Schema: storage; Owner: postgres
--

CREATE FUNCTION storage.foldername(name text) RETURNS text[]
    LANGUAGE sql IMMUTABLE
    AS $$ select string_to_array(name,'/') $$;


ALTER FUNCTION storage.foldername(name text) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.audit_log (
    id bigint NOT NULL,
    actor_id uuid,
    actor_role text,
    action text,
    entity text,
    entity_id text,
    old_value jsonb,
    new_value jsonb,
    at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.audit_log OWNER TO postgres;

--
-- Name: audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.audit_log ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.categories (
    id integer NOT NULL,
    slug text,
    name text,
    hue integer,
    spec_template jsonb,
    hidden boolean DEFAULT false,
    "position" integer
);


ALTER TABLE public.categories OWNER TO postgres;

--
-- Name: categories_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.categories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.categories_id_seq OWNER TO postgres;

--
-- Name: categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.categories_id_seq OWNED BY public.categories.id;


--
-- Name: companies; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.companies (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    slug text,
    name text NOT NULL,
    business_type text,
    about text,
    city text,
    state text,
    country text,
    website text,
    logo_path text,
    directory_status public.directory_status DEFAULT 'draft'::public.directory_status NOT NULL,
    claim_status public.claim_status DEFAULT 'unclaimed'::public.claim_status NOT NULL,
    verification_status public.verification_status DEFAULT 'not_verified'::public.verification_status NOT NULL,
    verified_at timestamp with time zone,
    verified_by uuid,
    data_review_status public.review_status DEFAULT 'pending'::public.review_status NOT NULL,
    data_reviewed_by uuid,
    data_reviewed_at timestamp with time zone,
    dedupe_key text,
    import_batch_id uuid,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.companies OWNER TO postgres;

--
-- Name: company_acquisition; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.company_acquisition (
    company_id uuid NOT NULL,
    acquisition_status public.acquisition_status DEFAULT 'not_contacted'::public.acquisition_status,
    last_contacted_at timestamp with time zone,
    next_follow_up_at timestamp with time zone,
    contact_channel text,
    contact_outcome text,
    owner_id uuid,
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.company_acquisition OWNER TO postgres;

--
-- Name: company_categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.company_categories (
    company_id uuid NOT NULL,
    category_id integer NOT NULL
);


ALTER TABLE public.company_categories OWNER TO postgres;

--
-- Name: company_claim_evidence; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.company_claim_evidence (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    claim_id uuid,
    storage_path text,
    description text,
    uploaded_by uuid,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.company_claim_evidence OWNER TO postgres;

--
-- Name: company_claims; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.company_claims (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid,
    claimant_id uuid,
    claimant_role_title text,
    statement text,
    status public.claim_status DEFAULT 'claim_submitted'::public.claim_status NOT NULL,
    decided_by uuid,
    decided_at timestamp with time zone,
    decision_reason text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.company_claims OWNER TO postgres;

--
-- Name: company_members; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.company_members (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid,
    user_id uuid,
    invite_email text,
    role public.member_role NOT NULL,
    status public.member_status DEFAULT 'active'::public.member_status NOT NULL,
    invited_by uuid,
    expires_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.company_members OWNER TO postgres;

--
-- Name: company_outreach_events; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.company_outreach_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid,
    event_type public.outreach_type NOT NULL,
    channel text,
    summary text,
    outcome text,
    delivery public.outreach_delivery DEFAULT 'logged_manual'::public.outreach_delivery NOT NULL,
    provider_ref text,
    occurred_at timestamp with time zone DEFAULT now(),
    recorded_by uuid
);


ALTER TABLE public.company_outreach_events OWNER TO postgres;

--
-- Name: company_private; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.company_private (
    company_id uuid NOT NULL,
    phone text,
    email text,
    address text,
    pin text,
    contact_person text,
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.company_private OWNER TO postgres;

--
-- Name: enquiries; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.enquiries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ref text,
    kind public.enquiry_kind NOT NULL,
    buyer_id uuid NOT NULL,
    product_id uuid,
    company_id uuid,
    category_id integer,
    subject text,
    quantity numeric(14,2),
    unit text,
    message text,
    city text,
    status public.enquiry_status DEFAULT 'new'::public.enquiry_status NOT NULL,
    delivery public.enquiry_delivery DEFAULT 'stored'::public.enquiry_delivery NOT NULL,
    delivery_note text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.enquiries OWNER TO postgres;

--
-- Name: enquiry_private; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.enquiry_private (
    enquiry_id uuid NOT NULL,
    buyer_name text,
    buyer_phone text,
    buyer_email text,
    buyer_company text,
    consent_at timestamp with time zone,
    notice_version text
);


ALTER TABLE public.enquiry_private OWNER TO postgres;

--
-- Name: notifications; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    company_id uuid,
    kind public.notif_kind NOT NULL,
    title text,
    body text,
    link text,
    read_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.notifications OWNER TO postgres;

--
-- Name: products; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.products (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid,
    category_id integer,
    name text NOT NULL,
    description text,
    tags text,
    directory_status public.directory_status DEFAULT 'draft'::public.directory_status,
    search tsvector
);


ALTER TABLE public.products OWNER TO postgres;

--
-- Name: profiles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    full_name text,
    phone text,
    company_name text,
    city text,
    country text,
    preferred_location text,
    app_role public.app_role DEFAULT 'buyer'::public.app_role NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.profiles OWNER TO postgres;

--
-- Name: public_companies; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.public_companies WITH (security_invoker='false') AS
 SELECT id,
    slug,
    name,
    business_type,
    about,
    city,
    state,
    country,
    website,
    logo_path,
        CASE
            WHEN (verification_status = 'verified'::public.verification_status) THEN 'Verified business'::text
            WHEN (claim_status = 'approved'::public.claim_status) THEN 'Claimed business'::text
            ELSE 'Unclaimed business'::text
        END AS public_label,
    (claim_status = 'approved'::public.claim_status) AS is_claimed,
    (verification_status = 'verified'::public.verification_status) AS is_verified,
    updated_at AS data_as_of,
    updated_at
   FROM public.companies
  WHERE ((directory_status = 'published'::public.directory_status) AND (data_review_status = 'approved'::public.review_status));


ALTER VIEW public.public_companies OWNER TO postgres;

--
-- Name: rate_events; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.rate_events (
    id bigint NOT NULL,
    user_id uuid,
    action text,
    at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.rate_events OWNER TO postgres;

--
-- Name: rate_events_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.rate_events ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.rate_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: objects; Type: TABLE; Schema: storage; Owner: postgres
--

CREATE TABLE storage.objects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    bucket_id text,
    name text
);


ALTER TABLE storage.objects OWNER TO postgres;

--
-- Name: categories id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categories ALTER COLUMN id SET DEFAULT nextval('public.categories_id_seq'::regclass);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);


--
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- Name: categories categories_slug_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_slug_key UNIQUE (slug);


--
-- Name: companies companies_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_pkey PRIMARY KEY (id);


--
-- Name: company_acquisition company_acquisition_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_acquisition
    ADD CONSTRAINT company_acquisition_pkey PRIMARY KEY (company_id);


--
-- Name: company_categories company_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_categories
    ADD CONSTRAINT company_categories_pkey PRIMARY KEY (company_id, category_id);


--
-- Name: company_claim_evidence company_claim_evidence_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_claim_evidence
    ADD CONSTRAINT company_claim_evidence_pkey PRIMARY KEY (id);


--
-- Name: company_claims company_claims_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_claims
    ADD CONSTRAINT company_claims_pkey PRIMARY KEY (id);


--
-- Name: company_members company_members_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_members
    ADD CONSTRAINT company_members_pkey PRIMARY KEY (id);


--
-- Name: company_outreach_events company_outreach_events_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_outreach_events
    ADD CONSTRAINT company_outreach_events_pkey PRIMARY KEY (id);


--
-- Name: company_private company_private_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_private
    ADD CONSTRAINT company_private_pkey PRIMARY KEY (company_id);


--
-- Name: enquiries enquiries_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.enquiries
    ADD CONSTRAINT enquiries_pkey PRIMARY KEY (id);


--
-- Name: enquiry_private enquiry_private_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.enquiry_private
    ADD CONSTRAINT enquiry_private_pkey PRIMARY KEY (enquiry_id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: rate_events rate_events_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rate_events
    ADD CONSTRAINT rate_events_pkey PRIMARY KEY (id);


--
-- Name: objects objects_pkey; Type: CONSTRAINT; Schema: storage; Owner: postgres
--

ALTER TABLE ONLY storage.objects
    ADD CONSTRAINT objects_pkey PRIMARY KEY (id);


--
-- Name: company_acquisition company_acquisition_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_acquisition
    ADD CONSTRAINT company_acquisition_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: company_categories company_categories_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_categories
    ADD CONSTRAINT company_categories_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id);


--
-- Name: company_categories company_categories_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_categories
    ADD CONSTRAINT company_categories_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- Name: company_claim_evidence company_claim_evidence_claim_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_claim_evidence
    ADD CONSTRAINT company_claim_evidence_claim_id_fkey FOREIGN KEY (claim_id) REFERENCES public.company_claims(id);


--
-- Name: company_claims company_claims_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_claims
    ADD CONSTRAINT company_claims_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: company_members company_members_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_members
    ADD CONSTRAINT company_members_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: company_outreach_events company_outreach_events_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_outreach_events
    ADD CONSTRAINT company_outreach_events_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: company_private company_private_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_private
    ADD CONSTRAINT company_private_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: enquiry_private enquiry_private_enquiry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.enquiry_private
    ADD CONSTRAINT enquiry_private_enquiry_id_fkey FOREIGN KEY (enquiry_id) REFERENCES public.enquiries(id);


--
-- Name: products products_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: audit_log; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

--
-- Name: company_acquisition cacq_staff; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY cacq_staff ON public.company_acquisition USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: categories cat_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY cat_read ON public.categories FOR SELECT USING (true);


--
-- Name: categories; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

--
-- Name: company_categories cc_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY cc_read ON public.company_categories FOR SELECT USING (true);


--
-- Name: company_claim_evidence cev_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY cev_read ON public.company_claim_evidence FOR SELECT USING (((public.claim_claimant(claim_id) = auth.uid()) OR public.is_staff()));


--
-- Name: company_claims claims_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY claims_read ON public.company_claims FOR SELECT USING (((claimant_id = auth.uid()) OR public.is_staff()));


--
-- Name: companies comp_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY comp_read ON public.companies FOR SELECT USING (((directory_status = 'published'::public.directory_status) OR public.is_staff() OR public.is_company_member(id)));


--
-- Name: companies; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

--
-- Name: company_acquisition; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.company_acquisition ENABLE ROW LEVEL SECURITY;

--
-- Name: company_categories; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.company_categories ENABLE ROW LEVEL SECURITY;

--
-- Name: company_claim_evidence; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.company_claim_evidence ENABLE ROW LEVEL SECURITY;

--
-- Name: company_claims; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.company_claims ENABLE ROW LEVEL SECURITY;

--
-- Name: company_members; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.company_members ENABLE ROW LEVEL SECURITY;

--
-- Name: company_outreach_events; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.company_outreach_events ENABLE ROW LEVEL SECURITY;

--
-- Name: company_private; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.company_private ENABLE ROW LEVEL SECURITY;

--
-- Name: company_outreach_events cout_insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY cout_insert ON public.company_outreach_events FOR INSERT WITH CHECK (public.is_staff());


--
-- Name: company_outreach_events cout_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY cout_read ON public.company_outreach_events FOR SELECT USING (public.is_staff());


--
-- Name: company_private cpriv_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY cpriv_read ON public.company_private FOR SELECT USING ((public.has_company_role(company_id, ARRAY['owner'::public.member_role, 'manager'::public.member_role]) OR public.is_staff()));


--
-- Name: enquiries enq_buyer_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY enq_buyer_read ON public.enquiries FOR SELECT USING ((buyer_id = auth.uid()));


--
-- Name: enquiries enq_company_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY enq_company_read ON public.enquiries FOR SELECT USING (((company_id IS NOT NULL) AND public.has_company_role(company_id, ARRAY['owner'::public.member_role, 'manager'::public.member_role, 'sales'::public.member_role])));


--
-- Name: enquiries enq_leads_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY enq_leads_read ON public.enquiries FOR SELECT USING (((kind = 'requirement'::public.enquiry_kind) AND public.seller_can_see_leads() AND public.lead_matches_my_company(category_id)));


--
-- Name: enquiries enq_staff_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY enq_staff_read ON public.enquiries FOR SELECT USING (public.is_staff());


--
-- Name: enquiries enq_staff_upd; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY enq_staff_upd ON public.enquiries FOR UPDATE USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: enquiries; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.enquiries ENABLE ROW LEVEL SECURITY;

--
-- Name: enquiry_private; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.enquiry_private ENABLE ROW LEVEL SECURITY;

--
-- Name: enquiry_private epriv_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY epriv_read ON public.enquiry_private FOR SELECT USING (((public.enquiry_buyer(enquiry_id) = auth.uid()) OR public.is_staff()));


--
-- Name: company_members members_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY members_read ON public.company_members FOR SELECT USING (((user_id = auth.uid()) OR public.is_staff()));


--
-- Name: notifications notif_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY notif_read ON public.notifications FOR SELECT USING ((user_id = auth.uid()));


--
-- Name: notifications; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

--
-- Name: products prod_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY prod_read ON public.products FOR SELECT USING (((directory_status = 'published'::public.directory_status) OR public.is_staff()));


--
-- Name: products; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles profiles_self_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY profiles_self_read ON public.profiles FOR SELECT USING (((id = auth.uid()) OR public.is_staff()));


--
-- Name: rate_events; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.rate_events ENABLE ROW LEVEL SECURITY;

--
-- Name: objects; Type: ROW SECURITY; Schema: storage; Owner: postgres
--

ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

--
-- Name: objects vd_read; Type: POLICY; Schema: storage; Owner: postgres
--

CREATE POLICY vd_read ON storage.objects FOR SELECT TO authenticated USING (((bucket_id = 'verification-docs'::text) AND ((public.claim_claimant(public.safe_uuid((storage.foldername(name))[1])) = auth.uid()) OR public.is_staff())));


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: SCHEMA storage; Type: ACL; Schema: -; Owner: postgres
--

GRANT USAGE ON SCHEMA storage TO anon;
GRANT USAGE ON SCHEMA storage TO authenticated;
GRANT USAGE ON SCHEMA storage TO service_role;


--
-- Name: FUNCTION block_mutation(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.block_mutation() FROM PUBLIC;
GRANT ALL ON FUNCTION public.block_mutation() TO authenticated;
GRANT ALL ON FUNCTION public.block_mutation() TO service_role;


--
-- Name: FUNCTION check_rate(p_action text, p_max integer, p_window interval); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.check_rate(p_action text, p_max integer, p_window interval) FROM PUBLIC;
GRANT ALL ON FUNCTION public.check_rate(p_action text, p_max integer, p_window interval) TO authenticated;
GRANT ALL ON FUNCTION public.check_rate(p_action text, p_max integer, p_window interval) TO service_role;


--
-- Name: FUNCTION claim_claimant(cid uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.claim_claimant(cid uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.claim_claimant(cid uuid) TO authenticated;
GRANT ALL ON FUNCTION public.claim_claimant(cid uuid) TO service_role;


--
-- Name: FUNCTION claim_is_open_for_me(cid uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.claim_is_open_for_me(cid uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.claim_is_open_for_me(cid uuid) TO authenticated;
GRANT ALL ON FUNCTION public.claim_is_open_for_me(cid uuid) TO service_role;


--
-- Name: FUNCTION enquiry_buyer(eid uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.enquiry_buyer(eid uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.enquiry_buyer(eid uuid) TO authenticated;
GRANT ALL ON FUNCTION public.enquiry_buyer(eid uuid) TO service_role;


--
-- Name: FUNCTION has_company_role(cid uuid, roles public.member_role[]); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.has_company_role(cid uuid, roles public.member_role[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.has_company_role(cid uuid, roles public.member_role[]) TO authenticated;
GRANT ALL ON FUNCTION public.has_company_role(cid uuid, roles public.member_role[]) TO service_role;


--
-- Name: FUNCTION is_admin(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
GRANT ALL ON FUNCTION public.is_admin() TO authenticated;
GRANT ALL ON FUNCTION public.is_admin() TO service_role;


--
-- Name: FUNCTION is_company_member(cid uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.is_company_member(cid uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.is_company_member(cid uuid) TO authenticated;
GRANT ALL ON FUNCTION public.is_company_member(cid uuid) TO service_role;


--
-- Name: FUNCTION is_staff(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.is_staff() FROM PUBLIC;
GRANT ALL ON FUNCTION public.is_staff() TO authenticated;
GRANT ALL ON FUNCTION public.is_staff() TO service_role;


--
-- Name: FUNCTION lead_matches_my_company(cat integer); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.lead_matches_my_company(cat integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.lead_matches_my_company(cat integer) TO authenticated;
GRANT ALL ON FUNCTION public.lead_matches_my_company(cat integer) TO service_role;


--
-- Name: FUNCTION norm_domain(t text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.norm_domain(t text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.norm_domain(t text) TO authenticated;
GRANT ALL ON FUNCTION public.norm_domain(t text) TO service_role;


--
-- Name: FUNCTION review_claim(p_claim uuid, p_decision public.claim_status, p_reason text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.review_claim(p_claim uuid, p_decision public.claim_status, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.review_claim(p_claim uuid, p_decision public.claim_status, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.review_claim(p_claim uuid, p_decision public.claim_status, p_reason text) TO service_role;


--
-- Name: FUNCTION safe_uuid(t text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.safe_uuid(t text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.safe_uuid(t text) TO authenticated;
GRANT ALL ON FUNCTION public.safe_uuid(t text) TO service_role;


--
-- Name: FUNCTION seller_can_see_leads(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.seller_can_see_leads() FROM PUBLIC;
GRANT ALL ON FUNCTION public.seller_can_see_leads() TO authenticated;
GRANT ALL ON FUNCTION public.seller_can_see_leads() TO service_role;


--
-- Name: FUNCTION staff_mark_enquiry(p_enquiry uuid, p_delivery public.enquiry_delivery, p_note text, p_provider_ref text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.staff_mark_enquiry(p_enquiry uuid, p_delivery public.enquiry_delivery, p_note text, p_provider_ref text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.staff_mark_enquiry(p_enquiry uuid, p_delivery public.enquiry_delivery, p_note text, p_provider_ref text) TO authenticated;
GRANT ALL ON FUNCTION public.staff_mark_enquiry(p_enquiry uuid, p_delivery public.enquiry_delivery, p_note text, p_provider_ref text) TO service_role;


--
-- Name: FUNCTION submit_claim(p_company uuid, p_title text, p_statement text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.submit_claim(p_company uuid, p_title text, p_statement text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.submit_claim(p_company uuid, p_title text, p_statement text) TO authenticated;
GRANT ALL ON FUNCTION public.submit_claim(p_company uuid, p_title text, p_statement text) TO service_role;


--
-- Name: TABLE audit_log; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.audit_log TO authenticated;


--
-- Name: TABLE categories; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.categories TO authenticated;


--
-- Name: TABLE companies; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.companies TO authenticated;


--
-- Name: TABLE company_acquisition; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.company_acquisition TO authenticated;


--
-- Name: TABLE company_categories; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.company_categories TO authenticated;


--
-- Name: TABLE company_claim_evidence; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.company_claim_evidence TO authenticated;


--
-- Name: TABLE company_claims; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.company_claims TO authenticated;


--
-- Name: TABLE company_members; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.company_members TO authenticated;


--
-- Name: TABLE company_outreach_events; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.company_outreach_events TO authenticated;


--
-- Name: TABLE company_private; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.company_private TO authenticated;


--
-- Name: TABLE enquiries; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.enquiries TO authenticated;


--
-- Name: TABLE enquiry_private; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.enquiry_private TO authenticated;


--
-- Name: TABLE notifications; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.notifications TO authenticated;


--
-- Name: TABLE products; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.products TO authenticated;


--
-- Name: TABLE profiles; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.profiles TO authenticated;


--
-- Name: TABLE public_companies; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.public_companies TO anon;
GRANT SELECT ON TABLE public.public_companies TO authenticated;


--
-- Name: TABLE rate_events; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.rate_events TO authenticated;


--
-- Name: TABLE objects; Type: ACL; Schema: storage; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE storage.objects TO authenticated;


--
-- PostgreSQL database dump complete
--


