import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'models/expense.dart';
import 'services/firebase_auth_service.dart';
import 'services/google_sheets_service.dart';
import 'services/spreadsheet_storage_service.dart';
import 'screens/spreadsheet_selection_screen.dart';
import 'utils/expense_categories.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('Firebase initialized successfully');
  } catch (e) {
    debugPrint('Error initializing Firebase: $e');
    debugPrint('Make sure you have:');
    debugPrint('1. Added google-services.json to android/app/');
    debugPrint('2. Updated firebase_options.dart with your Firebase config');
    debugPrint('3. OR run: flutterfire configure');
    // Continue anyway - Firebase might work if configured correctly
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Expense Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        dropdownMenuTheme: const DropdownMenuThemeData(
          textStyle: TextStyle(color: Colors.black),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          labelStyle: TextStyle(color: Colors.black87),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.black),
          bodyMedium: TextStyle(color: Colors.black),
          bodySmall: TextStyle(color: Colors.black),
        ),
      ),
      home: const ExpenseTrackerPage(),
    );
  }
}

class ExpenseTrackerPage extends StatefulWidget {
  const ExpenseTrackerPage({super.key});

  @override
  State<ExpenseTrackerPage> createState() => _ExpenseTrackerPageState();
}

class _ExpenseTrackerPageState extends State<ExpenseTrackerPage> {
  final FirebaseAuthService _authService = FirebaseAuthService();
  final GoogleSheetsService _sheetsService = GoogleSheetsService();
  final SpreadsheetStorageService _storageService = SpreadsheetStorageService();

  final _formKey = GlobalKey<FormState>();
  final _labelController = TextEditingController();
  final _priceController = TextEditingController();
  final _noteController = TextEditingController();
  final _spreadsheetIdController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  String? _selectedCategory;
  String? _selectedPaidBy;
  bool _isLoading = false;
  bool _isSignedIn = false;
  String? _userEmail;
  String? _verifiedSpreadsheetName;
  List<SpreadsheetInfo> _savedSpreadsheets = [];
  String? _selectedSpreadsheetId;
  List<String> _personNames = [];
  bool _isLoadingPersonNames = false;

  @override
  void initState() {
    super.initState();
    _loadSavedSpreadsheets();
    _checkSignInStatus();

    // Listen to auth state changes
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
        // Auto-fill first spreadsheet ID if available and field is empty
        if (spreadsheets.isNotEmpty) {
          final firstSpreadsheet = spreadsheets.first;
          // Only auto-fill if field is empty
          if (_spreadsheetIdController.text.trim().isEmpty) {
            _spreadsheetIdController.text = firstSpreadsheet.id;
            _selectedSpreadsheetId = firstSpreadsheet.id;
            _verifiedSpreadsheetName =
                firstSpreadsheet.name ?? 'Unnamed Spreadsheet';
            // Set spreadsheet ID in service and load person names
            if (_isSignedIn) {
              _sheetsService.setSpreadsheetId(firstSpreadsheet.id);
              _loadPersonNames();
            }
          } else {
            // If field has value, check if it matches a saved spreadsheet
            final currentId = _spreadsheetIdController.text.trim();
            try {
              final matching = spreadsheets.firstWhere(
                (s) => s.id == currentId,
              );
              _selectedSpreadsheetId = matching.id;
              _verifiedSpreadsheetName = matching.name ?? 'Unnamed Spreadsheet';
              // Set spreadsheet ID in service and load person names
              if (_isSignedIn) {
                _sheetsService.setSpreadsheetId(currentId);
                _loadPersonNames();
              }
            } catch (e) {
              // Current ID doesn't match any saved spreadsheet
            }
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
      // Load saved spreadsheet name if ID is already entered
      _loadSpreadsheetNameIfExists();
      // Load person names
      _loadPersonNames();
    }
  }

  Future<void> _loadPersonNames() async {
    if (!_isSignedIn || _spreadsheetIdController.text.trim().isEmpty) {
      setState(() {
        _isLoadingPersonNames = false;
      });
      return;
    }
    setState(() {
      _isLoadingPersonNames = true;
    });
    try {
      final names = await _sheetsService.getPersonNames();
      debugPrint('Person names: $names');
      // Remove duplicates
      final uniqueNames = names.toSet().toList()..sort();
      setState(() {
        _personNames = uniqueNames;
        _isLoadingPersonNames = false;
      });

      // Load and verify default paid by name
      await _loadDefaultPaidByName();
    } catch (e) {
      debugPrint('Error loading person names: $e');
      setState(() {
        _isLoadingPersonNames = false;
      });
    }
  }

  Future<void> _loadDefaultPaidByName() async {
    try {
      final defaultName = await _storageService.getDefaultPaidByName();
      if (defaultName != null && defaultName.isNotEmpty) {
        // Check if the default name exists in the sheet
        if (_personNames.contains(defaultName)) {
          // Name exists in sheet, set it as selected
          setState(() {
            _selectedPaidBy = defaultName;
          });
          debugPrint('Default paid by name loaded: $defaultName');
        } else {
          // Name doesn't exist in sheet, clear it from storage
          debugPrint(
            'Default paid by name "$defaultName" not found in sheet, clearing default',
          );
          await _storageService.clearDefaultPaidByName();
          setState(() {
            _selectedPaidBy = null;
          });
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
      debugPrint('ExpenseTrackerPage: Starting Firebase Google Sign-In...');
      final result = await _authService.signInWithGoogle();

      if (result.isSuccess && result.firebaseUser != null) {
        debugPrint(
          'ExpenseTrackerPage: Firebase sign in successful, initializing Sheets API...',
        );

        // Initialize Sheets API with access token
        if (result.accessToken != null) {
          final sheetsApi = await _sheetsService.initializeSheetsApiWithToken(
            result.accessToken!,
          );
          if (sheetsApi != null) {
            setState(() {
              _isSignedIn = true;
              _userEmail = result.firebaseUser!.email;
            });
            debugPrint(
              'ExpenseTrackerPage: Sheets API initialized, user signed in',
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Signed in successfully!'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          } else {
            debugPrint('ExpenseTrackerPage: Failed to initialize Sheets API');
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
          debugPrint('ExpenseTrackerPage: Access token is null');
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
        debugPrint('ExpenseTrackerPage: Sign in cancelled by user');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sign in cancelled'),
              backgroundColor: Colors.grey,
            ),
          );
        }
      } else {
        debugPrint(
          'ExpenseTrackerPage: Sign in failed: ${result.errorMessage}',
        );
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
      debugPrint('ExpenseTrackerPage: Unexpected error during sign in: $e');
      debugPrint('ExpenseTrackerPage: Stack trace: $stackTrace');
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
    // Show confirmation dialog
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

    // If user confirmed, proceed with sign out
    if (confirm != true) {
      return;
    }

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
      debugPrint('Error signing out: $e');
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
      setState(() {
        _selectedDate = picked;
      });
    }
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
      // Set spreadsheet ID temporarily to verify
      _sheetsService.setSpreadsheetId(spreadsheetId);

      // Verify spreadsheet exists
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

      // Get spreadsheet name
      String? spreadsheetName;
      try {
        spreadsheetName = await _sheetsService.getSpreadsheetName(
          spreadsheetId,
        );
      } catch (e) {
        debugPrint('Could not get spreadsheet name: $e');
      }

      // Check if already saved
      final existing = await _storageService.getSpreadsheet(spreadsheetId);
      final isNew = existing == null;

      // Save to SharedPreferences
      final spreadsheetInfo = SpreadsheetInfo(
        id: spreadsheetId,
        name: spreadsheetName,
        addedDate: existing?.addedDate ?? DateTime.now(),
      );

      await _storageService.saveSpreadsheet(spreadsheetInfo);
      _loadPersonNames();
      // Update UI to show spreadsheet name
      setState(() {
        _verifiedSpreadsheetName = spreadsheetName ?? 'Unnamed Spreadsheet';
        _selectedSpreadsheetId = spreadsheetId;
      });

      // Reload saved spreadsheets to update the list
      await _loadSavedSpreadsheets();

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

      debugPrint(
        'Spreadsheet ${isNew ? "saved" : "updated"}: ${spreadsheetName ?? spreadsheetId}',
      );
    } catch (e, stackTrace) {
      debugPrint('Error checking/saving spreadsheet: $e');
      debugPrint('Stack trace: $stackTrace');
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
      // Check if already saved
      final existing = await _storageService.getSpreadsheet(spreadsheetId);
      if (existing != null) {
        debugPrint('Spreadsheet already saved, skipping auto-save');
        return;
      }

      debugPrint('Auto-saving spreadsheet: $spreadsheetId');

      // Verify spreadsheet exists (it should since we just used it)
      final exists = await _sheetsService.verifySpreadsheetExists(
        spreadsheetId,
      );

      if (!exists) {
        debugPrint('Spreadsheet does not exist, skipping auto-save');
        return;
      }

      // Get spreadsheet name
      String? spreadsheetName;
      try {
        spreadsheetName = await _sheetsService.getSpreadsheetName(
          spreadsheetId,
        );
      } catch (e) {
        debugPrint('Could not get spreadsheet name: $e');
      }

      // Save to SharedPreferences
      final spreadsheetInfo = SpreadsheetInfo(
        id: spreadsheetId,
        name: spreadsheetName,
        addedDate: DateTime.now(),
      );

      await _storageService.saveSpreadsheet(spreadsheetInfo);

      debugPrint('Spreadsheet auto-saved: ${spreadsheetName ?? spreadsheetId}');

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
      debugPrint('Stack trace: $stackTrace');
      // Don't show error to user, just log it
    }
  }

  Future<void> _submitExpense() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

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

    // Set spreadsheet ID
    _sheetsService.setSpreadsheetId(spreadsheetId);

    // Create expense object
    final expense = Expense(
      label: _labelController.text.trim(),
      price: double.parse(_priceController.text.trim()),
      category: _selectedCategory,
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
      expenseDate: _selectedDate,
      paidBy: _selectedPaidBy,
    );

    // Clear form immediately for better UX
    _labelController.clear();
    _priceController.clear();
    _noteController.clear();
    setState(() {
      _selectedDate = DateTime.now();
      _selectedCategory = null;
      _selectedPaidBy = null;
    });

    // Show success message immediately
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Expense added! Syncing to sheet...'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }

    // Upload to Google Sheets in background
    _uploadExpenseToSheet(expense, spreadsheetId);
  }

  Future<void> _uploadExpenseToSheet(
    Expense expense,
    String spreadsheetId,
  ) async {
    try {
      debugPrint(
        'ExpenseTrackerPage: Uploading expense to sheet: ${expense.toMap()}',
      );
      final success = await _sheetsService.addExpense(expense);

      if (success) {
        debugPrint(
          'ExpenseTrackerPage: Expense uploaded successfully to Google Sheets',
        );

        // Auto-save spreadsheet ID if not already saved
        await _autoSaveSpreadsheetIfNeeded(spreadsheetId);

        // Reload person names in case a new one was added
        _loadPersonNames();

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
        debugPrint(
          'ExpenseTrackerPage: Failed to upload expense (success returned false)',
        );
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
      debugPrint('ExpenseTrackerPage: Error uploading expense: $e');
      debugPrint('ExpenseTrackerPage: Stack trace: $stackTrace');
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
      debugPrint('Default paid by name saved: $name');
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
      setState(() => _isLoading = true);
      try {
        final success = await _sheetsService.addPersonName(result);
        if (success) {
          // Reload person names
          await _loadPersonNames();
          // Set the newly added name as selected and save as default
          setState(() {
            _selectedPaidBy = result;
          });
          // Save as default
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
    _labelController.dispose();
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
              icon: const Icon(Icons.email),
              onPressed: _showUserInfoDialog,
              tooltip: 'View Account Info',
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _signOut,
              tooltip: 'Sign Out',
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Sign In Section
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

              // Spreadsheet ID Input
              if (_isSignedIn) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _spreadsheetIdController,
                        decoration: InputDecoration(
                          labelText: 'Google Spreadsheet ID *',
                          hintText: 'Enter your Google Sheet ID',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.table_chart),
                          helperText: _verifiedSpreadsheetName != null
                              ? 'Sheet: $_verifiedSpreadsheetName'
                              : 'Click check to verify and save',
                          helperMaxLines: 2,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter Spreadsheet ID';
                          }
                          return null;
                        },
                        onChanged: (value) {
                          // Clear verified name when ID changes
                          if (_verifiedSpreadsheetName != null) {
                            setState(() {
                              _verifiedSpreadsheetName = null;
                              _selectedSpreadsheetId = null;
                            });
                          }
                        },
                      ),
                    ),
                    if (_savedSpreadsheets.isNotEmpty) ...[
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
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _checkAndSaveSpreadsheet,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Icon(Icons.check_circle),
                      label: const Text('Check'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Expense Form
              if (_isSignedIn) ...[
                const Text(
                  'Add Expense',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // Label and Price in one row
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _labelController,
                        decoration: const InputDecoration(
                          labelText: 'Label *',
                          hintText: 'e.g., Groceries, Lunch, etc.',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.label),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a label';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _priceController,
                        decoration: const InputDecoration(
                          labelText: 'Price *',
                          hintText: '0.00',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.attach_money),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
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
                const SizedBox(height: 16),

                // Category and Date in one row
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedCategory,
                        decoration: const InputDecoration(
                          labelText: 'Category (Optional)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.category, size: 20),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        style: const TextStyle(fontSize: 14),
                        isExpanded: true,
                        selectedItemBuilder: (BuildContext context) {
                          return [
                            const Text(
                              'None',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.black,
                              ),
                            ),
                            ...ExpenseCategories.categories.map((category) {
                              return Text(
                                category,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black,
                                ),
                                overflow: TextOverflow.visible,
                              );
                            }),
                          ];
                        },
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text(
                              'None',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.black,
                              ),
                            ),
                          ),
                          ...ExpenseCategories.categories.map((category) {
                            return DropdownMenuItem(
                              value: category,
                              child: Text(
                                category,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black,
                                ),
                                overflow: TextOverflow.visible,
                              ),
                            );
                          }),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedCategory = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: InkWell(
                        onTap: _selectDate,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Expense Date *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.calendar_today, size: 20),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  DateFormat(
                                    'yyyy-MM-dd',
                                  ).format(_selectedDate),
                                  style: const TextStyle(fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.arrow_drop_down, size: 20),
                            ],
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
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),

                // Paid By (Optional)
                Row(
                  children: [
                    Expanded(
                      child: _isLoadingPersonNames
                          ? const LinearProgressIndicator()
                          : DropdownButtonFormField<String>(
                              value: _selectedPaidBy,
                              decoration: const InputDecoration(
                                labelText: 'Paid By (Optional)',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.person, size: 20),
                              ),
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black,
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text(
                                    'None',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                                ..._personNames.map((name) {
                                  return DropdownMenuItem(
                                    value: name,
                                    child: Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.black,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  _selectedPaidBy = value;
                                });
                                // Save as default if a name is selected
                                if (value != null && value.isNotEmpty) {
                                  _saveDefaultPaidByName(value);
                                } else {
                                  // Clear default if "None" is selected
                                  _storageService.clearDefaultPaidByName();
                                }
                              },
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
                // View Spreadsheets Button
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
