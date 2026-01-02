import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleSignInService {
  static final GoogleSignInService _instance = GoogleSignInService._internal();
  factory GoogleSignInService() => _instance;
  GoogleSignInService._internal();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'https://www.googleapis.com/auth/spreadsheets',
    ],
  );

  GoogleSignInAccount? _currentUser;

  GoogleSignInAccount? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;

  Future<SignInResult> signIn() async {
    try {
      debugPrint('GoogleSignInService: Attempting to sign in...');
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account != null) {
        _currentUser = account;
        debugPrint('GoogleSignInService: Sign in successful for ${account.email}');
        return SignInResult.success(account);
      } else {
        debugPrint('GoogleSignInService: Sign in cancelled by user');
        return SignInResult.cancelled();
      }
    } catch (e, stackTrace) {
      debugPrint('GoogleSignInService: Error signing in: $e');
      debugPrint('GoogleSignInService: Stack trace: $stackTrace');
      return SignInResult.error(e.toString());
    }
  }

  Future<void> signOut() async {
    try {
      debugPrint('GoogleSignInService: Signing out...');
      await _googleSignIn.signOut();
      _currentUser = null;
      debugPrint('GoogleSignInService: Sign out successful');
    } catch (e, stackTrace) {
      debugPrint('GoogleSignInService: Error signing out: $e');
      debugPrint('GoogleSignInService: Stack trace: $stackTrace');
    }
  }
}

class SignInResult {
  final bool isSuccess;
  final bool isCancelled;
  final String? errorMessage;
  final GoogleSignInAccount? account;

  SignInResult.success(this.account)
      : isSuccess = true,
        isCancelled = false,
        errorMessage = null;

  SignInResult.cancelled()
      : isSuccess = false,
        isCancelled = true,
        errorMessage = null,
        account = null;

  SignInResult.error(this.errorMessage)
      : isSuccess = false,
        isCancelled = false,
        account = null;
}

