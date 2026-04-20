import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/db_helper.dart';
import '../../services/auth_service.dart';
import '../../services/cloud_sync_service.dart';
import '../auth/login_screen.dart';

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

  Future<void> _changeEmail() async {
    final TextEditingController emailController = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Email'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Your data will be transferred to the new email. '
              'The current account will be deleted so the old email starts completely fresh. '
              'Sign up or sign in with the new email to get your data back.',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: 'New Email Address',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final newEmail = emailController.text.trim().toLowerCase();
              if (newEmail.isEmpty) return;
              setState(() => _isLoading = true);
              try {
                final user = _auth.currentUser;
                if (user == null) throw Exception('Not logged in.');

                // Step 1: Backup all data to a transfer document keyed by the NEW email
                final db = kIsWeb ? null : await DBHelper.instance.database;
                final prefs = await SharedPreferences.getInstance();

                final Map<String, dynamic> transferData = {
                  'transferred_at': FieldValue.serverTimestamp(),
                };

                if (!kIsWeb && db != null) {
                  transferData['subjects'] = await db.query('subjects');
                  transferData['timetable'] = await db.query('timetable');
                  transferData['attendance_records'] = await db.query('attendance_records');
                }

                final Map<String, dynamic> userPrefs = {};
                for (String key in prefs.getKeys()) {
                  userPrefs[key] = prefs.get(key);
                }
                transferData['preferences'] = userPrefs;

                // Save to a transfer collection indexed by the new email
                await FirebaseFirestore.instance
                    .collection('data_transfers')
                    .doc(newEmail)
                    .set(transferData);

                // Step 2: Delete old user's Firestore document
                await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();

                // Step 3: Delete the Firebase Auth account entirely
                await user.delete();

                // Step 4: Wipe all local data
                if (!kIsWeb && db != null) {
                  await db.delete('attendance_records');
                  await db.delete('timetable');
                  await db.delete('subjects');
                }
                await prefs.clear();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Account deleted. Sign up with $newEmail to restore your data.'),
                      duration: const Duration(seconds: 6),
                    ),
                  );
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                }
              } on FirebaseAuthException catch (e) {
                if (e.code == 'requires-recent-login') {
                  _showSnackBar('For security, please log out, log back in, and try again.');
                } else {
                  _showSnackBar(e.message ?? 'An error occurred.');
                }
                setState(() => _isLoading = false);
              } catch (e) {
                _showSnackBar('Error: $e');
                setState(() => _isLoading = false);
              }
            },
            child: const Text('Transfer & Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _changePassword() async {
    final user = _auth.currentUser;
    if (user == null || user.email == null || user.isAnonymous) {
      _showSnackBar('No verified email available to trigger a password reset.');
      return;
    }

    // Backup data to cloud first so it survives any re-login
    await _syncService.backupDataToCloud();

    final bool hasPasswordProvider =
        user.providerData.any((p) => p.providerId == 'password');

    if (hasPasswordProvider) {
      // User already has email/password provider — send reset email
      setState(() => _isLoading = true);
      try {
        await _auth.sendPasswordResetEmail(email: user.email!);
        _showSnackBar('Password reset link sent to ${user.email}!');
      } on FirebaseAuthException catch (e) {
        _showSnackBar(e.message ?? 'An error occurred.');
      } catch (e) {
        _showSnackBar('Error: $e');
      } finally {
        setState(() => _isLoading = false);
      }
    } else {
      // Google-only user — needs to SET a password to enable email/password login
      final TextEditingController newPassCtrl = TextEditingController();
      final TextEditingController confirmPassCtrl = TextEditingController();
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Set a Password'),
          content: Column(
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
                  _showSnackBar('Password set! You can now sign in with email & password.');
                } on FirebaseAuthException catch (e) {
                  if (e.code == 'provider-already-linked') {
                    try {
                      await user.updatePassword(newPass);
                      _showSnackBar('Password updated successfully!');
                    } catch (updateErr) {
                      _showSnackBar('Error updating password: $updateErr');
                    }
                  } else {
                    _showSnackBar('Error: ${e.message}');
                  }
                } catch (e) {
                  _showSnackBar('Error setting password: $e');
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
    setState(() => _isLoading = true);
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return; // aborted
      }
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await _auth.currentUser?.linkWithCredential(credential);
      // Successfully linked! Sync local data to the newly upgraded Cloud account.
      await _syncService.backupDataToCloud();

      _showSnackBar('Successfully linked to Google and synced your data!');
      setState(() {}); 
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use') {
        _showSnackBar('This Google account is already registered. Please sign in normally, or select a different Google account to link.');
      } else {
        _showSnackBar('Failed to link account: ${e.message}');
      }
    } catch (e) {
      _showSnackBar('Error linking account: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteAccount() async {
    final TextEditingController deleteController = TextEditingController();
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This action is irreversible. All your data will be permanently deleted.',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
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
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              if (deleteController.text == 'DELETE') {
                Navigator.pop(ctx);
                await _performDeletion();
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Verification failed. Account not deleted.')),
                );
              }
            },
            child: const Text('Delete Permanently', style: TextStyle(color: Colors.white)),
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
        await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();
        await user.delete();
      }
      
      await _authService.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (!kIsWeb) {
        final db = await DBHelper.instance.database;
        await db.delete('attendance_records');
        await db.delete('timetable');
        await db.delete('subjects');
      }

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _isLoading = false);
      if (e.code == 'requires-recent-login') {
        _showSnackBar('Security requirement: Please log out, log back in, and try deleting your account again.');
      } else {
        _showSnackBar(e.message ?? 'An error occurred.');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('Error deleting account: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = _auth.currentUser;
    final isGuest = user?.isAnonymous ?? true;

    return Scaffold(
      appBar: AppBar(title: const Text('Account Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.of(context).size.width > 600 ? 32 : 16,
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
                    leading: Icon(isGuest ? Icons.person_outline : Icons.email, color: theme.colorScheme.primary),
                    title: Text(isGuest ? 'Guest Account' : (user?.email ?? 'Unknown Email')),
                    subtitle: isGuest ? const Text('Temporary session') : const Text('Verified user'),
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
                      subtitle: 'Save your guest data permanently to a secure Google account.',
                      onTap: _linkWithGoogle,
                      theme: theme,
                    ),
                  ] else ...[
                    _actionTile(
                      icon: Icons.edit_note,
                      title: 'Change Email Address',
                      subtitle: 'Migrate your account data to a new email address.',
                      onTap: _changeEmail,
                      theme: theme,
                    ),
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
                    subtitle: 'Permanently remove your account and all data.',
                    onTap: _deleteAccount,
                    theme: theme,
                    isDestructive: true,
                  ),
                ],
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
      color: isDestructive ? Colors.red.withOpacity(0.05) : theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDestructive ? Colors.red.withOpacity(0.3) : theme.dividerColor,
        ),
      ),
      child: ListTile(
        leading: Icon(icon, color: isDestructive ? Colors.red : theme.colorScheme.primary),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: isDestructive ? Colors.red.withOpacity(0.8) : theme.textTheme.bodySmall?.color)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: onTap,
      ),
    );
  }
}
