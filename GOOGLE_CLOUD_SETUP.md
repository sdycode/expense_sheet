# Google Cloud Console Setup Guide (No Firebase Required)

## Error Code 10 Fix - Step by Step

Error code 10 (`DEVELOPER_ERROR`) means your OAuth credentials are not properly configured. Follow these steps:

---

## Step 1: Get Your SHA-1 Certificate Fingerprint

### For Debug Build (Testing):
Run this command in your terminal from the project root:

```bash
cd android
./gradlew signingReport
```

Look for the output under `Variant: debug` → `SHA1:` - copy this value.

**OR** use this command:
```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```

The SHA-1 will look like: `AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD`

---

## Step 2: Create/Configure Google Cloud Project

1. **Go to [Google Cloud Console](https://console.cloud.google.com/)**
2. **Create a new project** (or select existing):
   - Click the project dropdown at the top
   - Click "New Project"
   - Enter project name: "Expense Tracker" (or any name)
   - Click "Create"

---

## Step 3: Enable Google Sheets API

1. In Google Cloud Console, go to **"APIs & Services"** → **"Library"**
2. Search for **"Google Sheets API"**
3. Click on it and click **"Enable"**
4. Wait for it to enable (usually takes a few seconds)

---

## Step 4: Configure OAuth Consent Screen

1. Go to **"APIs & Services"** → **"OAuth consent screen"**
2. Choose **"External"** (unless you have Google Workspace)
3. Click **"Create"**
4. Fill in the required fields:
   - **App name**: Expense Tracker (or your app name)
   - **User support email**: Your email
   - **Developer contact information**: Your email
5. Click **"Save and Continue"**
6. On **Scopes** page:
   - Click **"Add or Remove Scopes"**
   - Search for: `https://www.googleapis.com/auth/spreadsheets`
   - Check the box and click **"Update"**
   - Click **"Save and Continue"**
7. On **Test users** page (if in testing mode):
   - Click **"Add Users"**
   - Add your Google account email (the one you'll use to sign in)
   - Click **"Save and Continue"**
8. Review and click **"Back to Dashboard"**

---

## Step 5: Create OAuth 2.0 Client ID for Android

1. Go to **"APIs & Services"** → **"Credentials"**
2. Click **"+ CREATE CREDENTIALS"** → **"OAuth client ID"**
3. Select **"Android"** as Application type
4. Fill in:
   - **Name**: Expense Tracker Android (or any name)
   - **Package name**: `com.example.expensesheet` (MUST match exactly)
   - **SHA-1 certificate fingerprint**: Paste the SHA-1 you got from Step 1
5. Click **"Create"**
6. **IMPORTANT**: You'll see a popup with Client ID - you can close it (we don't need to save it for this setup)

---

## Step 6: Verify Configuration

Your credentials should now show:
- ✅ Google Sheets API: Enabled
- ✅ OAuth consent screen: Configured
- ✅ OAuth 2.0 Client ID (Android): Created with correct package name and SHA-1

---

## Step 7: Test the App

1. **Rebuild the app** (important!):
   ```bash
   flutter clean
   flutter pub get
   flutter run
   ```

2. Try signing in again

---

## Common Issues & Solutions

### Still Getting Error 10?

1. **Double-check package name**: Must be exactly `com.example.expensesheet`
2. **Verify SHA-1**: Make sure you copied the correct SHA-1 (debug vs release)
3. **Wait a few minutes**: Google Cloud changes can take 5-10 minutes to propagate
4. **Check OAuth consent screen**: Make sure it's published or you're added as a test user
5. **Rebuild app**: Run `flutter clean && flutter run`

### SHA-1 Not Working?

If you're testing on a physical device or using a different keystore:
- Get SHA-1 from the keystore you're actually using
- For release builds, use your release keystore's SHA-1

### Package Name Mismatch?

If you changed the package name in `android/app/build.gradle.kts`:
- Update it in Google Cloud Console OAuth client
- OR change it back to `com.example.expensesheet`

---

## Firebase vs Direct Google APIs

**You DON'T need Firebase!** Here's why:

### Direct Google APIs (What we're using):
- ✅ Simpler setup
- ✅ No Firebase project required
- ✅ Direct access to Google Sheets API
- ✅ Works with `google_sign_in` package
- ✅ Free (within Google Cloud quotas)

### Firebase (Not needed):
- ❌ Requires Firebase project
- ❌ More complex setup
- ❌ Additional services you don't need
- ❌ Same OAuth setup required anyway

**Bottom line**: Your current setup is correct. Just need to configure Google Cloud Console properly.

---

## Quick Checklist

- [ ] Got SHA-1 fingerprint from debug keystore
- [ ] Created Google Cloud project
- [ ] Enabled Google Sheets API
- [ ] Configured OAuth consent screen
- [ ] Added `https://www.googleapis.com/auth/spreadsheets` scope
- [ ] Added yourself as test user (if in testing mode)
- [ ] Created Android OAuth client with:
  - [ ] Package name: `com.example.expensesheet`
  - [ ] SHA-1: Your debug SHA-1
- [ ] Rebuilt app (`flutter clean && flutter run`)
- [ ] Tested sign-in

---

## Need Help?

If you're still getting errors:
1. Check the debug console for the exact error message
2. Verify all steps above
3. Make sure you're using the same Google account that's added as a test user
4. Wait 5-10 minutes after making changes in Google Cloud Console

