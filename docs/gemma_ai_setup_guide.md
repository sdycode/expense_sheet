# Gemma AI — Production Integration Guide (Flutter, iOS + Android)

A concrete, battle-tested guide for wiring `flutter_gemma` on-device LLM into
a Flutter app. Captures every trap this project hit so the next project
doesn't have to re-learn them.

> Target: Flutter 3.32+, Dart ^3.8, `flutter_gemma: ^0.13.5`, iOS 15+, Android
> API 26+. Primary production target is iOS; Android kept working alongside.

---

## TL;DR — order of operations

1. Add packages (Gemma, Firebase for token fetch, Isar, notifications).
2. In `main()`: `Firebase.initializeApp()` →

**`FlutterGemma.initialize(huggingFaceToken: …)` BEFORE anything else touches the plugin** → Isar → notifications → `runApp`.
3. Build a single `GemmaService` singleton with a **future-chain mutex** around `generate()` and `chat()`.
4. Use `createSession()` per call, never `createChat()`.
5. Serve users a **production model picker** after onboarding. Compact is community-hosted (no license step). Balanced/Advanced are Google-gated — handle the 401.
6. Inject an **AppContext** snapshot (latest Isar data) into every chat call so the AI can answer questions about the user's own data.
7. Gate every dev-only button behind a `devMode` constant. Never leak HF tokens or file paths into the production UI.
8. Never surface raw exceptions. `debugPrint` the real error; render a friendly `AiErrorState` with a "Upgrade model" CTA.

---

## 1. Packages

### `pubspec.yaml` additions

```yaml
dependencies:
  # On-device LLM
  flutter_gemma: ^0.13.5

  # Fetching HF token from RTDB at launch
  firebase_core: ^4.6.0
  firebase_database: ^12.2.0

  # Local DB — source of truth for data the AI reads
  isar: ^3.1.0+1
  isar_flutter_libs: ^3.1.0+1
  path_provider: ^2.1.5

  # Step notifications (bake plans, reminders, etc.)
  flutter_local_notifications: ^18.0.1
  flutter_timezone: ^5.0.0
  timezone: ^0.9.4
  permission_handler: ^11.3.1

  # State management
  flutter_riverpod: ^2.6.1

  # Persistent flags (ai_setup_shown, selected model, cached HF token)
  shared_preferences: ^2.3.3

dev_dependencies:
  isar_generator: ^3.1.0+1
  build_runner: ^2.4.13
```

Generate the Isar schemas once after defining collections:
```
dart run build_runner build --delete-conflicting-outputs
```

### Android manifest (`android/app/src/main/AndroidManifest.xml`)

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
```

Inside `<application>`:

```xml
<receiver
    android:exported="false"
    android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
<receiver
    android:exported="false"
    android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED"/>
        <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
    </intent-filter>
</receiver>
```

### iOS (`ios/Runner/Info.plist`)

Nothing Gemma-specific is required. If you use local notifications, the
plugin requests permission at runtime. Don't pre-declare alert/sound in
DarwinInitializationSettings — request lazily so the system prompt doesn't
fire at cold start.

---

## 2. HuggingFace token — the single most-important thing

`flutter_gemma` reads the HF token from its global service registry, **not**
from the per-spec `authToken` you pass to `ModelSource.network(...)`. The
token is cached on first `FlutterGemma.initialize()` call and subsequent
updates are ignored until process restart.

Rules:
- Fetch the token **before** any other Gemma-related code runs.
- Call `FlutterGemma.initialize(huggingFaceToken: token)` exactly once per
  process, with the token you want to use.
- Cache the last token inside `GemmaService` so you can re-init only when it
  actually changes.

### Where the token lives

- **Remote**: Firebase RTDB root at `/hftoken` (developer pushes this — one
  HuggingFace account token shared across all installs).
- **Local cache**: `SharedPreferences` key `ai_hf_token` (survives offline
  restart).

### `HfTokenService`

```dart
class HfTokenService {
  static const _prefKey = 'ai_hf_token';

  static Future<String> fetchAndCache() async {
    // 1. Try Firebase RTDB
    try {
      final snap =
          await FirebaseDatabase.instance.ref('hftoken').get();
      if (snap.exists && snap.value is String) {
        final token = (snap.value as String).trim();
        if (token.isNotEmpty) {
          await (await SharedPreferences.getInstance())
              .setString(_prefKey, token);
          return token;
        }
      }
    } catch (e, st) {
      debugPrint('[HfTokenService.fetchAndCache] RTDB fetch failed: $e\n$st');
    }
    // 2. Fall back to cached token
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey) ?? '';
  }
}
```

---

## 3. `main()` — initialization order is load-bearing

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Firebase FIRST — HfTokenService uses FirebaseDatabase.
  try {
    await Firebase.initializeApp();
  } catch (e, st) {
    debugPrint('[main] Firebase init failed: $e\n$st');
  }

  // 2. Fetch + cache HF token.
  final hfToken = await HfTokenService.fetchAndCache();

  // 3. Initialize flutter_gemma's service registry with the token.
  //    This MUST happen before any code touches FlutterGemmaPlugin.
  await FlutterGemma.initialize(
    huggingFaceToken: hfToken.isEmpty ? null : hfToken,
  );

  // 4. Open Isar (local DB the AI reads for context).
  final isar = await IsarService.init();

  // 5. Cross-platform notification service.
  await NotificationService.init();

  runApp(
    ProviderScope(
      overrides: [isarProvider.overrideWithValue(isar)],
      child: const MyApp(),
    ),
  );
}
```

> Symptom when `FlutterGemma.initialize` is called late: downloads fail with
> HTTP 401 even with a valid token. The registry captured a null token on
> first use and refuses to re-read.

---

## 4. Gemma model catalog

Three variants, smallest to largest. All are LiteRT `.task` files
downloaded from HuggingFace on first use.

| ID | UI name | Size | Repo | Gated? |
|---|---|---|---|---|
| `gemma3-1b` | Compact | ~555 MB | `litert-community/Gemma3-1B-IT` | No |
| `gemma3n-e2b` | Balanced | ~3.1 GB | `google/gemma-3n-E2B-it-litert-preview` | **Yes** |
| `gemma3n-e4b` | Advanced | ~4.4 GB | `google/gemma-3n-E4B-it-litert-preview` | **Yes** |

```dart
const List<GemmaModel> kGemmaCatalog = [
  GemmaModel(
    id: 'gemma3-1b',
    name: 'Gemma 3 1B',
    tagline: 'Smallest usable — recommended for testing',
    approxMB: 555,
    url: 'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task',
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.task,
    huggingFacePage: 'https://huggingface.co/litert-community/Gemma3-1B-IT',
  ),
  GemmaModel(
    id: 'gemma3n-e2b',
    name: 'Gemma 3n E2B',
    tagline: 'Mobile-optimized — best quality-to-size',
    approxMB: 3100,
    url: 'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/gemma-3n-E2B-it-int4.task',
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.task,
    huggingFacePage: 'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview',
  ),
  GemmaModel(
    id: 'gemma3n-e4b',
    name: 'Gemma 3n E4B',
    tagline: 'Largest — best quality, needs 6GB+ RAM',
    approxMB: 4400,
    url: 'https://huggingface.co/google/gemma-3n-E4B-it-litert-preview/resolve/main/gemma-3n-E4B-it-int4.task',
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.task,
    huggingFacePage: 'https://huggingface.co/google/gemma-3n-E4B-it-litert-preview',
  ),
];
const String kDefaultGemmaModelId = 'gemma3-1b';
```

### Gated-repo trap

Balanced and Advanced live under `google/…` repos. Every HuggingFace account
must click **"Agree and access"** on each page once before the token can
download that model. If your shared Firebase-hosted token belongs to an
account that hasn't accepted, downloads 401 with no explanation.

**Operator action (do this once)**: log into the HF account that owns the
shared token, visit each gated model page, click "Agree and access".

**User-facing fallback**: on 401, surface the model page URL with a "Copy
link" action and a Retry button (see §9).

---

## 5. `GemmaService` — the singleton

Three things that matter and will bite you if skipped:

1. **Serialise inference calls.** The underlying MediaPipe LLM engine is a
   single state machine on a shared `InferenceModel`. Two concurrent
   `generate()` calls trip the engine with `"AddQueryChunk should not be
   called before PredictDone, not supported for now"`. Queue calls through a
   future chain.
2. **Use `createSession()` per call, not `createChat()`.** `InferenceChat`
   has a late-init `session` field that raises `LateInitializationError:
   "session has not been initialised"` on the first use on a cold model.
   Sessions are cheap — make a new one per turn and close it.
3. **Stable backend for reliability**: `PreferredBackend.cpu` avoids GPU
   fallback surprises on older Android devices.

```dart
class GemmaService {
  static final GemmaService _instance = GemmaService._();
  factory GemmaService() => _instance;
  GemmaService._();

  final _plugin = FlutterGemmaPlugin.instance;
  InferenceModel? _model;
  String? _loadedModelId;
  String? _lastTokenInitWith;

  // Serialises all inference — see comment above.
  Future<dynamic> _inferenceChain = Future<void>.value();

  Future<T> _runSerialised<T>(Future<T> Function() op) {
    final next = _inferenceChain.then((_) => op());
    _inferenceChain = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  Future<void> initializeWithToken(String? token) async {
    final t = (token ?? '').trim();
    if (_lastTokenInitWith == t) return;
    try {
      await FlutterGemma.initialize(
        huggingFaceToken: t.isEmpty ? null : t,
      );
      _lastTokenInitWith = t;
    } catch (e, st) {
      debugPrint('[GemmaService.initializeWithToken] $e\n$st');
    }
  }

  InferenceModelSpec _specFor(GemmaModel m, {String? authToken}) =>
      InferenceModelSpec(
        name: 'app-${m.id}',
        modelSource: ModelSource.network(m.url, authToken: authToken),
        modelType: m.modelType,
        fileType: m.fileType,
      );

  Future<bool> isInstalled(GemmaModel m) async {
    try {
      return await _plugin.modelManager.isModelInstalled(_specFor(m));
    } catch (_) {
      return false;
    }
  }

  Future<bool> isAnyInstalled() async {
    for (final m in kGemmaCatalog) {
      if (await isInstalled(m)) return true;
    }
    return false;
  }

  Stream<GemmaDownloadProgress> install(GemmaModel m,
      {String? huggingFaceToken}) async* {
    await initializeWithToken(huggingFaceToken);
    final spec = _specFor(m, authToken: huggingFaceToken);
    try {
      await for (final p
          in _plugin.modelManager.downloadModelWithProgress(spec)) {
        yield GemmaDownloadProgress(
          fraction: (p.overallProgress / 100.0).clamp(0.0, 1.0),
          fileName: p.currentFileName,
        );
      }
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('401') || msg.toLowerCase().contains('auth')) {
        throw GemmaAuthException(m.huggingFacePage);
      }
      rethrow;
    }
  }

  Future<void> delete(GemmaModel m) async {
    if (_loadedModelId == m.id) await unload();
    try {
      await _plugin.modelManager.deleteModel(_specFor(m));
    } catch (_) {}
  }

  Future<void> load(GemmaModel m) async {
    if (_model != null && _loadedModelId == m.id) return;
    await unload();
    _plugin.modelManager.setActiveModel(_specFor(m));
    _model = await _plugin.createModel(
      modelType: m.modelType,
      preferredBackend: PreferredBackend.cpu,
      maxTokens: 1024,
    );
    _loadedModelId = m.id;
  }

  Future<void> unload() async {
    try { await _model?.close(); } catch (_) {}
    _model = null;
    _loadedModelId = null;
  }

  Future<String> generate({
    required GemmaModel model,
    required String prompt,
    String? instructions,
    double temperature = 0.7,
  }) {
    return _runSerialised(() async {
      await load(model);
      InferenceModelSession? session;
      try {
        session = await _model!.createSession(
          temperature: temperature,
          randomSeed: DateTime.now().millisecondsSinceEpoch % 10000,
          topK: 40,
          systemInstruction: instructions,
        );
        final full = (instructions != null && instructions.isNotEmpty)
            ? '$instructions\n\n$prompt' : prompt;
        await session.addQueryChunk(Message(text: full, isUser: true));
        return await session.getResponse();
      } catch (e, st) {
        debugPrint('[GemmaService.generate] $e\n$st');
        rethrow;
      } finally {
        try { await session?.close(); } catch (_) {}
      }
    });
  }

  Future<String> chat({
    required GemmaModel model,
    required List<Map<String, String>> messages,
    String? instructions,
  }) {
    return _runSerialised(() async {
      await load(model);
      InferenceModelSession? session;
      try {
        session = await _model!.createSession(
          temperature: 0.7,
          randomSeed: DateTime.now().millisecondsSinceEpoch % 10000,
          topK: 40,
          systemInstruction: instructions,
        );
        // Sessions carry no history. Flatten prior turns into one prompt.
        final last = messages.last['content'] ?? '';
        final prompt = messages.length > 1
            ? 'Conversation so far:\n${messages.sublist(0, messages.length - 1).map((m) => '${(m['role'] ?? 'user').toUpperCase()}: ${m['content']}').join('\n')}\n\nUser: $last'
            : last;
        await session.addQueryChunk(Message(text: prompt, isUser: true));
        return await session.getResponse();
      } catch (e, st) {
        debugPrint('[GemmaService.chat] $e\n$st');
        rethrow;
      } finally {
        try { await session?.close(); } catch (_) {}
      }
    });
  }
}

class GemmaAuthException implements Exception {
  final String acceptLicenseUrl;
  GemmaAuthException(this.acceptLicenseUrl);
  @override
  String toString() => 'GemmaAuthException: accept license at $acceptLicenseUrl';
}
```

---

## 6. Riverpod providers

```dart
// Selected model (persisted in SharedPreferences).
final selectedModelProvider =
    StateNotifierProvider<SelectedModelNotifier, GemmaModel>(
  (_) => SelectedModelNotifier(),
);

// Installation state of the currently selected model.
final selectedModelInstalledProvider = FutureProvider<bool>((ref) async {
  final m = ref.watch(selectedModelProvider);
  return ref.read(gemmaServiceProvider).isInstalled(m);
});

// Is ANY model installed? Use this for "AI set up at all?" banners —
// selected-model check is too strict when the user optimistically switched
// to an uninstalled variant and the download failed.
final anyModelInstalledProvider = FutureProvider<bool>((ref) async {
  return ref.read(gemmaServiceProvider).isAnyInstalled();
});

// Effective availability — honours preview mode for devs without a model.
final aiAvailableProvider = FutureProvider<bool>((ref) async {
  if (ref.watch(aiPreviewModeProvider)) return true;
  return ref.watch(selectedModelInstalledProvider.future);
});
```

After any `install`/`delete`:

```dart
ref.invalidate(selectedModelInstalledProvider);
ref.invalidate(anyModelInstalledProvider);
```

---

## 7. First-launch model setup — production flow

Add a post-onboarding gate in your router:

```dart
redirect: (context, state) async {
  final prefs = await SharedPreferences.getInstance();
  final onboardingDone = prefs.getBool('onboarding_completed') ?? false;
  final aiSetupShown = prefs.getBool('ai_setup_shown') ?? false;
  final loc = state.matchedLocation;

  if (!onboardingDone && loc != '/onboarding') return '/onboarding';

  if (onboardingDone && !aiSetupShown && loc != '/ai-setup') {
    final hasModel = await GemmaService().isAnyInstalled();
    if (!hasModel) return '/ai-setup';
    await prefs.setBool('ai_setup_shown', true);
  }
  return null;
},
```

- Fresh install → onboarding → `/ai-setup`.
- App reinstall clears SharedPreferences, so the flow fires again — this is
  what the user sees on "uninstall and reinstall" and is correct.
- A user who already has a model installed (reached this code somehow) is
  silently marked as setup-done and falls through to `/home`.

### `AiSetupScreen` contract

Single screen, three model cards, a **Skip for now / Continue to app**
button, no HF token fields, no file paths, no jargon.

Copy guidelines:
- Call models **Compact / Balanced / Advanced**, not `1B / E2B / E4B`.
- State size in MB or GB, never bytes.
- Tell the user what the trade-off is ("fast, works on any phone" vs "best
  quality, needs 6 GB+ RAM").

Download behaviour:
- **Do not** call `selectedModelProvider.set(m)` when the user taps Download
  — wait until `onDone` fires. A failed download otherwise leaves the user
  on an uninstalled model and the app thinks AI is offline.
- On success, mark `ai_setup_shown = true`, snackbar "Model is ready", then
  `context.go('/home')` if this was the initial setup.
- On failure, render an error card with friendly copy + a Retry button. If
  the error is auth (gated repo), also render **Copy model page link** with
  a snackbar instruction: *"Open it in your browser, sign in to
  HuggingFace, click 'Agree and access', then come back and tap Retry."*

### Installed ≠ Active — two states, not one

Users can install more than one model over time (they try Compact first,
then upgrade to Balanced, then keep both on disk). If every installed model
looks the same in the picker, it's impossible to tell which one the app
will actually use — and nothing tells them how to switch.

Three visual states per card, not two:

| State | Border | Badge | Trailing action |
|---|---|---|---|
| Not installed | 0.6 px hairline | — | `Download (size)` primary |
| Installed, not active | 0.6 px hairline | neutral grey "INSTALLED" pill | `Use this model` outlined button |
| **Active** | **2 px brand blue** | blue "ACTIVE" pill | "Currently in use" label (no button) |

The outlined "Use this model" button is the fix. Tapping it calls
`selectedModelProvider.notifier.set(m)`, invalidates
`selectedModelInstalledProvider`, and shows a confirmation snackbar
("Balanced is now active"). All subsequent AI calls route through the new
active model.

```dart
void _selectModel(GemmaModel m) {
  ref.read(selectedModelProvider.notifier).set(m);
  ref.invalidate(selectedModelInstalledProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('${friendlyName(m)} is now active.')),
  );
}
```

Pass `isActive: selected.id == m.id` into every card and branch the trailing
action on `isActive / installed / neither`. Never colour the "INSTALLED"
badge in brand blue — reserve that colour for the **one** active model so
the user's eye catches it instantly.

---

## 8. Injecting user data into the AI (app context)

Users want to ask things like "how many starters do I have?" and "when did
I last feed Bubbles?". Generic chat can't answer that — you have to feed
the model the live data.

### `AppContext` — compact snapshot

```dart
class AppContext {
  final List<Starter> starters;
  final Map<String, List<Feeding>> recentFeedingsByStarter; // cap 5/starter
  final List<BakePlan> plans;
  final DateTime generatedAt;

  String formatForAi() {
    if (starters.isEmpty && plans.isEmpty) {
      return 'USER APP DATA: empty. No starters, feedings, or bake plans yet.';
    }
    final buf = StringBuffer('USER APP DATA (as of ${_fmtDate(generatedAt)}):\n');
    // ... starters block (name, age, hydration, health, last fed relative)
    // ... feedings (5 most recent per starter, compact)
    // ... plans (name, target time, progress, next step)
    return buf.toString().trim();
  }
}
```

Rules for formatting:
- Use **relative times** ("2h ago", "in 3d") — the model handles these
  better than ISO timestamps.
- Cap per-starter feedings at 5 — enough for pattern questions, tiny prompt
  budget.
- Skip deleted rows (your Isar repos already filter).
- Hard ceiling around 500 tokens; if you need more, summarise further.

### Fresh on every send, not cached

```dart
final context = await buildAppContext(ref); // reads Isar NOW
final reply = await ref.read(aiServiceProvider).chat(
  messages: [...],
  appContext: context.formatForAi(),
);
```

Caching the snapshot at app-open is tempting but wrong: users log a feeding
and immediately ask "did I log it?" — the model must see the write. Reading
Isar is cheap; do it every send.

### Guardrail in the system instruction

```dart
final baseChat =
    'You are a friendly, expert sourdough coach. Keep replies under 100 '
    'words. Never use emojis.';
final grounding = (appContext == null || appContext.trim().isEmpty) ? ''
    : '\n\nUse the following live data when the baker asks about their own '
      'starters, feedings, or bake plans. If the question is about their '
      'data and the data is missing, say so briefly — do NOT invent '
      'values.\n\n$appContext';
```

The "do NOT invent" line matters. Without it, Gemma hallucinates plausible
numbers.

---

## 9. Error handling — the policy

Golden rule: **`debugPrint` the real exception, never show raw strings in
the UI.** Every UI surface that can show an error shows a friendly message
with a retry path.

### `AiErrorState` — shared widget

```dart
class AiErrorState extends ConsumerWidget {
  final VoidCallback? onRetry;
  final String? heading;
  final String? detail;
  const AiErrorState({super.key, this.onRetry, this.heading, this.detail});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedModelProvider);
    final canUpgrade = selected.id != kGemmaCatalog.last.id;
    // Heading default: "Our AI is still learning"
    // Detail default: "Couldn't finish that request. Retry, or pick a larger
    //                  on-device model in Settings for better answers."
    // Buttons: [Try again] + (if canUpgrade) [Upgrade model → AiSetupScreen]
  }
}
```

Use this widget in:
- `AiResultCard` error branch.
- Chat bubble when `message.isError`.
- Any ad-hoc AI sheet.

### Slow-hint on load

`AiResultCard` arms a 6-second timer. If the future hasn't resolved by
then, flip the label to **"Still thinking…"** + *"First response after
opening the app takes a few seconds. Hang tight."* This covers the one-off
cold-load latency (model paging into RAM on iOS).

### Error classifier — copy that doesn't lie

For download errors:

| Signal | User-facing copy |
|---|---|
| `GemmaAuthException`, `401`, `403`, `unauthorized`, `forbidden` | "This model is gated on HuggingFace and needs a one-time license acceptance. Open the model page, sign in, click 'Agree and access', then tap Retry." |
| `404`, `not found` | "This model isn't available right now. Pick another option." |
| `timeout`, `timed out` | "Download is taking too long. Check your Wi-Fi and try again." |
| `socket`, `connection refused/reset`, `host lookup`, `unreachable` | "No internet connection. Make sure Wi-Fi is on, then retry." |
| `space`, `enospc`, `storage` | "Not enough storage on this device." |
| anything else | "Download didn't finish. Tap Retry." |

**Don't** say "check your internet connection" for 401/403. The network is
fine; HuggingFace rejected the request. Showing a network message here is
what drove every user-reported bug in this project.

### `buildAsyncErrorPlaceholder` for data-loading

For `AsyncValue.when(error: …)` branches (not AI — Isar/stream errors):

```dart
Widget buildAsyncErrorPlaceholder(Object error, StackTrace? stack,
    {String? where, String? message}) {
  debugPrint('[${where ?? 'Async'}] $error\n$stack');
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_rounded, size: 32, color: Colors.grey),
        const SizedBox(height: 12),
        Text(message ?? "Couldn't load this right now. Pull to refresh or "
            "try again in a moment.", textAlign: TextAlign.center),
      ]),
    ),
  );
}
```

Use it everywhere you had `error: (e, _) => Center(child: Text('Error: $e'))`.

---

## 10. Dev vs Production UI — the `devMode` switch

```dart
// lib/core/utils/dev_mode.dart
import 'package:flutter/foundation.dart';

/// Gate for every dev-only UI affordance: HF token fields, file-path display,
/// warm-up diagnostics, preview-mode toggle, test-chat screen.
///
/// Release builds always hide this (kDebugMode is false). In debug, flip the
/// trailing `&& true` to preview the production experience without making a
/// release build.
const bool devMode = kDebugMode && true;
```

Wrap every dev-facing element:

```dart
if (devMode) ...[
  _hfTokenInput(),
  _fetchFromFirebaseButton(),
  _filePathDisplay(),
]
```

Production users never see:
- HF token textfield
- "Fetch token from Firebase" button
- Gemma file paths in documents directory
- `modelWarmStatusProvider` panels
- AI preview mode toggle
- Raw model IDs ("gemma3-1b", "gemma3n-e2b") — only "Compact", "Balanced", "Advanced".

Keep the dev screen (`GemmaSetupScreen` in this project) reachable behind
`devMode` so testers can still debug. Production Settings links to
`AiSetupScreen` which is the friendly version.

---

## 10b. User-facing "Disable AI" toggle

Give end users a single switch in Settings that turns the AI layer off
completely. The assistant is a big feature, but it's also a big resource
cost — some users will want it gone. A clear toggle with honest info about
what it saves is better than forcing them to uninstall or resent the app.

### What the toggle actually does

When the toggle is flipped **ON** (AI disabled):

1. Persist `ai_disabled = true` in SharedPreferences.
2. `aiAvailableProvider` returns `false`, so every `AiButton` across the
   app hides itself (they already check availability).
3. Immediately call `GemmaService().unload()` to drop the loaded
   `InferenceModel` and free the model's RAM footprint (~1.2 GB resident
   for E2B, ~2 GB for E4B).
4. The **installed model files stay on disk** — don't delete them. If the
   user flips back, we avoid a multi-GB re-download.
5. Optionally offer a separate "Free up storage" action (routes to
   `AiSetupScreen` where they can delete specific models).

When flipped **OFF**:

- Clear the flag. First AI call reloads the model lazily (same 2–5 s cold
  warm-up users saw on first launch — surface the slow-hint).

### Provider

```dart
// lib/core/services/ai/ai_providers.dart

class AiDisabledNotifier extends StateNotifier<bool> {
  AiDisabledNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('ai_disabled') ?? false;
  }

  Future<void> set(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ai_disabled', value);

    // Free the loaded model immediately when the user turns AI off.
    if (value) {
      try { await GemmaService().unload(); } catch (_) {}
    }
  }
}

final aiDisabledProvider =
    StateNotifierProvider<AiDisabledNotifier, bool>((_) => AiDisabledNotifier());
```

Wire it into the availability check **before** any other gating:

```dart
final aiAvailableProvider = FutureProvider<bool>((ref) async {
  if (ref.watch(aiDisabledProvider)) return false;      // user-level off switch
  if (ref.watch(aiPreviewModeProvider)) return true;    // dev preview
  return ref.watch(selectedModelInstalledProvider.future);
});
```

### Settings UI

Two pieces: the switch itself and an honest info block under it.

```dart
class _AiDisableTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disabled = ref.watch(aiDisabledProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: const Text('Disable AI assistant'),
          subtitle: Text(
            disabled
                ? 'AI is OFF. All AI buttons are hidden across the app.'
                : 'Turn off if you don\'t want on-device AI features.',
            style: theme.textTheme.bodySmall,
          ),
          value: disabled,
          activeThumbColor: AppColors.primaryButton,
          onChanged: (v) => ref.read(aiDisabledProvider.notifier).set(v),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What disabling AI does',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                _bullet(theme, 'Frees up memory while the app runs — '
                    'the model unloads right away (~1–2 GB of RAM).'),
                _bullet(theme, 'Hides every AI button, tip, and chat screen.'),
                _bullet(theme, 'The downloaded model files stay on your '
                    'device. Turn AI back on anytime without re-downloading.'),
                _bullet(theme, 'Saves some battery during long sessions — '
                    'no cold-load warm-ups.'),
                const SizedBox(height: 6),
                Text(
                  'Want to reclaim storage too? Open "Manage AI model" and '
                  'delete the installed variant.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _bullet(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('•  '),
          Expanded(
            child: Text(text,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.4)),
          ),
        ]),
      );
}
```

Place `_AiDisableTile` at the **bottom** of the AI section in Settings —
after the "Manage AI model" tile. This order matters: users who want to
disable AI have already seen the option to manage/upgrade it first.

### Copy rules

- Call it **"Disable AI assistant"** — not "AI off" (ambiguous) or "Kill
  AI" (aggressive).
- Be specific about what's saved: memory, not "performance". Users
  understand GB; they don't know what "performance" means here.
- Be explicit that **model files stay on disk**. A common mental model is
  "disabling = uninstalling"; correct it upfront.
- Link to the delete-model flow for users who actually want to reclaim
  storage.

### What does NOT need to change

- `AiButton` already hides when `aiAvailableProvider` is false — no edit
  needed.
- `AiChatScreen` already renders `_UnavailableState` when unavailable — it
  just shows "AI Assistant needs setup" which is close enough. Tighten the
  copy to mention the toggle if you want: *"AI is turned off. Re-enable in
  Settings > AI Assistant."*
- The router gate to `/ai-setup` intentionally **only** checks for a
  missing model, not the disabled flag — a user who turned AI off doesn't
  want to be force-marched back through setup on next launch.

---

## 11. Cross-platform local notifications (step reminders)

Common pitfall: the first iteration was iOS-only (`if (!Platform.isIOS)
return`). If you ship to Android, you must:

1. Initialize with `AndroidInitializationSettings('@mipmap/ic_launcher')`.
2. Pre-create a notification channel at init (Android 8+).
3. Provide `AndroidNotificationDetails` in every schedule call.
4. Request `POST_NOTIFICATIONS` at runtime on Android 13+ via
   `Permission.notification.request()`.
5. Use `androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle` for
   exact alarms.

```dart
class NotificationService {
  static const _channelId = 'bake_plan_steps';
  static const _channelName = 'Bake plan steps';

  static Future<void> init() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(
        tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));

    await FlutterLocalNotificationsPlugin().initialize(
      const InitializationSettings(
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    if (Platform.isAndroid) {
      await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            _channelId, _channelName,
            description: 'Step reminders',
            importance: Importance.high,
          ));
    }
  }

  Future<bool> requestPermission() async {
    if (Platform.isIOS) {
      return (await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, sound: true, badge: true)) ?? false;
    }
    if (Platform.isAndroid) {
      return (await Permission.notification.request()).isGranted;
    }
    return false;
  }
}
```

Re-schedule cleanly by cancelling the plan's existing notifications before
adding new ones. Soft-delete of a step must `cancelStepNotification` too,
or you leak a ghost alert.

---

## 12. Isar — the local source of truth

The AI reads from Isar, not Firebase. Isar is also where iCloud backup hooks
attach (iOS file-based backup survives uninstall).

### Collection shape

Every collection has sync fields so the upgrade to a proper replication
layer later is painless:

```dart
@collection
class StarterEntity {
  Id isarId = Isar.autoIncrement;
  @Index(unique: true) late String uuid;

  // ... domain fields ...

  // Sync fields — every writer sets these
  late DateTime updatedAt;
  late bool isDeleted;       // soft delete
  late int version;          // bumped on every update
  late int syncStatus;       // 0=synced, 1=pending
}
```

### Initialise once in `main()`

```dart
class IsarService {
  static Future<Isar> init() async {
    final dir = await getApplicationDocumentsDirectory();
    return Isar.open(
      [StarterEntitySchema, FeedingEntitySchema, BakePlanEntitySchema],
      directory: dir.path,
    );
  }
}
```

Expose via Riverpod and override in `ProviderScope`:

```dart
final isarProvider = Provider<Isar>((_) =>
    throw UnimplementedError('Initialize in main'));

// main.dart:
ProviderScope(
  overrides: [isarProvider.overrideWithValue(isar)],
  child: MyApp(),
);
```

### Repository pattern

Thin wrapper around Isar for each collection. The AI's `buildAppContext`
reads through these repos — nothing queries Isar directly from widgets.

---

## 13. iOS production checklist

- Test on a real device. Simulators run MediaPipe LLM way faster than any
  real iPhone and hide cold-load latency.
- Minimum iPhone tested for the 1B model: iPhone 12 (6 GB RAM). E2B works on
  iPhone 14 Pro. E4B needs iPhone 15 Pro Max (8 GB) or later.
- `PreferredBackend.cpu` is conservative but consistent. Try
  `PreferredBackend.gpu` if you have the device coverage to test
  regressions.
- First inference after cold launch is 2–5 s. The `_slow` hint in
  `AiResultCard` covers this visually.
- Download sizes are big (3–4 GB for E2B/E4B). Warn users on cellular; the
  plugin doesn't gate network itself.
- `getApplicationDocumentsDirectory()` is included in iCloud backup by
  default. For a 3.1 GB model you probably want to exclude that file from
  backup — set the `NSURLIsExcludedFromBackupKey` attribute via a method
  channel after install.

---

## 14. Production launch checklist

- [ ] `devMode = kDebugMode && true` flipped to `false` for release, or
      confirmed that `kDebugMode` is already false in release builds.
- [ ] `Firebase.initializeApp()` actually has a `google-services.json`
      (Android) and `GoogleService-Info.plist` (iOS) wired in.
- [ ] HF token pushed to Firebase RTDB at `/hftoken` with correct read
      rules. Account owning that token has accepted every gated Gemma
      model's license.
- [ ] `FlutterGemma.initialize()` fires before anything else touches the
      plugin. Test this by throwing a breakpoint in `_specFor`.
- [ ] Router gate redirects to `/ai-setup` on fresh install.
- [ ] `ai_setup_shown` flag set on both success and skip paths.
- [ ] Every `catch`/`error:` branch in the project logs via `debugPrint`
      and renders friendly copy. Grep for `'Error: $e'` and `'${e}'` —
      should have zero hits.
- [ ] No raw "1B / E2B / E4B" strings in production-visible UI.
- [ ] Notifications tested on both iOS and Android 13+ device.
- [ ] `Permission.notification.request()` called at a sane moment (during
      onboarding, not on first app open).
- [ ] Upgrade-model CTA in `AiErrorState` navigates to `AiSetupScreen`, not
      `GemmaSetupScreen`.
- [ ] Settings shows a prominent "Manage AI model" tile that opens the
      production screen — regardless of whether a model is installed.

---

## 15. Common pitfalls — checked against

| Symptom | Root cause | Fix |
|---|---|---|
| HTTP 401 on first download with valid token | `FlutterGemma.initialize` called after first use of the plugin | Call it in `main()` before anything else |
| HTTP 401 only on Balanced/Advanced | HF account hasn't accepted Google Gemma license | Accept on `huggingface.co/google/gemma-3n-E2B-it-litert-preview` and the E4B page |
| HTTP 404 on download | Wrong filename in model URL | Use the URLs from `flutter_gemma` example app, not the repo's README |
| `LateInitializationError: session has not been initialised` | Using `createChat()` | Use `createSession()` per call |
| `Failed to add query chunk … AddQueryChunk should not be called before PredictDone` | Concurrent AI calls | Serialise via future chain in `GemmaService` |
| Settings says "AI model not installed" even though one is | Selected model != installed model, and provider defaults to `false` during loading | Use `anyModelInstalledProvider`, render `.when(loading: …)` |
| Error card says "check your internet" but internet works | Classifier lumps 401/403 into network errors | Split auth from network in `_humanError`; show license URL for auth |
| AI answers generically, ignores user's starters | No context injection | `buildAppContext(ref)` on every send + grounding paragraph in instructions |
| Model keeps hallucinating timestamps | Raw ISO dates in prompt | Use relative times ("2h ago") in `AppContext.formatForAi` |
| Android notifications silently fail | iOS-only guards in `NotificationService` | Remove guards, add `AndroidNotificationDetails`, request POST_NOTIFICATIONS |
| Dev panel leaks into TestFlight builds | `devMode = kDebugMode && true` but release build still shows | Check the compiler actually strips it; tree-shaking relies on `kDebugMode` being a const `false` in release |
| Two installed models both look "selected" in picker | Card reused the same brand colour + badge for "installed" and "active" | Separate visual states: `INSTALLED` pill in neutral grey vs `ACTIVE` pill in brand blue; add a `Use this model` button on installed-but-not-active cards that sets `selectedModelProvider` |

---

## File layout cheat-sheet

```
lib/
  core/
    services/ai/
      ai_providers.dart          Riverpod state (selected model, preview mode, HF token, warm status)
      ai_service.dart            High-level AI methods (chat, explainHealth, suggestPlanStep, …)
      app_context.dart           AppContext + buildAppContext (reads Isar for AI)
      gemma_models.dart          Catalog of 3 variants
      gemma_service.dart         flutter_gemma wrapper — singleton + mutex
      hf_token_service.dart      Firebase RTDB → SharedPreferences
    utils/
      dev_mode.dart              const bool devMode
      notification_service.dart  Cross-platform local notifications
  data/local/
    collections/                 Isar @collection classes
    repositories/                Isar-backed repos (mirror old API)
    isar_service.dart            Isar.open wiring
    local_providers.dart         Riverpod providers for repos
  features/
    settings/
      ai_setup_screen.dart       PRODUCTION model picker (used by onboarding gate + Settings)
      gemma_setup_screen.dart    DEV-ONLY screen (HF token, paths, manual download/delete)
  shared/widgets/
    ai_widgets.dart              AiButton, AiResultCard, AiErrorState, showAiSheet
    error_placeholder.dart       Friendly AsyncValue.error replacement
  app/
    router.dart                  /onboarding → /ai-setup → /home gate
  main.dart                      Firebase → HF token → FlutterGemma.initialize → Isar → Notifications → runApp
```

That's the whole recipe. Copying this layout plus the code blocks above
gets you from zero to a production-safe Gemma integration without hitting
any of the traps documented in §15.
