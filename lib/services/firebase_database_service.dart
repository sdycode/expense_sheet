import 'package:expensesheet/models/event.dart';
import 'package:expensesheet/models/frequent_expense_item.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class FirebaseDatabaseService {
  final FirebaseDatabase _database = FirebaseDatabase.instance;

  // Sanitize email to be safe for Firebase path (replace . with ,)
  String _sanitizeEmail(String email) {
    return email.replaceAll('.', ',');
  }

  // Get reference to the paid_by node for a specific user
  DatabaseReference _getPaidByRef(String userEmail) {
    final sanitizedEmail = _sanitizeEmail(userEmail);
    return _database.ref().child('expenseSheet/$sanitizedEmail/paid_by');
  }

  // Get reference to frequent_expenses for a user
  DatabaseReference _getFrequentExpensesRef(String userEmail) {
    final sanitizedEmail = _sanitizeEmail(userEmail);
    return _database.ref().child('expenseSheet/$sanitizedEmail/frequent_expenses');
  }

  DatabaseReference _getEventsRef(String userEmail) {
    final sanitizedEmail = _sanitizeEmail(userEmail);
    return _database.ref().child('expenseSheet/$sanitizedEmail/events');
  }

  DatabaseReference _getExpenseEventsRef(String userEmail) {
    final sanitizedEmail = _sanitizeEmail(userEmail);
    return _database.ref().child('expenseSheet/$sanitizedEmail/expense_events');
  }

  // Fetch list of paid by persons
  Future<List<String>> getPaidByPersons(String userEmail) async {
    try {
      final ref = _getPaidByRef(userEmail);
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
  Future<bool> addPaidByPerson(String userEmail, String personName) async {
    try {
      final persons = await getPaidByPersons(userEmail);

      // Check if person already exists (case-insensitive check might be good, but strict for now matches previous behavior)
      if (persons.contains(personName)) {
        return false;
      }

      final ref = _getPaidByRef(userEmail);
      // We can push a new node for the person
      await ref.push().set(personName);
      return true;
    } catch (e) {
      debugPrint('Error adding paid by person to Firebase: $e');
      return false;
    }
  }

  // --- Frequent Expense Items ---

  Future<List<FrequentExpenseItem>> getFrequentExpenseItems(String userEmail) async {
    try {
      final ref = _getFrequentExpensesRef(userEmail);
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

  Future<String?> addFrequentExpenseItem(String userEmail, FrequentExpenseItem item) async {
    try {
      final ref = _getFrequentExpensesRef(userEmail);
      final newRef = ref.push();
      await newRef.set(item.toMap());
      return newRef.key;
    } catch (e) {
      debugPrint('Error adding frequent expense item: $e');
      return null;
    }
  }

  Future<bool> updateFrequentExpenseItem(String userEmail, FrequentExpenseItem item) async {
    try {
      final ref = _getFrequentExpensesRef(userEmail).child(item.id);
      await ref.update(item.toMap());
      return true;
    } catch (e) {
      debugPrint('Error updating frequent expense item: $e');
      return false;
    }
  }

  Future<bool> deleteFrequentExpenseItem(String userEmail, String itemId) async {
    try {
      final ref = _getFrequentExpensesRef(userEmail).child(itemId);
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

  Future<List<Event>> getEvents(String userEmail) async {
    try {
      final ref = _getEventsRef(userEmail);
      final snapshot = await ref.get();
      if (!snapshot.exists || snapshot.value == null) return [];

      final data = snapshot.value as Map<dynamic, dynamic>;
      final events = <Event>[];
      for (final entry in data.entries) {
        final key = entry.key.toString();
        final val = entry.value;
        if (val is Map) {
          final raw = Map<dynamic, dynamic>.from(val as Map);
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

  Future<String?> addEvent(String userEmail, Event event) async {
    try {
      final ref = _getEventsRef(userEmail);
      final newRef = ref.push();
      final data = event.toMap();
      await newRef.set(data);
      return newRef.key;
    } catch (e) {
      debugPrint('Error adding event: $e');
      return null;
    }
  }

  Future<bool> updateEvent(String userEmail, Event event) async {
    try {
      final ref = _getEventsRef(userEmail).child(event.id);
      await ref.update(event.toMap());
      return true;
    } catch (e) {
      debugPrint('Error updating event: $e');
      return false;
    }
  }

  Future<bool> deleteEvent(String userEmail, String eventId) async {
    try {
      final ref = _getEventsRef(userEmail).child(eventId);
      await ref.remove();
      final expenseEventsRef = _getExpenseEventsRef(userEmail);
      final snapshot = await expenseEventsRef.get();
      if (snapshot.exists && snapshot.value != null) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        for (final expenseId in data.keys) {
          await expenseEventsRef.child(expenseId.toString()).child(eventId).remove();
        }
      }
      return true;
    } catch (e) {
      debugPrint('Error deleting event: $e');
      return false;
    }
  }

  Future<List<String>> getEventIdsForExpense(String userEmail, String expenseId) async {
    try {
      final ref = _getExpenseEventsRef(userEmail).child(expenseId);
      final snapshot = await ref.get();
      if (!snapshot.exists || snapshot.value == null) return [];
      final data = snapshot.value as Map<dynamic, dynamic>;
      return data.keys.map((e) => e.toString()).toList();
    } catch (e) {
      debugPrint('Error getting event ids for expense: $e');
      return [];
    }
  }

  Future<bool> setExpenseEvents(String userEmail, String expenseId, List<String> eventIds) async {
    try {
      final eventsRef = _getEventsRef(userEmail);
      final expenseEventsRef = _getExpenseEventsRef(userEmail).child(expenseId);

      final previousSnapshot = await expenseEventsRef.get();
      final previousIds = <String>{};
      if (previousSnapshot.exists && previousSnapshot.value != null) {
        final data = previousSnapshot.value as Map<dynamic, dynamic>;
        previousIds.addAll(data.keys.map((e) => e.toString()));
      }
      final newSet = eventIds.toSet();

      for (final eventId in previousIds) {
        if (!newSet.contains(eventId)) {
          await eventsRef.child(eventId).child('expense_ids').child(expenseId).remove();
          await expenseEventsRef.child(eventId).remove();
        }
      }
      for (final eventId in newSet) {
        await eventsRef.child(eventId).child('expense_ids').child(expenseId).set(true);
        await expenseEventsRef.child(eventId).set(true);
      }
      return true;
    } catch (e) {
      debugPrint('Error setting expense events: $e');
      return false;
    }
  }
}
