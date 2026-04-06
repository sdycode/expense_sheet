import 'package:flutter/material.dart';
import '../../../services/google_sheets_service.dart';
import '../models/ai_extraction_result.dart';
import '../widgets/extracted_card.dart';

/// Review screen showing all extracted transactions.
///
/// Users can edit fields, toggle individual results, and save selected
/// transactions to the connected Google Sheets.
class AIResultsScreen extends StatefulWidget {
  final List<AIExtractionResult> results;
  final String commonSpreadsheetId;
  final String? personalSpreadsheetId;
  final String userEmail;
  final String defaultPaidBy;

  const AIResultsScreen({
    super.key,
    required this.results,
    required this.commonSpreadsheetId,
    this.personalSpreadsheetId,
    required this.userEmail,
    required this.defaultPaidBy,
  });

  @override
  State<AIResultsScreen> createState() => _AIResultsScreenState();
}

class _AIResultsScreenState extends State<AIResultsScreen> {
  late List<AIExtractionResult> _results;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _results = widget.results;
  }

  int get _selectedCount => _results.where((r) => r.isSelected).length;

  void _selectAll() {
    for (final r in _results) {
      r.isSelected = true;
    }
    setState(() {});
  }

  void _deselectAll() {
    for (final r in _results) {
      r.isSelected = false;
    }
    setState(() {});
  }

  Future<void> _saveSelected() async {
    final selected = _results.where((r) => r.isSelected).toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No transactions selected')));
      return;
    }

    setState(() => _isSaving = true);

    final sheetsService = GoogleSheetsService();
    int successCount = 0;
    int failCount = 0;

    for (final item in selected) {
      final expense = item.toExpense(
        paidBy: widget.defaultPaidBy,
        addedByEmail: widget.userEmail,
      );

      try {
        // Save to shared sheet.
        if (widget.commonSpreadsheetId.isNotEmpty) {
          await sheetsService.addExpenseTo(
            widget.commonSpreadsheetId,
            expense,
            personalLayout: false,
          );
        }

        // Also save to personal sheet if configured.
        if (widget.personalSpreadsheetId != null &&
            widget.personalSpreadsheetId!.isNotEmpty) {
          await sheetsService.addExpenseTo(
            widget.personalSpreadsheetId!,
            expense,
            personalLayout: true,
          );
        }

        successCount++;
      } catch (e) {
        debugPrint('Error saving extracted expense: $e');
        failCount++;
      }
    }

    setState(() => _isSaving = false);

    if (!mounted) return;

    if (failCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$successCount transaction(s) saved!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$successCount saved, $failCount failed. Check connection and retry.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Review (${_results.length})'),
        actions: [
          TextButton(
            onPressed: _selectedCount == _results.length
                ? _deselectAll
                : _selectAll,
            child: Text(
              _selectedCount == _results.length ? 'Deselect All' : 'Select All',
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Summary bar ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            ),
            child: Text(
              '$_selectedCount of ${_results.length} selected · '
              'Total: ₹${_calculateTotal()}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          // ── Cards list ──
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _results.length,
              itemBuilder: (context, index) {
                return ExtractedCard(
                  result: _results[index],
                  index: index,
                  onToggle: () {
                    setState(() {
                      _results[index].isSelected = !_results[index].isSelected;
                    });
                  },
                  onChanged: () => setState(() {}),
                );
              },
            ),
          ),

          // ── Save button ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                onPressed: _isSaving || _selectedCount == 0
                    ? null
                    : _saveSelected,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(
                  _isSaving ? 'Saving…' : 'Save $_selectedCount Transaction(s)',
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _calculateTotal() {
    double total = 0;
    for (final r in _results.where((r) => r.isSelected)) {
      total += double.tryParse(r.price) ?? 0;
    }
    return total.toStringAsFixed(0);
  }
}
