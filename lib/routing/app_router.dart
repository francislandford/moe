import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:moe/features/school/presentation/pages/my_schools_page.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_colors.dart';
import '../features/auth/presentation/pages/login.dart';
import '../features/auth/presentation/providers/auth_provider.dart';
import '../features/home.dart';
import '../features/onboarding/presentation/pages/onboarding_page.dart';
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

  const AuthenticatedLayout({super.key, required this.child});

  @override
  State<AuthenticatedLayout> createState() => _AuthenticatedLayoutState();
}

class _AuthenticatedLayoutState extends State<AuthenticatedLayout> {
  int _selectedIndex = 0;

  static const List<String> _navRoutes = [
    '/home',
    '/about',
    '/profile',
    '/settings',
  ];

  void _onTap(int index) {
    if (index == 2) return; // Skip FAB placeholder

    final routeIndex = index < 2 ? index : index - 1;

    if (routeIndex != _selectedIndex) {
      setState(() => _selectedIndex = routeIndex);
      context.go(_navRoutes[routeIndex]);
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
      final isGoingToPublic = state.matchedLocation.startsWith('/login') ||
          state.matchedLocation == '/splash' ||
          state.matchedLocation == '/onboarding';

      if (!isLoggedIn && !isGoingToPublic) {
        return '/login';
      }
      if (isLoggedIn && isGoingToPublic) {
        return '/home';
      }
      return null;
    },
    routes: [
      // ─── Public / Unauthenticated Routes ───
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/splash',
        builder: (context, state) => const OnboardingPage(),
      ),

      // ─── Authenticated Routes (with bottom nav) ───
      ShellRoute(
        builder: (context, state, child) => AuthenticatedLayout(child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const MySchoolsPage(),
          ),
          GoRoute(
            path: '/about',
            builder: (context, state) => const AboutPage(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfilePage(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsPage(),
          ),

          // ─── Full-screen modal routes (using pageBuilder + CustomTransitionPage) ───
          GoRoute(
            path: '/schools',
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

          // Keep the original classroom page for backward compatibility if needed
          GoRoute(
            path: '/classroom',
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

          GoRoute(
            path: '/leadership',
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

          // Offline pages (remain regular pages)
          GoRoute(
            path: '/offline-assessments',
            builder: (context, state) => const OfflineAssessmentsPage(),
          ),
          GoRoute(
            path: '/offline-students',
            builder: (context, state) => const OfflineStudentsPage(),
          ),
          GoRoute(
            path: '/offline-document-checks',
            builder: (context, state) => const OfflineDocumentChecksPage(),
          ),
          GoRoute(
            path: '/offline-infrastructure',
            builder: (context, state) => const OfflineInfrastructurePage(),
          ),
          GoRoute(
            path: '/offline-classroom-observation',
            builder: (context, state) => const OfflineClassroomObservationPage(),
          ),
          GoRoute(
            path: '/offline-leadership',
            builder: (context, state) => const OfflineLeadershipPage(),
          ),
          GoRoute(
            path: '/offline-parent-participation',
            builder: (context, state) => const OfflineParentParticipationPage(),
          ),
          GoRoute(
            path: '/offline-student-participation',
            builder: (context, state) => const OfflineStudentParticipationPage(),
          ),
          GoRoute(
            path: '/offline-textbooks-teaching',
            builder: (context, state) => const OfflineTextbooksTeachingPage(),
          ),

          // Completion page
          GoRoute(
            path: '/assessment-complete',
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

          // Sample / misc pages
          GoRoute(
            path: '/sample-dashboard',
            builder: (context, state) => const SampleDashboardPage(),
          ),
        ],
      ),
    ],
  );
}