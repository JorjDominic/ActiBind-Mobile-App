-- The mobile app is the account controller. It creates the pending PC record and
-- displays a short-lived code; the PC collector claims that code and receives only
-- a device-scoped upload credential.
create or replace function public.edge_claim_parent_registered_device_pairing(
  p_client_key text,
  p_pairing_code_hash text,
  p_device_secret_hash text
)
returns table (
  paired boolean,
  device_id uuid,
  device_name text,
  error_code text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  pending_device public.registered_devices%rowtype;
begin
  if not private.consume_edge_rate_limit('pc_pairing_claim', p_client_key, 20, 900) then
    return query select false, null::uuid, ''::text, 'rate_limited'::text;
    return;
  end if;

  if p_pairing_code_hash is null
     or p_pairing_code_hash !~ '^[0-9a-f]{64}$'
     or p_device_secret_hash is null
     or p_device_secret_hash !~ '^[0-9a-f]{64}$' then
    return query select false, null::uuid, ''::text, 'invalid_pairing_request'::text;
    return;
  end if;

  select *
  into pending_device
  from public.registered_devices device
  where device.pairing_code_hash = p_pairing_code_hash
    and device.device_type = 'pc'
    and device.connected = false
    and device.revoked_at is null
    and device.pairing_expires_at > now()
  for update;

  if not found then
    return query select false, null::uuid, ''::text, 'pairing_not_found'::text;
    return;
  end if;

  insert into private.device_credentials (device_id, secret_hash)
  values (pending_device.id, p_device_secret_hash)
  on conflict (device_id) do update
  set secret_hash = excluded.secret_hash,
      revoked_at = null,
      rotated_at = now();

  update public.registered_devices
  set connected = true,
      last_seen_at = now(),
      pairing_code_hash = null,
      pairing_expires_at = null,
      revoked_at = null,
      credential_rotation_required = false
  where id = pending_device.id;

  return query
  select true, pending_device.id, pending_device.name, null::text;
end;
$$;

revoke all on function public.edge_claim_parent_registered_device_pairing(text, text, text)
from public, anon, authenticated;
grant execute on function public.edge_claim_parent_registered_device_pairing(text, text, text)
to service_role;
