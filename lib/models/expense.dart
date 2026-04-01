import 'package:uuid/uuid.dart';

class Expense {
  final String id;
  final String label;
  final double price;
  final String? category;
  final String? note;
  final DateTime expenseDate;
  final DateTime timestamp;
  final String? paidBy;
  final bool isOneTimePurchase;
  /// Email of user who added the row (common: column J; personal: column I).
  final String? addedByEmail;
  /// Personal sheet only: home/common spreadsheet id this row is tied to (column J).
  final String? linkedHomeSpreadsheetId;

  Expense({
    String? id,
    required this.label,
    required this.price,
    this.category,
    this.note,
    required this.expenseDate,
    DateTime? timestamp,
    this.paidBy,
    this.isOneTimePurchase = false,
    this.addedByEmail,
    this.linkedHomeSpreadsheetId,
  }) : id = id ?? const Uuid().v4(),
       timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'label': label,
      'price': price.toStringAsFixed(0),
      'category': category ?? '',
      'note': note ?? '',
      'expenseDate': expenseDate.toIso8601String().split('T')[0],
      'timestamp': timestamp.toIso8601String(),
      'paidBy': paidBy ?? '',
      'isOneTimePurchase': isOneTimePurchase,
      'addedByEmail': addedByEmail ?? '',
      'linkedHomeSpreadsheetId': linkedHomeSpreadsheetId ?? '',
    };
  }

  /// Shared sheet row (A–J, 10 columns).
  List<String> toRow() {
    return [
      id,                                            // A
      label,                                         // B
      price.toStringAsFixed(0),                      // C
      category ?? '',                                // D
      note ?? '',                                    // E
      expenseDate.toIso8601String().split('T')[0],   // F
      timestamp.toIso8601String(),                   // G
      paidBy ?? '',                                  // H
      isOneTimePurchase ? 'TRUE' : 'FALSE',          // I
      addedByEmail?.trim() ?? '',                    // J
    ];
  }

  /// Personal sheet row (A–K, 11 columns).
  /// Columns A–J are identical to [toRow] so both layouts are interoperable.
  /// Column K holds the linked shared spreadsheet ID.
  List<String> toPersonalRow() {
    return [
      id,                                            // A
      label,                                         // B
      price.toStringAsFixed(0),                      // C
      category ?? '',                                // D
      note ?? '',                                    // E
      expenseDate.toIso8601String().split('T')[0],   // F
      timestamp.toIso8601String(),                   // G
      paidBy ?? '',                                  // H
      isOneTimePurchase ? 'TRUE' : 'FALSE',          // I
      addedByEmail?.trim() ?? '',                    // J
      linkedHomeSpreadsheetId?.trim() ?? '',         // K
    ];
  }

  Expense.fromMap(Map<String, dynamic> map)
    : id = map['id'] as String? ?? const Uuid().v4(),
      label = map['label'] as String,
      price = (map['price'] is num)
          ? (map['price'] as num).toDouble()
          : double.tryParse(map['price'].toString()) ?? 0.0,
      category = map['category'] as String?,
      note = map['note'] as String?,
      expenseDate = map['expenseDate'] is DateTime
          ? map['expenseDate'] as DateTime
          : DateTime.tryParse(map['expenseDate'].toString()) ?? DateTime.now(),
      timestamp = map['timestamp'] is DateTime
          ? map['timestamp'] as DateTime
          : DateTime.tryParse(map['timestamp'].toString()) ?? DateTime.now(),
      paidBy = map['paidBy'] as String?,
      isOneTimePurchase = map['isOneTimePurchase'] is bool
          ? map['isOneTimePurchase'] as bool
          : (map['isOneTimePurchase']?.toString().toUpperCase() == 'TRUE' || 
             map['isOneTimePurchase']?.toString() == '1'),
      addedByEmail = _parseOptionalString(map['addedByEmail']),
      linkedHomeSpreadsheetId =
          _parseOptionalString(map['linkedHomeSpreadsheetId']);

  static String? _parseOptionalString(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }
}
