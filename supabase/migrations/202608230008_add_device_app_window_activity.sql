-- Window titles are sensitive and optional. App-level totals remain authoritative in
-- device_app_activity; these rows are only a drill-down and must never be added to
-- the parent total.

-- Composite target makes it impossible for a child to claim a different owner,
-- device, local date or application than its parent.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.device_app_activity'::regclass
      and conname = 'device_app_activity_window_parent_key'
  ) then
    alter table public.device_app_activity
      add constraint device_app_activity_window_parent_key unique (
        id, user_id, device_id, usage_date, app_name, package_name
      );
  end if;
end;
$$;

create table if not exists public.device_app_window_activity (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id uuid not null,
  activity_id uuid not null,
  usage_date date not null,
  app_name text not null,
  package_name text not null default '',
  window_title text not null,
  total_seconds bigint not null default 0,
  first_used_at timestamptz,
  last_used_at timestamptz,
  device_timezone text not null default '',
  last_synced_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint device_app_window_activity_parent_fkey
    foreign key (
      activity_id, user_id, device_id, usage_date, app_name, package_name
    ) references public.device_app_activity (
      id, user_id, device_id, usage_date, app_name, package_name
    ) on delete cascade,
  constraint device_app_window_activity_identity_key
    unique (activity_id, window_title),
  constraint device_app_window_activity_app_name_check
    check (char_length(app_name) between 1 and 150 and app_name = trim(app_name)),
  constraint device_app_window_activity_package_name_check
    check (char_length(package_name) <= 300 and package_name = trim(package_name)),
  constraint device_app_window_activity_window_title_check
    check (char_length(window_title) between 1 and 500 and window_title = trim(window_title)),
  constraint device_app_window_activity_timezone_check
    check (char_length(device_timezone) <= 100 and device_timezone = trim(device_timezone)),
  constraint device_app_window_activity_total_seconds_check
    check (total_seconds between 0 and 86400),
  constraint device_app_window_activity_used_at_check
    check (first_used_at is null or last_used_at is null or last_used_at >= first_used_at)
);

create index if not exists device_app_window_activity_device_date_idx
on public.device_app_window_activity (device_id, usage_date desc);

create index if not exists device_app_window_activity_activity_usage_idx
on public.device_app_window_activity (activity_id, total_seconds desc);

create index if not exists device_app_window_activity_sync_idx
on public.device_app_window_activity (device_id, last_synced_at desc);

drop trigger if exists device_app_window_activity_set_updated_at
on public.device_app_window_activity;
create trigger device_app_window_activity_set_updated_at
before update on public.device_app_window_activity
for each row execute function public.set_updated_at();

alter table public.device_app_window_activity enable row level security;
grant select, insert, update, delete on public.device_app_window_activity to authenticated;
revoke all on public.device_app_window_activity from anon;

drop policy if exists "Users can view their device window activity"
on public.device_app_window_activity;
drop policy if exists "Users can create their device window activity"
on public.device_app_window_activity;
drop policy if exists "Users can update their device window activity"
on public.device_app_window_activity;
drop policy if exists "Users can delete their device window activity"
on public.device_app_window_activity;

create policy "Users can view their device window activity"
on public.device_app_window_activity for select to authenticated
using (
  user_id = (select auth.uid())
  and exists (
    select 1 from public.registered_devices device
    where device.id = device_app_window_activity.device_id
      and device.user_id = (select auth.uid())
  )
);

create policy "Users can create their device window activity"
on public.device_app_window_activity for insert to authenticated
with check (
  user_id = (select auth.uid())
  and exists (
    select 1 from public.registered_devices device
    where device.id = device_app_window_activity.device_id
      and device.user_id = (select auth.uid())
  )
);

create policy "Users can update their device window activity"
on public.device_app_window_activity for update to authenticated
using (
  user_id = (select auth.uid())
  and exists (
    select 1 from public.registered_devices device
    where device.id = device_app_window_activity.device_id
      and device.user_id = (select auth.uid())
  )
)
with check (
  user_id = (select auth.uid())
  and exists (
    select 1 from public.registered_devices device
    where device.id = device_app_window_activity.device_id
      and device.user_id = (select auth.uid())
  )
);

create policy "Users can delete their device window activity"
on public.device_app_window_activity for delete to authenticated
using (
  user_id = (select auth.uid())
  and exists (
    select 1 from public.registered_devices device
    where device.id = device_app_window_activity.device_id
      and device.user_id = (select auth.uid())
  )
);

-- Service-role-only upload path for a future PC collector update. Every row resolves
-- its parent by the normal app identity; retries replace totals and never increment.
create or replace function public.edge_upload_device_app_window_activity(
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
  if not private.consume_edge_rate_limit('window_upload', p_client_key, 180, 900) then
    return query select false, 0, sync_time, 'rate_limited'::text;
    return;
  end if;

  owner_id := private.authenticate_registered_device(p_device_id, p_device_secret);
  if owner_id is null then
    return query select false, 0, sync_time, 'device_auth_failed'::text;
    return;
  end if;

  if p_rows is null or jsonb_typeof(p_rows) <> 'array'
     or jsonb_array_length(p_rows) < 1 or jsonb_array_length(p_rows) > 1000 then
    return query select false, 0, sync_time, 'invalid_payload'::text;
    return;
  end if;

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
        private.try_parse_timestamptz(value->>'last_used_at') as last_used_at
      from jsonb_array_elements(p_rows) value
    )
    select 1 from parsed
    where jsonb_typeof(raw) <> 'object'
       or usage_date is null
       or char_length(app_name) not between 1 and 150
       or char_length(package_name) > 300
       or char_length(window_title) not between 1 and 500
       or char_length(device_timezone) > 100
       or total_seconds is null or total_seconds not between 0 and 86400
       or (first_used_at is not null and last_used_at is not null and last_used_at < first_used_at)
  ) then
    return query select false, 0, sync_time, 'invalid_window_row'::text;
    return;
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_rows) value
    group by
      private.try_parse_date(value->>'usage_date'),
      trim(coalesce(value->>'app_name', '')),
      trim(coalesce(value->>'package_name', '')),
      trim(coalesce(value->>'window_title', ''))
    having count(*) > 1
  ) then
    return query select false, 0, sync_time, 'duplicate_window_identity'::text;
    return;
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_rows) value
    where not exists (
      select 1 from public.device_app_activity parent
      where parent.user_id = owner_id
        and parent.device_id = p_device_id
        and parent.usage_date = private.try_parse_date(value->>'usage_date')
        and parent.app_name = trim(value->>'app_name')
        and parent.package_name = trim(coalesce(value->>'package_name', ''))
    )
  ) then
    return query select false, 0, sync_time, 'parent_activity_not_found'::text;
    return;
  end if;

  insert into public.device_app_window_activity (
    user_id, device_id, activity_id, usage_date, app_name, package_name,
    window_title, total_seconds, first_used_at, last_used_at,
    device_timezone, last_synced_at
  )
  select
    owner_id,
    p_device_id,
    parent.id,
    parent.usage_date,
    parent.app_name,
    parent.package_name,
    trim(value->>'window_title'),
    private.try_parse_bigint(value->>'total_seconds'),
    private.try_parse_timestamptz(value->>'first_used_at'),
    private.try_parse_timestamptz(value->>'last_used_at'),
    trim(coalesce(value->>'device_timezone', '')),
    sync_time
  from jsonb_array_elements(p_rows) value
  join public.device_app_activity parent
    on parent.user_id = owner_id
   and parent.device_id = p_device_id
   and parent.usage_date = private.try_parse_date(value->>'usage_date')
   and parent.app_name = trim(value->>'app_name')
   and parent.package_name = trim(coalesce(value->>'package_name', ''))
  on conflict (activity_id, window_title) do update
  set total_seconds = excluded.total_seconds,
      first_used_at = excluded.first_used_at,
      last_used_at = excluded.last_used_at,
      device_timezone = excluded.device_timezone,
      last_synced_at = sync_time;

  get diagnostics affected = row_count;
  return query select true, affected, sync_time, null::text;
end;
$$;

revoke all on function public.edge_upload_device_app_window_activity(text, uuid, text, jsonb)
from public, anon, authenticated;
grant execute on function public.edge_upload_device_app_window_activity(text, uuid, text, jsonb)
to service_role;

-- Scheduling remains optional. When called by a trusted scheduler, window details
-- are removed after 30 days while app summaries retain their existing 90-day policy.
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
  delete from public.device_app_window_activity
  where usage_date < current_date - 30;

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

revoke all on function public.purge_device_sync_housekeeping()
from public, anon, authenticated;
grant execute on function public.purge_device_sync_housekeeping() to service_role;
