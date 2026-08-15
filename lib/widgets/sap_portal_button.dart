import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// A circular "open the SAP portal" button for a screen's AppBar.
///
/// The report this app imports comes from SVKM's SAP portal, so the trip to
/// fetch a fresh one starts there. It sits immediately left of
/// [SyncReportButton] in the dashboard's AppBar, in that order because that is
/// the order of the task: download the report from SAP, then sync it here.
///
/// Deliberately the same 40px chip, grey surface and tinted glyph as its
/// neighbour rather than a variation on it — the two are one pair of controls,
/// and any difference in size or weight would read as one being more important
/// than the other.
///
/// The artwork is a transparent-background PNG tinted to the theme's content
/// colour, so it reads white on the dark theme and dark on the light one with
/// nothing of its own drawn behind it.
class SapPortalButton extends StatelessWidget {
  const SapPortalButton({super.key});

  /// The SVKM SAP portal. The same address the Sync New Report screen and the
  /// setup upload screen open.
  static final Uri portalUrl = Uri.parse(
    'https://sdc-sppap1.svkm.ac.in:50001/irj/portal',
  );

  /// Outer diameter. Matches [SyncReportButton] exactly — see the class doc.
  static const double _size = 40;

  /// Hands the portal to the browser rather than an in-app view: the login is
  /// the university's own, and a session started in the user's real browser is
  /// the one that already holds their credentials.
  Future<void> _open(BuildContext context) async {
    bool launched = false;
    try {
      launched = await launchUrl(
        portalUrl,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // A platform channel failure (no browser installed, a blocked intent)
      // throws rather than returning false. Both mean the same thing to the
      // user, so both land on the same message below.
      launched = false;
    }
    if (launched || !context.mounted) return;

    // Keep the status colour on the icon; the snackbar surface follows the
    // active light/dark theme.
    final c = context.appColors;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline_rounded, size: 20, color: c.danger),
              const SizedBox(width: AppDimens.space12),
              const Expanded(child: Text('Could not launch SAP Portal.')),
            ],
          ),
          duration: const Duration(seconds: 5),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.appColors;
    final Color content =
        theme.textTheme.bodyLarge?.color ?? theme.colorScheme.onSurface;

    return Semantics(
      button: true,
      label: 'Open SAP Portal',
      child: Tooltip(
        message: 'SAP Portal',
        child: SizedBox.square(
          dimension: _size,
          child: Material(
            color: c.subtleSurface,
            shape: CircleBorder(side: BorderSide(color: c.cardBorder)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _open(context),
              customBorder: const CircleBorder(),
              child: Center(
                // A bare glyph on a transparent background, so a plain srcIn
                // tint is all it needs: the alpha channel already separates
                // mark from nothing, and every visible pixel takes the theme's
                // content colour.
                child: Image.asset(
                  'assets/icon/sap_icon.png',
                  // Larger than the sync button's 20px arrow on purpose. That
                  // glyph is a chunky, roughly square mark that fills its
                  // canvas; the SAP logo is a wide one (~2:1) sitting in a
                  // square source, so fitting it into the same box renders it
                  // only about half as tall and it reads small and adrift
                  // inside the circle. 24 brings the mark up to the visual
                  // weight of its neighbour while keeping an 8px margin to the
                  // chip's border.
                  width: 24,
                  height: 24,
                  color: content.withValues(alpha: 0.85),
                  colorBlendMode: BlendMode.srcIn,
                  // The source is much larger than 24px, so it is filtered on
                  // the way down rather than left to alias along the mark's
                  // diagonal edge.
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps [SapPortalButton] with the inset that spaces it from the sync button.
///
/// Only a leading gap: the trailing one comes from `SyncReportAction`'s own
/// left padding, so the pair keeps a single 8px gap between them instead of
/// stacking two.
class SapPortalAction extends StatelessWidget {
  const SapPortalAction({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(
        left: AppDimens.space8,
        top: AppDimens.space8,
        bottom: AppDimens.space8,
      ),
      child: SapPortalButton(),
    );
  }
}
