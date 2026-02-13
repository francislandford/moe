import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_url.dart';
import '../../../../core/services/local_storage_service.dart';
import '../../../../core/widgets/custom_app_bar.dart';
import '../../../../core/widgets/loading_overlay.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/assessment_provider.dart';

class OfflineAssessmentsPage extends StatefulWidget {
  const OfflineAssessmentsPage({super.key});

  @override
  State<OfflineAssessmentsPage> createState() => _OfflineAssessmentsPageState();
}

class _OfflineAssessmentsPageState extends State<OfflineAssessmentsPage> {
  bool _isSyncing = false;
  List<Map<String, dynamic>> _pendingAssessments = [];

  @override
  void initState() {
    super.initState();
    _loadPendingAssessments();
  }

  Future<void> _loadPendingAssessments() async {
    setState(() {
      _pendingAssessments = LocalStorageService.getPendingAssessments();
    });
  }

  Future<void> _syncAll() async {
    if (!await LocalStorageService.isOnline()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No internet connection. Connect and try again.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSyncing = true);

    int successCount = 0;
    final pendingCopy = List<Map<String, dynamic>>.from(_pendingAssessments);

    for (var assessment in pendingCopy) {
      try {
        final success = await _syncSingleAssessment(assessment, context);
        if (success) {
          successCount++;
          await _removeFromPending(assessment);
        }
      } catch (e) {
        debugPrint('Sync failed for one assessment: $e');
      }
    }

    await _loadPendingAssessments();
    setState(() => _isSyncing = false);

    if (successCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$successCount assessment(s) synced successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No assessments were synced. Check logs or try again.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  /// Syncs ONE queued assessment — submits ALL sections
  Future<bool> _syncSingleAssessment(Map<String, dynamic> assessment, BuildContext context) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!auth.isAuthenticated || auth.token == null) {
      debugPrint('Cannot sync: not authenticated');
      return false;
    }

    final token = auth.token!;
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    };

    final school = assessment['schoolCode'] ?? assessment['schoolName'] ?? 'unknown';
    debugPrint('Syncing assessment for school: $school (queued: ${assessment['queuedAt']})');

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
        debugPrint('Absent sync: ${res.statusCode}');
        if (res.statusCode != 201) throw 'Absent failed: ${res.body}';
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
        debugPrint('Staff sync: ${res.statusCode}');
        if (res.statusCode != 201) throw 'Staff failed: ${res.body}';
      }

      // 3. Required Teachers (only if data exists)
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
        debugPrint('Req-teachers sync: ${res.statusCode}');
        if (res.statusCode != 201) throw 'Req-teachers failed: ${res.body}';
      }

      // 4. Verify Students (only if data exists)
      final verify = assessment['verifyStudents'] ?? {};
      if ((verify['class'] ?? '').toString().trim().isNotEmpty) {
        final res = await http.post(
          Uri.parse('${AppUrl.url}/schools/verify-students'),
          headers: headers,
          body: jsonEncode({
            ...verify,
            'school': school,
          }),
        );
        debugPrint('Verify-students sync: ${res.statusCode}');
        if (res.statusCode != 201) throw 'Verify-students failed: ${res.body}';
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
        debugPrint('Fees sync: ${res.statusCode}');
        if (res.statusCode != 201) throw 'Fees failed: ${res.body}';
      }

      debugPrint('Full assessment synced successfully');
      return true;
    } catch (e) {
      debugPrint('Assessment sync error: $e');
      return false;
    }
  }

  Future<void> _removeFromPending(Map<String, dynamic> assessmentToRemove) async {
    final current = LocalStorageService.getPendingAssessments();
    final updated = current.where((a) {
      return a['queuedAt'] != assessmentToRemove['queuedAt'];
    }).toList();

    final box = Hive.box(LocalStorageService.pendingAssessmentsBox);
    await box.put('pending', updated);

    setState(() {
      _pendingAssessments = updated;
    });
  }

  Future<void> _deletePending(int index) async {
    final assessment = _pendingAssessments[index];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Pending Assessment'),
        content: const Text('Are you sure? This unsynced assessment will be permanently removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _removeFromPending(assessment);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pending assessment deleted'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Offline Assessments',
        backgroundColor: AppColors.primary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          tooltip: 'Back to Home',
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh list',
            onPressed: _loadPendingAssessments,
          ),
        ],
      ),
      body: StreamBuilder<bool>(
        stream: LocalStorageService.onlineStatusStream,
        initialData: true,
        builder: (context, snapshot) {
          final bool isOnline = snapshot.data ?? true;

          return Column(
            children: [
              if (!isOnline)
                Container(
                  width: double.infinity,
                  color: Colors.orange.shade100,
                  padding: const EdgeInsets.all(12),
                  child: const Text(
                    'Offline Mode — Sync buttons disabled until connected',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w600),
                  ),
                ),

              Expanded(
                child: _pendingAssessments.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_done_rounded, size: 90, color: Colors.green.shade300),
                      const SizedBox(height: 20),
                      const Text(
                        'No Pending Assessments',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'All assessments have been synced or cleared.',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ],
                  ),
                )
                    : RefreshIndicator(
                  onRefresh: _loadPendingAssessments,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _pendingAssessments.length,
                    itemBuilder: (context, index) {
                      final assessment = _pendingAssessments[index];
                      final date = assessment['queuedAt'] != null
                          ? DateFormat('dd MMM yyyy, HH:mm').format(DateTime.parse(assessment['queuedAt']))
                          : 'Unknown date';

                      final absentCount = (assessment['absentRecords'] as List?)?.length ?? 0;
                      final staffCount = (assessment['staffRecords'] as List?)?.length ?? 0;
                      final feeCount = (assessment['feeRecords'] as List?)?.length ?? 0;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        elevation: 3,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                          leading: CircleAvatar(
                            radius: 30,
                            backgroundColor: AppColors.primary.withOpacity(0.15),
                            child: Icon(Icons.assessment_rounded, color: AppColors.primary, size: 32),
                          ),
                          title: Text(
                            assessment['schoolName'] ?? 'Unnamed School',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Code: ${assessment['schoolCode'] ?? 'N/A'}', style: const TextStyle(fontSize: 14)),
                                Text('Queued: $date', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                                const SizedBox(height: 4),
                                Text(
                                  'Data: $absentCount absent • $staffCount staff • $feeCount fees',
                                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                                tooltip: 'Delete this pending assessment',
                                onPressed: () => _deletePending(index),
                              ),
                              IconButton(
                                icon: const Icon(Icons.sync_rounded, color: AppColors.primary),
                                tooltip: isOnline ? 'Sync now' : 'Offline - connect to sync',
                                onPressed: isOnline
                                    ? () async {
                                  setState(() => _isSyncing = true);
                                  final success = await _syncSingleAssessment(assessment, context);
                                  if (success) {
                                    await _removeFromPending(assessment);
                                    await _loadPendingAssessments();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Synced successfully'), backgroundColor: Colors.green),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Sync failed'), backgroundColor: Colors.orange),
                                    );
                                  }
                                  setState(() => _isSyncing = false);
                                }
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: _pendingAssessments.isNotEmpty
          ? StreamBuilder<bool>(
        stream: LocalStorageService.onlineStatusStream,
        initialData: true,
        builder: (context, snapshot) {
          final bool canSync = snapshot.data ?? false;

          return FloatingActionButton.extended(
            heroTag: 'sync_all_assessments',
            onPressed: canSync && !_isSyncing ? _syncAll : null,
            backgroundColor: canSync ? AppColors.primary : Colors.grey,
            icon: _isSyncing
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
            )
                : const Icon(Icons.sync_rounded, color: Colors.white),
            label: Text(
              _isSyncing ? 'Syncing...' : 'Sync All (${_pendingAssessments.length})',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          );
        },
      )
          : null,
    );
  }
}