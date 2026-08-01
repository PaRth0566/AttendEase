import 'package:flutter/widgets.dart';

import '../theme/app_breakpoints.dart';

/// Wraps a scrollable screen body in consistent gutters and a centered
/// max-width column, so content does not stretch full-bleed on wide windows.
///
/// Pass [web] for web screens so the 768 boundary and web gutter scale apply.
class ResponsiveBody extends StatelessWidget {
  const ResponsiveBody({super.key, required this.child, this.web = false});

  final Widget child;

  /// Use the web gutter scale ([AppBreakpoints.webGutter]) instead of the app one.
  final bool web;

  @override
  Widget build(BuildContext context) {
    final gutter = web
        ? AppBreakpoints.webGutter(context)
        : AppBreakpoints.gutter(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: AppBreakpoints.contentMaxWidth(context),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: child,
        ),
      ),
    );
  }
}
