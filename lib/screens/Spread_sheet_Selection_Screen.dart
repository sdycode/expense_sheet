import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../services/spreadsheet_storage_service.dart';
import '../services/google_sheets_service.dart';
import '../services/firebase_auth_service.dart';
import '../services/firebase_database_service.dart';
import 'expenses_list_screen.dart';
import 'spreadsheet_picker_screen.dart';

class SpreadsheetSelectionScreen extends StatefulWidget {
  final GoogleSheetsService sheetsService;

  const SpreadsheetSelectionScreen({super.key, required this.sheetsService});

  @override
  State<SpreadsheetSelectionScreen> createState() =>
      _SpreadsheetSelectionScreenState();
}

class _SpreadsheetSelectionScreenState
    extends State<SpreadsheetSelectionScreen> {
  final SpreadsheetStorageService _storageService = SpreadsheetStorageService();
  final FirebaseAuthService _authService = FirebaseAuthService();
  List<SpreadsheetInfo> _spreadsheets = [];
  bool _isLoading = true;
  String? _activeSpreadsheetId;

  @override
  void initState() {
    super.initState();
    _loadSpreadsheets();
  }

  Future<void> _loadSpreadsheets() async {
    setState(() => _isLoading = true);
    try {
      final active = await _storageService.getActiveSpreadsheetId();
      final localSpreadsheets = await _storageService.getSavedSpreadsheets();
      List<SpreadsheetInfo> sharedSpreadsheetsInfo = [];

      final currentUserEmail = FirebaseAuthService().currentUser?.email;
      if (currentUserEmail != null) {
        final sharedSheets = await FirebaseDatabaseService()
            .getSharedSpreadsheets(currentUserEmail);
        for (var sheet in sharedSheets) {
          sharedSpreadsheetsInfo.add(
            SpreadsheetInfo(
              id: sheet['id']!,
              name: '${sheet['name']} (Shared)',
              addedDate:
                  DateTime.now(), // Approximate since we only need string formatting
            ),
          );
        }
      }

      // Combine and remove duplicates by ID
      final Map<String, SpreadsheetInfo> uniqueSheets = {};
      for (var sheet in localSpreadsheets) {
        uniqueSheets[sheet.id] = sheet;
      }
      for (var sheet in sharedSpreadsheetsInfo) {
        uniqueSheets[sheet.id] = sheet;
      }

      setState(() {
        _spreadsheets = uniqueSheets.values.toList();
        _activeSpreadsheetId = active;
      });
    } catch (e) {
      debugPrint('Error loading spreadsheets: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading spreadsheets: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteSpreadsheet(SpreadsheetInfo spreadsheet) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange[700], size: 28),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Remove Spreadsheet',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to remove this spreadsheet from your saved list?',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Name: ${spreadsheet.name ?? "Unnamed Spreadsheet"}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ID: ${spreadsheet.id}',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Note: This will only remove it from your saved list. The actual spreadsheet will not be deleted.',
              style: TextStyle(
                color: Colors.orange[700],
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No, Cancel', style: TextStyle(fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text(
              'Yes, Remove',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _storageService.deleteSpreadsheet(spreadsheet.id);
        _loadSpreadsheets();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Spreadsheet removed'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _navigateToExpenses(SpreadsheetInfo spreadsheet) async {
    await _storageService.setActiveSpreadsheetId(spreadsheet.id);
    if (!mounted) return;
    setState(() => _activeSpreadsheetId = spreadsheet.id);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExpensesListScreen(
          sheetsService: widget.sheetsService,
          spreadsheetId: spreadsheet.id,
        ),
      ),
    );
  }

  Future<void> _openDrivePicker() async {
    final token = await _authService.getAccessToken();
    if (token == null || token.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sign in from the expense screen, then try again.'),
          ),
        );
      }
      return;
    }
    await widget.sheetsService.initializeSheetsApiWithToken(token);

    final r = await Navigator.push<SpreadsheetPickerResult>(
      context,
      MaterialPageRoute(
        builder: (ctx) =>
            SpreadsheetPickerScreen(sheetsService: widget.sheetsService),
      ),
    );
    if (!mounted || r == null) return;
    await _storageService.setActiveSpreadsheetId(r.spreadsheetId);
    await _loadSpreadsheets();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Selected: ${r.name ?? r.spreadsheetId}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Spreadsheets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_outlined),
            onPressed: _openDrivePicker,
            tooltip: 'Browse Google Drive',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSpreadsheets,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _spreadsheets.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.table_chart, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No spreadsheets saved yet',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Use Browse Google Drive (cloud icon) or add an ID on the expense screen',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.8,
              ),
              itemCount: _spreadsheets.length,
              itemBuilder: (context, index) {
                final spreadsheet = _spreadsheets[index];
                return _SpreadsheetCard(
                  spreadsheet: spreadsheet,
                  index: index,
                  isActive: spreadsheet.id == _activeSpreadsheetId,
                  onTap: () => _navigateToExpenses(spreadsheet),
                  onDelete: () => {},
                );
              },
            ),
    );
  }
}

class _SpreadsheetCard extends StatelessWidget {
  final SpreadsheetInfo spreadsheet;
  final int index;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SpreadsheetCard({
    required this.spreadsheet,
    required this.index,
    this.isActive = false,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = spreadsheet.name ?? 'Spreadsheet ${index + 1}';
    final dateAdded = DateFormat('MMM dd, yyyy').format(spreadsheet.addedDate);
    final theme = Theme.of(context);

    return Card(
      elevation: isActive ? 4 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isActive ? theme.colorScheme.primary : Colors.transparent,
          width: isActive ? 2 : 0,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Icon(
                      Icons.table_chart,
                      size: 32,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  if (isActive)
                    Icon(
                      Icons.check_circle,
                      color: theme.colorScheme.primary,
                      size: 22,
                    ),
                  if (false)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: onDelete,
                      tooltip: 'Delete',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                displayName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                dateAdded,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const Spacer(),
              Row(
                children: [
                  Text(
                    'ID: ${spreadsheet.id.substring(0, 8)}...',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[500],
                      fontFamily: 'monospace',
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey[400],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
