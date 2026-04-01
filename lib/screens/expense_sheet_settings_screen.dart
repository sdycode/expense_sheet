import 'package:flutter/material.dart';
import 'package:MoneyTracker/screens/spreadsheet_picker_screen.dart';
import 'package:MoneyTracker/services/services_module.dart';

/// Primary sheet, single/both update mode, and active sheet pickers.
class ExpenseSheetSettingsScreen extends StatefulWidget {
  const ExpenseSheetSettingsScreen({super.key});

  @override
  State<ExpenseSheetSettingsScreen> createState() =>
      _ExpenseSheetSettingsScreenState();
}

class _ExpenseSheetSettingsScreenState
    extends State<ExpenseSheetSettingsScreen> {
  final _settings = ExpenseSettingsStorage.instance;
  final _storage = SpreadsheetStorageService();
  final _sheets = GoogleSheetsService();
  final _auth = FirebaseAuthService();

  bool _loading = true;
  ExpensePrimarySheet _primary = ExpensePrimarySheet.shared;
  ExpenseSheetsUpdateMode _updateMode = ExpenseSheetsUpdateMode.both;
  bool _secondaryDefaultChecked = true;
  String? _commonId;
  String? _commonName;
  String? _personalId;
  String? _personalName;

  String? get _userEmail => _auth.userEmail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _storage.migrateLegacyActiveSheetIdIfNeeded();
    final primary = await _settings.getPrimarySheet(_userEmail);
    final mode = await _settings.getUpdateMode(_userEmail);
    final secDef = await _settings.getSecondaryCheckboxDefaultChecked(_userEmail);
    final cId = await _storage.getActiveCommonSheetId();
    final pId = await _storage.getActivePersonalSheetId();
    final cInfo = cId != null ? await _storage.getSpreadsheet(cId) : null;
    final pInfo = pId != null ? await _storage.getSpreadsheet(pId) : null;
    if (!mounted) return;
    setState(() {
      _loading = false;
      _primary = primary;
      _updateMode = mode;
      _secondaryDefaultChecked = secDef;
      _commonId = cId;
      _commonName = cInfo?.name;
      _personalId = pId;
      _personalName = pInfo?.name;
    });
  }

  String _helperText() {
    final sharedWord = 'shared';
    final personalWord = 'personal';
    if (_updateMode == ExpenseSheetsUpdateMode.single) {
      if (_primary == ExpensePrimarySheet.shared) {
        return 'Only your $sharedWord sheet will get new rows.';
      }
      return 'Only your $personalWord sheet will get new rows.';
    }
    if (_secondaryDefaultChecked) {
      return 'New expenses go to your primary sheet; the form will offer to also add to the other sheet (on by default).';
    }
    return 'New expenses go to your primary sheet; the form will offer to also add to the other sheet (off by default).';
  }

  Future<void> _openPicker(SpreadsheetPickerPurpose purpose) async {
    final token = await _auth.getAccessToken();
    if (token == null || token.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sign in from the expense screen first.'),
          ),
        );
      }
      return;
    }
    await _sheets.initializeSheetsApiWithToken(token);
    if (!mounted) return;
    final r = await Navigator.push<SpreadsheetPickerResult>(
      context,
      MaterialPageRoute(
        builder: (ctx) => SpreadsheetPickerScreen(
          sheetsService: _sheets,
          purpose: purpose,
        ),
      ),
    );
    if (r == null || !mounted) return;
    if (purpose == SpreadsheetPickerPurpose.common) {
      await _storage.setActiveCommonSheetId(r.spreadsheetId);
    } else {
      await _storage.setActivePersonalSheetId(r.spreadsheetId);
    }
    await _load();
  }

  Widget _segmentRow<T>({
    required String label,
    required List<T> values,
    required List<String> titles,
    required T groupValue,
    required ValueChanged<T> onChanged,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(values.length, (i) {
            final v = values[i];
            final selected = v == groupValue;
            return ChoiceChip(
              label: Text(titles[i]),
              selected: selected,
              onSelected: (_) => onChanged(v),
            );
          }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Expense sheets')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _segmentRow<ExpensePrimarySheet>(
                  label: 'Set primary sheet as',
                  values: const [
                    ExpensePrimarySheet.shared,
                    ExpensePrimarySheet.personal,
                  ],
                  titles: const ['Shared', 'Personal'],
                  groupValue: _primary,
                  onChanged: (v) async {
                    setState(() => _primary = v);
                    await _settings.setPrimarySheet(_userEmail, v);
                  },
                ),
                const SizedBox(height: 20),
                _segmentRow<ExpenseSheetsUpdateMode>(
                  label: 'Update expenses on',
                  values: const [
                    ExpenseSheetsUpdateMode.single,
                    ExpenseSheetsUpdateMode.both,
                  ],
                  titles: const ['Single sheet', 'Both sheets'],
                  groupValue: _updateMode,
                  onChanged: (v) async {
                    setState(() => _updateMode = v);
                    await _settings.setUpdateMode(_userEmail, v);
                  },
                ),
                if (_updateMode == ExpenseSheetsUpdateMode.both) ...[
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Default: also save to the other sheet'),
                    subtitle: const Text(
                      'When on, the add form starts with that option checked.',
                    ),
                    value: _secondaryDefaultChecked,
                    onChanged: (v) async {
                      setState(() => _secondaryDefaultChecked = v);
                      await _settings.setSecondaryCheckboxDefaultChecked(
                        _userEmail,
                        v,
                      );
                    },
                  ),
                ],
                const SizedBox(height: 16),
                Card(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.45,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      _helperText(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 32),
                Text(
                  'Active sheets',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _ActiveSheetCard(
                  typeLabel: 'SHARED',
                  typeDescription: 'Group & household · 10 columns',
                  accentColor: theme.colorScheme.primary,
                  containerColor: theme.colorScheme.primaryContainer
                      .withValues(alpha: 0.45),
                  badgeForeground: theme.colorScheme.onPrimary,
                  sheetName: _commonName,
                  sheetId: _commonId,
                  emptyHint: 'Not set',
                  onPick: () =>
                      _openPicker(SpreadsheetPickerPurpose.common),
                ),
                const SizedBox(height: 12),
                _ActiveSheetCard(
                  typeLabel: 'PERSONAL',
                  typeDescription: 'Owner only · optional · 10 columns',
                  accentColor: theme.colorScheme.tertiary,
                  containerColor: theme.colorScheme.tertiaryContainer
                      .withValues(alpha: 0.45),
                  badgeForeground: theme.colorScheme.onTertiary,
                  sheetName: _personalName,
                  sheetId: _personalId,
                  emptyHint: 'Not set (optional)',
                  onPick: () =>
                      _openPicker(SpreadsheetPickerPurpose.personal),
                ),
              ],
            ),
    );
  }
}

class _ActiveSheetCard extends StatelessWidget {
  const _ActiveSheetCard({
    required this.typeLabel,
    required this.typeDescription,
    required this.accentColor,
    required this.containerColor,
    required this.badgeForeground,
    required this.sheetName,
    required this.sheetId,
    required this.emptyHint,
    required this.onPick,
  });

  final String typeLabel;
  final String typeDescription;
  final Color accentColor;
  final Color containerColor;
  final Color badgeForeground;
  final String? sheetName;
  final String? sheetId;
  final String emptyHint;
  final VoidCallback onPick;

  bool get _hasSheet => sheetId != null && sheetId!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: containerColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: accentColor.withValues(alpha: 0.65),
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: accentColor,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: accentColor.withValues(alpha: 0.35),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          typeLabel,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: badgeForeground,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        typeDescription,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  onPressed: onPick,
                  style: FilledButton.styleFrom(
                    foregroundColor: accentColor,
                  ),
                  child: const Text('Pick'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (!_hasSheet)
              Text(
                emptyHint,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.outline,
                  fontWeight: FontWeight.w500,
                  fontStyle: FontStyle.italic,
                ),
              )
            else ...[
              Text(
                'SHEET NAME',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                sheetName?.trim().isNotEmpty == true
                    ? sheetName!.trim()
                    : 'Untitled sheet',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: accentColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'SPREADSHEET ID',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                sheetId!.trim(),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
