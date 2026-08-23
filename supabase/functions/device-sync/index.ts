import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

async function clientKey(request: Request) {
  const secret = Deno.env.get("DEVICE_RATE_LIMIT_SALT") ??
    Deno.env.get("DEVICE_SYNC_RATE_LIMIT_SECRET");
  if (!secret) throw new Error("Device sync rate-limit secret is not configured");
  const forwarded = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  const identity = forwarded || request.headers.get("cf-connecting-ip") || "unknown";
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(identity));
  return Array.from(new Uint8Array(signature), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

const actions: Record<string, { rpc: string; params: Record<string, string> }> = {
  begin_pairing: {
    rpc: "edge_begin_registered_device_pairing",
    params: { device_name: "p_device_name", platform: "p_platform", pairing_code_hash: "p_pairing_code_hash", device_secret_hash: "p_device_secret_hash" },
  },
  poll_pairing: {
    rpc: "edge_poll_registered_device_pairing",
    params: { pairing_request_id: "p_pairing_request_id", device_secret: "p_device_secret" },
  },
  cancel_pairing: {
    rpc: "edge_cancel_registered_device_pairing",
    params: { pairing_request_id: "p_pairing_request_id", device_secret: "p_device_secret" },
  },
  status: {
    rpc: "edge_get_registered_device_status",
    params: { device_id: "p_device_id", device_secret: "p_device_secret" },
  },
  check_connection: {
    rpc: "edge_get_registered_device_status",
    params: { device_id: "p_device_id", device_secret: "p_device_secret" },
  },
  check_status: {
    rpc: "edge_get_registered_device_status",
    params: { device_id: "p_device_id", device_secret: "p_device_secret" },
  },
  upload_activity: {
    rpc: "edge_upload_device_app_activity",
    params: { device_id: "p_device_id", device_secret: "p_device_secret", rows: "p_rows" },
  },
  upload: {
    rpc: "edge_upload_device_app_activity",
    params: { device_id: "p_device_id", device_secret: "p_device_secret", rows: "p_rows" },
  },
  rotate_credential: {
    rpc: "edge_rotate_registered_device_credential",
    params: { device_id: "p_device_id", current_device_secret: "p_current_device_secret", new_device_secret_hash: "p_new_device_secret_hash" },
  },
  disconnect: {
    rpc: "edge_disconnect_registered_device_by_device",
    params: { device_id: "p_device_id", device_secret: "p_device_secret" },
  },
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  try {
    const contentLength = Number(request.headers.get("content-length") ?? "0");
    if (contentLength > 512_000) return json({ error: "payload_too_large" }, 413);
    const rawBody = await request.json() as Record<string, unknown>;
    const body: Record<string, unknown> = {
      ...rawBody,
      device_id: rawBody.device_id ?? rawBody.deviceId,
      device_secret: rawBody.device_secret ?? rawBody.deviceSecret,
      rows: rawBody.rows ?? rawBody.activities ?? rawBody.activity_rows,
      current_device_secret:
        rawBody.current_device_secret ?? rawBody.currentDeviceSecret,
      new_device_secret_hash:
        rawBody.new_device_secret_hash ?? rawBody.newDeviceSecretHash,
    };
    const action = typeof body.action === "string" ? actions[body.action] : null;
    if (!action) return json({ error_code: "invalid_action" }, 400);

    const params: Record<string, unknown> = { p_client_key: await clientKey(request) };
    for (const [input, rpcName] of Object.entries(action.params)) params[rpcName] = body[input];

    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serviceKey) throw new Error("Supabase service configuration is missing");
    const supabase = createClient(url, serviceKey, { auth: { persistSession: false } });
    const { data, error } = await supabase.rpc(action.rpc, params);
    if (error) {
      console.error("device-sync RPC failed", { action: body.action, code: error.code });
      return json({
        error_code: "device_sync_failed",
        diagnostic: error.code,
      }, 500);
    }
    const result = Array.isArray(data) ? data[0] : data;
    if (result && typeof result === "object" && "error_code" in result) {
      const errorCode = (result as Record<string, unknown>).error_code;
      const status = errorCode === "rate_limited" ? 429 : 200;
      return json(result, status);
    }
    if (typeof result === "boolean") return json({ ok: result });
    return json(result ?? { error_code: "empty_response" }, result == null ? 500 : 200);
  } catch (error) {
    console.error("device-sync request failed", error instanceof Error ? error.message : "unknown");
    return json({ error_code: "invalid_request" }, 400);
  }
});
