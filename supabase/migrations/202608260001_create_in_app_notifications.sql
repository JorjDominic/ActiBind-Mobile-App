create table if not exists public.app_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  notification_key text not null,
  notification_type text not null default 'general',
  title text not null,
  body text not null,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  constraint app_notifications_user_key unique (user_id, notification_key),
  constraint app_notifications_type_check
    check (notification_type in ('break_warning', 'activity', 'routine', 'general')),
  constraint app_notifications_title_check check (char_length(title) between 1 and 160),
  constraint app_notifications_body_check check (char_length(body) between 1 and 500)
);

create index if not exists app_notifications_user_created_idx
on public.app_notifications (user_id, created_at desc);

alter table public.app_notifications enable row level security;
grant select, update, delete on public.app_notifications to authenticated;
revoke insert on public.app_notifications from authenticated, anon;

create policy "Users can view their own app notifications"
on public.app_notifications for select to authenticated
using ((select auth.uid()) = user_id);

create policy "Users can update their own app notifications"
on public.app_notifications for update to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "Users can delete their own app notifications"
on public.app_notifications for delete to authenticated
using ((select auth.uid()) = user_id);
