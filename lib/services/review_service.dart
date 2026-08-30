import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Google Play in-app reviews, gated on genuine engagement.
///
/// Two paths:
///
///   * [openStoreListing] — the always-available, user-initiated path behind the
///     Profile "Rate AttendEase" tile. Not quota-limited; just opens the Play
///     listing where the user can leave a rating.
///   * [maybeRequestReview] — the native in-app rating dialog. Play enforces a
///     strict, invisible quota on it, so it is fired only at a natural positive
///     moment (a completed report sync) after a few of them, never on the very
///     first action, never during onboarding or after an error, and at most once
///     every 30 days. Even then Play may show nothing — that is normal and silent.
///
/// The store listing display of ratings/reviews is entirely Play's: once a user
/// submits through the dialog (on the production track) or rates from the
/// listing, Google aggregates it into the app's star rating and review list. The
/// app only *triggers* the prompt; it neither displays nor fetches those totals.
class ReviewService {
  ReviewService._();
  static final ReviewService instance = ReviewService._();

  final InAppReview _inAppReview = InAppReview.instance;

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
      await prefs.setInt(
        _lastPromptKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (error) {
      debugPrint('In-app review request skipped: $error');
    }
  }
}
