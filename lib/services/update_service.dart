import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Information about an available update.
class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final String releaseNotes;
  final String htmlUrl; // GitHub release page URL

  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.htmlUrl,
  });
}

/// Service that checks for app updates via GitHub Releases API.
///
/// Only runs on mobile. Compares the installed app version against the
/// latest GitHub release tag and returns [UpdateInfo] if a newer version
/// is available.
class UpdateService {
  static const String _repoOwner = 'PaRth0566';
  static const String _repoName = 'AttendEase';

  /// Checks GitHub for a newer release. Returns [UpdateInfo] if an update
  /// is available, or `null` if the app is up-to-date (or on web).
  Future<UpdateInfo?> checkForUpdate() async {
    // Never run on web
    if (kIsWeb) return null;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // e.g. "1.0.2"

      // Fetch latest release from GitHub
      final response = await http
          .get(
            Uri.parse(
              'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest',
            ),
            headers: {'Accept': 'application/vnd.github.v3+json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      final latestVersion = tagName.replaceFirst(RegExp(r'^v'), ''); // "v1.1.0" → "1.1.0"
      final releaseNotes = data['body'] as String? ?? 'Bug fixes and improvements.';
      final htmlUrl = data['html_url'] as String? ?? '';

      // Find the APK asset download URL
      String downloadUrl = '';
      final assets = data['assets'] as List<dynamic>? ?? [];
      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.apk')) {
          downloadUrl = asset['browser_download_url'] as String? ?? '';
          break;
        }
      }

      // Fallback: use the GitHub release page if no APK asset found
      if (downloadUrl.isEmpty) {
        downloadUrl = htmlUrl;
      }

      // Validate the download URL domain — only trust GitHub
      if (downloadUrl.isNotEmpty) {
        final uri = Uri.tryParse(downloadUrl);
        if (uri == null ||
            !(uri.host == 'github.com' ||
              uri.host.endsWith('.githubusercontent.com'))) {
          debugPrint('Update check: rejected untrusted download URL: $downloadUrl');
          downloadUrl = htmlUrl; // Fall back to release page
        }
      }

      // Compare versions
      if (!_isNewerVersion(currentVersion, latestVersion)) {
        return null; // already up-to-date
      }

      return UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        downloadUrl: downloadUrl,
        releaseNotes: releaseNotes,
        htmlUrl: htmlUrl,
      );
    } catch (e) {
      // Fail silently — update check is non-critical
      debugPrint('Update check failed: $e');
      return null;
    }
  }

  /// Returns `true` if [latest] is a higher semantic version than [current].
  bool _isNewerVersion(String current, String latest) {
    final currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final latestParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    // Pad to 3 parts (major.minor.patch)
    while (currentParts.length < 3) {
      currentParts.add(0);
    }
    while (latestParts.length < 3) {
      latestParts.add(0);
    }

    for (int i = 0; i < 3; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return false; // versions are equal
  }
}
