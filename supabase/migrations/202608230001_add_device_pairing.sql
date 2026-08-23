alter table public.registered_devices
  alter column connected set default false,
  add column if not exists pairing_code_hash text,
  add column if not exists pairing_expires_at timestamptz;

create unique index if not exists registered_devices_active_pairing_code_idx
on public.registered_devices (pairing_code_hash)
where pairing_code_hash is not null;

create or replace function public.claim_registered_device(p_pairing_code_hash text)
returns table (device_id uuid, device_name text)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in before connecting a device.';
  end if;

  return query
  update public.registered_devices as device
  set connected = true,
      last_seen_at = now(),
      updated_at = now(),
      pairing_code_hash = null,
      pairing_expires_at = null
  where device.pairing_code_hash = p_pairing_code_hash
    and device.connected = false
    and device.pairing_expires_at > now()
  returning device.id, device.name;
end;
$$;

revoke all on function public.claim_registered_device(text) from public;
grant execute on function public.claim_registered_device(text) to authenticated;
