-- PC pairing is initiated by the collector through device-pairing. Remove the
-- temporary reverse-flow RPC so there is one authoritative PC pairing path.
drop function if exists public.edge_claim_parent_registered_device_pairing(text, text, text);
