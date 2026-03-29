import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/expense.dart';
import '../models/event.dart';
import '../services/google_sheets_service.dart';
import '../services/services_module.dart';
import '../utils/expense_categories.dart';

class EditExpenseScreen extends StatefulWidget {
  final Expense expense;
  final GoogleSheetsService sheetsService;
  final String spreadsheetId;
  final bool personalLayout;

  const EditExpenseScreen({
    super.key,
    required this.expense,
    required this.sheetsService,
    required this.spreadsheetId,
    this.personalLayout = false,
  });

  @override
  State<EditExpenseScreen> createState() => _EditExpenseScreenState();
}

class _EditExpenseScreenState extends State<EditExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelController;
  late final TextEditingController _priceController;
  late final TextEditingController _noteController;
  late String? _selectedCategory;
  late String? _selectedPaidBy;
  late DateTime _selectedDate;
  late bool _isOneTimePurchase;
  bool _isLoading = false;
  bool _isLoadingPersonNames = true;
  List<String> _personNames = [];
  final FirebaseDatabaseService _firebaseDb = FirebaseDatabaseService();
  List<Event> _events = [];
  Set<String> _selectedEventIds = {};
  bool _isLoadingEvents = true;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.expense.label);
    _priceController = TextEditingController(
      text: widget.expense.price.toStringAsFixed(0),
    );
    _noteController = TextEditingController(text: widget.expense.note ?? '');
    // Parse category - if comma-separated, take the first one
    if (widget.expense.category != null &&
        widget.expense.category!.isNotEmpty) {
      final categories = widget.expense.category!
          .split(',')
          .map((c) => c.trim())
          .where((c) => c.isNotEmpty)
          .toList();
      _selectedCategory = categories.isNotEmpty ? categories.first : null;
    } else {
      _selectedCategory = null;
    }
    _selectedPaidBy = widget.expense.paidBy;
    _selectedDate = widget.expense.expenseDate;
    _isOneTimePurchase = widget.expense.isOneTimePurchase;
    _loadPersonNames();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    final spreadsheetId = widget.spreadsheetId;
    if (spreadsheetId.isEmpty) {
      setState(() {
        _events = [];
        _selectedEventIds = {};
        _isLoadingEvents = false;
      });
      return;
    }
    try {
      final events = await _firebaseDb.getEvents(spreadsheetId);
      final eventIds = await _firebaseDb.getEventIdsForExpense(
        spreadsheetId,
        widget.expense.id,
      );
      if (mounted) {
        setState(() {
          _events = events;
          _selectedEventIds = eventIds.toSet();
          _isLoadingEvents = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading events: $e');
      if (mounted) {
        setState(() {
          _events = [];
          _selectedEventIds = {};
          _isLoadingEvents = false;
        });
      }
    }
  }

  Future<void> _loadPersonNames() async {
    try {
      final names = await widget.sheetsService.getPersonNames();
      // Remove duplicates and ensure selected value is in the list
      final uniqueNames = names.toSet().toList()..sort();

      // If selectedPaidBy exists but not in the list, add it
      if (_selectedPaidBy != null &&
          _selectedPaidBy!.isNotEmpty &&
          !uniqueNames.contains(_selectedPaidBy)) {
        uniqueNames.add(_selectedPaidBy!);
        uniqueNames.sort();
      }

      setState(() {
        _personNames = uniqueNames;
        _isLoadingPersonNames = false;
      });
    } catch (e) {
      debugPrint('Error loading person names: $e');
      // If loading fails but we have a selected value, add it to the list
      if (_selectedPaidBy != null && _selectedPaidBy!.isNotEmpty) {
        setState(() {
          _personNames = [_selectedPaidBy!];
          _isLoadingPersonNames = false;
        });
      } else {
        setState(() {
          _isLoadingPersonNames = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    _priceController.dispose();
    _noteController.dispose();
    super.dispose();
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

  Future<void> _updateExpense() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final updatedExpense = Expense(
      id: widget.expense.id,
      label: _labelController.text.trim(),
      price: double.parse(_priceController.text.trim()),
      category: _selectedCategory,
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
      expenseDate: _selectedDate,
      timestamp: widget.expense.timestamp, // Keep original timestamp
      paidBy: widget.personalLayout ? null : _selectedPaidBy,
      isOneTimePurchase: _isOneTimePurchase,
      addedByEmail: widget.expense.addedByEmail,
      linkedHomeSpreadsheetId: widget.personalLayout
          ? widget.expense.linkedHomeSpreadsheetId
          : null,
    );

    // Save event links in Firebase (expense can belong to multiple events)
    if (widget.spreadsheetId.isNotEmpty) {
      _firebaseDb.setExpenseEvents(
        widget.spreadsheetId,
        widget.expense.id,
        _selectedEventIds.toList(),
      );
    }

    // Close screen immediately for better UX
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Expense updated! Syncing to sheet...'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.pop(context, true);
    }

    // Update in Google Sheets in background
    _uploadUpdateToSheet(updatedExpense);
  }

  Future<void> _uploadUpdateToSheet(Expense expense) async {
    try {
      debugPrint(
        'EditExpenseScreen: Updating expense in sheet: ${expense.toMap()}',
      );
      await widget.sheetsService.updateExpenseFor(
        widget.spreadsheetId,
        expense,
        personalLayout: widget.personalLayout,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Expense synced to sheet successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Error updating expense in sheet: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error syncing expense: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _uploadUpdateToSheet(expense),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Expense')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Edit Expense',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),

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
                        prefixIcon: Icon(Icons.monetization_on_outlined),
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

              // Category, Date, and One Time Purchase in one row
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
                      style: const TextStyle(fontSize: 14, color: Colors.black),
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text(
                            'None',
                            style: TextStyle(color: Colors.black),
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
                              overflow: TextOverflow.ellipsis,
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
                                DateFormat('yyyy-MM-dd').format(_selectedDate),
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 0,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shopping_cart, size: 20),
                    const SizedBox(width: 8),
                    const Text('One Time', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 8),
                    Switch(
                      value: _isOneTimePurchase,
                      onChanged: (value) {
                        setState(() {
                          _isOneTimePurchase = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              if (!widget.personalLayout) ...[
                const SizedBox(height: 16),
                _isLoadingPersonNames
                    ? const LinearProgressIndicator()
                    : Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value:
                                  _selectedPaidBy != null &&
                                      _selectedPaidBy!.isNotEmpty &&
                                      _personNames.contains(_selectedPaidBy)
                                  ? _selectedPaidBy
                                  : null,
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
                              },
                            ),
                          ),
                        ],
                      ),
              ],
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

              // Events (multi-select: add this expense to events)
              const Text(
                'Events (Optional)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 6),
              _isLoadingEvents
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(),
                    )
                  : _events.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        FirebaseAuthService().currentUser?.email == null
                            ? 'Sign in to manage events'
                            : 'No events yet. Create events to group this expense.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _events.map((event) {
                        final selected = _selectedEventIds.contains(event.id);
                        return FilterChip(
                          label: Text(event.name),
                          selected: selected,
                          onSelected: (value) {
                            setState(() {
                              if (value) {
                                _selectedEventIds.add(event.id);
                              } else {
                                _selectedEventIds.remove(event.id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
              const SizedBox(height: 24),

              // Update Button
              ElevatedButton(
                onPressed: _isLoading ? null : _updateExpense,
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
                        'Update Expense',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
