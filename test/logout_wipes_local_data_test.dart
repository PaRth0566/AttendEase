// Regression: signing out on the web left the previous account's data behind.
//
// `AuthService.signOut()` wiped the local database only under `if (!kIsWeb)`,
// on the assumption that the web build has no database. It does — db_helper.dart
// opens one through `databaseFactoryFfiWeb`, backed by IndexedDB — so on web the
// rows survived sign-out. `prefs.clear()` still ran and the router's memoised
// "has setup data?" answer was invalidated, so the next `/app/*` redirect
// re-queried, found the *previous* user's subjects still present, and admitted
// the new user straight into them: one account seeing another's attendance on a
// shared browser.
//
// ## Why this reads the source instead of calling signOut()
//
// The behavioural test — seed the database, call signOut(), assert every table
// is empty — is the one worth having, and it is not reachable here: AuthService
// holds `FirebaseAuth.instance` and a `GoogleSignIn`, so constructing one needs
// a live Firebase app, and signOut() talks to both providers before it touches
// the database. There is no seam to inject past them today.
//
// So this asserts the narrower invariant the plan calls for instead: that the
// wipe is unconditional. That is exactly the bug — the wipe was never missing,
// only skipped on one platform — and it is the one property a platform guard
// creeping back in would break. It cannot catch a wipe that runs and fails; the
// try/catch there is deliberate and logs.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The body of `AuthService.signOut()`, from its signature to the router-cache
/// invalidation that closes it, **with line comments stripped**.
///
/// Stripping matters: the wipe carries a comment explaining why it is *not*
/// guarded by `kIsWeb`, so a raw substring search would match the explanation
/// of the fix and report the bug it documents.
String signOutCode() {
  final source = File('lib/services/auth_service.dart').readAsStringSync();

  const signature = 'Future<void> signOut() async {';
  final start = source.indexOf(signature);
  expect(
    start,
    isNot(-1),
    reason:
        'AuthService.signOut() was renamed or resignatured; this test '
        'reads it by name and can no longer find it',
  );

  // The invalidation is the last statement in the method and exists precisely
  // because the wipe above it ran, so it is a stable end marker.
  const terminator = 'AppRouter.invalidateDataCache();';
  final end = source.indexOf(terminator, start);
  expect(
    end,
    isNot(-1),
    reason:
        'signOut() no longer ends by invalidating the router data cache; '
        'if the wipe moved, move this test with it',
  );

  return source
      .substring(start, end)
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');
}

void main() {
  test('signOut wipes local data on every platform, web included', () {
    final code = signOutCode();

    expect(
      code,
      isNot(contains('kIsWeb')),
      reason:
          'the local-data wipe is guarded by a platform check again. The '
          'web build has a real IndexedDB-backed database, so skipping the '
          'wipe there leaks one account\'s subjects into the next session.',
    );
  });

  test('signOut wipes every table that holds user data', () {
    final code = signOutCode();

    // The full set db_helper.dart creates. A table added to the schema and not
    // added here would survive sign-out and leak the same way.
    for (final table in const [
      'attendance_records',
      'timetable',
      'subjects',
      'imported_report_dates',
    ]) {
      expect(
        code,
        contains("delete('$table')"),
        reason: '$table is not wiped on sign-out',
      );
    }

    expect(
      code,
      contains('prefs.clear()'),
      reason:
          'SharedPreferences still holds the previous account\'s setup '
          'flags and target percentage',
    );
  });
}
