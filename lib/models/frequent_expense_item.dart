class FrequentExpenseItem {
  final String id;
  final String label;
  final double price;
  final String? category;
  final bool show;

  FrequentExpenseItem({
    required this.id,
    required this.label,
    required this.price,
    this.category,
    this.show = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'label': label,
      'price': price,
      'category': category ?? '',
      'show': show,
    };
  }

  factory FrequentExpenseItem.fromMap(String id, Map<dynamic, dynamic> map) {
    return FrequentExpenseItem(
      id: id,
      label: map['label']?.toString() ?? '',
      price: (map['price'] is num)
          ? (map['price'] as num).toDouble()
          : double.tryParse(map['price']?.toString() ?? '0') ?? 0,
      category: (map['category']?.toString() ?? '').isEmpty
          ? null
          : map['category']?.toString(),
      show: map['show'] == true || map['show']?.toString() == 'true',
    );
  }

  FrequentExpenseItem copyWith({
    String? id,
    String? label,
    double? price,
    String? category,
    bool? show,
  }) {
    return FrequentExpenseItem(
      id: id ?? this.id,
      label: label ?? this.label,
      price: price ?? this.price,
      category: category ?? this.category,
      show: show ?? this.show,
    );
  }
}
