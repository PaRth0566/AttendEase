import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A PDF handed to AttendEase from outside the app.
class IncomingPdf {
  const IncomingPdf({required this.bytes, required this.name});

  /// The file's contents, already read on the native side.
  final Uint8List bytes;

  /// The display name, for showing the user which file they tapped. Falls back
  /// to `report.pdf` when the provider does not expose one.
  final String name;
}

/// Receives attendance PDFs opened from Android's "Open with" chooser or Share
/// sheet.
///
/// The app can already import a report three ways — the setup upload screen, the
/// Sync New Report screen, and the dashboard's one-tap button — but all three
/// start at the file picker, so the user has to be inside AttendEase first. This
/// is the other direction: tap a PDF anywhere on the phone, pick AttendEase, and
/// the same import runs.
///
/// Two delivery paths, because Android has two:
///
///   * **Cold start** — the launch intent is delivered before the Flutter engine
///     exists, so there is nobody to push it to. The native side parks it and
///     Dart pulls it with [takeInitialPdf].
///   * **Warm start** — the activity is `singleTop`, so a later tap arrives at
///     `onNewIntent` and is pushed straight here as [onPdfReceived].
///
/// Bytes are read natively rather than passed as a path: the chooser hands over
/// a `content://` URI that Dart's `File` cannot open, and the read grant only
/// lives as long as the intent's delivery.
class IncomingPdfService {
  IncomingPdfService._() {
    if (_supported) {
      _channel.setMethodCallHandler(_onNativeCall);
    }
  }

  static final IncomingPdfService instance = IncomingPdfService._();

  static const MethodChannel _channel = MethodChannel(
    'com.parthm.attendease/incoming_pdf',
  );

  /// Android only. The manifest filters and the channel are both Android-side,
  /// so on web and every other platform this service is inert rather than
  /// throwing `MissingPluginException` at whoever calls it.
  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Fires when a PDF arrives while the app is already running.
  final ValueNotifier<IncomingPdf?> onPdfReceived =
      ValueNotifier<IncomingPdf?>(null);

  /// A PDF that arrived before anyone could act on it.
  ///
  /// The case that matters is a signed-out user: the report is real and worth
  /// keeping, but it cannot be imported until they are through login and setup.
  /// Parked here rather than discarded so the tap is not wasted.
  IncomingPdf? _held;

  /// Stashes [pdf] until the app is in a state that can import it.
  void hold(IncomingPdf pdf) => _held = pdf;

  /// Returns and clears the held PDF, if any.
  IncomingPdf? takeHeld() {
    final pdf = _held;
    _held = null;
    return pdf;
  }

  bool get hasHeld => _held != null;

  /// The PDF this app was launched with, or null for an ordinary launch.
  ///
  /// Clears it on the native side as it reads, so returning to the app later
  /// does not re-import the same file.
  Future<IncomingPdf?> takeInitialPdf() async {
    if (!_supported) return null;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getInitialPdf',
      );
      return _fromPayload(result);
    } catch (error) {
      debugPrint('Incoming PDF check skipped: $error');
      return null;
    }
  }

  Future<void> _onNativeCall(MethodCall call) async {
    if (call.method != 'onPdfReceived') return;
    final pdf = _fromPayload(
      (call.arguments as Map?)?.cast<String, dynamic>(),
    );
    if (pdf == null) return;
    // Reassigned even when the previous value was non-null: a second tap is a
    // newer intent than the first, and the listener consumes on every change.
    onPdfReceived.value = pdf;
  }

  IncomingPdf? _fromPayload(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final bytes = payload['bytes'];
    if (bytes is! Uint8List || bytes.isEmpty) return null;
    final name = payload['name'];
    return IncomingPdf(
      bytes: bytes,
      name: name is String && name.trim().isNotEmpty
          ? name.trim()
          : 'report.pdf',
    );
  }
}
