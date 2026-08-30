create table if not exists public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  activity_reminders boolean not null default true,
  routine_reminders boolean not null default true,
  phone_breaks boolean not null default true,
  pc_breaks boolean not null default true,
  daily_summary boolean not null default true,
  quiet_hours boolean not null default false,
  quiet_start_hour smallint not null default 22 check (quiet_start_hour between 0 and 23),
  quiet_end_hour smallint not null default 7 check (quiet_end_hour between 0 and 23),
  updated_at timestamptz not null default now()
);

alter table public.notification_preferences enable row level security;
grant select, insert, update, delete on public.notification_preferences to authenticated;

create policy "Users manage their notification preferences"
on public.notification_preferences for all to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);
