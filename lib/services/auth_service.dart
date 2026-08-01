import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart' show PlatformException;
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';

/// A sign-in failure with a message that is safe to show to the user directly.
///
/// Google Sign-In on Android fails for a handful of genuinely different
/// reasons, and the platform reports most of them as an opaque
/// `PlatformException`. Collapsing them all into "Google Sign-In failed"
/// makes a misconfigured SHA-1 (which needs a Firebase Console change)
/// indistinguishable from flaky wifi (which needs nothing). [code] is
/// retained for logging; [message] is what the UI shows.
class AuthFailure implements Exception {
  final String message;
  final String code;
  const AuthFailure(this.code, this.message);
  @override
  String toString() => '$code: $message';
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  User? get currentUser => _auth.currentUser;

  // ✅ NEW: Get current user ID easily
  String? get currentUserId => _auth.currentUser?.uid;

  /// Sentinel used to signal "the user backed out of the Google chooser".
  /// This is not an error and must not surface a message.
  static const cancelledCode = 'cancelled';

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
      }

      // ── Mobile flow ───────────────────────────────────────────────
      // Sign out of the Google SDK first so the account chooser always
      // appears rather than silently reusing the last account.
      try {
        await _googleSignIn.signOut();
      } catch (_) {
        // A failed pre-emptive sign-out must not block a fresh sign-in.
      }

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      // Null means the user dismissed the account picker.
      if (googleUser == null) {
        throw const AuthFailure(cancelledCode, 'Sign-in cancelled.');
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Firebase requires the idToken. If Google returns an account but no
      // idToken, the OAuth client is misconfigured — surface that plainly
      // instead of letting Firebase reject a null credential later.
      if (googleAuth.idToken == null) {
        throw const AuthFailure(
          'missing-id-token',
          'Google did not return a sign-in token. '
              'The app\'s Google configuration is incomplete.',
        );
      }

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
          await _auth.signInWithCredential(credential);
      return userCredential.user;
    } on AuthFailure {
      rethrow;
    } on PlatformException catch (e) {
      debugPrint('Google Auth PlatformException: ${e.code} ${e.message}');
      throw AuthFailure(e.code, _googleErrorMessage(e));
    } on FirebaseAuthException catch (e) {
      debugPrint('Google Auth FirebaseAuthException: ${e.code}');
      throw AuthFailure(e.code, _firebaseGoogleMessage(e));
    } catch (e) {
      debugPrint('Google Auth Error: ${e.runtimeType} $e');
      throw const AuthFailure(
        'unknown',
        'Google Sign-In failed. Please try again.',
      );
    }
  }

  /// Maps a `google_sign_in` platform error to an actionable message.
  ///
  /// Code `10` is DEVELOPER_ERROR: the SHA-1 of the certificate signing this
  /// build is not registered against this package name in the Firebase
  /// project, so Play Services refuses the request. It is by far the most
  /// common cause and no amount of retrying fixes it, so the message says so
  /// rather than inviting the user to try again forever.
  static String _googleErrorMessage(PlatformException e) {
    switch (e.code) {
      case 'sign_in_canceled':
      case 'sign_in_cancelled':
        return 'Sign-in cancelled.';
      case 'network_error':
        return 'Network error during Google Sign-In. Check your connection.';
      case 'sign_in_required':
        return 'No Google account available. Add one in device settings.';
      case '10':
      case 'sign_in_failed':
        // The raw message usually embeds the ApiException status code.
        if (e.message?.contains('10:') == true ||
            e.message?.contains('DEVELOPER_ERROR') == true ||
            e.code == '10') {
          return 'Google Sign-In is not configured for this build '
              '(certificate not registered). Please use email sign-in, '
              'or reinstall the official release.';
        }
        if (e.message?.contains('12500') == true) {
          return 'Google Play Services needs an update on this device.';
        }
        if (e.message?.contains('7:') == true) {
          return 'Network error during Google Sign-In. Check your connection.';
        }
        return 'Google Sign-In failed. Please try again.';
      default:
        return 'Google Sign-In failed. Please try again.';
    }
  }

  static String _firebaseGoogleMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'account-exists-with-different-credential':
        return 'An account already exists with this email. '
            'Sign in with your email and password instead.';
      case 'invalid-credential':
        return 'Google rejected the sign-in token. Please try again.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'operation-not-allowed':
        return 'Google Sign-In is not enabled for this app.';
      default:
        return e.message ?? 'Google Sign-In failed. Please try again.';
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
        // Re-check against the server before rejecting: `emailVerified` on a
        // cached user object can be stale if they verified on another device
        // since the token was minted.
        try {
          await user.reload();
        } catch (_) {
          // If the refresh fails, fall through to the cached value.
        }
        final refreshed = _auth.currentUser;
        if (refreshed != null && !refreshed.emailVerified) {
          // Send a fresh verification link before signing out, so the user has
          // something actionable rather than a dead end. Best-effort: a
          // throttled send must not mask the real reason for the rejection.
          try {
            await refreshed.sendEmailVerification();
          } catch (_) {}
          await _auth.signOut();
          throw FirebaseAuthException(
            code: 'email-not-verified',
            message: 'Please verify your email before logging in. '
                'We just sent a new verification link to ${email.trim()}.',
          );
        }
        return refreshed;
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
  //
  /// Local data is wiped so one account's attendance cannot leak into the next
  /// account signed in on this device. That wipe is destructive, so the caller
  /// is expected to have flushed anything unsynced to the cloud first — see
  /// the backup step in the profile screen's sign-out handler. Guests have no
  /// cloud copy by definition, so their data is genuinely gone; the UI warns
  /// them before calling this.
  Future<void> signOut() async {
    // Sign out of the identity providers FIRST. If this fails we must not have
    // already destroyed the local data, or the user is left signed in with an
    // empty database and no way to recover it.
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint('Google sign-out failed: ${e.runtimeType}');
    }
    await _auth.signOut();

    // ── WIPE LOCAL DATA TO PREVENT LEAKING BETWEEN ACCOUNTS ──
    try {
      if (!kIsWeb) {
        final db = await DBHelper.instance.database;
        await db.delete('attendance_records');
        await db.delete('timetable');
        await db.delete('subjects');
        await db.delete('imported_report_dates');
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (e) {
      debugPrint('Failed to wipe local data on logout: ${e.runtimeType}');
    }
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