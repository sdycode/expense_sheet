# Quick Setup Reference - Your Exact Values

## Your App Configuration

**Package Name**: `com.example.expensesheet`

**SHA-1 Fingerprint (Debug)**: 
```
98:DF:06:6A:1A:1B:A0:AB:F4:82:B6:22:E1:34:95:BE:26:F1:FF:06
```

---

## Google Cloud Console - Quick Steps

### 1. Create Project
- Go to: https://console.cloud.google.com/
- Create new project: "Expense Tracker"

### 2. Enable API
- APIs & Services → Library
- Search: "Google Sheets API"
- Click: **Enable**

### 3. OAuth Consent Screen
- APIs & Services → OAuth consent screen
- Type: **External**
- App name: Expense Tracker
- Support email: Your email
- Scopes: Add `https://www.googleapis.com/auth/spreadsheets`
- Test users: Add your Google account email

### 4. Create OAuth Client (Android)
- APIs & Services → Credentials → Create Credentials → OAuth client ID
- Type: **Android**
- Package name: `com.example.expensesheet`
- SHA-1: `98:DF:06:6A:1A:1B:A0:AB:F4:82:B6:22:E1:34:95:BE:26:F1:FF:06`
- Click: **Create**

### 5. Rebuild App
```bash
flutter clean
flutter pub get
flutter run
```

---

## Important Notes

✅ **Firebase is NOT required** - Direct Google APIs work perfectly!

❌ **Don't use Firebase** - It adds unnecessary complexity

✅ **Your current setup is correct** - Just need Google Cloud Console configuration

---

## After Setup

1. Wait 2-5 minutes for changes to propagate
2. Run the app
3. Sign in with the Google account you added as a test user
4. Should work! 🎉

---

## Still Getting Error 10?

1. Double-check package name matches exactly
2. Verify SHA-1 is correct (copy-paste it)
3. Make sure you're added as a test user in OAuth consent screen
4. Wait 5-10 minutes and try again
5. Rebuild: `flutter clean && flutter run`

