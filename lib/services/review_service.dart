import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Google Play ratings and reviews.
///
/// Three paths:
///
///   * [openReviewComposer] — the user-initiated path behind the Profile
///     "Rate AttendEase" tile. Always opens Play's review page for AttendEase,
///     deep-linked to the ratings section where "Write feedback" lives, on
///     *every* tap — whether or not the user has already reviewed, and whether
///     or not Play's in-app quota would have allowed a sheet.
///   * [maybeRequestReview] — the native in-app sheet (stars + review box drawn
///     over the app), fired automatically at a natural positive moment (a
///     completed report sync) after a few of them, never on the very first
///     action, never during onboarding or after an error, and at most once
///     every 30 days.
///   * [openStoreListing] — the plain store listing. The last-resort fallback,
///     and the only path that exists on web.
///
/// The split matters. The native sheet is the nicer experience — the user never
/// leaves the app — but Play enforces an invisible, undetectable quota on it:
/// `requestReview()` completes identically whether the sheet appeared or was
/// silently dropped, and it never appears at all for a user who already
/// reviewed. Google's own guidance is therefore not to put it behind a button.
/// So the tile does not use it: a button must do the same visible thing every
/// time, and only the Play deep link can promise that.
///
/// The store display of ratings/reviews is entirely Play's: once a user submits,
/// Google aggregates it into the app's star rating and review list — for a
/// testing track it goes to the developer as private feedback instead. The app
/// only *opens* the page; it neither displays nor fetches those totals.
class ReviewService {
  ReviewService._();
  static final ReviewService instance = ReviewService._();

  final InAppReview _inAppReview = InAppReview.instance;

  /// Native side of the review deep link. Needs an explicit Play package and a
  /// `resolveActivity` check, neither of which `url_launcher` exposes — see
  /// `PlayReviewLauncher.kt`.
  static const MethodChannel _channel = MethodChannel(
    'com.parthm.attendease/play_review',
  );

  static const _packageId = 'com.parthm.attendease';
  static const _countKey = 'review.positive_action_count';
  static const _lastPromptKey = 'review.last_prompt_at';

  /// How many positive actions before the dialog may fire. The first action is
  /// deliberately excluded (we do not prompt on first use), so this is the
  /// user's Nth meaningful success.
  static const _minPositiveActions = 3;

  /// Do not re-prompt within this window, matching Play's own spirit of not
  /// nagging. Play's hidden quota is stricter still; this is our own floor.
  static const _minInterval = Duration(days: 30);

  /// Opens Play's review page for AttendEase, and returns false only if nothing
  /// at all could be opened.
  ///
  /// This is deliberately unconditional: the same page opens on every tap, for
  /// a user who has already left a review as much as for one who has not. No
  /// native sheet is attempted here even though it looks like the more direct
  /// option, because it cannot deliver that guarantee — Play suppresses it on
  /// quota and for users who already reviewed, gives the app no way to detect
  /// either, and the tile would then appear to do nothing at all.
  ///
  /// The native side tries the review deep links pinned to the Play app,
  /// falling back through less specific forms and finally to a browser. On web
  /// (and anything that is not Android) there is no Play app, so the https
  /// listing is the only possibility.
  Future<bool> openReviewComposer() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return openStoreListing();
    }

    try {
      final bool? opened = await _channel.invokeMethod<bool>(
        'openReviewPage',
        <String, Object?>{'packageId': _packageId},
      );
      if (opened ?? false) return true;
    } catch (error) {
      // MissingPluginException on an old install of the app, or a platform
      // error. Either way the Dart-side launch below still works.
      debugPrint('Native review deep link unavailable: $error');
    }

    return _openRatingsSection();
  }

  /// The Play listing's ratings and reviews section, launched from Dart.
  ///
  /// Reached only when the native channel could not open anything. `url_launcher`
  /// cannot pin the intent to Play, so a browser may take the https form — which
  /// is still the review page, just on the web listing.
  Future<bool> _openRatingsSection() async {
    final Uri market = Uri.parse(
      'market://details?id=$_packageId&showAllReviews=true&reviewId=0',
    );
    try {
      if (await canLaunchUrl(market)) {
        if (await launchUrl(market, mode: LaunchMode.externalApplication)) {
          return true;
        }
      }
    } catch (_) {
      // Fall through to the https listing.
    }

    final Uri web = Uri.parse(
      'https://play.google.com/store/apps/details'
      '?id=$_packageId&showAllReviews=true&reviewId=0',
    );
    try {
      if (await launchUrl(web, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (error) {
      debugPrint('Could not open Play ratings section: $error');
    }

    return openStoreListing();
  }

  /// Opens the Play Store listing so the user can rate/review directly. On
  /// Android it tries the `market://` deep link first (opens the Play app),
  /// then falls back to the https listing. On web there is no Play app, so it
  /// goes straight to the https listing in a new tab.
  ///
  /// Returns false if nothing could be opened, so a caller on web can tell the
  /// user (e.g. the listing is not public yet) instead of leaving them on a
  /// Play "URL not found" page.
  Future<bool> openStoreListing() async {
    final web = Uri.parse(
      'https://play.google.com/store/apps/details?id=$_packageId',
    );

    // On Android, in_app_review's own helper opens the native listing cleanly.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _inAppReview.openStoreListing();
        return true;
      } catch (_) {
        // Fall through to the manual launch below.
      }
      final market = Uri.parse('market://details?id=$_packageId');
      try {
        if (await canLaunchUrl(market)) {
          await launchUrl(market, mode: LaunchMode.externalApplication);
          return true;
        }
      } catch (_) {
        // Fall through to the web listing.
      }
    }

    try {
      final ok = await launchUrl(web, mode: LaunchMode.externalApplication);
      return ok;
    } catch (error) {
      debugPrint('Could not open Play Store listing: $error');
      return false;
    }
  }

  /// Records that a genuine success just happened (a completed report sync).
  /// Increments the running count the review gate reads.
  Future<void> registerPositiveAction() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = (prefs.getInt(_countKey) ?? 0) + 1;
      await prefs.setInt(_countKey, count);
    } catch (error) {
      debugPrint('Could not record positive action for review gate: $error');
    }
  }

  /// Requests the native in-app review dialog if every gate passes: enough
  /// positive actions, not the first one, no prompt in the last 30 days, and the
  /// API reports itself available. Silent on every failure — a review prompt is
  /// never worth interrupting the user with an error.
  Future<void> maybeRequestReview() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = prefs.getInt(_countKey) ?? 0;
      if (count < _minPositiveActions) return;

      final lastPromptMs = prefs.getInt(_lastPromptKey);
      if (lastPromptMs != null) {
        final since = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(lastPromptMs),
        );
        if (since < _minInterval) return;
      }

      if (!await _inAppReview.isAvailable()) return;
      await _inAppReview.requestReview();
      await _recordPromptShown();
    } catch (error) {
      debugPrint('In-app review request skipped: $error');
    }
  }

  /// Stamps "the rating sheet was requested just now", which is what the 30-day
  /// floor in [maybeRequestReview] reads. Only the automatic path writes this:
  /// [openReviewComposer] no longer touches the in-app sheet at all, so a tap on
  /// the tile cannot consume the sheet's quota and has nothing to record.
  Future<void> _recordPromptShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastPromptKey, DateTime.now().millisecondsSinceEpoch);
    } catch (error) {
      debugPrint('Could not record review prompt timestamp: $error');
    }
  }
}
