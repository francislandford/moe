import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_url.dart';
import '../../../../core/widgets/custom_app_bar.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../core/services/data_preloader_service.dart';
import '../../../../core/services/local_storage_service.dart';
import '../../../../core/services/parent_local_storage_service.dart';
import '../../../../core/services/student_local_storage_service.dart';
import '../../../../core/services/textbooks_teaching_local_storage.dart';
import '../../../school/presentation/providers/school_provider.dart';
import '../../../school/presentation/providers/assessment_provider.dart';

// Progress model for sync operations (separate from preload progress)
class SyncProgress {
  final String currentTask;
  final double progress;
  final List<String> completedTasks;
  final Map<String, int> moduleCounts;
  final int totalItems;
  final int syncedItems;

  SyncProgress({
    required this.currentTask,
    required this.progress,
    required this.completedTasks,
    required this.moduleCounts,
    required this.totalItems,
    required this.syncedItems,
  });

  SyncProgress copyWith({
    String? currentTask,
    double? progress,
    List<String>? completedTasks,
    Map<String, int>? moduleCounts,
    int? totalItems,
    int? syncedItems,
  }) {
    return SyncProgress(
      currentTask: currentTask ?? this.currentTask,
      progress: progress ?? this.progress,
      completedTasks: completedTasks ?? this.completedTasks,
      moduleCounts: moduleCounts ?? this.moduleCounts,
      totalItems: totalItems ?? this.totalItems,
      syncedItems: syncedItems ?? this.syncedItems,
    );
  }
}

// Global notifier for sync progress
final ValueNotifier<SyncProgress> syncProgressNotifier = ValueNotifier<SyncProgress>(
  SyncProgress(
    currentTask: 'Initializing...',
    progress: 0.0,
    completedTasks: [],
    moduleCounts: {},
    totalItems: 0,
    syncedItems: 0,
  ),
);

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);

    final user = authProvider.user;
    final name = user?['name']?.toString() ?? 'User';
    final username = user?['username']?.toString() ?? 'No username';
    final usertype = user?['usertype']?.toString() ?? 'User';
    final phone = user?['phone']?.toString() ?? 'Not provided';

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Settings',
        backgroundColor: AppColors.primary,
        textColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ─── Account Section ───────────────────────────────────────────────
          _buildSectionHeader(context, 'Account'),
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: AppColors.primary,
              child: Icon(Icons.person, color: Colors.white),
            ),
            title: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(username),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('View full profile coming soon')),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Role / Position'),
            subtitle: Text(usertype),
          ),
          ListTile(
            leading: const Icon(Icons.phone_outlined),
            title: const Text('Phone Number'),
            subtitle: Text(phone),
          ),
          const Divider(height: 32),

          // ─── Data Management Section ───────────────────────────────────
          _buildSectionHeader(context, 'Data Management'),

          // Preload Offline Data
          ListTile(
            leading: const Icon(Icons.cloud_download_outlined, color: AppColors.primary),
            title: const Text('Preload Offline Data'),
            subtitle: const Text('Download all reference data for offline use'),
            trailing: ValueListenableBuilder<bool>(
              valueListenable: ValueNotifier<bool>(DataPreloaderService.isPreloading),
              builder: (context, isPreloading, child) {
                if (isPreloading) {
                  return const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  );
                }
                return const Icon(Icons.download_rounded);
              },
            ),
            onTap: () async {
              if (DataPreloaderService.isPreloading) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Preloading already in progress...'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }

              // Show confirmation dialog
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Preload Offline Data'),
                  content: const Text(
                      'This will download all reference data (schools, grades, subjects, questions) for offline use. '
                          'This may take a few moments and requires an internet connection.'
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Start Download'),
                    ),
                  ],
                ),
              );

              if (confirm == true && context.mounted) {
                // Show preload dialog with progress
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (BuildContext context) {
                    return const PreloadDataDialog();
                  },
                );

                // Start preloading
                await DataPreloaderService.preloadAllData(context);
              }
            },
          ),

          // Sync All Offline Data
          ListTile(
            leading: const Icon(Icons.sync_rounded, color: AppColors.primary),
            title: const Text('Sync All Offline Data'),
            subtitle: const Text('Upload all pending submissions to server'),
            trailing: FutureBuilder<int>(
              future: _getTotalPendingCount(),
              builder: (context, snapshot) {
                if (syncProgressNotifier.value.progress > 0 && syncProgressNotifier.value.progress < 1.0) {
                  return const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  );
                }
                final count = snapshot.data ?? 0;
                if (count > 0) {
                  return Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                }
                return const Icon(Icons.sync_rounded);
              },
            ),
            onTap: () async {
              if (!await LocalStorageService.isOnline()) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No internet connection. Connect and try again.'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }

              final totalCount = await _getTotalPendingCount();
              if (totalCount == 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No pending data to sync.'),
                    backgroundColor: Colors.green,
                  ),
                );
                return;
              }

              // Show confirmation dialog
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Sync All Offline Data'),
                  content: Text(
                      'This will upload $totalCount pending item(s) to the server. '
                          'This may take a few moments and requires an internet connection.'
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Start Sync'),
                    ),
                  ],
                ),
              );

              if (confirm == true && context.mounted) {
                // Show sync dialog with progress
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (BuildContext context) {
                    return const SyncDataDialog();
                  },
                );

                // Start syncing
                await _syncAllOfflineData(context);
              }
            },
          ),

          ListTile(
            leading: const Icon(Icons.info_outline, color: Colors.grey),
            title: const Text('Storage Info'),
            subtitle: FutureBuilder<int>(
              future: _getTotalPendingCount(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Text('Loading...');
                }
                return Text('Pending items: ${snapshot.data}');
              },
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              _showStorageInfo(context);
            },
          ),
          const Divider(height: 32),

          // ─── App Preferences ───────────────────────────────────────────────
          _buildSectionHeader(context, 'App Preferences'),
          SwitchListTile(
            secondary: Icon(
              themeProvider.isDarkMode ? Icons.dark_mode : Icons.light_mode,
              color: themeProvider.isDarkMode ? Colors.yellow[700] : AppColors.primary,
            ),
            title: const Text('Dark Mode'),
            subtitle: const Text('Switch between light and dark theme'),
            value: themeProvider.isDarkMode,
            onChanged: (value) {
              themeProvider.toggleTheme();
            },
          ),
          const Divider(height: 32),

          // ─── About & Support ──────────────────────────────────────────────
          _buildSectionHeader(context, 'About & Support'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About the App'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/about'),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Help & Manual'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('User manual coming soon')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.contact_support_outlined),
            title: const Text('Contact Support'),
            subtitle: const Text('Email or call MOE support team'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('support@moe.gov.lr')),
              );
            },
          ),
          const Divider(height: 32),

          // ─── Logout Section ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.logout, color: Colors.redAccent),
              label: const Text(
                'Log Out',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Colors.redAccent,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent, width: 2),
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Log Out'),
                    content: const Text('Are you sure you want to log out?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Log Out', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );

                if (confirm == true && context.mounted) {
                  await Provider.of<AuthProvider>(context, listen: false).logout();
                  // Router will redirect to login automatically
                }
              },
            ),
          ),

          const SizedBox(height: 60),

          // Footer version & credits
          Center(
            child: Column(
              children: [
                Text(
                  'School Quality Assessment • v1.0.0',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  '© 2026 Ministry of Education, Liberia',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
          letterSpacing: 1.1,
          fontFamily: 'RobotoSlabRegular',
        ),
      ),
    );
  }

  Future<int> _getTotalPendingCount() async {
    int count = 0;
    count += LocalStorageService.getPendingSchools().length;
    count += LocalStorageService.getPendingAssessments().length;
    count += LocalStorageService.getPendingDocumentChecks().length;
    count += LocalStorageService.getPendingInfrastructure().length;
    count += LocalStorageService.getPendingLeadership().length;
    count += LocalStorageService.getPendingClassroomObservation().length;
    count += (await ParentLocalStorageService.getPending()).length;
    count += (await StudentLocalStorageService.getPending()).length;
    count += (await TextbooksTeachingLocalStorageService.getPending()).length;
    return count;
  }

  // Helper method to sync a single assessment
  Future<bool> _syncSingleAssessment(Map<String, dynamic> assessment, BuildContext context, Map<String, String> headers) async {
    final school = assessment['schoolCode'] ?? assessment['schoolName'] ?? 'unknown';

    try {
      // 1. Absent records
      for (var r in assessment['absentRecords'] ?? []) {
        final res = await http.post(
          Uri.parse('${AppUrl.url}/schools/absents'),
          headers: headers,
          body: jsonEncode({
            ...r,
            'school': school,
          }),
        );
        if (res.statusCode != 201) return false;
      }

      // 2. Staff records
      for (var r in assessment['staffRecords'] ?? []) {
        final res = await http.post(
          Uri.parse('${AppUrl.url}/schools/staff'),
          headers: headers,
          body: jsonEncode({
            ...r,
            'school': school,
          }),
        );
        if (res.statusCode != 201) return false;
      }

      // 3. Required Teachers
      final req = assessment['reqTeachers'] ?? {};
      if ((req['level'] ?? '').toString().trim().isNotEmpty) {
        final res = await http.post(
          Uri.parse('${AppUrl.url}/schools/req-teachers'),
          headers: headers,
          body: jsonEncode({
            ...req,
            'school': school,
          }),
        );
        if (res.statusCode != 201) return false;
      }

      // 4. Verify Student Records (tabular format)
      for (var record in assessment['verifyStudentRecords'] ?? []) {
        final gradeName = record['classGrade']?.toString() ?? '';
        if (gradeName.isEmpty) continue;

        final payload = {
          'school': school,
          'classes': gradeName,
          'emis_male': int.tryParse(record['emisMale']?.toString() ?? '0') ?? 0,
          'count_male': int.tryParse(record['countMale']?.toString() ?? '0') ?? 0,
          'emis_female': int.tryParse(record['emisFemale']?.toString() ?? '0') ?? 0,
          'count_female': int.tryParse(record['countFemale']?.toString() ?? '0') ?? 0,
        };

        final res = await http.post(
          Uri.parse('${AppUrl.url}/schools/verify-students'),
          headers: headers,
          body: jsonEncode(payload),
        );
        if (res.statusCode != 201) return false;
      }

      // 5. Fee records
      for (var r in assessment['feeRecords'] ?? []) {
        final res = await http.post(
          Uri.parse('${AppUrl.url}/schools/fees-paid'),
          headers: headers,
          body: jsonEncode({
            ...r,
            'school': school,
          }),
        );
        if (res.statusCode != 201) return false;
      }

      return true;
    } catch (e) {
      debugPrint('Assessment sync error: $e');
      return false;
    }
  }

  // Helper method to sync a single classroom observation
  Future<bool> _syncSingleClassroom(Map<String, dynamic> payload, Map<String, String> headers) async {
    try {
      final res = await http.post(
        Uri.parse('${AppUrl.url}/classroom-observation'),
        headers: headers,
        body: jsonEncode(payload),
      );
      return (res.statusCode == 200 || res.statusCode == 201);
    } catch (e) {
      debugPrint('Classroom sync error: $e');
      return false;
    }
  }

  // Helper method to sync a single document check
  Future<bool> _syncSingleDocumentCheck(Map<String, dynamic> payload, Map<String, String> headers) async {
    try {
      final res = await http.post(
        Uri.parse('${AppUrl.url}/document-check'),
        headers: headers,
        body: jsonEncode(payload),
      );
      return (res.statusCode == 200 || res.statusCode == 201);
    } catch (e) {
      debugPrint('Document check sync error: $e');
      return false;
    }
  }

  // Helper method to sync a single infrastructure assessment
  Future<bool> _syncSingleInfrastructure(Map<String, dynamic> payload, Map<String, String> headers) async {
    try {
      final res = await http.post(
        Uri.parse('${AppUrl.url}/infrastructure'),
        headers: headers,
        body: jsonEncode(payload),
      );
      return (res.statusCode == 200 || res.statusCode == 201);
    } catch (e) {
      debugPrint('Infrastructure sync error: $e');
      return false;
    }
  }

  // Helper method to sync a single leadership assessment
  Future<bool> _syncSingleLeadership(Map<String, dynamic> payload, Map<String, String> headers) async {
    try {
      final res = await http.post(
        Uri.parse('${AppUrl.url}/leadership'),
        headers: headers,
        body: jsonEncode(payload),
      );
      return (res.statusCode == 200 || res.statusCode == 201);
    } catch (e) {
      debugPrint('Leadership sync error: $e');
      return false;
    }
  }

  Future<void> _syncAllOfflineData(BuildContext context) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isAuthenticated || authProvider.token == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Not authenticated. Please log in again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final headers = authProvider.getAuthHeaders();
    final schoolProvider = Provider.of<SchoolProvider>(context, listen: false);

    // Get all pending items
    final pendingSchools = LocalStorageService.getPendingSchools();
    final pendingAssessments = LocalStorageService.getPendingAssessments();
    final pendingDocumentChecks = LocalStorageService.getPendingDocumentChecks();
    final pendingInfrastructure = LocalStorageService.getPendingInfrastructure();
    final pendingLeadership = LocalStorageService.getPendingLeadership();
    final pendingClassroom = LocalStorageService.getPendingClassroomObservation();
    final pendingParent = await ParentLocalStorageService.getPending();
    final pendingStudent = await StudentLocalStorageService.getPending();
    final pendingTextbooks = await TextbooksTeachingLocalStorageService.getPending();

    final moduleCounts = {
      'Schools': pendingSchools.length,
      'Assessments': pendingAssessments.length,
      'Document Checks': pendingDocumentChecks.length,
      'Infrastructure': pendingInfrastructure.length,
      'Leadership': pendingLeadership.length,
      'Classroom': pendingClassroom.length,
      'Parent': pendingParent.length,
      'Student': pendingStudent.length,
      'Textbooks': pendingTextbooks.length,
    };

    final totalItems = pendingSchools.length +
        pendingAssessments.length +
        pendingDocumentChecks.length +
        pendingInfrastructure.length +
        pendingLeadership.length +
        pendingClassroom.length +
        pendingParent.length +
        pendingStudent.length +
        pendingTextbooks.length;

    int syncedItems = 0;
    final completedModules = <String>[];

    // Update initial progress
    syncProgressNotifier.value = SyncProgress(
      currentTask: 'Starting sync...',
      progress: 0.0,
      completedTasks: [],
      moduleCounts: moduleCounts,
      totalItems: totalItems,
      syncedItems: 0,
    );

    // Sync Schools
    if (pendingSchools.isNotEmpty) {
      syncProgressNotifier.value = syncProgressNotifier.value.copyWith(
        currentTask: 'Syncing schools...',
      );
      for (var school in pendingSchools) {
        try {
          final result = await schoolProvider.createSchool(school, context);
          if (result['success'] == true && result['offline'] != true) {
            await LocalStorageService.removePendingSchool(school);
            syncedItems++;
            syncProgressNotifier.value = syncProgressNotifier.value.copyWith(
              syncedItems: syncedItems,
              progress: syncedItems / totalItems,
            );
          }
        } catch (e) {
          debugPrint('School sync error: $e');
        }
      }
      completedModules.add('Schools');
      syncProgressNotifier.value = syncProgressNotifier.value.copyWith(
        completedTasks: completedModules,
      );
    }

    // Sync Assessments
    if (pendingAssessments.isNotEmpty) {
      syncProgressNotifier.value = syncProgressNotifier.value.copyWith(
        currentTask: 'Syncing assessments...',
      );
      for (var assessment in pendingAssessments) {
        final success = await _syncSingleAssessment(assessment, context, headers);
        if (success) {
          await LocalStorageService.removePendingAssessment(assessment);
          syncedItems++;
          syncProgressNotifier.value = syncProgressNotifier.value.copyWith(
            syncedItems: syncedItems,
            progress: syncedItems / totalItems,
          );
        }
      }
      completedModules.add('Assessments');
      syncProgressNotifier.value = syncProgressNotifier.value.copyWith(
        completedTasks: completedModules,
      );
    }

    // Sync Document Checks
    if (pendingDocumentChecks.isNotEmpty) {
      syncProgressNotifier.value = syncProgressNotifier.value.copyWith(
        currentTask: 'Syncing document checks...',
      );
      for (var check in pendingDocumentChecks) {
        final success = await _syncSingleDocumentCheck(check, headers);
        if (success) {
          await LocalStorageService.removePendingDocumentCheck(check);
          syncedItems++;
          syncProgressNotifier.value = syncProgressNotifier.value.copyWith(
            syncedItems: syncedItems,
            progress: syncedItems / totalItems,
          );
        }
      }
      completedModules.add('Document Checks');
      syncProgressNotifier.value = syncProgressNotifier.value.copyWith(
        completedTasks: completedModules,
      );
    }

    // Sync Infrastructure
    if (pendingInfrastructure.isNotEmpty) {
      syncProgressNotifier.value = syncProgressNotifier.value.copyWith(
        currentTask: 'Syncing infrastructure...',
      );
      for (var item in pendingInfrastructure) {
        final success = await _syncSingleInfrastructure(item, headers);
        if (success) {
          await LocalStorageService.removePendingInfrastructure(item);
          syncedItems++;
          syncProgressNotifier.value = syncProgressNotifier.value.copyWith(
            syncedItems: syncedItems,
            progress: syncedItems / totalItems,
          );
        }
      }
      completedModules.add('Infrastructure');
      syncProgressNotifier.value = syncProgressNotifier.value.copyWith(
        completedTasks: completedModules,
      );
    }

    // Sync Leadership
    if (pendingLeadership.isNotEmpty) {
      syncProgressNotifier.value = syncProgressNotifier.value.copyWith(
        currentTask: 'Syncing leadership...',
      );
      for (var item in pendingLeadership) {
        final success = await _syncSingleLeadership(item, headers);
        if (success) {
          await LocalStorageService.removePendingLeadership(item);
          syncedItems++;
          syncProgressNotifier.value = syncProgressNotifier.value.copyWith(
            syncedItems: syncedItems,
            progress: syncedItems / totalItems,
          );
        }
      }
      completedModules.add('Leadership');
      syncProgressNotifier.value = syncProgressNotifier.value.copyWith(
        completedTasks: completedModules,
      );
    }

    // Sync Classroom Observations
    if (pendingClassroom.isNotEmpty) {
      syncProgressNotifier.value = syncProgressNotifier.value.copyWith(
        currentTask: 'Syncing classroom observations...',
      );
      for (var item in pendingClassroom) {
        final success = await _syncSingleClassroom(item, headers);
        if (success) {
          await LocalStorageService.removePendingClassroomObservation(item);
          syncedItems++;
          syncProgressNotifier.value = syncProgressNotifier.value.copyWith(
            syncedItems: syncedItems,
            progress: syncedItems / totalItems,
          );
        }
      }
      completedModules.add('Classroom');
      syncProgressNotifier.value = syncProgressNotifier.value.copyWith(
        completedTasks: completedModules,
      );
    }

    // Sync Parent Participation
    if (pendingParent.isNotEmpty) {
      syncProgressNotifier.value = syncProgressNotifier.value.copyWith(
        currentTask: 'Syncing parent participation...',
      );
      await ParentLocalStorageService.syncPending(headers);
      syncedItems += pendingParent.length;
      syncProgressNotifier.value = syncProgressNotifier.value.copyWith(
        syncedItems: syncedItems,
        progress: syncedItems / totalItems,
      );
      completedModules.add('Parent');
      syncProgressNotifier.value = syncProgressNotifier.value.copyWith(
        completedTasks: completedModules,
      );
    }

    // Sync Student Participation
    if (pendingStudent.isNotEmpty) {
      syncProgressNotifier.value = syncProgressNotifier.value.copyWith(
        currentTask: 'Syncing student participation...',
      );
      await StudentLocalStorageService.syncPending(headers);
      syncedItems += pendingStudent.length;
      syncProgressNotifier.value = syncProgressNotifier.value.copyWith(
        syncedItems: syncedItems,
        progress: syncedItems / totalItems,
      );
      completedModules.add('Student');
      syncProgressNotifier.value = syncProgressNotifier.value.copyWith(
        completedTasks: completedModules,
      );
    }

    // Sync Textbooks
    if (pendingTextbooks.isNotEmpty) {
      syncProgressNotifier.value = syncProgressNotifier.value.copyWith(
        currentTask: 'Syncing textbooks...',
      );
      await TextbooksTeachingLocalStorageService.syncPending(headers);
      syncedItems += pendingTextbooks.length;
      syncProgressNotifier.value = syncProgressNotifier.value.copyWith(
        syncedItems: syncedItems,
        progress: syncedItems / totalItems,
      );
      completedModules.add('Textbooks');
      syncProgressNotifier.value = syncProgressNotifier.value.copyWith(
        completedTasks: completedModules,
      );
    }

    // Complete
    syncProgressNotifier.value = syncProgressNotifier.value.copyWith(
      currentTask: 'Complete!',
      progress: 1.0,
    );
  }

  void _showStorageInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => FutureBuilder<Map<String, int>>(
        future: _getDetailedCounts(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const AlertDialog(
              content: SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          }
          final counts = snapshot.data!;
          return AlertDialog(
            title: const Text('Storage Information'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _storageInfoRow('Schools', counts['schools']?.toString() ?? '0'),
                _storageInfoRow('Assessments', counts['assessments']?.toString() ?? '0'),
                _storageInfoRow('Document Checks', counts['documentChecks']?.toString() ?? '0'),
                _storageInfoRow('Infrastructure', counts['infrastructure']?.toString() ?? '0'),
                _storageInfoRow('Leadership', counts['leadership']?.toString() ?? '0'),
                _storageInfoRow('Classroom', counts['classroom']?.toString() ?? '0'),
                _storageInfoRow('Parent', counts['parent']?.toString() ?? '0'),
                _storageInfoRow('Student', counts['student']?.toString() ?? '0'),
                _storageInfoRow('Textbooks', counts['textbooks']?.toString() ?? '0'),
                const Divider(),
                _storageInfoRow('Total Pending', counts['total']?.toString() ?? '0'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<Map<String, int>> _getDetailedCounts() async {
    final schools = LocalStorageService.getPendingSchools().length;
    final assessments = LocalStorageService.getPendingAssessments().length;
    final documentChecks = LocalStorageService.getPendingDocumentChecks().length;
    final infrastructure = LocalStorageService.getPendingInfrastructure().length;
    final leadership = LocalStorageService.getPendingLeadership().length;
    final classroom = LocalStorageService.getPendingClassroomObservation().length;
    final parent = (await ParentLocalStorageService.getPending()).length;
    final student = (await StudentLocalStorageService.getPending()).length;
    final textbooks = (await TextbooksTeachingLocalStorageService.getPending()).length;
    final total = await _getTotalPendingCount();

    return {
      'schools': schools,
      'assessments': assessments,
      'documentChecks': documentChecks,
      'infrastructure': infrastructure,
      'leadership': leadership,
      'classroom': classroom,
      'parent': parent,
      'student': student,
      'textbooks': textbooks,
      'total': total,
    };
  }

  Widget _storageInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

// Preload Data Dialog with progress tracking
class PreloadDataDialog extends StatefulWidget {
  const PreloadDataDialog({super.key});

  @override
  State<PreloadDataDialog> createState() => _PreloadDataDialogState();
}

class _PreloadDataDialogState extends State<PreloadDataDialog> {
  bool _preloadComplete = false;

  @override
  void initState() {
    super.initState();
    DataPreloaderService.progressNotifier.addListener(_onProgressUpdate);
  }

  void _onProgressUpdate() {
    if (DataPreloaderService.preloadComplete && !_preloadComplete) {
      setState(() {
        _preloadComplete = true;
      });

      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          if (Navigator.canPop(context)) {
            Navigator.of(context).pop();
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Offline data preloaded successfully!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    DataPreloaderService.progressNotifier.removeListener(_onProgressUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  if (Navigator.canPop(context)) {
                    Navigator.of(context).pop();
                  }
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
            ValueListenableBuilder(
              valueListenable: DataPreloaderService.progressNotifier,
              builder: (context, progress, _) {
                return Column(
                  children: [
                    if (_preloadComplete)
                      const Icon(Icons.check_circle, color: Colors.green, size: 60)
                    else
                      const CircularProgressIndicator(),
                    const SizedBox(height: 24),
                    Text(
                      _preloadComplete ? 'Complete!' : progress.currentTask,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    if (!_preloadComplete) ...[
                      LinearProgressIndicator(
                        value: progress.progress,
                        backgroundColor: Colors.grey[200],
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 8),
                      Text('${(progress.progress * 100).toInt()}%'),
                    ],
                    if (progress.completedTasks.isNotEmpty && !_preloadComplete) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      ...progress.completedTasks.map((task) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                task,
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ),
                          ],
                        ),
                      )).toList(),
                    ],
                    if (_preloadComplete) ...[
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          if (Navigator.canPop(context)) {
                            Navigator.of(context).pop();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 45),
                        ),
                        child: const Text('Close'),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// Sync Data Dialog with progress tracking
class SyncDataDialog extends StatefulWidget {
  const SyncDataDialog({super.key});

  @override
  State<SyncDataDialog> createState() => _SyncDataDialogState();
}

class _SyncDataDialogState extends State<SyncDataDialog> {
  bool _syncComplete = false;

  @override
  void initState() {
    super.initState();
    syncProgressNotifier.addListener(_onProgressUpdate);
  }

  void _onProgressUpdate() {
    if (syncProgressNotifier.value.progress >= 1.0 && !_syncComplete) {
      setState(() {
        _syncComplete = true;
      });

      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          if (Navigator.canPop(context)) {
            Navigator.of(context).pop();
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ All data synced successfully!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    syncProgressNotifier.removeListener(_onProgressUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  if (Navigator.canPop(context)) {
                    Navigator.of(context).pop();
                  }
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
            ValueListenableBuilder<SyncProgress>(
              valueListenable: syncProgressNotifier,
              builder: (context, progress, _) {
                return Column(
                  children: [
                    if (_syncComplete)
                      const Icon(Icons.check_circle, color: Colors.green, size: 60)
                    else
                      const CircularProgressIndicator(),
                    const SizedBox(height: 24),
                    Text(
                      _syncComplete ? 'Complete!' : progress.currentTask,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    if (!_syncComplete) ...[
                      LinearProgressIndicator(
                        value: progress.progress,
                        backgroundColor: Colors.grey[200],
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 8),
                      Text('${(progress.progress * 100).toInt()}%'),
                      const SizedBox(height: 8),
                      Text(
                        '${progress.syncedItems} of ${progress.totalItems} items',
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                    if (progress.completedTasks.isNotEmpty && !_syncComplete) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      ...progress.completedTasks.map((task) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                task,
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ),
                          ],
                        ),
                      )).toList(),
                    ],
                    if (progress.moduleCounts.isNotEmpty && !_syncComplete) ...[
                      const SizedBox(height: 8),
                      const Divider(),
                      const SizedBox(height: 8),
                      ...progress.moduleCounts.entries.map((entry) {
                        if (entry.value == 0) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Icon(Icons.pending_rounded, color: Colors.orange, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${entry.key}: ${entry.value} items',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                    if (_syncComplete) ...[
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          if (Navigator.canPop(context)) {
                            Navigator.of(context).pop();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 45),
                        ),
                        child: const Text('Close'),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}