import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  User? get currentUser => _auth.currentUser;

  // ✅ NEW: Get current user ID easily
  String? get currentUserId => _auth.currentUser?.uid;

  // 1. SIGN IN WITH GOOGLE
  Future<User?> signInWithGoogle() async {
    try {
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
    } catch (e) {
      print("Google Auth Error: $e");
      return null;
    }
  }

  // 2. SIGN IN WITH EMAIL & PASSWORD
  Future<User?> signInWithEmail(String email, String password) async {
    try {
      final UserCredential userCredential = await _auth
          .signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      return userCredential.user;
    } catch (e) {
      print("Email Login Error: $e");
      throw e;
    }
  }

  // 3. SIGN UP WITH NEW EMAIL & PASSWORD
  Future<User?> signUpWithEmail(String email, String password) async {
    try {
      final UserCredential userCredential = await _auth
          .createUserWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      // Automatically send a verification email
      await userCredential.user?.sendEmailVerification();

      return userCredential.user;
    } catch (e) {
      print("Email Signup Error: $e");
      throw e;
    }
  }

  // 4. FORGOT PASSWORD
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } catch (e) {
      print("Password Reset Error: $e");
      throw e;
    }
  }

  // 5. SIGN OUT
  Future<void> signOut() async {
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
      print("Error signing in anonymously: $e");
      return null;
    }
  }
}