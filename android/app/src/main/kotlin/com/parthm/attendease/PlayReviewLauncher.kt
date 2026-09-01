package com.parthm.attendease

import android.content.Context
import android.content.Intent
import android.net.Uri

/**
 * Opens the Google Play review page for this app as directly as Play allows.
 *
 * This exists because `url_launcher` cannot do the two things that make the
 * difference here:
 *
 *   * **Target the Play app explicitly.** A bare `market://` launch goes through
 *     the normal chooser/default-handler path; setting the package pins it to
 *     Play (`com.android.vending`) so the review deep-link parameters are seen
 *     by the app that understands them instead of, say, a browser.
 *   * **Ask before launching.** `resolveActivity` says whether a given intent
 *     will actually land, so a URI form a particular Play build does not honour
 *     can be skipped rather than dumping the user somewhere wrong.
 *
 * Play publishes no documented deep link to the review composer — the only
 * documented paths are the (quota-gated, undetectable) In-App Review API and the
 * plain store listing. What *does* exist is a set of long-standing review
 * parameters that Play builds have honoured to varying degrees over the years.
 * They are tried most-specific-first and the first one that resolves wins, so a
 * Play build that honours the composer form gets it and one that does not still
 * lands on the reviews section rather than the top of the listing.
 */
object PlayReviewLauncher {
    private const val PLAY_PACKAGE = "com.android.vending"

    /**
     * Review deep links, most direct first.
     *
     * `reviewId=0` is the older of the two hints: Play treats it as "scroll to a
     * review", finds no review with that id, and settles on the user-reviews
     * section. Pairing it with `showAllReviews=true` is what gets current builds
     * onto the ratings screen the "Write feedback" control lives on, rather than
     * the listing header.
     */
    private fun candidates(packageId: String): List<Uri> = listOf(
        Uri.parse("market://details?id=$packageId&showAllReviews=true&reviewId=0"),
        Uri.parse("market://details?id=$packageId&reviewId=0"),
        Uri.parse("market://details?id=$packageId&showAllReviews=true"),
        Uri.parse(
            "https://play.google.com/store/apps/details" +
                "?id=$packageId&showAllReviews=true&reviewId=0",
        ),
    )

    /**
     * Launches the review page for [packageId], returning true if anything was
     * opened.
     *
     * Every candidate is tried pinned to Play first. Only if none of them
     * resolve — no Play app at all, which is a sideloaded device without the
     * store — does this fall back to an unpinned https launch that a browser can
     * take.
     */
    fun open(context: Context, packageId: String): Boolean {
        for (uri in candidates(packageId)) {
            if (launch(context, uri, pinToPlay = true)) return true
        }
        // No Play app. The web listing in a browser is the only thing left.
        return launch(
            context,
            Uri.parse("https://play.google.com/store/apps/details?id=$packageId"),
            pinToPlay = false,
        )
    }

    private fun launch(context: Context, uri: Uri, pinToPlay: Boolean): Boolean {
        val intent = Intent(Intent.ACTION_VIEW, uri).apply {
            if (pinToPlay) setPackage(PLAY_PACKAGE)
            // The flag set Android documents for sending a user to a Play
            // listing, and each one earns its place for a *repeatable* button:
            //
            //   NEW_TASK      — launched from a method channel, outside Play's
            //                   own task, so it needs a task of its own.
            //   NEW_DOCUMENT  — treat each launch as its own document rather
            //                   than reusing whatever Play screen is already
            //                   open, which is what makes the second tap land
            //                   on the review page instead of resuming a stale
            //                   listing.
            //   MULTIPLE_TASK — with NEW_DOCUMENT, forces the new URI to be
            //                   honoured rather than matched to an existing
            //                   task.
            //   NO_HISTORY    — Play does not linger in recents behind the app.
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_NEW_DOCUMENT or
                    Intent.FLAG_ACTIVITY_MULTIPLE_TASK or
                    Intent.FLAG_ACTIVITY_NO_HISTORY,
            )
        }
        if (intent.resolveActivity(context.packageManager) == null) return false
        return try {
            context.startActivity(intent)
            true
        } catch (error: Exception) {
            // resolveActivity said yes and startActivity still refused
            // (disabled component, locked profile). Treat as "not this one" and
            // let the caller try the next candidate.
            false
        }
    }
}
