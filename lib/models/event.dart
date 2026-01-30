class Event {
  final String id;
  final String name;
  final String? notes;
  final DateTime? date;
  final DateTime? startDate;
  final DateTime? endDate;

  Event({
    required this.id,
    required this.name,
    this.notes,
    this.date,
    this.startDate,
    this.endDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'notes': notes ?? '',
      'date': date?.toIso8601String(),
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
    };
  }

  factory Event.fromMap(String id, Map<dynamic, dynamic> map) {
    return Event(
      id: id,
      name: map['name']?.toString() ?? '',
      notes: (map['notes']?.toString() ?? '').isEmpty ? null : map['notes']?.toString(),
      date: map['date'] != null ? DateTime.tryParse(map['date'].toString()) : null,
      startDate: map['startDate'] != null ? DateTime.tryParse(map['startDate'].toString()) : null,
      endDate: map['endDate'] != null ? DateTime.tryParse(map['endDate'].toString()) : null,
    );
  }

  Event copyWith({
    String? id,
    String? name,
    String? notes,
    DateTime? date,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return Event(
      id: id ?? this.id,
      name: name ?? this.name,
      notes: notes ?? this.notes,
      date: date ?? this.date,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
    );
  }
}
