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

  Future<void> _syncSingleAssessmentFromCard(Map<String, dynamic> assessment) async {
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
      for (var r in assessment['absentRecords'] ?? []) {
        final res = await http.post(
          Uri.parse('${AppUrl.url}/schools/absents'),
          headers: headers,
          body: jsonEncode({...r, 'school': school}),
        );
        if (res.statusCode != 200 && res.statusCode != 201) {
          throw 'Absent failed: ${res.body}';
        }
      }

      for (var r in assessment['staffRecords'] ?? []) {
        final res = await http.post(
          Uri.parse('${AppUrl.url}/schools/staff'),
          headers: headers,
          body: jsonEncode({...r, 'school': school}),
        );
        if (res.statusCode != 200 && res.statusCode != 201) {
          throw 'Staff failed: ${res.body}';
        }
      }

      /*
      final req = assessment['reqTeachers'] ?? {};
      if ((req['level'] ?? '').toString().trim().isNotEmpty) {
        final res = await http.post(
          Uri.parse('${AppUrl.url}/schools/req-teachers'),
          headers: headers,
          body: jsonEncode({...req, 'school': school}),
        );
        if (res.statusCode != 200 && res.statusCode != 201) {
          throw 'Req-teachers failed: ${res.body}';
        }
      }
      */

      final verifyLegacy = assessment['verifyStudents'] ?? {};
      if ((verifyLegacy['class'] ?? '').toString().trim().isNotEmpty) {
        final res = await http.post(
          Uri.parse('${AppUrl.url}/schools/verify-students'),
          headers: headers,
          body: jsonEncode({...verifyLegacy, 'school': school}),
        );
        if (res.statusCode != 200 && res.statusCode != 201) {
          throw 'Legacy verify-students failed: ${res.body}';
        }
      }

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
        if (res.statusCode != 200 && res.statusCode != 201) {
          throw 'Verify-student row failed: ${res.body}';
        }
      }

      /*
      for (var r in assessment['feeRecords'] ?? []) {
        final res = await http.post(
          Uri.parse('${AppUrl.url}/schools/fees-paid'),
          headers: headers,
          body: jsonEncode({...r, 'school': school}),
        );
        if (res.statusCode != 200 && res.statusCode != 201) {
          throw 'Fees failed: ${res.body}';
        }
      }
      */

      debugPrint('Full assessment synced successfully');
      return true;
    } catch (e) {
      debugPrint('Assessment sync error: $e');
      return false;
    }
  }

  Future<void> _removeFromPending(Map<String, dynamic> assessmentToRemove) async {
    final current = LocalStorageService.getPendingAssessments();
    final updated = current.where((a) => a['queuedAt'] != assessmentToRemove['queuedAt']).toList();
    final box = Hive.box(LocalStorageService.pendingAssessmentsBox);
    await box.put('pending', updated);
    setState(() => _pendingAssessments = updated);
  }

  Future<void> _updatePendingAssessment(Map<String, dynamic> updatedAssessment) async {
    final current = LocalStorageService.getPendingAssessments();
    final index = current.indexWhere((a) => a['queuedAt'] == updatedAssessment['queuedAt']);

    if (index != -1) {
      current[index] = updatedAssessment;
      final box = Hive.box(LocalStorageService.pendingAssessmentsBox);
      await box.put('pending', current);

      setState(() {
        _pendingAssessments = current;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Assessment data updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
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

  void _showEditDialog(Map<String, dynamic> assessment) {
    final editableAssessment = Map<String, dynamic>.from(assessment);

    List<Map<String, dynamic>> staffRecords = [];
    if (editableAssessment['staffRecords'] != null) {
      staffRecords = (editableAssessment['staffRecords'] as List).map((record) {
        return Map<String, dynamic>.from(record);
      }).toList();
    }

    /*
    List<Map<String, dynamic>> feeRecords = [];
    if (editableAssessment['feeRecords'] != null) {
      feeRecords = (editableAssessment['feeRecords'] as List).map((record) {
        return Map<String, dynamic>.from(record);
      }).toList();
    }
    */

    List<Map<String, dynamic>> verifyRecords = [];
    if (editableAssessment['verifyStudentRecords'] != null) {
      verifyRecords = (editableAssessment['verifyStudentRecords'] as List).map((record) {
        return Map<String, dynamic>.from(record);
      }).toList();
    }

    /*
    Map<String, dynamic> reqTeachers = {};
    if (editableAssessment['reqTeachers'] != null) {
      reqTeachers = Map<String, dynamic>.from(editableAssessment['reqTeachers']);
    }
    */

    final schoolNameController = TextEditingController(text: editableAssessment['schoolName'] ?? '');
    final schoolCodeController = TextEditingController(text: editableAssessment['schoolCode'] ?? '');
    final levelController = TextEditingController(text: editableAssessment['level'] ?? 'ECE');

    /*
    final reqLevelController = TextEditingController(text: reqTeachers['level'] ?? '');
    final reqAssTeacherController = TextEditingController(text: reqTeachers['ass_teacher']?.toString() ?? '');
    final reqVolunteersController = TextEditingController(text: reqTeachers['volunteers']?.toString() ?? '');
    final reqStudentsController = TextEditingController(text: reqTeachers['students']?.toString() ?? '');
    final reqNumRequiredController = TextEditingController(text: reqTeachers['num_req']?.toString() ?? '');

    String? reqSelfContain = reqTeachers['self_contain'] ?? 'No';
    */

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('Edit Assessment: ${editableAssessment['schoolName'] ?? 'Unnamed'}'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('School Information', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: schoolNameController,
                      decoration: const InputDecoration(
                        labelText: 'School Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: schoolCodeController,
                      decoration: const InputDecoration(
                        labelText: 'School Code',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: levelController,
                      decoration: const InputDecoration(
                        labelText: 'School Level',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    const Text('Staff Records', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    ...staffRecords.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final staff = entry.value;

                      final fnameController = TextEditingController(text: staff['fname'] ?? '');
                      final positionController = TextEditingController(text: staff['position'] ?? '');
                      final weekLoadController = TextEditingController(text: staff['week_load']?.toString() ?? '');
                      final bioIdController = TextEditingController(text: staff['bio_id'] ?? '');
                      final payIdController = TextEditingController(text: staff['pay_id'] ?? '');
                      final qualificationController = TextEditingController(text: staff['qualification'] ?? '');

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            children: [
                              Text('Staff #${idx + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: fnameController,
                                decoration: const InputDecoration(
                                  labelText: 'Full Name',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (value) => staff['fname'] = value,
                              ),
                              const SizedBox(height: 4),
                              DropdownButtonFormField<String>(
                                value: staff['gender'] ?? 'Male',
                                decoration: const InputDecoration(
                                  labelText: 'Gender',
                                  border: OutlineInputBorder(),
                                ),
                                items: ['Male', 'Female']
                                    .map((gender) => DropdownMenuItem(value: gender, child: Text(gender)))
                                    .toList(),
                                onChanged: (value) => staff['gender'] = value,
                              ),
                              const SizedBox(height: 4),
                              TextFormField(
                                controller: positionController,
                                decoration: const InputDecoration(
                                  labelText: 'Position',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (value) => staff['position'] = value,
                              ),
                              const SizedBox(height: 4),
                              TextFormField(
                                controller: weekLoadController,
                                decoration: const InputDecoration(
                                  labelText: 'Weekly Load',
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (value) => staff['week_load'] = value,
                              ),
                              const SizedBox(height: 4),
                              DropdownButtonFormField<String>(
                                value: staff['present'] ?? 'Yes',
                                decoration: const InputDecoration(
                                  labelText: 'Present',
                                  border: OutlineInputBorder(),
                                ),
                                items: ['Yes', 'No', 'Partial']
                                    .map((present) => DropdownMenuItem(value: present, child: Text(present)))
                                    .toList(),
                                onChanged: (value) => staff['present'] = value,
                              ),
                              const SizedBox(height: 4),
                              TextFormField(
                                controller: bioIdController,
                                decoration: const InputDecoration(
                                  labelText: 'Bio ID',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (value) => staff['bio_id'] = value,
                              ),
                              const SizedBox(height: 4),
                              TextFormField(
                                controller: payIdController,
                                decoration: const InputDecoration(
                                  labelText: 'Pay ID',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (value) => staff['pay_id'] = value,
                              ),
                              const SizedBox(height: 4),
                              TextFormField(
                                controller: qualificationController,
                                decoration: const InputDecoration(
                                  labelText: 'Qualification',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (value) => staff['qualification'] = value,
                              ),
                              if (staff['present'] == 'No') ...[
                                const SizedBox(height: 4),
                                DropdownButtonFormField<String>(
                                  value: staff['excuse'] ?? 'Yes',
                                  decoration: const InputDecoration(
                                    labelText: 'Excuse',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: ['Yes', 'No']
                                      .map((excuse) => DropdownMenuItem(value: excuse, child: Text(excuse)))
                                      .toList(),
                                  onChanged: (value) => staff['excuse'] = value,
                                ),
                                const SizedBox(height: 4),
                                TextFormField(
                                  controller: TextEditingController(text: staff['reason'] ?? ''),
                                  decoration: const InputDecoration(
                                    labelText: 'Reason',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (value) => staff['reason'] = value,
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),

                    if (staffRecords.isEmpty)
                      const Text('No staff records', style: TextStyle(color: Colors.grey)),

                    const SizedBox(height: 16),

                    /*
                    const Text('Required Teachers', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: reqLevelController,
                      decoration: const InputDecoration(
                        labelText: 'Level',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => reqTeachers['level'] = value,
                    ),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      value: reqSelfContain,
                      decoration: const InputDecoration(
                        labelText: 'Self-contained class?',
                        border: OutlineInputBorder(),
                      ),
                      items: ['Yes', 'No', 'Partial']
                          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          reqSelfContain = value;
                          reqTeachers['self_contain'] = value;
                        });
                      },
                    ),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: reqAssTeacherController,
                      decoration: const InputDecoration(
                        labelText: 'Assigned Teachers',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) => reqTeachers['ass_teacher'] = value,
                    ),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: reqVolunteersController,
                      decoration: const InputDecoration(
                        labelText: 'Volunteers',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) => reqTeachers['volunteers'] = value,
                    ),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: reqStudentsController,
                      decoration: const InputDecoration(
                        labelText: 'Students',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) => reqTeachers['students'] = value,
                    ),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: reqNumRequiredController,
                      decoration: const InputDecoration(
                        labelText: 'Teachers Required',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) => reqTeachers['num_req'] = value,
                    ),

                    const SizedBox(height: 16),
                    */

                    /*
                    const Text('Fee Records', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    ...feeRecords.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final fee = entry.value;

                      final feeController = TextEditingController(text: fee['fee'] ?? '');
                      final purposeController = TextEditingController(text: fee['purpose'] ?? '');
                      final amountController = TextEditingController(text: fee['amount']?.toString() ?? '');

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            children: [
                              Text('Fee #${idx + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              TextFormField(
                                controller: feeController,
                                decoration: const InputDecoration(
                                  labelText: 'Fee Type',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (value) => fee['fee'] = value,
                              ),
                              const SizedBox(height: 4),
                              DropdownButtonFormField<String>(
                                value: fee['pay'] ?? 'Yes',
                                decoration: const InputDecoration(
                                  labelText: 'Pay?',
                                  border: OutlineInputBorder(),
                                ),
                                items: ['Yes', 'No']
                                    .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                                    .toList(),
                                onChanged: (value) => fee['pay'] = value,
                              ),
                              const SizedBox(height: 4),
                              TextFormField(
                                controller: purposeController,
                                decoration: const InputDecoration(
                                  labelText: 'Purpose',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (value) => fee['purpose'] = value,
                              ),
                              const SizedBox(height: 4),
                              TextFormField(
                                controller: amountController,
                                decoration: const InputDecoration(
                                  labelText: 'Amount',
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (value) => fee['amount'] = value,
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),

                    const SizedBox(height: 16),
                    */

                    const Text('Verify Student Records', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    ...verifyRecords.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final record = entry.value;

                      final classGradeController = TextEditingController(text: record['classGrade'] ?? '');
                      final emisMaleController = TextEditingController(text: record['emisMale']?.toString() ?? '0');
                      final countMaleController = TextEditingController(text: record['countMale']?.toString() ?? '0');
                      final emisFemaleController = TextEditingController(text: record['emisFemale']?.toString() ?? '0');
                      final countFemaleController = TextEditingController(text: record['countFemale']?.toString() ?? '0');

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            children: [
                              Text('Grade #${idx + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              TextFormField(
                                controller: classGradeController,
                                decoration: const InputDecoration(
                                  labelText: 'Class Grade',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (value) => record['classGrade'] = value,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: emisMaleController,
                                      decoration: const InputDecoration(
                                        labelText: 'EMIS Male',
                                        border: OutlineInputBorder(),
                                      ),
                                      keyboardType: TextInputType.number,
                                      onChanged: (value) => record['emisMale'] = value,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: TextFormField(
                                      controller: countMaleController,
                                      decoration: const InputDecoration(
                                        labelText: 'Count Male',
                                        border: OutlineInputBorder(),
                                      ),
                                      keyboardType: TextInputType.number,
                                      onChanged: (value) => record['countMale'] = value,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: emisFemaleController,
                                      decoration: const InputDecoration(
                                        labelText: 'EMIS Female',
                                        border: OutlineInputBorder(),
                                      ),
                                      keyboardType: TextInputType.number,
                                      onChanged: (value) => record['emisFemale'] = value,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: TextFormField(
                                      controller: countFemaleController,
                                      decoration: const InputDecoration(
                                        labelText: 'Count Female',
                                        border: OutlineInputBorder(),
                                      ),
                                      keyboardType: TextInputType.number,
                                      onChanged: (value) => record['countFemale'] = value,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  editableAssessment['schoolName'] = schoolNameController.text;
                  editableAssessment['schoolCode'] = schoolCodeController.text;
                  editableAssessment['level'] = levelController.text;
                  editableAssessment['staffRecords'] = staffRecords;
                  // editableAssessment['feeRecords'] = feeRecords;
                  editableAssessment['verifyStudentRecords'] = verifyRecords;
                  // editableAssessment['reqTeachers'] = reqTeachers;

                  Navigator.pop(context);
                  await _updatePendingAssessment(editableAssessment);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Update'),
              ),
            ],
          );
        },
      ),
    );
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
          StreamBuilder<bool>(
            stream: LocalStorageService.onlineStatusStream,
            initialData: LocalStorageService.currentOnlineStatus,
            builder: (context, snapshot) {
              final bool isOnline = snapshot.data ?? true;
              return Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isOnline ? Colors.green : Colors.orange,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isOnline ? Icons.wifi : Icons.wifi_off, color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      isOnline ? 'Online' : 'Offline',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh list',
            onPressed: _loadPendingAssessments,
          ),
        ],
      ),
      body: StreamBuilder<bool>(
        stream: LocalStorageService.onlineStatusStream,
        initialData: LocalStorageService.currentOnlineStatus,
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
                    'You are offline. Sync buttons are disabled until connected.',
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
                      const Text('No Pending Assessments', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      const Text('All assessments have been synced or cleared.', style: TextStyle(color: Colors.grey, fontSize: 16)),
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
                      // final feeCount = (assessment['feeRecords'] as List?)?.length ?? 0;
                      final verifyCount = (assessment['verifyStudentRecords'] as List?)?.length ?? 0;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        elevation: 3,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: InkWell(
                          onTap: () => _showEditDialog(assessment),
                          borderRadius: BorderRadius.circular(16),
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
                                    'Data: $absentCount absent • $staffCount staff • $verifyCount verify',
                                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
                                  tooltip: 'Edit this pending assessment',
                                  onPressed: _isSyncing ? null : () => _showEditDialog(assessment),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                                  tooltip: 'Delete this pending assessment',
                                  onPressed: _isSyncing ? null : () => _deletePending(index),
                                ),
                                IconButton(
                                  icon: Icon(Icons.sync_rounded, color: isOnline ? AppColors.primary : Colors.grey),
                                  tooltip: isOnline ? 'Sync now' : 'Offline - connect to sync',
                                  onPressed: (isOnline && !_isSyncing)
                                      ? () => _syncSingleAssessmentFromCard(assessment)
                                      : null,
                                ),
                              ],
                            ),
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
        initialData: LocalStorageService.currentOnlineStatus,
        builder: (context, snapshot) {
          final bool isOnline = snapshot.data ?? true;
          return FloatingActionButton.extended(
            heroTag: 'sync_all_assessments',
            onPressed: (isOnline && !_isSyncing) ? _syncAll : null,
            backgroundColor: isOnline ? AppColors.primary : Colors.grey,
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