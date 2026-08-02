import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/attendance_dao.dart';
import '../../database/subject_dao.dart';
import '../../services/auth_service.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/update_service.dart';
import '../../theme/app_breakpoints.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_motion.dart';
import '../../theme/container_transform.dart';
import '../../theme/theme_provider.dart'; // ✅ NEW IMPORT
import '../../widgets/app_overlays.dart';
import '../../widgets/backup_sync_card.dart';
import '../../widgets/pressable.dart';
import '../../widgets/smooth_theme_switch.dart';
import '../../widgets/theme_crossfade.dart';
import '../../widgets/update_dialog.dart';
import '../root/tab_page_state.dart';


class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => ProfileScreenState();
}

class ProfileScreenState extends TabPageState<ProfileScreen>
    with AutomaticKeepAliveClientMixin {
  // Kept alive so a tab slide composites this page instead of rebuilding it
  // mid-drag (§1.6).
  @override
  bool get wantKeepAlive => true;

  final AttendanceDao _attendanceDao = AttendanceDao();
  final SubjectDao _subjectDao = SubjectDao();

  String name = '';
  String course = '';
  String year = '';
  String division = '';
  int semester = 1;

  double overallAttendance = 0.0;

  /// Target %, for the hero card's status pill and the bar's target tick. Same
  /// pref the dashboard reads, so the two screens cannot disagree.
  double _requiredTarget = 75.0;

  bool _loading = true;
  String _appVersion = '';
  bool _checkingForUpdate = false;

  /// Drives the chevron rotation while the semester picker sheet is open.
  bool _semesterPickerOpen = false;

  /// First letters of the first two words of [name], for the avatar. Falls back
  /// to a single letter for a mononym and '?' for an empty name.
  String get _initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }

  /// The design shows a year span (`Year 2026 – 2027`); [year] holds one value.
  /// Render the span only when it parses as a real calendar year — an ordinal
  /// like "3" or "TY" is shown as entered, never as `Year 3 – 4`.
  String get _yearLabel {
    final int? start = int.tryParse(year.trim());
    if (start != null && start >= 1900 && start <= 2200) {
      return 'Year $start – ${start + 1}';
    }
    return year.trim().isEmpty ? '' : 'Year ${year.trim()}';
  }

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  @override
  Future<void> reloadData() => _loadProfileData();

  Future<void> _loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    semester = prefs.getInt('semester') ?? 1;
    _requiredTarget = prefs.getDouble('overall_required_attendance') ?? 75.0;

    final subjectsForSem = await _subjectDao.getSubjectsBySemester(semester);
    final stats = await _attendanceDao.getAttendanceStats(semester);

    int attended = 0;
    int total = 0;

    for (final sub in subjectsForSem) {
      final s = stats[sub.id];
      if (s != null) {
        attended += s['attended']!;
        total += s['total']!;
      }
    }

    setState(() {
      name = prefs.getString('full_name') ?? 'AttendEase User';
      course = prefs.getString('course') ?? '';
      year = prefs.getString('year') ?? '';
      division = prefs.getString('division') ?? '';

      overallAttendance = total == 0 ? 0.0 : (attended / total) * 100;
      _loading = false;
    });

    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = info.version;
        });
      }
    } catch (_) {}
  }

  Future<void> _switchSemester(int newSemester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('semester', newSemester);

    setState(() => _loading = true);
    await _loadProfileData();

    // Auto-sync after switching semester
    CloudSyncService().backupDataToCloud();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Switched to Semester $newSemester')),
    );
  }

  /// The hero card's semester switcher — a bottom sheet rather than an anchored
  /// dropdown, which would paint its own material over the bordered card.
  Future<void> _showSemesterPicker() async {
    setState(() => _semesterPickerOpen = true);
    final theme = Theme.of(context);
    final int? picked = await showAppModalSheet<int>(
      context: context,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Active Semester',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppDimens.space12),
              ...List.generate(8, (i) {
                final int sem = i + 1;
                final bool isCurrent = sem == semester;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.school_rounded,
                    color: isCurrent
                        ? theme.colorScheme.primary
                        : theme.textTheme.bodyMedium?.color,
                  ),
                  title: Text(
                    'Semester $sem',
                    style: TextStyle(
                      fontWeight:
                          isCurrent ? FontWeight.bold : FontWeight.w500,
                      color: isCurrent ? theme.colorScheme.primary : null,
                    ),
                  ),
                  trailing: isCurrent
                      ? Icon(Icons.check_rounded,
                          color: theme.colorScheme.primary)
                      : null,
                  onTap: () => Navigator.of(ctx).pop(sem),
                );
              }),
            ],
          ),
        );
      },
    );
    if (mounted) setState(() => _semesterPickerOpen = false);
    if (picked != null && picked != semester) await _switchSemester(picked);
  }

  /// Pull-to-refresh: bidirectional cloud sync then reload
  Future<void> _syncAndReload() async {
    await CloudSyncService().syncBidirectional();
    await _loadProfileData();
  }

  Future<void> _checkForUpdates() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('In-app updates are available on Android.')),
      );
      return;
    }
    if (_checkingForUpdate) return;
    // If the automatic startup sheet is already on screen, don't stack another.
    if (UpdateService.instance.isUpdateSheetVisible) return;
    setState(() => _checkingForUpdate = true);
    try {
      final update = await UpdateService.instance.checkForUpdate();
      if (!mounted) return;
      if (update == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Already up to date.')),
        );
      } else {
        await UpdateService.instance.runExclusiveSheet(
          () => showUpdateBottomSheet(context, update),
        );
      }
    } on UpdateException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not check for updates. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingForUpdate = false);
    }
  }

  /// Asks whether to log out anyway after the cloud backup failed. Logging out
  /// wipes local data, so without a cloud copy the data is unrecoverable —
  /// this is the last point at which the user can back out.
  Future<bool?> _confirmLogoutWithoutBackup(BuildContext ctx) {
    return showAppDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Backup Failed'),
        content: const Text(
          'Your data could not be backed up to the cloud, and logging out '
          'erases it from this device.\n\n'
          'Stay logged in and try syncing again, or log out and lose any '
          'changes since your last successful backup.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Stay Logged In'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text(
              'Log Out Anyway',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  /// Guests have no cloud document, so their data only ever exists on this
  /// device. Logging out deletes it outright — say so plainly.
  Future<bool?> _confirmGuestLogout(BuildContext ctx) {
    return showAppDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Guest Data?'),
        content: const Text(
          'Guest sessions are not backed up to the cloud. Logging out will '
          'permanently delete your attendance data from this device.\n\n'
          'To keep it, cancel and link a Google account in Account Settings '
          'first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text(
              'Log Out & Delete',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout() async {
    final rootContext = context; // capture before dialog opens
    showAppDialog(
      context: rootContext,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Log Out?'),
        content: const Text(
          'Your data will be securely backed up to the cloud before logging out.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(dialogCtx); // close confirmation dialog

              // Back up BEFORE tearing anything down, and only continue if it
              // worked. signOut() wipes the local database to stop one
              // account's attendance leaking into the next, so logging out on
              // a failed backup would destroy unsynced data with no copy
              // anywhere. Guests have no cloud document at all, so their
              // backup always reports false — they are handled separately.
              final user = FirebaseAuth.instance.currentUser;
              final isGuest = user?.isAnonymous ?? false;

              if (!isGuest) {
                showAppDialog(
                  context: rootContext,
                  barrierDismissible: false,
                  builder: (_) => const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                );

                bool backedUp = false;
                try {
                  backedUp = await CloudSyncService().backupDataToCloud();
                } catch (e) {
                  debugPrint('Logout backup failed: $e');
                }

                // Dismiss the spinner dialog.
                if (rootContext.mounted) Navigator.of(rootContext).pop();

                if (!backedUp) {
                  if (!rootContext.mounted) return;
                  final proceed = await _confirmLogoutWithoutBackup(rootContext);
                  if (proceed != true) return;
                }
              } else {
                if (!rootContext.mounted) return;
                final proceed = await _confirmGuestLogout(rootContext);
                if (proceed != true) return;
              }

              if (rootContext.mounted) {
                showAppDialog(
                  context: rootContext,
                  barrierDismissible: false,
                  builder: (_) => const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                );
              }

              try {
                // Wipes local data and clears prefs internally.
                await AuthService().signOut();
              } catch (e) {
                debugPrint('Logout failed: $e');
              }

              if (!rootContext.mounted) return;
              rootContext.go(kIsWeb ? '/web/home' : '/login');
            },
            child: const Text('Log Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    // Allows us to grab the current theme colors dynamically
    final theme = Theme.of(context);

    return Scaffold(
      // ✅ Removed hardcoded Colors.white
      appBar: AppBar(title: const Text('Profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: RefreshIndicator(
                  onRefresh: _syncAndReload,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      AppBreakpoints.isMobile(context) ? 16 : 32,
                      AppDimens.headerContentGap,
                      AppBreakpoints.isMobile(context) ? 16 : 32,
                      // Clears the floating glass nav bar (Scaffold reports its
                      // height as bottom padding under extendBody).
                      16 + MediaQuery.paddingOf(context).bottom,
                    ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hero card: identity + attendance breakdown, and the only
                  // semester switcher (§5). Its own bottom margin replaces the
                  // old SizedBox(32) + Active Semester row.
                  _heroCard(),

                  _themeToggleTile(),

                  _profileTile(
                    icon: Icons.person_rounded,
                    title: 'Edit Profile & Dates',
                    onTap: () => context.go('/app/profile/basic'),
                  ),

                  _profileTile(
                    icon: Icons.book_rounded,
                    title: 'Edit Subjects (Sem $semester)',
                    onTap: () => context.go('/app/profile/subjects'),
                  ),

                  _profileTile(
                    icon: Icons.schedule_rounded,
                    title: 'Edit Timetable (Sem $semester)',
                    onTap: () => context.go('/app/profile/timetable'),
                  ),

                  _profileTile(
                    icon: Icons.rule_rounded,
                    title: 'Attendance Preferences',
                    onTap: () => context.go('/app/profile/criteria'),
                  ),

                  _profileTile(
                    icon: Icons.bar_chart_rounded,
                    title: 'Reports & Analytics',
                    onTap: () => context.go('/app/profile/report'),
                  ),

                  _profileTile(
                    icon: Icons.cloud_sync_rounded,
                    title: 'Sync New Attendance Report',
                    onTap: () => context.go('/app/profile/refresh-pdf'),
                  ),

                  // Carries its own 12px bottom margin, matching the tiles'
                  // rhythm — no extra spacers, which made its gap wider before.
                  BackupSyncCard(onSyncComplete: _loadProfileData),

                  _profileTile(
                    icon: Icons.manage_accounts_rounded,
                    title: 'Account Settings',
                    onTap: () => context.go('/app/profile/account'),
                  ),

                  _profileTile(
                    icon: Icons.bug_report_rounded,
                    title: 'Report a Bug',
                    onTap: () => context.go('/app/profile/bug-report'),
                  ),

                  _profileTile(
                    icon: Icons.system_update_rounded,
                    title: _checkingForUpdate ? 'Checking for updates…' : 'Check for Updates',
                    enabled: !_checkingForUpdate,
                    trailing: _checkingForUpdate
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                    onTap: _checkForUpdates,
                  ),

                  _profileTile(
                    icon: Icons.logout_rounded,
                    title: 'Log Out',
                    isRedAlert: true,
                    onTap: _handleLogout,
                  ),

                  // Left-aligned under the cards. The Log Out tile already
                  // carries 12px below it, so only a small extra gap here, and
                  // a modest tail before the nav-bar clearance padding.
                  if (_appVersion.isNotEmpty) ...[
                    const SizedBox(height: AppDimens.space4),
                    Padding(
                      padding: const EdgeInsets.only(left: AppDimens.space4),
                      child: Text(
                        'Version $_appVersion',
                        style: TextStyle(
                          color: theme.textTheme.bodyMedium?.color?.withAlpha(150),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppDimens.space8),
                ],
              ),
                  ),
                ),
              ),
            ),
    );
  }

  /// The Profile hero card (§5): identity + semester switcher on top, the
  /// attendance breakdown below, split by a full-width divider.
  Widget _heroCard() {
    final theme = Theme.of(context);
    final c = context.appColors;
    final bool isAbove = overallAttendance >= _requiredTarget;
    final Color statusColor = isAbove ? c.success : c.danger;
    final String statusLabel = isAbove ? 'Above Target' : 'Below Target';
    final Color secondary =
        theme.textTheme.bodyMedium?.color ?? theme.colorScheme.onSurface;

    Widget vRule() => Container(
          width: 1,
          height: 36,
          margin: const EdgeInsets.symmetric(horizontal: AppDimens.space12),
          color: theme.dividerColor,
        );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppDimens.space24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(AppDimens.radiusXl),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        children: [
          // ── Upper row: identity + semester chip ──────────────
          Padding(
            padding: const EdgeInsets.all(AppDimens.space16),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: secondary.withAlpha(28),
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Text(
                    _initials,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: secondary,
                    ),
                  ),
                ),
                const SizedBox(width: AppDimens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                      if (course.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          course,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: secondary),
                        ),
                      ],
                      if (_yearLabel.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.calendar_today_rounded,
                                size: 14, color: secondary),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _yearLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: secondary),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppDimens.space12),
                _semesterChip(theme),
              ],
            ),
          ),

          Divider(height: 1, thickness: 1, color: theme.dividerColor),

          // ── Lower row: attendance breakdown, three columns ───
          // No IntrinsicHeight: _targetBar uses a LayoutBuilder, which cannot
          // answer intrinsic-dimension queries. The vertical rules carry their
          // own fixed height instead.
          Padding(
            padding: const EdgeInsets.all(AppDimens.space16),
            child: Row(
              children: [
                // col 1 — icon tile
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withAlpha(28),
                        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                      ),
                      child: Icon(Icons.percent_rounded,
                          color: theme.colorScheme.primary, size: 22),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Overall\nAttendance',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: secondary, height: 1.2),
                    ),
                  ],
                ),
                vRule(),
                // col 2 — figure + status pill
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Overall Attendance',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: secondary),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${overallAttendance.toStringAsFixed(1)}%',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: statusColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withAlpha(30),
                          borderRadius:
                              BorderRadius.circular(AppDimens.radiusPill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isAbove
                                  ? Icons.trending_up_rounded
                                  : Icons.trending_down_rounded,
                              size: 14,
                              color: statusColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              statusLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                vRule(),
                // col 3 — status + target bar
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              statusLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Target: ${_requiredTarget.toStringAsFixed(1)}%',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: secondary),
                      ),
                      const SizedBox(height: 8),
                      _targetBar(theme, statusColor),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Outlined chip: grad-cap + `Sem N` + chevron, all in primary. Opens the
  /// semester picker; the chevron rotates 180° while it is open.
  Widget _semesterChip(ThemeData theme) {
    final primary = theme.colorScheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        onTap: _showSemesterPicker,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            border: Border.all(color: primary.withAlpha(120)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.school_rounded, size: 16, color: primary),
              const SizedBox(width: 6),
              Text(
                'Sem $semester',
                style: TextStyle(
                  color: primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: _semesterPickerOpen ? 0.5 : 0.0,
                duration: AppMotion.standard,
                curve: AppMotion.morph,
                child: Icon(Icons.keyboard_arrow_down_rounded,
                    size: 18, color: primary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Horizontal progress bar with a vertical tick at the target, labelled below.
  Widget _targetBar(ThemeData theme, Color statusColor) {
    final double value = (overallAttendance / 100).clamp(0.0, 1.0);
    final double target = (_requiredTarget / 100).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final double w = constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 8,
              width: w,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: theme.dividerColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: value,
                    child: Container(
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Positioned(
                    left: (w * target).clamp(0.0, w - 2),
                    top: -2,
                    bottom: -2,
                    child: Container(
                      width: 2,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment((target * 2 - 1).clamp(-1.0, 1.0), 0),
              child: Text(
                '${_requiredTarget.toStringAsFixed(0)}%',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.textTheme.bodyMedium?.color),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _themeToggleTile() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: ListTile(
        leading: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          switchInCurve: Curves.easeInOutCubic,
          switchOutCurve: Curves.easeInOutCubic,
          transitionBuilder: (child, animation) => RotationTransition(
            turns: Tween<double>(begin: 0.5, end: 1.0).animate(animation),
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: Icon(
            isDark ? Icons.dark_mode_rounded : Icons.wb_sunny_rounded,
            key: ValueKey(isDark),
            color: theme.colorScheme.primary,
          ),
        ),
        title: const Text(
          'Dark Mode',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        trailing: SmoothThemeSwitch(
          value: isDark,
          onChanged: (bool value) {
            ThemeCrossfade.of(context).crossfade(
              () => themeProvider.setThemeMode(
                value ? ThemeMode.dark : ThemeMode.light,
              ),
              onMidpoint: () => SystemChrome.setSystemUIOverlayStyle(
                value
                    ? SystemUiOverlayStyle.light.copyWith(
                        statusBarColor: Colors.transparent,
                        systemNavigationBarColor: Colors.black,
                      )
                    : SystemUiOverlayStyle.dark.copyWith(
                        statusBarColor: Colors.transparent,
                        systemNavigationBarColor: Colors.white,
                      ),
              ),
            );
            setState(() {});
          },
        ),
      ),
    );
  }

  Widget _profileTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isRedAlert = false,
    bool enabled = true,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.space12),
      child: ContainerTransformAnchor(
        borderRadius: AppDimens.radiusMd,
        enabled: enabled,
        child: Pressable(
          onTap: enabled ? onTap : null,
          borderRadius: AppDimens.brMd,
          child: Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            color: isRedAlert
                ? (isDark ? Colors.red.withAlpha(38) : Colors.red.shade50)
                : theme.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: AppDimens.brMd,
              side: BorderSide(
                color: isRedAlert ? Colors.red.withAlpha(76) : theme.dividerColor,
              ),
            ),
            child: ListTile(
              leading: Icon(
                icon,
                color: isRedAlert ? Colors.red : theme.colorScheme.primary,
              ),
              title: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isRedAlert ? Colors.red : theme.textTheme.bodyLarge?.color,
                ),
              ),
              trailing: trailing ??
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: isRedAlert ? Colors.red : Colors.grey,
                  ),
              enabled: enabled,
            ),
          ),
        ),
      ),
    );
  }
}
