import 'package:MoneyTracker/models/frequent_expense_item.dart';
import 'package:MoneyTracker/services/services_module.dart';
import 'package:MoneyTracker/utils/expense_categories.dart';
import 'package:flutter/material.dart';

class FrequentExpenseItemsPage extends StatefulWidget {
  final String spreadsheetId;

  const FrequentExpenseItemsPage({super.key, required this.spreadsheetId});

  @override
  State<FrequentExpenseItemsPage> createState() =>
      _FrequentExpenseItemsPageState();
}

class _FrequentExpenseItemsPageState extends State<FrequentExpenseItemsPage> {
  final FirebaseDatabaseService _db = FirebaseDatabaseService();
  List<FrequentExpenseItem> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() => _isLoading = true);
    try {
      final items = await _db.getFrequentExpenseItems(widget.spreadsheetId);
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading items: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleShow(FrequentExpenseItem item) async {
    final updated = item.copyWith(show: !item.show);
    final ok = await _db.updateFrequentExpenseItem(
      widget.spreadsheetId,
      updated,
    );
    if (ok && mounted) {
      setState(() {
        final i = _items.indexWhere((e) => e.id == item.id);
        if (i >= 0) _items[i] = updated;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(updated.show ? 'Visible on home' : 'Hidden from home'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _deleteItem(FrequentExpenseItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text(
          'Delete "${item.label}" (₹${item.price.toStringAsFixed(0)})?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await _db.deleteFrequentExpenseItem(
      widget.spreadsheetId,
      item.id,
    );
    if (ok && mounted) {
      setState(() => _items.removeWhere((e) => e.id == item.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Item deleted'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _showAddEditDialog([FrequentExpenseItem? existing]) async {
    final labelController = TextEditingController(text: existing?.label ?? '');
    final priceController = TextEditingController(
      text: existing?.price.toStringAsFixed(0) ?? '',
    );
    String? category = existing?.category;
    bool show = existing?.show ?? true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(existing == null ? 'Add Frequent Item' : 'Edit Item'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: labelController,
                    decoration: const InputDecoration(
                      labelText: 'Label *',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.all(8),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceController,
                    decoration: const InputDecoration(
                      labelText: 'Price *',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.all(8),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: category,
                    decoration: const InputDecoration(
                      labelText: 'Category (Optional)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.all(8),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None')),
                      ...ExpenseCategories.categories.map(
                        (c) => DropdownMenuItem(value: c, child: Text(c)),
                      ),
                    ],
                    onChanged: (v) => setDialogState(() => category = v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Show on home'),
                      const SizedBox(width: 8),
                      Switch(
                        value: show,
                        onChanged: (v) => setDialogState(() => show = v),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final label = labelController.text.trim();
                  final price = double.tryParse(priceController.text.trim());
                  if (label.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Enter label')),
                    );
                    return;
                  }
                  if (price == null || price <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Enter valid price')),
                    );
                    return;
                  }
                  Navigator.pop(ctx);

                  if (existing != null) {
                    final updated = existing.copyWith(
                      label: label,
                      price: price,
                      category: category,
                      show: show,
                    );
                    final ok = await _db.updateFrequentExpenseItem(
                      widget.spreadsheetId,
                      updated,
                    );
                    if (ok && mounted) {
                      setState(() {
                        final i = _items.indexWhere((e) => e.id == existing.id);
                        if (i >= 0) _items[i] = updated;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Item updated'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } else {
                    final item = FrequentExpenseItem(
                      id: '',
                      label: label,
                      price: price,
                      category: category,
                      show: show,
                    );
                    final id = await _db.addFrequentExpenseItem(
                      widget.spreadsheetId,
                      item,
                    );
                    if (id != null && mounted) {
                      setState(() => _items.add(item.copyWith(id: id)));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Item added'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Frequent Expense Items')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.star_border, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No frequent items yet',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tap + to add items that appear on the home screen',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadItems,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(
                        item.label,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '₹${item.price.toStringAsFixed(0)}${item.category != null ? ' • ${item.category}' : ''}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.show ? 'Show' : 'Hide',
                            style: TextStyle(
                              fontSize: 12,
                              color: item.show ? Colors.green : Colors.grey,
                            ),
                          ),
                          Switch(
                            value: item.show,
                            onChanged: (_) => _toggleShow(item),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () => _showAddEditDialog(item),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.delete,
                              size: 20,
                              color: Colors.red[700],
                            ),
                            onPressed: () => _deleteItem(item),
                          ),
                        ],
                      ),
                      onTap: () => _showAddEditDialog(item),
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
