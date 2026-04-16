import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/db_helper.dart';
import '../../services/auth_service.dart';
import '../auth/login_screen.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final AuthService _authService = AuthService();
  bool _isLoading = false;

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
        content: TextField(
          controller: emailController,
          decoration: const InputDecoration(labelText: 'New Email Address'),
          keyboardType: TextInputType.emailAddress,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (emailController.text.trim().isEmpty) return;
              setState(() => _isLoading = true);
              try {
                await _auth.currentUser?.verifyBeforeUpdateEmail(emailController.text.trim());
                _showSnackBar('Verification email sent to new address! Please check your inbox.');
              } on FirebaseAuthException catch (e) {
                _showSnackBar(e.message ?? 'An error occurred.');
              } catch (e) {
                _showSnackBar('Error: $e');
              } finally {
                setState(() => _isLoading = false);
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetPassword() async {
    setState(() => _isLoading = true);
    try {
      final email = _auth.currentUser?.email;
      if (email != null && email.isNotEmpty) {
        await _authService.sendPasswordResetEmail(email);
        _showSnackBar('Password reset email sent!');
      } else {
        _showSnackBar('No email associated with this account to reset password.');
      }
    } catch (e) {
      _showSnackBar('Failed to send reset email.');
    } finally {
      setState(() => _isLoading = false);
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
      _showSnackBar('Successfully linked to Google!');
      setState(() {}); 
    } on FirebaseAuthException catch (e) {
      _showSnackBar('Failed to link account: ${e.message}');
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
    final bool hasGoogleLinked = user?.providerData.any((p) => p.providerId == 'google.com') ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Account Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
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
                      onTap: () {
                        if (hasGoogleLinked) {
                           _showSnackBar('Your account is linked to Google. Email changes must be managed through Google.');
                        } else {
                           _changeEmail();
                        }
                      },
                      theme: theme,
                    ),
                    _actionTile(
                      icon: Icons.lock_reset,
                      title: 'Reset Password',
                      subtitle: 'We will send a reset link to your email.',
                      onTap: () {
                        if (hasGoogleLinked) {
                          _showSnackBar('Your account is linked to Google. Password resets must be managed through Google.');
                        } else {
                          _resetPassword();
                        }
                      },
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
