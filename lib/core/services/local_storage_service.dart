import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class LocalStorageService {
  // Public box names
  static const String dropdownBox = 'dropdowns';
  static const String pendingSchoolsBox = 'pending_schools';
  static const String pendingAssessmentsBox = 'pending_assessments';
  static const String pendingDocumentChecksBox = 'pending_document_checks';
  static const String pendingLeadershipBox = 'pending_leadership';
  static const String pendingInfrastructureBox = 'pending_infrastructure';
  static const String pendingClassroomObservationBox = 'pending_classroom_observation';
  // ─── Singleton + Stream for real-time connectivity ───────────────────────────
  static final LocalStorageService _instance = LocalStorageService._internal();
  factory LocalStorageService() => _instance;
  LocalStorageService._internal();

  static Stream<bool> get onlineStatusStream => _onlineController.stream;
  static final _onlineController = StreamController<bool>.broadcast();

  static bool _lastKnownOnline = true; // optimistic start

  static Timer? _connectivityTimer;

  // Initialize Hive boxes + start periodic connectivity check
  static Future<void> init() async {
    await Hive.openBox(dropdownBox);
    await Hive.openBox(pendingSchoolsBox);
    await Hive.openBox(pendingAssessmentsBox); // new
    await Hive.openBox(pendingDocumentChecksBox);
    await Hive.openBox(pendingLeadershipBox);
    await Hive.openBox(pendingInfrastructureBox);
    await Hive.openBox(pendingClassroomObservationBox);

    // Start periodic check every 5 seconds
    _startConnectivityCheck();
  }

  static void _startConnectivityCheck() {
    // Immediate first check
    _checkConnectivity();

    // Then every 5 seconds
    _connectivityTimer?.cancel();
    _connectivityTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkConnectivity();
    });
  }

  static Future<void> _checkConnectivity() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final isOnline = connectivityResult != ConnectivityResult.none;

      if (isOnline != _lastKnownOnline) {
        _lastKnownOnline = isOnline;
        if (!_onlineController.isClosed) {
          _onlineController.add(isOnline);
        }
        debugPrint('Connectivity changed: ${isOnline ? "Online" : "Offline"}');
      }
    } catch (e) {
      debugPrint('Connectivity check failed: $e');
      // Assume offline on error
      if (_lastKnownOnline != false) {
        _lastKnownOnline = false;
        if (!_onlineController.isClosed) {
          _onlineController.add(false);
        }
      }
    }
  }

  // Save pending assessment
  static Future<void> savePendingAssessment(Map<String, dynamic> assessmentData) async {
    final box = Hive.box(pendingAssessmentsBox);
    var pending = box.get('pending', defaultValue: <dynamic>[]) as List<dynamic>;
    if (!assessmentData.containsKey('queuedAt')) {
      assessmentData['queuedAt'] = DateTime.now().toIso8601String();
    }
    pending.add(assessmentData);
    await box.put('pending', pending);
  }

// Get pending assessments
  static List<Map<String, dynamic>> getPendingAssessments() {
    final box = Hive.box(pendingAssessmentsBox);
    final rawList = box.get('pending', defaultValue: <dynamic>[]) as List<dynamic>;
    return rawList.map((item) {
      if (item is Map) return Map<String, dynamic>.from(item);
      return <String, dynamic>{};
    }).toList();
  }

// Remove one pending assessment
  static Future<void> removePendingAssessment(Map<String, dynamic> toRemove) async {
    final current = getPendingAssessments();
    final updated = current.where((a) => a['queuedAt'] != toRemove['queuedAt']).toList();
    final box = Hive.box(pendingAssessmentsBox);
    await box.put('pending', updated);
  }

  // ─── Pending Document Checks ────────────────────────────────────────────────
  static Future<void> savePendingDocumentCheck(Map<String, dynamic> payload) async {
    final box = Hive.box(pendingDocumentChecksBox);
    var pending = box.get('pending', defaultValue: <dynamic>[]) as List<dynamic>;
    if (!payload.containsKey('queuedAt')) {
      payload['queuedAt'] = DateTime.now().toIso8601String();
    }
    pending.add(payload);
    await box.put('pending', pending);
    debugPrint('Document check queued offline');
  }

  static List<Map<String, dynamic>> getPendingDocumentChecks() {
    final box = Hive.box(pendingDocumentChecksBox);
    final rawList = box.get('pending', defaultValue: <dynamic>[]) as List<dynamic>;
    return rawList.map((item) {
      if (item is Map) return Map<String, dynamic>.from(item);
      return <String, dynamic>{};
    }).toList();
  }

  static Future<void> removePendingDocumentCheck(Map<String, dynamic> toRemove) async {
    final current = getPendingDocumentChecks();
    final updated = current.where((p) => p['queuedAt'] != toRemove['queuedAt']).toList();
    final box = Hive.box(pendingDocumentChecksBox);
    await box.put('pending', updated);
    debugPrint('Pending document check removed after sync');
  }

  // Save
  static Future<void> savePendingLeadership(Map<String, dynamic> payload) async {
    final box = Hive.box(pendingLeadershipBox);
    var pending = box.get('pending', defaultValue: <dynamic>[]) as List<dynamic>;
    if (!payload.containsKey('queuedAt')) {
      payload['queuedAt'] = DateTime.now().toIso8601String();
    }
    pending.add(payload);
    await box.put('pending', pending);
  }

// Get
  static List<Map<String, dynamic>> getPendingLeadership() {
    final box = Hive.box(pendingLeadershipBox);
    final rawList = box.get('pending', defaultValue: <dynamic>[]) as List<dynamic>;
    return rawList.map((item) {
      if (item is Map) return Map<String, dynamic>.from(item);
      return <String, dynamic>{};
    }).toList();
  }

// Remove
  static Future<void> removePendingLeadership(Map<String, dynamic> toRemove) async {
    final current = getPendingLeadership();
    final updated = current.where((p) => p['queuedAt'] != toRemove['queuedAt']).toList();
    final box = Hive.box(pendingLeadershipBox);
    await box.put('pending', updated);
  }

  // Save
  static Future<void> savePendingInfrastructure(Map<String, dynamic> payload) async {
    final box = Hive.box(pendingInfrastructureBox);
    var pending = box.get('pending', defaultValue: <dynamic>[]) as List<dynamic>;
    if (!payload.containsKey('queuedAt')) {
      payload['queuedAt'] = DateTime.now().toIso8601String();
    }
    pending.add(payload);
    await box.put('pending', pending);
  }

// Get
  static List<Map<String, dynamic>> getPendingInfrastructure() {
    final box = Hive.box(pendingInfrastructureBox);
    final rawList = box.get('pending', defaultValue: <dynamic>[]) as List<dynamic>;
    return rawList.map((item) {
      if (item is Map) return Map<String, dynamic>.from(item);
      return <String, dynamic>{};
    }).toList();
  }

// Remove
  static Future<void> removePendingInfrastructure(Map<String, dynamic> toRemove) async {
    final current = getPendingInfrastructure();
    final updated = current.where((p) => p['queuedAt'] != toRemove['queuedAt']).toList();
    final box = Hive.box(pendingInfrastructureBox);
    await box.put('pending', updated);
  }

  // Call this when app is disposed / no longer needed (optional)
  static void dispose() {
    _connectivityTimer?.cancel();
    _onlineController.close();
  }

  // ─── Dropdown Caching ────────────────────────────────────────────────────────
  static Future<void> cacheDropdowns(Map<String, dynamic> data) async {
    final box = Hive.box(dropdownBox);
    await box.put('counties', data['counties']);
    await box.put('districts', data['districts']);
    await box.put('levels', data['levels']);
    await box.put('types', data['types']);
    await box.put('ownerships', data['ownerships']);
    await box.put('lastSync', DateTime.now().toIso8601String());
  }

  static Map<String, dynamic> getCachedDropdowns() {
    final box = Hive.box(dropdownBox);
    return {
      'counties': box.get('counties', defaultValue: <dynamic>[]),
      'districts': box.get('districts', defaultValue: <dynamic>[]),
      'levels': box.get('levels', defaultValue: <dynamic>[]),
      'types': box.get('types', defaultValue: <dynamic>[]),
      'ownerships': box.get('ownerships', defaultValue: <dynamic>[]),
    };
  }

  // ─── Pending Schools Queue ───────────────────────────────────────────────────
  static Future<void> savePendingSchool(Map<String, dynamic> schoolData) async {
    final box = Hive.box(pendingSchoolsBox);
    var pending = box.get('pending', defaultValue: <dynamic>[]) as List<dynamic>;
    // Optional: add timestamp if not present
    if (!schoolData.containsKey('queuedAt')) {
      schoolData['queuedAt'] = DateTime.now().toIso8601String();
    }
    pending.add(schoolData);
    await box.put('pending', pending);
  }

  static List<Map<String, dynamic>> getPendingSchools() {
    final box = Hive.box(pendingSchoolsBox);
    final rawList = box.get('pending', defaultValue: <dynamic>[]) as List<dynamic>;

    return rawList.map((item) {
      if (item is Map) {
        return Map<String, dynamic>.from(item);
      }
      return <String, dynamic>{};
    }).toList();
  }

  // Save
  static Future<void> savePendingClassroomObservation(Map<String, dynamic> payload) async {
    final box = Hive.box(pendingClassroomObservationBox);
    var pending = box.get('pending', defaultValue: <dynamic>[]) as List<dynamic>;
    if (!payload.containsKey('queuedAt')) {
      payload['queuedAt'] = DateTime.now().toIso8601String();
    }
    pending.add(payload);
    await box.put('pending', pending);
  }

// Get
  static List<Map<String, dynamic>> getPendingClassroomObservation() {
    final box = Hive.box(pendingClassroomObservationBox);
    final rawList = box.get('pending', defaultValue: <dynamic>[]) as List<dynamic>;
    return rawList.map((item) {
      if (item is Map) return Map<String, dynamic>.from(item);
      return <String, dynamic>{};
    }).toList();
  }

// Remove
  static Future<void> removePendingClassroomObservation(Map<String, dynamic> toRemove) async {
    final current = getPendingClassroomObservation();
    final updated = current.where((p) => p['queuedAt'] != toRemove['queuedAt']).toList();
    final box = Hive.box(pendingClassroomObservationBox);
    await box.put('pending', updated);
  }

  static Future<void> clearPendingSchools() async {
    final box = Hive.box(pendingSchoolsBox);
    await box.delete('pending');
  }

  // Legacy method (for backward compatibility) — prefer onlineStatusStream
  static Future<bool> isOnline() async {
    return _lastKnownOnline;
  }
}