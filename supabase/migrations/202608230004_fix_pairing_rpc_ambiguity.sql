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
    pairing_code_hash, device_secret_hash, device_name, platform, expires_at
  ) values (
    p_pairing_code_hash, p_device_secret_hash, clean_name, clean_platform, server_expires_at
  ) returning id into request_id;

  return query select request_id, server_expires_at, null::text;
exception
  when unique_violation then
    return query select null::uuid, null::timestamptz, 'pairing_code_collision'::text;
end;
$$;

revoke all on function public.edge_begin_registered_device_pairing(text, text, text, text, text)
from public, anon, authenticated;
grant execute on function public.edge_begin_registered_device_pairing(text, text, text, text, text)
to service_role;
