create or replace function public.reconnect_registered_device(
  p_device_id uuid,
  p_pairing_code_hash text
)
returns table (device_id uuid, device_name text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  requester uuid := auth.uid();
  target public.registered_devices%rowtype;
  pairing private.device_pairing_requests%rowtype;
begin
  if requester is null then
    raise exception 'Sign in before reconnecting a device.';
  end if;

  if p_pairing_code_hash is null or p_pairing_code_hash !~ '^[0-9a-f]{64}$' then
    return;
  end if;

  select * into target
  from public.registered_devices device
  where device.id = p_device_id
    and device.user_id = requester
    and device.device_type = 'pc'
    and device.connected = false
    and device.revoked_at is not null
  for update;

  if not found then return; end if;

  select * into pairing
  from private.device_pairing_requests request
  where request.pairing_code_hash = p_pairing_code_hash
    and request.claimed_at is null
    and request.expires_at > now()
  for update;

  if not found then return; end if;

  insert into private.device_credentials (device_id, secret_hash)
  values (target.id, pairing.device_secret_hash)
  on conflict (device_id) do update
  set secret_hash = excluded.secret_hash,
      revoked_at = null,
      rotated_at = now();

  update public.registered_devices as device
  set connected = true,
      platform = pairing.platform,
      last_seen_at = now(),
      revoked_at = null,
      credential_rotation_required = false,
      pairing_code_hash = null,
      pairing_expires_at = null
  where device.id = target.id
    and device.user_id = requester;

  update private.device_pairing_requests as request
  set claimed_at = now(),
      claimed_by = requester,
      device_id = target.id
  where request.id = pairing.id;

  return query select target.id, target.name;
end;
$$;

revoke all on function public.reconnect_registered_device(uuid, text) from public;
grant execute on function public.reconnect_registered_device(uuid, text) to authenticated;
