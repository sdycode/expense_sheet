import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

/// After this many hits the system switches from owner (default) keys to user keys.
const int kOwnerHitLimit = 50;

/// Supported provider identifiers (must match Firebase RTDB path segments).
/// Order reflects the preferred cascade: Gemini → SambaNova → Groq → Mistral → Cloudflare.
const List<String> kSupportedProviders = [
  'gemini',
  'sambanova',
  'groq',
  'mistral',
  'cloudflare',
];


// ── Exception ─────────────────────────────────────────────────────────────────

/// Thrown when no keys remain (all exhausted or none configured) for a provider.
class NoAvailableKeyException implements Exception {
  final String provider;
  const NoAvailableKeyException(this.provider);

  @override
  String toString() =>
      'NoAvailableKeyException: No available API keys for "$provider". '
      'Please add your own keys in AI Key Settings.';
}

// ── KeyManager ────────────────────────────────────────────────────────────────

/// Manages multi-provider API key rotation using Firebase Realtime Database.
///
/// ### RTDB Schema
/// ```
/// default_keys/{provider}/list   → List<String>  (owner/app keys, < 50 hits)
/// user_keys/{uid}/{provider}/list → List<String>  (user-provided keys, >= 50 hits)
/// user_usage/{uid}/hit_count     → int            (cumulative requests)
/// ```
///
/// ### Usage
/// ```dart
/// final key = await KeyManager.instance.getBestAvailableKey('gemini');
/// // on 429/401 → call reportKeyFailure then retry
/// KeyManager.instance.reportKeyFailure(failedKey, 'gemini');
/// // on success → call once per successful request
/// await KeyManager.instance.incrementHitCount();
/// ```
class KeyManager {
  KeyManager._();

  /// Global singleton.
  static final KeyManager instance = KeyManager._();

  final _db = FirebaseDatabase.instance;

  // In-memory rotation cursors (index into the list, wraps on exhaustion)
  final Map<String, int> _defaultCursor = {};
  final Map<String, int> _userCursor = {};

  // Session-level key list caches to avoid repeated RTDB reads
  final Map<String, List<String>> _defaultCache = {};
  final Map<String, List<String>> _userCache = {};

  // Last fetched hit count — updated after each increment
  int? _cachedHitCount;

  // ── Auth helper ───────────────────────────────────────────────────────────

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns the best available key for [provider].
  ///
  /// Picks from **default_keys** when hit_count < [kOwnerHitLimit],
  /// falls back to **user_keys** otherwise.
  ///
  /// Throws [NoAvailableKeyException] if the relevant list is empty.
  Future<String> getBestAvailableKey(String provider) async {
    final hitCount = await _fetchHitCount();
    if (hitCount < kOwnerHitLimit) {
      return _nextFromDefault(provider);
    } else {
      return _nextFromUser(provider);
    }
  }

  /// Marks [key] as failed for [provider] and advances the rotation cursor.
  ///
  /// On the **next** call to [getBestAvailableKey] the following key in the
  /// list will be returned.  The cache is invalidated so a fresh RTDB read
  /// occurs, handling the case where the owner added new keys mid-session.
  void reportKeyFailure(String key, String provider) {
    final hitCount = _cachedHitCount ?? 0;
    if (hitCount < kOwnerHitLimit) {
      _defaultCursor[provider] = (_defaultCursor[provider] ?? 0) + 1;
      _defaultCache.remove(provider); // force re-fetch
    } else {
      _userCursor[provider] = (_userCursor[provider] ?? 0) + 1;
      _userCache.remove(provider);
    }
    debugPrint('KeyManager: key failure reported for $provider — cursor advanced.');
  }

  /// Increments `user_usage/{uid}/hit_count` by 1 after a successful request.
  Future<void> incrementHitCount() async {
    final uid = _uid;
    if (uid == null) return;
    await _db.ref('user_usage/$uid/hit_count').set(ServerValue.increment(1));
    _cachedHitCount = (_cachedHitCount ?? 0) + 1;
    debugPrint('KeyManager: hit_count → $_cachedHitCount');
  }

  /// Returns the current hit count for the logged-in user (reads RTDB).
  Future<int> getHitCount() => _fetchHitCount(forceRefresh: true);

  /// Returns true if there is at least one configured key (owner or user)
  /// for [provider].  Used by the banner / configuration check.
  Future<bool> isAnyKeyConfigured(String provider) async {
    final defaults = await _loadDefaultKeys(provider);
    if (defaults.isNotEmpty) return true;
    final userKeys = await _loadUserKeys(provider);
    return userKeys.isNotEmpty;
  }

  /// Clears in-session caches.  Call after adding/removing user keys.
  void clearCache() {
    _defaultCache.clear();
    _userCache.clear();
    _cachedHitCount = null;
  }

  // ── User key CRUD — used by ApiKeySettingsScreen ──────────────────────────

  /// Fetches the list of user-defined keys for [provider] (always fresh).
  Future<List<String>> getUserKeys(String provider) async {
    _userCache.remove(provider);
    return _loadUserKeys(provider);
  }

  /// Appends [key] to `user_keys/{uid}/{provider}/list` (deduplicates).
  Future<void> addUserKey(String provider, String key) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not logged in');
    final current = await getUserKeys(provider);
    if (current.contains(key)) return;
    await _db
        .ref('user_keys/$uid/$provider/list')
        .set([...current, key]);
    _userCache.remove(provider);
    debugPrint('KeyManager: added user key for $provider (total=${current.length + 1})');
  }

  /// Removes the key at [index] from `user_keys/{uid}/{provider}/list`.
  Future<void> removeUserKeyAt(String provider, int index) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not logged in');
    final current = await getUserKeys(provider);
    if (index < 0 || index >= current.length) return;
    final updated = List<String>.from(current)..removeAt(index);
    await _db.ref('user_keys/$uid/$provider/list').set(updated);
    _userCache.remove(provider);
    _userCursor.remove(provider); // reset rotation after deletion
    debugPrint('KeyManager: removed user key[$index] for $provider');
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<int> _fetchHitCount({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedHitCount != null) return _cachedHitCount!;
    final uid = _uid;
    if (uid == null) return 0;
    final snap = await _db.ref('user_usage/$uid/hit_count').get();
    final count = (snap.value as int?) ?? 0;
    _cachedHitCount = count;
    return count;
  }

  Future<String> _nextFromDefault(String provider) async {
    final keys = await _loadDefaultKeys(provider);
    if (keys.isEmpty) throw NoAvailableKeyException(provider);
    final cursor = (_defaultCursor[provider] ?? 0) % keys.length;
    _defaultCursor[provider] = cursor;
    return keys[cursor];
  }

  Future<String> _nextFromUser(String provider) async {
    final keys = await _loadUserKeys(provider);
    if (keys.isEmpty) throw NoAvailableKeyException(provider);
    final cursor = (_userCursor[provider] ?? 0) % keys.length;
    _userCursor[provider] = cursor;
    return keys[cursor];
  }

  Future<List<String>> _loadDefaultKeys(String provider) async {
    if (_defaultCache.containsKey(provider)) return _defaultCache[provider]!;
    final snap = await _db.ref('default_keys/$provider/list').get();
    final list = _parseList(snap.value);
    _defaultCache[provider] = list;
    return list;
  }

  Future<List<String>> _loadUserKeys(String provider) async {
    final uid = _uid;
    if (uid == null) return [];
    if (_userCache.containsKey(provider)) return _userCache[provider]!;
    final snap = await _db.ref('user_keys/$uid/$provider/list').get();
    final list = _parseList(snap.value);
    _userCache[provider] = list;
    return list;
  }

  /// Handles both Firebase `List` and `Map` node formats.
  List<String> _parseList(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value.whereType<String>().where((s) => s.isNotEmpty).toList();
    }
    if (value is Map) {
      return value.values.whereType<String>().where((s) => s.isNotEmpty).toList();
    }
    return [];
  }
}
