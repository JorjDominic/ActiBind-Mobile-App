import { createClient } from "npm:@supabase/supabase-js@2";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers });
  if (request.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405, headers });
  }
  const authorization = request.headers.get("Authorization") ?? "";
  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: { user }, error } = await userClient.auth.getUser();
  if (error || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers });
  }
  const body = await request.json().catch(() => ({}));
  if (body.confirmation !== "DELETE") {
    return new Response(JSON.stringify({ error: "Confirmation required" }), { status: 400, headers });
  }
  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
  const { error: deletionError } = await admin.auth.admin.deleteUser(user.id);
  if (deletionError) {
    console.error("Account deletion failed", deletionError.message);
    return new Response(JSON.stringify({ error: "Account deletion failed" }), { status: 500, headers });
  }
  return new Response(JSON.stringify({ deleted: true }), { status: 200, headers });
});
