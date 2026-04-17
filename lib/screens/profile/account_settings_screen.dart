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

  Future<void> _changePassword() async {
    final TextEditingController currentPassCtrl = TextEditingController();
    final TextEditingController newPassCtrl = TextEditingController();
    
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentPassCtrl,
              decoration: const InputDecoration(labelText: 'Current Password', border: OutlineInputBorder()),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: newPassCtrl,
              decoration: const InputDecoration(labelText: 'New Password', border: OutlineInputBorder()),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final currentPass = currentPassCtrl.text;
              final newPass = newPassCtrl.text;
              
              if (currentPass.isEmpty || newPass.isEmpty) {
                 _showSnackBar('Both passwords are required.');
                 return;
              }
              
              setState(() => _isLoading = true);
              try {
                final user = _auth.currentUser;
                if (user != null && user.email != null) {
                  final cred = EmailAuthProvider.credential(email: user.email!, password: currentPass);
                  await user.reauthenticateWithCredential(cred);
                  await user.updatePassword(newPass);
                  _showSnackBar('Password changed successfully within the app!');
                }
              } on FirebaseAuthException catch (e) {
                if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
                  _showSnackBar('Current password is incorrect.');
                } else if (e.code == 'weak-password') {
                  _showSnackBar('New password is too weak.');
                } else {
                  _showSnackBar(e.message ?? 'An error occurred.');
                }
              } catch (e) {
                _showSnackBar('Error updating password: $e');
              } finally {
                setState(() => _isLoading = false);
              }
            },
            child: const Text('Change Password'),
          ),
        ],
      ),
    );
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
                      icon: Icons.password,
                      title: 'Change Password',
                      subtitle: 'Update your password directly within the app.',
                      onTap: () {
                        if (hasGoogleLinked) {
                          _showSnackBar('Your account is linked to Google. Passwords must be managed through Google.');
                        } else {
                          _changePassword();
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
