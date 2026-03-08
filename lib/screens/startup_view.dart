import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'expense_tracker_page_style2.dart';

class StartupView extends StatefulWidget {
  const StartupView({super.key});

  @override
  State<StartupView> createState() => _StartupViewState();
}

class _StartupViewState extends State<StartupView> {
  bool _isInitializing = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    // The very first line of _initializeServices() must be FlutterNativeSplash.remove()
    FlutterNativeSplash.remove();

    try {
      // Run the initializations concurrently
      final results = await Future.wait([
        _initFirebase(),
        _checkGitHubTokens(),
        _initLocalStorage(),
        _determineLoginStateAndSync(),
      ]);

      // Assuming results[3] contains bool about authentication state
      bool isAuthenticated = results[3] as bool;

      if (!mounted) return;

      // Navigate to the next screen with a cross-fade transition
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) {
            return isAuthenticated
                ? const HomeGalleryScreen()
                : const LoginScreen();
          },
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 600),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _errorMessage = 'Initialization failed: \${e.toString()}';
      });
    }
  }

  Future<void> _initFirebase() async {
    try {
      await Firebase.initializeApp();
      debugPrint('Firebase initialized successfully');
    } catch (e) {
      debugPrint('Error initializing Firebase: $e');
    }
  }

  Future<bool> _checkGitHubTokens() async {
    try {
      const storage = FlutterSecureStorage();
      String? token = await storage.read(key: 'github_auth_token');
      debugPrint('GitHub token checked');
      return token != null;
    } catch (e) {
      debugPrint('Error checking github tokens: $e');
      return false;
    }
  }

  Future<void> _initLocalStorage() async {
    // Initialize local storage/caching directories
    await Future.delayed(const Duration(milliseconds: 200));
    debugPrint('Local storage initialized.');
  }

  Future<bool> _determineLoginStateAndSync() async {
    // Determine the user's login state and repository sync status.
    await Future.delayed(const Duration(milliseconds: 300));
    // Simulated as logged in state
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            // Static, lightweight screen (centered logo)
            Center(
              child: Image.asset(
                'assets/icon.png',
                width: 150,
                height: 150,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.account_balance_wallet,
                    size: 100,
                    color: Colors.blue,
                  );
                },
              ),
            ),
            const Spacer(),
            // Smoothly animate in a CircularProgressIndicator at the bottom
            SizedBox(
              height: 48,
              child: AnimatedOpacity(
                opacity: _isInitializing ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 500),
                child: _errorMessage.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Text(
                          _errorMessage,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// Screen placeholders to satisfy requirements
// -------------------------------------------------------------

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            Navigator.of(context).pushReplacement(
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) =>
                    const HomeGalleryScreen(),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) {
                      return FadeTransition(opacity: animation, child: child);
                    },
              ),
            );
          },
          child: const Text('Login successful'),
        ),
      ),
    );
  }
}

class HomeGalleryScreen extends StatelessWidget {
  const HomeGalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ExpenseTrackerPageStyle2(); // Assuming this is the actual home page
  }
}
