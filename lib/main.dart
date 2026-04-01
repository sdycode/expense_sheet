import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:MoneyTracker/screens/startup_view.dart';
import 'package:MoneyTracker/services/theme_preference_service.dart';
import 'package:MoneyTracker/theme/app_themes.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  await ThemePreferenceService.instance.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemePreferenceService.instance,
      builder: (context, _) {
        final svc = ThemePreferenceService.instance;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Expense Tracker',
          themeMode: svc.themeMode,
          theme: AppThemes.light(),
          darkTheme: AppThemes.dark(),
          home: const StartupView(),
        );
      },
    );
  }
}
