import 'package:MoneyTracker/models/event.dart';
import 'package:MoneyTracker/models/frequent_expense_item.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class FirebaseDatabaseService {
  final FirebaseDatabase _database = FirebaseDatabase.instance;

  // Get reference to the paid_by node for a specific spreadsheet
  DatabaseReference _getPaidByRef(String spreadsheetId) {
    return _database.ref().child('expenseSheet/$spreadsheetId/paid_by');
  }

  // Get reference to frequent_expenses for a spreadsheet
  DatabaseReference _getFrequentExpensesRef(String spreadsheetId) {
    return _database.ref().child(
      'expenseSheet/$spreadsheetId/frequent_expenses',
    );
  }

  DatabaseReference _getEventsRef(String spreadsheetId) {
    return _database.ref().child('expenseSheet/$spreadsheetId/events');
  }

  DatabaseReference _getExpenseEventsRef(String spreadsheetId) {
    return _database.ref().child('expenseSheet/$spreadsheetId/expense_events');
  }

  // --- Spreadsheet registry, sharing, members (see spreadsheets/ + users/ + user_sheets/) ---
  String _sanitizeEmail(String email) {
    return email.replaceAll('.', ',');
  }

  /// Lowercase trimmed email for comparisons and stable paths where safe.
  String _normalizeEmail(String email) => email.trim().toLowerCase();

  DatabaseReference _getSharedSheetsRef(String userEmail) {
    final sanitizedEmail = _sanitizeEmail(_normalizeEmail(userEmail));
    return _database.ref().child('user_sheets/$sanitizedEmail');
  }

  DatabaseReference _spreadsheetMetaRef(String spreadsheetId) {
    return _database.ref().child('spreadsheets/$spreadsheetId/meta');
  }

  DatabaseReference _spreadsheetMembersRef(String spreadsheetId) {
    return _database.ref().child('spreadsheets/$spreadsheetId/members');
  }

  DatabaseReference _userOwnedSheetsRef(String normalizedEmail) {
    return _database.ref().child(
      'users/${_sanitizeEmail(normalizedEmail)}/ownedSheets',
    );
  }

  /// Call when the current user verifies/saves a spreadsheet they use as owner.
  Future<void> registerSpreadsheetOwnership({
    required String ownerEmail,
    required String spreadsheetId,
    required String displayName,
  }) async {
    final norm = _normalizeEmail(ownerEmail);
    if (norm.isEmpty) return;
    final now = DateTime.now().toIso8601String();
    final san = _sanitizeEmail(norm);
    try {
      await _spreadsheetMetaRef(spreadsheetId).set({
        'name': displayName,
        'ownerEmail': norm,
        'updatedAt': now,
      });
      await _spreadsheetMembersRef(spreadsheetId).child(san).set({
        'email': norm,
        'role': 'owner',
        'addedAt': now,
      });
      await _userOwnedSheetsRef(norm).child(spreadsheetId).set({
        'name': displayName,
        'role': 'owner',
        'updatedAt': now,
      });
    } catch (e) {
      debugPrint('registerSpreadsheetOwnership: $e');
    }
  }

  /// Writes Firebase registry + invitee index. Caller should also call [GoogleDriveShareService.grantEditorAccess] when possible.
  Future<bool> shareSpreadsheet({
    required String ownerEmail,
    required String inviteeEmail,
    required String spreadsheetId,
    required String spreadsheetName,
  }) async {
    final normOwner = _normalizeEmail(ownerEmail);
    final normInv = _normalizeEmail(inviteeEmail);
    if (normOwner.isEmpty || normInv.isEmpty) return false;
    if (normOwner == normInv) return false;

    final now = DateTime.now().toIso8601String();
    final sanOwner = _sanitizeEmail(normOwner);
    final sanInv = _sanitizeEmail(normInv);

    try {
      final metaRef = _spreadsheetMetaRef(spreadsheetId);
      final metaSnap = await metaRef.get();
      if (!metaSnap.exists) {
        await metaRef.set({
          'name': spreadsheetName,
          'ownerEmail': normOwner,
          'updatedAt': now,
        });
      } else {
        await metaRef.update({
          'name': spreadsheetName,
          'ownerEmail': normOwner,
          'updatedAt': now,
        });
      }

      final invRef = _spreadsheetMembersRef(spreadsheetId).child(sanInv);
      final invSnap = await invRef.get();
      final inviteePayload = <String, dynamic>{
        'email': normInv,
        'role': 'editor',
        'sharedAt': now,
        'addedByEmail': normOwner,
        'driveLastGrantSuccess': null,
      };
      if (invSnap.exists && invSnap.value is Map) {
        final old = Map<String, dynamic>.from(invSnap.value as Map);
        inviteePayload['driveAccessConfirmed'] =
            old['driveAccessConfirmed'] == true;
      } else {
        inviteePayload['driveAccessConfirmed'] = false;
      }

      await Future.wait([
        _spreadsheetMembersRef(spreadsheetId).child(sanOwner).set({
          'email': normOwner,
          'role': 'owner',
          'addedAt': now,
        }),
        invRef.set(inviteePayload),
        _getSharedSheetsRef(normInv).child(spreadsheetId).set({
          'name': spreadsheetName,
          'sharedAt': now,
        }),
        _userOwnedSheetsRef(normOwner).child(spreadsheetId).set({
          'name': spreadsheetName,
          'role': 'owner',
          'updatedAt': now,
        }),
      ]);
      return true;
    } catch (e) {
      debugPrint('Error sharing spreadsheet: $e');
      return false;
    }
  }

  /// Meta under spreadsheets/{id}/meta (name, ownerEmail, …).
  Future<Map<String, String?>> getSpreadsheetMeta(String spreadsheetId) async {
    try {
      final snap = await _spreadsheetMetaRef(spreadsheetId).get();
      if (!snap.exists || snap.value == null) {
        return {'name': null, 'ownerEmail': null};
      }
      final m = Map<String, dynamic>.from(snap.value as Map);
      return {
        'name': m['name']?.toString(),
        'ownerEmail': m['ownerEmail']?.toString(),
      };
    } catch (e) {
      debugPrint('getSpreadsheetMeta: $e');
      return {'name': null, 'ownerEmail': null};
    }
  }

  /// Updates Drive-related flags on spreadsheets/{id}/members/{sanitizedEmail}.
  Future<void> updateSpreadsheetMemberDriveFields(
    String spreadsheetId,
    String memberEmail, {
    bool? driveLastGrantSuccess,
    bool? driveAccessConfirmed,
  }) async {
    final norm = _normalizeEmail(memberEmail);
    if (norm.isEmpty) return;
    final patch = <String, dynamic>{};
    if (driveLastGrantSuccess != null) {
      patch['driveLastGrantSuccess'] = driveLastGrantSuccess;
    }
    if (driveAccessConfirmed != null) {
      patch['driveAccessConfirmed'] = driveAccessConfirmed;
    }
    if (patch.isEmpty) return;
    try {
      final san = _sanitizeEmail(norm);
      await _spreadsheetMembersRef(spreadsheetId).child(san).update(patch);
    } catch (e) {
      debugPrint('updateSpreadsheetMemberDriveFields: $e');
    }
  }

  /// Members under spreadsheets/{id}/members (keys are sanitized emails).
  Future<List<Map<String, dynamic>>> getSpreadsheetMembers(
    String spreadsheetId,
  ) async {
    try {
      final ref = _spreadsheetMembersRef(spreadsheetId);
      final snapshot = await ref.get();
      if (!snapshot.exists || snapshot.value == null) return [];

      final data = snapshot.value as Map<dynamic, dynamic>;
      return data.entries.map((e) {
        final m = Map<String, dynamic>.from(e.value as Map);
        m['key'] = e.key.toString();
        return m;
      }).toList();
    } catch (e) {
      debugPrint('getSpreadsheetMembers: $e');
      return [];
    }
  }

  Future<List<Map<String, String>>> getOwnedSpreadsheetsRemote(
    String userEmail,
  ) async {
    final norm = _normalizeEmail(userEmail);
    if (norm.isEmpty) return [];
    try {
      final ref = _userOwnedSheetsRef(norm);
      final snapshot = await ref.get();
      if (!snapshot.exists || snapshot.value == null) return [];

      final data = snapshot.value as Map<dynamic, dynamic>;
      final out = <Map<String, String>>[];
      for (final e in data.entries) {
        final v = e.value as Map<dynamic, dynamic>;
        out.add({
          'id': e.key.toString(),
          'name': v['name']?.toString() ?? 'Sheet',
        });
      }
      return out;
    } catch (e) {
      debugPrint('getOwnedSpreadsheetsRemote: $e');
      return [];
    }
  }

  Future<List<Map<String, String>>> getSharedSpreadsheets(
    String userEmail,
  ) async {
    try {
      final ref = _getSharedSheetsRef(userEmail);
      final snapshot = await ref.get();
      if (!snapshot.exists || snapshot.value == null) return [];

      final data = snapshot.value as Map<dynamic, dynamic>;
      final sharedSheets = <Map<String, String>>[];

      for (final entry in data.entries) {
        final id = entry.key.toString();
        final value = entry.value as Map<dynamic, dynamic>;
        sharedSheets.add({
          'id': id,
          'name': value['name']?.toString() ?? 'Unnamed Shared Sheet',
        });
      }
      return sharedSheets;
    } catch (e) {
      debugPrint('Error getting shared spreadsheets: $e');
      return [];
    }
  }

  // Fetch list of paid by persons
  Future<List<String>> getPaidByPersons(String spreadsheetId) async {
    try {
      final ref = _getPaidByRef(spreadsheetId);
      final snapshot = await ref.get();

      if (snapshot.exists && snapshot.value != null) {
        final data = snapshot.value;
        if (data is Map) {
          // If stored as specific keys (e.g. push IDs)
          return data.values.map((e) => e.toString()).toList();
        } else if (data is List) {
          // If stored as a simple list
          return data.map((e) => e.toString()).toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching paid by persons from Firebase: $e');
      return [];
    }
  }

  // Add a new person to the list
  Future<bool> addPaidByPerson(String spreadsheetId, String personName) async {
    try {
      final persons = await getPaidByPersons(spreadsheetId);

      // Check if person already exists (case-insensitive check might be good, but strict for now matches previous behavior)
      if (persons.contains(personName)) {
        return false;
      }

      final ref = _getPaidByRef(spreadsheetId);
      // We can push a new node for the person
      await ref.push().set(personName);
      return true;
    } catch (e) {
      debugPrint('Error adding paid by person to Firebase: $e');
      return false;
    }
  }

  // --- Frequent Expense Items ---

  Future<List<FrequentExpenseItem>> getFrequentExpenseItems(
    String spreadsheetId,
  ) async {
    try {
      final ref = _getFrequentExpensesRef(spreadsheetId);
      final snapshot = await ref.get();

      if (!snapshot.exists || snapshot.value == null) return [];

      final data = snapshot.value as Map<dynamic, dynamic>;
      return data.entries.map((e) {
        return FrequentExpenseItem.fromMap(
          e.key.toString(),
          Map<dynamic, dynamic>.from(e.value as Map),
        );
      }).toList();
    } catch (e) {
      debugPrint('Error fetching frequent expense items: $e');
      return [];
    }
  }

  Future<String?> addFrequentExpenseItem(
    String spreadsheetId,
    FrequentExpenseItem item,
  ) async {
    try {
      final ref = _getFrequentExpensesRef(spreadsheetId);
      final newRef = ref.push();
      await newRef.set(item.toMap());
      return newRef.key;
    } catch (e) {
      debugPrint('Error adding frequent expense item: $e');
      return null;
    }
  }

  Future<bool> updateFrequentExpenseItem(
    String spreadsheetId,
    FrequentExpenseItem item,
  ) async {
    try {
      final ref = _getFrequentExpensesRef(spreadsheetId).child(item.id);
      await ref.update(item.toMap());
      return true;
    } catch (e) {
      debugPrint('Error updating frequent expense item: $e');
      return false;
    }
  }

  Future<bool> deleteFrequentExpenseItem(
    String spreadsheetId,
    String itemId,
  ) async {
    try {
      final ref = _getFrequentExpensesRef(spreadsheetId).child(itemId);
      await ref.remove();
      return true;
    } catch (e) {
      debugPrint('Error deleting frequent expense item: $e');
      return false;
    }
  }

  // --- Events (groups) ---
  // events/{eventId} = { name, notes, date, startDate, endDate }
  // events/{eventId}/expense_ids/{expenseId} = true
  // expense_events/{expenseId}/{eventId} = true (reverse index)

  Future<List<Event>> getEvents(String spreadsheetId) async {
    try {
      final ref = _getEventsRef(spreadsheetId);
      final snapshot = await ref.get();
      if (!snapshot.exists || snapshot.value == null) return [];

      final data = snapshot.value as Map<dynamic, dynamic>;
      final events = <Event>[];
      for (final entry in data.entries) {
        final key = entry.key.toString();
        final val = entry.value;
        if (val is Map) {
          final raw = Map<dynamic, dynamic>.from(val);
          final eventData = Map<dynamic, dynamic>.from(raw)
            ..remove('expense_ids');
          if (eventData.containsKey('name')) {
            events.add(Event.fromMap(key, eventData));
          }
        }
      }
      return events;
    } catch (e) {
      debugPrint('Error fetching events: $e');
      return [];
    }
  }

  Future<String?> addEvent(String spreadsheetId, Event event) async {
    try {
      final ref = _getEventsRef(spreadsheetId);
      final newRef = ref.push();
      final data = event.toMap();
      await newRef.set(data);
      return newRef.key;
    } catch (e) {
      debugPrint('Error adding event: $e');
      return null;
    }
  }

  Future<bool> updateEvent(String spreadsheetId, Event event) async {
    try {
      final ref = _getEventsRef(spreadsheetId).child(event.id);
      await ref.update(event.toMap());
      return true;
    } catch (e) {
      debugPrint('Error updating event: $e');
      return false;
    }
  }

  Future<bool> deleteEvent(String spreadsheetId, String eventId) async {
    try {
      final ref = _getEventsRef(spreadsheetId).child(eventId);
      await ref.remove();
      final expenseEventsRef = _getExpenseEventsRef(spreadsheetId);
      final snapshot = await expenseEventsRef.get();
      if (snapshot.exists && snapshot.value != null) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        for (final expenseId in data.keys) {
          await expenseEventsRef
              .child(expenseId.toString())
              .child(eventId)
              .remove();
        }
      }
      return true;
    } catch (e) {
      debugPrint('Error deleting event: $e');
      return false;
    }
  }

  Future<List<String>> getEventIdsForExpense(
    String spreadsheetId,
    String expenseId,
  ) async {
    try {
      final ref = _getExpenseEventsRef(spreadsheetId).child(expenseId);
      final snapshot = await ref.get();
      if (!snapshot.exists || snapshot.value == null) return [];
      final data = snapshot.value as Map<dynamic, dynamic>;
      return data.keys.map((e) => e.toString()).toList();
    } catch (e) {
      debugPrint('Error getting event ids for expense: $e');
      return [];
    }
  }

  /// Returns expense ids that are linked to the given event (from events/{eventId}/expense_ids).
  Future<List<String>> getExpenseIdsForEvent(
    String spreadsheetId,
    String eventId,
  ) async {
    try {
      final ref = _getEventsRef(
        spreadsheetId,
      ).child(eventId).child('expense_ids');
      final snapshot = await ref.get();
      if (!snapshot.exists || snapshot.value == null) return [];
      final data = snapshot.value as Map<dynamic, dynamic>;
      return data.keys.map((e) => e.toString()).toList();
    } catch (e) {
      debugPrint('Error getting expense ids for event: $e');
      return [];
    }
  }

  Future<bool> setExpenseEvents(
    String spreadsheetId,
    String expenseId,
    List<String> eventIds,
  ) async {
    try {
      final eventsRef = _getEventsRef(spreadsheetId);
      final expenseEventsRef = _getExpenseEventsRef(
        spreadsheetId,
      ).child(expenseId);

      final previousSnapshot = await expenseEventsRef.get();
      final previousIds = <String>{};
      if (previousSnapshot.exists && previousSnapshot.value != null) {
        final data = previousSnapshot.value as Map<dynamic, dynamic>;
        previousIds.addAll(data.keys.map((e) => e.toString()));
      }
      final newSet = eventIds.toSet();

      for (final eventId in previousIds) {
        if (!newSet.contains(eventId)) {
          await eventsRef
              .child(eventId)
              .child('expense_ids')
              .child(expenseId)
              .remove();
          await expenseEventsRef.child(eventId).remove();
        }
      }
      for (final eventId in newSet) {
        await eventsRef
            .child(eventId)
            .child('expense_ids')
            .child(expenseId)
            .set(true);
        await expenseEventsRef.child(eventId).set(true);
      }
      return true;
    } catch (e) {
      debugPrint('Error setting expense events: $e');
      return false;
    }
  }
}
