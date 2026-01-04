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
    };
  }

  List<String> toRow() {
    return [
      id,
      label,
      price.toStringAsFixed(0),
      category ?? '',
      note ?? '',
      expenseDate.toIso8601String().split('T')[0],
      timestamp.toIso8601String(),
      paidBy ?? '',
      isOneTimePurchase ? 'TRUE' : 'FALSE',
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
             map['isOneTimePurchase']?.toString() == '1');
}
