import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../../../core/constants/app_url.dart';
import '../../../../core/services/local_storage_service.dart';
import '../../../../core/services/data_preloader_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class AssessmentProvider with ChangeNotifier {
  String schoolName = '';
  String schoolCode = '';
  String level = 'ECE';

  // Dynamic lists
  List<Map<String, dynamic>> staffRecords = []; // Now includes excuse, reason, and status
  List<Map<String, dynamic>> feeRecords = [];
  List<Map<String, dynamic>> verifyStudentRecords = [];

  // Required Teachers
  String reqLevel = '';
  String reqSelfContain = 'No';
  String reqAssTeacher = '';
  String reqVolunteers = '';
  String reqStudents = '';
  String reqNumRequired = '';

  // Legacy verify students
  String verifyClass = '';
  String emisMale = '';
  String countMale = '';
  String emisFemale = '';
  String countFemale = '';

  // Verification fields
  String teachersPresent = 'Yes';
  String verifyComment = '';

  // Grades from DataPreloaderService
  List<Map<String, dynamic>> gradesForLevel = [];
  bool isLoadingGrades = false;
  String? gradesError;

  // Positions from DataPreloaderService
  List<Map<String, dynamic>> _positions = [];
  bool _isLoadingPositions = false;

  List<Map<String, dynamic>> get positions => _positions;
  bool get isLoadingPositions => _isLoadingPositions;

  // Fees from DataPreloaderService
  List<Map<String, dynamic>> _availableFees = [];
  bool _isLoadingFees = false;

  List<Map<String, dynamic>> get availableFees => _availableFees;
  bool get isLoadingFees => _isLoadingFees;

  // Maps for tabular data
  final Map<String, Map<String, dynamic>> _verifyStudentRecordsByGrade = {};
  final Map<String, Map<String, dynamic>> _feeRecordsByType = {};

  bool isSubmitting = false;
  String? lastError;
  bool lastOffline = false;

  int get pendingCount => LocalStorageService.getPendingAssessments().length;

  // Helper method to check success status codes
  bool _isSuccessStatusCode(int statusCode) {
    return statusCode == 200 || statusCode == 201;
  }

  // ─── Add / Remove / Update Methods ──────────────────────────────────────────
  void addStaff() {
    staffRecords.add({
      'fname': TextEditingController(),
      'gender': 'Male',
      'status': 'Employed', // Added status field with default value
      'position': TextEditingController(),
      'week_load': TextEditingController(),
      'present': 'Yes',
      'excuse': 'Yes', // Added excuse field
      'reason': TextEditingController(), // Added reason field
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

  // ─── Load from DataPreloaderService ─────────────────────────────────────

  void loadGradesFromCache(String schoolLevel) {
    gradesForLevel = DataPreloaderService.getGradesForLevel(schoolLevel);
    notifyListeners();
  }

  void loadPositionsFromCache() {
    _positions = DataPreloaderService.getCachedData('positions');
    notifyListeners();
  }

  void loadFeesFromCache() {
    _availableFees = DataPreloaderService.getCachedData('fees');
    _initializeFeeRecords();
    notifyListeners();
  }

  // ─── Fetch methods (background refresh) ────────────────────────────────

  Future<void> fetchGradesForLevel(String schoolLevel, BuildContext context) async {
    debugPrint('🔄 Fetching grades for level: $schoolLevel');

    final hadCachedData = gradesForLevel.isNotEmpty;
    if (!hadCachedData) {
      isLoadingGrades = true;
      notifyListeners();
    }

    final isOnline = await LocalStorageService.isOnline();
    if (!isOnline) {
      isLoadingGrades = false;
      notifyListeners();
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isAuthenticated || authProvider.token == null) {
      isLoadingGrades = false;
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
      final uri = Uri.parse('${AppUrl.url}/grades?level=$schoolLevel');
      final res = await http.get(uri, headers: headers);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final loaded = _extractListFromResponse(data);

        gradesForLevel = loaded;
        debugPrint('✅ Loaded ${gradesForLevel.length} grades from API');

        // Update cache
        await LocalStorageService.saveToCache('grades_${schoolLevel.toLowerCase()}', loaded);
      }
    } catch (e) {
      debugPrint('❌ Fetch grades error: $e');
    } finally {
      isLoadingGrades = false;
      notifyListeners();
    }
  }

  Future<void> fetchPositions(BuildContext context) async {
    debugPrint('🔄 Fetching positions');

    final hadCachedData = _positions.isNotEmpty;
    if (!hadCachedData) {
      _isLoadingPositions = true;
      notifyListeners();
    }

    final isOnline = await LocalStorageService.isOnline();
    if (!isOnline) {
      _isLoadingPositions = false;
      notifyListeners();
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isAuthenticated || authProvider.token == null) {
      _isLoadingPositions = false;
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
      final response = await http.get(
        Uri.parse('${AppUrl.url}/positions'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _positions = _extractListFromResponse(data);
        debugPrint('✅ Loaded ${_positions.length} positions from API');
        await LocalStorageService.saveToCache('positions', _positions);
      }
    } catch (e) {
      debugPrint('❌ Fetch positions error: $e');
    } finally {
      _isLoadingPositions = false;
      notifyListeners();
    }
  }

  Future<void> fetchFees(BuildContext context) async {
    debugPrint('🔄 Fetching fees');

    final hadCachedData = _availableFees.isNotEmpty;
    if (!hadCachedData) {
      _isLoadingFees = true;
      notifyListeners();
    }

    final isOnline = await LocalStorageService.isOnline();
    if (!isOnline) {
      _isLoadingFees = false;
      notifyListeners();
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isAuthenticated || authProvider.token == null) {
      _isLoadingFees = false;
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
      final response = await http.get(
        Uri.parse('${AppUrl.url}/fees'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _availableFees = _extractListFromResponse(data);
        debugPrint('✅ Loaded ${_availableFees.length} fees from API');
        _initializeFeeRecords();
        await LocalStorageService.saveToCache('fees', _availableFees);
      }
    } catch (e) {
      debugPrint('❌ Fetch fees error: $e');
    } finally {
      _isLoadingFees = false;
      notifyListeners();
    }
  }

  List<Map<String, dynamic>> _extractListFromResponse(dynamic data) {
    if (data is List) {
      return List<Map<String, dynamic>>.from(data);
    } else if (data is Map && data.containsKey('data')) {
      if (data['data'] is List) {
        return List<Map<String, dynamic>>.from(data['data']);
      }
    }
    return [];
  }

  // ─── Verify Students Tabular Methods ──────────────────────────────────────

  void ensureVerifyStudentRecord(String gradeName) {
    if (!_verifyStudentRecordsByGrade.containsKey(gradeName)) {
      _verifyStudentRecordsByGrade[gradeName] = {
        'classGrade': gradeName,
        'emisMale': TextEditingController(),
        'countMale': TextEditingController(),
        'emisFemale': TextEditingController(),
        'countFemale': TextEditingController(),
      };
    }
  }

  Map<String, dynamic> getVerifyStudentRecord(String gradeName) {
    return _verifyStudentRecordsByGrade[gradeName]!;
  }

  List<Map<String, dynamic>> getAllVerifyStudentRecords() {
    return _verifyStudentRecordsByGrade.values.toList();
  }

  // ─── Fees Tabular Methods ─────────────────────────────────────────────────

  void _initializeFeeRecords() {
    _feeRecordsByType.clear();
    for (var fee in _availableFees) {
      final feeName = fee['name']?.toString() ?? fee['fee']?.toString() ?? 'Unknown';
      _feeRecordsByType[feeName] = {
        'fee': feeName,
        'pay': 'Yes',
        'purpose': TextEditingController(),
        'amount': TextEditingController(),
      };
    }
    notifyListeners();
  }

  List<Map<String, dynamic>> getAllFeeRecords() {
    return _feeRecordsByType.values.toList();
  }

  Map<String, dynamic>? getFeeRecord(String feeName) {
    return _feeRecordsByType[feeName];
  }

  void updateFeeRecord(String feeName, String key, dynamic value) {
    if (_feeRecordsByType.containsKey(feeName)) {
      if (key == 'pay') {
        _feeRecordsByType[feeName]![key] = value;
      } else {
        final controller = _feeRecordsByType[feeName]![key] as TextEditingController;
        controller.text = value;
      }
      notifyListeners();
    }
  }

  // ─── Submission methods ───────────────────────────────────────────────

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
        // Track if any submission fails
        bool hasFailure = false;

        // 1. Submit Staff Records (now includes excuse, reason, and status)
        for (var r in staffRecords) {
          try {
            // Only include excuse and reason if present is 'No'
            final payload = {
              'school': schoolCode.trim(),
              'fname': r['fname'].text.trim(),
              'gender': r['gender'],
              'status': r['status'], // Added status field
              'position': r['position'].text.trim(),
              'week_load': int.tryParse(r['week_load'].text.trim() ?? '0') ?? 0,
              'present': r['present'],
              'bio_id': r['bio_id'].text.trim(),
              'pay_id': r['pay_id'].text.trim(),
              'qualification': r['qualification'].text.trim(),
            };

            // Add excuse and reason only if present is 'No'
            if (r['present'] == 'No') {
              payload['excuse'] = r['excuse'] ?? 'Yes';
              payload['reason'] = r['reason']?.text.trim() ?? '';
            }

            debugPrint('Staff submission payload: ${jsonEncode(payload)}');

            final res = await http.post(
              Uri.parse('${AppUrl.url}/schools/staff'),
              headers: headers,
              body: jsonEncode(payload),
            );
            debugPrint('Staff submission: ${res.statusCode}');
            if (!_isSuccessStatusCode(res.statusCode)) {
              debugPrint('Staff failed: ${res.statusCode} - ${res.body}');
              hasFailure = true;
            }
          } catch (e, stack) {
            debugPrint('Staff submission error: $e');
            debugPrint('Stack: $stack');
            hasFailure = true;
          }
        }

        // 2. Submit Required Teachers
        // if (reqLevel.trim().isNotEmpty) {
        //   try {
        //     final payload = {
        //       'school': schoolCode.trim(),
        //       'level': reqLevel.trim(),
        //       'self_contain': reqSelfContain,
        //       'ass_teacher': int.tryParse(reqAssTeacher.trim() ?? '0') ?? 0,
        //       'volunteers': int.tryParse(reqVolunteers.trim() ?? '0') ?? 0,
        //       'students': int.tryParse(reqStudents.trim() ?? '0') ?? 0,
        //       'num_req': int.tryParse(reqNumRequired.trim() ?? '0') ?? 0,
        //     };
        //
        //     debugPrint('Attempting req-teachers POST with payload: ${jsonEncode(payload)}');
        //
        //     final res = await http.post(
        //       Uri.parse('${AppUrl.url}/schools/req-teachers'),
        //       headers: headers,
        //       body: jsonEncode(payload),
        //     );
        //
        //     debugPrint('Req Teachers response: ${res.statusCode} - ${res.body}');
        //
        //     if (!_isSuccessStatusCode(res.statusCode)) {
        //       debugPrint('Req Teachers failed: ${res.statusCode} - ${res.body}');
        //       hasFailure = true;
        //     }
        //   } catch (e, stack) {
        //     debugPrint('Req Teachers submission error: $e');
        //     debugPrint('Stack: $stack');
        //     hasFailure = true;
        //   }
        // } else {
        //   debugPrint('Skipping req-teachers submission: reqLevel is empty');
        // }

        // 3. Submit Verify Students - Using tabular records
        for (var record in _verifyStudentRecordsByGrade.values) {
          try {
            final gradeName = record['classGrade']?.toString() ?? '';
            if (gradeName.isEmpty) continue;

            final payload = {
              'school': schoolCode.trim(),
              'classes': gradeName,
              'emis_male': int.tryParse(record['emisMale'].text.trim() ?? '0') ?? 0,
              'count_male': int.tryParse(record['countMale'].text.trim() ?? '0') ?? 0,
              'emis_female': int.tryParse(record['emisFemale'].text.trim() ?? '0') ?? 0,
              'count_female': int.tryParse(record['countFemale'].text.trim() ?? '0') ?? 0,
            };

            debugPrint('Sending verify row for $gradeName: ${jsonEncode(payload)}');

            final res = await http.post(
              Uri.parse('${AppUrl.url}/schools/verify-students'),
              headers: headers,
              body: jsonEncode(payload),
            );

            debugPrint('Verify row response: ${res.statusCode} - ${res.body}');

            if (!_isSuccessStatusCode(res.statusCode)) {
              debugPrint('Verify row failed: ${res.statusCode} - ${res.body}');
              hasFailure = true;
            }
          } catch (e, stack) {
            debugPrint('Verify submission error: $e');
            debugPrint('Stack: $stack');
            hasFailure = true;
          }
        }

        // 4. Submit Fees - Using tabular fee records
        // for (var record in _feeRecordsByType.values) {
        //   try {
        //     final amount = double.tryParse(record['amount'].text.trim() ?? '0') ?? 0.0;
        //     final payload = {
        //       'school': schoolCode.trim(),
        //       'fee': record['fee'],
        //       'pay': record['pay'],
        //       'purpose': record['purpose'].text.trim(),
        //       'amount': amount,
        //     };
        //
        //     debugPrint('Sending fee record: ${jsonEncode(payload)}');
        //
        //     final res = await http.post(
        //       Uri.parse('${AppUrl.url}/schools/fees-paid'),
        //       headers: headers,
        //       body: jsonEncode(payload),
        //     );
        //
        //     debugPrint('Fee submission response: ${res.statusCode}');
        //
        //     if (!_isSuccessStatusCode(res.statusCode)) {
        //       debugPrint('Fee failed: ${res.statusCode} - ${res.body}');
        //       hasFailure = true;
        //     }
        //   } catch (e, stack) {
        //     debugPrint('Fee submission error: $e');
        //     debugPrint('Stack: $stack');
        //     hasFailure = true;
        //   }
        // }

        // 5. Submit Verification Data
        try {
          final payload = {
            'school': schoolCode.trim(),
            'teachers_present': teachersPresent,
            'verify_comment': verifyComment.trim(),
          };

          debugPrint('Sending verification data: ${jsonEncode(payload)}');

          final res = await http.post(
            Uri.parse('${AppUrl.url}/schools/verification'),
            headers: headers,
            body: jsonEncode(payload),
          );

          debugPrint('Verification submission response: ${res.statusCode}');

          if (!_isSuccessStatusCode(res.statusCode)) {
            debugPrint('Verification failed: ${res.statusCode} - ${res.body}');
            hasFailure = true;
          }
        } catch (e, stack) {
          debugPrint('Verification submission error: $e');
          debugPrint('Stack: $stack');
          hasFailure = true;
        }

        // If any failures occurred, save to pending for retry
        if (hasFailure) {
          final payload = _buildAssessmentPayload();
          await LocalStorageService.savePendingAssessment(payload);
          lastOffline = true;
          return true;
        }

        // All good - sync any pending from previous sessions
        await _syncPendingAssessments(context);
        lastOffline = false;
        return true;
      } else {
        // Offline: Save to pending queue
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
      'staffRecords': staffRecords.map((r) => {
        'fname': r['fname'].text.trim(),
        'gender': r['gender'],
        'status': r['status'], // Added status field
        'position': r['position'].text.trim(),
        'week_load': r['week_load'].text.trim(),
        'present': r['present'],
        'excuse': r['present'] == 'No' ? r['excuse'] : null,
        'reason': r['present'] == 'No' ? r['reason']?.text.trim() : null,
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
      // New tabular verify students records
      'verifyStudentRecords': _verifyStudentRecordsByGrade.values.map((r) => {
        'classGrade': r['classGrade'],
        'emisMale': r['emisMale'].text.trim(),
        'countMale': r['countMale'].text.trim(),
        'emisFemale': r['emisFemale'].text.trim(),
        'countFemale': r['countFemale'].text.trim(),
      }).toList(),
      // New tabular fee records
      'feeRecords': _feeRecordsByType.values.map((r) => {
        'fee': r['fee'],
        'pay': r['pay'],
        'purpose': r['purpose'].text.trim(),
        'amount': r['amount'].text.trim(),
      }).toList(),
      // Verification data
      'verification': {
        'teachers_present': teachersPresent,
        'verify_comment': verifyComment.trim(),
      },
      'queuedAt': DateTime.now().toIso8601String(),
    };
  }

  // ─── Sync pending assessments with better error handling ─────────
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

    List<Map<String, dynamic>> failedSyncs = [];

    for (var assessment in pending) {
      try {
        final school = assessment['schoolCode'] ?? assessment['schoolName'] ?? 'unknown';
        bool hasFailure = false;

        debugPrint('Syncing assessment for school: $school (queued: ${assessment['queuedAt']})');

        // Staff (now includes excuse, reason, and status)
        for (var r in assessment['staffRecords'] ?? []) {
          try {
            final payload = {
              'school': school,
              'fname': r['fname'],
              'gender': r['gender'],
              'status': r['status'], // Added status field
              'position': r['position'],
              'week_load': int.tryParse(r['week_load']?.toString() ?? '0') ?? 0,
              'present': r['present'],
              'bio_id': r['bio_id'],
              'pay_id': r['pay_id'],
              'qualification': r['qualification'],
            };

            // Add excuse and reason if present is 'No'
            if (r['present'] == 'No') {
              payload['excuse'] = r['excuse'] ?? 'Yes';
              payload['reason'] = r['reason'] ?? '';
            }

            final res = await http.post(
              Uri.parse('${AppUrl.url}/schools/staff'),
              headers: headers,
              body: jsonEncode(payload),
            );

            if (_isSuccessStatusCode(res.statusCode)) {
              debugPrint('Staff sync: ${res.statusCode}');
            } else {
              debugPrint('Pending staff sync failed: ${res.statusCode} - ${res.body}');
              hasFailure = true;
            }
          } catch (e) {
            debugPrint('Pending staff sync error: $e');
            hasFailure = true;
          }
        }

        // Required Teachers
        final req = assessment['reqTeachers'] ?? {};
        if (req['level']?.toString().trim().isNotEmpty ?? false) {
          try {
            debugPrint('Syncing pending req-teachers with level: ${req['level']}');
            final res = await http.post(
              Uri.parse('${AppUrl.url}/schools/req-teachers'),
              headers: headers,
              body: jsonEncode({
                ...req,
                'school': school,
              }),
            );
            debugPrint('Pending req-teachers response: ${res.statusCode} - ${res.body}');
            if (_isSuccessStatusCode(res.statusCode)) {
              debugPrint('Req-teachers sync: ${res.statusCode}');
            } else {
              debugPrint('Pending req-teachers sync failed: ${res.body}');
              hasFailure = true;
            }
          } catch (e) {
            debugPrint('Pending req-teachers sync error: $e');
            hasFailure = true;
          }
        }

        // Verify Students - dynamic rows
        for (var r in assessment['verifyStudentRecords'] ?? []) {
          try {
            final res = await http.post(
              Uri.parse('${AppUrl.url}/schools/verify-students'),
              headers: headers,
              body: jsonEncode({
                ...r,
                'school': school,
              }),
            );

            if (_isSuccessStatusCode(res.statusCode)) {
              debugPrint('Verify-student row sync for ${r['classGrade']}: ${res.statusCode}');
            } else {
              debugPrint('Pending verify-student row sync failed: ${res.body}');
              hasFailure = true;
            }
          } catch (e) {
            debugPrint('Pending verify-student row sync error: $e');
            hasFailure = true;
          }
        }

        // Fees - FIXED: Properly handle 200 status code as success
        for (var r in assessment['feeRecords'] ?? []) {
          try {
            final res = await http.post(
              Uri.parse('${AppUrl.url}/schools/fees-paid'),
              headers: headers,
              body: jsonEncode({
                ...r,
                'school': school,
              }),
            );

            // Check if status code indicates success (200 or 201)
            if (_isSuccessStatusCode(res.statusCode)) {
              debugPrint('Fees sync: ${res.statusCode}');
              // Success - continue to next fee record
            } else {
              debugPrint('Pending fee sync failed: ${res.statusCode} - ${res.body}');
              hasFailure = true;
            }
          } catch (e) {
            debugPrint('Pending fee sync error: $e');
            hasFailure = true;
          }
        }

        // Sync Verification data
        final verification = assessment['verification'];
        if (verification != null) {
          try {
            final res = await http.post(
              Uri.parse('${AppUrl.url}/schools/verification'),
              headers: headers,
              body: jsonEncode({
                ...verification,
                'school': school,
              }),
            );

            if (_isSuccessStatusCode(res.statusCode)) {
              debugPrint('Verification sync: ${res.statusCode}');
            } else {
              debugPrint('Pending verification sync failed: ${res.body}');
              hasFailure = true;
            }
          } catch (e) {
            debugPrint('Pending verification sync error: $e');
            hasFailure = true;
          }
        }

        if (!hasFailure) {
          await LocalStorageService.removePendingAssessment(assessment);
          debugPrint('✅ Pending assessment synced and removed successfully');
        } else {
          debugPrint('❌ Assessment sync had failures, keeping in pending queue');
          failedSyncs.add(assessment);
        }
      } catch (e, stack) {
        debugPrint('❌ Full pending assessment sync error: $e');
        debugPrint('Stack: $stack');
        failedSyncs.add(assessment);
      }
    }

    // Update pending queue with failed items only
    if (failedSyncs.isNotEmpty) {
      await LocalStorageService.saveFailedSyncs(failedSyncs);
    }
  }

  // ─── Manual retry for failed syncs ────────────────────────────────────────
  Future<void> retryFailedSyncs(BuildContext context) async {
    final isOnline = await LocalStorageService.isOnline();
    if (!isOnline) return;

    await _syncPendingAssessments(context);
  }

  // ─── Get pending count ────────────────────────────────────────────────────
  int getPendingCount() {
    return LocalStorageService.getPendingAssessments().length;
  }

  // ─── Reset all data ───────────────────────────────────────────────────────
  void reset() {
    staffRecords.clear();
    feeRecords.clear();
    verifyStudentRecords.clear();
    _verifyStudentRecordsByGrade.clear();
    _feeRecordsByType.clear();
    _positions.clear();
    _availableFees.clear();
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
    teachersPresent = 'Yes';
    verifyComment = '';
    gradesForLevel.clear();
    isLoadingGrades = false;
    _isLoadingPositions = false;
    _isLoadingFees = false;
    gradesError = null;
    notifyListeners();
  }
}