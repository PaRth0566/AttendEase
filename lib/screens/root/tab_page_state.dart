import 'package:flutter/widgets.dart';

/// A tab page that can re-read its data in place, without being rebuilt.
///
/// The three tabs used to be swapped by building one page at a time, so
/// "arriving at a tab" and "loading that tab's data" were the same event: the
/// page did not exist until you selected it, and `initState` did the read. That
/// coupling is what made tab switches expensive — see the note on
/// `_RootScreenState._buildBody`.
///
/// Now the pages are all alive at once and only their visibility changes, so
/// the two events have to be separated: [RootScreen] switches instantly and
/// asks the page it just revealed to refresh itself afterwards. Implementations
/// keep their current content on screen while the read is in flight, which is
/// why this is a reload rather than a rebuild — a rebuild would drop back to
/// the skeleton state every time you crossed the bar.
abstract class TabPageState<T extends StatefulWidget> extends State<T> {
  /// Re-reads this page's data. Safe to call while the page is off-screen.
  Future<void> reloadData();
}
