import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../../database/db_helper.dart';
import '../../services/auth_service.dart';
import '../../services/cloud_sync_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/container_transform.dart';
import '../../utils/db_utils.dart';
import 'package:go_router/go_router.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  final CloudSyncService _syncService = CloudSyncService();

  bool _isLoading = false;
  bool _obscurePassword = true;

  // ── Login throttling ──────────────────────────────────────
  static const int _maxAttempts = 5;
  static const int _lockoutSeconds = 60;
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;
  Timer? _lockoutTimer;
  int _lockoutRemaining = 0;

  bool get _isLockedOut =>
      _lockoutUntil != null && DateTime.now().isBefore(_lockoutUntil!);

  void _startLockout() {
    _lockoutUntil = DateTime.now().add(const Duration(seconds: _lockoutSeconds));
    _lockoutRemaining = _lockoutSeconds;
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() {
        _lockoutRemaining--;
        if (_lockoutRemaining <= 0) {
          _lockoutUntil = null;
          _failedAttempts = 0;
          timer.cancel();
        }
      });
    });
  }

  void _recordFailedAttempt() {
    _failedAttempts++;
    if (_failedAttempts >= _maxAttempts) {
      _startLockout();
    }
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handlePostLogin(User? user) async {
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    final creationTime = user.metadata.creationTime;
    final lastSignIn = user.metadata.lastSignInTime;
    bool isBrandNewUser = false;

    if (user.isAnonymous && creationTime != null) {
      final daysSinceCreation = DateTime.now().difference(creationTime).inDays;
      if (daysSinceCreation >= 30) {
        try {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();
          await user.delete();
          await _authService.signOut();
          
          final prefs = await SharedPreferences.getInstance();
          await prefs.clear();

          if (!kIsWeb) {
            final db = await DBHelper.instance.database;
            await db.delete('attendance_records');
            await db.delete('timetable');
            await db.delete('subjects');
          }
        } catch (_) {}
        
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Guest session expired (>30 days). Your local data was deleted.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }
    }

    if (creationTime != null && lastSignIn != null) {
      final difference = lastSignIn.difference(creationTime).inSeconds.abs();
      isBrandNewUser = difference < 5;
    }

    if (isBrandNewUser) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      context.go('/setup');
      return;
    }

    bool hasRestored = await _syncService.restoreDataFromCloud();

    // Check for pending email transfer data (from "Change Email" flow)
    if (!hasRestored && user.email != null) {
      try {
        final transferId = user.uid; // Secured: lookup by UID
        final transferDoc = await FirebaseFirestore.instance
            .collection('data_transfers')
            .doc(transferId)
            .get();

        if (transferDoc.exists && transferDoc.data() != null) {
          final data = transferDoc.data()!;
          final db = kIsWeb ? null : await DBHelper.instance.database;
          final prefs = await SharedPreferences.getInstance();

          // Restore SharedPreferences
          final Map<String, dynamic> prefsData = data['preferences'] ?? {};
          for (var entry in prefsData.entries) {
            final value = entry.value;
            if (value is String) {
              await prefs.setString(entry.key, value);
            } else if (value is bool) {
              await prefs.setBool(entry.key, value);
            } else if (value is int) {
              await prefs.setInt(entry.key, value);
            } else if (value is double) {
              await prefs.setDouble(entry.key, value);
            } else if (value is num) {
              if (value == value.toInt()) {
                await prefs.setInt(entry.key, value.toInt());
              } else {
                await prefs.setDouble(entry.key, value.toDouble());
              }
            }
          }

          // Restore SQLite data (sanitize Firestore num types)
          if (!kIsWeb && db != null) {
            await db.delete('subjects');
            await db.delete('timetable');
            await db.delete('attendance_records');

            for (var row in (data['subjects'] as List<dynamic>? ?? [])) {
              await db.insert('subjects', DbUtils.sanitizeRow(Map<String, dynamic>.from(row)),
                  conflictAlgorithm: ConflictAlgorithm.replace);
            }
            for (var row in (data['timetable'] as List<dynamic>? ?? [])) {
              await db.insert('timetable', DbUtils.sanitizeRow(Map<String, dynamic>.from(row)),
                  conflictAlgorithm: ConflictAlgorithm.replace);
            }
            for (var row in (data['attendance_records'] as List<dynamic>? ?? [])) {
              await db.insert('attendance_records', DbUtils.sanitizeRow(Map<String, dynamic>.from(row)),
                  conflictAlgorithm: ConflictAlgorithm.replace);
            }
          }

          // Also backup to the new user's Firestore doc so future logins work
          await _syncService.backupDataToCloud();

          // Delete the transfer document — it's been consumed
          await FirebaseFirestore.instance
              .collection('data_transfers')
              .doc(transferId)
              .delete();

          hasRestored = true;
        }
      } catch (e) {
        debugPrint('Transfer restore error: $e');
      }
    }

    // Also check if local data already exists on this device
    bool hasLocalData = false;
    if (!hasRestored && !kIsWeb) {
      try {
        final db = await DBHelper.instance.database;
        final subjects = await db.query('subjects', limit: 1);
        hasLocalData = subjects.isNotEmpty;
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (hasRestored || hasLocalData) {
      context.go('/app/dashboard');
    } else {
      context.go('/setup');
    }
  }

  Future<void> _loginWithEmail() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter both your email and password.'),
        ),
      );
      return;
    }

    if (!kIsWeb) {
      final List<ConnectivityResult> connectivityResult = await (Connectivity()
          .checkConnectivity());
      if (connectivityResult.contains(ConnectivityResult.none)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No internet connection. Please connect to log in.'),
            ),
          );
        }
        return;
      }
    }

    setState(() => _isLoading = true);
    try {
      User? user = await _authService.signInWithEmail(
        _emailController.text.trim(),
        _passwordController.text,
      );
      _failedAttempts = 0; // Reset on success
      await _handlePostLogin(user);
    } on FirebaseAuthException catch (e) {
      setState(() => _isLoading = false);
      _recordFailedAttempt();

      String errorMessage = 'An error occurred. Please try again.';

      if (e.code == 'user-not-found' ||
          e.code == 'wrong-password' ||
          e.code == 'invalid-credential') {
        errorMessage = 'Email or password incorrect please verify.';
      } else if (e.code == 'invalid-email') {
        errorMessage = 'The email address is not formatted correctly.';
      } else {
        errorMessage = e.message ?? errorMessage;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red.shade600,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Login failed. Please try again.')),
        );
      }
    }
  }

  Future<void> _loginWithGoogle() async {
    if (!kIsWeb) {
      final List<ConnectivityResult> connectivityResult = await (Connectivity()
          .checkConnectivity());
      if (connectivityResult.contains(ConnectivityResult.none)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No internet connection. Please connect to log in.'),
            ),
          );
        }
        return;
      }
    }

    setState(() => _isLoading = true);
    try {
      User? user = await _authService.signInWithGoogle();
      await _handlePostLogin(user);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google Sign-In failed. Please try again.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  // ✅ NEW: Guest Login Logic
  Future<void> _loginAsGuest() async {
    if (!kIsWeb) {
      final List<ConnectivityResult> connectivityResult = await (Connectivity()
          .checkConnectivity());
      if (connectivityResult.contains(ConnectivityResult.none)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No internet connection. Please connect to log in.'),
            ),
          );
        }
        return;
      }
    }

    setState(() => _isLoading = true);
    try {
      User? user = await _authService.signInGuest();
      await _handlePostLogin(user); // Routes them properly!
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Guest Login failed. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: MediaQuery.of(context).size.width > 600 ? 40 : 24,
                  vertical: 32, // Add top padding to prevent hugging the top edge
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Image.asset(
                        'assets/icon/app_icon2.png',
                        height: 88,
                        width: 88,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 20),

                    Text(
                      'Welcome to AttendEase',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Log in to sync and manage your attendance',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.textTheme.bodyMedium?.color,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 48),

                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          ),
                          tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                    ),

                    Align(
                      alignment: Alignment.centerRight,
                      child: ContainerTransformAnchor(
                        borderRadius: AppDimens.radiusSm,
                        child: TextButton(
                          onPressed: () {
                            context.push('/forgot-password');
                          },
                          child: Text(
                            'Forgot Password?',
                            style: TextStyle(color: theme.colorScheme.primary),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLockedOut ? null : _loginWithEmail,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : _isLockedOut
                                ? Text('Try again in ${_lockoutRemaining}s')
                                : const Text('Log In'),
                      ),
                    ),
                    const SizedBox(height: 24),

                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'OR',
                            style: TextStyle(
                              color: theme.textTheme.bodyMedium?.color,
                            ),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 24),

                    OutlinedButton.icon(
                      onPressed: _loginWithGoogle,
                      icon: Image.asset(
                        'assets/icon/google_logo.png',
                        height: 24,
                      ),
                      label: Text(
                        'Continue with Google',
                        style: TextStyle(
                          color: theme.textTheme.bodyLarge?.color,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: theme.dividerColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 🔥 NEW: Continue as Guest Button 🔥
                    OutlinedButton.icon(
                      onPressed: _loginAsGuest,
                      icon: Icon(
                        Icons.person_outline_rounded,
                        color: theme.colorScheme.primary,
                        size: 24,
                      ),
                      label: Text(
                        'Continue as Guest',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(
                            color: theme.colorScheme.primary.withAlpha(100),
                            width: 1.5
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Don't have an account?",
                          style: TextStyle(
                            color: theme.textTheme.bodyMedium?.color,
                          ),
                        ),
                        ContainerTransformAnchor(
                          borderRadius: AppDimens.radiusSm,
                          child: TextButton(
                            onPressed: () => context.push('/signup'),
                            child: Text(
                              'Sign up',
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                ),
              ),
            ),
            // The barrier stays — it is what stops a second tap while the
            // request is in flight — but it no longer carries a spinner of its
            // own. There were two: this one and the button's. Centred in the
            // stack, this one landed on top of the Log In button and drew a
            // theme-coloured indicator over a primary-coloured fill, which is
            // the smear in the middle of the button. The button's own white
            // spinner already says the same thing, in the place you just
            // pressed.
            if (_isLoading)
              const ModalBarrier(dismissible: false, color: Colors.transparent),
          ],
        ),
      ),
    );
  }
}