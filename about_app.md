# MoneyTracker — Personal & Shared Expense Tracker (Flutter, Android)

A self-built expense tracker I use daily, designed around a spreadsheet-first model: **Google Sheets is the database**, so my data stays in my own Drive, readable and editable outside the app.

- Built with **Flutter/Dart** (~19K LOC, 60+ Dart files) using a feature-first architecture, Provider state management, and Material 3 theming with light/dark modes and per-context accent colors.
- Writes and reads expenses directly through the **Google Sheets API v4**, with two interoperable row layouts — *shared* household sheets and *personal* sheets linked back to a shared sheet.
- **Google Sign-In + Firebase Auth** for identity; **Firebase Realtime Database** stores sheet ownership, member lists, events, frequent items, and payer registry.
- Multi-user collaboration: invite members by email and auto-grant editor access via the **Google Drive API**, with role checks so only owners can write to personal sheets.
- **AI expense extraction** — snap or upload a payment/UPI screenshot and an LLM returns structured, auto-categorized transactions (label, amount, category, date) ready to save.
- Built a **multi-provider LLM layer** (Gemini, Groq, SambaNova, Mistral, Cloudflare Workers AI) with an API-key rotation manager, per-user usage quotas, and automatic failover on rate-limit/auth errors.
- Added an **on-device LLM path** using `flutter_gemma` (MediaPipe) for offline, private inference — model download, license handling, and serialized inference queue.
- Extra workflow features: expense events/trips tagging, frequent-item shortcuts, category analytics, filtering, and spreadsheet picker/sharing UI.

**Stack:** Flutter · Dart · Firebase (Auth, RTDB) · Google Sheets & Drive APIs · Gemini / Groq / Mistral APIs · flutter_gemma · Provider
