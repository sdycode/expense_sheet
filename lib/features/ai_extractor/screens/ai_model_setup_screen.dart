import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/gemini_service.dart';

/// One-time setup screen where the user enters their Gemini API key.
///
/// The key is stored persistently via [SharedPreferences]. After saving,
/// the screen pops with [true] so the caller can refresh model status.
class AIModelSetupScreen extends StatefulWidget {
  const AIModelSetupScreen({super.key});

  @override
  State<AIModelSetupScreen> createState() => _AIModelSetupScreenState();
}

class _AIModelSetupScreenState extends State<AIModelSetupScreen> {
  final _keyController = TextEditingController();
  bool _obscure = true;
  bool _isSaving = false;
  bool _hasExisting = false;

  @override
  void initState() {
    super.initState();
    _loadExistingKey();
  }

  Future<void> _loadExistingKey() async {
    final key = await GeminiService.loadApiKey();
    if (mounted && key != null) {
      setState(() {
        _hasExisting = true;
        // Show masked placeholder — don't pre-fill for security.
      });
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your API key')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      await GeminiService.saveApiKey(key);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('API key saved ✓'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // true = key was updated
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving key: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _clearKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove API Key'),
        content: const Text('Are you sure you want to remove the saved Gemini API key?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await GeminiService.clearApiKey();
      if (mounted) {
        _keyController.clear();
        setState(() => _hasExisting = false);
        Navigator.pop(context, true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gemini API Setup'),
        actions: [
          if (_hasExisting)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove API key',
              onPressed: _clearKey,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // ── Icon + title ──────────────────────────────────────────────────
          Icon(
            Icons.auto_awesome,
            size: 56,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 14),
          Text(
            'Connect Gemini AI',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Enter your Google Gemini API key to enable AI-powered\ntransaction extraction from screenshots.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // ── API key field ─────────────────────────────────────────────────
          if (_hasExisting) ...[
            Card(
              color: Colors.green.withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: const ListTile(
                leading: Icon(Icons.check_circle, color: Colors.green),
                title: Text('API key is saved'),
                subtitle: Text('Enter a new key below to replace it'),
              ),
            ),
            const SizedBox(height: 16),
          ],

          TextField(
            controller: _keyController,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Gemini API Key',
              hintText: _hasExisting ? 'Enter new key to replace existing' : 'AIza...',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.key_outlined),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                    tooltip: _obscure ? 'Show' : 'Hide',
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  IconButton(
                    icon: const Icon(Icons.content_paste_outlined),
                    tooltip: 'Paste',
                    onPressed: () async {
                      final data = await Clipboard.getData(Clipboard.kTextPlain);
                      if (data?.text != null) {
                        _keyController.text = data!.text!.trim();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Save button ───────────────────────────────────────────────────
          FilledButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: Text(_isSaving ? 'Saving…' : 'Save API Key'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
          const SizedBox(height: 28),

          // ── Info card ─────────────────────────────────────────────────────
          _InfoTile(
            theme: theme,
            icon: Icons.link,
            title: 'Get a free API key',
            subtitle: 'Visit aistudio.google.com → Get API Key\n(no credit card required for free tier)',
          ),
          const SizedBox(height: 10),
          _InfoTile(
            theme: theme,
            icon: Icons.lock_outline,
            title: 'Stored locally on device',
            subtitle: 'Your key is saved only in this app\'s private storage and is never shared.',
          ),
          const SizedBox(height: 10),
          _InfoTile(
            theme: theme,
            icon: Icons.flash_on_outlined,
            title: 'Gemini 1.5 Flash',
            subtitle: 'Uses the fast, free-tier model for image analysis.',
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final ThemeData theme;
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoTile({
    required this.theme,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, height: 1.4)),
      ),
    );
  }
}
