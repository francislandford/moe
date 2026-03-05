import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_colors.dart';

// Auth Pages
import '../features/auth/presentation/pages/login.dart';
import '../features/auth/presentation/pages/reset_password_code_page.dart';
import '../features/auth/presentation/pages/reset_password_email_page.dart';
import '../features/auth/presentation/pages/reset_password_new_page.dart';
import '../features/auth/presentation/providers/auth_provider.dart';

// Onboarding
import '../features/onboarding/presentation/pages/onboarding_page.dart';

// School Pages
import '../features/school/presentation/pages/my_schools_page.dart';
import '../features/school/presentation/pages/Profile.dart';
import '../features/school/presentation/pages/about.dart';
import '../features/school/presentation/pages/add_school_page.dart';
import '../features/school/presentation/pages/assessment_2.dart';
import '../features/school/presentation/pages/assessment_complete_page.dart';
import '../features/school/presentation/pages/classroom_1_page.dart';
import '../features/school/presentation/pages/classroom_2_page.dart';
import '../features/school/presentation/pages/classroom_3_page.dart';
import '../features/school/presentation/pages/classroom_observation_page.dart';
import '../features/school/presentation/pages/document_check_page.dart';
import '../features/school/presentation/pages/infrastructure_page.dart';
import '../features/school/presentation/pages/leadership_page.dart';
import '../features/school/presentation/pages/offline_assessment_page.dart';
import '../features/school/presentation/pages/offline_classroom_observation.dart';
import '../features/school/presentation/pages/offline_document_checks_page.dart';
import '../features/school/presentation/pages/offline_infrastructure_page.dart';
import '../features/school/presentation/pages/offline_leadership_page.dart';
import '../features/school/presentation/pages/offline_parent_participation.dart';
import '../features/school/presentation/pages/offline_student_participation.dart';
import '../features/school/presentation/pages/offline_students_page.dart';
import '../features/school/presentation/pages/offline_textbooks_teaching_page.dart';
import '../features/school/presentation/pages/parents_page.dart';
import '../features/school/presentation/pages/sample_page.dart';
import '../features/school/presentation/pages/settings.dart';
import '../features/school/presentation/pages/student_page.dart';
import '../features/school/presentation/pages/textbooks_teaching_page.dart';

// ────────────────────────────────────────────────
// Floating Bottom Navigation Layout
// ────────────────────────────────────────────────
class AuthenticatedLayout extends StatefulWidget {
  final Widget child;
  final String location;

  const AuthenticatedLayout({
    super.key,
    required this.child,
    required this.location,
  });

  @override
  State<AuthenticatedLayout> createState() => _AuthenticatedLayoutState();
}

class _AuthenticatedLayoutState extends State<AuthenticatedLayout> {
  int _selectedIndex = 0;

  // Map routes to their corresponding navigation indices (accounting for FAB placeholder)
  final Map<String, int> _routeToIndex = {
    '/home': 0,
    '/about': 1,
    '/profile': 3,  // Index 3 because index 2 is FAB placeholder
    '/settings': 4,
  };

  @override
  void initState() {
    super.initState();
    _updateSelectedIndex();
  }

  @override
  void didUpdateWidget(AuthenticatedLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.location != oldWidget.location) {
      _updateSelectedIndex();
    }
  }

  void _updateSelectedIndex() {
    final newIndex = _routeToIndex[widget.location] ?? 0;
    if (_selectedIndex != newIndex) {
      setState(() {
        _selectedIndex = newIndex;
      });
    }
  }

  void _onTap(int index) {
    if (index == 2) return; // Skip FAB placeholder

    // Map navigation indices back to routes
    switch (index) {
      case 0:
        context.go('/home');
        break;
      case 1:
        context.go('/about');
        break;
      case 3:
        context.go('/profile');
        break;
      case 4:
        context.go('/settings');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: widget.child,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          context.push('/schools');
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 8,
        shape: const CircleBorder(),
        child: const Icon(Icons.add_rounded, size: 32),
      ),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 6),
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: NavigationBar(
            height: 76,
            elevation: 0,
            backgroundColor: theme.brightness == Brightness.dark
                ? Colors.grey[900]!.withOpacity(0.95)
                : Colors.white.withOpacity(0.95),
            indicatorColor: AppColors.primary.withOpacity(0.2),
            selectedIndex: _selectedIndex,
            onDestinationSelected: _onTap,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.info_outline),
                selectedIcon: Icon(Icons.info),
                label: 'About',
              ),
              NavigationDestination(
                icon: SizedBox.shrink(),
                label: '',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profile',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────
// Router Configuration
// ────────────────────────────────────────────────
GoRouter createRouter(AuthProvider authProvider) {
  return GoRouter(
    initialLocation: authProvider.isAuthenticated ? '/home' : '/login',
    redirect: (context, state) {
      final isLoggedIn = authProvider.isAuthenticated;

      // List of public routes that don't require authentication
      final publicRoutes = [
        '/login',
        '/splash',
        '/onboarding',
        '/forgot-password',
        '/reset-password-code',
        '/reset-password-new',
      ];

      // Check if current route is a password reset route
      final isPasswordResetRoute = state.matchedLocation.startsWith('/forgot-password') ||
          state.matchedLocation.startsWith('/reset-password-code') ||
          state.matchedLocation.startsWith('/reset-password-new');

      final isGoingToPublic = publicRoutes.any(
            (route) => state.matchedLocation.startsWith(route),
      );

      // Allow authenticated users to access password reset routes
      if (isLoggedIn && isPasswordResetRoute) {
        return null; // Don't redirect, let them access the page
      }

      if (!isLoggedIn && !isGoingToPublic) {
        return '/login';
      }

      // Redirect authenticated users away from other public routes
      if (isLoggedIn && isGoingToPublic) {
        return '/home';
      }

      return null;
    },
    routes: [
      // ─── Public / Unauthenticated Routes ───
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/splash',
        name: 'splash',
        builder: (context, state) => const OnboardingPage(),
      ),

      // Password Reset Routes
      GoRoute(
        path: '/forgot-password',
        name: 'forgot-password',
        builder: (context, state) => const ForgotPasswordEmailPage(),
      ),
      GoRoute(
        path: '/reset-password-code',
        name: 'reset-password-code',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return ResetPasswordCodePage(
            email: extra?['email'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/reset-password-new',
        name: 'reset-password-new',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return ResetPasswordNewPage(
            email: extra?['email'] as String?,
            code: extra?['code'] as String?,
          );
        },
      ),

      // ─── Authenticated Routes (with bottom nav) ───
      ShellRoute(
        navigatorKey: GlobalKey<NavigatorState>(),
        builder: (context, state, child) {
          return AuthenticatedLayout(
            child: child,
            location: state.matchedLocation,
          );
        },
        routes: [
          // Main Navigation Routes
          GoRoute(
            path: '/home',
            name: 'home',
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: const MySchoolsPage(),
            ),
          ),
          GoRoute(
            path: '/about',
            name: 'about',
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: const AboutPage(),
            ),
          ),
          GoRoute(
            path: '/profile',
            name: 'profile',
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: const ProfilePage(),
            ),
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: const SettingsPage(),
            ),
          ),

          // ─── Full-screen modal routes ───
          GoRoute(
            path: '/schools',
            name: 'add-school',
            pageBuilder: (context, state) => MaterialPage(
              key: state.pageKey,
              fullscreenDialog: true,
              child: const AddSchoolPage(),
            ),
          ),
          GoRoute(
            path: '/assessment-2',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const SchoolAssessmentFormPage(),
              transitionDuration: const Duration(milliseconds: 400),
              reverseTransitionDuration: const Duration(milliseconds: 300),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),
          GoRoute(
            path: '/document-check',
            name: 'document-check',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const DocumentCheckPage(),
              transitionDuration: const Duration(milliseconds: 400),
              reverseTransitionDuration: const Duration(milliseconds: 300),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),
          GoRoute(
            path: '/infrastructure',
            name: 'infrastructure',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const InfrastructurePage(),
              transitionDuration: const Duration(milliseconds: 400),
              reverseTransitionDuration: const Duration(milliseconds: 300),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),

          // ─── Individual Classroom Routes ───
          GoRoute(
            path: '/classroom-1',
            name: 'classroom-1',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: Classroom1Page(
                schoolCode: (state.extra as Map<String, dynamic>?)?['schoolCode'] as String?,
                schoolName: (state.extra as Map<String, dynamic>?)?['schoolName'] as String?,
                schoolLevel: (state.extra as Map<String, dynamic>?)?['level'] as String?,
              ),
              transitionDuration: const Duration(milliseconds: 400),
              reverseTransitionDuration: const Duration(milliseconds: 300),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),
          GoRoute(
            path: '/classroom-2',
            name: 'classroom-2',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: Classroom2Page(
                schoolCode: (state.extra as Map<String, dynamic>?)?['schoolCode'] as String?,
                schoolName: (state.extra as Map<String, dynamic>?)?['schoolName'] as String?,
                schoolLevel: (state.extra as Map<String, dynamic>?)?['level'] as String?,
              ),
              transitionDuration: const Duration(milliseconds: 400),
              reverseTransitionDuration: const Duration(milliseconds: 300),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),
          GoRoute(
            path: '/classroom-3',
            name: 'classroom-3',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: Classroom3Page(
                schoolCode: (state.extra as Map<String, dynamic>?)?['schoolCode'] as String?,
                schoolName: (state.extra as Map<String, dynamic>?)?['schoolName'] as String?,
                schoolLevel: (state.extra as Map<String, dynamic>?)?['level'] as String?,
              ),
              transitionDuration: const Duration(milliseconds: 400),
              reverseTransitionDuration: const Duration(milliseconds: 300),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),
          GoRoute(
            path: '/classroom',
            name: 'classroom',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const ClassroomObservationPage(),
              transitionDuration: const Duration(milliseconds: 400),
              reverseTransitionDuration: const Duration(milliseconds: 300),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),

          // More Assessment Routes
          GoRoute(
            path: '/leadership',
            name: 'leadership',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const LeadershipPage(),
              transitionDuration: const Duration(milliseconds: 400),
              reverseTransitionDuration: const Duration(milliseconds: 300),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),
          GoRoute(
            path: '/parents',
            name: 'parents',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const ParentPage(),
              transitionDuration: const Duration(milliseconds: 400),
              reverseTransitionDuration: const Duration(milliseconds: 300),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),
          GoRoute(
            path: '/students',
            name: 'students',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const StudentParticipationPage(),
              transitionDuration: const Duration(milliseconds: 400),
              reverseTransitionDuration: const Duration(milliseconds: 300),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),
          GoRoute(
            path: '/textbooks-teaching',
            name: 'textbooks-teaching',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const TextbooksTeachingPage(),
              transitionDuration: const Duration(milliseconds: 400),
              reverseTransitionDuration: const Duration(milliseconds: 300),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),

          // Offline pages
          GoRoute(
            path: '/offline-assessments',
            name: 'offline-assessments',
            builder: (context, state) => const OfflineAssessmentsPage(),
          ),
          GoRoute(
            path: '/offline-students',
            name: 'offline-students',
            builder: (context, state) => const OfflineStudentsPage(),
          ),
          GoRoute(
            path: '/offline-document-checks',
            name: 'offline-document-checks',
            builder: (context, state) => const OfflineDocumentChecksPage(),
          ),
          GoRoute(
            path: '/offline-infrastructure',
            name: 'offline-infrastructure',
            builder: (context, state) => const OfflineInfrastructurePage(),
          ),
          GoRoute(
            path: '/offline-classroom-observation',
            name: 'offline-classroom-observation',
            builder: (context, state) => const OfflineClassroomObservationPage(),
          ),
          GoRoute(
            path: '/offline-leadership',
            name: 'offline-leadership',
            builder: (context, state) => const OfflineLeadershipPage(),
          ),
          GoRoute(
            path: '/offline-parent-participation',
            name: 'offline-parent-participation',
            builder: (context, state) => const OfflineParentParticipationPage(),
          ),
          GoRoute(
            path: '/offline-student-participation',
            name: 'offline-student-participation',
            builder: (context, state) => const OfflineStudentParticipationPage(),
          ),
          GoRoute(
            path: '/offline-textbooks-teaching',
            name: 'offline-textbooks-teaching',
            builder: (context, state) => const OfflineTextbooksTeachingPage(),
          ),

          // Completion page
          GoRoute(
            path: '/assessment-complete',
            name: 'assessment-complete',
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>? ?? {};
              final bool isOffline = extra['isOffline'] as bool? ?? false;
              final String? schoolName = extra['schoolName'] as String?;
              return AssessmentCompletePage(
                isOffline: isOffline,
                schoolName: schoolName,
              );
            },
          ),

          // Sample page
          GoRoute(
            path: '/sample-dashboard',
            name: 'sample-dashboard',
            builder: (context, state) => const SampleDashboardPage(),
          ),
        ],
      ),
    ],
  );
}