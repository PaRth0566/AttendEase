import 'update_platform_contract.dart';

UpdatePlatform createUpdatePlatform() => _UnsupportedUpdatePlatform();

class _UnsupportedUpdatePlatform implements UpdatePlatform {
  @override
  bool get isSupported => false;

  @override
  UpdateDownload download({
    required Uri url,
    required String version,
    required String expectedSha256,
  }) {
    throw UnsupportedError('In-app installation is only available on Android.');
  }

  @override
  Future<void> launchInstaller(String path) {
    throw UnsupportedError('In-app installation is only available on Android.');
  }
}
