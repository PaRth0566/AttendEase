import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'update_platform_contract.dart';
import 'update_platform_stub.dart'
    if (dart.library.io) 'update_platform_io.dart';

// Re-export so UI widgets can depend on a single `update_service.dart` import
// for the download handle and cancellation type instead of reaching into the
// platform contract directly.
export 'update_platform_contract.dart'
    show UpdateDownload, UpdatePlatformException, UpdatePlatformCancelledException;

/// A user-facing error raised anywhere in the update pipeline. Its [message]
/// is safe to show directly in a SnackBar or dialog.
class UpdateException implements Exception {
  final String message;
  const UpdateException(this.message);
  @override
  String toString() => message;
}

class ReleaseNotes {
  final String version;
  final DateTime publishedAt;
  final String summary;
  final List<String> changes;

  const ReleaseNotes({
    required this.version,
    required this.publishedAt,
    required this.summary,
    required this.changes,
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'publishedAt': publishedAt.toIso8601String(),
        'summary': summary,
        'changes': changes,
      };

  factory ReleaseNotes.fromJson(Map<String, dynamic> json) => ReleaseNotes(
        version: json['version'] as String,
        publishedAt: DateTime.parse(json['publishedAt'] as String),
        summary: json['summary'] as String,
        changes: List<String>.from(json['changes'] as List),
      );
}

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final Uri apkUrl;
  final Uri checksumUrl;
  final String expectedSha256;
  final ReleaseNotes notes;

  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.apkUrl,
    required this.checksumUrl,
    required this.expectedSha256,
    required this.notes,
  });
}

class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const _owner = 'PaRth0566';
  static const _repo = 'AttendEase';
  final UpdatePlatform _platform = createUpdatePlatform();
  static const _pendingKey = 'update.pending_release';
  static const _historyKey = 'update.patch_notes_history';
  static const _viewedKey = 'update.last_viewed_patch_notes_version';
  static const _installedKey = 'update.last_installed_version';

  /// True while an update sheet (startup or manual) is being shown, so callers
  /// can avoid stacking a second sheet on top of the first.
  bool _sheetVisible = false;
  bool get isUpdateSheetVisible => _sheetVisible;

  /// Marks the update/patch-notes sheet as visible for the duration of [action]
  /// and guarantees the flag is reset afterwards. Returns false without running
  /// [action] if a sheet is already visible.
  Future<bool> runExclusiveSheet(Future<void> Function() action) async {
    if (_sheetVisible) return false;
    _sheetVisible = true;
    try {
      await action();
    } finally {
      _sheetVisible = false;
    }
    return true;
  }

  Future<UpdateInfo?> checkForUpdate() async {
    if (!_platform.isSupported) return null;
    final packageInfo = await PackageInfo.fromPlatform();
    final client = http.Client();
    try {
      final response = await _getWithRetry(
        client,
        Uri.https('api.github.com', '/repos/$_owner/$_repo/releases/latest'),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
        timeout: const Duration(seconds: 15),
      );
      if (response.statusCode == 403 || response.statusCode == 429) {
        throw const UpdateException('GitHub rate limit reached. Please try again later.');
      }
      if (response.statusCode == 404) {
        // No published release yet — treat as "up to date" rather than an error.
        return null;
      }
      if (response.statusCode != 200) {
        throw const UpdateException('Unable to check for updates right now.');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const UpdateException('GitHub returned an invalid release.');
      }
      final json = decoded;
      if (json['draft'] == true || json['prerelease'] == true) {
        // A draft/prerelease is not a production update — silently ignore it
        // instead of surfacing an error to the user.
        return null;
      }
      final latest = _normalizeVersion(json['tag_name']?.toString() ?? '');
      final current = _normalizeVersion(packageInfo.version);
      if (latest.isEmpty || !_isNewer(latest, current)) return null;

      final assets = (json['assets'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      final apk = _findAsset(assets, (name) => name.toLowerCase().endsWith('.apk'));
      final checksum = _findAsset(
        assets,
        (name) => name.toLowerCase().endsWith('.sha256') ||
            name.toLowerCase() == 'sha256sums.txt',
      );
      if (apk == null || checksum == null) {
        throw const UpdateException(
          'This release is missing its APK or SHA-256 checksum asset.',
        );
      }
      final apkUrl = _validatedDownloadUri(apk['browser_download_url']);
      final checksumUrl = _validatedDownloadUri(checksum['browser_download_url']);
      final checksumResponse = await _getWithRetry(
        client,
        checksumUrl,
        timeout: const Duration(seconds: 10),
      );
      if (checksumResponse.statusCode != 200) {
        throw const UpdateException('Unable to verify the update checksum.');
      }
      final expectedHash = _extractChecksum(
        checksumResponse.body,
        apk['name']?.toString() ?? '',
      );
      final publishedAt = DateTime.tryParse(json['published_at']?.toString() ?? '') ??
          DateTime.now().toUtc();
      final notes = _summarizeNotes(
        version: latest,
        body: json['body']?.toString() ?? '',
        publishedAt: publishedAt,
      );
      return UpdateInfo(
        currentVersion: current,
        latestVersion: latest,
        apkUrl: apkUrl,
        checksumUrl: checksumUrl,
        expectedSha256: expectedHash,
        notes: notes,
      );
    } on UpdateException {
      rethrow;
    } on TimeoutException {
      throw const UpdateException('The update check timed out. Check your connection.');
    } on http.ClientException {
      throw const UpdateException('No internet connection.');
    } on FormatException {
      throw const UpdateException('GitHub returned an invalid release.');
    } finally {
      client.close();
    }
  }

  /// Performs a GET with a single retry on transient network/timeout failures.
  /// HTTP error status codes are returned as-is (not retried) for the caller to
  /// interpret. Uses [http.ClientException] rather than `SocketException` so the
  /// service remains free of `dart:io` and safe to compile for web.
  Future<http.Response> _getWithRetry(
    http.Client client,
    Uri url, {
    Map<String, String>? headers,
    required Duration timeout,
  }) async {
    const maxAttempts = 2;
    for (var attempt = 1; ; attempt++) {
      try {
        return await client.get(url, headers: headers).timeout(timeout);
      } on TimeoutException {
        if (attempt >= maxAttempts) rethrow;
      } on http.ClientException {
        if (attempt >= maxAttempts) rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
    }
  }

  UpdateDownload download(UpdateInfo info) {
    final raw = _platform.download(
      url: info.apkUrl,
      version: info.latestVersion,
      expectedSha256: info.expectedSha256,
    );
    // Translate low-level platform errors into user-facing [UpdateException]s so
    // the UI depends on a single error type. Cancellation is preserved as a
    // distinct subtype so the UI can suppress its error message.
    final completed = raw.completedPath.catchError((Object error) {
      if (error is UpdatePlatformCancelledException) {
        throw error;
      }
      if (error is UpdatePlatformException) {
        throw UpdateException(error.message);
      }
      throw const UpdateException('The update could not be completed.');
    });
    return UpdateDownload(
      completedPath: completed,
      progress: raw.progress,
      cancel: raw.cancel,
    );
  }

  Future<void> launchInstaller(String apkPath, UpdateInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingKey, jsonEncode(info.notes.toJson()));
    try {
      await _platform.launchInstaller(apkPath);
    } on UpdatePlatformException catch (error) {
      await prefs.remove(_pendingKey);
      throw UpdateException(error.message);
    } catch (error) {
      await prefs.remove(_pendingKey);
      throw const UpdateException('Android could not open the installer.');
    }
  }

  Future<ReleaseNotes?> reconcileInstalledUpdate() async {
    if (!_platform.isSupported) return null;
    final prefs = await SharedPreferences.getInstance();
    final current = _normalizeVersion((await PackageInfo.fromPlatform()).version);
    if (current.isNotEmpty) await prefs.setString(_installedKey, current);
    final raw = prefs.getString(_pendingKey);
    if (raw == null) return null;
    try {
      final notes = ReleaseNotes.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      final pendingVersion = _normalizeVersion(notes.version);
      if (pendingVersion != current) {
        // The pending update was not the version that ended up installed.
        // If the installed version already meets or exceeds the pending one,
        // the pending record is stale (user installed something else or a
        // newer build) — drop it. Otherwise the install was likely cancelled,
        // so keep the record for a later completed install.
        if (pendingVersion.isEmpty || !_isNewer(pendingVersion, current)) {
          await prefs.remove(_pendingKey);
        }
        return null;
      }
      final history = await patchNotesHistory();
      final updated = [notes, ...history.where((item) => item.version != notes.version)];
      await prefs.setString(
        _historyKey,
        jsonEncode(updated.take(20).map((item) => item.toJson()).toList()),
      );
      await prefs.remove(_pendingKey);
      if (prefs.getString(_viewedKey) == current) return null;
      return notes;
    } catch (_) {
      await prefs.remove(_pendingKey);
      return null;
    }
  }

  Future<List<ReleaseNotes>> patchNotesHistory() async {
    final raw = (await SharedPreferences.getInstance()).getString(_historyKey);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((item) => ReleaseNotes.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> markPatchNotesViewed(String version) async {
    await (await SharedPreferences.getInstance()).setString(_viewedKey, version);
  }

  static bool isNewerVersion(String candidate, String installed) =>
      _isNewer(_normalizeVersion(candidate), _normalizeVersion(installed));

  static Map<String, dynamic>? _findAsset(
    List<Map<String, dynamic>> assets,
    bool Function(String) matches,
  ) {
    for (final asset in assets) {
      if (matches(asset['name']?.toString() ?? '')) return asset;
    }
    return null;
  }

  static Uri _validatedDownloadUri(Object? value) {
    final uri = Uri.tryParse(value?.toString() ?? '');
    const allowed = {'github.com', 'objects.githubusercontent.com'};
    if (uri == null || uri.scheme != 'https' || !allowed.contains(uri.host)) {
      throw const FormatException('Untrusted release asset URL.');
    }
    return uri;
  }

  static String _extractChecksum(String contents, String apkName) {
    final hashPattern = RegExp(r'\b[a-fA-F0-9]{64}\b');
    for (final line in const LineSplitter().convert(contents)) {
      if (line.contains(apkName)) {
        final match = hashPattern.firstMatch(line);
        if (match != null) return match.group(0)!.toLowerCase();
      }
    }
    final all = hashPattern.allMatches(contents).toList();
    if (all.length == 1) return all.single.group(0)!.toLowerCase();
    throw const FormatException('No unambiguous APK checksum found.');
  }

  static String _normalizeVersion(String version) {
    final match = RegExp(r'^(?:v)?(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$').firstMatch(version.trim());
    return match == null ? '' : '${match.group(1)}.${match.group(2)}.${match.group(3)}';
  }

  static bool _isNewer(String candidate, String installed) {
    if (candidate.isEmpty || installed.isEmpty) return false;
    final a = candidate.split('.').map(int.parse).toList();
    final b = installed.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  static ReleaseNotes _summarizeNotes({
    required String version,
    required String body,
    required DateTime publishedAt,
  }) {
    final cleaned = body
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^\)]+\)'), r'$1')
        .replaceAll(RegExp(r'[`*_>#]'), ' ');
    final candidates = cleaned
        .split(RegExp(r'[\r\n]+|(?<=[.!?])\s+'))
        .map((line) => line.replaceFirst(RegExp(r'^\s*[-+•\d.)]+\s*'), '').trim())
        .where((line) => line.length >= 5)
        .map((line) => line.length > 140 ? '${line.substring(0, 137).trim()}...' : line)
        .toSet()
        .take(8)
        .toList();
    final changes = candidates.isEmpty ? const ['General improvements and bug fixes'] : candidates;
    final summary = changes.take(2).join(' ');
    return ReleaseNotes(
      version: version,
      publishedAt: publishedAt,
      summary: summary.length > 220 ? '${summary.substring(0, 217).trim()}...' : summary,
      changes: changes,
    );
  }
}
