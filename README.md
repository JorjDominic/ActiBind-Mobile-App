# ActiBind

ActiBind is a Flutter activity-planning and digital-wellbeing app that combines
schedules, routines, tasks, phone usage, synchronized computer activity,
weather, holidays, notifications, widgets, and privacy-controlled AI insights.

## Quality checks

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

See `docs/PRIVACY.md` for the implemented data controls and
`docs/RELEASE_CHECKLIST.md` before publishing.

## Groq-powered insights

AI insights are proxied through the authenticated `groq-insights` Supabase Edge
Function. Never put a Groq API key in Flutter source code or a `--dart-define`,
because values shipped in a client application can be extracted.

After creating a fresh Groq key, configure and deploy the function:

```powershell
supabase secrets set GROQ_API_KEY=your_new_key
supabase functions deploy groq-insights
```

The optional `GROQ_MODEL` secret can override the default
`openai/gpt-oss-20b` production model.

The Edge Function enforces a shared daily budget of 180,000 tokens by default,
leaving headroom below Groq's developer-tier limit. Override it when needed:

```powershell
supabase secrets set GROQ_DAILY_TOKEN_LIMIT=180000
```

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
