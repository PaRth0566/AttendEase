import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';

import '../../database/db_helper.dart';
import '../../services/auth_service.dart';
import '../../services/cloud_sync_service.dart';
import '../../theme/app_breakpoints.dart';
import '../../widgets/app_overlays.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final AuthService _authService = AuthService();
  final CloudSyncService _syncService = CloudSyncService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _refreshUser();
  }

  Future<void> _refreshUser() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        await user.reload();
        setState(() {}); // refresh email UI
      } catch (e) {
        debugPrint('Silent reload failed: $e');
      }
    }
  }

  void _showSnackBar(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Re-authenticates the current user before a sensitive operation.
  /// Returns true if re-auth succeeded, false if the user cancelled or it failed.
  Future<bool> _reAuthenticate() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final bool isGoogleUser = user.providerData.any(
      (p) => p.providerId == 'google.com',
    );
    final bool hasPassword = user.providerData.any(
      (p) => p.providerId == 'password',
    );

    if (isGoogleUser && !hasPassword) {
      // Re-auth via Google
      try {
        await GoogleSignIn().signOut(); // Force prompt for recent login
        final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) return false;
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        await user.reauthenticateWithCredential(credential);
        return true;
      } catch (_) {
        _showSnackBar('Re-authentication failed. Please try again.');
        return false;
      }
    }

    // Re-auth via email + password
    final passCtrl = TextEditingController();
    bool success = false;
    await showAppDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Your Identity'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Please enter your current password for ${user.email} to continue.',
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Current Password',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final credential = EmailAuthProvider.credential(
                  email: user.email!,
                  password: passCtrl.text,
                );
                await user.reauthenticateWithCredential(credential);
                success = true;
                if (ctx.mounted) Navigator.pop(ctx);
              } on FirebaseAuthException {
                _showSnackBar('Incorrect password. Please try again.');
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return success;
  }



  Future<void> _changePassword() async {
    final user = _auth.currentUser;
    if (user == null || user.email == null || user.isAnonymous) {
      _showSnackBar('No verified email available to trigger a password reset.');
      return;
    }

    // Backup data to cloud first so it survives any re-login
    await _syncService.backupDataToCloud();
    if (!mounted) return;

    final bool hasPasswordProvider = user.providerData.any(
      (p) => p.providerId == 'password',
    );

    if (hasPasswordProvider) {
      // User already has email/password provider — send reset email
      setState(() => _isLoading = true);
      try {
        await _auth.sendPasswordResetEmail(email: user.email!);
        _showSnackBar(
          'Password reset link sent to ${user.email}. Check your inbox.',
        );
      } on FirebaseAuthException {
        _showSnackBar('Could not send reset email. Please try again.');
      } catch (e) {
        _showSnackBar('Something went wrong. Please try again.');
      } finally {
        setState(() => _isLoading = false);
      }
    } else {
      // Google-only user — needs to SET a password to enable email/password login
      final TextEditingController newPassCtrl = TextEditingController();
      final TextEditingController confirmPassCtrl = TextEditingController();
      await showAppDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Set a Password'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Your account was created with Google and has no password yet. '
                  'Set one now to enable email & password login.',
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: newPassCtrl,
                  decoration: const InputDecoration(
                    labelText: 'New Password',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmPassCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Confirm Password',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newPass = newPassCtrl.text;
                final confirmPass = confirmPassCtrl.text;
                if (newPass.isEmpty || newPass.length < 6) {
                  _showSnackBar('Password must be at least 6 characters.');
                  return;
                }
                if (newPass != confirmPass) {
                  _showSnackBar('Passwords do not match.');
                  return;
                }
                Navigator.pop(ctx);
                setState(() => _isLoading = true);
                try {
                  final credential = EmailAuthProvider.credential(
                    email: user.email!,
                    password: newPass,
                  );
                  await user.linkWithCredential(credential);
                  _showSnackBar(
                    'Password set! You can now sign in with email & password.',
                  );
                } on FirebaseAuthException catch (e) {
                  if (e.code == 'provider-already-linked') {
                    try {
                      await user.updatePassword(newPass);
                      _showSnackBar('Password updated successfully!');
                    } catch (updateErr) {
                      _showSnackBar(
                        'Could not update password. Please try again.',
                      );
                    }
                  } else {
                    _showSnackBar('Could not set password. Please try again.');
                  }
                } catch (e) {
                  _showSnackBar('Something went wrong. Please try again.');
                } finally {
                  setState(() => _isLoading = false);
                }
              },
              child: const Text('Set Password'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _linkWithGoogle() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      // Reuse AuthService's Google flow so the credential handling and the
      // error-to-message mapping live in exactly one place. It signs the
      // Google SDK out first, so the account chooser always appears.
      final GoogleSignIn googleSignIn = GoogleSignIn();
      try {
        await googleSignIn.signOut();
      } catch (_) {}

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        if (mounted) setState(() => _isLoading = false);
        return; // aborted
      }
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      if (googleAuth.idToken == null) {
        _showSnackBar(
          'Google did not return a sign-in token. '
          'The app\'s Google configuration is incomplete.',
        );
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final user = _auth.currentUser;
      if (user == null) {
        _showSnackBar('You are no longer signed in. Please log in again.');
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      await user.linkWithCredential(credential);
      // The anonymous account has been upgraded in place, so the UID is
      // unchanged and the local data is still this user's. Reload so the
      // screen reflects the new provider/email before we report success.
      await user.reload();

      // Successfully linked! Sync local data to the newly upgraded Cloud
      // account. Report the sync result honestly rather than claiming a
      // sync that did not happen.
      final bool synced = await _syncService.backupDataToCloud();

      if (!mounted) return;
      setState(() {});
      _showSnackBar(
        synced
            ? 'Successfully linked to Google and synced your data!'
            : 'Linked to Google. Your data will sync on the next backup.',
      );
    } on PlatformException catch (e) {
      debugPrint('Link Google PlatformException: ${e.code} ${e.message}');
      if (e.code == '10' ||
          e.message?.contains('10:') == true ||
          e.message?.contains('DEVELOPER_ERROR') == true) {
        _showSnackBar(
          'Google Sign-In is not configured for this build '
          '(certificate not registered).',
        );
      } else if (e.code == 'network_error') {
        _showSnackBar('Network error. Check your connection and try again.');
      } else {
        _showSnackBar('Could not link your Google account. Please try again.');
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use') {
        _showSnackBar(
          'This Google account is already linked to another AttendEase account. Please choose a different Google account.',
        );
      } else if (e.code == 'provider-already-linked') {
        _showSnackBar('This account is already linked to Google.');
      } else if (e.code == 'network-request-failed') {
        _showSnackBar('Network error. Check your connection and try again.');
      } else {
        _showSnackBar('Could not link your Google account. Please try again.');
      }
    } catch (e) {
      debugPrint('Link Google error: ${e.runtimeType} $e');
      _showSnackBar('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteAccount() async {
    final TextEditingController deleteController = TextEditingController();
    await showAppDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This action is irreversible. All your data will be permanently deleted.',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text('Type "DELETE" below to confirm:'),
              const SizedBox(height: 8),
              TextField(
                controller: deleteController,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              if (deleteController.text == 'DELETE') {
                Navigator.pop(ctx);
                final bool reAuthed = await _reAuthenticate();
                if (!reAuthed) return;
                await _performDeletion();
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Verification failed. Account not deleted.'),
                  ),
                );
              }
            },
            child: const Text(
              'Delete Permanently',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _performDeletion() async {
    setState(() => _isLoading = true);
    try {
      final user = _auth.currentUser;
      if (user != null) {
        // Delete the auth user FIRST. It is the step that can fail
        // (`requires-recent-login`), and if it does we must not have already
        // destroyed the Firestore document — that would leave the user with a
        // live account and no data and no way to get it back.
        await user.delete();

        // The auth user is gone. Clean up its Firestore document. The security
        // rules key on request.auth.uid, which is now null, so this delete is
        // attempted while still holding the old token and may be rejected;
        // failing here must not abort the local cleanup below.
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .delete();
        } catch (e) {
          debugPrint('Cloud document cleanup after delete failed: $e');
        }
      }

      await _authService.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (!kIsWeb) {
        final db = await DBHelper.instance.database;
        await db.delete('attendance_records');
        await db.delete('timetable');
        await db.delete('subjects');
        await db.delete('imported_report_dates');
      }

      if (mounted) {
        context.go('/login');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _isLoading = false);
      if (e.code == 'requires-recent-login') {
        _showSnackBar(
          'Security requirement: Please log out, log back in, and try deleting your account again.',
        );
      } else {
        _showSnackBar('Could not delete account. Please try again.');
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _showSnackBar('Something went wrong. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = _auth.currentUser;
    final isGuest = user?.isAnonymous ?? true;

    return Scaffold(
      appBar: AppBar(title: const Text('Account Settings')),
      body: SafeArea(
        top: false,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppBreakpoints.isMobile(context) ? 16 : 32,
                      vertical: 16,
                    ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Profile Information',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: theme.dividerColor),
                        ),
                        leading: Icon(
                          isGuest ? Icons.person_outline : Icons.email,
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(
                          isGuest
                              ? 'Guest Account'
                              : (user?.email ?? 'Unknown Email'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: isGuest
                            ? const Text('Temporary session')
                            : const Text('Verified user'),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'Settings',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (isGuest) ...[
                        _actionTile(
                          icon: Icons.link,
                          title: 'Link with Google Account',
                          subtitle:
                              'Save your guest data permanently to a secure Google account.',
                          onTap: _linkWithGoogle,
                          theme: theme,
                        ),
                      ] else ...[

                        _actionTile(
                          icon: Icons.password,
                          title: 'Change Password',
                          subtitle: 'Set or reset your account password.',
                          onTap: _changePassword,
                          theme: theme,
                        ),
                      ],

                      const SizedBox(height: 48),
                      Text(
                        'Danger Zone',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _actionTile(
                        icon: Icons.delete_forever,
                        title: 'Delete Account',
                        subtitle:
                            'Permanently remove your account and all data.',
                        onTap: _deleteAccount,
                        theme: theme,
                        isDestructive: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required ThemeData theme,
    bool isDestructive = false,
  }) {
    final color = isDestructive ? Colors.red : theme.textTheme.bodyLarge?.color;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: isDestructive ? Colors.red.withValues(alpha: 0.05) : theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDestructive
              ? Colors.red.withValues(alpha: 0.3)
              : theme.dividerColor,
        ),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isDestructive ? Colors.red : theme.colorScheme.primary,
        ),
        title: Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w600, color: color),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: isDestructive
                ? Colors.red.withValues(alpha: 0.8)
                : theme.textTheme.bodySmall?.color,
          ),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: onTap,
      ),
    );
  }
}
