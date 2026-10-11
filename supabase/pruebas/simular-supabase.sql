-- Simula lo mínimo de Supabase en un Postgres local para probar instalar.sql (NO se usa en Supabase).
do $$ begin create role anon nologin; exception when others then null; end $$;
do $$ begin create role authenticated nologin; exception when others then null; end $$;
do $$ begin create role service_role nologin bypassrls; exception when others then null; end $$;
create schema auth;
create table auth.users (
  id uuid primary key default gen_random_uuid(), email text, email_confirmed_at timestamptz,
  raw_user_meta_data jsonb default '{}'::jsonb, created_at timestamptz default now()
);
create function auth.uid() returns uuid language sql stable as
  $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create schema extensions;
create extension pgcrypto with schema extensions;
create schema storage;
create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid,
  metadata jsonb default '{}'::jsonb, created_at timestamptz default now());
alter table storage.objects enable row level security;
grant usage on schema storage to authenticated, anon;
grant select, insert, update, delete on storage.objects to authenticated;
create function storage.foldername(name text) returns text[] language sql immutable as
  $$ select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1] $$;
create schema cron;
create table cron.job (jobid bigserial primary key, jobname text, schedule text, command text);
create function cron.schedule(n text, s text, c text) returns bigint language sql as
  $$ insert into cron.job (jobname, schedule, command) values (n, s, c) returning jobid $$;
create function cron.unschedule(id bigint) returns boolean language sql as $$ delete from cron.job where jobid = id; select true $$;
create schema net;
create table net.llamadas (id bigserial, url text, body jsonb);
create function net.http_post(url text, body jsonb default '{}'::jsonb, params jsonb default '{}'::jsonb,
  headers jsonb default '{}'::jsonb, timeout_milliseconds int default 5000) returns bigint language sql as
  $$ insert into net.llamadas (url, body) values (url, body) returning id $$;
create publication supabase_realtime;
