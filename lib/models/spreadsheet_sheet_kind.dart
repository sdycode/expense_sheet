/// Stored under Firebase `spreadsheets/{id}/meta/sheetKind` and `users/.../ownedSheets/{id}/sheetKind`.
enum SpreadsheetSheetKind {
  /// Shared / home / group expenses.
  common,

  /// Owner-only; no Paid By; column J = linked home/common spreadsheet id.
  personal;

  static SpreadsheetSheetKind fromDb(String? v) {
    if (v == 'personal') return SpreadsheetSheetKind.personal;
    return SpreadsheetSheetKind.common;
  }

  String get dbValue => this == SpreadsheetSheetKind.personal ? 'personal' : 'common';
}
