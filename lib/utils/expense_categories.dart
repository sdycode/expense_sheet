class _ExpenseCategories {
  static const List<String> categories = [
    'Food & Groceries',
    'Transportation',
    'Utilities',
    'Shopping',
    'Entertainment',
    'Healthcare',
    'Education',
    'Bills & Payments',
    'Personal Care',
    'Home & Maintenance',
    'Travel',
    'Gifts & Donations',
    'Other',
  ];
}

// Export for use in other files
class ExpenseCategories {
  static const List<String> categories = _ExpenseCategories.categories;
}

