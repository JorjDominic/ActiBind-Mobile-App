# Release checklist

- Replace `com.example.actibind` with a permanent application ID and register it
  in Firebase before producing a release build.
- Configure a protected Android upload keystore; never ship debug signing.
- Deploy all pending Supabase migrations and the `groq-insights`,
  `send-due-reminders`, and `delete-account` functions.
- Verify Firebase service-account credentials with a real FCM acceptance test.
- Test foreground, background, terminated, reboot, offline, and force-stop flows.
- Complete Play Data safety disclosures and publish reviewed privacy/terms URLs.
- Confirm notification, location, usage-access, accessibility, and package-query
  permissions are explained in context and are required by enabled features.
- Run `flutter analyze`, `flutter test`, and signed release smoke tests.
- Validate account export and deletion against a disposable production account.
- Add crash reporting only after consent and sensitive-data redaction are defined.
