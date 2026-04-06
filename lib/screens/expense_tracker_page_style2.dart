import 'package:MoneyTracker/models/expense.dart';
import 'package:MoneyTracker/models/frequent_expense_item.dart';
import 'package:MoneyTracker/models/spreadsheet_sheet_kind.dart';
import 'package:MoneyTracker/screens/events_page.dart';
import 'package:MoneyTracker/screens/app_settings_screen.dart';
import 'package:MoneyTracker/screens/expense_sheet_settings_screen.dart';
import 'package:MoneyTracker/screens/frequent_expense_items_page.dart';
import 'package:MoneyTracker/screens/Spread_sheet_Selection_Screen.dart';
import 'package:MoneyTracker/services/services_module.dart';
import 'package:MoneyTracker/utils/expense_categories.dart';
import 'package:MoneyTracker/screens/spreadsheet_picker_screen.dart';
import 'package:MoneyTracker/widgets/share_spreadsheet_dialog.dart';
import '../features/ai_extractor/screens/ai_extractor_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class ExpenseTrackerPageStyle2 extends StatefulWidget {
  const ExpenseTrackerPageStyle2({super.key});

  @override
  State<ExpenseTrackerPageStyle2> createState() =>
      _ExpenseTrackerPageStyle2State();
}

class _ExpenseTrackerPageStyle2State extends State<ExpenseTrackerPageStyle2> {
  final FirebaseAuthService _authService = FirebaseAuthService();
  final GoogleSheetsService _sheetsService = GoogleSheetsService();
  final SpreadsheetStorageService _storageService = SpreadsheetStorageService();
  final FirebaseDatabaseService _firebaseDatabaseService =
      FirebaseDatabaseService();
  final GoogleDriveShareService _driveShareService = GoogleDriveShareService();

  final _formKey = GlobalKey<FormState>();
  final _priceController = TextEditingController();
  final _noteController = TextEditingController();
  final _commonSpreadsheetIdController = TextEditingController();
  final _personalSpreadsheetIdController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  String? _selectedCategory;
  String? _selectedPaidBy;
  bool _isOneTimePurchase = false;
  bool _isLoading = false;
  bool _isSignedIn = false;
  String? _userEmail;
  String? _verifiedCommonName;
  String? _verifiedPersonalName;
  ExpensePrimarySheet _primarySheet = ExpensePrimarySheet.shared;
  ExpenseSheetsUpdateMode _updateMode = ExpenseSheetsUpdateMode.both;
  bool _includeSecondarySheet = true;
  List<SpreadsheetInfo> _savedSpreadsheets = [];
  List<String> _personNames = [];
  bool _isLoadingPersonNames = false;
  List<Expense> _expensesToUpdate = [];
  bool _isLoadingExpenses = false;
  List<FrequentExpenseItem> _frequentItems = [];

  /// Label -> count from sheet; used for label suggestions (sorted by count).
  Map<String, int> _labelCountMap = {};
  bool _labelCountMapLoadTriggered = false;
  TextEditingController? _autocompleteLabelController;

  /// Which sheets receive the next submit (from primary, mode, and secondary checkbox).
  ({bool writesShared, bool writesPersonal}) _writesForSubmit() {
    if (_updateMode == ExpenseSheetsUpdateMode.single) {
      if (_primarySheet == ExpensePrimarySheet.shared) {
        return (writesShared: true, writesPersonal: false);
      }
      return (writesShared: false, writesPersonal: true);
    }
    if (!_includeSecondarySheet) {
      if (_primarySheet == ExpensePrimarySheet.shared) {
        return (writesShared: true, writesPersonal: false);
      }
      return (writesShared: false, writesPersonal: true);
    }
    return (writesShared: true, writesPersonal: true);
  }

  bool get _writesSharedThisSubmit => _writesForSubmit().writesShared;

  Future<void> _loadExpenseUiSettings() async {
    final email = _userEmail ?? _authService.userEmail;
    final primary = await ExpenseSettingsStorage.instance.getPrimarySheet(
      email,
    );
    final mode = await ExpenseSettingsStorage.instance.getUpdateMode(email);
    final secDefault = await ExpenseSettingsStorage.instance
        .getSecondaryCheckboxDefaultChecked(email);
    if (!mounted) return;
    setState(() {
      _primarySheet = primary;
      _updateMode = mode;
      if (mode == ExpenseSheetsUpdateMode.both) {
        _includeSecondarySheet = secDefault;
      }
    });
  }

  String _trackerStatusTitle() {
    final p = _primarySheet == ExpensePrimarySheet.shared
        ? 'Shared'
        : 'Personal';
    final m = _updateMode == ExpenseSheetsUpdateMode.both
        ? 'Both sheets'
        : 'Single sheet';
    return 'Primary: $p · $m';
  }

  List<SpreadsheetInfo> get _savedCommonSheets =>
      _savedSpreadsheets.where((s) => s.sheetKind != 'personal').toList();

  List<SpreadsheetInfo> get _savedPersonalSheets =>
      _savedSpreadsheets.where((s) => s.sheetKind == 'personal').toList();

  @override
  void initState() {
    super.initState();
    _loadExpenseUiSettings();
    _loadSavedSpreadsheets();
    _checkSignInStatus();

    // Rebuild when the user changes accent colours in App Settings.
    ThemePreferenceService.instance.addListener(_onThemeChanged);

    _authService.authStateChanges.listen((User? user) {
      if (mounted) {
        setState(() {
          _isSignedIn = user != null;
          _userEmail = user?.email;
        });
        if (user != null) {
          _loadExpenseUiSettings();
          _initializeSheetsApi();
        }
      }
    });
  }

  Future<void> _loadSavedSpreadsheets() async {
    try {
      await _storageService.migrateLegacyActiveSheetIdIfNeeded();
      final spreadsheets = await _storageService.getSavedSpreadsheets();
      final commonActive = await _storageService.getActiveCommonSheetId();
      final personalActive = await _storageService.getActivePersonalSheetId();

      SpreadsheetInfo? pickCommon() {
        if (commonActive != null && commonActive.isNotEmpty) {
          try {
            return spreadsheets.firstWhere((s) => s.id == commonActive);
          } catch (_) {}
        }
        try {
          return spreadsheets.firstWhere((s) => s.sheetKind != 'personal');
        } catch (_) {
          return spreadsheets.isNotEmpty ? spreadsheets.first : null;
        }
      }

      SpreadsheetInfo? pickPersonal() {
        if (personalActive != null && personalActive.isNotEmpty) {
          try {
            return spreadsheets.firstWhere((s) => s.id == personalActive);
          } catch (_) {}
        }
        try {
          return spreadsheets.firstWhere((s) => s.sheetKind == 'personal');
        } catch (_) {
          return null;
        }
      }

      final defaultCommon = pickCommon();
      final defaultPersonal = pickPersonal();

      setState(() {
        _savedSpreadsheets = spreadsheets;

        if (_commonSpreadsheetIdController.text.trim().isEmpty &&
            defaultCommon != null) {
          _commonSpreadsheetIdController.text = defaultCommon.id;
          _verifiedCommonName = defaultCommon.unavailable
              ? '⚠ Deleted / no access: ${defaultCommon.name ?? "Unnamed"}'
              : defaultCommon.name ?? 'Unnamed Spreadsheet';
        } else if (_commonSpreadsheetIdController.text.trim().isNotEmpty) {
          try {
            final m = spreadsheets.firstWhere(
              (s) => s.id == _commonSpreadsheetIdController.text.trim(),
            );
            _verifiedCommonName = m.unavailable
                ? '⚠ Deleted / no access: ${m.name ?? "Unnamed"}'
                : m.name ?? 'Unnamed Spreadsheet';
          } catch (_) {}
        }

        if (_personalSpreadsheetIdController.text.trim().isEmpty &&
            defaultPersonal != null) {
          _personalSpreadsheetIdController.text = defaultPersonal.id;
          _verifiedPersonalName = defaultPersonal.unavailable
              ? '⚠ Deleted / no access: ${defaultPersonal.name ?? "Unnamed"}'
              : defaultPersonal.name;
        } else if (_personalSpreadsheetIdController.text.trim().isNotEmpty) {
          try {
            final m = spreadsheets.firstWhere(
              (s) => s.id == _personalSpreadsheetIdController.text.trim(),
            );
            _verifiedPersonalName = m.unavailable
                ? '⚠ Deleted / no access: ${m.name ?? "Unnamed"}'
                : m.name;
          } catch (_) {}
        }
      });

      if (_isSignedIn) {
        final cid = _commonSpreadsheetIdController.text.trim();
        if (cid.isNotEmpty) {
          _sheetsService.setSpreadsheetId(cid);
          _loadPersonNames();
          _loadExpensesToUpdate();
          _loadFrequentItems();
        }
      }
    } catch (e) {
      debugPrint('Error loading saved spreadsheets: $e');
    }
  }

  Future<void> _checkSignInStatus() async {
    final user = _authService.currentUser;
    if (user != null) {
      setState(() {
        _isSignedIn = true;
        _userEmail = user.email;
      });
      await _loadExpenseUiSettings();
      await _initializeSheetsApi();
      _loadSpreadsheetNameIfExists();
      _loadPersonNames();
      _loadFrequentItems();
    }
  }

  Future<void> _loadFrequentItems() async {
    final spreadsheetId = _commonSpreadsheetIdController.text.trim();
    if (!_isSignedIn || spreadsheetId.isEmpty) {
      setState(() => _frequentItems = []);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'frequent_items_$spreadsheetId';

    // 1. Load from local cache instantly
    try {
      final cachedData = prefs.getString(cacheKey);
      if (cachedData != null) {
        final List<dynamic> decoded = json.decode(cachedData);
        final cachedItems = decoded
            .map(
              (itemMap) =>
                  FrequentExpenseItem.fromMap(itemMap['id'] ?? '', itemMap),
            )
            .where((e) => e.show)
            .toList();

        setState(() => _frequentItems = cachedItems);
      }
    } catch (e) {
      debugPrint('Error loading frequent items from cache: $e');
    }

    // 2. Fetch from Firebase and update cache
    try {
      final all = await _firebaseDatabaseService.getFrequentExpenseItems(
        spreadsheetId,
      );

      setState(() => _frequentItems = all.where((e) => e.show).toList());

      final itemsToCache = all.map((e) {
        final map = e.toMap();
        map['id'] = e.id;
        return map;
      }).toList();
      await prefs.setString(cacheKey, json.encode(itemsToCache));
    } catch (e) {
      debugPrint('Error loading frequent items: $e');
      if (_frequentItems.isEmpty) {
        setState(() => _frequentItems = []);
      }
    }
  }

  void _applyFrequentItem(FrequentExpenseItem item) {
    _autocompleteLabelController?.text = item.label;
    _priceController.text = item.price.toStringAsFixed(0);
    setState(() => _selectedCategory = item.category);
  }

  Future<void> _openFrequentExpenseItemsPage() async {
    final spreadsheetId = _commonSpreadsheetIdController.text.trim();
    if (spreadsheetId.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            FrequentExpenseItemsPage(spreadsheetId: spreadsheetId),
      ),
    );
    await _loadFrequentItems();
  }

  Future<void> _loadPersonNames() async {
    final spreadsheetId = _commonSpreadsheetIdController.text.trim();
    if (!_isSignedIn || spreadsheetId.isEmpty) {
      setState(() => _isLoadingPersonNames = false);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'person_names_$spreadsheetId';

    // 1. Load from local cache instantly
    try {
      final cachedData = prefs.getStringList(cacheKey);
      if (cachedData != null) {
        final uniqueNames = cachedData.toSet().toList()..sort();
        setState(() {
          _personNames = uniqueNames;
        });
        await _loadDefaultPaidByName();
      } else {
        setState(() => _isLoadingPersonNames = true);
      }
    } catch (e) {
      debugPrint('Error loading person names from cache: $e');
      setState(() => _isLoadingPersonNames = true);
    }

    // 2. Fetch from Firebase and update cache
    try {
      final names = await _firebaseDatabaseService.getPaidByPersons(
        spreadsheetId,
      );
      final uniqueNames = names.toSet().toList()..sort();

      setState(() {
        _personNames = uniqueNames;
        _isLoadingPersonNames = false;
      });

      await prefs.setStringList(cacheKey, uniqueNames);
      await _loadDefaultPaidByName();
    } catch (e) {
      debugPrint('Error loading person names: $e');
      setState(() => _isLoadingPersonNames = false);
    }
  }

  Future<void> _loadDefaultPaidByName() async {
    try {
      final defaultName = await _storageService.getDefaultPaidByName();
      if (defaultName != null && defaultName.isNotEmpty) {
        if (_personNames.contains(defaultName)) {
          setState(() => _selectedPaidBy = defaultName);
        } else {
          await _storageService.clearDefaultPaidByName();
          setState(() => _selectedPaidBy = null);
        }
      }
    } catch (e) {
      debugPrint('Error loading default paid by name: $e');
    }
  }

  Future<void> _loadSpreadsheetNameIfExists() async {
    final spreadsheetId = _commonSpreadsheetIdController.text.trim();
    if (spreadsheetId.isNotEmpty) {
      try {
        final saved = await _storageService.getSpreadsheet(spreadsheetId);
        if (saved != null && mounted) {
          setState(() {
            _verifiedCommonName = saved.name ?? 'Unnamed Spreadsheet';
          });
        }
      } catch (e) {
        debugPrint('Error loading spreadsheet name: $e');
      }
    }
    final pid = _personalSpreadsheetIdController.text.trim();
    if (pid.isNotEmpty) {
      try {
        final saved = await _storageService.getSpreadsheet(pid);
        if (saved != null && mounted) {
          setState(() {
            _verifiedPersonalName = saved.name;
          });
        }
      } catch (e) {
        debugPrint('Error loading personal spreadsheet name: $e');
      }
    }
  }

  Future<void> _initializeSheetsApi() async {
    try {
      final accessToken = await _authService.getAccessToken();
      if (accessToken != null) {
        await _sheetsService.initializeSheetsApiWithToken(accessToken);
      }
    } catch (e) {
      debugPrint('Error initializing Sheets API: $e');
    }
  }

  Future<void> _signIn() async {
    setState(() => _isLoading = true);
    try {
      final result = await _authService.signInWithGoogle();

      if (result.isSuccess && result.firebaseUser != null) {
        if (result.accessToken != null) {
          final sheetsApi = await _sheetsService.initializeSheetsApiWithToken(
            result.accessToken!,
          );
          if (sheetsApi != null) {
            setState(() {
              _isSignedIn = true;
              _userEmail = result.firebaseUser!.email;
            });
            _loadFrequentItems();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Signed in successfully!'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Sign in successful but failed to initialize Sheets API. Please try again.',
                  ),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Sign in successful but access token is missing. Please try again.',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } else if (result.isCancelled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Sign in cancelled'),
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Sign in failed: ${result.errorMessage ?? "Unknown error"}',
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      debugPrint('Unexpected error during sign in: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unexpected error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.logout, color: Colors.orange[700], size: 28),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Sign Out',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to sign out?',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No, Cancel', style: TextStyle(fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text(
              'Yes, Sign Out',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await _authService.signOut();
      setState(() {
        _isSignedIn = false;
        _userEmail = null;
        _verifiedCommonName = null;
        _verifiedPersonalName = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Signed out successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error signing out: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _openSpreadsheetPicker(SpreadsheetPickerPurpose purpose) async {
    if (!_isSignedIn) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please sign in first')));
      return;
    }
    final token = await _authService.getAccessToken();
    if (token == null || token.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not get Google token. Sign in again.'),
          ),
        );
      }
      return;
    }
    await _sheetsService.initializeSheetsApiWithToken(token);

    final r = await Navigator.push<SpreadsheetPickerResult>(
      context,
      MaterialPageRoute(
        builder: (ctx) => SpreadsheetPickerScreen(
          sheetsService: _sheetsService,
          purpose: purpose,
        ),
      ),
    );
    if (!mounted || r == null) return;
    if (purpose == SpreadsheetPickerPurpose.common) {
      await _storageService.setActiveCommonSheetId(r.spreadsheetId);
      setState(() {
        _commonSpreadsheetIdController.text = r.spreadsheetId;
        _verifiedCommonName = r.name ?? 'Spreadsheet';
      });
      _sheetsService.setSpreadsheetId(r.spreadsheetId);
      _loadPersonNames();
      _loadExpensesToUpdate();
      _loadFrequentItems();
    } else {
      await _storageService.setActivePersonalSheetId(r.spreadsheetId);
      setState(() {
        _personalSpreadsheetIdController.text = r.spreadsheetId;
        _verifiedPersonalName = r.name;
      });
    }
    // Refresh the dropdown list to include any newly saved sheets.
    if (mounted) await _loadSavedSpreadsheets();
  }

  Future<void> _showSpreadsheetDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Spreadsheets'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Shared (10 columns)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _commonSpreadsheetIdController,
                decoration: InputDecoration(
                  labelText: 'Shared spreadsheet ID',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.groups),
                  contentPadding: const EdgeInsets.all(2),
                  helperText: _verifiedCommonName != null
                      ? 'Sheet: $_verifiedCommonName'
                      : 'Verify to save',
                  helperMaxLines: 2,
                ),
                onChanged: (_) => setState(() => _verifiedCommonName = null),
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _isSignedIn
                        ? () async {
                            Navigator.pop(dialogContext);
                            await _openSpreadsheetPicker(
                              SpreadsheetPickerPurpose.common,
                            );
                          }
                        : null,
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Browse'),
                  ),
                  TextButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => _checkAndSaveSpreadsheet(forPersonal: false),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Verify'),
                  ),
                ],
              ),
              if (_savedCommonSheets.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: PopupMenuButton<String>(
                    tooltip: 'Saved shared sheets',
                    onSelected: (spreadsheetId) async {
                      final spreadsheet = _savedCommonSheets.firstWhere(
                        (s) => s.id == spreadsheetId,
                      );
                      await _storageService.setActiveCommonSheetId(
                        spreadsheet.id,
                      );
                      setState(() {
                        _commonSpreadsheetIdController.text = spreadsheet.id;
                        _verifiedCommonName =
                            spreadsheet.name ?? 'Unnamed Spreadsheet';
                      });
                      if (_isSignedIn) {
                        _sheetsService.setSpreadsheetId(spreadsheet.id);
                        _loadPersonNames();
                        _loadExpensesToUpdate();
                        _loadFrequentItems();
                      }
                    },
                    itemBuilder: (context) {
                      return _savedCommonSheets.map((spreadsheet) {
                        return PopupMenuItem<String>(
                          value: spreadsheet.id,
                          child: Text(
                            spreadsheet.name ?? spreadsheet.id,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList();
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Saved shared', style: TextStyle(fontSize: 13)),
                          Icon(Icons.arrow_drop_down),
                        ],
                      ),
                    ),
                  ),
                ),
              const Divider(height: 28),
              const Text(
                'Personal (10 columns)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _personalSpreadsheetIdController,
                decoration: InputDecoration(
                  labelText: 'Personal spreadsheet ID (optional)',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.person),
                  contentPadding: const EdgeInsets.all(2),
                  helperText: _verifiedPersonalName != null
                      ? 'Sheet: $_verifiedPersonalName'
                      : 'Owner only',
                  helperMaxLines: 2,
                ),
                onChanged: (_) => setState(() => _verifiedPersonalName = null),
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _isSignedIn
                        ? () async {
                            Navigator.pop(dialogContext);
                            await _openSpreadsheetPicker(
                              SpreadsheetPickerPurpose.personal,
                            );
                          }
                        : null,
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Browse'),
                  ),
                  TextButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => _checkAndSaveSpreadsheet(forPersonal: true),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Verify'),
                  ),
                ],
              ),
              if (_savedPersonalSheets.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: PopupMenuButton<String>(
                    tooltip: 'Saved personal sheets',
                    onSelected: (spreadsheetId) async {
                      final spreadsheet = _savedPersonalSheets.firstWhere(
                        (s) => s.id == spreadsheetId,
                      );
                      await _storageService.setActivePersonalSheetId(
                        spreadsheet.id,
                      );
                      setState(() {
                        _personalSpreadsheetIdController.text = spreadsheet.id;
                        _verifiedPersonalName = spreadsheet.name;
                      });
                    },
                    itemBuilder: (context) {
                      return _savedPersonalSheets.map((spreadsheet) {
                        return PopupMenuItem<String>(
                          value: spreadsheet.id,
                          child: Text(
                            spreadsheet.name ?? spreadsheet.id,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList();
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Saved personal',
                            style: TextStyle(fontSize: 13),
                          ),
                          Icon(Icons.arrow_drop_down),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkAndSaveSpreadsheet({required bool forPersonal}) async {
    final spreadsheetId = forPersonal
        ? _personalSpreadsheetIdController.text.trim()
        : _commonSpreadsheetIdController.text.trim();

    if (spreadsheetId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            forPersonal
                ? 'Please enter personal spreadsheet ID'
                : 'Please enter shared spreadsheet ID',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!_isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      _sheetsService.setSpreadsheetId(spreadsheetId);

      final exists = await _sheetsService.verifySpreadsheetExists(
        spreadsheetId,
      );

      if (!exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Spreadsheet not found or not accessible. Please check the ID and permissions.',
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      final layoutOk = forPersonal
          ? await _sheetsService.isCompatiblePersonalExpenseSheet(spreadsheetId)
          : await _sheetsService.isCompatibleExpenseSheet(spreadsheetId);
      if (!layoutOk) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                forPersonal
                    ? 'Sheet1 headers must match the personal format (10 columns).'
                    : 'Sheet1 headers must match the shared (10-column) format.',
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      String? spreadsheetName;
      try {
        spreadsheetName = await _sheetsService.getSpreadsheetName(
          spreadsheetId,
        );
      } catch (e) {
        debugPrint('Could not get spreadsheet name: $e');
      }

      final existing = await _storageService.getSpreadsheet(spreadsheetId);
      final isNew = existing == null;
      final kind = forPersonal
          ? SpreadsheetSheetKind.personal
          : SpreadsheetSheetKind.common;

      final spreadsheetInfo = SpreadsheetInfo(
        id: spreadsheetId,
        name: spreadsheetName,
        addedDate: existing?.addedDate ?? DateTime.now(),
        sheetKind: kind.dbValue,
      );

      await _storageService.saveSpreadsheet(spreadsheetInfo);
      if (forPersonal) {
        await _storageService.setActivePersonalSheetId(spreadsheetId);
      } else {
        await _storageService.setActiveCommonSheetId(spreadsheetId);
      }
      if (_userEmail != null && _userEmail!.isNotEmpty) {
        await _firebaseDatabaseService.registerSpreadsheetOwnership(
          ownerEmail: _userEmail!,
          spreadsheetId: spreadsheetId,
          displayName:
              spreadsheetName ?? spreadsheetInfo.name ?? 'Unnamed Spreadsheet',
          sheetKind: kind,
        );
      }
      if (!forPersonal) {
        _loadPersonNames();
      }
      setState(() {
        if (forPersonal) {
          _verifiedPersonalName = spreadsheetName ?? 'Unnamed Spreadsheet';
        } else {
          _verifiedCommonName = spreadsheetName ?? 'Unnamed Spreadsheet';
        }
      });

      await _loadSavedSpreadsheets();
      if (!forPersonal) {
        await _loadExpensesToUpdate();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isNew
                  ? (spreadsheetName != null
                        ? 'Spreadsheet "$spreadsheetName" verified and saved!'
                        : 'Spreadsheet verified and saved!')
                  : (spreadsheetName != null
                        ? 'Spreadsheet "$spreadsheetName" updated!'
                        : 'Spreadsheet updated!'),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Error checking/saving spreadsheet: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _autoSaveSpreadsheetIfNeeded(
    String spreadsheetId, {
    required bool personalLayout,
  }) async {
    try {
      final existing = await _storageService.getSpreadsheet(spreadsheetId);
      if (existing != null) return;

      final exists = await _sheetsService.verifySpreadsheetExists(
        spreadsheetId,
      );
      if (!exists) return;

      String? spreadsheetName;
      try {
        spreadsheetName = await _sheetsService.getSpreadsheetName(
          spreadsheetId,
        );
      } catch (e) {
        debugPrint('Could not get spreadsheet name: $e');
      }

      final kind = personalLayout
          ? SpreadsheetSheetKind.personal
          : SpreadsheetSheetKind.common;

      final spreadsheetInfo = SpreadsheetInfo(
        id: spreadsheetId,
        name: spreadsheetName,
        addedDate: DateTime.now(),
        sheetKind: kind.dbValue,
      );

      await _storageService.saveSpreadsheet(spreadsheetInfo);
      if (personalLayout) {
        await _storageService.setActivePersonalSheetId(spreadsheetId);
      } else {
        await _storageService.setActiveCommonSheetId(spreadsheetId);
      }
      if (_userEmail != null && _userEmail!.isNotEmpty) {
        await _firebaseDatabaseService.registerSpreadsheetOwnership(
          ownerEmail: _userEmail!,
          spreadsheetId: spreadsheetId,
          displayName:
              spreadsheetName ?? spreadsheetInfo.name ?? 'Unnamed Spreadsheet',
          sheetKind: kind,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              spreadsheetName != null
                  ? 'Spreadsheet "$spreadsheetName" saved automatically!'
                  : 'Spreadsheet saved automatically!',
            ),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Error auto-saving spreadsheet: $e');
    }
  }

  Future<void> _submitExpense() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_isSignedIn) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please sign in first')));
      return;
    }

    final commonId = _commonSpreadsheetIdController.text.trim();
    final personalId = _personalSpreadsheetIdController.text.trim();
    final w = _writesForSubmit();
    final writesShared = w.writesShared;
    final writesPersonal = w.writesPersonal;

    if (writesShared && commonId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set a shared spreadsheet ID.')),
      );
      return;
    }
    if (writesPersonal && personalId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set a personal spreadsheet ID.')),
      );
      return;
    }

    final userEmail = _userEmail?.trim() ?? '';
    if (userEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in again to add expenses.')),
      );
      return;
    }

    // The Sheets API write itself returns 403 if the user has no write access —
    // no need to guard here via Firebase meta (which may be missing for newly
    // created sheets).

    final primarySpreadsheetId = _primarySheet == ExpensePrimarySheet.shared
        ? commonId
        : personalId;
    _sheetsService.setSpreadsheetId(primarySpreadsheetId);

    final expenseId = const Uuid().v4();
    final expense = Expense(
      id: expenseId,
      label: _autocompleteLabelController?.text.trim() ?? '',
      price: double.parse(_priceController.text.trim()),
      category: _selectedCategory,
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
      expenseDate: _selectedDate,
      paidBy: writesShared ? _selectedPaidBy : null,
      isOneTimePurchase: _isOneTimePurchase,
      addedByEmail: FirebaseAuth.instance.currentUser?.email,
      linkedHomeSpreadsheetId: commonId.isEmpty ? null : commonId,
    );

    _autocompleteLabelController?.clear();
    _priceController.clear();
    _noteController.clear();
    setState(() {
      _selectedDate = DateTime.now();
      _selectedCategory = null;
      _selectedPaidBy = null;
      _isOneTimePurchase = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Expense added! Syncing to sheet...'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }

    await _uploadExpenseToSheet(
      expense,
      commonId: commonId,
      personalId: personalId,
      writeShared: writesShared,
      writePersonal: writesPersonal,
    );
  }

  Future<void> _uploadExpenseToSheet(
    Expense expense, {
    required String commonId,
    required String personalId,
    required bool writeShared,
    required bool writePersonal,
  }) async {
    assert(writeShared || writePersonal);
    final primaryShared = _primarySheet == ExpensePrimarySheet.shared;

    Future<bool> addCommon() async {
      try {
        return await _sheetsService.addExpenseTo(
          commonId,
          expense,
          personalLayout: false,
        );
      } catch (e, st) {
        debugPrint('add common: $e\n$st');
        return false;
      }
    }

    Future<bool> addPersonal() async {
      try {
        return await _sheetsService.addExpenseTo(
          personalId,
          expense,
          personalLayout: true,
        );
      } catch (e, st) {
        debugPrint('add personal: $e\n$st');
        return false;
      }
    }

    try {
      var commonOk = !writeShared;
      var personalOk = !writePersonal;

      if (primaryShared) {
        if (writeShared) commonOk = await addCommon();
        if (writePersonal) personalOk = await addPersonal();
      } else {
        if (writePersonal) personalOk = await addPersonal();
        if (writeShared) commonOk = await addCommon();
      }

      final allOk =
          (!writeShared || commonOk) && (!writePersonal || personalOk);

      if (allOk) {
        if (writeShared) {
          await _autoSaveSpreadsheetIfNeeded(commonId, personalLayout: false);
          _loadPersonNames();
          _loadExpensesToUpdate();
        }
        if (writePersonal) {
          await _autoSaveSpreadsheetIfNeeded(personalId, personalLayout: true);
        }
        if (mounted) {
          String msg;
          if (writeShared && writePersonal) {
            msg = 'Expense synced to shared and personal sheets.';
          } else if (writeShared) {
            msg = 'Expense synced to shared sheet.';
          } else {
            msg = 'Expense synced to personal sheet.';
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      if (writeShared && writePersonal) {
        if (commonOk && !personalOk) {
          await _autoSaveSpreadsheetIfNeeded(commonId, personalLayout: false);
          _loadPersonNames();
          _loadExpensesToUpdate();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Saved to shared sheet only; personal sheet sync failed.',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 6),
                action: SnackBarAction(
                  label: 'Retry',
                  textColor: Colors.white,
                  onPressed: () => _uploadExpenseToSheet(
                    expense,
                    commonId: commonId,
                    personalId: personalId,
                    writeShared: writeShared,
                    writePersonal: writePersonal,
                  ),
                ),
              ),
            );
          }
        } else if (!commonOk && personalOk) {
          await _autoSaveSpreadsheetIfNeeded(personalId, personalLayout: true);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Saved to personal sheet only; shared sheet sync failed.',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 6),
                action: SnackBarAction(
                  label: 'Retry',
                  textColor: Colors.white,
                  onPressed: () => _uploadExpenseToSheet(
                    expense,
                    commonId: commonId,
                    personalId: personalId,
                    writeShared: writeShared,
                    writePersonal: writePersonal,
                  ),
                ),
              ),
            );
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Could not sync to the selected sheet(s). Check connection and IDs.',
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: () => _uploadExpenseToSheet(
                  expense,
                  commonId: commonId,
                  personalId: personalId,
                  writeShared: writeShared,
                  writePersonal: writePersonal,
                ),
              ),
            ),
          );
        }
      } else if (writeShared && !commonOk && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Failed to sync expense. Please check connection.',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _uploadExpenseToSheet(
                expense,
                commonId: commonId,
                personalId: personalId,
                writeShared: writeShared,
                writePersonal: writePersonal,
              ),
            ),
          ),
        );
      } else if (writePersonal && !personalOk && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Failed to sync expense. Please check connection.',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _uploadExpenseToSheet(
                expense,
                commonId: commonId,
                personalId: personalId,
                writeShared: writeShared,
                writePersonal: writePersonal,
              ),
            ),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Error uploading expense: $e\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error syncing expense: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _saveDefaultPaidByName(String name) async {
    try {
      await _storageService.saveDefaultPaidByName(name);
    } catch (e) {
      debugPrint('Error saving default paid by name: $e');
    }
  }

  Future<void> _showUserInfoDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.account_circle, size: 28),
            SizedBox(width: 12),
            Text('Account Info'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Signed in as:',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _userEmail ?? 'Unknown',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String? _getCategoryFromLabelAndNotes(Expense expense) {
    final label = expense.label.toLowerCase();
    final note = (expense.note ?? '').toLowerCase();
    final combinedText = '$label $note';

    if (combinedText.contains('milk')) return 'Milk';
    if (combinedText.contains('vegetable')) return 'Vegetables';
    if (combinedText.contains('petrol')) return 'Petrol';
    return null;
  }

  Future<void> _loadExpensesToUpdate() async {
    if (!_isSignedIn || _commonSpreadsheetIdController.text.trim().isEmpty) {
      setState(() {
        _expensesToUpdate = [];
        _labelCountMap = {};
        _labelCountMapLoadTriggered = false;
      });
      return;
    }

    setState(() => _isLoadingExpenses = true);

    try {
      final cid = _commonSpreadsheetIdController.text.trim();
      final expenses = await _sheetsService.getExpensesFor(
        cid,
        personalLayout: false,
      );
      // Build label -> count for suggestions (from all expenses)
      final labelCountMap = <String, int>{};
      for (final e in expenses) {
        final label = e.label.trim();
        if (label.isEmpty) continue;
        labelCountMap[label] = (labelCountMap[label] ?? 0) + 1;
      }
      final expensesToUpdate = expenses.where((expense) {
        final newCategory = _getCategoryFromLabelAndNotes(expense);
        return newCategory != null && newCategory != expense.category;
      }).toList();

      setState(() {
        _expensesToUpdate = expensesToUpdate;
        _labelCountMap = labelCountMap;
        _isLoadingExpenses = false;
      });
    } catch (e) {
      debugPrint('Error loading expenses: $e');
      setState(() {
        _expensesToUpdate = [];
        _labelCountMap = {};
        _isLoadingExpenses = false;
      });
    }
  }

  Future<void> _updateExpenseCategory(Expense expense) async {
    final newCategory = _getCategoryFromLabelAndNotes(expense);
    if (newCategory == null || newCategory == expense.category) return;

    setState(() => _isLoading = true);

    try {
      final updatedExpense = Expense(
        id: expense.id,
        label: expense.label,
        price: expense.price,
        category: newCategory,
        note: expense.note,
        expenseDate: expense.expenseDate,
        timestamp: expense.timestamp,
        paidBy: expense.paidBy,
        isOneTimePurchase: expense.isOneTimePurchase,
        addedByEmail: expense.addedByEmail,
      );

      final cid = _commonSpreadsheetIdController.text.trim();
      await _sheetsService.updateExpenseFor(
        cid,
        updatedExpense,
        personalLayout: false,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Updated "${expense.label}" to category "$newCategory"',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      await _loadExpensesToUpdate();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateAllCategories() async {
    if (_expensesToUpdate.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      int updatedCount = 0;

      for (var expense in _expensesToUpdate) {
        final newCategory = _getCategoryFromLabelAndNotes(expense);

        if (newCategory != null && newCategory != expense.category) {
          final updatedExpense = Expense(
            id: expense.id,
            label: expense.label,
            price: expense.price,
            category: newCategory,
            note: expense.note,
            expenseDate: expense.expenseDate,
            timestamp: expense.timestamp,
            paidBy: expense.paidBy,
            isOneTimePurchase: expense.isOneTimePurchase,
            addedByEmail: expense.addedByEmail,
          );

          final cid = _commonSpreadsheetIdController.text.trim();
          await _sheetsService.updateExpenseFor(
            cid,
            updatedExpense,
            personalLayout: false,
          );
          updatedCount++;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully updated $updatedCount expense(s)'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      await _loadExpensesToUpdate();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showAddPersonDialog() async {
    final nameController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Person Name'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Person Name',
            hintText: 'Enter name',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.all(2),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context, name);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      if (_userEmail == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User email not available. Please sign in again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      setState(() => _isLoading = true);
      try {
        final sharedId = _commonSpreadsheetIdController.text.trim();
        if (sharedId.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Set a shared spreadsheet ID to store paid-by names.',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
        final success = await _firebaseDatabaseService.addPaidByPerson(
          sharedId,
          result,
        );
        if (success) {
          await _loadPersonNames();
          setState(() => _selectedPaidBy = result);
          await _saveDefaultPaidByName(result);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Person "$result" added successfully!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Person "$result" already exists!'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('Error adding person name: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error adding person: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    ThemePreferenceService.instance.removeListener(_onThemeChanged);
    // _autocompleteLabelController is owned by Autocomplete, do not dispose
    _priceController.dispose();
    _noteController.dispose();
    _commonSpreadsheetIdController.dispose();
    _personalSpreadsheetIdController.dispose();
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openAppSettings() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (context) => const AppSettingsScreen()),
    );
  }

  Future<void> _openExpenseSheetSettings() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => const ExpenseSheetSettingsScreen(),
      ),
    );
    if (!mounted) return;
    await _loadExpenseUiSettings();
    await _loadSavedSpreadsheets();
  }

  Future<void> _showShareSpreadsheetDialog() async {
    final spreadsheetId = _commonSpreadsheetIdController.text.trim();

    if (spreadsheetId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Set a shared spreadsheet ID to use sharing.'),
        ),
      );
      return;
    }

    if (_userEmail == null || _userEmail!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to share a spreadsheet.')),
      );
      return;
    }

    if (await _firebaseDatabaseService.isSpreadsheetPersonal(spreadsheetId)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sharing applies to shared sheets only. Switch to your shared sheet ID.',
            ),
          ),
        );
      }
      return;
    }

    await ShareSpreadsheetDialog.show(
      context,
      spreadsheetId: spreadsheetId,
      fallbackSheetName: _verifiedCommonName ?? 'Shared spreadsheet',
      ownerEmail: _userEmail!,
      firebaseDatabaseService: _firebaseDatabaseService,
      driveShareService: _driveShareService,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sharedPrimary = _primarySheet == ExpensePrimarySheet.shared;
    final colorSvc = ThemePreferenceService.instance;
    final accentColor = sharedPrimary
        ? colorSvc.sharedColor
        : colorSvc.personalColor;
    final appBarBg = accentColor;
    const appBarFg = Colors.white;
    final tintAlpha = isDark ? 0.14 : 0.08;
    final tint = accentColor.withValues(alpha: tintAlpha);
    final scaffoldBg = Color.alphaBlend(tint, theme.colorScheme.surface);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text(
          _trackerStatusTitle(),
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: appBarFg,
          ),
          maxLines: 2,
        ),
        backgroundColor: appBarBg,
        foregroundColor: appBarFg,
        iconTheme: const IconThemeData(color: appBarFg),
        actionsIconTheme: const IconThemeData(color: appBarFg),

        actions: [
          IconButton(
            icon: const Icon(Icons.palette_outlined),
            onPressed: _openAppSettings,
            tooltip: 'App settings',
          ),
          if (_isSignedIn) ...[
            IconButton(
              icon: const Icon(Icons.check_circle),
              onPressed: _showSpreadsheetDialog,
              tooltip: 'Spreadsheet - Verify & Save',
            ),
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Account'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.auto_awesome),
                          title: const Text('AI Extract'),
                          subtitle: const Text('Extract from screenshots'),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AIExtractorScreen(
                                  commonSpreadsheetId:
                                      _commonSpreadsheetIdController.text
                                          .trim(),
                                  personalSpreadsheetId:
                                      _personalSpreadsheetIdController.text
                                          .trim(),
                                  userEmail: _userEmail,
                                  defaultPaidBy: _selectedPaidBy,
                                ),
                              ),
                            );
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.settings),
                          title: const Text('Expense sheet settings'),
                          onTap: () {
                            Navigator.pop(context);
                            _openExpenseSheetSettings();
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.share),
                          title: const Text('Share Spreadsheet'),
                          onTap: () {
                            Navigator.pop(context);
                            _showShareSpreadsheetDialog();
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.email),
                          title: const Text('Account Info'),
                          onTap: () {
                            Navigator.pop(context);
                            _showUserInfoDialog();
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.logout),
                          title: const Text('Sign Out'),
                          onTap: () {
                            Navigator.pop(context);
                            _signOut();
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
              tooltip: 'Account',
            ),
          ],
        ],
      ),
      endDrawer: _isSignedIn
          ? Drawer(
              child: ListView(
                padding: const EdgeInsets.only(top: 48),
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.palette_outlined),
                    label: const Text('App settings'),
                    onPressed: () {
                      Navigator.pop(context);
                      _openAppSettings();
                    },
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.email),
                    label: const Text('Account Info'),
                    onPressed: () {
                      Navigator.pop(context);
                      _showUserInfoDialog();
                    },
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign Out'),
                    onPressed: () {
                      Navigator.pop(context);
                      _signOut();
                    },
                  ),
                ],
              ),
            )
          : null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_isSignedIn)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Text(
                          'Sign in with Google to continue',
                          style: TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _isLoading ? null : _signIn,
                          icon: const Icon(Icons.login),
                          label: const Text('Sign in with Google'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              if (_isSignedIn) ...[
                // Load label suggestions from sheet when form is shown and map is empty (once)
                if (_labelCountMap.isEmpty &&
                    _commonSpreadsheetIdController.text.trim().isNotEmpty &&
                    !_labelCountMapLoadTriggered)
                  Builder(
                    builder: (context) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted &&
                            _labelCountMap.isEmpty &&
                            _commonSpreadsheetIdController.text
                                .trim()
                                .isNotEmpty &&
                            !_labelCountMapLoadTriggered) {
                          _labelCountMapLoadTriggered = true;
                          _loadExpensesToUpdate();
                        }
                      });
                      return const SizedBox.shrink();
                    },
                  ),
                Row(
                  children: [
                    //     const Text(
                    //   'Add Expense',
                    //   style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    // ),
                    OutlinedButton.icon(
                      onPressed: () {
                        final spreadsheetId = _commonSpreadsheetIdController
                            .text
                            .trim();
                        if (spreadsheetId.isEmpty) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                EventsPage(spreadsheetId: spreadsheetId),
                          ),
                        );
                      },
                      icon: const Icon(Icons.star, size: 18),
                      label: const Text('Events'),
                    ),
                    Spacer(),
                    OutlinedButton.icon(
                      onPressed: _openFrequentExpenseItemsPage,
                      icon: const Icon(Icons.star, size: 18),
                      label: const Text('Frequents'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                // Frequent items: button + scrollable row
                if (_frequentItems.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Tap to fill',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _frequentItems.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final item = _frequentItems[index];
                        return ActionChip(
                          label: Text(
                            '${item.label} • ₹${item.price.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          onPressed: () => _applyFrequentItem(item),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ] else
                  const SizedBox(height: 8),

                // Label (with suggestions from sheet) and Price
                Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Autocomplete<String>(
                        displayStringForOption: (s) => s,
                        optionsBuilder: (TextEditingValue value) {
                          final q = value.text.trim().toLowerCase();
                          List<String> keys = q.isEmpty
                              ? _labelCountMap.keys.toList()
                              : _labelCountMap.keys
                                    .where((l) => l.toLowerCase().contains(q))
                                    .toList();
                          keys.sort(
                            (a, b) => (_labelCountMap[b] ?? 0).compareTo(
                              _labelCountMap[a] ?? 0,
                            ),
                          );
                          return keys;
                        },
                        onSelected: (String value) {
                          _autocompleteLabelController?.text = value;
                        },
                        fieldViewBuilder:
                            (context, controller, focusNode, onFieldSubmitted) {
                              _autocompleteLabelController ??= controller;
                              return TextFormField(
                                controller: controller,
                                focusNode: focusNode,
                                decoration: const InputDecoration(
                                  labelText: 'Label *',
                                  hintText: 'e.g., Groceries, Lunch, etc.',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.label),
                                  contentPadding: EdgeInsets.all(2),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter a label';
                                  }
                                  return null;
                                },
                              );
                            },
                        // Use default options view so overlay is positioned correctly below field
                        optionsMaxHeight: 200,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _priceController,
                        decoration: const InputDecoration(
                          labelText: 'Price *',
                          hintText: '0',
                          border: OutlineInputBorder(),
                          // prefixIcon: Icon(Icons.attach_money),
                          contentPadding: EdgeInsets.all(2),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: false,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a price';
                          }
                          final price = double.tryParse(value);
                          if (price == null || price <= 0) {
                            return 'Please enter a valid price';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Divider(), const SizedBox(height: 6),
                // Category: wrap, 3 rows max, horizontal scroll
                const Text(
                  'Category (Optional)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 80,
                  width: double.infinity,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Wrap(
                      direction: Axis.vertical,
                      spacing: 0,
                      runSpacing: 4,
                      alignment: WrapAlignment.start,
                      runAlignment: WrapAlignment.start,
                      crossAxisAlignment: WrapCrossAlignment.start,
                      children: [
                        ...ExpenseCategories.categories.map((category) {
                          return FilterChip(
                            pressElevation: 0,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.all(2),
                            label: Text(
                              category,
                              style: TextStyle(fontSize: 12),
                            ),
                            selected: _selectedCategory == category,
                            onSelected: (selected) {
                              setState(() {
                                _selectedCategory = selected ? category : null;
                              });
                            },
                          );
                        }),
                        FilterChip(
                          pressElevation: 0,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.all(2),
                          label: const Text(
                            'None',
                            style: TextStyle(fontSize: 12),
                          ),
                          selected: _selectedCategory == null,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) _selectedCategory = null;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Divider(),
                // Date (small "30 Jan") + One time switch in one row
                Row(
                  children: [
                    const SizedBox(width: 16),
                    const Text('One Time', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 8),
                    Switch(
                      value: _isOneTimePurchase,
                      onChanged: (value) {
                        setState(() => _isOneTimePurchase = value);
                      },
                    ),
                    Spacer(),
                    InkWell(
                      onTap: _selectDate,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          DateFormat('d MMM').format(_selectedDate),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Note (Optional)
                TextFormField(
                  controller: _noteController,
                  decoration: const InputDecoration(
                    labelText: 'Note (Optional)',
                    hintText: 'Additional notes...',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.note),
                    contentPadding: EdgeInsets.all(12),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                if (_updateMode == ExpenseSheetsUpdateMode.both)
                  CheckboxListTile(
                    value: _includeSecondarySheet,
                    onChanged: (v) {
                      setState(() => _includeSecondarySheet = v ?? true);
                    },
                    title: Text(
                      _primarySheet == ExpensePrimarySheet.shared
                          ? 'Also add to personal sheet'
                          : 'Also add to shared sheet',
                    ),
                    subtitle: const Text(
                      'Same expense ID when both sheets are updated.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                if (_updateMode == ExpenseSheetsUpdateMode.both)
                  const SizedBox(height: 8),

                // Paid By: shared sheet column only
                if (_writesSharedThisSubmit)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Paid By (Optional)',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (_isLoadingPersonNames)
                              const LinearProgressIndicator()
                            else
                              Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: [
                                  ..._personNames.map((name) {
                                    return FilterChip(
                                      pressElevation: 0,
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.all(2),
                                      label: Text(
                                        name,
                                        style: TextStyle(fontSize: 12),
                                      ),
                                      selected: _selectedPaidBy == name,
                                      onSelected: (selected) {
                                        setState(() {
                                          _selectedPaidBy = selected
                                              ? name
                                              : null;
                                          if (selected && name.isNotEmpty) {
                                            _saveDefaultPaidByName(name);
                                          } else {
                                            _storageService
                                                .clearDefaultPaidByName();
                                          }
                                        });
                                      },
                                    );
                                  }),
                                  FilterChip(
                                    pressElevation: 0,
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.all(2),
                                    label: const Text(
                                      'None',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    selected: _selectedPaidBy == null,
                                    onSelected: (selected) {
                                      setState(() {
                                        if (selected) {
                                          _selectedPaidBy = null;
                                          _storageService
                                              .clearDefaultPaidByName();
                                        }
                                      });
                                    },
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: _isLoading ? null : _showAddPersonDialog,
                        tooltip: 'Add new person',
                        style: IconButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                        ),
                      ),
                    ],
                  ),
                if (_writesSharedThisSubmit) const SizedBox(height: 24),

                // Submit Button
                ElevatedButton(
                  onPressed: _isLoading ? null : _submitExpense,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text(
                          'Add Expense to Sheet',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
                const SizedBox(height: 16),

                // My Spreadsheets Button
                ElevatedButton.icon(
                  onPressed: _isLoading
                      ? null
                      : () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SpreadsheetSelectionScreen(
                                sheetsService: _sheetsService,
                              ),
                            ),
                          );
                          // Reload saved sheets so the dropdown reflects any
                          // sheet selected (including Drive-shared by others).
                          if (mounted) await _loadSavedSpreadsheets();
                        },
                  icon: const Icon(Icons.table_chart),
                  label: const Text('My Spreadsheets'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
