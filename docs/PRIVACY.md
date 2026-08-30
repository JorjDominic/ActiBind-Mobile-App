# ActiBind privacy controls

ActiBind processes schedules, tasks, routines, app usage, synchronized computer
activity, and optional browser window titles. Browser titles, note contents, and
family profiles are excluded from AI requests by default. Users can change each
AI source independently under **Settings > AI data controls**.

The account export copies a JSON representation of accessible account records to
the clipboard. Clipboard contents may be visible to the operating system and
other software, so users should paste and save the export only in a trusted app.

Account deletion requires typing `DELETE` and calls the authenticated
`delete-account` Edge Function. Deleting the Supabase auth user cascades through
tables whose user foreign keys use `on delete cascade`.

Before publishing, replace this engineering note with reviewed legal terms and a
public privacy-policy URL. Document retention periods and every external data
processor, including Supabase, Firebase, Groq, Open-Meteo, and Nager.Date.
