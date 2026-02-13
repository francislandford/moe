import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/custom_app_bar.dart';
import '../../../../core/theme/theme_provider.dart';

class SampleDashboardPage extends StatelessWidget {
  const SampleDashboardPage({super.key});

  // Sample school data passed to every page
  static const Map<String, dynamic> sampleSchoolData = {
    'schoolName': 'St Francis High School',
    'schoolCode': '12345098',
    'level': 'ECE',
  };

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
      ),
      body: Container(
        color: isDark ? Colors.grey[900] : Colors.grey[100],
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quick Navigation',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Access all main sections of the application',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white70 : Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 32),

                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 20,
                    crossAxisSpacing: 20,
                    childAspectRatio: 1.35,
                    children: [
                      // Core Actions
                      _buildCard(
                        context: context,
                        icon: Icons.school,
                        title: 'Add New School',
                        color: Colors.blue,
                        route: '/schools',
                      ),
                      // _buildCard(
                      //   context: context,
                      //   icon: Icons.assessment,
                      //   title: 'Start Assessment',
                      //   color: Colors.green,
                      //   route: '/assessment-2',
                      // ),

                      // Assessment Modules
                      // _buildCard(
                      //   context: context,
                      //   icon: Icons.description,
                      //   title: 'Document Check',
                      //   color: Colors.deepPurple,
                      //   route: '/document-check',
                      // ),
                      // _buildCard(
                      //   context: context,
                      //   icon: Icons.group,
                      //   title: 'Leadership Assessment',
                      //   color: Colors.indigo,
                      //   route: '/leadership',
                      // ),
                      // _buildCard(
                      //   context: context,
                      //   icon: Icons.domain,
                      //   title: 'Infrastructure Assessment',
                      //   color: Colors.teal,
                      //   route: '/infrastructure',
                      // ),
                      // _buildCard(
                      //   context: context,
                      //   icon: Icons.ac_unit_rounded,
                      //   title: 'Classroom Observation',
                      //   color: Colors.purple,
                      //   route: '/classroom',
                      // ),

                      // Offline Sections
                      _buildCard(
                        context: context,
                        icon: Icons.cloud_off,
                        title: 'Offline Students',
                        color: Colors.orange,
                        route: '/offline-students',
                      ),
                      _buildCard(
                        context: context,
                        icon: Icons.cloud_upload,
                        title: 'Offline Assessments',
                        color: Colors.deepOrange,
                        route: '/offline-assessments',
                      ),
                      _buildCard(
                        context: context,
                        icon: Icons.description_outlined,
                        title: 'Offline Doc Checks',
                        color: Colors.amber,
                        route: '/offline-document-checks',
                      ),
                      _buildCard(
                        context: context,
                        icon: Icons.group,
                        title: 'Offline Leadership',
                        color: Colors.indigo,
                        route: '/offline-leadership',
                      ),
                      _buildCard(
                        context: context,
                        icon: Icons.domain,
                        title: 'Offline Infrastructure',
                        color: Colors.teal,
                        route: '/offline-infrastructure',
                      ),
                      _buildCard(
                        context: context,
                        icon: Icons.abc_outlined,
                        title: 'Offline Classroom Obs.',
                        color: Colors.purple,
                        route: '/offline-classroom-observation',
                      ),
                      // _buildCard(
                      //   context: context,
                      //   icon: Icons.verified_user_sharp,
                      //   title: 'Parents Participation',
                      //   color: Colors.purple,
                      //   route: '/parents',
                      // ),
                      // _buildCard(
                      //   context: context,
                      //   icon: Icons.verified_user_sharp,
                      //   title: 'Students Participation',
                      //   color: Colors.purple,
                      //   route: '/students',
                      // ),
                      // _buildCard(
                      //   context: context,
                      //   icon: Icons.verified_user_sharp,
                      //   title: 'Textbooks & Teaching Materials',
                      //   color: Colors.purple,
                      //   route: '/textbooks-teaching',
                      // ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Footer
                Center(
                  child: Text(
                    'Version 1.0.0 • © 2026 MOE Liberia',
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.grey[600],
                      fontSize: 13,
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
  }) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;

    return GestureDetector(
      onTap: () {
        context.push(
          route,
          extra: {
            'schoolName': 'St Francis High School',
            'schoolCode': '20202020',
            'level': 'ECE',
          },
        );
      },
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: isDark ? Colors.grey[850] : Colors.white,
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 48,
                color: color,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}