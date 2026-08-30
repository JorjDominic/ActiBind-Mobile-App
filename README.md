# ActiBind

ActiBind is a Flutter activity planner and digital-wellbeing application. It
combines schedules, routines, tasks, notes, phone usage, synchronized computer
activity, weather, holidays, reminders, widgets, family controls, and
privacy-controlled AI analysis.

This README is both a user guide and a developer setup guide.

## Contents

- [Features](#features)
- [User guide](#user-guide)
- [Notifications](#notifications)
- [AI insights and privacy](#ai-insights-and-privacy)
- [Permissions](#permissions)
- [Development setup](#development-setup)
- [Backend setup and deployment](#backend-setup-and-deployment)
- [Project structure](#project-structure)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)
- [Release preparation](#release-preparation)

## Features

### Planning and organization

- Create, edit, complete, and delete scheduled activities.
- Configure categories, start/end times, repeat behavior, conflict warnings,
  usage monitoring, and reminder lead times.
- Detect overlapping activities.
- Create recurring routines with active weekdays, date ranges, completion
  states, monitoring, and reminders.
- Maintain prioritized to-do items with due dates, details, and completion
  history.
- Create personal notes.
- Display Philippine public holidays in the planner.

### Device activity and digital wellbeing

- Read Android foreground-app usage after Usage Access is granted.
- Show device-use totals, top apps, trends, and planned-time share.
- Synchronize app activity from registered PC/laptop devices.
- Display activity by date, device, application, and window title.
- Treat Chrome/browser tab titles as optional sensitive data.
- Send phone and PC/laptop break reminders at the 2, 3, 4, 5, 6, 7,
  and 8-hour app-usage milestones.
- Give every milestone a unique delivery identity to prevent duplicates.

### AI insights

- Generate home insights and more detailed daily analysis.
- Ask follow-up questions in the Insights Assistant.
- Analyze schedules, routine completion, tasks, usage, device freshness,
  optional browser titles, weather, holidays, and selected family context.
- Distinguish phone usage from named PC/laptop sources.
- Send optional private sources only after the user enables them.
- Proxy Groq requests through an authenticated Supabase Edge Function.
- Enforce a server-side shared daily token budget.
- Provide a schedule/task fallback for home and daily cards when AI is
  temporarily unavailable.

### Weather and holidays

- Load temperature, apparent temperature, humidity, wind, condition, and
  observation time from Open-Meteo.
- Use the device location when available, with Manila as the fallback.
- Generate weather-aware planning tips.
- Load public holidays through Nager.Date.

### Notifications

- Deliver Android activity and routine reminders through Firebase Cloud
  Messaging while the app is foregrounded, backgrounded, or terminated.
- Maintain an in-app notification inbox.
- Label sources as Phone activity, PC/Laptop activity, Schedule, All devices,
  or ActiBind.
- Show local sent time and relative age.
- Configure activity, routine, phone-break, PC-break, and daily-summary alerts.
- Apply server-synchronized quiet hours.
- Scan due reminders every minute through Supabase Cron.
- Remove unregistered Firebase tokens after provider rejection.

### Android home-screen widgets

- To-do widget
- Next activity widget
- Daily insight widget

Widgets retain the last successful content while offline.

### Account and privacy

- Email/password registration, sign-in, session restoration, and password
  reset.
- Profile-name editing and system/light/dark themes.
- Export accessible account records as formatted JSON copied to the clipboard.
- Permanently delete the authenticated account and associated cascading data.
- Independently control whether AI may receive device activity, browser
  titles, notes, family profiles, weather, and holidays.
- Browser titles, notes, and family profiles are excluded from AI by default.

### Family and protected mode

- Enable or hide Family mode in Settings.
- Create child profiles and configure screen-time/app restrictions.
- Select allowed and restricted Android applications.
- Start temporary or profile-based protected sessions.
- Use optional Android device-admin and accessibility capabilities.
- Restore an active protected session after restarting the app.

### Developer diagnostics

Developer mode exposes AI model/status/latency/token usage, authentication
state, application version, platform, build mode, locale, time zone, display
information, and cache status without showing secrets or access tokens.

## User guide

### 1. Sign in

Launch ActiBind and register with an email/password or sign in. Sessions are
persisted and refreshed automatically. Use **Settings > Security** to request a
password-reset email.

### 2. Use Overview

Overview contains phone and computer usage totals, upcoming plans, conflicts,
quick activity/routine actions, weather, top apps, and the latest AI insight.

### 3. Create an activity

1. Open **Activity**.
2. Choose a planner date and add an activity.
3. Enter its name, category, start/end time, repeat option, reminder timing,
   and monitoring preferences.
4. Review any conflict warning and save.
5. Edit, complete, or delete it later from the planner.

### 4. Create a routine

1. Open the routine section under **Activity**.
2. Add its name, time range, weekdays, and optional date range.
3. Configure reminders and monitoring.
4. Mark each occurrence scheduled, complete, or skipped.

### 5. Manage tasks and notes

Use the task list for priorities, due dates, details, and completion. Notes can
store supporting information. Note content is not sent to AI unless enabled in
**Settings > AI data controls**.

### 6. Enable phone activity

1. Open Android Usage Access when prompted.
2. Enable ActiBind.
3. Return to **Activity** or **Insights** and refresh.

ActiBind reads aggregated foreground usage from Android and excludes its own
foreground time.

### 7. Review PC/laptop activity

After a supported companion source is registered and synchronized:

1. Open device activity.
2. Choose a PC/laptop.
3. Review applications, durations, dates, and synchronization freshness.
4. Open an application breakdown for synchronized window/tab titles.

Window titles may be collected by the companion source, but including them in
AI requests is independently disabled by default.

### 8. Use Insights

Open **Insights** to review progress, activity rhythm, device/app totals, and
the assistant. Example questions:

- “Which apps interrupted my planned focus time?”
- “How did my phone and laptop activity differ this week?”
- “Which Chrome tabs took the most time?”
- “What should I reschedule because of today's weather?”

The assistant uses only sources enabled under **AI data controls**.

### 9. Configure notifications

Open **Settings > Notification preferences** to toggle activity reminders,
routine reminders, phone and PC/laptop break warnings, daily summaries, and
quiet hours. Preferences are stored locally and synchronized to Supabase.

### 10. Export or delete data

For export, open **Settings > Export my data**. A JSON export is copied to the
clipboard; paste it into a trusted editor and save it securely.

For deletion, open **Settings > Delete account and data**, type `DELETE`, and
confirm. Deletion cannot be undone.

## Notifications

### Delivery flow

1. Supabase Cron calls `send-due-reminders` every minute.
2. The function checks activity/routine times and PC usage in each device time
   zone.
3. It applies the user's categories and quiet hours.
4. It creates an inbox row and a unique delivery claim.
5. It sends a high-priority FCM message.

### Usage milestones

| Milestone | Behavior |
| --- | --- |
| 2 hours | First extended-use reminder |
| 3–7 hours | Additional hourly reminders |
| 8 hours | Final daily milestone; higher usage remains capped |

ActiBind sends the current whole-hour milestone. If usage jumps from below two
hours to five hours between checks, it sends the five-hour alert instead of
flooding the phone with every missed milestone.

### Platform notes

- Android foreground messages are displayed through a local high-priority
  channel.
- Android background/terminated notification payloads are displayed by the
  operating system; data-only messages use the registered background handler.
- After Android force-stop, the app must be reopened before FCM resumes.
- iOS/macOS local notification code exists, but production APNs configuration
  is not completed here.
- Web background FCM is not configured.

## AI insights and privacy

AI calls pass through `supabase/functions/groq-insights`; `GROQ_API_KEY` is
never included in Flutter code.

Depending on user controls, requests can contain recent activities, routines,
occurrence states, tasks, optional notes, phone usage, PC/laptop usage,
optional browser titles, device freshness, optional family profiles, weather,
holidays, and recent conversation history.

The server instructs the model not to invent statistics, URLs, forecasts, or
unsupported date attribution. See [docs/PRIVACY.md](docs/PRIVACY.md).

## Permissions

| Android capability | Purpose |
| --- | --- |
| Notifications | Schedule, summary, and usage alerts |
| Usage Access | Aggregate foreground-app activity |
| Location | Local weather and reverse geocoding |
| Internet | Supabase, Firebase, weather, holidays, and AI |
| Boot completed | Restore workers/widgets after reboot |
| Exact alarms | Local schedule support where applicable |
| Package visibility | Resolve app names/icons and family controls |
| Device admin | Optional protected child-mode controls |
| Accessibility service | Optional active child-mode restrictions |

Grant only the capabilities required for features you choose to use.

## Development setup

### Requirements

- Flutter stable and Dart compatible with `sdk: ^3.10.8`
- Android Studio, Android SDK, and Java 17
- Supabase CLI and a Supabase project
- Firebase project for Android FCM
- Groq API key for AI insights

### Install and run

```powershell
flutter pub get
flutter devices
flutter run -d <device-id>
```

Use a full restart after changing initialization, background handlers, native
Android code, dependencies, or services. Hot reload is suitable for normal
Dart UI edits.

Build a debug APK:

```powershell
flutter build apk --debug
```

Output is written under `build/app/outputs/flutter-apk/`.

## Backend setup and deployment

### Supabase

Client configuration lives in `lib/core/config/supabase_config.dart`. The
publishable key is client-safe; authorization relies on Auth and Row Level
Security. Never put a service-role key in Flutter code.

Link and migrate:

```powershell
supabase link --project-ref <project-ref>
supabase migration list --linked
supabase db push --linked
```

Migrations cover activities, routines, tasks, notes, profiles, devices,
device/window activity, tokens, notification delivery/inbox, AI budgets,
preferences, RLS policies, RPCs, and cron scheduling.

### Groq

```powershell
supabase secrets set GROQ_API_KEY=<key>
supabase secrets set GROQ_MODEL=openai/gpt-oss-20b
supabase secrets set GROQ_DAILY_TOKEN_LIMIT=180000
supabase functions deploy groq-insights
```

The model and limit are optional; the default shared budget is 180,000 tokens
per UTC day.

### Firebase FCM

Configure the FCM HTTP v1 sender from a Firebase service account:

```powershell
supabase secrets set FIREBASE_PROJECT_ID=<project-id>
supabase secrets set FIREBASE_CLIENT_EMAIL=<service-account-email>
supabase secrets set FIREBASE_PRIVATE_KEY=<private-key>
```

Keep the private key server-side. Android also requires the matching
`android/app/google-services.json`.

### Deploy functions

```powershell
supabase functions deploy groq-insights
supabase functions deploy send-due-reminders --no-verify-jwt
supabase functions deploy device-sync
supabase functions deploy device-pairing
supabase functions deploy delete-account
```

`send-due-reminders` validates the Vault-backed private cron secret created by
the scheduling migration; it is not a public test endpoint.

Required custom secrets include:

- `GROQ_API_KEY`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_CLIENT_EMAIL`
- `FIREBASE_PRIVATE_KEY`
- `DEVICE_RATE_LIMIT_SALT`
- `DEVICE_SYNC_RATE_LIMIT_SECRET`

Supabase supplies its URL, client, and service-role values to Edge Functions.

## Project structure

```text
lib/
  core/              Configuration, services, settings, and theme
  features/
    account/         Export and account deletion
    activities/      Planner, usage, holidays, and break alerts
    auth/            Sign-in and session gate
    developer/       Safe diagnostics
    devices/         Registered device and app/window activity
    family/          Profiles and protected mode
    home/            Navigation, overview, ledger, and settings
    insights/        Metrics and AI assistant
    notes/            Notes
    notifications/    In-app inbox
    routines/         Recurring schedules
    todos/            Task management
    weather/          Weather and geocoding
supabase/
  functions/         Edge Functions
  migrations/        Schema, RLS, RPC, and cron history
  tests/             SQL tests
android/app/src/main/ Native usage access, workers, widgets, and child mode
test/                 Dart and Flutter tests
docs/                 Privacy and release guidance
```

## Testing

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

`.github/workflows/quality.yml` runs dependency installation, formatting,
analysis, tests, and a debug APK build. Tests cover validation, overlaps, app
names, device parsing, usage milestones, privacy defaults, settings, themes,
and narrow-screen layouts.

## Troubleshooting

### Notifications do not arrive

1. Reopen the app after installation or force-stop.
2. Allow notifications in Android settings.
3. Confirm the signed-in user has a row in `device_push_tokens`.
4. Check notification categories and quiet hours.
5. Confirm the reminder cron and `send-due-reminders` are active.
6. Inspect function logs for Firebase authentication/token errors.
7. Ensure `google-services.json` and server credentials use the same Firebase
   project.

### Phone usage is empty

Enable ActiBind under Android **Usage access**, return to the app, and refresh.
Manufacturers may aggregate or delay usage events differently.

### PC/laptop usage is stale

Check the companion connection, device `last_seen_at`, activity
`last_synced_at`, clock/time zone, `device-sync` logs, and rate-limit secrets.

### AI is unavailable

Confirm authentication, the `groq-insights` deployment, `GROQ_API_KEY`, token
budget, and selected data controls. Home/daily cards can use a local fallback;
interactive chat reports service failures rather than inventing an answer.

### Weather or holidays fail

Check connectivity and location permission. Weather falls back to Manila when
a GPS fix is unavailable. Planning remains usable if an external API fails.

### Account deletion fails

Confirm `delete-account` is deployed with JWT verification, reauthenticate if
the session expired, and type `DELETE` exactly.

## Release preparation

Before public release, the owner must:

- Replace `com.example.actibind` with a permanent application ID and register
  it in Firebase.
- Configure a protected release/upload keystore instead of debug signing.
- Publish reviewed privacy/terms URLs and complete Play Data Safety forms.
- Test FCM foreground, background, terminated, reboot, offline, force-stop,
  and vendor battery-saving behavior.
- Validate export/deletion with a disposable production account.
- Complete APNs/web push or declare Android as the supported production target.

See [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md) and
[docs/PRIVACY.md](docs/PRIVACY.md).
