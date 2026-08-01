import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/cloud_sync_service.dart';

class BackupSyncCard extends StatefulWidget {
  /// Called after a successful sync so parent screens can reload data.
  final VoidCallback? onSyncComplete;

  const BackupSyncCard({super.key, this.onSyncComplete});

  @override
  State<BackupSyncCard> createState() => _BackupSyncCardState();
}

class _BackupSyncCardState extends State<BackupSyncCard> {
  bool _isLoading = false;
  String _lastSyncTime = "Never";

  @override
  void initState() {
    super.initState();
    _loadLastSyncTime();
  }

  // Smart formatting function
  String _formatTime(String rawTime) {
    if (rawTime == "Never") return rawTime;
    try {
      // Parse UTC time from storage and convert to device local time
      final DateTime parsedUtc = DateTime.parse(rawTime);
      final DateTime local = parsedUtc.toLocal();
      final DateTime now = DateTime.now();
      // If it was today, show just the time; otherwise show date + time
      if (local.year == now.year && local.month == now.month && local.day == now.day) {
        return 'Today at ${DateFormat('h:mm a').format(local)}';
      } else {
        return DateFormat('MMM d, h:mm a').format(local);
      }
    } catch (e) {
      return rawTime;
    }
  }

  // Fetch the saved time from local storage
  Future<void> _loadLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final rawTime = prefs.getString('last_sync_time') ?? "Never";

    if (!mounted) return;
    setState(() {
      _lastSyncTime = _formatTime(rawTime);
    });
  }

  /// Performs a **bidirectional** sync:
  /// - If cloud has newer data → pulls it down (restore)
  /// - If local has newer data → pushes it up (backup)
  /// This ensures changes made on web show up in app and vice versa.
  Future<void> _handleSync() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final result = await CloudSyncService().syncBidirectional();

      if (!mounted) return;

      String message;
      switch (result) {
        case 'restored':
          message = 'Synced! Data pulled from cloud.';
          break;
        case 'backed_up':
          message = 'Synced! Data pushed to cloud.';
          break;
        case 'no_network':
          message = 'No internet connection. Connect to sync.';
          break;
        case 'guest':
          message =
              'Cloud backup needs an account. Link a Google account in '
              'Account Settings to sync.';
          break;
        case 'syncing':
          message = 'A sync is already in progress.';
          break;
        case 'no_user':
          message = 'You must be logged in to sync.';
          break;
        default:
          message = 'Sync failed. Please try again.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );

      // Reload the sync time display
      await _loadLastSyncTime();

      // Notify parent to reload its data
      if (result == 'restored' || result == 'backed_up') {
        widget.onSyncComplete?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync failed. Please check your connection and try again.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).dividerColor,
        ),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.cloud_sync_rounded,
                        color: Color(0xFF2563EB),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          "Cloud Backup",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 36.0),
                    child: Text(
                      "Last sync: $_lastSyncTime",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _isLoading
                ? const Padding(
                    padding: EdgeInsets.only(right: 16.0),
                    child: SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : TextButton(
                    onPressed: _handleSync,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF2563EB),
                    ),
                    child: const Text("Sync Now"),
                  ),
          ],
        ),
      ),
    );
  }
}
