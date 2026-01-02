import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:zoom_tap_animation/zoom_tap_animation.dart';
import '../models/expense.dart';
import '../services/google_sheets_service.dart';
import '../utils/expense_categories.dart';
import 'edit_expense_screen.dart';

class ExpensesListScreen extends StatefulWidget {
  final GoogleSheetsService sheetsService;
  final String spreadsheetId;

  const ExpensesListScreen({
    super.key,
    required this.sheetsService,
    required this.spreadsheetId,
  });

  @override
  State<ExpensesListScreen> createState() => _ExpensesListScreenState();
}

class _ExpensesListScreenState extends State<ExpensesListScreen> {
  List<Expense> _allExpenses = [];
  List<Expense> _filteredExpenses = [];
  bool _isLoading = false;
  String? _selectedCategory;
  DateTime? _selectedMonth;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    widget.sheetsService.setSpreadsheetId(widget.spreadsheetId);
    _loadExpenses();
  }

  Future<void> _loadExpenses() async {
    setState(() => _isLoading = true);
    try {
      final expenses = await widget.sheetsService.getExpenses();
      setState(() {
        _allExpenses = expenses;
        _applyFilters();
      });
    } catch (e) {
      debugPrint('Error loading expenses: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading expenses: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    var filtered = List<Expense>.from(_allExpenses);

    // Category filter
    if (_selectedCategory != null && _selectedCategory!.isNotEmpty) {
      filtered = filtered.where((e) {
        if (_selectedCategory == 'Other') {
          return e.category == null ||
              e.category!.isEmpty ||
              !ExpenseCategories.categories.contains(e.category);
        }
        return e.category == _selectedCategory;
      }).toList();
    }

    // Month filter
    if (_selectedMonth != null) {
      filtered = filtered.where((e) {
        return e.expenseDate.year == _selectedMonth!.year &&
            e.expenseDate.month == _selectedMonth!.month;
      }).toList();
    }

    // Date filter
    if (_selectedDate != null) {
      filtered = filtered.where((e) {
        return e.expenseDate.year == _selectedDate!.year &&
            e.expenseDate.month == _selectedDate!.month &&
            e.expenseDate.day == _selectedDate!.day;
      }).toList();
    }

    // Sort by date (newest first)
    filtered.sort((a, b) => b.expenseDate.compareTo(a.expenseDate));

    setState(() {
      _filteredExpenses = filtered;
    });
  }

  Future<void> _selectMonth() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: 'Select Month',
    );
    if (picked != null) {
      setState(() {
        _selectedMonth = DateTime(picked.year, picked.month);
        _selectedDate = null; // Clear date filter when month is selected
      });
      _applyFilters();
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _selectedMonth = null; // Clear month filter when date is selected
      });
      _applyFilters();
    }
  }

  void _clearFilters() {
    setState(() {
      _selectedCategory = null;
      _selectedMonth = null;
      _selectedDate = null;
    });
    _applyFilters();
  }

  double _getTotalAmount() {
    return _filteredExpenses.fold(0.0, (sum, expense) => sum + expense.price);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Expenses'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadExpenses,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filters Section
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[100],
            child: Column(
              children: [
                // Category Filter - Chips
                SizedBox(
                  height: 50,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      FilterChip(
                        label: const Text(
                          'All',
                          style: TextStyle(color: Colors.black),
                        ),
                        selected: _selectedCategory == null,
                        onSelected: (selected) {
                          setState(() => _selectedCategory = null);
                          _applyFilters();
                        },
                      ),
                      const SizedBox(width: 8),
                      ...ExpenseCategories.categories.map((category) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(
                              category,
                              style: const TextStyle(color: Colors.black),
                            ),
                            selected: _selectedCategory == category,
                            onSelected: (selected) {
                              setState(() {
                                _selectedCategory = selected ? category : null;
                              });
                              _applyFilters();
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Date Filters
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: ButtonStyle(
                          padding: MaterialStateProperty.all(EdgeInsets.zero),
                          foregroundColor: MaterialStateProperty.all(
                            Colors.black,
                          ),
                        ),
                        onPressed: _selectMonth,
                        icon: const Icon(
                          Icons.calendar_month,
                          color: Colors.black,
                        ),
                        label: Text(
                          _selectedMonth != null
                              ? DateFormat('MMM yyyy').format(_selectedMonth!)
                              : 'Select Month',
                          style: const TextStyle(color: Colors.black),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: ButtonStyle(
                          padding: MaterialStateProperty.all(EdgeInsets.zero),
                          foregroundColor: MaterialStateProperty.all(
                            Colors.black,
                          ),
                        ),
                        onPressed: _selectDate,
                        icon: const Icon(
                          Icons.calendar_today,
                          color: Colors.black,
                        ),
                        label: Text(
                          _selectedDate != null
                              ? DateFormat(
                                  'MMM dd, yyyy',
                                ).format(_selectedDate!)
                              : 'Select Date',
                          style: const TextStyle(color: Colors.black),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      child: const Icon(Icons.clear),
                      onTap: _clearFilters,
                    ),
                  ],
                ),
                // Total Amount
                if (_filteredExpenses.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total:',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '₹${_getTotalAmount().toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // Expenses List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredExpenses.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.receipt_long,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _allExpenses.isEmpty
                              ? 'No expenses yet'
                              : 'No expenses match your filters',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadExpenses,
                    child: ListView.builder(
                      itemCount: _filteredExpenses.length,
                      padding: const EdgeInsets.all(8),
                      itemBuilder: (context, index) {
                        final expense = _filteredExpenses[index];
                        return _ExpenseCard(
                          expense: expense,
                          onEdit: () => _editExpense(expense),
                          onDelete: () => _deleteExpense(expense),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _editExpense(Expense expense) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditExpenseScreen(
          expense: expense,
          sheetsService: widget.sheetsService,
        ),
      ),
    );

    if (result == true) {
      _loadExpenses();
    }
  }

  Future<void> _deleteExpense(Expense expense) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange[700], size: 28),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Delete Expense',
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
              'Are you sure you want to delete this expense?',
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
                    'Label: ${expense.label}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text('Amount: ₹${expense.price.toStringAsFixed(0)}'),
                  if (expense.category != null)
                    Text('Category: ${expense.category}'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This action cannot be undone.',
              style: TextStyle(
                color: Colors.red[700],
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
              'Yes, Delete',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        await widget.sheetsService.deleteExpense(expense.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Expense deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
        _loadExpenses();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting expense: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }
}

class _ExpenseCard extends StatelessWidget {
  final Expense expense;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ExpenseCard({
    required this.expense,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // Category Icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getCategoryIcon(expense.category),
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            // Main Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          expense.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (expense.category != null &&
                          expense.category!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            expense.category!,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[700],
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (expense.note != null && expense.note!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      expense.note!,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Price and Actions
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ZoomTapAnimation(
                      onTap: onEdit,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.edit,
                          size: 20,
                          color: Colors.blue[700],
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    ZoomTapAnimation(
                      onTap: onDelete,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.delete,
                          size: 20,
                          color: Colors.red[700],
                        ),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 50,
                        minHeight: 32,
                      ),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '₹${expense.price.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String? category) {
    switch (category) {
      case 'Food & Groceries':
        return Icons.restaurant;
      case 'Transportation':
        return Icons.directions_car;
      case 'Utilities':
        return Icons.bolt;
      case 'Shopping':
        return Icons.shopping_bag;
      case 'Entertainment':
        return Icons.movie;
      case 'Healthcare':
        return Icons.medical_services;
      case 'Education':
        return Icons.school;
      case 'Bills & Payments':
        return Icons.receipt;
      case 'Personal Care':
        return Icons.spa;
      case 'Home & Maintenance':
        return Icons.home_repair_service;
      case 'Travel':
        return Icons.flight;
      case 'Gifts & Donations':
        return Icons.card_giftcard;
      default:
        return Icons.category;
    }
  }
}
