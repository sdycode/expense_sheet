import 'package:flutter/foundation.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as io;
import '../models/expense.dart';

// Custom HTTP client that adds authorization header
class AuthenticatedClient extends http.BaseClient {
  final http.Client _inner;
  final String _accessToken;

  AuthenticatedClient(this._inner, this._accessToken);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_accessToken';
    return _inner.send(request);
  }
}

class GoogleSheetsService {
  static final GoogleSheetsService _instance = GoogleSheetsService._internal();
  factory GoogleSheetsService() => _instance;
  GoogleSheetsService._internal();

  /// Expected first-row headers on `Sheet1` for expense data (see [_createHeaders]).
  static const List<String> expenseSheetHeaderLabels = [
    'ID',
    'Label',
    'Price',
    'Category',
    'Note',
    'Expense Date',
    'Timestamp',
    'Paid By',
    'Is One Time Purchase',
    'Added By Email',
  ];

  /// Personal layout: no Paid By; column J = linked home/common spreadsheet id.
  static const List<String> personalExpenseSheetHeaderLabels = [
    'ID',
    'Label',
    'Price',
    'Category',
    'Note',
    'Expense Date',
    'Timestamp',
    'Is One Time Purchase',
    'Added By Email',
    'Linked Home Sheet ID',
  ];

  sheets.SheetsApi? _sheetsApi;
  String? _spreadsheetId;
  String? _currentAccessToken;
  GoogleSignInAccount? _currentAccount;

  void setSpreadsheetId(String id) {
    _spreadsheetId = id;
  }

  // New method: Initialize with Firebase access token
  Future<sheets.SheetsApi?> initializeSheetsApiWithToken(String accessToken) async {
    try {
      _currentAccessToken = accessToken;
      
      if (accessToken.isEmpty) {
        throw Exception('Access token is empty');
      }

      // Create authenticated HTTP client
      final httpClient = AuthenticatedClient(
        io.IOClient(),
        accessToken,
      );

      _sheetsApi = sheets.SheetsApi(httpClient);
      debugPrint('GoogleSheetsService: Sheets API initialized successfully with Firebase token');
      return _sheetsApi;
    } catch (e, stackTrace) {
      debugPrint('GoogleSheetsService: Error initializing Sheets API: $e');
      debugPrint('GoogleSheetsService: Stack trace: $stackTrace');
      return null;
    }
  }

  // Legacy method: Initialize with GoogleSignInAccount (for backward compatibility)
  Future<sheets.SheetsApi?> initializeSheetsApi(GoogleSignInAccount account) async {
    try {
      _currentAccount = account;
      final GoogleSignInAuthentication authData = await account.authentication;
      
      // Refresh token if needed
      if (authData.accessToken == null) {
        // Try to refresh authentication
        await account.clearAuthCache();
        final newAuth = await account.authentication;
        if (newAuth.accessToken == null) {
          throw Exception('Access token is null. Please sign in again.');
        }
      }

      final accessToken = authData.accessToken!;
      return await initializeSheetsApiWithToken(accessToken);
    } catch (e, stackTrace) {
      debugPrint('GoogleSheetsService: Error initializing Sheets API: $e');
      debugPrint('GoogleSheetsService: Stack trace: $stackTrace');
      return null;
    }
  }

  Future<void> refreshAuth() async {
    if (_currentAccount != null) {
      await initializeSheetsApi(_currentAccount!);
    } else if (_currentAccessToken != null) {
      // Try to refresh using Google Sign-In silently
      try {
        final googleSignIn = GoogleSignIn(
          scopes: ['https://www.googleapis.com/auth/spreadsheets'],
        );
        final GoogleSignInAccount? account = await googleSignIn.signInSilently();
        if (account != null) {
          final GoogleSignInAuthentication auth = await account.authentication;
          if (auth.accessToken != null) {
            await initializeSheetsApiWithToken(auth.accessToken!);
          }
        }
      } catch (e) {
        debugPrint('GoogleSheetsService: Error refreshing auth: $e');
      }
    }
  }

  Future<bool> isInitialized() async {
    return _sheetsApi != null && _spreadsheetId != null;
  }

  /// True when [e] is a Google API 401 (expired or invalid OAuth access token).
  static bool isSheetsUnauthorizedError(Object e) {
    final s = e.toString();
    return s.contains('DetailedApiRequestError') && s.contains('401');
  }

  Future<String?> getSpreadsheetName(String spreadsheetId) async {
    if (_sheetsApi == null) {
      throw Exception('Sheets API not initialized');
    }

    try {
      final spreadsheet = await _sheetsApi!.spreadsheets.get(spreadsheetId);
      return spreadsheet.properties?.title;
    } catch (e, stackTrace) {
      debugPrint('GoogleSheetsService: Error getting spreadsheet name: $e');
      debugPrint('GoogleSheetsService: Stack trace: $stackTrace');
      return null;
    }
  }

  /// Like [getSpreadsheetName], but on 401 runs [reauthorize] once (e.g. refresh
  /// OAuth token + [initializeSheetsApiWithToken]) and retries the request.
  Future<String?> getSpreadsheetNameWithReauthorize(
    String spreadsheetId,
    Future<void> Function() reauthorize,
  ) async {
    if (_sheetsApi == null) {
      debugPrint(
        'GoogleSheetsService: getSpreadsheetNameWithReauthorize: API not initialized',
      );
      return null;
    }

    Future<String?> fetch() async {
      final spreadsheet = await _sheetsApi!.spreadsheets.get(spreadsheetId);
      return spreadsheet.properties?.title;
    }

    try {
      return await fetch();
    } catch (e, stackTrace) {
      if (!isSheetsUnauthorizedError(e)) {
        debugPrint('GoogleSheetsService: Error getting spreadsheet name: $e');
        debugPrint('GoogleSheetsService: Stack trace: $stackTrace');
        return null;
      }
      debugPrint(
        'GoogleSheetsService: 401 on getSpreadsheetName, refreshing token and retrying...',
      );
      try {
        await reauthorize();
        if (_sheetsApi == null) return null;
        return await fetch();
      } catch (e2, st2) {
        debugPrint(
          'GoogleSheetsService: Retry after reauthorize failed: $e2',
        );
        debugPrint('GoogleSheetsService: Stack trace: $st2');
        return null;
      }
    }
  }

  Future<bool> verifySpreadsheetExists(String spreadsheetId) async {
    if (_sheetsApi == null) {
      throw Exception('Sheets API not initialized');
    }

    try {
      await _sheetsApi!.spreadsheets.get(spreadsheetId);
      return true;
    } catch (e) {
      debugPrint('GoogleSheetsService: Spreadsheet does not exist or not accessible: $e');
      return false;
    }
  }

  /// Creates an empty spreadsheet in the user's Google Drive (default `Sheet1`).
  /// Headers are written on first expense append via [_createHeadersFor].
  Future<String?> createBlankSpreadsheet({required String title}) async {
    if (_sheetsApi == null) {
      throw Exception('Sheets API not initialized');
    }
    try {
      final req = sheets.Spreadsheet(
        properties: sheets.SpreadsheetProperties(title: title),
      );
      final created = await _sheetsApi!.spreadsheets.create(req);
      final id = created.spreadsheetId;
      debugPrint('GoogleSheetsService: Created spreadsheet $id');
      return id;
    } catch (e, stackTrace) {
      debugPrint('GoogleSheetsService: createBlankSpreadsheet error: $e');
      debugPrint('GoogleSheetsService: Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// True if [Sheet1] row 1 is empty or matches [expenseSheetHeaderLabels].
  Future<bool> isCompatibleExpenseSheet(String spreadsheetId) async {
    if (_sheetsApi == null) {
      throw Exception('Sheets API not initialized');
    }
    try {
      final response = await _sheetsApi!.spreadsheets.values.get(
        spreadsheetId,
        'Sheet1!A1:J1',
      );
      final values = response.values;
      if (values == null || values.isEmpty) return true;
      final row = values.first;
      if (row.every((c) => c.toString().trim().isEmpty)) return true;
      return _rowMatchesExpenseHeaders(row);
    } catch (e) {
      debugPrint(
        'GoogleSheetsService: isCompatibleExpenseSheet false for '
        '$spreadsheetId: $e',
      );
      return false;
    }
  }

  bool _rowMatchesExpenseHeaders(List<Object?> row) {
    final n = expenseSheetHeaderLabels.length;
    for (var i = 0; i < n; i++) {
      final expected = expenseSheetHeaderLabels[i].toLowerCase();
      final actual =
          i < row.length ? row[i].toString().trim().toLowerCase() : '';
      if (actual != expected) return false;
    }
    return true;
  }

  /// Matches 10-column personal headers, or legacy 9-column (no linked home id).
  bool _rowMatchesPersonalHeaders(List<Object?> row) {
    final full = personalExpenseSheetHeaderLabels;
    if (_rowMatchesHeaderLabels(row, full)) return true;
    if (row.length >= 9) {
      return _rowMatchesHeaderLabels(row, full.sublist(0, 9));
    }
    return false;
  }

  bool _rowMatchesHeaderLabels(List<Object?> row, List<String> labels) {
    if (row.length < labels.length) return false;
    for (var i = 0; i < labels.length; i++) {
      final expected = labels[i].toLowerCase();
      final actual = row[i].toString().trim().toLowerCase();
      if (actual != expected) return false;
    }
    return true;
  }

  /// True if [Sheet1] row 1 is empty or matches [personalExpenseSheetHeaderLabels].
  Future<bool> isCompatiblePersonalExpenseSheet(String spreadsheetId) async {
    if (_sheetsApi == null) {
      throw Exception('Sheets API not initialized');
    }
    try {
      final response = await _sheetsApi!.spreadsheets.values.get(
        spreadsheetId,
        'Sheet1!A1:J1',
      );
      final values = response.values;
      if (values == null || values.isEmpty) return true;
      final row = values.first;
      if (row.every((c) => c.toString().trim().isEmpty)) return true;
      return _rowMatchesPersonalHeaders(row);
    } catch (e) {
      debugPrint(
        'GoogleSheetsService: isCompatiblePersonalExpenseSheet false for '
        '$spreadsheetId: $e',
      );
      return false;
    }
  }

  Future<bool> addExpense(Expense expense, {bool personalLayout = false}) async {
    if (_spreadsheetId == null) {
      throw Exception('Spreadsheet ID not set');
    }
    return addExpenseTo(
      _spreadsheetId!,
      expense,
      personalLayout: personalLayout,
    );
  }

  Future<bool> addExpenseTo(
    String spreadsheetId,
    Expense expense, {
    required bool personalLayout,
  }) async {
    if (_sheetsApi == null) {
      throw Exception('Sheets API not initialized');
    }

    try {
      const headerRange = 'Sheet1!A1:J1';
      try {
        await _sheetsApi!.spreadsheets.values.get(spreadsheetId, headerRange);
      } catch (e) {
        await _createHeadersFor(spreadsheetId, personalLayout);
      }

      final nextRow = await _getNextRowFor(spreadsheetId);
      final rowData =
          personalLayout ? expense.toPersonalRow() : expense.toRow();
      final valueRange = sheets.ValueRange(values: [rowData]);

      await _sheetsApi!.spreadsheets.values.append(
        valueRange,
        spreadsheetId,
        'Sheet1!A$nextRow',
        valueInputOption: 'USER_ENTERED',
      );

      debugPrint(
        'GoogleSheetsService: Expense added to $spreadsheetId row $nextRow',
      );
      return true;
    } catch (e, stackTrace) {
      debugPrint('GoogleSheetsService: Error adding expense: $e');
      debugPrint('GoogleSheetsService: Stack trace: $stackTrace');
      if (e.toString().contains('401') ||
          e.toString().contains('unauthorized') ||
          e.toString().toLowerCase().contains('authentication')) {
        await refreshAuth();
        if (_sheetsApi != null) {
          final nextRow = await _getNextRowFor(spreadsheetId);
          final rowData =
              personalLayout ? expense.toPersonalRow() : expense.toRow();
          final valueRange = sheets.ValueRange(values: [rowData]);
          await _sheetsApi!.spreadsheets.values.append(
            valueRange,
            spreadsheetId,
            'Sheet1!A$nextRow',
            valueInputOption: 'USER_ENTERED',
          );
          return true;
        }
      }
      rethrow;
    }
  }

  Future<void> _createHeaders() async {
    if (_spreadsheetId == null) return;
    await _createHeadersFor(_spreadsheetId!, false);
  }

  Future<void> _createHeadersFor(
    String spreadsheetId,
    bool personalLayout,
  ) async {
    if (_sheetsApi == null) return;

    final headers = [
      personalLayout
          ? personalExpenseSheetHeaderLabels
          : expenseSheetHeaderLabels,
    ];

    final valueRange = sheets.ValueRange(values: headers);

    await _sheetsApi!.spreadsheets.values.update(
      valueRange,
      spreadsheetId,
      'Sheet1!A1',
      valueInputOption: 'USER_ENTERED',
    );
  }

  Future<int> _getNextRow() async {
    if (_spreadsheetId == null) return 2;
    return _getNextRowFor(_spreadsheetId!);
  }

  Future<int> _getNextRowFor(String spreadsheetId) async {
    if (_sheetsApi == null) return 2;

    try {
      final response = await _sheetsApi!.spreadsheets.values.get(
        spreadsheetId,
        'Sheet1!A:A',
      );

      if (response.values == null || response.values!.isEmpty) {
        return 2;
      }

      return response.values!.length + 1;
    } catch (e, stackTrace) {
      debugPrint('GoogleSheetsService: Error getting next row: $e');
      debugPrint('GoogleSheetsService: Stack trace: $stackTrace');
      return 2;
    }
  }

  Future<List<Expense>> getExpenses({bool personalLayout = false}) async {
    if (_spreadsheetId == null) {
      throw Exception('Sheets API not initialized or Spreadsheet ID not set');
    }
    return getExpensesFor(_spreadsheetId!, personalLayout: personalLayout);
  }

  Future<List<Expense>> getExpensesFor(
    String spreadsheetId, {
    required bool personalLayout,
  }) async {
    if (_sheetsApi == null) {
      throw Exception('Sheets API not initialized');
    }

    try {
      const range = 'Sheet1!A2:J';
      final response =
          await _sheetsApi!.spreadsheets.values.get(spreadsheetId, range);

      if (response.values == null || response.values!.isEmpty) {
        return [];
      }

      final expenses = <Expense>[];
      for (var row in response.values!) {
        if (row.isEmpty || row[0].toString().trim().isEmpty) {
          continue;
        }

        if (row.length >= 6) {
          try {
            final bool isOne;
            final String? addedBy;
            final String? paidBy;
            final String? linkedHomeId;

            if (personalLayout) {
              isOne = row.length > 7
                  ? (row[7].toString().toUpperCase() == 'TRUE' ||
                      row[7].toString() == '1' ||
                      row[7].toString().toLowerCase() == 'true')
                  : false;
              addedBy = row.length > 8 && row[8].toString().trim().isNotEmpty
                  ? row[8].toString().trim()
                  : null;
              paidBy = null;
              linkedHomeId =
                  row.length > 9 && row[9].toString().trim().isNotEmpty
                      ? row[9].toString().trim()
                      : null;
            } else {
              isOne = row.length > 8
                  ? (row[8].toString().toUpperCase() == 'TRUE' ||
                      row[8].toString() == '1' ||
                      row[8].toString().toLowerCase() == 'true')
                  : false;
              addedBy = row.length > 9 && row[9].toString().trim().isNotEmpty
                  ? row[9].toString().trim()
                  : null;
              paidBy = row.length > 7 && row[7].toString().isNotEmpty
                  ? row[7].toString()
                  : null;
              linkedHomeId = null;
            }

            final expense = Expense(
              id: row[0].toString().trim(),
              label: row[1].toString(),
              price: double.tryParse(row[2].toString()) ?? 0.0,
              category: row[3].toString().isEmpty ? null : row[3].toString(),
              note: row[4].toString().isEmpty ? null : row[4].toString(),
              expenseDate: _parseDate(row[5].toString()),
              timestamp: row.length > 6
                  ? _parseDate(row[6].toString())
                  : DateTime.now(),
              paidBy: paidBy,
              isOneTimePurchase: isOne,
              addedByEmail: addedBy,
              linkedHomeSpreadsheetId: linkedHomeId,
            );
            expenses.add(expense);
          } catch (e) {
            debugPrint('Error parsing expense row: $e');
          }
        }
      }
      return expenses;
    } catch (e, stackTrace) {
      debugPrint('GoogleSheetsService: Error getting expenses: $e');
      debugPrint('GoogleSheetsService: Stack trace: $stackTrace');
      rethrow;
    }
  }

  DateTime _parseDate(String dateStr) {
    try {
      String s = dateStr.trim();
      if (s.isEmpty) return DateTime.now();

      // Try parsing as-is first
      try {
        return DateTime.parse(s);
      } catch (_) {}

      // Normalize "2026-01-18 6:04:33" -> "2026-01-18T06:04:33" (space to T, pad time parts)
      final spaceIndex = s.indexOf(' ');
      if (spaceIndex > 0) {
        final datePart = s.substring(0, spaceIndex);
        final timePart = s.substring(spaceIndex + 1).trim();
        if (timePart.isNotEmpty) {
          final timeSegments = timePart.split(':');
          final padded = timeSegments.map((e) => e.padLeft(2, '0')).join(':');
          s = '${datePart}T$padded';
        } else {
          s = datePart;
        }
        return DateTime.parse(s);
      }

      return DateTime.parse(s);
    } catch (e) {
      debugPrint('Error parsing date: $dateStr, using current date');
      return DateTime.now();
    }
  }

  Future<bool> updateExpense(
    Expense expense, {
    bool personalLayout = false,
  }) async {
    if (_spreadsheetId == null) {
      throw Exception('Spreadsheet ID not set');
    }
    return updateExpenseFor(
      _spreadsheetId!,
      expense,
      personalLayout: personalLayout,
    );
  }

  Future<bool> updateExpenseFor(
    String spreadsheetId,
    Expense expense, {
    required bool personalLayout,
  }) async {
    if (_sheetsApi == null) {
      throw Exception('Sheets API not initialized');
    }

    try {
      final response = await _sheetsApi!.spreadsheets.values.get(
        spreadsheetId,
        'Sheet1!A:A',
      );

      if (response.values == null || response.values!.isEmpty) {
        throw Exception('No data found in sheet');
      }

      int? rowIndex;
      for (int i = 0; i < response.values!.length; i++) {
        if (i == 0) continue;
        if (response.values![i].isNotEmpty &&
            response.values![i][0].toString() == expense.id) {
          rowIndex = i;
          break;
        }
      }

      if (rowIndex == null) {
        throw Exception('Expense with ID ${expense.id} not found');
      }

      final rowNumber = rowIndex + 1;

      final rowData =
          personalLayout ? expense.toPersonalRow() : expense.toRow();
      final valueRange = sheets.ValueRange(values: [rowData]);

      await _sheetsApi!.spreadsheets.values.update(
        valueRange,
        spreadsheetId,
        'Sheet1!A$rowNumber',
        valueInputOption: 'USER_ENTERED',
      );

      debugPrint(
        'GoogleSheetsService: Expense updated at row $rowNumber (${expense.id})',
      );
      return true;
    } catch (e, stackTrace) {
      debugPrint('GoogleSheetsService: Error updating expense: $e');
      debugPrint('GoogleSheetsService: Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<bool> deleteExpense(String expenseId) async {
    if (_spreadsheetId == null) {
      throw Exception('Spreadsheet ID not set');
    }
    return deleteExpenseFor(_spreadsheetId!, expenseId);
  }

  Future<bool> deleteExpenseFor(String spreadsheetId, String expenseId) async {
    if (_sheetsApi == null) {
      throw Exception('Sheets API not initialized');
    }

    try {
      final response = await _sheetsApi!.spreadsheets.values.get(
        spreadsheetId,
        'Sheet1!A:A',
      );

      if (response.values == null || response.values!.isEmpty) {
        throw Exception('No data found in sheet');
      }

      int? rowIndex;
      for (int i = 0; i < response.values!.length; i++) {
        if (i == 0) continue;
        if (response.values![i].isNotEmpty &&
            response.values![i][0].toString() == expenseId) {
          rowIndex = i;
          break;
        }
      }

      if (rowIndex == null) {
        throw Exception('Expense with ID $expenseId not found');
      }

      final rowNumber = rowIndex + 1;

      final spreadsheet = await _sheetsApi!.spreadsheets.get(spreadsheetId);
      int? sheetId;
      
      if (spreadsheet.sheets != null && spreadsheet.sheets!.isNotEmpty) {
        // Find Sheet1 or use the first sheet
        final sheet = spreadsheet.sheets!.firstWhere(
          (s) => s.properties?.title == 'Sheet1',
          orElse: () => spreadsheet.sheets!.first,
        );
        sheetId = sheet.properties?.sheetId;
      }
      
      if (sheetId == null) {
        throw Exception('Could not find sheet ID');
      }

      // Delete the entire row using batchUpdate
      final deleteRequest = sheets.DeleteDimensionRequest(
        range: sheets.DimensionRange(
          sheetId: sheetId,
          dimension: 'ROWS',
          startIndex: rowNumber - 1, // 0-based index
          endIndex: rowNumber, // End index is exclusive
        ),
      );

      final request = sheets.Request(
        deleteDimension: deleteRequest,
      );

      final batchUpdateRequest = sheets.BatchUpdateSpreadsheetRequest(
        requests: [request],
      );

      await _sheetsApi!.spreadsheets.batchUpdate(
        batchUpdateRequest,
        spreadsheetId,
      );

      debugPrint(
        'GoogleSheetsService: Expense row deleted at row $rowNumber ($expenseId)',
      );
      return true;
    } catch (e, stackTrace) {
      debugPrint('GoogleSheetsService: Error deleting expense: $e');
      debugPrint('GoogleSheetsService: Stack trace: $stackTrace');
      rethrow;
    }
  }

  // Get all person names from column I (separate column for person names)
  Future<List<String>> getPersonNames() async {
    if (_sheetsApi == null || _spreadsheetId == null) {
      throw Exception('Sheets API not initialized or Spreadsheet ID not set');
    }

    try {
      final response = await _sheetsApi!.spreadsheets.values.get(
        _spreadsheetId!,
        'Sheet1!I:I', // Column I for person names
      );

      if (response.values == null || response.values!.isEmpty) {
        return [];
      }

      final names = <String>[];
      for (var row in response.values!) {
        if (row.isNotEmpty && row[0].toString().trim().isNotEmpty) {
          final name = row[0].toString().trim();
          // Avoid duplicates
          if (!names.contains(name)) {
            names.add(name);
          }
        }
      }
      
      // Sort names alphabetically
      names.sort();
      return names;
    } catch (e, stackTrace) {
      debugPrint('GoogleSheetsService: Error getting person names: $e');
      debugPrint('GoogleSheetsService: Stack trace: $stackTrace');
      // If column doesn't exist, return empty list
      return [];
    }
  }

  // Add a new person name to column I
  Future<bool> addPersonName(String name) async {
    if (_sheetsApi == null || _spreadsheetId == null) {
      throw Exception('Sheets API not initialized or Spreadsheet ID not set');
    }

    if (name.trim().isEmpty) {
      throw Exception('Person name cannot be empty');
    }

    try {
      // Check if name already exists
      final existingNames = await getPersonNames();
      if (existingNames.contains(name.trim())) {
        debugPrint('GoogleSheetsService: Person name already exists: $name');
        return false; // Already exists
      }

      // Find the next empty row in column I
      final response = await _sheetsApi!.spreadsheets.values.get(
        _spreadsheetId!,
        'Sheet1!I:I',
      );

      int nextRow = 1; // Start from row 1 (header row is in row 1, but we'll use row 2+)
      if (response.values != null && response.values!.isNotEmpty) {
        // Find first empty row
        bool foundEmpty = false;
        for (int i = 0; i < response.values!.length; i++) {
          if (response.values![i].isEmpty || 
              response.values![i][0].toString().trim().isEmpty) {
            nextRow = i + 1;
            foundEmpty = true;
            break;
          }
        }
        if (!foundEmpty) {
          nextRow = response.values!.length + 1;
        }
      } else {
        nextRow = 1; // First row after header
      }

      // Add the name
      final valueRange = sheets.ValueRange(values: [[name.trim()]]);
      await _sheetsApi!.spreadsheets.values.update(
        valueRange,
        _spreadsheetId!,
        'Sheet1!I$nextRow',
        valueInputOption: 'USER_ENTERED',
      );

      debugPrint('GoogleSheetsService: Person name added successfully: $name');
      return true;
    } catch (e, stackTrace) {
      debugPrint('GoogleSheetsService: Error adding person name: $e');
      debugPrint('GoogleSheetsService: Stack trace: $stackTrace');
      rethrow;
    }
  }
}

