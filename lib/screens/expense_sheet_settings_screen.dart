import 'package:flutter/material.dart';
import 'package:MoneyTracker/screens/spreadsheet_picker_screen.dart';
import 'package:MoneyTracker/services/services_module.dart';

/// Toggles for home/personal checkbox visibility and active sheet pickers.
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
  bool _showToggle = true;
  bool _defaultHomeHidden = true;
  String? _commonId;
  String? _commonName;
  String? _personalId;
  String? _personalName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _storage.migrateLegacyActiveSheetIdIfNeeded();
    final show = await _settings.getShowHomePersonalToggle();
    final defH = await _settings.getDefaultIncludeHomeWhenHidden();
    final cId = await _storage.getActiveCommonSheetId();
    final pId = await _storage.getActivePersonalSheetId();
    final cInfo = cId != null ? await _storage.getSpreadsheet(cId) : null;
    final pInfo = pId != null ? await _storage.getSpreadsheet(pId) : null;
    if (!mounted) return;
    setState(() {
      _loading = false;
      _showToggle = show;
      _defaultHomeHidden = defH;
      _commonId = cId;
      _commonName = cInfo?.name;
      _personalId = pId;
      _personalName = pInfo?.name;
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Expense sheets')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SwitchListTile(
                  title: const Text('Show home/personal toggle on add form'),
                  subtitle: const Text(
                    'When off, new expenses use the default below.',
                  ),
                  value: _showToggle,
                  onChanged: (v) async {
                    setState(() => _showToggle = v);
                    await _settings.setShowHomePersonalToggle(v);
                  },
                ),
                SwitchListTile(
                  title: const Text(
                    'When toggle is hidden: also add to home sheet',
                  ),
                  subtitle: const Text(
                    'If off, expenses go to the personal sheet only.',
                  ),
                  value: _defaultHomeHidden,
                  onChanged: (v) async {
                    setState(() => _defaultHomeHidden = v);
                    await _settings.setDefaultIncludeHomeWhenHidden(v);
                  },
                ),
                const Divider(height: 32),
                const Text(
                  'Active sheets',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ListTile(
                  title: const Text('Home / shared sheet'),
                  subtitle: Text(
                    _commonId == null || _commonId!.isEmpty
                        ? 'Not set'
                        : '${_commonName ?? "Sheet"}\n$_commonId',
                  ),
                  isThreeLine: _commonId != null && _commonId!.isNotEmpty,
                  trailing: FilledButton.tonal(
                    onPressed: () =>
                        _openPicker(SpreadsheetPickerPurpose.common),
                    child: const Text('Pick'),
                  ),
                ),
                ListTile(
                  title: const Text('Personal sheet'),
                  subtitle: Text(
                    _personalId == null || _personalId!.isEmpty
                        ? 'Not set (optional)'
                        : '${_personalName ?? "Sheet"}\n$_personalId',
                  ),
                  isThreeLine:
                      _personalId != null && _personalId!.isNotEmpty,
                  trailing: FilledButton.tonal(
                    onPressed: () =>
                        _openPicker(SpreadsheetPickerPurpose.personal),
                    child: const Text('Pick'),
                  ),
                ),
              ],
            ),
    );
  }
}
