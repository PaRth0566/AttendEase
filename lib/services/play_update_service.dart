import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

/// Google Play in-app updates, flexible flow.
///
/// Replaces the old GitHub-releases updater. Play now distributes every build,
/// so the app no longer downloads or sideloads an APK itself — it asks Play
/// whether a newer build is on the user's track and, if so, lets Play download
/// it in the background while the app stays usable, then prompts to restart.
///
/// Android only. Every call is a no-op on web, and on a build that was not
/// installed from Play (a `flutter run`, an emulator, a sideload) the platform
/// throws `ERROR_API_NOT_AVAILABLE` — caught and logged rather than surfaced,
/// exactly as the previous startup flow swallowed its errors.
class PlayUpdateService {
  PlayUpdateService._();
  static final PlayUpdateService instance = PlayUpdateService._();

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Startup path: check for an update and, if a flexible one is offered, start
  /// the background download and complete (prompt to restart) when it lands.
  /// Silent on every failure — this runs unattended at launch.
  Future<void> checkAndStartFlexibleUpdate() async {
    if (!_supported) return;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        return;
      }
      if (info.flexibleUpdateAllowed) {
        await InAppUpdate.startFlexibleUpdate();
        // Resolves once the download finishes; this installs it (a restart
        // prompt). If the user backgrounds the app mid-download it resolves
        // later; a failure here is non-fatal and swallowed below.
        await InAppUpdate.completeFlexibleUpdate();
      } else if (info.immediateUpdateAllowed) {
        // Track allows only an immediate (full-screen) update — take it rather
        // than leave the user stranded on an old build.
        await InAppUpdate.performImmediateUpdate();
      }
    } catch (error) {
      debugPrint('Play in-app update check skipped: $error');
    }
  }

  // There is deliberately no manual "check for updates" entry point. Play
  // auto-updates in the background and the launch check above already covers
  // the on-demand case, so the Profile tile that used to call one was dropped
  // rather than kept as a third path to the same result.
}
