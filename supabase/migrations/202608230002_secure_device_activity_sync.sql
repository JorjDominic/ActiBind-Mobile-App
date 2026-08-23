-- ActiBind secure device activity synchronization (deployment-hardened).
--
-- Ownership model:
--   device_app_activity keeps user_id for efficient filtering, while a composite
--   foreign key (device_id, user_id) -> registered_devices(id, user_id) guarantees
--   that activity ownership always matches the registered-device owner, even if
--   RLS is bypassed by a trusted backend operation.
--
-- Daily identity and synchronization semantics:
--   One row represents the authoritative foreground total for:
--     device_id + usage_date + app_name + package_name/executable.
--   window_title is NOT part of the identity. It is optional metadata containing
--   only the latest/redacted title submitted for that app/day. Omitting an identity
--   from a later upload means "unchanged"; it does not delete the existing row.
--   Retries replace total_seconds, so the operation is idempotent.
--
-- Time model:
--   usage_date is supplied by the monitored device and means that device's LOCAL
--   calendar date. device_timezone is descriptive metadata. created_at, updated_at,
--   last_synced_at, first_used_at and last_used_at are timestamptz values stored in UTC.
--   Date validation intentionally has a small UTC-boundary buffer because Windows
--   timezone IDs are not always PostgreSQL/IANA timezone IDs.
--
-- Device authentication model:
--   The PC generates a high-entropy permanent secret. Only its SHA-256 hash is stored
--   in the private schema. Anonymous device operations are NOT granted directly to
--   API roles. Supabase Edge Functions call service-role-only RPCs and apply per-IP/
--   per-device rate limits before database work. There is no global device lockout
--   that an attacker can repeatedly trigger with a known device UUID.
--
-- Retention:
--   This migration creates a housekeeping function but does NOT require pg_cron.
--   Scheduling is a separate optional deployment step so pg_cron availability cannot
--   block the core schema migration.

create extension if not exists pgcrypto with schema extensions;

-- -----------------------------------------------------------------------------
-- Existing registered_devices hardening
-- -----------------------------------------------------------------------------

alter table public.registered_devices
  alter column connected set default false,
  add column if not exists pairing_code_hash text,
  add column if not exists pairing_expires_at timestamptz,
  add column if not exists revoked_at timestamptz,
  add column if not exists credential_rotation_required boolean not null default false;

-- Legacy pairing columns remain for migration compatibility, but PC pairing no longer
-- uses registered_devices.pairing_code_hash. PC pairing is initiated by the PC and
-- stored privately until the authenticated parent claims the displayed code.
create unique index if not exists registered_devices_active_pairing_code_idx
on public.registered_devices (pairing_code_hash)
where pairing_code_hash is not null;

-- Composite ownership target required by device_app_activity.
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.registered_devices'::regclass
      and conname = 'registered_devices_id_user_id_key'
  ) then
    alter table public.registered_devices
      add constraint registered_devices_id_user_id_key unique (id, user_id);
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- Generic updated_at trigger
-- -----------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Daily aggregate table
-- -----------------------------------------------------------------------------

create table if not exists public.device_app_activity (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  device_id uuid not null,
  usage_date date not null,
  app_name text not null,
  package_name text not null default '',
  window_title text not null default '',
  device_timezone text not null default '',
  total_seconds bigint not null default 0,
  first_used_at timestamptz,
  last_used_at timestamptz,
  last_synced_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Converge known development schemas. This migration supports the known ActiBind
-- development table shapes; unknown incompatible column types should be fixed in a
-- dedicated migration rather than silently coerced here.
alter table public.device_app_activity
  add column if not exists user_id uuid,
  add column if not exists device_id uuid,
  add column if not exists usage_date date,
  add column if not exists app_name text,
  add column if not exists package_name text,
  add column if not exists window_title text,
  add column if not exists device_timezone text,
  add column if not exists total_seconds bigint,
  add column if not exists first_used_at timestamptz,
  add column if not exists last_used_at timestamptz,
  add column if not exists last_synced_at timestamptz not null default now(),
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

-- Registered device is the ownership source of truth. Orphans from development are
-- removed because they cannot satisfy the ownership invariant.
delete from public.device_app_activity activity
where activity.device_id is null
   or not exists (
     select 1
     from public.registered_devices device
     where device.id = activity.device_id
   );

update public.device_app_activity activity
set user_id = device.user_id
from public.registered_devices device
where device.id = activity.device_id
  and activity.user_id is distinct from device.user_id;

-- Remove obviously unusable development rows before final NOT NULL/check constraints.
delete from public.device_app_activity
where usage_date is null
   or char_length(trim(coalesce(app_name, ''))) = 0;

update public.device_app_activity
set app_name = left(trim(app_name), 150),
    package_name = left(coalesce(trim(package_name), ''), 300),
    window_title = left(coalesce(trim(window_title), ''), 500),
    device_timezone = left(coalesce(trim(device_timezone), ''), 100),
    total_seconds = greatest(0, least(86400, coalesce(total_seconds, 0))),
    last_synced_at = coalesce(last_synced_at, now()),
    created_at = coalesce(created_at, now()),
    updated_at = coalesce(updated_at, now());

-- A development FK may have cascaded activity when a device row was deleted. Disconnect
-- should preserve history, so the final ownership FK uses ON DELETE NO ACTION.
alter table public.device_app_activity
  drop constraint if exists device_app_activity_device_id_fkey,
  drop constraint if exists device_app_activity_owner_device_fkey;

-- Drop any old unique constraint/index that used window_title as part of the daily
-- identity. This catches differently named development artifacts, not just one known
-- constraint name.
do $$
declare
  item record;
begin
  for item in
    select c.conname
    from pg_constraint c
    where c.conrelid = 'public.device_app_activity'::regclass
      and c.contype = 'u'
      and pg_get_constraintdef(c.oid) ilike '%device_id%'
      and pg_get_constraintdef(c.oid) ilike '%usage_date%'
      and pg_get_constraintdef(c.oid) ilike '%app_name%'
      and pg_get_constraintdef(c.oid) ilike '%package_name%'
      and pg_get_constraintdef(c.oid) ilike '%window_title%'
  loop
    execute format('alter table public.device_app_activity drop constraint %I', item.conname);
  end loop;

  for item in
    select n.nspname, cls.relname
    from pg_index i
    join pg_class cls on cls.oid = i.indexrelid
    join pg_namespace n on n.oid = cls.relnamespace
    where i.indrelid = 'public.device_app_activity'::regclass
      and i.indisunique
      and not i.indisprimary
      and not exists (select 1 from pg_constraint c where c.conindid = i.indexrelid)
      and pg_get_indexdef(i.indexrelid) ilike '%device_id%'
      and pg_get_indexdef(i.indexrelid) ilike '%usage_date%'
      and pg_get_indexdef(i.indexrelid) ilike '%app_name%'
      and pg_get_indexdef(i.indexrelid) ilike '%package_name%'
      and pg_get_indexdef(i.indexrelid) ilike '%window_title%'
  loop
    execute format('drop index if exists %I.%I', item.nspname, item.relname);
  end loop;
end;
$$;

-- Merge legacy title-fragmented rows into the new app/package identity. The aggregate
-- total is capped at one day because ActiBind currently measures foreground usage.
with grouped as (
  select
    (array_agg(id order by id))[1] as keep_id,
    array_agg(id) as ids,
    device_id,
    usage_date,
    trim(app_name) as app_name,
    trim(coalesce(package_name, '')) as package_name,
    max(trim(coalesce(window_title, ''))) as representative_title,
    max(trim(coalesce(device_timezone, ''))) as representative_timezone,
    least(86400::numeric, sum(greatest(coalesce(total_seconds, 0), 0)))::bigint as merged_seconds,
    min(first_used_at) as merged_first,
    max(last_used_at) as merged_last,
    max(last_synced_at) as merged_sync
  from public.device_app_activity
  group by device_id, usage_date, trim(app_name), trim(coalesce(package_name, ''))
  having count(*) > 1
), updated as (
  update public.device_app_activity a
  set app_name = g.app_name,
      package_name = g.package_name,
      window_title = g.representative_title,
      device_timezone = g.representative_timezone,
      total_seconds = g.merged_seconds,
      first_used_at = g.merged_first,
      last_used_at = g.merged_last,
      last_synced_at = coalesce(g.merged_sync, now())
  from grouped g
  where a.id = g.keep_id
  returning a.id
)
delete from public.device_app_activity a
using grouped g
where a.id = any(g.ids)
  and a.id <> g.keep_id;

alter table public.device_app_activity
  alter column user_id set default auth.uid(),
  alter column user_id set not null,
  alter column device_id set not null,
  alter column usage_date set not null,
  alter column usage_date drop default,
  alter column app_name set not null,
  alter column package_name set default '',
  alter column package_name set not null,
  alter column window_title set default '',
  alter column window_title set not null,
  alter column device_timezone set default '',
  alter column device_timezone set not null,
  alter column total_seconds set default 0,
  alter column total_seconds set not null,
  alter column last_synced_at set default now(),
  alter column last_synced_at set not null,
  alter column created_at set default now(),
  alter column created_at set not null,
  alter column updated_at set default now(),
  alter column updated_at set not null;

-- Replace final named constraints to guarantee convergence.
alter table public.device_app_activity
  drop constraint if exists device_app_activity_identity_key,
  drop constraint if exists device_app_activity_app_name_check,
  drop constraint if exists device_app_activity_package_name_check,
  drop constraint if exists device_app_activity_window_title_check,
  drop constraint if exists device_app_activity_timezone_check,
  drop constraint if exists device_app_activity_total_seconds_check,
  drop constraint if exists device_app_activity_used_at_check;

alter table public.device_app_activity
  add constraint device_app_activity_owner_device_fkey
    foreign key (device_id, user_id)
    references public.registered_devices(id, user_id)
    on delete no action
    deferrable initially deferred,
  add constraint device_app_activity_identity_key
    unique (device_id, usage_date, app_name, package_name),
  add constraint device_app_activity_app_name_check
    check (char_length(app_name) between 1 and 150 and app_name = trim(app_name)),
  add constraint device_app_activity_package_name_check
    check (char_length(package_name) <= 300 and package_name = trim(package_name)),
  add constraint device_app_activity_window_title_check
    check (char_length(window_title) <= 500 and window_title = trim(window_title)),
  add constraint device_app_activity_timezone_check
    check (char_length(device_timezone) <= 100 and device_timezone = trim(device_timezone)),
  add constraint device_app_activity_total_seconds_check
    check (total_seconds between 0 and 86400),
  add constraint device_app_activity_used_at_check
    check (first_used_at is null or last_used_at is null or last_used_at >= first_used_at);

create index if not exists device_app_activity_user_date_idx
on public.device_app_activity (user_id, usage_date desc);

create index if not exists device_app_activity_device_date_idx
on public.device_app_activity (device_id, usage_date desc);

create index if not exists device_app_activity_device_date_usage_idx
on public.device_app_activity (device_id, usage_date, total_seconds desc);

create index if not exists device_app_activity_device_sync_idx
on public.device_app_activity (device_id, last_synced_at desc);

drop trigger if exists device_app_activity_set_updated_at on public.device_app_activity;
create trigger device_app_activity_set_updated_at
before update on public.device_app_activity
for each row execute function public.set_updated_at();

-- Migrate the known earlier PC-only aggregate table if present. Because that table
-- could contain one row per window title, aggregate it to app/day first.
do $$
begin
  if to_regclass('public.device_usage_daily') is not null then
    execute $migration$
      insert into public.device_app_activity (
        user_id,
        device_id,
        usage_date,
        app_name,
        package_name,
        window_title,
        device_timezone,
        total_seconds,
        last_synced_at
      )
      select
        device.user_id,
        old.device_id,
        old.usage_date,
        left(trim(old.app_name), 150),
        '',
        left(max(trim(coalesce(old.window_title, ''))), 500),
        '',
        least(86400::bigint, sum(greatest(coalesce(old.total_seconds, 0), 0))::bigint),
        max(coalesce(old.last_synced_at, now()))
      from public.device_usage_daily old
      join public.registered_devices device on device.id = old.device_id
      where old.usage_date is not null
        and char_length(trim(coalesce(old.app_name, ''))) between 1 and 150
      group by device.user_id, old.device_id, old.usage_date, left(trim(old.app_name), 150)
      on conflict (device_id, usage_date, app_name, package_name)
      do update set
        window_title = excluded.window_title,
        total_seconds = greatest(public.device_app_activity.total_seconds, excluded.total_seconds),
        last_synced_at = greatest(public.device_app_activity.last_synced_at, excluded.last_synced_at)
    $migration$;
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- RLS: authenticated parent/main-phone access
-- -----------------------------------------------------------------------------

alter table public.device_app_activity enable row level security;
grant select, insert, update, delete on public.device_app_activity to authenticated;
revoke all on public.device_app_activity from anon;

drop policy if exists "Users can view their device activity" on public.device_app_activity;
drop policy if exists "Users can create their device activity" on public.device_app_activity;
drop policy if exists "Users can update their device activity" on public.device_app_activity;
drop policy if exists "Users can delete their device activity" on public.device_app_activity;
drop policy if exists "Users can view usage from their own registered devices" on public.device_app_activity;
drop policy if exists "Users can insert usage for their own registered devices" on public.device_app_activity;
drop policy if exists "Users can update usage from their own registered devices" on public.device_app_activity;
drop policy if exists "Users can delete usage from their own registered devices" on public.device_app_activity;

create policy "Users can view their device activity"
on public.device_app_activity
for select to authenticated
using (
  user_id = (select auth.uid())
  and exists (
    select 1
    from public.registered_devices d
    where d.id = device_app_activity.device_id
      and d.user_id = (select auth.uid())
  )
);

create policy "Users can create their device activity"
on public.device_app_activity
for insert to authenticated
with check (
  user_id = (select auth.uid())
  and exists (
    select 1
    from public.registered_devices d
    where d.id = device_app_activity.device_id
      and d.user_id = (select auth.uid())
  )
);

create policy "Users can update their device activity"
on public.device_app_activity
for update to authenticated
using (
  user_id = (select auth.uid())
  and exists (
    select 1
    from public.registered_devices d
    where d.id = device_app_activity.device_id
      and d.user_id = (select auth.uid())
  )
)
with check (
  user_id = (select auth.uid())
  and exists (
    select 1
    from public.registered_devices d
    where d.id = device_app_activity.device_id
      and d.user_id = (select auth.uid())
  )
);

create policy "Users can delete their device activity"
on public.device_app_activity
for delete to authenticated
using (
  user_id = (select auth.uid())
  and exists (
    select 1
    from public.registered_devices d
    where d.id = device_app_activity.device_id
      and d.user_id = (select auth.uid())
  )
);

-- -----------------------------------------------------------------------------
-- Private device credentials, pairing requests and Edge rate limits
-- -----------------------------------------------------------------------------

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.device_credentials (
  device_id uuid primary key
    references public.registered_devices(id) on delete cascade,
  secret_hash text not null check (secret_hash ~ '^[0-9a-f]{64}$'),
  last_authenticated_at timestamptz,
  rotated_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Remove the old global lockout fields if an earlier development migration created them.
alter table private.device_credentials
  drop column if exists failed_attempts,
  drop column if exists locked_until;

create table if not exists private.device_pairing_requests (
  id uuid primary key default gen_random_uuid(),
  pairing_code_hash text not null unique check (pairing_code_hash ~ '^[0-9a-f]{64}$'),
  device_secret_hash text not null check (device_secret_hash ~ '^[0-9a-f]{64}$'),
  device_name text not null check (char_length(trim(device_name)) between 1 and 80),
  platform text not null check (char_length(trim(platform)) between 1 and 120),
  expires_at timestamptz not null,
  claimed_at timestamptz,
  claimed_by uuid references auth.users(id) on delete cascade,
  device_id uuid references public.registered_devices(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists device_pairing_requests_active_idx
on private.device_pairing_requests (expires_at)
where claimed_at is null;

alter table private.device_pairing_requests
  drop column if exists failed_attempts,
  drop column if exists locked_until;

create table if not exists private.device_edge_rate_limits (
  bucket text not null,
  client_key text not null check (client_key ~ '^[0-9a-f]{64}$'),
  window_start timestamptz not null,
  request_count integer not null default 0 check (request_count >= 0),
  updated_at timestamptz not null default now(),
  primary key (bucket, client_key, window_start)
);

revoke all on all tables in schema private from public, anon, authenticated;
revoke all on all sequences in schema private from public, anon, authenticated;

drop trigger if exists device_credentials_set_updated_at on private.device_credentials;
create trigger device_credentials_set_updated_at
before update on private.device_credentials
for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Safe parsing helpers: malformed JSON values must never leak cast exceptions.
-- -----------------------------------------------------------------------------

create or replace function private.try_parse_date(p_value text)
returns date
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_value is null or p_value !~ '^\d{4}-\d{2}-\d{2}$' then
    return null;
  end if;
  return p_value::date;
exception when others then
  return null;
end;
$$;

create or replace function private.try_parse_bigint(p_value text)
returns bigint
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_value is null or p_value !~ '^\d+$' then
    return null;
  end if;
  return p_value::bigint;
exception when others then
  return null;
end;
$$;

create or replace function private.try_parse_timestamptz(p_value text)
returns timestamptz
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_value is null
     or btrim(p_value) = ''
     or p_value !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?([zZ]|[+-]\d{2}:\d{2})$' then
    return null;
  end if;
  return p_value::timestamptz;
exception when others then
  return null;
end;
$$;

revoke all on function private.try_parse_date(text) from public, anon, authenticated;
revoke all on function private.try_parse_bigint(text) from public, anon, authenticated;
revoke all on function private.try_parse_timestamptz(text) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Private authentication and rate-limit helpers
-- -----------------------------------------------------------------------------

-- No attacker-triggerable global lockout is used. Edge endpoints rate-limit callers
-- by an HMAC-derived client key. A bad secret simply fails this one authentication.
create or replace function private.authenticate_registered_device(
  p_device_id uuid,
  p_device_secret text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  device_owner uuid;
  provided_hash text;
begin
  if p_device_id is null or p_device_secret is null
     or char_length(p_device_secret) < 32 or char_length(p_device_secret) > 256 then
    return null;
  end if;

  provided_hash := encode(extensions.digest(convert_to(p_device_secret, 'UTF8'), 'sha256'), 'hex');

  select d.user_id
  into device_owner
  from private.device_credentials c
  join public.registered_devices d on d.id = c.device_id
  where c.device_id = p_device_id
    and c.secret_hash = provided_hash
    and c.revoked_at is null
    and d.connected = true
    and d.revoked_at is null;

  if device_owner is null then
    return null;
  end if;

  update private.device_credentials
  set last_authenticated_at = now()
  where device_id = p_device_id;

  return device_owner;
end;
$$;

revoke all on function private.authenticate_registered_device(uuid, text) from public, anon, authenticated;

create or replace function private.consume_edge_rate_limit(
  p_bucket text,
  p_client_key text,
  p_limit integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  bucket_name text := left(trim(coalesce(p_bucket, '')), 80);
  current_window timestamptz;
  new_count integer;
begin
  if bucket_name = ''
     or p_client_key is null or p_client_key !~ '^[0-9a-f]{64}$'
     or p_limit < 1 or p_limit > 10000
     or p_window_seconds < 60 or p_window_seconds > 86400 then
    return false;
  end if;

  current_window := to_timestamp(
    floor(extract(epoch from clock_timestamp()) / p_window_seconds) * p_window_seconds
  );

  insert into private.device_edge_rate_limits (
    bucket, client_key, window_start, request_count, updated_at
  ) values (
    bucket_name, p_client_key, current_window, 1, now()
  )
  on conflict (bucket, client_key, window_start)
  do update set
    request_count = private.device_edge_rate_limits.request_count + 1,
    updated_at = now()
  returning request_count into new_count;

  return new_count <= p_limit;
end;
$$;

revoke all on function private.consume_edge_rate_limit(text, text, integer, integer)
from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- PC-initiated pairing
-- -----------------------------------------------------------------------------

-- Remove old client-callable development functions so they cannot bypass Edge rate
-- limiting. Edge functions invoke the edge_* RPCs below with the service role.
drop function if exists public.begin_registered_device_pairing(text, text, text, text, timestamptz);
drop function if exists public.begin_registered_device_pairing(text, text, text, text);
drop function if exists public.poll_registered_device_pairing(uuid, text);
drop function if exists public.cancel_registered_device_pairing(uuid, text);

create or replace function public.edge_begin_registered_device_pairing(
  p_client_key text,
  p_device_name text,
  p_platform text,
  p_pairing_code_hash text,
  p_device_secret_hash text
)
returns table (pairing_request_id uuid, expires_at timestamptz, error_code text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  request_id uuid;
  server_expires_at timestamptz := now() + interval '15 minutes';
  clean_name text := trim(coalesce(p_device_name, ''));
  clean_platform text := trim(coalesce(p_platform, ''));
  active_pairings integer;
begin
  if not private.consume_edge_rate_limit('pairing_begin', p_client_key, 10, 900) then
    return query select null::uuid, null::timestamptz, 'rate_limited'::text;
    return;
  end if;

  select count(*) into active_pairings
  from private.device_pairing_requests request
  where request.claimed_at is null and request.expires_at > now();

  if active_pairings >= 10000 then
    return query select null::uuid, null::timestamptz, 'pairing_capacity_reached'::text;
    return;
  end if;

  if char_length(clean_name) not between 1 and 80
     or char_length(clean_platform) not between 1 and 120
     or p_pairing_code_hash is null or p_pairing_code_hash !~ '^[0-9a-f]{64}$'
     or p_device_secret_hash is null or p_device_secret_hash !~ '^[0-9a-f]{64}$' then
    return query select null::uuid, null::timestamptz, 'invalid_pairing_request'::text;
    return;
  end if;

  insert into private.device_pairing_requests (
    pairing_code_hash,
    device_secret_hash,
    device_name,
    platform,
    expires_at
  ) values (
    p_pairing_code_hash,
    p_device_secret_hash,
    clean_name,
    clean_platform,
    server_expires_at
  )
  returning id into request_id;

  return query select request_id, server_expires_at, null::text;
exception
  when unique_violation then
    return query select null::uuid, null::timestamptz, 'pairing_code_collision'::text;
end;
$$;

revoke all on function public.edge_begin_registered_device_pairing(text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.edge_begin_registered_device_pairing(text, text, text, text, text) to service_role;

-- The authenticated parent/main phone claims the code displayed by the PC. The legacy
-- parent-generated PC-code fallback is intentionally removed because it could connect a
-- row without creating a persistent device credential.
create or replace function public.claim_registered_device(p_pairing_code_hash text)
returns table (device_id uuid, device_name text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  requester uuid := auth.uid();
  pairing private.device_pairing_requests%rowtype;
  created_device_id uuid;
begin
  if requester is null then
    raise exception 'Sign in before connecting a device.';
  end if;

  -- A valid session does not permit unlimited pairing-code guesses. The key is
  -- derived inside PostgreSQL and cannot be selected by the caller.
  if not private.consume_edge_rate_limit(
    'pairing_claim',
    encode(extensions.digest(convert_to(requester::text, 'UTF8'), 'sha256'), 'hex'),
    20,
    900
  ) then
    return;
  end if;

  if p_pairing_code_hash is null or p_pairing_code_hash !~ '^[0-9a-f]{64}$' then
    return;
  end if;

  select *
  into pairing
  from private.device_pairing_requests
  where pairing_code_hash = p_pairing_code_hash
    and claimed_at is null
    and expires_at > now()
  for update;

  if not found then
    -- Mobile devices still use the existing parent-created code flow. This path
    -- is deliberately restricted to a mobile row already owned by this account;
    -- PCs must pair through private.device_pairing_requests so they receive a
    -- persistent, least-privilege device credential.
    return query
    update public.registered_devices as device
    set connected = true,
        last_seen_at = now(),
        pairing_code_hash = null,
        pairing_expires_at = null,
        revoked_at = null
    where device.pairing_code_hash = p_pairing_code_hash
      and device.user_id = requester
      and device.device_type = 'mobile'
      and device.connected = false
      and device.pairing_expires_at > now()
    returning device.id, device.name;
    return;
  end if;

  insert into public.registered_devices (
    user_id,
    name,
    device_type,
    platform,
    connected,
    last_seen_at,
    revoked_at,
    credential_rotation_required,
    pairing_code_hash,
    pairing_expires_at
  ) values (
    requester,
    pairing.device_name,
    'pc',
    pairing.platform,
    true,
    now(),
    null,
    false,
    null,
    null
  )
  returning id into created_device_id;

  insert into private.device_credentials (device_id, secret_hash)
  values (created_device_id, pairing.device_secret_hash);

  update private.device_pairing_requests
  set claimed_at = now(),
      claimed_by = requester,
      device_id = created_device_id
  where id = pairing.id;

  return query select created_device_id, pairing.device_name;
end;
$$;

revoke all on function public.claim_registered_device(text) from public;
grant execute on function public.claim_registered_device(text) to authenticated;

create or replace function public.edge_poll_registered_device_pairing(
  p_client_key text,
  p_pairing_request_id uuid,
  p_device_secret text
)
returns table (
  paired boolean,
  device_id uuid,
  device_name text,
  connected boolean,
  expires_at timestamptz,
  error_code text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  pairing private.device_pairing_requests%rowtype;
  provided_hash text;
begin
  if not private.consume_edge_rate_limit('pairing_poll', p_client_key, 180, 900) then
    return query select false, null::uuid, ''::text, false, null::timestamptz, 'rate_limited'::text;
    return;
  end if;

  if p_pairing_request_id is null or p_device_secret is null
     or char_length(p_device_secret) < 32 or char_length(p_device_secret) > 256 then
    return query select false, null::uuid, ''::text, false, null::timestamptz, 'invalid_pairing_request'::text;
    return;
  end if;

  provided_hash := encode(extensions.digest(convert_to(p_device_secret, 'UTF8'), 'sha256'), 'hex');

  select *
  into pairing
  from private.device_pairing_requests
  where id = p_pairing_request_id
    and device_secret_hash = provided_hash;

  if not found then
    return query select false, null::uuid, ''::text, false, null::timestamptz, 'pairing_not_found'::text;
    return;
  end if;

  return query
  select
    pairing.claimed_at is not null,
    pairing.device_id,
    coalesce(
      (select device.name from public.registered_devices device where device.id = pairing.device_id),
      pairing.device_name
    ),
    coalesce(
      (select device.connected from public.registered_devices device where device.id = pairing.device_id),
      false
    ),
    pairing.expires_at,
    null::text;
end;
$$;

revoke all on function public.edge_poll_registered_device_pairing(text, uuid, text) from public, anon, authenticated;
grant execute on function public.edge_poll_registered_device_pairing(text, uuid, text) to service_role;

create or replace function public.edge_cancel_registered_device_pairing(
  p_client_key text,
  p_pairing_request_id uuid,
  p_device_secret text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  expected_hash text;
begin
  if not private.consume_edge_rate_limit('pairing_cancel', p_client_key, 30, 900) then
    return false;
  end if;

  if p_pairing_request_id is null or p_device_secret is null
     or char_length(p_device_secret) < 32 or char_length(p_device_secret) > 256 then
    return false;
  end if;

  expected_hash := encode(extensions.digest(convert_to(p_device_secret, 'UTF8'), 'sha256'), 'hex');

  delete from private.device_pairing_requests
  where id = p_pairing_request_id
    and claimed_at is null
    and device_secret_hash = expected_hash;

  return found;
end;
$$;

revoke all on function public.edge_cancel_registered_device_pairing(text, uuid, text) from public, anon, authenticated;
grant execute on function public.edge_cancel_registered_device_pairing(text, uuid, text) to service_role;

-- -----------------------------------------------------------------------------
-- Service-role-only device operations called by the rate-limited Edge endpoint
-- -----------------------------------------------------------------------------

-- Remove old direct client-callable versions if present.
drop function if exists public.get_registered_device_status(uuid, text);
drop function if exists public.upload_device_app_activity(uuid, text, jsonb);
drop function if exists public.rotate_registered_device_credential(uuid, text, text);
drop function if exists public.disconnect_registered_device_by_device(uuid, text);

create or replace function public.edge_get_registered_device_status(
  p_client_key text,
  p_device_id uuid,
  p_device_secret text
)
returns table (
  connected boolean,
  revoked boolean,
  credential_rotation_required boolean,
  last_seen_at timestamptz,
  error_code text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_id uuid;
begin
  if not private.consume_edge_rate_limit('device_status', p_client_key, 180, 900) then
    return query select false, false, false, null::timestamptz, 'rate_limited'::text;
    return;
  end if;

  owner_id := private.authenticate_registered_device(p_device_id, p_device_secret);
  if owner_id is null then
    return query select false, false, false, null::timestamptz, 'device_auth_failed'::text;
    return;
  end if;

  update public.registered_devices as device
  set last_seen_at = now()
  where device.id = p_device_id
    and device.user_id = owner_id
    and device.connected = true
    and device.revoked_at is null;

  return query
  select
    d.connected,
    d.revoked_at is not null,
    d.credential_rotation_required,
    d.last_seen_at,
    null::text
  from public.registered_devices d
  where d.id = p_device_id
    and d.user_id = owner_id;
end;
$$;

revoke all on function public.edge_get_registered_device_status(text, uuid, text) from public, anon, authenticated;
grant execute on function public.edge_get_registered_device_status(text, uuid, text) to service_role;

create or replace function public.edge_upload_device_app_activity(
  p_client_key text,
  p_device_id uuid,
  p_device_secret text,
  p_rows jsonb
)
returns table (
  accepted boolean,
  rows_upserted integer,
  synced_at timestamptz,
  error_code text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_id uuid;
  affected integer := 0;
  sync_time timestamptz := now();
begin
  if not private.consume_edge_rate_limit('device_upload', p_client_key, 180, 900) then
    return query select false, 0, sync_time, 'rate_limited'::text;
    return;
  end if;

  owner_id := private.authenticate_registered_device(p_device_id, p_device_secret);
  if owner_id is null then
    return query select false, 0, sync_time, 'device_auth_failed'::text;
    return;
  end if;

  if exists (
    select 1
    from public.registered_devices d
    where d.id = p_device_id
      and d.user_id = owner_id
      and d.credential_rotation_required = true
  ) then
    return query select false, 0, sync_time, 'credential_rotation_required'::text;
    return;
  end if;

  if p_rows is null or jsonb_typeof(p_rows) <> 'array'
     or jsonb_array_length(p_rows) < 1
     or jsonb_array_length(p_rows) > 500 then
    return query select false, 0, sync_time, 'invalid_payload'::text;
    return;
  end if;

  -- Parse everything as text first. try_parse_* converts malformed values to NULL,
  -- allowing a controlled invalid_activity_row response instead of a PostgreSQL cast
  -- exception leaking through PostgREST/Edge Function.
  if exists (
    with parsed as (
      select
        value as raw,
        private.try_parse_date(value->>'usage_date') as usage_date,
        trim(coalesce(value->>'app_name', '')) as app_name,
        trim(coalesce(value->>'package_name', '')) as package_name,
        trim(coalesce(value->>'window_title', '')) as window_title,
        trim(coalesce(value->>'device_timezone', '')) as device_timezone,
        private.try_parse_bigint(value->>'total_seconds') as total_seconds,
        private.try_parse_timestamptz(value->>'first_used_at') as first_used_at,
        private.try_parse_timestamptz(value->>'last_used_at') as last_used_at,
        nullif(trim(coalesce(value->>'first_used_at', '')), '') is not null as first_was_supplied,
        nullif(trim(coalesce(value->>'last_used_at', '')), '') is not null as last_was_supplied
      from jsonb_array_elements(p_rows) value
    )
    select 1
    from parsed
    where jsonb_typeof(raw) <> 'object'
       or char_length(app_name) not between 1 and 150
       or char_length(package_name) > 300
       or char_length(window_title) > 500
       or char_length(device_timezone) > 100
       or total_seconds is null
       or total_seconds < 0
       or total_seconds > 86400
       or usage_date is null
       -- Small buffer accounts for device-local dates near UTC boundaries.
       or usage_date < current_date - 92
       or usage_date > current_date + 2
       or (first_was_supplied and first_used_at is null)
       or (last_was_supplied and last_used_at is null)
       or (first_used_at is not null and last_used_at is not null and last_used_at < first_used_at)
       -- Any supplied first/last timestamp must be reasonably close to the local date.
       -- Â±18h covers real-world UTC offsets and DST without pretending device_timezone
       -- is guaranteed to be an IANA identifier.
       or (
         first_used_at is not null
         and (
           first_used_at < ((usage_date::timestamp at time zone 'UTC') - interval '18 hours')
           or first_used_at >= (((usage_date + 1)::timestamp at time zone 'UTC') + interval '18 hours')
         )
       )
       or (
         last_used_at is not null
         and (
           last_used_at < ((usage_date::timestamp at time zone 'UTC') - interval '18 hours')
           or last_used_at >= (((usage_date + 1)::timestamp at time zone 'UTC') + interval '18 hours')
         )
       )
  ) then
    return query select false, 0, sync_time, 'invalid_activity_row'::text;
    return;
  end if;

  -- Reject duplicate normalized identities in one payload before ON CONFLICT so a
  -- single INSERT can never attempt to update the same target row twice.
  if exists (
    with normalized as (
      select
        private.try_parse_date(value->>'usage_date') as usage_date,
        trim(coalesce(value->>'app_name', '')) as app_name,
        trim(coalesce(value->>'package_name', '')) as package_name
      from jsonb_array_elements(p_rows) value
    )
    select 1
    from normalized
    group by usage_date, app_name, package_name
    having count(*) > 1
  ) then
    return query select false, 0, sync_time, 'duplicate_activity_identity'::text;
    return;
  end if;

  insert into public.device_app_activity (
    user_id,
    device_id,
    usage_date,
    app_name,
    package_name,
    window_title,
    device_timezone,
    total_seconds,
    first_used_at,
    last_used_at,
    last_synced_at
  )
  select
    owner_id,
    p_device_id,
    private.try_parse_date(value->>'usage_date'),
    trim(value->>'app_name'),
    trim(coalesce(value->>'package_name', '')),
    trim(coalesce(value->>'window_title', '')),
    trim(coalesce(value->>'device_timezone', '')),
    private.try_parse_bigint(value->>'total_seconds'),
    private.try_parse_timestamptz(value->>'first_used_at'),
    private.try_parse_timestamptz(value->>'last_used_at'),
    sync_time
  from jsonb_array_elements(p_rows) value
  on conflict (device_id, usage_date, app_name, package_name)
  do update set
    user_id = excluded.user_id,
    window_title = excluded.window_title,
    device_timezone = excluded.device_timezone,
    total_seconds = excluded.total_seconds,
    first_used_at = excluded.first_used_at,
    last_used_at = excluded.last_used_at,
    last_synced_at = sync_time;

  get diagnostics affected = row_count;

  update public.registered_devices
  set last_seen_at = sync_time
  where id = p_device_id
    and user_id = owner_id
    and connected = true
    and revoked_at is null;

  return query select true, affected, sync_time, null::text;
end;
$$;

revoke all on function public.edge_upload_device_app_activity(text, uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.edge_upload_device_app_activity(text, uuid, text, jsonb) to service_role;

create or replace function public.edge_rotate_registered_device_credential(
  p_client_key text,
  p_device_id uuid,
  p_current_device_secret text,
  p_new_device_secret_hash text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_id uuid;
begin
  if not private.consume_edge_rate_limit('device_rotate', p_client_key, 20, 900) then
    return false;
  end if;

  owner_id := private.authenticate_registered_device(p_device_id, p_current_device_secret);
  if owner_id is null then
    return false;
  end if;

  if p_new_device_secret_hash is null or p_new_device_secret_hash !~ '^[0-9a-f]{64}$' then
    return false;
  end if;

  update private.device_credentials
  set secret_hash = p_new_device_secret_hash,
      rotated_at = now()
  where device_id = p_device_id;

  update public.registered_devices
  set credential_rotation_required = false,
      last_seen_at = now()
  where id = p_device_id
    and user_id = owner_id;

  return true;
end;
$$;

revoke all on function public.edge_rotate_registered_device_credential(text, uuid, text, text) from public, anon, authenticated;
grant execute on function public.edge_rotate_registered_device_credential(text, uuid, text, text) to service_role;

create or replace function public.edge_disconnect_registered_device_by_device(
  p_client_key text,
  p_device_id uuid,
  p_device_secret text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_id uuid;
begin
  if not private.consume_edge_rate_limit('device_disconnect', p_client_key, 20, 900) then
    return false;
  end if;

  owner_id := private.authenticate_registered_device(p_device_id, p_device_secret);
  if owner_id is null then
    return false;
  end if;

  update public.registered_devices
  set connected = false,
      revoked_at = now(),
      credential_rotation_required = false
  where id = p_device_id
    and user_id = owner_id;

  update private.device_credentials
  set revoked_at = now()
  where device_id = p_device_id;

  return true;
end;
$$;

revoke all on function public.edge_disconnect_registered_device_by_device(text, uuid, text) from public, anon, authenticated;
grant execute on function public.edge_disconnect_registered_device_by_device(text, uuid, text) to service_role;

-- -----------------------------------------------------------------------------
-- Parent/main-phone credential/device management
-- -----------------------------------------------------------------------------

create or replace function public.request_registered_device_credential_rotation(p_device_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    return false;
  end if;

  update public.registered_devices
  set credential_rotation_required = true
  where id = p_device_id
    and user_id = auth.uid()
    and connected = true
    and revoked_at is null;

  return found;
end;
$$;

revoke all on function public.request_registered_device_credential_rotation(uuid) from public;
grant execute on function public.request_registered_device_credential_rotation(uuid) to authenticated;

-- Disconnect/revoke keeps the registered_devices row and all historical activity.
create or replace function public.revoke_registered_device(p_device_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    return false;
  end if;

  update public.registered_devices
  set connected = false,
      revoked_at = now(),
      credential_rotation_required = false
  where id = p_device_id
    and user_id = auth.uid();

  if not found then
    return false;
  end if;

  update private.device_credentials
  set revoked_at = now()
  where device_id = p_device_id;

  return true;
end;
$$;

revoke all on function public.revoke_registered_device(uuid) from public;
grant execute on function public.revoke_registered_device(uuid) to authenticated;

-- Permanent deletion is deliberately separate and destructive.
create or replace function public.delete_registered_device_permanently(p_device_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    return false;
  end if;

  if not exists (
    select 1
    from public.registered_devices d
    where d.id = p_device_id
      and d.user_id = auth.uid()
  ) then
    return false;
  end if;

  delete from public.device_app_activity
  where device_id = p_device_id
    and user_id = auth.uid();

  delete from public.registered_devices
  where id = p_device_id
    and user_id = auth.uid();

  return true;
end;
$$;

revoke all on function public.delete_registered_device_permanently(uuid) from public;
grant execute on function public.delete_registered_device_permanently(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Housekeeping (scheduling intentionally separate from this core migration)
-- -----------------------------------------------------------------------------

-- If an earlier development version scheduled the old pg_cron job, remove that job
-- without requiring pg_cron to exist on fresh projects. The extension itself is left
-- untouched if it was already enabled for other project features.
do $$
declare
  item record;
begin
  if to_regnamespace('cron') is not null then
    for item in execute $cleanup$
      select jobid
      from cron.job
      where jobname in ('purge-actibind-device-app-activity', 'actibind-device-sync-housekeeping')
    $cleanup$
    loop
      perform cron.unschedule(item.jobid);
    end loop;
  end if;
exception when others then
  -- Core schema deployment must not fail because optional scheduler cleanup failed.
  null;
end;
$$;

create or replace function public.purge_device_sync_housekeeping()
returns table (
  activity_rows_deleted bigint,
  pairing_rows_deleted bigint,
  rate_limit_rows_deleted bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  a bigint := 0;
  p bigint := 0;
  r bigint := 0;
begin
  delete from public.device_app_activity
  where usage_date < current_date - 90;
  get diagnostics a = row_count;

  delete from private.device_pairing_requests
  where expires_at < now() - interval '1 day'
     or (claimed_at is not null and claimed_at < now() - interval '1 day');
  get diagnostics p = row_count;

  delete from private.device_edge_rate_limits
  where window_start < now() - interval '2 days';
  get diagnostics r = row_count;

  return query select a, p, r;
end;
$$;

revoke all on function public.purge_device_sync_housekeeping() from public, anon, authenticated;
grant execute on function public.purge_device_sync_housekeeping() to service_role;
