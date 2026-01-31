import 'package:expensesheet/models/expense.dart';
import 'package:expensesheet/models/frequent_expense_item.dart';
import 'package:expensesheet/screens/events_page.dart';
import 'package:expensesheet/screens/frequent_expense_items_page.dart';
import 'package:expensesheet/screens/121212.dart';
import 'package:expensesheet/services/services_module.dart';
import 'package:expensesheet/utils/expense_categories.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

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

  final _formKey = GlobalKey<FormState>();
  final _priceController = TextEditingController();
  final _noteController = TextEditingController();
  final _spreadsheetIdController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  String? _selectedCategory;
  String? _selectedPaidBy;
  bool _isOneTimePurchase = false;
  bool _isLoading = false;
  bool _isSignedIn = false;
  String? _userEmail;
  String? _verifiedSpreadsheetName;
  List<SpreadsheetInfo> _savedSpreadsheets = [];
  String? _selectedSpreadsheetId;
  List<String> _personNames = [];
  bool _isLoadingPersonNames = false;
  List<Expense> _expensesToUpdate = [];
  bool _isLoadingExpenses = false;
  List<FrequentExpenseItem> _frequentItems = [];

  /// Label -> count from sheet; used for label suggestions (sorted by count).
  Map<String, int> _labelCountMap = {};
  bool _labelCountMapLoadTriggered = false;
  TextEditingController? _autocompleteLabelController;

  @override
  void initState() {
    super.initState();
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
      final spreadsheets = await _storageService.getSavedSpreadsheets();
      setState(() {
        _savedSpreadsheets = spreadsheets;
        if (spreadsheets.isNotEmpty) {
          final firstSpreadsheet = spreadsheets.first;
          if (_spreadsheetIdController.text.trim().isEmpty) {
            _spreadsheetIdController.text = firstSpreadsheet.id;
            _selectedSpreadsheetId = firstSpreadsheet.id;
            _verifiedSpreadsheetName =
                firstSpreadsheet.name ?? 'Unnamed Spreadsheet';
            if (_isSignedIn) {
              _sheetsService.setSpreadsheetId(firstSpreadsheet.id);
              _loadPersonNames();
              _loadExpensesToUpdate();
            }
          } else {
            final currentId = _spreadsheetIdController.text.trim();
            try {
              final matching = spreadsheets.firstWhere(
                (s) => s.id == currentId,
              );
              _selectedSpreadsheetId = matching.id;
              _verifiedSpreadsheetName = matching.name ?? 'Unnamed Spreadsheet';
              if (_isSignedIn) {
                _sheetsService.setSpreadsheetId(currentId);
                _loadPersonNames();
                _loadExpensesToUpdate();
              }
            } catch (e) {}
          }
        }
      });
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
    if (!_isSignedIn || _userEmail == null) {
      setState(() => _frequentItems = []);
      return;
    }
    try {
      final all = await _firebaseDatabaseService.getFrequentExpenseItems(
        _userEmail!,
      );
      setState(() => _frequentItems = all.where((e) => e.show).toList());
    } catch (e) {
      debugPrint('Error loading frequent items: $e');
      setState(() => _frequentItems = []);
    }
  }

  void _applyFrequentItem(FrequentExpenseItem item) {
    _autocompleteLabelController?.text = item.label;
    _priceController.text = item.price.toStringAsFixed(0);
    setState(() => _selectedCategory = item.category);
  }

  Future<void> _openFrequentExpenseItemsPage() async {
    if (_userEmail == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FrequentExpenseItemsPage(userEmail: _userEmail!),
      ),
    );
    await _loadFrequentItems();
  }

  Future<void> _loadPersonNames() async {
    if (!_isSignedIn || _userEmail == null) {
      setState(() => _isLoadingPersonNames = false);
      return;
    }
    setState(() => _isLoadingPersonNames = true);
    try {
      final names = await _firebaseDatabaseService.getPaidByPersons(
        _userEmail!,
      );
      final uniqueNames = names.toSet().toList()..sort();
      setState(() {
        _personNames = uniqueNames;
        _isLoadingPersonNames = false;
      });
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
    final spreadsheetId = _spreadsheetIdController.text.trim();
    if (spreadsheetId.isNotEmpty) {
      try {
        final saved = await _storageService.getSpreadsheet(spreadsheetId);
        if (saved != null && mounted) {
          setState(() {
            _verifiedSpreadsheetName = saved.name ?? 'Unnamed Spreadsheet';
          });
        }
      } catch (e) {
        debugPrint('Error loading spreadsheet name: $e');
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
        _verifiedSpreadsheetName = null;
        _selectedSpreadsheetId = null;
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

  Future<void> _showSpreadsheetDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Spreadsheet'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _spreadsheetIdController,
                decoration: InputDecoration(
                  labelText: 'Google Spreadsheet ID *',
                  hintText: 'Enter your Google Sheet ID',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.table_chart),
                  contentPadding: const EdgeInsets.all(2),
                  helperText: _verifiedSpreadsheetName != null
                      ? 'Sheet: $_verifiedSpreadsheetName'
                      : 'Click Check to verify and save',
                  helperMaxLines: 2,
                ),
                onChanged: (value) {
                  if (_verifiedSpreadsheetName != null) {
                    setState(() {
                      _verifiedSpreadsheetName = null;
                      _selectedSpreadsheetId = null;
                    });
                  }
                },
              ),
              if (_savedSpreadsheets.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Saved:', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      tooltip: 'Select saved spreadsheet',
                      onSelected: (spreadsheetId) {
                        final spreadsheet = _savedSpreadsheets.firstWhere(
                          (s) => s.id == spreadsheetId,
                        );
                        setState(() {
                          _spreadsheetIdController.text = spreadsheet.id;
                          _selectedSpreadsheetId = spreadsheet.id;
                          _verifiedSpreadsheetName =
                              spreadsheet.name ?? 'Unnamed Spreadsheet';
                        });
                        if (_isSignedIn) {
                          _sheetsService.setSpreadsheetId(spreadsheet.id);
                          _loadPersonNames();
                          _loadExpensesToUpdate();
                        }
                      },
                      itemBuilder: (context) {
                        return _savedSpreadsheets.map((spreadsheet) {
                          return PopupMenuItem<String>(
                            value: spreadsheet.id,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  spreadsheet.name ?? 'Unnamed Spreadsheet',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  spreadsheet.id,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[600],
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.arrow_drop_down, size: 24),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: _isLoading
                ? null
                : () async {
                    if (_spreadsheetIdController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter Spreadsheet ID'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }
                    await _checkAndSaveSpreadsheet();
                    try {
                      if (mounted) Navigator.pop(context);
                    } catch (e) {}
                  },
            icon: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle),
            label: const Text('Check'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkAndSaveSpreadsheet() async {
    final spreadsheetId = _spreadsheetIdController.text.trim();

    if (spreadsheetId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter Spreadsheet ID'),
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

      final spreadsheetInfo = SpreadsheetInfo(
        id: spreadsheetId,
        name: spreadsheetName,
        addedDate: existing?.addedDate ?? DateTime.now(),
      );

      await _storageService.saveSpreadsheet(spreadsheetInfo);
      _loadPersonNames();
      setState(() {
        _verifiedSpreadsheetName = spreadsheetName ?? 'Unnamed Spreadsheet';
        _selectedSpreadsheetId = spreadsheetId;
      });

      await _loadSavedSpreadsheets();
      await _loadExpensesToUpdate();

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

  Future<void> _autoSaveSpreadsheetIfNeeded(String spreadsheetId) async {
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

      final spreadsheetInfo = SpreadsheetInfo(
        id: spreadsheetId,
        name: spreadsheetName,
        addedDate: DateTime.now(),
      );

      await _storageService.saveSpreadsheet(spreadsheetInfo);

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

    if (_spreadsheetIdController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter Spreadsheet ID')),
      );
      return;
    }

    final spreadsheetId = _spreadsheetIdController.text.trim();

    _sheetsService.setSpreadsheetId(spreadsheetId);

    final expense = Expense(
      label: _autocompleteLabelController?.text.trim() ?? '',
      price: double.parse(_priceController.text.trim()),
      category: _selectedCategory,
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
      expenseDate: _selectedDate,
      paidBy: _selectedPaidBy,
      isOneTimePurchase: _isOneTimePurchase,
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

    _uploadExpenseToSheet(expense, spreadsheetId);
  }

  Future<void> _uploadExpenseToSheet(
    Expense expense,
    String spreadsheetId,
  ) async {
    try {
      final success = await _sheetsService.addExpense(expense);

      if (success) {
        await _autoSaveSpreadsheetIfNeeded(spreadsheetId);
        _loadPersonNames();
        _loadExpensesToUpdate(); // refresh label suggestions

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Expense synced to sheet successfully!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Failed to sync expense to sheet. Please check your connection and try again.',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: () => _uploadExpenseToSheet(expense, spreadsheetId),
              ),
            ),
          );
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
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _uploadExpenseToSheet(expense, spreadsheetId),
            ),
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
    if (!_isSignedIn || _spreadsheetIdController.text.trim().isEmpty) {
      setState(() {
        _expensesToUpdate = [];
        _labelCountMap = {};
        _labelCountMapLoadTriggered = false;
      });
      return;
    }

    setState(() => _isLoadingExpenses = true);

    try {
      final expenses = await _sheetsService.getExpenses();
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
      );

      await _sheetsService.updateExpense(updatedExpense);

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
          );

          await _sheetsService.updateExpense(updatedExpense);
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
        final success = await _firebaseDatabaseService.addPaidByPerson(
          _userEmail!,
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
    _spreadsheetIdController.dispose();
    super.dispose();
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
                    _spreadsheetIdController.text.trim().isNotEmpty &&
                    !_labelCountMapLoadTriggered)
                  Builder(
                    builder: (context) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted &&
                            _labelCountMap.isEmpty &&
                            _spreadsheetIdController.text.trim().isNotEmpty &&
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
                        if (_userEmail == null) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                EventsPage(userEmail: _userEmail!),
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

                // Paid By: wrap + add button
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
                const SizedBox(height: 24),

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
