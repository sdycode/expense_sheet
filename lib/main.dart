import 'package:expensesheet/screens/ExpenseTrackerPage.dart';
import 'package:expensesheet/screens/expense_tracker_page_style2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'models/expense.dart';
import 'services/firebase_auth_service.dart';
import 'services/google_sheets_service.dart';
import 'services/spreadsheet_storage_service.dart';
import 'services/firebase_database_service.dart';
import 'screens/121212.dart';
import 'utils/expense_categories.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    debugPrint('Firebase initialized successfully');
  } catch (e) {
    debugPrint('Error initializing Firebase: $e');
    debugPrint('Make sure you have:');
    debugPrint('1. Added google-services.json to android/app/');
    debugPrint('2. Updated firebase_options.dart with your Firebase config');
    debugPrint('3. OR run: flutterfire configure');
    // Continue anyway - Firebase might work if configured correctly
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Expense Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        dropdownMenuTheme: const DropdownMenuThemeData(
          textStyle: TextStyle(color: Colors.black),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          labelStyle: TextStyle(color: Colors.black87),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.black),
          bodyMedium: TextStyle(color: Colors.black),
          bodySmall: TextStyle(color: Colors.black),
        ),
      ),
      home: const ExpenseTrackerPageStyle2(),
    );
  }
}
