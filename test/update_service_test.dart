import 'package:attend_ease/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('semantic version comparison', () {
    test('recognizes patch, minor, and major updates', () {
      expect(UpdateService.isNewerVersion('1.0.4', '1.0.3'), isTrue);
      expect(UpdateService.isNewerVersion('1.1.0', '1.0.3'), isTrue);
      expect(UpdateService.isNewerVersion('2.0.0', '1.2.8'), isTrue);
    });

    test('does not report equal or older versions', () {
      expect(UpdateService.isNewerVersion('1.0.3', '1.0.3'), isFalse);
      expect(UpdateService.isNewerVersion('1.0.2', '1.0.3'), isFalse);
      expect(UpdateService.isNewerVersion('0.9.9', '1.0.0'), isFalse);
    });

    test('compares numerically, not lexicographically', () {
      // The classic string-compare trap: "1.0.10" < "1.0.9" as strings.
      expect(UpdateService.isNewerVersion('1.0.10', '1.0.9'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.9', '1.0.10'), isFalse);
      expect(UpdateService.isNewerVersion('1.10.0', '1.9.9'), isTrue);
      expect(UpdateService.isNewerVersion('2.0.0', '1.9.9'), isTrue);
    });

    test('does not treat a downgrade as an update', () {
      expect(UpdateService.isNewerVersion('2.1.4', '2.1.5'), isFalse);
    });

    test('accepts tags and build metadata but rejects invalid versions', () {
      expect(UpdateService.isNewerVersion('v1.1.0+7', '1.0.9'), isTrue);
      expect(UpdateService.isNewerVersion('v2.0.0', '1.0.0'), isTrue);
      expect(UpdateService.isNewerVersion('1.2.3-beta.1', '1.2.2'), isTrue);
      expect(UpdateService.isNewerVersion('latest', '1.0.9'), isFalse);
      expect(UpdateService.isNewerVersion('', '1.0.9'), isFalse);
      expect(UpdateService.isNewerVersion('1.0', '1.0.9'), isFalse);
      expect(UpdateService.isNewerVersion('1.0.0.1', '1.0.0'), isFalse);
    });
  });
}
