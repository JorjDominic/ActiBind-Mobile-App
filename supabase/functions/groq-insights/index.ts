const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type ChatMessage = { role: "user" | "assistant"; content: string };

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const dailyTokenLimit = Math.max(
  1000,
  Number(Deno.env.get("GROQ_DAILY_TOKEN_LIMIT")) || 180_000,
);

async function tokenBudgetRpc(name: string, body: Record<string, unknown>) {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) throw new Error("Token budget service is not configured");
  const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      "apikey": serviceKey,
      "Authorization": `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  const responseText = await response.text();
  if (!response.ok) throw new Error(`Token budget request failed: ${response.status}`);
  // PostgREST returns an empty body for void RPCs such as token settlement.
  return responseText ? JSON.parse(responseText) : null;
}

async function settleTokens(date: string, reserved: number, actual: number) {
  try {
    await tokenBudgetRpc("settle_ai_daily_tokens", {
      requested_date: date,
      reserved_tokens: reserved,
      actual_tokens: actual,
    });
  } catch (error) {
    // Keep the worst-case reservation if settlement fails. This preserves the
    // hard limit without turning a successful AI response into an app outage.
    console.error("Token budget settlement failed", String(error));
  }
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!request.headers.get("Authorization")) return json({ error: "Unauthorized" }, 401);

  const apiKey = Deno.env.get("GROQ_API_KEY");
  if (!apiKey) return json({ error: "Insights service is not configured" }, 503);

  let stage = "request";
  try {
    const body = await request.json();
    const prompt = typeof body.prompt === "string" ? body.prompt.trim() : "";
    if (body.mode === "diagnostics") {
      const now = new Date();
      const usageDate = now.toISOString().slice(0, 10);
      const tokensUsed = await tokenBudgetRpc("read_ai_daily_tokens", {
        requested_date: usageDate,
      });
      const reset = new Date(`${usageDate}T00:00:00.000Z`);
      reset.setUTCDate(reset.getUTCDate() + 1);
      return json({
        model: Deno.env.get("GROQ_MODEL") ?? "openai/gpt-oss-20b",
        daily_token_limit: dailyTokenLimit,
        tokens_used_today: Number(tokensUsed) || 0,
        resets_at: reset.toISOString(),
        server_time: now.toISOString(),
        region: Deno.env.get("SB_REGION") ?? "Unknown",
        deployment_id: Deno.env.get("DENO_DEPLOYMENT_ID") ?? "Unknown",
        jwt_verification: "enabled",
      });
    }
    const mode = ["home", "daily", "chat", "weather"].includes(body.mode) ? body.mode : "chat";
    if (!prompt || prompt.length > 1000) return json({ error: "Invalid prompt" }, 400);

    const activities = Array.isArray(body.activities) ? body.activities.slice(0, 100) : [];
    const usage = Array.isArray(body.usage) ? body.usage.slice(0, 20) : [];
    const pcUsage = Array.isArray(body.pc_usage) ? body.pc_usage.slice(0, 200) : [];
    const devices = Array.isArray(body.devices) ? body.devices.slice(0, 30) : [];
    const routines = Array.isArray(body.routines) ? body.routines.slice(0, 100) : [];
    const routineOccurrences = Array.isArray(body.routine_occurrences)
      ? body.routine_occurrences.slice(0, 200)
      : [];
    const todos = Array.isArray(body.todos) ? body.todos.slice(0, 150) : [];
    const notes = Array.isArray(body.notes) ? body.notes.slice(0, 30) : [];
    const familyProfiles = Array.isArray(body.family_profiles)
      ? body.family_profiles.slice(0, 20)
      : [];
    const history: ChatMessage[] = Array.isArray(body.history)
      ? body.history
          .filter((item: ChatMessage) =>
            ["user", "assistant"].includes(item?.role) &&
            typeof item?.content === "string" &&
            item.content.length <= 2000
          )
          .slice(-8)
      : [];

    const system = [
      "You are ActiBind's activity insights assistant.",
      "Use only the supplied context; never invent statistics.",
      "Analyze phone and PC usage together, while clearly distinguishing device sources and date ranges.",
      "Phone usage is a current-day snapshot only. Never copy or infer it into earlier dates. PC rows contain their own usage_date and may be compared by date.",
      "Use schedules, routines and their completion states, tasks, notes, connected-device status, and family profiles when relevant.",
      "Prefer meaningful relationships across sources over generic productivity or focus advice.",
      "Design every response for a narrow mobile screen: never use Markdown tables, ASCII tables, columns, or raw data dumps.",
      "Start with one direct takeaway, then use at most four short bullet points only when they improve clarity. Each bullet must contain one idea.",
      "Mention no more than five app names unless the user explicitly asks for a longer list.",
      "Summarize evidence instead of repeating every supplied record.",
      "If data is insufficient, say so briefly and still offer a practical suggestion.",
      "Do not provide medical diagnoses. Be concise, supportive, and specific.",
      mode === "weather"
        ? "Use the supplied weather and schedule together. Return one practical sentence under 35 words. Do not invent a forecast or claim that current observations predict future conditions."
        : mode === "home"
        ? "Return at most two short sentences."
        : mode === "chat"
        ? "Return at most 160 words, using short paragraphs suitable for a phone."
        : "Return at most 100 words, using short paragraphs suitable for a phone.",
    ].join(" ");
    const context = JSON.stringify({
      local_time: body.local_time,
      timezone: body.timezone,
      recent_activities: activities,
      phone_usage_today: usage,
      pc_usage_by_day: pcUsage,
      registered_devices: devices,
      routines,
      routine_occurrences: routineOccurrences,
      tasks: todos,
      notes,
      family_profiles: familyProfiles,
      weather: body.weather,
    });

    const maxCompletionTokens = mode === "weather"
      ? 256
      : mode === "home"
      ? 384
      : mode === "chat"
      ? 640
      : 480;
    const messages = [
      { role: "system", content: system },
      { role: "system", content: `User context: ${context}` },
      ...history,
      { role: "user", content: prompt },
    ];
    // Reserve a worst-case allowance before calling Groq. The reservation is
    // settled to the provider's actual usage afterward, preventing concurrent
    // requests from exceeding the shared daily budget.
    const estimatedInputTokens = Math.ceil(JSON.stringify(messages).length / 4) + 128;
    const reservedTokens = estimatedInputTokens + maxCompletionTokens;
    const usageDate = new Date().toISOString().slice(0, 10);
    let reserved: unknown;
    try {
      reserved = await tokenBudgetRpc("reserve_ai_daily_tokens", {
        requested_date: usageDate,
        requested_tokens: reservedTokens,
        token_limit: dailyTokenLimit,
      });
    } catch (error) {
      console.error("Token budget reservation failed", String(error));
      return json({ error: "AI token budget is temporarily unavailable" }, 503);
    }
    if (reserved !== true) {
      return json({ error: "Daily AI token limit reached. Try again tomorrow." }, 429);
    }

    let groqResponse: Response;
    try {
      stage = "provider request";
      groqResponse = await fetch("https://api.groq.com/openai/v1/chat/completions", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: Deno.env.get("GROQ_MODEL") ?? "openai/gpt-oss-20b",
          temperature: 0.35,
          reasoning_effort: "low",
          max_completion_tokens: maxCompletionTokens,
          messages,
        }),
      });
    } catch (error) {
      await settleTokens(usageDate, reservedTokens, 0);
      throw error;
    }

    if (!groqResponse.ok) {
      const errorText = await groqResponse.text();
      console.error("Groq request failed", groqResponse.status, errorText.slice(0, 300));
      await settleTokens(usageDate, reservedTokens, 0);
      return json({ error: "AI provider request failed" }, 502);
    }
    stage = "provider response";
    const result = await groqResponse.json();
    const actualTokens = Number(result?.usage?.total_tokens);
    await settleTokens(
      usageDate,
      reservedTokens,
      Number.isFinite(actualTokens) && actualTokens >= 0 ? actualTokens : reservedTokens,
    );
    const insight = result?.choices?.[0]?.message?.content;
    if (typeof insight !== "string" || !insight.trim()) {
      return json({ error: "AI provider returned no insight" }, 502);
    }
    return json({ insight: insight.trim() });
  } catch (error) {
    console.error("Insight function error", stage, String(error));
    return json({ error: "Unable to generate insight", stage }, 500);
  }
});
