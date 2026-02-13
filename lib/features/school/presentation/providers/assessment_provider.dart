import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../../../core/constants/app_url.dart';
import '../../../../core/services/local_storage_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class AssessmentProvider with ChangeNotifier {
  String schoolName = '';
  String schoolCode = '';
  String level = 'ECE';

  // Dynamic lists
  List<Map<String, dynamic>> absentRecords = [];
  List<Map<String, dynamic>> staffRecords = [];
  List<Map<String, dynamic>> feeRecords = [];
  List<Map<String, dynamic>> verifyStudentRecords = [];

  // Required Teachers
  String reqLevel = '';
  String reqSelfContain = 'No';
  String reqAssTeacher = '';
  String reqVolunteers = '';
  String reqStudents = '';
  String reqNumRequired = '';

  // Legacy verify students (single fields - kept as requested)
  String verifyClass = '';
  String emisMale = '';
  String countMale = '';
  String emisFemale = '';
  String countFemale = '';

  // Grades for Verify Students dropdown (shared across rows)
  List<Map<String, dynamic>> gradesForLevel = [];

  bool isSubmitting = false;
  String? lastError;
  bool lastOffline = false;

  // ─── Add / Remove / Update Methods ──────────────────────────────────────────
  void addAbsent() {
    absentRecords.add({
      'fname': TextEditingController(),
      'bio_id': TextEditingController(),
      'pay_id': TextEditingController(),
      'reason': TextEditingController(),
      'excuse': 'Yes',
    });
    notifyListeners();
  }

  void removeAbsent(int index) {
    if (index >= 0 && index < absentRecords.length) {
      absentRecords.removeAt(index);
      notifyListeners();
    }
  }

  void addStaff() {
    staffRecords.add({
      'fname': TextEditingController(),
      'gender': 'Male',
      'position': TextEditingController(),
      'week_load': TextEditingController(),
      'present': 'Yes',
      'bio_id': TextEditingController(),
      'pay_id': TextEditingController(),
      'qualification': TextEditingController(),
    });
    notifyListeners();
  }

  void removeStaff(int index) {
    if (index >= 0 && index < staffRecords.length) {
      staffRecords.removeAt(index);
      notifyListeners();
    }
  }

  void addFeeRecord() {
    feeRecords.add({
      'fee': 'Tuition fees',
      'pay': 'Yes',
      'purpose': TextEditingController(),
      'amount': TextEditingController(),
    });
    notifyListeners();
  }

  void removeFee(int index) {
    if (index >= 0 && index < feeRecords.length) {
      feeRecords.removeAt(index);
      notifyListeners();
    }
  }

  void updateFee(int index, String key, dynamic value) {
    if (index >= 0 && index < feeRecords.length) {
      feeRecords[index][key] = value;
      notifyListeners();
    }
  }

  void addVerifyStudent() {
    verifyStudentRecords.add({
      'classGrade': null,
      'verifyClass': '',
      'emisMale': TextEditingController(),
      'countMale': TextEditingController(),
      'emisFemale': TextEditingController(),
      'countFemale': TextEditingController(),
    });
    notifyListeners();
  }

  void removeVerifyStudent(int index) {
    if (index >= 0 && index < verifyStudentRecords.length) {
      verifyStudentRecords.removeAt(index);
      notifyListeners();
    }
  }

  void updateVerifyStudent(int index, String key, dynamic value) {
    if (index >= 0 && index < verifyStudentRecords.length) {
      verifyStudentRecords[index][key] = value;
      notifyListeners();
    }
  }

  // ─── Fetch grades for Verify Students dropdown ──────────────────────────────
  Future<void> fetchGradesForLevel(String schoolLevel, BuildContext context) async {
    print('Fetching grades for level: $schoolLevel');
    gradesForLevel = [];
    notifyListeners();

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isAuthenticated || authProvider.token == null) {
      print('Cannot fetch grades: User is not authenticated');
      lastError = 'Authentication required to fetch grades';
      notifyListeners();
      return;
    }

    final token = authProvider.token!;
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    };

    try {
      final uri = Uri.parse('${AppUrl.url}/level/grades?level=$schoolLevel');
      print('Requesting: $uri');
      final res = await http.get(uri, headers: headers);

      print('Grades response status: ${res.statusCode}');
      print('Response body: ${res.body}');

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        List<Map<String, dynamic>> loaded = [];

        if (data is List) {
          loaded = List<Map<String, dynamic>>.from(data);
        } else if (data is Map && data.containsKey('data')) {
          loaded = List<Map<String, dynamic>>.from(data['data']);
        }

        // Deduplicate by 'id'
        final seen = <String>{};
        gradesForLevel = loaded.where((grade) {
          final id = grade['id']?.toString();
          if (id == null || id.isEmpty) return false;
          return seen.add(id);
        }).toList();

        print('Loaded ${gradesForLevel.length} unique grades');

        if (gradesForLevel.isNotEmpty) {
          print('First grade sample: ${gradesForLevel.first}');
        }
      } else {
        print('Failed to load grades - status ${res.statusCode}');
        print('Response body: ${res.body}');
      }
    } catch (e, stack) {
      print('Fetch grades error: $e');
      print('Stack trace: $stack');
      lastError = 'Failed to fetch grades: $e';
    }

    notifyListeners();
  }

  // ─── Submission – Offline-first + Queue ─────────────────────────────────────
  Future<bool> submitAllData(BuildContext context) async {
    isSubmitting = true;
    lastError = null;
    lastOffline = false;
    notifyListeners();

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isAuthenticated || authProvider.token == null) {
      lastError = 'You must be logged in.';
      isSubmitting = false;
      notifyListeners();
      return false;
    }

    final token = authProvider.token!;
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    };

    final isOnlineNow = await LocalStorageService.isOnline();

    try {
      if (isOnlineNow) {
        // 1. Submit Absent Teachers
        for (var r in absentRecords) {
          try {
            final res = await http.post(
              Uri.parse('${AppUrl.url}/schools/absents'),
              headers: headers,
              body: jsonEncode({
                'school': schoolCode.trim(),
                'fname': r['fname'].text.trim(),
                'bio_id': r['bio_id'].text.trim(),
                'pay_id': r['pay_id'].text.trim(),
                'reason': r['reason'].text.trim(),
                'excuse': r['excuse'],
              }),
            );
            print('Absent submission: ${res.statusCode}');
            if (res.statusCode != 201) {
              throw Exception('Absent failed: ${res.statusCode} - ${res.body}');
            }
          } catch (e, stack) {
            print('Absent submission error: $e');
            print('Stack: $stack');
            lastError = 'Absent submission failed: $e';
          }
        }

        // 2. Submit Staff Records
        for (var r in staffRecords) {
          try {
            final res = await http.post(
              Uri.parse('${AppUrl.url}/schools/staff'),
              headers: headers,
              body: jsonEncode({
                'school': schoolCode.trim(),
                'fname': r['fname'].text.trim(),
                'gender': r['gender'],
                'position': r['position'].text.trim(),
                'week_load': int.tryParse(r['week_load'].text.trim() ?? '0') ?? 0,
                'present': r['present'],
                'bio_id': r['bio_id'].text.trim(),
                'pay_id': r['pay_id'].text.trim(),
                'qualification': r['qualification'].text.trim(),
              }),
            );
            print('Staff submission: ${res.statusCode}');
            if (res.statusCode != 201) {
              throw Exception('Staff failed: ${res.statusCode} - ${res.body}');
            }
          } catch (e, stack) {
            print('Staff submission error: $e');
            print('Stack: $stack');
            lastError = 'Staff submission failed: $e';
          }
        }

        // 3. Submit Required Teachers - FIXED: Added detailed logging
        if (reqLevel.trim().isNotEmpty) {
          try {
            final payload = {
              'school': schoolCode.trim(),
              'level': reqLevel.trim(),
              'self_contain': reqSelfContain,
              'ass_teacher': int.tryParse(reqAssTeacher.trim() ?? '0') ?? 0,
              'volunteers': int.tryParse(reqVolunteers.trim() ?? '0') ?? 0,
              'students': int.tryParse(reqStudents.trim() ?? '0') ?? 0,
              'num_req': int.tryParse(reqNumRequired.trim() ?? '0') ?? 0,
            };

            print('Attempting req-teachers POST with payload: ${jsonEncode(payload)}');

            final res = await http.post(
              Uri.parse('${AppUrl.url}/schools/req-teachers'),
              headers: headers,
              body: jsonEncode(payload),
            );

            print('Req Teachers response: ${res.statusCode} - ${res.body}');

            if (res.statusCode != 201) {
              throw Exception('Req Teachers failed: ${res.statusCode} - ${res.body}');
            }
          } catch (e, stack) {
            print('Req Teachers submission error: $e');
            print('Stack: $stack');
            lastError = 'Required Teachers submission failed: $e';
          }
        } else {
          print('Skipping req-teachers submission: reqLevel is empty');
        }

        // 4. Submit Legacy Verify Students
        if (verifyClass.trim().isNotEmpty) {
          try {
            final res = await http.post(
              Uri.parse('${AppUrl.url}/schools/verify-students'),
              headers: headers,
              body: jsonEncode({
                'school': schoolCode.trim(),
                'classes': verifyClass.trim(),
                'emis_male': int.tryParse(emisMale.trim() ?? '0') ?? 0,
                'count_male': int.tryParse(countMale.trim() ?? '0') ?? 0,
                'emis_female': int.tryParse(emisFemale.trim() ?? '0') ?? 0,
                'count_female': int.tryParse(countFemale.trim() ?? '0') ?? 0,
              }),
            );
            print('Legacy Verify: ${res.statusCode}');
            if (res.statusCode != 201) {
              throw Exception('Legacy Verify failed: ${res.statusCode} - ${res.body}');
            }
          } catch (e, stack) {
            print('Legacy Verify submission error: $e');
            print('Stack: $stack');
            lastError = 'Legacy Verify submission failed: $e';
          }
        }

        // 5. Submit Dynamic Verify Students
        for (var r in verifyStudentRecords) {
          try {
            final gradeId = r['classGrade']?.toString() ?? '';
            if (gradeId.isEmpty) continue;

            final payload = {
              'school': schoolCode.trim(),
              'classes': gradeId,
              'emis_male': int.tryParse(r['emisMale'].text.trim() ?? '0') ?? 0,
              'count_male': int.tryParse(r['countMale'].text.trim() ?? '0') ?? 0,
              'emis_female': int.tryParse(r['emisFemale'].text.trim() ?? '0') ?? 0,
              'count_female': int.tryParse(r['countFemale'].text.trim() ?? '0') ?? 0,
            };

            print('Sending verify row: ${jsonEncode(payload)}');

            final res = await http.post(
              Uri.parse('${AppUrl.url}/schools/verify-students'),
              headers: headers,
              body: jsonEncode(payload),
            );

            print('Verify row response: ${res.statusCode} - ${res.body}');

            if (res.statusCode != 201) {
              throw Exception('Verify row failed: ${res.statusCode} - ${res.body}');
            }
          } catch (e, stack) {
            print('Dynamic Verify submission error: $e');
            print('Stack: $stack');
            lastError = 'Dynamic Verify submission failed: $e';
          }
        }

        // 6. Submit Fees
        for (var r in feeRecords) {
          try {
            final amount = double.tryParse(r['amount'].text.trim() ?? '0') ?? 0.0;
            final res = await http.post(
              Uri.parse('${AppUrl.url}/schools/fees-paid'),
              headers: headers,
              body: jsonEncode({
                'school': schoolCode.trim(),
                'fee': r['fee'],
                'pay': r['pay'],
                'purpose': r['purpose'].text.trim(),
                'amount': amount,
              }),
            );
            print('Fee submission: ${res.statusCode}');
            if (res.statusCode != 201) {
              throw Exception('Fee failed: ${res.statusCode} - ${res.body}');
            }
          } catch (e, stack) {
            print('Fee submission error: $e');
            print('Stack: $stack');
            lastError = 'Fee submission failed: $e';
          }
        }

        // All good
        await _syncPendingAssessments(context);
        lastOffline = false;
        return true;
      } else {
        final payload = _buildAssessmentPayload();
        await LocalStorageService.savePendingAssessment(payload);
        lastOffline = true;
        return true;
      }
    } catch (e, stack) {
      lastError = e.toString();
      debugPrint('Submit error: $e');
      debugPrint('Stack: $stack');
      final payload = _buildAssessmentPayload();
      await LocalStorageService.savePendingAssessment(payload);
      lastOffline = true;
      return true;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  // ─── Build payload for offline storage ──────────────────────────────────────
  Map<String, dynamic> _buildAssessmentPayload() {
    return {
      'schoolName': schoolName,
      'schoolCode': schoolCode,
      'level': level,
      'absentRecords': absentRecords.map((r) => {
        'fname': r['fname'].text.trim(),
        'bio_id': r['bio_id'].text.trim(),
        'pay_id': r['pay_id'].text.trim(),
        'reason': r['reason'].text.trim(),
        'excuse': r['excuse'],
      }).toList(),
      'staffRecords': staffRecords.map((r) => {
        'fname': r['fname'].text.trim(),
        'gender': r['gender'],
        'position': r['position'].text.trim(),
        'week_load': r['week_load'].text.trim(),
        'present': r['present'],
        'bio_id': r['bio_id'].text.trim(),
        'pay_id': r['pay_id'].text.trim(),
        'qualification': r['qualification'].text.trim(),
      }).toList(),
      'reqTeachers': {
        'level': reqLevel.trim(),
        'self_contain': reqSelfContain,
        'ass_teacher': reqAssTeacher.trim(),
        'volunteers': reqVolunteers.trim(),
        'students': reqStudents.trim(),
        'num_req': reqNumRequired.trim(),
      },
      // Legacy single verify (kept as requested)
      'verifyStudents': {
        'class': verifyClass.trim(),
        'emis_male': emisMale.trim(),
        'count_male': countMale.trim(),
        'emis_female': emisFemale.trim(),
        'count_female': countFemale.trim(),
      },
      // Dynamic verify students rows
      'verifyStudentRecords': verifyStudentRecords.map((r) => {
        'classGrade': r['classGrade'],
        'verifyClass': r['verifyClass'] ?? '',
        'emisMale': r['emisMale'].text.trim(),
        'countMale': r['countMale'].text.trim(),
        'emisFemale': r['emisFemale'].text.trim(),
        'countFemale': r['countFemale'].text.trim(),
      }).toList(),
      'feeRecords': feeRecords.map((r) => {
        'fee': r['fee'],
        'pay': r['pay'],
        'purpose': r['purpose'].text.trim(),
        'amount': r['amount'].text.trim(),
      }).toList(),
      'queuedAt': DateTime.now().toIso8601String(),
    };
  }

  // ─── Sync pending assessments ───────────────────────────────────────────────
  Future<void> _syncPendingAssessments(BuildContext context) async {
    final pending = LocalStorageService.getPendingAssessments();
    if (pending.isEmpty) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isAuthenticated || authProvider.token == null) {
      debugPrint('Cannot sync pending: not authenticated');
      return;
    }

    final token = authProvider.token!;
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    };

    for (var assessment in pending) {
      try {
        final school = assessment['schoolCode'] ?? assessment['schoolName'] ?? 'unknown';

        // Absent
        for (var r in assessment['absentRecords'] ?? []) {
          final res = await http.post(
            Uri.parse('${AppUrl.url}/schools/absents'),
            headers: headers,
            body: jsonEncode({
              ...r,
              'school': school,
            }),
          );
          if (res.statusCode != 201) {
            debugPrint('Pending absent sync failed: ${res.body}');
            continue;
          }
        }

        // Staff
        for (var r in assessment['staffRecords'] ?? []) {
          final res = await http.post(
            Uri.parse('${AppUrl.url}/schools/staff'),
            headers: headers,
            body: jsonEncode({
              ...r,
              'school': school,
            }),
          );
          if (res.statusCode != 201) {
            debugPrint('Pending staff sync failed: ${res.body}');
            continue;
          }
        }

        // Required Teachers - with debug logging
        final req = assessment['reqTeachers'] ?? {};
        if (req['level']?.toString().trim().isNotEmpty ?? false) {
          print('Syncing pending req-teachers with level: ${req['level']}');
          final res = await http.post(
            Uri.parse('${AppUrl.url}/schools/req-teachers'),
            headers: headers,
            body: jsonEncode({
              ...req,
              'school': school,
            }),
          );
          print('Pending req-teachers response: ${res.statusCode} - ${res.body}');
          if (res.statusCode != 201) {
            debugPrint('Pending req-teachers sync failed: ${res.body}');
          }
        } else {
          print('Skipping pending req-teachers: level is empty');
        }

        // Verify Students - legacy single object
        final verify = assessment['verifyStudents'] ?? {};
        if (verify['class']?.toString().trim().isNotEmpty ?? false) {
          final res = await http.post(
            Uri.parse('${AppUrl.url}/schools/verify-students'),
            headers: headers,
            body: jsonEncode({
              ...verify,
              'school': school,
            }),
          );
          if (res.statusCode != 201) {
            debugPrint('Pending verify-students sync failed: ${res.body}');
          }
        }

        // Verify Students - dynamic rows
        for (var r in assessment['verifyStudentRecords'] ?? []) {
          final res = await http.post(
            Uri.parse('${AppUrl.url}/schools/verify-students'),
            headers: headers,
            body: jsonEncode({
              ...r,
              'school': school,
            }),
          );
          if (res.statusCode != 201) {
            debugPrint('Pending verify-student row sync failed: ${res.body}');
          }
        }

        // Fees
        for (var r in assessment['feeRecords'] ?? []) {
          final res = await http.post(
            Uri.parse('${AppUrl.url}/schools/fees-paid'),
            headers: headers,
            body: jsonEncode({
              ...r,
              'school': school,
            }),
          );
          if (res.statusCode != 201) {
            debugPrint('Pending fee sync failed: ${res.body}');
            continue;
          }
        }

        await LocalStorageService.removePendingAssessment(assessment);
        debugPrint('Pending assessment synced and removed');
      } catch (e, stack) {
        debugPrint('Full pending assessment sync error: $e');
        debugPrint('Stack: $stack');
        // Keep failed items for next retry
      }
    }
  }

  void reset() {
    absentRecords.clear();
    staffRecords.clear();
    feeRecords.clear();
    verifyStudentRecords.clear();
    reqLevel = '';
    reqSelfContain = 'No';
    reqAssTeacher = '';
    reqVolunteers = '';
    reqStudents = '';
    reqNumRequired = '';
    verifyClass = '';
    emisMale = '';
    countMale = '';
    emisFemale = '';
    countFemale = '';
    gradesForLevel.clear();
    notifyListeners();
  }
}