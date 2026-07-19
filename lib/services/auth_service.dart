import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  User? get currentUser => _auth.currentUser;

  // ✅ NEW: Get current user ID easily
  String? get currentUserId => _auth.currentUser?.uid;

  // 1. SIGN IN WITH GOOGLE
  Future<User?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        // Use Firebase native web popup flow
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        // Force account selection every time
        googleProvider.setCustomParameters({'prompt': 'select_account'});
        final UserCredential userCredential = await _auth.signInWithPopup(googleProvider);
        return userCredential.user;
      } else {
        // Mobile Flow
        // Force logout first so it doesn't auto-login to the previous account
        await _googleSignIn.signOut();
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
        if (googleUser == null) return null;

        final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        final UserCredential userCredential = await _auth.signInWithCredential(
          credential,
        );
        return userCredential.user;
      }
    } catch (e) {
      debugPrint("Google Auth Error: ${e.runtimeType}");
      rethrow;
    }
  }

  // 2. SIGN IN WITH EMAIL & PASSWORD
  Future<User?> signInWithEmail(String email, String password) async {
    try {
      final UserCredential userCredential = await _auth
          .signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = userCredential.user;
      if (user != null && !user.emailVerified) {
        await _auth.signOut();
        throw FirebaseAuthException(
          code: 'email-not-verified',
          message: 'Please verify your email before logging in.',
        );
      }
      return user;
    } catch (e) {
      debugPrint("Email Login Error: ${e.runtimeType}");
      rethrow;
    }
  }

  // 3. SIGN UP WITH NEW EMAIL & PASSWORD
  Future<User?> signUpWithEmail(String email, String password) async {
    try {
      final UserCredential userCredential = await _auth
          .createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      // Automatically send a verification email
      await userCredential.user?.sendEmailVerification();

      return userCredential.user;
    } catch (e) {
      debugPrint("Email Signup Error: ${e.runtimeType}");
      rethrow;
    }
  }

  // 4. FORGOT PASSWORD
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } catch (e) {
      debugPrint("Password Reset Error: ${e.runtimeType}");
      rethrow;
    }
  }

  // 5. SIGN OUT
  Future<void> signOut() async {
    // ── WIPE LOCAL DATA TO PREVENT LEAKING BETWEEN ACCOUNTS ──
    try {
      if (!kIsWeb) {
        final db = await DBHelper.instance.database;
        await db.delete('attendance_records');
        await db.delete('timetable');
        await db.delete('subjects');
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (e) {
      debugPrint('Failed to wipe local data on logout: ${e.runtimeType}');
    }

    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  // 6. ✅ NEW: SIGN IN ANONYMOUSLY (GUEST MODE)
  Future<User?> signInGuest() async {
    try {
      // Check if they are already logged in from a previous session
      if (_auth.currentUser != null) {
        return _auth.currentUser;
      }

      // If not, create a new anonymous guest account
      UserCredential result = await _auth.signInAnonymously();
      return result.user;
    } catch (e) {
      debugPrint("Error signing in anonymously: ${e.runtimeType}");
      return null;
    }
  }
}