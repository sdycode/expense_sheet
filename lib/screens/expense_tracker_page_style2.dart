import 'package:MoneyTracker/models/expense.dart';
import 'package:MoneyTracker/models/frequent_expense_item.dart';
import 'package:MoneyTracker/models/spreadsheet_sheet_kind.dart';
import 'package:MoneyTracker/screens/events_page.dart';
import 'package:MoneyTracker/screens/expense_sheet_settings_screen.dart';
import 'package:MoneyTracker/screens/frequent_expense_items_page.dart';
import 'package:MoneyTracker/screens/Spread_sheet_Selection_Screen.dart';
import 'package:MoneyTracker/services/services_module.dart';
import 'package:MoneyTracker/utils/expense_categories.dart';
import 'package:MoneyTracker/screens/spreadsheet_picker_screen.dart';
import 'package:MoneyTracker/widgets/share_spreadsheet_dialog.dart';
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
  bool _showHomePersonalToggle = true;
  bool _includeHomeSheet = true;
  bool _defaultIncludeHomeWhenHidden = true;
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

  bool get _effectiveIncludeHome =>
      _showHomePersonalToggle ? _includeHomeSheet : _defaultIncludeHomeWhenHidden;

  Future<void> _loadExpenseUiSettings() async {
    final show =
        await ExpenseSettingsStorage.instance.getShowHomePersonalToggle();
    final def = await ExpenseSettingsStorage.instance
        .getDefaultIncludeHomeWhenHidden();
    if (!mounted) return;
    setState(() {
      _showHomePersonalToggle = show;
      _defaultIncludeHomeWhenHidden = def;
      if (!show) _includeHomeSheet = def;
    });
  }

  List<SpreadsheetInfo> get _savedCommonSheets => _savedSpreadsheets
      .where((s) => s.sheetKind != 'personal')
      .toList();

  List<SpreadsheetInfo> get _savedPersonalSheets => _savedSpreadsheets
      .where((s) => s.sheetKind == 'personal')
      .toList();

  @override
  void initState() {
    super.initState();
    _loadExpenseUiSettings();
    _loadSavedSpreadsheets();
    _checkSignInStatus();

    _authService.authStateChanges.listen((User? user) {
      if (mounted) {
        setState(() {
          _isSignedIn = user != null;
          _userEmail = user?.email;
        });
        if (user != null) {
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
          _verifiedCommonName =
              defaultCommon.name ?? 'Unnamed Spreadsheet';
        } else if (_commonSpreadsheetIdController.text.trim().isNotEmpty) {
          try {
            final m = spreadsheets.firstWhere(
              (s) => s.id == _commonSpreadsheetIdController.text.trim(),
            );
            _verifiedCommonName = m.name ?? 'Unnamed Spreadsheet';
          } catch (_) {}
        }

        if (_personalSpreadsheetIdController.text.trim().isEmpty &&
            defaultPersonal != null) {
          _personalSpreadsheetIdController.text = defaultPersonal.id;
          _verifiedPersonalName = defaultPersonal.name;
        } else if (_personalSpreadsheetIdController.text.trim().isNotEmpty) {
          try {
            final m = spreadsheets.firstWhere(
              (s) => s.id == _personalSpreadsheetIdController.text.trim(),
            );
            _verifiedPersonalName = m.name;
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
            const SnackBar(
              content: Text('Sign in cancelled'),
              backgroundColor: Colors.grey,
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in first')),
      );
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
                'Home / shared (10 columns)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _commonSpreadsheetIdController,
                decoration: InputDecoration(
                  labelText: 'Home spreadsheet ID',
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
                    tooltip: 'Saved home sheets',
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
                          Text('Saved home', style: TextStyle(fontSize: 13)),
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
                          Text('Saved personal', style: TextStyle(fontSize: 13)),
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
                : 'Please enter home spreadsheet ID',
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
          ? await _sheetsService.isCompatiblePersonalExpenseSheet(
              spreadsheetId,
            )
          : await _sheetsService.isCompatibleExpenseSheet(spreadsheetId);
      if (!layoutOk) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                forPersonal
                    ? 'Sheet1 headers must match the personal format (10 columns).'
                    : 'Sheet1 headers must match the home (10-column) format.',
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
    final includeHome = _effectiveIncludeHome;

    if (includeHome) {
      if (commonId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Set a home (shared) spreadsheet ID.'),
          ),
        );
        return;
      }
      if (personalId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Set a personal spreadsheet ID to save to both sheets.',
            ),
          ),
        );
        return;
      }
    } else {
      if (personalId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Set a personal spreadsheet ID.')),
        );
        return;
      }
    }

    final userEmail = _userEmail?.trim() ?? '';
    if (userEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in again to add expenses.')),
      );
      return;
    }

    final canPersonal = await _firebaseDatabaseService.userCanWritePersonalSheet(
      personalId,
      userEmail,
    );
    if (!canPersonal) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You can only write to a personal sheet you own.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    _sheetsService.setSpreadsheetId(includeHome ? commonId : personalId);

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
      paidBy: includeHome ? _selectedPaidBy : null,
      isOneTimePurchase: _isOneTimePurchase,
      addedByEmail: FirebaseAuth.instance.currentUser?.email,
      linkedHomeSpreadsheetId:
          commonId.isEmpty ? null : commonId,
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
      includeHome: includeHome,
    );
  }

  Future<void> _uploadExpenseToSheet(
    Expense expense, {
    required String commonId,
    required String personalId,
    required bool includeHome,
  }) async {
    try {
      if (includeHome) {
        var commonOk = false;
        var personalOk = false;
        try {
          commonOk = await _sheetsService.addExpenseTo(
            commonId,
            expense,
            personalLayout: false,
          );
        } catch (e, st) {
          debugPrint('add common: $e\n$st');
        }
        try {
          personalOk = await _sheetsService.addExpenseTo(
            personalId,
            expense,
            personalLayout: true,
          );
        } catch (e, st) {
          debugPrint('add personal: $e\n$st');
        }

        if (commonOk && personalOk) {
          await _autoSaveSpreadsheetIfNeeded(commonId, personalLayout: false);
          await _autoSaveSpreadsheetIfNeeded(personalId, personalLayout: true);
          _loadPersonNames();
          _loadExpensesToUpdate();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Expense synced to home and personal sheets.'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else if (commonOk && !personalOk) {
          await _autoSaveSpreadsheetIfNeeded(commonId, personalLayout: false);
          _loadPersonNames();
          _loadExpensesToUpdate();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Saved to home sheet only; personal sheet sync failed.',
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
                    includeHome: true,
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
                  'Saved to personal sheet only; home sheet sync failed.',
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
                    includeHome: true,
                  ),
                ),
              ),
            );
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Could not sync to either sheet. Check connection and IDs.',
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
                  includeHome: true,
                ),
              ),
            ),
          );
        }
      } else {
        try {
          final ok = await _sheetsService.addExpenseTo(
            personalId,
            expense,
            personalLayout: true,
          );
          if (ok) {
            await _autoSaveSpreadsheetIfNeeded(
              personalId,
              personalLayout: true,
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Expense synced to personal sheet.'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 2),
                ),
              );
            }
          } else if (mounted) {
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
                    includeHome: false,
                  ),
                ),
              ),
            );
          }
        } catch (e) {
          debugPrint('personal-only upload: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error: ${e.toString()}'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'Retry',
                  textColor: Colors.white,
                  onPressed: () => _uploadExpenseToSheet(
                    expense,
                    commonId: commonId,
                    personalId: personalId,
                    includeHome: false,
                  ),
                ),
              ),
            );
          }
        }
      }
    } catch (e, stackTrace) {
      debugPrint('Error uploading expense: $e');
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
            const Text(
              'Signed in as:',
              style: TextStyle(fontSize: 12, color: Colors.grey),
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
        final homeId = _commonSpreadsheetIdController.text.trim();
        if (homeId.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Set a home spreadsheet ID to store paid-by names.',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
        final success = await _firebaseDatabaseService.addPaidByPerson(
          homeId,
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
    // _autocompleteLabelController is owned by Autocomplete, do not dispose
    _priceController.dispose();
    _noteController.dispose();
    _commonSpreadsheetIdController.dispose();
    _personalSpreadsheetIdController.dispose();
    super.dispose();
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
          content: Text('Set a home (shared) spreadsheet ID to use sharing.'),
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
              'Sharing applies to home sheets only. Switch to your home sheet ID.',
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Tracker'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,

        actions: [
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
                            _commonSpreadsheetIdController.text.trim().isNotEmpty &&
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
                        final spreadsheetId = _commonSpreadsheetIdController.text
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
                  const Text(
                    'Tap to fill',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
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
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          DateFormat('d MMM').format(_selectedDate),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
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

                if (_showHomePersonalToggle)
                  CheckboxListTile(
                    value: _includeHomeSheet,
                    onChanged: (v) {
                      setState(() => _includeHomeSheet = v ?? true);
                    },
                    title: const Text('Also add to home / shared sheet'),
                    subtitle: const Text(
                      'Unchecked: personal sheet only (same expense ID when both are used).',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                if (_showHomePersonalToggle) const SizedBox(height: 8),

                // Paid By: wrap + add button (home sheet column only)
                if (_effectiveIncludeHome)
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
                        backgroundColor: Colors.blue[50],
                      ),
                    ),
                  ],
                ),
                if (_effectiveIncludeHome) const SizedBox(height: 24),

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
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SpreadsheetSelectionScreen(
                                sheetsService: _sheetsService,
                              ),
                            ),
                          );
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
