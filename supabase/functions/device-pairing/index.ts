import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function respond(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

async function sha256(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function rateLimitKey(request: Request) {
  const secret = Deno.env.get("DEVICE_RATE_LIMIT_SALT") ??
    Deno.env.get("DEVICE_SYNC_RATE_LIMIT_SECRET");
  if (!secret) throw new Error("rate_limit_secret_missing");
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

function pairingCode() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const random = new Uint32Array(8);
  crypto.getRandomValues(random);
  return Array.from(random, (value) => alphabet[value % alphabet.length]).join("");
}

function field(body: Record<string, unknown>, ...names: string[]) {
  for (const name of names) if (typeof body[name] === "string") return body[name] as string;
  return "";
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (request.method !== "POST") return respond({ success: false, error: "method_not_allowed" }, 405);

  try {
    const declaredSize = Number(request.headers.get("content-length") ?? "0");
    if (declaredSize > 64_000) return respond({ success: false, error: "payload_too_large" }, 413);
    const body = await request.json() as Record<string, unknown>;
    const action = field(body, "action") || "create";
    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serviceKey) throw new Error("service_configuration_missing");
    const client = createClient(url, serviceKey, { auth: { persistSession: false } });
    const clientKey = await rateLimitKey(request);

    if (action === "create" || action === "begin" || action === "begin_pairing") {
      const deviceName = field(body, "device_name", "deviceName").trim();
      const platform = field(body, "platform").trim() || "Windows";
      const secretHash = field(body, "device_secret_hash", "deviceSecretHash").toLowerCase();
      const suppliedCodeHash = field(body, "pairing_code_hash", "pairingCodeHash").toLowerCase();
      if (!deviceName) {
        return respond({
          success: false,
          error: "invalid_pairing_request",
          message: "device_name is required.",
        }, 400);
      }
      if (!/^[0-9a-f]{64}$/.test(secretHash)) {
        return respond({
          success: false,
          error: "invalid_pairing_request",
          message: "device_secret_hash must be a 64-character lowercase SHA-256 value.",
        }, 400);
      }
      if (suppliedCodeHash && !/^[0-9a-f]{64}$/.test(suppliedCodeHash)) {
        return respond({
          success: false,
          error: "invalid_pairing_request",
          message: "pairing_code_hash must be a 64-character lowercase SHA-256 value.",
        }, 400);
      }
      const code = suppliedCodeHash ? "" : pairingCode();
      const { data, error } = await client.rpc("edge_begin_registered_device_pairing", {
        p_client_key: clientKey,
        p_device_name: deviceName,
        p_platform: platform,
        p_pairing_code_hash: suppliedCodeHash || await sha256(code),
        p_device_secret_hash: secretHash,
      });
      if (error) throw new Error(`pairing_rpc:${error.code}`);
      const result = Array.isArray(data) ? data[0] : data;
      if (!result || result.error_code) {
        const status = result?.error_code === "rate_limited"
          ? 429
          : result?.error_code === "pairing_capacity_reached"
          ? 503
          : result?.error_code === "pairing_code_collision"
          ? 409
          : result
          ? 400
          : 500;
        return respond(
          result ?? { error_code: "empty_response" },
          status,
        );
      }
      const response: Record<string, unknown> = suppliedCodeHash
        ? {
          pairing_request_id: result.pairing_request_id,
          expires_at: result.expires_at,
          error_code: null,
        }
        : {
          success: true,
          pairing_code: code,
          pairing_id: result.pairing_request_id,
          pairing_request_id: result.pairing_request_id,
          expires_at: result.expires_at,
        };
      // If the PC supplied only a hash, it already owns and displays the raw code;
      // a one-way hash cannot and must not be reversed by the server.
      return respond(response);
    }

    if (action === "poll") {
      const { data, error } = await client.rpc("edge_poll_registered_device_pairing", {
        p_client_key: clientKey,
        p_pairing_request_id: field(
          body,
          "pairing_request_id",
          "pairing_id",
          "pairingId",
        ),
        p_device_secret: field(body, "device_secret", "deviceSecret"),
      });
      if (error) throw new Error(`poll_rpc:${error.code}`);
      const result = Array.isArray(data) ? data[0] : data;
      if (result?.error_code === "rate_limited") return respond(result, 429);
      return respond(result ?? { error_code: "empty_response" }, result ? 200 : 500);
    }

    if (action === "cancel") {
      const { data, error } = await client.rpc("edge_cancel_registered_device_pairing", {
        p_client_key: clientKey,
        p_pairing_request_id: field(
          body,
          "pairing_request_id",
          "pairing_id",
          "pairingId",
        ),
        p_device_secret: field(body, "device_secret", "deviceSecret"),
      });
      if (error) throw new Error(`cancel_rpc:${error.code}`);
      return respond({ ok: data === true, success: data === true });
    }

    return respond({ success: false, error: "invalid_action" }, 400);
  } catch (error) {
    const diagnostic = error instanceof Error ? error.message : "unknown";
    console.error("device-pairing failed", diagnostic);
    return respond({ success: false, error: "server_error", diagnostic }, 500);
  }
});
