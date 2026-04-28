import 'package:flutter/material.dart';
import 'package:flutter_gemma/core/api/flutter_gemma.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import 'package:MoneyTracker/screens/startup_view.dart';
import 'package:MoneyTracker/services/theme_preference_service.dart';
import 'package:MoneyTracker/theme/app_themes.dart';
import 'package:MoneyTracker/features/ai_extractor/providers/ai_extractor_provider.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
 
   await FlutterGemma.initialize();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  await ThemePreferenceService.instance.load();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AIExtractorProvider()..init()),
      ],
      child: const MyApp(),
    ),
  );
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
          theme: AppThemes.light(seedColor: svc.sharedColor),
          darkTheme: AppThemes.dark(seedColor: svc.sharedColor),
          home: const StartupView(),
        );
      },
    );
  }
}
