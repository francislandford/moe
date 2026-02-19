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
  bool isLoadingGrades = false; // For background refresh indicator
  String? gradesError; // For logging only, not shown to users

  // Positions for Staff dropdown
  List<Map<String, dynamic>> _positions = [];
  bool _isLoadingPositions = false;

  List<Map<String, dynamic>> get positions => _positions;
  bool get isLoadingPositions => _isLoadingPositions;

  // Fees from API
  List<Map<String, dynamic>> _availableFees = [];
  bool _isLoadingFees = false;

  List<Map<String, dynamic>> get availableFees => _availableFees;
  bool get isLoadingFees => _isLoadingFees;

  // Map to store verify student records by grade name (for tabular format)
  final Map<String, Map<String, dynamic>> _verifyStudentRecordsByGrade = {};

  // Map to store fee records by fee name (for tabular format)
  final Map<String, Map<String, dynamic>> _feeRecordsByType = {};

  bool isSubmitting = false;
  String? lastError;
  bool lastOffline = false;

  // Pending count getter
  int get pendingCount => LocalStorageService.getPendingAssessments().length;

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

  // ─── Positions Methods ────────────────────────────────────────────────────

  // Load positions from cache
  void loadPositionsFromCache() {
    try {
      final cachedPositions = LocalStorageService.getFromCache('positions');

      if (cachedPositions != null && cachedPositions is List) {
        _positions = cachedPositions.map((position) {
          if (position is Map) {
            return Map<String, dynamic>.from(position);
          }
          return <String, dynamic>{};
        }).toList();
        debugPrint('✅ Loaded ${_positions.length} positions from cache');
      } else {
        debugPrint('ℹ️ No cached positions found');
        _positions = [];
      }
    } catch (e) {
      debugPrint('❌ Error loading positions from cache: $e');
      _positions = [];
    }
    notifyListeners();
  }

  // Cache positions for offline use
  Future<void> _cachePositions(List<Map<String, dynamic>> positions) async {
    try {
      await LocalStorageService.saveToCache('positions', positions);
      debugPrint('✅ Cached ${positions.length} positions');
    } catch (e) {
      debugPrint('❌ Error caching positions: $e');
    }
  }

  // Fetch positions from API
  Future<void> fetchPositions(BuildContext context) async {
    debugPrint('🔄 Fetching positions');

    final hadCachedData = _positions.isNotEmpty;
    if (!hadCachedData) {
      _isLoadingPositions = true;
      notifyListeners();
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isAuthenticated || authProvider.token == null) {
      debugPrint('❌ Cannot fetch positions: User not authenticated');
      _isLoadingPositions = false;
      notifyListeners();
      return;
    }

    final isOnline = await LocalStorageService.isOnline();

    if (!isOnline) {
      debugPrint('📱 Offline: using cached positions. Count: ${_positions.length}');
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
      // Adjust endpoint as needed - this might be different in your API
      final response = await http.get(
        Uri.parse('${AppUrl.url}/positions'),
        headers: headers,
      );

      debugPrint('📥 Positions response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<Map<String, dynamic>> loaded = [];

        if (data is List) {
          loaded = List<Map<String, dynamic>>.from(data);
        } else if (data is Map && data.containsKey('data')) {
          loaded = List<Map<String, dynamic>>.from(data['data']);
        }

        _positions = loaded;
        debugPrint('✅ Loaded ${_positions.length} positions from API');

        // Cache for offline use
        await _cachePositions(_positions);
      } else {
        debugPrint('❌ Failed to load positions - status ${response.statusCode}');
      }
    } catch (e, stack) {
      debugPrint('❌ Fetch positions error: $e');
      debugPrint('Stack trace: $stack');
    } finally {
      _isLoadingPositions = false;
      notifyListeners();
    }
  }

  // ─── Fees Methods ────────────────────────────────────────────────────────

  // Load fees from cache
  void loadFeesFromCache() {
    try {
      final cachedFees = LocalStorageService.getFromCache('fees');

      if (cachedFees != null && cachedFees is List) {
        _availableFees = cachedFees.map((fee) {
          if (fee is Map) {
            return Map<String, dynamic>.from(fee);
          }
          return <String, dynamic>{};
        }).toList();
        debugPrint('✅ Loaded ${_availableFees.length} fees from cache');

        // Initialize fee records for each fee type
        _initializeFeeRecords();
      } else {
        debugPrint('ℹ️ No cached fees found');
        _availableFees = [];
      }
    } catch (e) {
      debugPrint('❌ Error loading fees from cache: $e');
      _availableFees = [];
    }
    notifyListeners();
  }

  // Cache fees for offline use
  Future<void> _cacheFees(List<Map<String, dynamic>> fees) async {
    try {
      await LocalStorageService.saveToCache('fees', fees);
      debugPrint('✅ Cached ${fees.length} fees');
    } catch (e) {
      debugPrint('❌ Error caching fees: $e');
    }
  }

  // Initialize fee records for each fee type
  void _initializeFeeRecords() {
    _feeRecordsByType.clear();
    for (var fee in _availableFees) {
      final feeName = fee['fee']?.toString() ?? fee['fee']?.toString() ?? 'Unknown';
      _feeRecordsByType[feeName] = {
        'fee': feeName,
        'pay': 'Yes',
        'purpose': TextEditingController(),
        'amount': TextEditingController(),
      };
    }
    notifyListeners();
  }

  // Fetch fees from API
  Future<void> fetchFees(BuildContext context) async {
    debugPrint('🔄 Fetching fees');

    final hadCachedData = _availableFees.isNotEmpty;
    if (!hadCachedData) {
      _isLoadingFees = true;
      notifyListeners();
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isAuthenticated || authProvider.token == null) {
      debugPrint('❌ Cannot fetch fees: User not authenticated');
      _isLoadingFees = false;
      notifyListeners();
      return;
    }

    final isOnline = await LocalStorageService.isOnline();

    if (!isOnline) {
      debugPrint('📱 Offline: using cached fees. Count: ${_availableFees.length}');
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
      // Adjust endpoint as needed
      final response = await http.get(
        Uri.parse('${AppUrl.url}/fees'), // Update endpoint as needed
        headers: headers,
      );

      debugPrint('📥 Fees response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<Map<String, dynamic>> loaded = [];

        if (data is List) {
          loaded = List<Map<String, dynamic>>.from(data);
        } else if (data is Map && data.containsKey('data')) {
          loaded = List<Map<String, dynamic>>.from(data['data']);
        }

        _availableFees = loaded;
        debugPrint('✅ Loaded ${_availableFees.length} fees from API');

        // Initialize fee records for each fee type
        _initializeFeeRecords();

        // Cache for offline use
        await _cacheFees(_availableFees);
      } else {
        debugPrint('❌ Failed to load fees - status ${response.statusCode}');
      }
    } catch (e, stack) {
      debugPrint('❌ Fetch fees error: $e');
      debugPrint('Stack trace: $stack');
    } finally {
      _isLoadingFees = false;
      notifyListeners();
    }
  }

  // ─── Verify Students Tabular Methods ──────────────────────────────────────

  // Ensure record exists for a grade
  void ensureVerifyStudentRecord(String gradeName) {
    if (!_verifyStudentRecordsByGrade.containsKey(gradeName)) {
      _verifyStudentRecordsByGrade[gradeName] = {
        'classGrade': gradeName,
        'emisMale': TextEditingController(),
        'countMale': TextEditingController(),
        'emisFemale': TextEditingController(),
        'countFemale': TextEditingController(),
      };
      notifyListeners();
    }
  }

  // Get record for a grade
  Map<String, dynamic> getVerifyStudentRecord(String gradeName) {
    return _verifyStudentRecordsByGrade[gradeName]!;
  }

  // Get all verify student records as list (for submission)
  List<Map<String, dynamic>> getAllVerifyStudentRecords() {
    return _verifyStudentRecordsByGrade.values.toList();
  }

  // Update verify student record field
  void updateVerifyStudentRecord(String gradeName, String field, String value) {
    if (_verifyStudentRecordsByGrade.containsKey(gradeName)) {
      final controller = _verifyStudentRecordsByGrade[gradeName]![field] as TextEditingController;
      controller.text = value;
      notifyListeners();
    }
  }

  // ─── Fees Tabular Methods ─────────────────────────────────────────────────

  // Get all fee records as list (for UI and submission)
  List<Map<String, dynamic>> getAllFeeRecords() {
    return _feeRecordsByType.values.toList();
  }

  // Get fee record by fee name
  Map<String, dynamic>? getFeeRecord(String feeName) {
    return _feeRecordsByType[feeName];
  }

  // Update fee record
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

  // ─── Load grades from cache (offline-first) ───────────────────────────
  void loadGradesFromCache(String schoolLevel) {
    try {
      // Try to get grades from cache using the specific key
      final cachedGrades = LocalStorageService.getFromCache('grades_${schoolLevel.toLowerCase()}');

      if (cachedGrades != null && cachedGrades is List) {
        gradesForLevel = cachedGrades.map((grade) {
          if (grade is Map) {
            return Map<String, dynamic>.from(grade);
          }
          return <String, dynamic>{};
        }).toList();
        debugPrint('✅ Loaded ${gradesForLevel.length} grades from cache for level: $schoolLevel');
      } else {
        debugPrint('ℹ️ No cached grades found for level: $schoolLevel');
        gradesForLevel = [];
      }
    } catch (e) {
      debugPrint('❌ Error loading grades from cache: $e');
      gradesForLevel = [];
    }
    notifyListeners();
  }

  // ─── Cache grades for offline use ─────────────────────────────────────
  Future<void> _cacheGrades(String schoolLevel, List<Map<String, dynamic>> grades) async {
    try {
      final cacheKey = 'grades_${schoolLevel.toLowerCase()}';
      await LocalStorageService.saveToCache(cacheKey, grades);
      debugPrint('✅ Cached ${grades.length} grades for level: $schoolLevel');
    } catch (e) {
      debugPrint('❌ Error caching grades: $e');
    }
  }

  // ─── Fetch grades for Verify Students dropdown (offline-first) ───
  Future<void> fetchGradesForLevel(String schoolLevel, BuildContext context) async {
    debugPrint('🔄 Fetching grades for level: $schoolLevel');

    // Don't show loading if we already have cached data
    final hadCachedData = gradesForLevel.isNotEmpty;

    // Only show loading if we have no cached data
    if (!hadCachedData) {
      isLoadingGrades = true;
      notifyListeners();
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isAuthenticated || authProvider.token == null) {
      debugPrint('❌ Cannot fetch grades: User is not authenticated');
      gradesError = 'Authentication required to fetch grades';
      isLoadingGrades = false;
      notifyListeners();
      return;
    }

    final isOnline = await LocalStorageService.isOnline();

    // If offline, just use cache (already loaded) and ensure we have data
    if (!isOnline) {
      debugPrint('📱 Offline: using cached grades. Count: ${gradesForLevel.length}');
      isLoadingGrades = false;

      // If we have no cached grades, show a user-friendly message
      if (gradesForLevel.isEmpty) {
        debugPrint('⚠️ No cached grades available offline');
      }

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
      debugPrint('🌐 Requesting: $uri');
      final res = await http.get(uri, headers: headers);

      debugPrint('📥 Grades response status: ${res.statusCode}');

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        List<Map<String, dynamic>> loaded = [];

        if (data is List) {
          loaded = List<Map<String, dynamic>>.from(data);
        } else if (data is Map && data.containsKey('data')) {
          loaded = List<Map<String, dynamic>>.from(data['data']);
        }

        // Deduplicate by 'id' or 'name' (use whichever is available)
        final seen = <String>{};
        gradesForLevel = loaded.where((grade) {
          // Try to use id first, fall back to name
          final id = grade['id']?.toString() ?? grade['name']?.toString();
          if (id == null || id.isEmpty) return false;
          if (seen.contains(id)) return false;
          seen.add(id);
          return true;
        }).toList();

        debugPrint('✅ Loaded ${gradesForLevel.length} unique grades from API');

        // Cache for offline use
        await _cacheGrades(schoolLevel, gradesForLevel);
        gradesError = null;
      } else {
        debugPrint('❌ Failed to load grades - status ${res.statusCode}');
        gradesError = 'API error: ${res.statusCode}';
        // Keep using cached data if available
        if (gradesForLevel.isEmpty) {
          debugPrint('⚠️ No cached grades available either');
        }
      }
    } catch (e, stack) {
      debugPrint('❌ Fetch grades error: $e');
      debugPrint('Stack trace: $stack');
      gradesError = 'Network error: $e';
      // Keep using cached data
      if (gradesForLevel.isEmpty) {
        debugPrint('⚠️ No cached grades available after network error');
      }
    } finally {
      isLoadingGrades = false;
      notifyListeners();
    }
  }

  // ─── Submission – Offline-first + Queue ──────────────────────────
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

        // 1. Submit Absent Teachers (optional - no validation)
        for (var r in absentRecords) {
          // Only submit if there's data
          if (r['fname'].text.trim().isNotEmpty) {
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
              debugPrint('Absent submission: ${res.statusCode}');
              if (res.statusCode != 201) {
                debugPrint('Absent failed: ${res.statusCode} - ${res.body}');
                hasFailure = true;
              }
            } catch (e, stack) {
              debugPrint('Absent submission error: $e');
              debugPrint('Stack: $stack');
              hasFailure = true;
            }
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
            debugPrint('Staff submission: ${res.statusCode}');
            if (res.statusCode != 201) {
              debugPrint('Staff failed: ${res.statusCode} - ${res.body}');
              hasFailure = true;
            }
          } catch (e, stack) {
            debugPrint('Staff submission error: $e');
            debugPrint('Stack: $stack');
            hasFailure = true;
          }
        }

        // 3. Submit Required Teachers
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

            debugPrint('Attempting req-teachers POST with payload: ${jsonEncode(payload)}');

            final res = await http.post(
              Uri.parse('${AppUrl.url}/schools/req-teachers'),
              headers: headers,
              body: jsonEncode(payload),
            );

            debugPrint('Req Teachers response: ${res.statusCode} - ${res.body}');

            if (res.statusCode != 201) {
              debugPrint('Req Teachers failed: ${res.statusCode} - ${res.body}');
              hasFailure = true;
            }
          } catch (e, stack) {
            debugPrint('Req Teachers submission error: $e');
            debugPrint('Stack: $stack');
            hasFailure = true;
          }
        } else {
          debugPrint('Skipping req-teachers submission: reqLevel is empty');
        }

        // 4. Submit Verify Students - Using tabular records
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

            if (res.statusCode != 201) {
              debugPrint('Verify row failed: ${res.statusCode} - ${res.body}');
              hasFailure = true;
            }
          } catch (e, stack) {
            debugPrint('Verify submission error: $e');
            debugPrint('Stack: $stack');
            hasFailure = true;
          }
        }

        // 5. Submit Fees - Using tabular fee records
        for (var record in _feeRecordsByType.values) {
          try {
            final amount = double.tryParse(record['amount'].text.trim() ?? '0') ?? 0.0;
            final payload = {
              'school': schoolCode.trim(),
              'fee': record['fee'],
              'pay': record['pay'],
              'purpose': record['purpose'].text.trim(),
              'amount': amount,
            };

            debugPrint('Sending fee record: ${jsonEncode(payload)}');

            final res = await http.post(
              Uri.parse('${AppUrl.url}/schools/fees-paid'),
              headers: headers,
              body: jsonEncode(payload),
            );

            debugPrint('Fee submission response: ${res.statusCode}');

            if (res.statusCode != 201) {
              debugPrint('Fee failed: ${res.statusCode} - ${res.body}');
              hasFailure = true;
            }
          } catch (e, stack) {
            debugPrint('Fee submission error: $e');
            debugPrint('Stack: $stack');
            hasFailure = true;
          }
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

        // Absent
        for (var r in assessment['absentRecords'] ?? []) {
          try {
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
              hasFailure = true;
            }
          } catch (e) {
            debugPrint('Pending absent sync error: $e');
            hasFailure = true;
          }
        }

        // Staff
        for (var r in assessment['staffRecords'] ?? []) {
          try {
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
            if (res.statusCode != 201) {
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
            if (res.statusCode != 201) {
              debugPrint('Pending verify-student row sync failed: ${res.body}');
              hasFailure = true;
            }
          } catch (e) {
            debugPrint('Pending verify-student row sync error: $e');
            hasFailure = true;
          }
        }

        // Fees
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
            if (res.statusCode != 201) {
              debugPrint('Pending fee sync failed: ${res.body}');
              hasFailure = true;
            }
          } catch (e) {
            debugPrint('Pending fee sync error: $e');
            hasFailure = true;
          }
        }

        if (!hasFailure) {
          await LocalStorageService.removePendingAssessment(assessment);
          debugPrint('Pending assessment synced and removed');
        } else {
          failedSyncs.add(assessment);
        }
      } catch (e, stack) {
        debugPrint('Full pending assessment sync error: $e');
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
    absentRecords.clear();
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
    gradesForLevel.clear();
    isLoadingGrades = false;
    _isLoadingPositions = false;
    _isLoadingFees = false;
    gradesError = null;
    notifyListeners();
  }
}