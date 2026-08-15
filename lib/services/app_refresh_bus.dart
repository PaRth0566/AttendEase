import 'package:flutter/foundation.dart';

/// Broadcasts "the stored data changed underneath you — re-read it".
///
/// The tab pages are all alive at once inside `RootScreen`, which is the only
/// place holding a handle on each of them ([TabPageState.reloadData]). Anything
/// deeper in the tree that rewrites the database — the dashboard's one-tap
/// report sync, most notably — has no way to reach its siblings, so a fresh
/// import used to leave the Calendar and Profile tabs showing the previous
/// report until they were rebuilt.
///
/// A single app-wide notifier keeps that decoupled: writers call [refreshAll]
/// and know nothing about who is listening; `RootScreen` listens and reloads
/// every mounted page. Not a stream, so there is no subscription to leak and a
/// late listener simply misses events it was not around for — which is correct
/// here, since a page built after the write already reads the new data in its
/// own `initState`.
class AppRefreshBus extends ChangeNotifier {
  AppRefreshBus._();

  static final AppRefreshBus instance = AppRefreshBus._();

  /// Asks every listening screen to re-read its data in place.
  void refreshAll() => notifyListeners();
}
