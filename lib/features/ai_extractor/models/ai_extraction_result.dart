import '../../../models/expense.dart';

/// Temporary model holding a single transaction extracted by the LLM.
///
/// Use [toExpense] to convert this into the app's canonical [Expense] model
/// before saving to Google Sheets.
class AIExtractionResult {
  String label;
  String price;
  String category;
  String note;
  String expenseDate; // yyyy-MM-dd
  String expenseTime; // HH:mm:ss

  /// Whether the user has toggled this result on (to be saved).
  bool isSelected;

  AIExtractionResult({
    required this.label,
    required this.price,
    required this.category,
    required this.note,
    required this.expenseDate,
    this.expenseTime = '00:00:00',
    this.isSelected = true,
  });

  factory AIExtractionResult.fromJson(Map<String, dynamic> json) {
    return AIExtractionResult(
      label: (json['label'] as String?)?.trim() ?? 'Unknown',
      price: (json['price'] ?? '0').toString().trim(),
      category: (json['category'] as String?)?.trim() ?? 'Other',
      note: (json['note'] as String?)?.trim() ?? '',
      expenseDate:
          (json['expenseDate'] as String?)?.trim() ??
          DateTime.now().toIso8601String().split('T')[0],
      expenseTime: (json['expenseTime'] as String?)?.trim() ?? '00:00:00',
    );
  }

  /// Convert to the app's [Expense] model.
  ///
  /// [paidBy] – the name of the person paying (e.g. "Shubham").
  /// [addedByEmail] – the logged-in user's email.
  Expense toExpense({required String paidBy, required String addedByEmail}) {
    final dateParts = expenseDate.split('-');
    DateTime parsedDate;
    try {
      parsedDate = DateTime(
        int.parse(dateParts[0]),
        int.parse(dateParts[1]),
        int.parse(dateParts[2]),
      );
    } catch (_) {
      parsedDate = DateTime.now();
    }

    DateTime parsedTimestamp;
    try {
      parsedTimestamp = DateTime.parse('${expenseDate}T$expenseTime');
    } catch (_) {
      parsedTimestamp = DateTime.now();
    }

    return Expense(
      label: label,
      price: double.tryParse(price) ?? 0.0,
      category: category,
      note: note.isNotEmpty ? note : null,
      expenseDate: parsedDate,
      timestamp: parsedTimestamp,
      paidBy: paidBy,
      isOneTimePurchase: false,
      addedByEmail: addedByEmail,
      linkedHomeSpreadsheetId: null,
    );
  }
}
