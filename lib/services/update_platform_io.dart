import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'update_platform_contract.dart';

UpdatePlatform createUpdatePlatform() => _IoUpdatePlatform();

class _IoUpdatePlatform implements UpdatePlatform {
  static const _channel = MethodChannel('com.parthm.attendease/update_installer');

  @override
  bool get isSupported => Platform.isAndroid;

  @override
  UpdateDownload download({
    required Uri url,
    required String version,
    required String expectedSha256,
  }) {
    final progress = StreamController<double>.broadcast();
    final client = http.Client();
    var cancelled = false;

    Future<String> run() async {
      File? partial;
      try {
        final response = await _openStreamWithRetry(client, url, () => cancelled);
        final total = response.contentLength;
        final directory = await getTemporaryDirectory();
        partial = File(
          '${directory.path}${Platform.pathSeparator}attendease-$version.apk.part',
        );
        final sink = partial.openWrite();
        var received = 0;
        try {
          await for (final chunk in response.stream) {
            if (cancelled) throw const UpdatePlatformCancelledException();
            sink.add(chunk);
            received += chunk.length;
            if (total != null && total > 0) {
              progress.add((received / total).clamp(0.0, 1.0).toDouble());
            }
          }
        } finally {
          await sink.close();
        }
        if (cancelled) throw const UpdatePlatformCancelledException();
        if (received == 0 || (total != null && received != total)) {
          throw const UpdatePlatformException('The update download is incomplete.');
        }
        final actual = (await sha256.bind(partial.openRead()).first).toString();
        if (actual.toLowerCase() != expectedSha256.toLowerCase()) {
          throw const UpdatePlatformException(
            'The downloaded update failed its integrity check.',
          );
        }
        final apk = File(partial.path.replaceAll(RegExp(r'\.part$'), ''));
        if (await apk.exists()) await apk.delete();
        await partial.rename(apk.path);
        progress.add(1);
        return apk.path;
      } on UpdatePlatformException {
        rethrow;
      } on TimeoutException {
        throw const UpdatePlatformException('The update download timed out.');
      } on SocketException {
        throw const UpdatePlatformException('The network connection was lost.');
      } on http.ClientException {
        if (cancelled) throw const UpdatePlatformCancelledException();
        throw const UpdatePlatformException('The update download was interrupted.');
      } on FileSystemException catch (error) {
        // ENOSPC (28) => disk full. Surface a clear, actionable message.
        if (error.osError?.errorCode == 28) {
          throw const UpdatePlatformException(
            'Not enough storage to download the update. Free up space and try again.',
          );
        }
        throw const UpdatePlatformException('The update could not be saved to storage.');
      } finally {
        client.close();
        if (!progress.isClosed) await progress.close();
        if (partial != null && await partial.exists() && partial.path.endsWith('.part')) {
          try {
            await partial.delete();
          } catch (_) {
            // Best-effort cleanup; ignore failures deleting the temp file.
          }
        }
      }
    }

    return UpdateDownload(
      completedPath: run(),
      progress: progress.stream,
      cancel: () {
        cancelled = true;
        client.close();
      },
    );
  }

  /// Opens the download stream, retrying once on a transient network failure.
  /// A non-200 response is treated as fatal (no retry) since it will not
  /// self-correct on an immediate retry.
  Future<http.StreamedResponse> _openStreamWithRetry(
    http.Client client,
    Uri url,
    bool Function() isCancelled,
  ) async {
    const maxAttempts = 2;
    for (var attempt = 1; ; attempt++) {
      if (isCancelled()) throw const UpdatePlatformCancelledException();
      try {
        final response = await client
            .send(http.Request('GET', url))
            .timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) {
          throw const UpdatePlatformException(
            'The update download could not be started.',
          );
        }
        return response;
      } on TimeoutException {
        if (attempt >= maxAttempts) rethrow;
      } on SocketException {
        if (attempt >= maxAttempts) rethrow;
      } on http.ClientException {
        if (isCancelled()) throw const UpdatePlatformCancelledException();
        if (attempt >= maxAttempts) rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 600 * attempt));
    }
  }

  @override
  Future<void> launchInstaller(String path) async {
    try {
      final launched = await _channel.invokeMethod<bool>('installApk', {'path': path});
      if (launched != true) {
        throw const UpdatePlatformException('Android could not open the installer.');
      }
    } on PlatformException catch (error) {
      throw UpdatePlatformException(
        error.message ?? 'Android could not open the installer.',
      );
    }
  }
}
