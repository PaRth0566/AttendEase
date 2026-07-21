import 'package:flutter/foundation.dart';

/// A platform-agnostic error raised while downloading or installing an update.
///
/// Lives in the shared contract (not in the io implementation) so that both the
/// web-safe [UpdateService] and the Android io platform can throw and catch the
/// same type without importing `dart:io`.
class UpdatePlatformException implements Exception {
  final String message;
  const UpdatePlatformException(this.message);
  @override
  String toString() => message;
}

/// Raised when the user cancels an in-progress download.
class UpdatePlatformCancelledException extends UpdatePlatformException {
  const UpdatePlatformCancelledException() : super('Update download cancelled.');
}

class UpdateDownload {
  final Future<String> completedPath;
  final Stream<double> progress;
  final VoidCallback cancel;

  const UpdateDownload({
    required this.completedPath,
    required this.progress,
    required this.cancel,
  });
}

abstract class UpdatePlatform {
  bool get isSupported;

  UpdateDownload download({
    required Uri url,
    required String version,
    required String expectedSha256,
  });

  Future<void> launchInstaller(String path);
}
