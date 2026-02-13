import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/custom_app_bar.dart';
import '../../../../core/services/local_storage_service.dart';
import '../../../../core/theme/theme_provider.dart';
import 'auth/presentation/providers/auth_provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isRefreshing = false;

  // Real counts loaded from Hive
  int _totalSchools = 84; // placeholder — replace with real API/backend count
  int _unsyncedSchools = 0;
  int _unsyncedAssessments = 0;
  int _unsyncedDocumentChecks = 0;
  int _unsyncedLeadership = 0;
  int _unsyncedInfrastructure = 0;
  int _unsyncedClassroom = 0;

  @override
  void initState() {
    super.initState();
    _loadOfflineCounts();
  }

  Future<void> _loadOfflineCounts() async {
    setState(() => _isRefreshing = true);

    try {
      _unsyncedSchools = LocalStorageService.getPendingSchools().length;
      _unsyncedAssessments = LocalStorageService.getPendingAssessments().length;
      _unsyncedDocumentChecks = LocalStorageService.getPendingDocumentChecks().length;
      _unsyncedLeadership = LocalStorageService.getPendingLeadership().length;
      _unsyncedInfrastructure = LocalStorageService.getPendingInfrastructure().length;
      _unsyncedClassroom = LocalStorageService.getPendingClassroomObservation().length;

      // TODO: Fetch real total schools from backend or cached data
      // For now keeping placeholder

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loading offline counts: $e');
    }

    setState(() => _isRefreshing = false);
  }

  Future<void> _refresh() async {
    await _loadOfflineCounts();
  }

  int get _totalUnsynced =>
      _unsyncedSchools +
          _unsyncedAssessments +
          _unsyncedDocumentChecks +
          _unsyncedLeadership +
          _unsyncedInfrastructure +
          _unsyncedClassroom;

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);

    final userName = authProvider.user?['name']?.toString() ?? 'Officer';
    final userRole = authProvider.user?['usertype']?.toString() ?? 'Supervisor';

    // Adaptive colors based on current theme
    final isDark = themeProvider.isDarkMode;
    final backgroundColor = isDark ? Colors.grey[900] : Colors.grey[50];
    final cardColor = isDark ? Colors.grey[850] : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.white70 : Colors.grey[700];

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: CustomAppBar(
        title: 'SQA Dashboard',
        backgroundColor: AppColors.primary,
        textColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white),
            tooltip: 'Sign Out',
            onPressed: () async {
              await authProvider.logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.primary,
        backgroundColor: isDark ? Colors.grey[850] : Colors.white,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Greeting Card
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                color: cardColor,
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: AppColors.primary.withOpacity(0.15),
                        child: Icon(
                          Icons.person_rounded,
                          size: 40,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Welcome back, $userName',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              userRole,
                              style: TextStyle(fontSize: 16, color: secondaryTextColor),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Offline sync banner
              if (_totalUnsynced > 0)
                Card(
                  color: isDark ? Colors.orange[900] : Colors.orange[50],
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    leading: Icon(
                      Icons.cloud_off_rounded,
                      color: isDark ? Colors.orange[300] : Colors.deepOrange,
                      size: 36,
                    ),
                    title: Text(
                      '$_totalUnsynced records pending sync',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.orange[300] : Colors.deepOrange,
                      ),
                    ),
                    subtitle: Text(
                      'Connect to internet to upload all data',
                      style: TextStyle(color: secondaryTextColor),
                    ),
                    trailing: TextButton.icon(
                      icon: Icon(Icons.sync, color: isDark ? Colors.orange[300] : Colors.deepOrange),
                      label: Text(
                        'Sync Now',
                        style: TextStyle(color: isDark ? Colors.orange[300] : Colors.deepOrange),
                      ),
                      onPressed: () {
                        context.push('/offline-overview');
                      },
                    ),
                  ),
                ),
              if (_totalUnsynced > 0) const SizedBox(height: 16),

              // Stats Grid
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.35,
                children: [
                  _buildStatCard(
                    icon: Icons.school_rounded,
                    title: 'Total Schools',
                    value: '$_totalSchools',
                    color: Colors.blue,
                    onTap: () => context.push('/schools'),
                  ),
                  _buildStatCard(
                    icon: Icons.cloud_upload_rounded,
                    title: 'Unsynced Schools',
                    value: '$_unsyncedSchools',
                    color: Colors.orange,
                    onTap: () => context.push('/offline-students'),
                  ),
                  _buildStatCard(
                    icon: Icons.assessment_rounded,
                    title: 'Assessments',
                    value: '$_unsyncedAssessments',
                    color: Colors.green,
                    onTap: () => context.push('/offline-assessments'),
                  ),
                  _buildStatCard(
                    icon: Icons.class_rounded,
                    title: 'Classroom Obs.',
                    value: '$_unsyncedClassroom',
                    color: Colors.purple,
                    onTap: () => context.push('/offline-classroom-observation'),
                  ),
                  _buildStatCard(
                    icon: Icons.domain_rounded,
                    title: 'Infrastructure',
                    value: '$_unsyncedInfrastructure',
                    color: Colors.teal,
                    onTap: () => context.push('/offline-infrastructure'),
                  ),
                  _buildStatCard(
                    icon: Icons.group_rounded,
                    title: 'Leadership',
                    value: '$_unsyncedLeadership',
                    color: Colors.indigo,
                    onTap: () => context.push('/offline-leadership'),
                  ),
                ],
              ),
              const SizedBox(height: 40),

              // Footer
              Center(
                child: Column(
                  children: [
                    Text(
                      'Ministry of Education, Republic of Liberia',
                      style: TextStyle(color: secondaryTextColor, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Version 1.0.0 • © 2026',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // NEW: Button to Sample Dashboard Page
              Center(
                child: ElevatedButton.icon(
                  onPressed: () => context.push('/sample-dashboard'),
                  icon: const Icon(Icons.dashboard),
                  label: const Text('Go to Sample Dashboard'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 4,
                    minimumSize: const Size(280, 56),
                  ),
                ),
              ),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),

      // Floating Action Button – Add School
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/schools'),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Add School',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        elevation: 6,
        heroTag: 'add_school_fab',
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    final cardColor = isDark ? Colors.grey[850] : Colors.white;

    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 4,
        color: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withOpacity(0.15), color.withOpacity(0.05)],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(height: 12),
              Text(
                value,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}