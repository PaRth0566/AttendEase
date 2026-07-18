import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../screens/auth/login_screen.dart';
import '../screens/auth/signup_screen.dart';
import '../screens/calendar/calender_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/dashboard/refresh_pdf_screen.dart';
import '../screens/profile/account_settings_screen.dart';
import '../screens/profile/bug_report_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/report/report_screen.dart';
import '../screens/root/root_screen.dart';
import '../screens/setup/add_subjects_screen.dart';
import '../screens/setup/attendance_criteria_screen.dart';
import '../screens/setup/basic_info_screen.dart';
import '../screens/setup/setup_choice_screen.dart';
import '../screens/setup/timetable_setup_screen.dart';
import '../screens/setup/upload_pdf_screen.dart';
import '../screens/web/aura_ai_dashboard.dart';
import '../screens/web/aura_landing_page.dart';
import '../screens/web/aura_upload_config.dart';
import '../screens/report/subject_detail_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../models/subject.dart';
import '../database/db_helper.dart';
import '../services/cloud_sync_service.dart';


Page<dynamic> _fadeTransition(GoRouterState state, Widget child) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurveTween(curve: Curves.easeInOut).animate(animation),
        child: child,
      );
    },
  );
}

class AppRouter {
  static final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: kIsWeb ? '/web/home' : '/',
    redirect: (context, state) async {
      final user = FirebaseAuth.instance.currentUser;
      final bool isLoggingIn = state.matchedLocation == '/login' ||
          state.matchedLocation == '/signup' ||
          state.matchedLocation == '/forgot-password';
      final bool isWebRoute = state.matchedLocation.startsWith('/web');
      final bool isAppRoute = state.matchedLocation.startsWith('/app');
      final bool isSetupRoute = state.matchedLocation.startsWith('/setup');

      // ── 1. NOT LOGGED IN ──────────────────────────────────────
      if (user == null) {
        // Auth pages are always accessible
        if (isLoggingIn) return null;

        // Web routes are public (/web/home, /web/upload, /web/dashboard).
        // /web/dashboard is guarded at the widget level — if no PDF data
        // has been parsed in the current session, AuraLandingPage shows
        // an "Upload Required" empty state instead of the dashboard.
        if (isWebRoute) {
          return null;
        }

        // /app/* and /setup/* require login
        if (isAppRoute || isSetupRoute) {
          return kIsWeb ? '/web/home' : '/login';
        }

        // Fallback: send to login or web home
        return kIsWeb ? '/web/home' : '/login';
      }

      // ── 2. LOGGED IN ──────────────────────────────────────────

      // Force logged-in users away from Login/Signup pages
      if (isLoggingIn) {
        return '/app/dashboard';
      }

      // /web/dashboard: no router redirect needed for logged-in users.
      // Widget-level guard in AuraLandingPage handles the fallback
      // (shows "Upload Required" empty state when no PDF data is parsed).

      // /app/* routes require setup completion (subjects must exist)
      if (isAppRoute) {
        bool hasData = false;
        try {
          final db = await DBHelper.instance.database;
          final subjects = await db.query('subjects', limit: 1);
          if (subjects.isNotEmpty) {
            hasData = true;
          } else {
            hasData = await CloudSyncService().restoreDataFromCloud();
          }
        } catch (_) {}

        if (!hasData) {
          return '/setup';
        }
        return null; // allow — user has auth + data
      }

      // If they hit the root domain '/', send them to the appropriate start page
      if (state.matchedLocation == '/') {
        bool hasData = false;
        try {
          final db = await DBHelper.instance.database;
          final subjects = await db.query('subjects', limit: 1);
          if (subjects.isNotEmpty) {
            hasData = true;
          } else {
            hasData = await CloudSyncService().restoreDataFromCloud();
          }
        } catch (_) {}

        return hasData ? '/app/dashboard' : '/setup';
      }

      // Allow everything else (/web/home, /web/upload, /setup/*)
      return null;
    },
    routes: [
      // Web Landing Page with Tabs
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AuraLandingPage(
            initialIndex: navigationShell.currentIndex,
            navigationShell: navigationShell,
          );
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/web/home',
                builder: (context, state) => const SizedBox.shrink(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/web/upload',
                builder: (context, state) => const AuraUploadConfig(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/web/dashboard',
                builder: (context, state) => const SizedBox.shrink(), // Rendered manually in AuraLandingPage for now
              ),
            ],
          ),
        ],
      ),

      // Main App with Tabs (Dashboard, Calendar, Profile)
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return RootScreen(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/app/dashboard',
                builder: (context, state) => const DashboardScreen(),
                routes: [
                  GoRoute(
                    path: 'subject-detail',
                    parentNavigatorKey: _rootNavigatorKey,
                    redirect: (context, state) {
                      // Guard: this route requires a Subject passed via state.extra.
                      // If force-browsed directly without data, redirect to dashboard.
                      if (state.extra == null || state.extra is! Subject) {
                        return '/app/dashboard';
                      }
                      return null;
                    },
                    pageBuilder: (context, state) {
final subject = state.extra as Subject;
                      return _fadeTransition(state, SubjectDetailScreen(subject: subject));
},
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/app/calendar',
                builder: (context, state) => const CalendarScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/app/profile',
                builder: (context, state) => const ProfileScreen(),
                routes: [
                  GoRoute(
                    path: 'basic',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => const BasicInfoScreen(isEditMode: true),
                  ),
                  GoRoute(
                    path: 'subjects',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => const AddSubjectsScreen(isEditMode: true),
                  ),
                  GoRoute(
                    path: 'timetable',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => const TimetableSetupScreen(isEditMode: true),
                  ),
                  GoRoute(
                    path: 'criteria',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => const AttendanceCriteriaScreen(isEditMode: true),
                  ),
                  GoRoute(
                    path: 'report',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => const ReportScreen(),
                  ),
                  GoRoute(
                    path: 'refresh-pdf',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => const RefreshPdfScreen(),
                  ),
                  GoRoute(
                    path: 'account',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => const AccountSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'bug-report',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => const BugReportScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      
      // Auth
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      
      // Setup Flow (Now as fully linkable routes)
      GoRoute(
        path: '/setup',
        builder: (context, state) => const SetupChoiceScreen(),
        routes: [
          GoRoute(
            path: 'upload',
            builder: (context, state) => const UploadPdfScreen(),
          ),
          GoRoute(
            path: 'basic',
            pageBuilder: (context, state) {
final extra = state.extra as Map<String, dynamic>?;
              return _fadeTransition(state, BasicInfoScreen(
                isEditMode: false,
                prefilledData: extra,
              ));
},
            routes: [
              GoRoute(
                path: 'criteria',
                builder: (context, state) => const AttendanceCriteriaScreen(isEditMode: false),
                routes: [
                  GoRoute(
                    path: 'subjects',
                    builder: (context, state) => const AddSubjectsScreen(isEditMode: false),
                    routes: [
                      GoRoute(
                        path: 'timetable',
                        builder: (context, state) => const TimetableSetupScreen(isEditMode: false),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      
      // Legacy root redirect
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
    ],
  );
}
