import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../screens/auth/login_screen.dart';
import '../screens/auth/signup_screen.dart';
import '../screens/root/root_screen.dart';
import '../screens/setup/setup_choice_screen.dart';
import '../screens/setup/upload_pdf_screen.dart';
import '../screens/setup/basic_info_screen.dart';
import '../screens/setup/attendance_criteria_screen.dart';
import '../screens/setup/add_subjects_screen.dart';
import '../screens/setup/timetable_setup_screen.dart';
import '../screens/web/aura_landing_page.dart';
import '../database/db_helper.dart';
import '../services/cloud_sync_service.dart';

class AppRouter {
  static final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: kIsWeb ? '/web/home' : '/',
    redirect: (context, state) async {
      final user = FirebaseAuth.instance.currentUser;
      final bool isLoggingIn = state.matchedLocation == '/login' || state.matchedLocation == '/signup';
      final bool isWebRoute = state.matchedLocation.startsWith('/web');

      // 1. If not logged in...
      if (user == null) {
        if (isLoggingIn || isWebRoute) return null;
        return kIsWeb ? '/web/home' : '/login';
      }

      // 2. If logged in...
      
      // Force logged-in users away from Login/Signup pages
      if (isLoggingIn) {
        return '/app/dashboard';
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

      // Allow everything else (including /web and setup steps)
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
                builder: (context, state) => const SizedBox.shrink(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/web/dashboard',
                builder: (context, state) => const SizedBox.shrink(),
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
                builder: (context, state) => const SizedBox.shrink(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/app/calendar',
                builder: (context, state) => const SizedBox.shrink(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/app/profile',
                builder: (context, state) => const SizedBox.shrink(),
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
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>?;
              return BasicInfoScreen(
                isEditMode: false,
                prefilledData: extra,
              );
            },
          ),
          GoRoute(
            path: 'criteria',
            builder: (context, state) => const AttendanceCriteriaScreen(isEditMode: false),
          ),
          GoRoute(
            path: 'subjects',
            builder: (context, state) => const AddSubjectsScreen(isEditMode: false),
          ),
          GoRoute(
            path: 'timetable',
            builder: (context, state) => const TimetableSetupScreen(isEditMode: false),
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
