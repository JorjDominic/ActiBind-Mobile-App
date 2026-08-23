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
    device.connected,
    device.revoked_at is not null,
    device.credential_rotation_required,
    device.last_seen_at,
    null::text
  from public.registered_devices device
  where device.id = p_device_id
    and device.user_id = owner_id;
end;
$$;

revoke all on function public.edge_get_registered_device_status(text, uuid, text)
from public, anon, authenticated;
grant execute on function public.edge_get_registered_device_status(text, uuid, text)
to service_role;
