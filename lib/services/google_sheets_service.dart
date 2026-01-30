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

  Future<bool> addExpense(Expense expense) async {
    debugPrint('ids are $_sheetsApi, $_spreadsheetId');
    if (_sheetsApi == null || _spreadsheetId == null) {
      throw Exception('Sheets API not initialized or Spreadsheet ID not set');
    }

    try {
      // Check if headers exist, if not create them
      try {
        await _sheetsApi!.spreadsheets.values.get(
          _spreadsheetId!,
          'Sheet1!A1:I1',
        );
      } catch (e) {
        // Headers don't exist, create them
        await _createHeaders();
      }

      // Get the next row
      final nextRow = await _getNextRow();
      
      // Prepare the row data
      final rowData = expense.toRow();
      
      // Create value range
      final valueRange = sheets.ValueRange(
        values: [rowData],
      );

      // Append the row
      await _sheetsApi!.spreadsheets.values.append(
        valueRange,
        _spreadsheetId!,
        'Sheet1!A$nextRow',
        valueInputOption: 'USER_ENTERED',
      );

      debugPrint('GoogleSheetsService: Expense added successfully to row $nextRow');
      return true;
    } catch (e, stackTrace) {
      debugPrint('GoogleSheetsService: Error adding expense: $e');
      debugPrint('GoogleSheetsService: Stack trace: $stackTrace');
      // Try to refresh auth and retry once
      if (e.toString().contains('401') || 
          e.toString().contains('unauthorized') ||
          e.toString().toLowerCase().contains('authentication')) {
        debugPrint('GoogleSheetsService: Authentication error detected, attempting to refresh...');
        await refreshAuth();
        if (_sheetsApi != null) {
          debugPrint('GoogleSheetsService: Retrying expense addition after auth refresh...');
          // Retry the operation
          final nextRow = await _getNextRow();
          final rowData = expense.toRow();
          final valueRange = sheets.ValueRange(values: [rowData]);
          await _sheetsApi!.spreadsheets.values.append(
            valueRange,
            _spreadsheetId!,
            'Sheet1!A$nextRow',
            valueInputOption: 'USER_ENTERED',
          );
          debugPrint('GoogleSheetsService: Expense added successfully after retry');
          return true;
        }
      }
      rethrow;
    }
  }

  Future<void> _createHeaders() async {
    if (_sheetsApi == null || _spreadsheetId == null) return;

    final headers = [
      ['ID', 'Label', 'Price', 'Category', 'Note', 'Expense Date', 'Timestamp', 'Paid By', 'Is One Time Purchase']
    ];

    final valueRange = sheets.ValueRange(values: headers);
    
    await _sheetsApi!.spreadsheets.values.update(
      valueRange,
      _spreadsheetId!,
      'Sheet1!A1',
      valueInputOption: 'USER_ENTERED',
    );
  }

  Future<int> _getNextRow() async {
    if (_sheetsApi == null || _spreadsheetId == null) return 2;

    try {
      final response = await _sheetsApi!.spreadsheets.values.get(
        _spreadsheetId!,
        'Sheet1!A:A',
      );

      if (response.values == null || response.values!.isEmpty) {
        return 2; // Headers + first data row
      }

      return response.values!.length + 1;
    } catch (e, stackTrace) {
      debugPrint('GoogleSheetsService: Error getting next row: $e');
      debugPrint('GoogleSheetsService: Stack trace: $stackTrace');
      return 2;
    }
  }

  Future<List<Expense>> getExpenses() async {
    if (_sheetsApi == null || _spreadsheetId == null) {
      throw Exception('Sheets API not initialized or Spreadsheet ID not set');
    }

    try {
      final response = await _sheetsApi!.spreadsheets.values.get(
        _spreadsheetId!,
        'Sheet1!A2:I', // Skip header row
      );

      if (response.values == null || response.values!.isEmpty) {
        return [];
      }

      final expenses = <Expense>[];
      for (var row in response.values!) {
        // Skip empty rows (deleted rows will be empty)
        if (row.isEmpty || row[0].toString().trim().isEmpty) {
          continue;
        }
        
        if (row.length >= 6) {
          try {
            final isOneTimePurchase = row.length > 8 
                ? (row[8].toString().toUpperCase() == 'TRUE' || 
                   row[8].toString() == '1' ||
                   row[8].toString().toLowerCase() == 'true')
                : false;
            
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
              paidBy: row.length > 7 && row[7].toString().isNotEmpty
                  ? row[7].toString()
                  : null,
              isOneTimePurchase: isOneTimePurchase,
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

  Future<bool> updateExpense(Expense expense) async {
    if (_sheetsApi == null || _spreadsheetId == null) {
      throw Exception('Sheets API not initialized or Spreadsheet ID not set');
    }

    try {
      // Find the row number by searching for the unique ID in column A
      final response = await _sheetsApi!.spreadsheets.values.get(
        _spreadsheetId!,
        'Sheet1!A:A', // Get all IDs from column A
      );

      if (response.values == null || response.values!.isEmpty) {
        throw Exception('No data found in sheet');
      }

      // Find the row index (0-based) where the ID matches
      int? rowIndex;
      for (int i = 0; i < response.values!.length; i++) {
        if (i == 0) continue; // Skip header row
        if (response.values![i].isNotEmpty && 
            response.values![i][0].toString() == expense.id) {
          rowIndex = i;
          break;
        }
      }

      if (rowIndex == null) {
        throw Exception('Expense with ID ${expense.id} not found');
      }

      // Row number (1-based, including header)
      final rowNumber = rowIndex + 1;

      final rowData = expense.toRow();
      final valueRange = sheets.ValueRange(values: [rowData]);

      await _sheetsApi!.spreadsheets.values.update(
        valueRange,
        _spreadsheetId!,
        'Sheet1!A$rowNumber',
        valueInputOption: 'USER_ENTERED',
      );

      debugPrint('GoogleSheetsService: Expense updated successfully at row $rowNumber (ID: ${expense.id})');
      return true;
    } catch (e, stackTrace) {
      debugPrint('GoogleSheetsService: Error updating expense: $e');
      debugPrint('GoogleSheetsService: Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<bool> deleteExpense(String expenseId) async {
    if (_sheetsApi == null || _spreadsheetId == null) {
      throw Exception('Sheets API not initialized or Spreadsheet ID not set');
    }

    try {
      // Find the row number by searching for the unique ID in column A
      final response = await _sheetsApi!.spreadsheets.values.get(
        _spreadsheetId!,
        'Sheet1!A:A', // Get all IDs from column A
      );

      if (response.values == null || response.values!.isEmpty) {
        throw Exception('No data found in sheet');
      }

      // Find the row index (0-based) where the ID matches
      int? rowIndex;
      for (int i = 0; i < response.values!.length; i++) {
        if (i == 0) continue; // Skip header row
        if (response.values![i].isNotEmpty && 
            response.values![i][0].toString() == expenseId) {
          rowIndex = i;
          break;
        }
      }

      if (rowIndex == null) {
        throw Exception('Expense with ID $expenseId not found');
      }

      // Row number (1-based, including header)
      final rowNumber = rowIndex + 1;

      // Get sheet ID for Sheet1
      final spreadsheet = await _sheetsApi!.spreadsheets.get(_spreadsheetId!);
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
        _spreadsheetId!,
      );

      debugPrint('GoogleSheetsService: Expense row deleted successfully at row $rowNumber (ID: $expenseId)');
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

