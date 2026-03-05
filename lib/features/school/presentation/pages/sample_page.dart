import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/custom_app_bar.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../core/services/local_storage_service.dart';
import '../../../../core/services/parent_local_storage_service.dart';
import '../../../../core/services/student_local_storage_service.dart';
import '../../../../core/services/textbooks_teaching_local_storage.dart';

class SampleDashboardPage extends StatefulWidget {
  const SampleDashboardPage({super.key});

  @override
  State<SampleDashboardPage> createState() => _SampleDashboardPageState();
}

class _SampleDashboardPageState extends State<SampleDashboardPage> {
  // Sample school data passed to every page
  static const Map<String, dynamic> sampleSchoolData = {
    'schoolName': 'St Francis High School',
    'schoolCode': 'MOE-046-005',
    'level': 'ECE',
    'firstAssessment': 'No',
  };

  // Map to store offline counts for each section
  Map<String, int> _offlineCounts = {
    'schools': 0,
    'assessments': 0,
    'documentChecks': 0,
    'leadership': 0,
    'infrastructure': 0,
    'classroom': 0,
    'parents': 0,
    'students': 0,
    'textbooks': 0,
  };

  @override
  void initState() {
    super.initState();
    _loadOfflineCounts();
  }

  Future<void> _loadOfflineCounts() async {
    final counts = {
      'schools': LocalStorageService.getPendingSchools().length,
      'assessments': LocalStorageService.getPendingAssessments().length,
      'documentChecks': LocalStorageService.getPendingDocumentChecks().length,
      'leadership': LocalStorageService.getPendingLeadership().length,
      'infrastructure': LocalStorageService.getPendingInfrastructure().length,
      'classroom': LocalStorageService.getPendingClassroomObservation().length,
      'parents': (await ParentLocalStorageService.getPending()).length,
      'students': (await StudentLocalStorageService.getPending()).length,
      'textbooks': (await TextbooksTeachingLocalStorageService.getPending()).length,
    };

    if (mounted) {
      setState(() {
        _offlineCounts = counts;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;

    return Scaffold(
      appBar: CustomAppBar(
        title: 'SQA Quick Access',
        backgroundColor: AppColors.primary,
        textColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.push('/home'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadOfflineCounts,
            tooltip: 'Refresh counts',
          ),
        ],
      ),
      body: Container(
        color: isDark ? Colors.grey[900] : Colors.grey[100],
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quick Navigation',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Access all main sections',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white70 : Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                    // Total offline count badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Total: ${_offlineCounts.values.reduce((a, b) => a + b)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 1.2,
                    children: [
                      // Core Actions - No badge for this one
                      _buildCard(
                        context: context,
                        icon: Icons.school,
                        title: 'Add New School',
                        color: Colors.blue,
                        route: '/schools',
                        badgeCount: 0,
                      ),

                      // Offline Sections with badges
                      _buildCard(
                        context: context,
                        icon: Icons.cloud_off,
                        title: 'Offline Schools',
                        color: Colors.orange,
                        route: '/offline-students',
                        badgeCount: _offlineCounts['schools']!,
                      ),
                      _buildCard(
                        context: context,
                        icon: Icons.cloud_upload,
                        title: 'Offline Assessments',
                        color: Colors.deepOrange,
                        route: '/offline-assessments',
                        badgeCount: _offlineCounts['assessments']!,
                      ),
                      _buildCard(
                        context: context,
                        icon: Icons.description_outlined,
                        title: 'Offline Doc Checks',
                        color: Colors.amber,
                        route: '/offline-document-checks',
                        badgeCount: _offlineCounts['documentChecks']!,
                      ),
                      _buildCard(
                        context: context,
                        icon: Icons.group,
                        title: 'Offline Leadership',
                        color: Colors.indigo,
                        route: '/offline-leadership',
                        badgeCount: _offlineCounts['leadership']!,
                      ),
                      // _buildCard(
                      //   context: context,
                      //   icon: Icons.group,
                      //   title: 'Leadership',
                      //   color: Colors.indigo,
                      //   route: '/leadership',
                      //   badgeCount: _offlineCounts['leadership']!,
                      // ),
                      // _buildCard(
                      //   context: context,
                      //   icon: Icons.group,
                      //   title: 'Document Checks',
                      //   color: Colors.indigo,
                      //   route: '/document-check',
                      //   badgeCount: _offlineCounts['leadership']!,
                      // ),
                      _buildCard(
                        context: context,
                        icon: Icons.domain,
                        title: 'Offline Infrastructure',
                        color: Colors.teal,
                        route: '/offline-infrastructure',
                        badgeCount: _offlineCounts['infrastructure']!,
                      ),
                      _buildCard(
                        context: context,
                        icon: Icons.school,
                        title: 'Offline Classroom',
                        color: Colors.purple,
                        route: '/offline-classroom-observation',
                        badgeCount: _offlineCounts['classroom']!,
                      ),
                      _buildCard(
                        context: context,
                        icon: Icons.family_restroom,
                        title: 'Offline Parents',
                        color: Colors.purple,
                        route: '/offline-parent-participation',
                        badgeCount: _offlineCounts['parents']!,
                      ),
                      _buildCard(
                        context: context,
                        icon: Icons.people,
                        title: 'Offline Students',
                        color: Colors.purple,
                        route: '/offline-student-participation',
                        badgeCount: _offlineCounts['students']!,
                      ),
                      _buildCard(
                        context: context,
                        icon: Icons.menu_book,
                        title: 'Offline Textbooks',
                        color: Colors.purple,
                        route: '/offline-textbooks-teaching',
                        badgeCount: _offlineCounts['textbooks']!,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Footer
                Center(
                  child: Text(
                    'Version 1.0.0 • © 2026 MOE Liberia',
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required Color color,
    required String route,
    required int badgeCount,
  }) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;

    return GestureDetector(
      onTap: () {
        context.push(
          route,
          extra: {
            'schoolName': 'St Francis High School',
            'schoolCode': 'MOE-046-005',
            'level': 'ECE',
            'firstAssessment': 'No',
          },
        ).then((_) => _loadOfflineCounts()); // Refresh counts when returning
      },
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: isDark ? Colors.grey[850] : Colors.white,
        child: Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 40,
                color: color,
              ),
              const SizedBox(height: 12),
              // Row containing text and badge
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  // Badge next to text - only show if count > 0
                  if (badgeCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 15,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Text(
                        badgeCount > 99 ? '99+' : badgeCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}