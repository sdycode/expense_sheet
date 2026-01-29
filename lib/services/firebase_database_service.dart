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
}
