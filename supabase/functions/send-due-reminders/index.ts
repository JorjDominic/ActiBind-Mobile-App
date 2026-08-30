import { createClient } from "npm:@supabase/supabase-js@2";

type TokenRow = {
  token: string;
  user_id: string;
  timezone: string;
};

type Reminder = {
  key: string;
  userId: string;
  title: string;
  body: string;
};

const officialAppNames: Record<string, string> = {
  chrome: "Google Chrome",
  "google chrome": "Google Chrome",
  msedge: "Microsoft Edge",
  "microsoft edge": "Microsoft Edge",
  firefox: "Mozilla Firefox",
  brave: "Brave",
  "brave browser": "Brave",
  opera: "Opera",
  "opera gx": "Opera GX",
  code: "Visual Studio Code",
  "visual studio code": "Visual Studio Code",
  devenv: "Microsoft Visual Studio",
  discord: "Discord",
  slack: "Slack",
  teams: "Microsoft Teams",
  "ms-teams": "Microsoft Teams",
  spotify: "Spotify",
  steam: "Steam",
  epicgameslauncher: "Epic Games Launcher",
  vlc: "VLC media player",
  winword: "Microsoft Word",
  excel: "Microsoft Excel",
  powerpnt: "Microsoft PowerPoint",
  outlook: "Microsoft Outlook",
  onenote: "Microsoft OneNote",
  notepad: "Notepad",
  explorer: "File Explorer",
  photos: "Microsoft Photos",
  applicationframehost: "Microsoft Store app",
};

function officialAppName(appName: string, packageName = "") {
  for (const value of [appName, packageName]) {
    const normalized = value.trim().replace(/\.exe$/i, "").toLowerCase();
    if (officialAppNames[normalized]) return officialAppNames[normalized];
  }
  return appName.trim().replace(/\.exe$/i, "") || "Unknown app";
}

function response(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function base64Url(value: Uint8Array | string) {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function privateKeyBytes(pem: string) {
  const encoded = pem
    .replaceAll("\\n", "\n")
    .replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "");
  return Uint8Array.from(atob(encoded), (character) => character.charCodeAt(0));
}

async function firebaseAccessToken() {
  const clientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL");
  const privateKey = Deno.env.get("FIREBASE_PRIVATE_KEY");
  if (!clientEmail || !privateKey) throw new Error("Firebase credentials are missing");
  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64Url(JSON.stringify({
    iss: clientEmail,
    sub: clientEmail,
    aud: "https://oauth2.googleapis.com/token",
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${claims}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    privateKeyBytes(privateKey),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const assertion = `${unsigned}.${base64Url(new Uint8Array(signature))}`;
  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!tokenResponse.ok) throw new Error(`Firebase authentication failed: ${tokenResponse.status}`);
  const tokenJson = await tokenResponse.json();
  return tokenJson.access_token as string;
}

function localParts(date: Date, timezone: string) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
    weekday: "short",
  }).formatToParts(date);
  const get = (type: string) => parts.find((part) => part.type === type)?.value ?? "";
  const weekday = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].indexOf(get("weekday")) + 1;
  return {
    date: `${get("year")}-${get("month")}-${get("day")}`,
    minute: Number(get("hour")) * 60 + Number(get("minute")),
    weekday,
  };
}

function timeMinutes(value: string) {
  const [hour, minute] = value.split(":").map(Number);
  return hour * 60 + minute;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return response({ error: "Method not allowed" }, 405);
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const projectId = Deno.env.get("FIREBASE_PROJECT_ID");
  if (!supabaseUrl || !serviceKey || !projectId) {
    return response({ error: "Server configuration is incomplete" }, 503);
  }
  const supabase = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  const suppliedSecret = request.headers.get("x-cron-secret") ?? "";
  const { data: authorized, error: authorizationError } = await supabase.rpc(
    "verify_reminder_cron_secret",
    { candidate: suppliedSecret },
  );
  if (authorizationError || authorized !== true) {
    return response({ error: "Unauthorized" }, 401);
  }

  try {
    const now = new Date();
    const lowerStart = new Date(now.getTime() - 60_000).toISOString();
    const upperStart = new Date(now.getTime() + 61 * 60_000).toISOString();
    const lowerEnd = new Date(now.getTime() - 60_000).toISOString();
    const upperEnd = new Date(now.getTime() + 60_000).toISOString();
    const [{ data: tokens, error: tokenError }, { data: starting }, { data: ending }, { data: preferenceRows }] = await Promise.all([
      supabase.from("device_push_tokens").select("token,user_id,timezone"),
      supabase.from("activities").select("id,user_id,name,starts_at,reminder_minutes").gte("starts_at", lowerStart).lt("starts_at", upperStart),
      supabase.from("activities").select("id,user_id,name,ends_at").gte("ends_at", lowerEnd).lt("ends_at", upperEnd),
      supabase.from("notification_preferences").select("*"),
    ]);
    if (tokenError) throw tokenError;
    const tokenRows = (tokens ?? []) as TokenRow[];
    const reminders: Reminder[] = [
      ...new Set(tokenRows.map((token) => token.user_id)),
    ].map((userId) => ({
      key: `system:fcm-ready-v3:${userId}`,
      userId,
      title: "ActiBind notifications are ready",
      body: "Background activity and routine reminders are now connected.",
    }));
    for (const activity of starting ?? []) {
      const startDelta = (new Date(activity.starts_at).getTime() - now.getTime()) / 60_000;
      const advance = activity.reminder_minutes ?? 5;
      if (advance > 0 && startDelta >= advance - 1 && startDelta <= advance + 1) {
        reminders.push({
          key: `activity:${activity.id}:advance:${advance}:${activity.starts_at}`,
          userId: activity.user_id,
          title: "Activity starting soon",
          body: `${activity.name} starts in ${advance} minutes.`,
        });
      }
      if (startDelta >= -1 && startDelta <= 1) {
        reminders.push({
          key: `activity:${activity.id}:start:${activity.starts_at}`,
          userId: activity.user_id,
          title: "Activity started",
          body: `${activity.name} is starting now.`,
        });
      }
    }
    for (const activity of ending ?? []) {
      reminders.push({
        key: `activity:${activity.id}:end:${activity.ends_at}`,
        userId: activity.user_id,
        title: "Activity time is over",
        body: `${activity.name} has reached its scheduled end time.`,
      });
    }

    const timezoneUsers = new Map<string, Set<string>>();
    for (const token of tokenRows) {
      if (!timezoneUsers.has(token.timezone)) timezoneUsers.set(token.timezone, new Set());
      timezoneUsers.get(token.timezone)!.add(token.user_id);
    }
    for (const [timezone, users] of timezoneUsers) {
      const local = localParts(now, timezone);
      const userIds = [...users];
      if (!userIds.length) continue;
      const [{ data: pcUsage }, { data: registeredDevices }] = await Promise.all([
        supabase
          .from("device_app_activity")
          .select("id,user_id,device_id,app_name,package_name,total_seconds")
          .in("user_id", userIds)
          .eq("usage_date", local.date)
          .gte("total_seconds", 2 * 60 * 60),
        supabase
          .from("registered_devices")
          .select("id,name")
          .in("user_id", userIds)
          .eq("device_type", "pc"),
      ]);
      const pcDeviceIds = new Set(
        (registeredDevices ?? []).map((device) => device.id),
      );
      const deviceNames = new Map(
        (registeredDevices ?? []).map((device) => [device.id, device.name]),
      );
      for (const usage of pcUsage ?? []) {
        if (!pcDeviceIds.has(usage.device_id)) continue;
        const appName = officialAppName(usage.app_name, usage.package_name ?? "");
        const deviceName = deviceNames.get(usage.device_id) ?? "your PC";
        reminders.push({
          key: `pc-break:${usage.device_id}:${usage.id}:${local.date}:2h`,
          userId: usage.user_id,
          title: "Time for a break on your PC",
          body: `PC/Laptop activity on ${deviceName}: ${appName} has been used for at least 2 hours. Consider taking a short break.`,
        });
      }
      const { data: routines } = await supabase
        .from("routines")
        .select("id,user_id,name,start_time,end_time,active_days,starts_on,ends_on,reminder_minutes")
        .in("user_id", userIds)
        .eq("active", true)
        .lte("starts_on", local.date)
        .or(`ends_on.is.null,ends_on.gte.${local.date}`);
      const { data: occurrences } = await supabase
        .from("routine_occurrences")
        .select("routine_id,status")
        .in("user_id", userIds)
        .eq("scheduled_date", local.date);
      const statuses = new Map((occurrences ?? []).map((item) => [item.routine_id, item.status]));
      for (const routine of routines ?? []) {
        if (!routine.active_days.includes(local.weekday) || (statuses.get(routine.id) ?? "scheduled") !== "scheduled") continue;
        const startDelta = timeMinutes(routine.start_time) - local.minute;
        const advance = routine.reminder_minutes ?? 5;
        if (advance > 0 && startDelta >= advance - 1 && startDelta <= advance + 1) {
          reminders.push({
            key: `routine:${routine.id}:advance:${advance}:${local.date}`,
            userId: routine.user_id,
            title: "Routine starting soon",
            body: `${routine.name} starts in ${advance} minutes.`,
          });
        }
        if (startDelta >= -1 && startDelta <= 1) {
          reminders.push({
            key: `routine:${routine.id}:start:${local.date}`,
            userId: routine.user_id,
            title: "Routine started",
            body: `${routine.name} is starting now.`,
          });
        }
        const endDelta = timeMinutes(routine.end_time) - local.minute;
        if (endDelta >= -1 && endDelta <= 1) {
          reminders.push({
            key: `routine:${routine.id}:end:${local.date}`,
            userId: routine.user_id,
            title: "Routine time is over",
            body: `${routine.name} has reached its scheduled end time.`,
          });
        }
      }
    }

    const preferences = new Map((preferenceRows ?? []).map((item) => [item.user_id, item]));
    const userTimezone = new Map(tokenRows.map((item) => [item.user_id, item.timezone]));
    const enabledReminders = reminders.filter((reminder) => {
      const preference = preferences.get(reminder.userId);
      if (!preference) return true;
      if (reminder.key.startsWith("activity:") && !preference.activity_reminders) return false;
      if (reminder.key.startsWith("routine:") && !preference.routine_reminders) return false;
      if (reminder.key.startsWith("pc-break:") && !preference.pc_breaks) return false;
      if (preference.quiet_hours && !reminder.key.startsWith("system:")) {
        const local = localParts(now, userTimezone.get(reminder.userId) ?? "UTC");
        const hour = Math.floor(local.minute / 60);
        const start = preference.quiet_start_hour;
        const end = preference.quiet_end_hour;
        const quiet = start > end ? hour >= start || hour < end : hour >= start && hour < end;
        if (quiet) return false;
      }
      return true;
    });
    reminders.length = 0;
    reminders.push(...enabledReminders);
    if (!reminders.length) return response({ checked: true, sent: 0 });
    const inboxRows = reminders
      .filter((reminder) => !reminder.key.startsWith("system:"))
      .map((reminder) => ({
        user_id: reminder.userId,
        notification_key: reminder.key,
        notification_type: reminder.key.startsWith("pc-break:")
          ? "break_warning"
          : reminder.key.startsWith("activity:")
          ? "activity"
          : reminder.key.startsWith("routine:")
          ? "routine"
          : "general",
        title: reminder.title,
        body: reminder.body,
      }));
    if (inboxRows.length) {
      const { error: inboxError } = await supabase
        .from("app_notifications")
        .upsert(inboxRows, { onConflict: "user_id,notification_key", ignoreDuplicates: true });
      if (inboxError) console.error("In-app notification sync failed", inboxError.message);
    }
    const accessToken = await firebaseAccessToken();
    let sent = 0;
    for (const reminder of reminders) {
      const { error: claimError } = await supabase.from("push_notification_deliveries").insert({
        delivery_key: reminder.key,
        user_id: reminder.userId,
      });
      if (claimError) continue;
      let sentForReminder = 0;
      for (const device of tokenRows.filter((token) => token.user_id === reminder.userId)) {
        const firebaseResponse = await fetch(
          `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${accessToken}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              message: {
                token: device.token,
                notification: { title: reminder.title, body: reminder.body },
                data: {
                  title: reminder.title,
                  body: reminder.body,
                  notification_key: reminder.key,
                  type: reminder.key.split(":", 1)[0],
                  sent_at: now.toISOString(),
                },
                android: {
                  priority: "high",
                  ttl: "86400s",
                  collapse_key: reminder.key,
                  notification: {
                    channel_id: reminder.key.startsWith("pc-break:")
                      ? "wellbeing_break_reminders_v1"
                      : "schedule_reminders_v3",
                    notification_priority: "PRIORITY_MAX",
                    visibility: "PUBLIC",
                    sound: "default",
                  },
                },
              },
            }),
          },
        );
        if (firebaseResponse.ok) {
          sent++;
          sentForReminder++;
        } else {
          const errorText = await firebaseResponse.text();
          if (errorText.includes("UNREGISTERED")) {
            await supabase.from("device_push_tokens").delete().eq("token", device.token);
          }
          console.error("FCM send failed", firebaseResponse.status, errorText.slice(0, 300));
        }
      }
      if (sentForReminder === 0) {
        await supabase
          .from("push_notification_deliveries")
          .delete()
          .eq("delivery_key", reminder.key);
      }
    }
    return response({ checked: true, sent });
  } catch (error) {
    console.error("Reminder sender failed", String(error));
    return response({ error: "Unable to send reminders" }, 500);
  }
});
