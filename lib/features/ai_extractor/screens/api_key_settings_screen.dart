import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/key_manager.dart';
import '../services/ai_request_service.dart';
import '../providers/ai_extractor_provider.dart';

// ── Provider metadata ─────────────────────────────────────────────────────────

class _ProviderInfo {
  final String id;
  final String label;
  final String hint;
  final String getKeyUrl;
  final IconData icon;
  final Color color;

  const _ProviderInfo({
    required this.id,
    required this.label,
    required this.hint,
    required this.getKeyUrl,
    required this.icon,
    required this.color,
  });
}

const _providers = [
  _ProviderInfo(
    id: 'gemini',
    label: 'Gemini (Google)',
    hint: 'AIza...',
    getKeyUrl: 'https://aistudio.google.com/app/apikey',
    icon: Icons.auto_awesome,
    color: Color(0xFF4285F4),
  ),
  _ProviderInfo(
    id: 'sambanova',
    label: 'SambaNova',
    hint: 'sn-...',
    getKeyUrl: 'https://cloud.sambanova.ai/apis',
    icon: Icons.speed,
    color: Color(0xFF00B388),
  ),
  _ProviderInfo(
    id: 'groq',
    label: 'Groq',
    hint: 'gsk_...',
    getKeyUrl: 'https://console.groq.com/keys',
    icon: Icons.bolt,
    color: Color(0xFFF55036),
  ),
  _ProviderInfo(
    id: 'mistral',
    label: 'Mistral AI',
    hint: 'your-mistral-key',
    getKeyUrl: 'https://console.mistral.ai/api-keys',
    icon: Icons.air,
    color: Color(0xFFFF7000),
  ),
  _ProviderInfo(
    id: 'cloudflare',
    // Credential must be: accountId|apiToken  (pipe-separated)
    label: 'Cloudflare Workers AI',
    hint: 'accountId|apiToken',
    getKeyUrl: 'https://dash.cloudflare.com/profile/api-tokens',
    icon: Icons.cloud_outlined,
    color: Color(0xFFF6821F),
  ),
];


// ── Screen ────────────────────────────────────────────────────────────────────

/// User-facing screen for managing per-provider API keys and viewing usage.
///
/// - Select a provider (Gemini / Groq / OpenRouter)
/// - Add / delete keys that are stored in Firebase RTDB under
///   `user_keys/{uid}/{provider}/list`
/// - View current hit count vs the 50-hit owner-key threshold
///
/// **Does not touch existing UI layouts, prompts, parsing, or result screens.**
class ApiKeySettingsScreen extends StatefulWidget {
  const ApiKeySettingsScreen({super.key});

  @override
  State<ApiKeySettingsScreen> createState() => _ApiKeySettingsScreenState();
}

class _ApiKeySettingsScreenState extends State<ApiKeySettingsScreen> {
  final _keyController = TextEditingController();
  bool _obscure = true;
  bool _isSaving = false;
  bool _isloading = true;

  int _selectedProviderIndex = 0;
  List<String> _userKeys = [];
  int _hitCount = 0;

  _ProviderInfo get _provider => _providers[_selectedProviderIndex];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _isloading = true);
    try {
      final keys = await KeyManager.instance.getUserKeys(_provider.id);
      final hitCount = await KeyManager.instance.getHitCount();
      if (mounted) {
        setState(() {
          _userKeys = keys;
          _hitCount = hitCount;
          _isloading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isloading = false);
        _snack('Error loading keys: $e', isError: true);
      }
    }
  }

  Future<void> _save() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      _snack('Please enter an API key.', isError: true);
      return;
    }
    setState(() => _isSaving = true);
    try {
      await KeyManager.instance.addUserKey(_provider.id, key);
      _keyController.clear();
      if (mounted) _snack('Key saved ✓', isError: false);
      await _refresh();
    } catch (e) {
      if (mounted) _snack('Save failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _delete(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Key'),
        content: const Text('Remove this API key from your account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await KeyManager.instance.removeUserKeyAt(_provider.id, index);
      if (mounted) _snack('Key removed.', isError: false);
      await _refresh();
    } catch (e) {
      if (mounted) _snack('Delete failed: $e', isError: true);
    }
  }

  void _snack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Key Settings'),
        centerTitle: true,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // ── AI Engine Selection (PREMIUM LOOK) ──────────────────────────
          _EngineSelectionSection(),
          const SizedBox(height: 32),

          // ── Usage card ──────────────────────────────────────────────────
          _UsageCard(hitCount: _hitCount),
          const SizedBox(height: 32),

          // ── Key Management Header ───────────────────────────────────────
          Row(
            children: [
              Icon(Icons.key, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Key Management',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          const SizedBox(height: 8),

          // ── Provider selector ───────────────────────────────────────────
          Text(
            'Select Provider to Manage Keys',
            style: theme.textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _ProviderSelector(
            selectedIndex: _selectedProviderIndex,
            onChanged: (i) {
              setState(() {
                _selectedProviderIndex = i;
                _userKeys = [];
                _keyController.clear();
              });
              _refresh();
            },
          ),
          const SizedBox(height: 24),

          // ── Add key card ────────────────────────────────────────────────
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_provider.icon, color: _provider.color, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Add ${_provider.label} Key',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Get a free key at ${_provider.getKeyUrl}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _keyController,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      hintText: _provider.hint,
                      prefixIcon: const Icon(Icons.key_outlined),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            tooltip: _obscure ? 'Show' : 'Hide',
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                          IconButton(
                            icon: const Icon(Icons.content_paste_outlined),
                            tooltip: 'Paste from clipboard',
                            onPressed: () async {
                              final data = await Clipboard.getData(
                                Clipboard.kTextPlain,
                              );
                              if (data?.text != null) {
                                _keyController.text = data!.text!.trim();
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.add_circle_outline),
                      label: Text(_isSaving ? 'Saving…' : 'Save Key'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 46),
                        backgroundColor: _provider.color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Your keys list ──────────────────────────────────────────────
          Row(
            children: [
              Text(
                'Your ${_provider.label} Keys',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (_isloading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),

          if (!_isloading && _userKeys.isEmpty)
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              color: colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: colorScheme.onSurfaceVariant,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No personal keys yet. The app uses owner keys until '
                        'you exceed $kOwnerHitLimit requests.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...List.generate(_userKeys.length, (i) {
              final key = _userKeys[i];
              final masked = _maskKey(key);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: Icon(
                    Icons.vpn_key_outlined,
                    color: _provider.color,
                  ),
                  title: Text(
                    masked,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    'Key ${i + 1} of ${_userKeys.length}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                    ),
                    tooltip: 'Remove key',
                    onPressed: () => _delete(i),
                  ),
                ),
              );
            }),

          const SizedBox(height: 24),

          // ── How it works ────────────────────────────────────────────────
          _HowItWorksCard(theme: theme),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// Shows last 6 chars and masks the rest with ●.
  String _maskKey(String key) {
    if (key.length <= 8) return '●' * key.length;
    return '${'●' * (key.length - 6)}${key.substring(key.length - 6)}';
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _UsageCard extends StatelessWidget {
  final int hitCount;
  const _UsageCard({required this.hitCount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = (hitCount / kOwnerHitLimit).clamp(0.0, 1.0);
    final remaining = (kOwnerHitLimit - hitCount).clamp(0, kOwnerHitLimit);
    final isExceeded = hitCount >= kOwnerHitLimit;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isExceeded ? Icons.lock_outlined : Icons.auto_awesome,
                  color: isExceeded ? Colors.orange : Colors.green,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  isExceeded ? 'Using your personal keys' : 'Using app keys',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                color: isExceeded ? Colors.orange : Colors.green,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isExceeded
                  ? '$hitCount requests used — add your own keys below to keep going.'
                  : '$hitCount / $kOwnerHitLimit free requests used ($remaining remaining)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Engine Selection Section ────────────────────────────────────────────────

class _EngineSelectionSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final aiProvider = Provider.of<AIExtractorProvider>(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final currentProviderId = aiProvider.preferredProvider;
    final currentModel = aiProvider.preferredModel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.psychology_outlined, size: 20, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'AI Extraction Engine',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Choose your preferred model or let the app decide automatically.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              // Auto / Provider Row
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButtonFormField<String?>(
                        value: currentProviderId,
                        decoration: const InputDecoration(
                          labelText: 'Provider',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Auto (Cascade Failover)'),
                          ),
                          ..._providers.map((p) => DropdownMenuItem(
                                value: p.id,
                                child: Text(p.label),
                              )),
                        ],
                        onChanged: (val) {
                          aiProvider.setPreferredAI(val, null);
                        },
                      ),
                    ),
                  ),
                ],
              ),
              if (currentProviderId != null) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: currentModel ?? kProviderModels[currentProviderId]!.first,
                  decoration: const InputDecoration(
                    labelText: 'Model',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  items: kProviderModels[currentProviderId]!
                      .map((m) => DropdownMenuItem(
                            value: m,
                            child: Text(m.split('/').last), // show model name only
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      aiProvider.setPreferredAI(currentProviderId, val);
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ProviderSelector extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _ProviderSelector({
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_providers.length, (i) {
        final p = _providers[i];
        final isSelected = i == selectedIndex;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < _providers.length - 1 ? 8 : 0),
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? p.color.withValues(alpha: 0.12)
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? p.color : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(p.icon, color: isSelected ? p.color : Colors.grey, size: 22),
                    const SizedBox(height: 4),
                    Text(
                      p.label.split(' ').first, // first word only
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? p.color : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _HowItWorksCard extends StatelessWidget {
  final ThemeData theme;
  const _HowItWorksCard({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'How key rotation works',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _Step(n: 1, text: 'First $kOwnerHitLimit requests use the app\'s shared keys — free for you.'),
            _Step(n: 2, text: 'After that, your personal keys are used automatically.'),
            _Step(n: 3, text: 'On 429 (rate-limit) or 503 (overload), the system skips to the next provider entirely.'),
            _Step(n: 4, text: 'Cascade order: Gemini → SambaNova → Groq → Mistral → Cloudflare.'),
            _Step(n: 5, text: 'For Cloudflare, enter your credential as: accountId|apiToken (pipe-separated).'),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String text;
  const _Step({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              '$n',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
