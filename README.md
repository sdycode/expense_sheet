# MoneyTracker — Expense Sheet

A Flutter (Android) expense tracker that uses **your own Google Sheets** as the database.
Track personal and shared/household expenses, invite people to a sheet, and add expenses
automatically by uploading a payment screenshot that an LLM parses into structured rows.

See [about_app.md](about_app.md) for a short feature overview.

> **Note on older docs:** `SETUP_GUIDE.md`, `QUICK_SETUP.md` and `GOOGLE_CLOUD_SETUP.md` are
> from an earlier version and say "Firebase is NOT required". That is no longer true — the app
> now requires Firebase Auth and Realtime Database. **This README is the current source of truth.**

---

# Part 1 — Developer Setup

Everything below is required to get a freshly cloned repo to actually run. Do the steps in order.

## 1.1 Prerequisites

| Requirement | Version / Notes |
|---|---|
| Flutter SDK | 3.32+ (Dart `^3.8.1`) |
| Android SDK | `minSdk 23` (Firebase Auth 23.x requirement), NDK `27.0.12077973` |
| Java | JDK 11 |
| Target platform | **Android** — iOS/desktop folders exist but are not configured |
| Accounts needed | Google account (Firebase + Google Cloud), Hugging Face account (only for on-device AI) |

```bash
git clone https://github.com/sdycode/expense_sheet.git
cd expense_sheet
flutter pub get
```

The Android application ID is `com.example.expensesheet`
(see [android/app/build.gradle.kts](android/app/build.gradle.kts)). Every Firebase / OAuth
registration below **must use this exact package name**, or Google Sign-In fails with
`ApiException: 10 (DEVELOPER_ERROR)`.

## 1.2 Get your debug SHA-1

You need this for both Firebase and the Google OAuth client:

```bash
cd android && ./gradlew signingReport
# copy the SHA1 under "Variant: debug"
```

## 1.3 Firebase project

The repo ships a `google-services.json` for the original developer's Firebase project.
**Replace it with your own** — you cannot write to someone else's database.

1. Create a project at [console.firebase.google.com](https://console.firebase.google.com/).
2. **Add an Android app** → package name `com.example.expensesheet`, paste your debug SHA-1.
3. Download `google-services.json` → place at **`android/app/google-services.json`** (overwrite the existing file).
4. **Authentication** → Sign-in method → enable **Google**, set a support email.
5. **Realtime Database** → Create database (pick a region, start in *locked mode*; rules in §1.5).

There is no `lib/firebase_options.dart` — Firebase is initialised from `google-services.json`
via `Firebase.initializeApp()` in [startup_view.dart:67](lib/screens/startup_view.dart#L67).
Do **not** run `flutterfire configure` unless you also update that call.

## 1.4 Google Cloud APIs & OAuth

Use the **same Google Cloud project** that Firebase created for you
([console.cloud.google.com](https://console.cloud.google.com/) → pick the project matching your Firebase project).

1. **APIs & Services → Library** → enable **both**:
   - **Google Sheets API** — reading/writing expense rows
   - **Google Drive API** — required for the "share spreadsheet" feature (granting editor access)
2. **OAuth consent screen** → External → fill app name + support email → add these scopes:
   - `https://www.googleapis.com/auth/spreadsheets`
   - `https://www.googleapis.com/auth/drive`

   > The narrower `drive.file` scope is **not** sufficient — Drive returns 404 for spreadsheet IDs
   > the app didn't create through the picker. See [firebase_auth_service.dart:12-18](lib/services/firebase_auth_service.dart#L12-L18).
3. While the consent screen is in *Testing* mode, add every Google account you'll sign in with
   under **Test users**.
4. **Credentials → Create OAuth client ID → Android** → package `com.example.expensesheet`, your debug SHA-1.

> Changes can take 5–10 minutes to propagate. After changing anything here, run
> `flutter clean && flutter pub get && flutter run`.

## 1.5 Realtime Database structure

The app writes and reads these paths. You don't have to pre-create them — except `default_keys`
and `hftoken`, which are read-only config you seed yourself.

```
hftoken                                   → "hf_xxx"   (string; for on-device Gemma, §1.7)
default_keys/{provider}/list              → [ "key1", "key2" ]   (app-owned AI keys, §1.6)
user_keys/{uid}/{provider}/list           → [ "key" ]            (written by the app)
user_usage/{uid}/hit_count                → int                  (written by the app)
spreadsheets/{spreadsheetId}/meta         → name, ownerEmail, sheetKind
spreadsheets/{spreadsheetId}/members/…    → invited members
spreadsheets/{spreadsheetId}/events/…     → events / trips
spreadsheets/{spreadsheetId}/frequent_expense_items/…
spreadsheets/{spreadsheetId}/paid_by_persons/…
```

Starting rules for local development — **tighten these before sharing the app with anyone**,
they let any signed-in user read every other user's keys:

```json
{
  "rules": {
    ".read": "auth != null",
    ".write": "auth != null",
    "user_keys": {
      "$uid": { ".read": "auth.uid === $uid", ".write": "auth.uid === $uid" }
    },
    "hftoken": { ".read": "auth != null", ".write": false },
    "default_keys": { ".read": "auth != null", ".write": false }
  }
}
```

## 1.6 AI extraction keys (cloud providers)

Screenshot → expense extraction runs through a provider cascade with automatic failover:
**Gemini → SambaNova → Groq → Mistral → Cloudflare**
(see [key_manager.dart](lib/features/ai_extractor/services/key_manager.dart)).

- For a user's first **50** requests (`kOwnerHitLimit`) the app uses keys from `default_keys/{provider}/list`.
- After that the user must add their own keys in-app (**AI Key Settings**), stored at `user_keys/{uid}/…`.
- On a `429`/`401` the failed key is dropped and the next key — then the next provider — is tried.

To seed app-wide keys, add a `default_keys` node in Realtime Database using any providers you have.
Free-tier keys are available from:

| Provider | Get a key |
|---|---|
| `gemini` | https://aistudio.google.com/app/apikey |
| `sambanova` | https://cloud.sambanova.ai/apis |
| `groq` | https://console.groq.com/keys |
| `mistral` | https://console.mistral.ai/api-keys |
| `cloudflare` | https://dash.cloudflare.com/profile/api-tokens |

At minimum seed `gemini` — the app works with just one provider configured. If you seed nothing,
users must add their own key on first use.

## 1.7 On-device AI (optional)

The Gemma feature ([lib/features/gemma_ai/](lib/features/gemma_ai/)) downloads a `.task` model and runs
inference locally via `flutter_gemma` / MediaPipe. It is **optional** — skip this section and the rest
of the app works fine.

1. Create a Hugging Face access token (read scope) at https://huggingface.co/settings/tokens.
2. Put it in Realtime Database at the key **`hftoken`** (read by
   [hf_token_service.dart](lib/features/gemma_ai/services/hf_token_service.dart)).
3. Accept the model licence on Hugging Face for whichever model you plan to use:
   - **Compact** — Gemma3-1B (~555 MB, community-hosted, no licence gate)
   - **Balanced** — Gemma 3n E2B (~3.1 GB, Google-gated)
   - **Advanced** — Gemma 3n E4B (~4.4 GB, needs 6 GB+ RAM, Google-gated)

Without accepting the licence the download fails with a `GemmaAuthException` and the app shows a
link to the licence page.

> **Status:** this feature is wired up and downloadable from **Gemma AI Setup** in the app drawer,
> but it is not yet used for expense extraction — the AI Extract flow still goes through the cloud providers.

## 1.8 Run

```bash
flutter pub get
flutter run            # debug
flutter build apk --release
```

> The release build is currently signed with the **debug** keystore
> ([android/app/build.gradle.kts](android/app/build.gradle.kts)). Add a real signing config before
> distributing, and register that keystore's SHA-1 in Firebase + the OAuth client too.

## 1.9 Troubleshooting

| Symptom | Fix |
|---|---|
| `ApiException: 10` / `DEVELOPER_ERROR` on sign-in | SHA-1 or package name mismatch. Re-run `./gradlew signingReport`, re-register in Firebase **and** the Android OAuth client, wait 5 min, `flutter clean`. |
| Sign-in works, but sheets fail with `401` | Access token expired or the Sheets API isn't enabled. The app retries with `getAccessToken(forceRefresh: true)`; if it persists, check the API is enabled in Cloud Console. |
| Sharing fails: *"API has not been used or is disabled"* (403) | Enable **Google Drive API** in the same Cloud project, wait a few minutes. |
| Drive returns `404` for a valid spreadsheet ID | The `drive` scope wasn't granted. Sign out, sign in again and accept both permission prompts. |
| `NoAvailableKeyException` | No keys under `default_keys/{provider}/list`, or the user is past 50 hits with no personal key. Add one in **AI Key Settings**. |
| Gemma download loops on "storing locally" | `background_downloader` must be a direct dependency (it is, in `pubspec.yaml`) and `FlutterGemma.initialize()` must run before anything touches the plugin — it does, in [main.dart](lib/main.dart). |
| `403` writing to Realtime Database | Your RTDB rules are still in locked mode. Apply the rules in §1.5. |

---

# Part 2 — How to Use the App

## 2.1 First run

1. **Sign in with Google** from the home screen. Accept **both** permission prompts — Sheets access
   and Drive access. Skipping the Drive prompt breaks spreadsheet sharing later.
2. Open the drawer → **Expense sheet settings** to attach a spreadsheet. You have three options:
   - **New shared / group sheet** — creates a fresh sheet in your Drive with the 10-column shared layout.
   - **New personal sheet** — creates a sheet with the 11-column personal layout.
   - **Browse Drive** — pick an existing spreadsheet you already own, then **Verify** it so the app
     checks/creates the header row.

You can attach **both** a shared and a personal sheet at the same time and switch between them.

### Shared vs personal sheets

| | Shared sheet | Personal sheet |
|---|---|---|
| Purpose | Household / group / roommate expenses | Your own private spending |
| Columns | A–J | A–K (adds *Linked Shared Sheet ID*) |
| Who can write | Owner + invited members | Owner only |
| Sharing | Yes — invite by email | No |
| Has "Paid By" | Yes | No |

Both layouts share columns A–J, so the same rows stay readable in either sheet.

## 2.2 Adding an expense

On the home screen fill in:

- **Label** (required) — e.g. "Groceries". Previously used labels autocomplete.
- **Price** (required)
- **Category** — Food, Grocery & Essential, Transport, Shopping, Health & Wellness, etc.
- **Date** — defaults to today
- **Paid By** — shared sheets only; pick a person or add a new one
- **Note** — optional
- **One-time purchase** — flag for non-recurring spends

Tap add — the row is appended to your Google Sheet immediately. If the sync fails (no network,
expired token) a **Retry** action appears in the snackbar. You can also turn on
*"Default: also save to the other sheet"* in **Expense sheet settings** to mirror each entry
into both your personal and shared sheets.

## 2.3 Adding expenses from a screenshot (AI Extract)

Drawer → **AI Extract**.

1. Pick or capture a payment screenshot — a UPI confirmation, bank SMS screenshot, order receipt, etc.
2. The image goes to an LLM, which returns every transaction it can see as structured data:
   label, amount, category, date and a short note.
3. Review the extracted cards — **edit anything that's wrong** before saving. The model guesses
   categories and can misread amounts on cluttered screenshots.
4. Save the ones you want; they're written to your sheet like manually added expenses.

Multiple transactions in one screenshot are extracted together, so a payment-history screen works
as well as a single receipt.

**AI Key Settings** (from the AI Extract screen) lets you:
- add your own API keys per provider, with a direct link to each provider's key page
- choose a specific provider, or leave it on **Auto (Cascade Failover)** to try them in order
- see your usage — after 50 requests on the app's shared keys you'll need your own

## 2.4 Viewing and editing

- **Expenses list** — browse everything in the sheet: search by label, sort by date or price, and
  filter by category, date range or one-time/recurring. Open any entry to edit or delete it; edits
  write back to the same row in Google Sheets.
- **Events** — group expenses under a trip or occasion ("Goa trip", "Diwali") and see them together.
- **Frequent items** — save expenses you log repeatedly so you can add them in one tap.

## 2.5 Sharing a spreadsheet

Drawer → **Share Spreadsheet** (shared sheets only — personal sheets can't be shared).

1. Enter the person's email. They need a Google account.
2. The app registers them in the database **and** grants them Drive editor access on the file.
3. They install the app, sign in with that email, and the shared sheet appears in their list.

Every row records the email of whoever added it, so you can see who logged what.

## 2.6 Appearance

Drawer → **App settings**: light / dark / system theme, plus separate accent colours for the
shared and personal contexts — a quick visual cue for which sheet you're currently writing to.

## 2.7 Your data

Everything lives in **your own Google Sheets file** in **your** Drive. You can open it in Google
Sheets on any device, chart it, export it, or stop using the app entirely and keep all your data.
The app's database only stores metadata — sheet ownership, members, events and frequent items —
never the expense amounts themselves.
