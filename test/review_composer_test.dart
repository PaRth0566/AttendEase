// The Profile "Rate AttendEase" tile must open Play's review page for the app —
// the ratings section where "Write feedback" lives — on *every* tap, whether or
// not the user has already left a review.
//
// It deliberately does not use the native in-app review sheet. Play suppresses
// that sheet on an invisible quota and for users who already reviewed, and gives
// the app no way to detect either case, so a button wired to it silently does
// nothing. These tests pin that down: no `requestReview` ever, a review deep
// link every time, and the automatic post-sync prompt left untouched.
import 'package:attend_ease/services/review_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const MethodChannel _reviewChannel = MethodChannel(
  'dev.britannio.in_app_review',
);
const MethodChannel _launcherChannel = MethodChannel(
  'plugins.flutter.io/url_launcher',
);
const MethodChannel _nativeChannel = MethodChannel(
  'com.parthm.attendease/play_review',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Method calls seen on the in_app_review channel, in order.
  late List<String> reviewCalls;

  /// URLs passed to url_launcher's `launch`, in order.
  late List<String> launched;

  /// Package ids the native launcher was asked to open, in order.
  late List<String> nativeOpened;

  /// What the native launcher reports: true = a Play review page was opened.
  /// Null stands in for a build whose native side is missing the handler.
  late bool? nativeResult;

  /// Whether `canLaunch` accepts the `market://` scheme, as a device with the
  /// Play Store installed does.
  late bool marketLaunchable;

  void mock() {
    final binding = TestDefaultBinaryMessengerBinding.instance;

    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _nativeChannel,
      (call) async {
        if (call.method != 'openReviewPage') return null;
        nativeOpened.add((call.arguments as Map)['packageId'] as String);
        if (nativeResult == null) {
          throw MissingPluginException('No implementation found');
        }
        return nativeResult;
      },
    );

    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _reviewChannel,
      (call) async {
        reviewCalls.add(call.method);
        switch (call.method) {
          case 'isAvailable':
            return true;
          case 'openStoreListing':
            launched.add('plugin:openStoreListing');
            return null;
        }
        return null;
      },
    );

    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _launcherChannel,
      (call) async {
        final String url = (call.arguments as Map)['url'] as String;
        switch (call.method) {
          case 'canLaunch':
            return url.startsWith('market://') ? marketLaunchable : true;
          case 'launch':
            if (url.startsWith('market://') && !marketLaunchable) return false;
            launched.add(url);
            return true;
        }
        return null;
      },
    );
  }

  setUp(() {
    reviewCalls = <String>[];
    launched = <String>[];
    nativeOpened = <String>[];
    nativeResult = true;
    marketLaunchable = true;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    mock();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    final binding = TestDefaultBinaryMessengerBinding.instance;
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(_reviewChannel, null);
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcherChannel, null);
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(_nativeChannel, null);
  });

  test('the tile opens the Play review page, never the in-app sheet', () async {
    final bool opened = await ReviewService.instance.openReviewComposer();

    expect(opened, isTrue);
    expect(nativeOpened, <String>['com.parthm.attendease']);
    // The regression this guards: `requestReview()` is quota-gated and
    // undetectable, so a button must not depend on it.
    expect(reviewCalls, isEmpty);
    expect(launched, isEmpty);
  });

  test('every tap opens it again, with nothing accumulating in between',
      () async {
    for (int tap = 0; tap < 5; tap++) {
      expect(await ReviewService.instance.openReviewComposer(), isTrue);
    }

    // Five taps, five openings — no quota, no once-per-30-days floor, and no
    // "already reviewed" state can make a later tap do less than the first.
    expect(nativeOpened, hasLength(5));
    expect(reviewCalls, isEmpty);
  });

  test('the tile does not consume the automatic prompt\'s 30-day floor',
      () async {
    await ReviewService.instance.openReviewComposer();

    final prefs = await SharedPreferences.getInstance();
    // Opening the Play page is not showing the native sheet, so it must not
    // stamp the timestamp that holds the automatic prompt back.
    expect(prefs.getInt('review.last_prompt_at'), isNull);
  });

  test('a native launcher that opens nothing falls back to a review deep link',
      () async {
    nativeResult = false;

    final bool opened = await ReviewService.instance.openReviewComposer();

    expect(opened, isTrue);
    expect(launched.single, startsWith('market://details'));
    expect(launched.single, contains('showAllReviews=true'));
    expect(launched.single, contains('reviewId=0'));
  });

  test('a missing native handler still lands on the review page', () async {
    // An install whose Kotlin side predates PlayReviewLauncher.
    nativeResult = null;

    final bool opened = await ReviewService.instance.openReviewComposer();

    expect(opened, isTrue);
    expect(launched.single, contains('showAllReviews=true'));
    expect(reviewCalls, isEmpty);
  });

  test('without the Play app the https review URL is used', () async {
    nativeResult = false;
    marketLaunchable = false;

    final bool opened = await ReviewService.instance.openReviewComposer();

    expect(opened, isTrue);
    expect(launched.single, startsWith('https://play.google.com/store/apps'));
    expect(launched.single, contains('showAllReviews=true'));
    expect(launched.single, contains('reviewId=0'));
  });

  test('off Android the web listing is the only path', () async {
    // Stands in for the web build, the app's only non-Android target: `kIsWeb`
    // cannot be toggled from a test, but it guards the same branch as the
    // platform check, and a non-Android platform reaches it identically.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    final bool opened = await ReviewService.instance.openReviewComposer();

    expect(opened, isTrue);
    expect(nativeOpened, isEmpty);
    expect(reviewCalls, isNot(contains('requestReview')));
    expect(launched, isNotEmpty);
  });

  test('the automatic post-sync prompt still uses the native sheet', () async {
    // The sheet is right for an unprompted moment — it just cannot back a
    // button. That path is unchanged.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('review.positive_action_count', 5);

    await ReviewService.instance.maybeRequestReview();

    expect(reviewCalls, <String>['isAvailable', 'requestReview']);
    expect(prefs.getInt('review.last_prompt_at'), isNotNull);
  });
}
