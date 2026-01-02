import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class FirebaseAuthService {
  static final FirebaseAuthService _instance = FirebaseAuthService._internal();
  factory FirebaseAuthService() => _instance;
  FirebaseAuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'https://www.googleapis.com/auth/spreadsheets',
    ],
  );

  User? get currentUser => _auth.currentUser;
  bool get isSignedIn => _auth.currentUser != null;
  String? get userEmail => _auth.currentUser?.email;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<SignInResult> signInWithGoogle() async {
    try {
      debugPrint('FirebaseAuthService: Starting Google Sign-In...');

      // Trigger the authentication flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        debugPrint('FirebaseAuthService: Sign in cancelled by user');
        return SignInResult.cancelled();
      }

      debugPrint('FirebaseAuthService: Google account selected: ${googleUser.email}');

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      debugPrint('FirebaseAuthService: Got Google authentication tokens');

      // Create a new credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      debugPrint('FirebaseAuthService: Created Firebase credential');

      // Sign in to Firebase with the Google credential
      final UserCredential userCredential =
          await _auth.signInWithCredential(credential);

      debugPrint(
        'FirebaseAuthService: Firebase sign-in successful for ${userCredential.user?.email}',
      );

      // Store Google account for Sheets API access
      return SignInResult.success(
        userCredential.user,
        googleUser,
        googleAuth.accessToken,
      );
    } on FirebaseAuthException catch (e) {
      debugPrint('FirebaseAuthService: Firebase Auth error: ${e.code} - ${e.message}');
      return SignInResult.error('Firebase Auth Error: ${e.message ?? e.code}');
    } catch (e, stackTrace) {
      debugPrint('FirebaseAuthService: Error signing in: $e');
      debugPrint('FirebaseAuthService: Stack trace: $stackTrace');
      return SignInResult.error(e.toString());
    }
  }

  Future<void> signOut() async {
    try {
      debugPrint('FirebaseAuthService: Signing out...');
      await Future.wait([
        _auth.signOut(),
        _googleSignIn.signOut(),
      ]);
      debugPrint('FirebaseAuthService: Sign out successful');
    } catch (e, stackTrace) {
      debugPrint('FirebaseAuthService: Error signing out: $e');
      debugPrint('FirebaseAuthService: Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<String?> getIdToken() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;
      return await user.getIdToken();
    } catch (e) {
      debugPrint('FirebaseAuthService: Error getting ID token: $e');
      return null;
    }
  }

  Future<String?> getAccessToken() async {
    try {
      // Get the current user
      final user = _auth.currentUser;
      if (user == null) return null;

      // Get the Google Sign-In account to retrieve access token
      final GoogleSignInAccount? googleAccount = await _googleSignIn.signInSilently();
      if (googleAccount == null) return null;

      final GoogleSignInAuthentication googleAuth = await googleAccount.authentication;
      return googleAuth.accessToken;
    } catch (e) {
      debugPrint('FirebaseAuthService: Error getting access token: $e');
      return null;
    }
  }
}

class SignInResult {
  final bool isSuccess;
  final bool isCancelled;
  final String? errorMessage;
  final User? firebaseUser;
  final GoogleSignInAccount? googleAccount;
  final String? accessToken;

  SignInResult.success(
    this.firebaseUser,
    this.googleAccount,
    this.accessToken,
  )   : isSuccess = true,
        isCancelled = false,
        errorMessage = null;

  SignInResult.cancelled()
      : isSuccess = false,
        isCancelled = true,
        errorMessage = null,
        firebaseUser = null,
        googleAccount = null,
        accessToken = null;

  SignInResult.error(this.errorMessage)
      : isSuccess = false,
        isCancelled = false,
        firebaseUser = null,
        googleAccount = null,
        accessToken = null;
}

