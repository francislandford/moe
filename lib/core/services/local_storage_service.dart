import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

class LocalStorageService {
  // Public box names
  static const String dropdownBox = 'dropdowns';
  static const String pendingSchoolsBox = 'pending_schools';
  static const String pendingAssessmentsBox = 'pending_assessments';
  static const String pendingDocumentChecksBox = 'pending_document_checks';
  static const String pendingLeadershipBox = 'pending_leadership';
  static const String pendingInfrastructureBox = 'pending_infrastructure';
  static const String pendingClassroomObservationBox = 'pending_classroom_observation';

  // Box for failed syncs to retry later
  static const String failedSyncsBox = 'failed_syncs';

  // ─── Singleton + Stream for real-time connectivity ───────────────────────────
  static final LocalStorageService _instance = LocalStorageService._internal();
  factory LocalStorageService() => _instance;
  LocalStorageService._internal();

  static Stream<bool> get onlineStatusStream => _onlineController.stream;
  static final _onlineController = StreamController<bool>.broadcast();
  static bool _lastKnownOnline = true; // optimistic start
  static Timer? _connectivityTimer;
  static StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // Initialize Hive boxes + start connectivity monitoring
  static Future<void> init() async {
    await Hive.openBox(dropdownBox);
    await Hive.openBox(pendingSchoolsBox);
    await Hive.openBox(pendingAssessmentsBox);
    await Hive.openBox(pendingDocumentChecksBox);
    await Hive.openBox(pendingLeadershipBox);
    await Hive.openBox(pendingInfrastructureBox);
    await Hive.openBox(pendingClassroomObservationBox);
    await Hive.openBox(failedSyncsBox);

    // Start connectivity monitoring
    _startConnectivityMonitoring();
  }

  static void _startConnectivityMonitoring() {
    // Listen to connectivity changes (real-time)
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      _handleConnectivityChange(results);
    });

    // Immediate first check
    _checkConnectivity();

    // Also check periodically every 5 seconds as backup
    _connectivityTimer?.cancel();
    _connectivityTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkConnectivity();
    });
  }

  static Future<void> _checkConnectivity() async {
    try {
      final results = await Connectivity().checkConnectivity();
      _handleConnectivityChange(results);
    } catch (e) {
      debugPrint('Connectivity check failed: $e');
      _updateStatus(false);
    }
  }

  static void _handleConnectivityChange(List<ConnectivityResult> results) {
    // Check if any connectivity result is not 'none'
    final hasConnection = results.any((result) => result != ConnectivityResult.none);
    _updateStatus(hasConnection);
  }

  static void _updateStatus(bool isOnline) {
    if (isOnline != _lastKnownOnline) {
      _lastKnownOnline = isOnline;
      if (!_onlineController.isClosed) {
        _onlineController.add(isOnline);
      }
      debugPrint('Connectivity changed: ${isOnline ? "Online" : "Offline"}');
    }
  }

  // ─── Dropdown Caching ────────────────────────────────────────────────────────
  static Future<void> cacheDropdowns(Map<String, dynamic> data) async {
    final box = Hive.box(dropdownBox);
    await box.put('counties', data['counties']);
    await box.put('all_districts', data['all_districts']);
    await box.put('levels', data['levels']);
    await box.put('types', data['types']);
    await box.put('ownerships', data['ownerships']);
    await box.put('lastSync', DateTime.now().toIso8601String());
  }

  static Map<String, dynamic> getCachedDropdowns() {
    final box = Hive.box(dropdownBox);
    return {
      'counties': box.get('counties', defaultValue: <dynamic>[]),
      'all_districts': box.get('all_districts', defaultValue: <dynamic>[]),
      'levels': box.get('levels', defaultValue: <dynamic>[]),
      'types': box.get('types', defaultValue: <dynamic>[]),
      'ownerships': box.get('ownerships', defaultValue: <dynamic>[]),
    };
  }

  // ─── Generic helper to safely store any data type ───────────────────────────
  static dynamic _makeSafeForHive(dynamic data) {
    if (data == null) return null;

    // Use jsonEncode/jsonDecode to convert all types to JSON-safe format
    try {
      final jsonString = jsonEncode(data);
      return jsonDecode(jsonString);
    } catch (e) {
      debugPrint('Error making data safe for Hive: $e');
      // If jsonEncode fails, return the original data
      return data;
    }
  }

  // ─── Pending Schools Queue ───────────────────────────────────────────────────
  static Future<void> savePendingSchool(Map<String, dynamic> schoolData) async {
    final box = Hive.box(pendingSchoolsBox);
    var pending = box.get('pending', defaultValue: <dynamic>[]) as List<dynamic>;

    // Make a safe copy of the data
    final safeData = _makeSafeForHive(schoolData) as Map<String, dynamic>;

    if (!safeData.containsKey('queuedAt')) {
      safeData['queuedAt'] = DateTime.now().toIso8601String();
    }

    pending.add(safeData);
    await box.put('pending', pending);
  }

  static List<Map<String, dynamic>> getPendingSchools() {
    final box = Hive.box(pendingSchoolsBox);
    final rawList = box.get('pending', defaultValue: <dynamic>[]) as List<dynamic>;
    return rawList.map((item) {
      if (item is Map) return Map<String, dynamic>.from(item);
      return <String, dynamic>{};
    }).toList();
  }

  static Future<void> removePendingSchool(Map<String, dynamic> toRemove) async {
    final current = getPendingSchools();
    final updated = current.where((a) => a['queuedAt'] != toRemove['queuedAt']).toList();
    final box = Hive.box(pendingSchoolsBox);
    await box.put('pending', updated);
  }

  static Future<void> clearPendingSchools() async {
    final box = Hive.box(pendingSchoolsBox);
    await box.delete('pending');
  }

  // ─── Pending Assessments ─────────────────────────────────────────────────────
  static Future<void> savePendingAssessment(Map<String, dynamic> assessmentData) async {
    final box = Hive.box(pendingAssessmentsBox);
    var pending = box.get('pending', defaultValue: <dynamic>[]) as List<dynamic>;

    final safeData = _makeSafeForHive(assessmentData) as Map<String, dynamic>;

    if (!safeData.containsKey('queuedAt')) {
      safeData['queuedAt'] = DateTime.now().toIso8601String();
    }

    pending.add(safeData);
    await box.put('pending', pending);
  }

  static List<Map<String, dynamic>> getPendingAssessments() {
    final box = Hive.box(pendingAssessmentsBox);
    final rawList = box.get('pending', defaultValue: <dynamic>[]) as List<dynamic>;
    return rawList.map((item) {
      if (item is Map) return Map<String, dynamic>.from(item);
      return <String, dynamic>{};
    }).toList();
  }

  static Future<void> removePendingAssessment(Map<String, dynamic> toRemove) async {
    final current = getPendingAssessments();
    final updated = current.where((a) => a['queuedAt'] != toRemove['queuedAt']).toList();
    final box = Hive.box(pendingAssessmentsBox);
    await box.put('pending', updated);

    // Add this debug code in your sync method where you call removePendingAssessment
    debugPrint('Attempting to remove assessment with queuedAt: ${toRemove['queuedAt']}');
    debugPrint('Current pending count before removal: ${getPendingAssessments().length}');
// After removal
    debugPrint('Current pending count after removal: ${getPendingAssessments().length}');
  }

  // ─── Save Failed Syncs for Retry ───────────────────────────────────────
  static Future<void> saveFailedSyncs(List<Map<String, dynamic>> failedItems) async {
    final box = Hive.box(failedSyncsBox);

    // Get existing failed items
    var existing = box.get('failed', defaultValue: <dynamic>[]) as List<dynamic>;
    List<Map<String, dynamic>> existingMaps = existing.map((item) {
      if (item is Map) return Map<String, dynamic>.from(item);
      return <String, dynamic>{};
    }).toList();

    // Make all items safe
    final safeFailedItems = failedItems.map((item) =>
    _makeSafeForHive(item) as Map<String, dynamic>
    ).toList();

    // Merge with new failed items (avoid duplicates by queuedAt)
    final allItems = {...existingMaps, ...safeFailedItems}.toList();

    await box.put('failed', allItems);
    debugPrint('Saved ${failedItems.length} failed items to retry queue. Total: ${allItems.length}');
  }

  static List<Map<String, dynamic>> getFailedSyncs() {
    final box = Hive.box(failedSyncsBox);
    final rawList = box.get('failed', defaultValue: <dynamic>[]) as List<dynamic>;
    return rawList.map((item) {
      if (item is Map) return Map<String, dynamic>.from(item);
      return <String, dynamic>{};
    }).toList();
  }

  static Future<void> removeFailedSync(Map<String, dynamic> toRemove) async {
    final current = getFailedSyncs();
    final updated = current.where((a) => a['queuedAt'] != toRemove['queuedAt']).toList();
    final box = Hive.box(failedSyncsBox);
    await box.put('failed', updated);
    debugPrint('Removed failed sync item. Remaining: ${updated.length}');
  }

  static Future<void> clearFailedSyncs() async {
    final box = Hive.box(failedSyncsBox);
    await box.delete('failed');
    debugPrint('Cleared all failed syncs');
  }

  // ─── Pending Document Checks ─────────────────────────────────────────────────
  static Future<void> savePendingDocumentCheck(Map<String, dynamic> payload) async {
    final box = Hive.box(pendingDocumentChecksBox);
    var pending = box.get('pending', defaultValue: <dynamic>[]) as List<dynamic>;

    final safePayload = _makeSafeForHive(payload) as Map<String, dynamic>;

    if (!safePayload.containsKey('queuedAt')) {
      safePayload['queuedAt'] = DateTime.now().toIso8601String();
    }

    pending.add(safePayload);
    await box.put('pending', pending);
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
  }

  // ─── Pending Leadership ──────────────────────────────────────────────────────
  static Future<void> savePendingLeadership(Map<String, dynamic> payload) async {
    final box = Hive.box(pendingLeadershipBox);
    var pending = box.get('pending', defaultValue: <dynamic>[]) as List<dynamic>;

    final safePayload = _makeSafeForHive(payload) as Map<String, dynamic>;

    if (!safePayload.containsKey('queuedAt')) {
      safePayload['queuedAt'] = DateTime.now().toIso8601String();
    }

    pending.add(safePayload);
    await box.put('pending', pending);
  }

  static List<Map<String, dynamic>> getPendingLeadership() {
    final box = Hive.box(pendingLeadershipBox);
    final rawList = box.get('pending', defaultValue: <dynamic>[]) as List<dynamic>;
    return rawList.map((item) {
      if (item is Map) {
        final map = Map<String, dynamic>.from(item);
        // Handle scores if present
        if (map.containsKey('scores') && map['scores'] is Map) {
          final scoresMap = <String, dynamic>{};
          (map['scores'] as Map).forEach((key, value) {
            scoresMap[key.toString()] = value;
          });
          map['scores'] = scoresMap;
        }
        return map;
      }
      return <String, dynamic>{};
    }).toList();
  }

  static Future<void> removePendingLeadership(Map<String, dynamic> toRemove) async {
    final current = getPendingLeadership();
    final updated = current.where((p) => p['queuedAt'] != toRemove['queuedAt']).toList();
    final box = Hive.box(pendingLeadershipBox);
    await box.put('pending', updated);
  }

  // ─── Pending Infrastructure ──────────────────────────────────────────────────
  static Future<void> savePendingInfrastructure(Map<String, dynamic> payload) async {
    final box = Hive.box(pendingInfrastructureBox);
    var pending = box.get('pending', defaultValue: <dynamic>[]) as List<dynamic>;

    // Make the payload safe for Hive by converting all types to JSON-safe formats
    final safePayload = _makeSafeForHive(payload) as Map<String, dynamic>;

    if (!safePayload.containsKey('queuedAt')) {
      safePayload['queuedAt'] = DateTime.now().toIso8601String();
    }

    pending.add(safePayload);
    await box.put('pending', pending);
  }

  static List<Map<String, dynamic>> getPendingInfrastructure() {
    final box = Hive.box(pendingInfrastructureBox);
    final rawList = box.get('pending', defaultValue: <dynamic>[]) as List<dynamic>;
    return rawList.map((item) {
      if (item is Map) {
        final map = Map<String, dynamic>.from(item);
        // Ensure scores are properly accessible
        if (map.containsKey('scores') && map['scores'] is Map) {
          final scoresMap = <String, dynamic>{};
          (map['scores'] as Map).forEach((key, value) {
            scoresMap[key.toString()] = value;
          });
          map['scores'] = scoresMap;
        }
        return map;
      }
      return <String, dynamic>{};
    }).toList();
  }

  static Future<void> removePendingInfrastructure(Map<String, dynamic> toRemove) async {
    final current = getPendingInfrastructure();
    final updated = current.where((p) => p['queuedAt'] != toRemove['queuedAt']).toList();
    final box = Hive.box(pendingInfrastructureBox);
    await box.put('pending', updated);
  }

  // ─── Pending Classroom Observation ───────────────────────────────────────────
  static Future<void> savePendingClassroomObservation(Map<String, dynamic> payload) async {
    final box = Hive.box(pendingClassroomObservationBox);
    var pending = box.get('pending', defaultValue: <dynamic>[]) as List<dynamic>;

    final safePayload = _makeSafeForHive(payload) as Map<String, dynamic>;

    if (!safePayload.containsKey('queuedAt')) {
      safePayload['queuedAt'] = DateTime.now().toIso8601String();
    }

    pending.add(safePayload);
    await box.put('pending', pending);
  }

  static List<Map<String, dynamic>> getPendingClassroomObservation() {
    final box = Hive.box(pendingClassroomObservationBox);
    final rawList = box.get('pending', defaultValue: <dynamic>[]) as List<dynamic>;
    return rawList.map((item) {
      if (item is Map) return Map<String, dynamic>.from(item);
      return <String, dynamic>{};
    }).toList();
  }

  static Future<void> removePendingClassroomObservation(Map<String, dynamic> toRemove) async {
    final current = getPendingClassroomObservation();
    final updated = current.where((p) => p['queuedAt'] != toRemove['queuedAt']).toList();
    final box = Hive.box(pendingClassroomObservationBox);
    await box.put('pending', updated);
  }

  // ─── General Cache Helpers ───────────────────────────────────────────────────
  static Future<void> saveToCache(String key, dynamic data) async {
    final box = Hive.box(dropdownBox);
    final safeData = _makeSafeForHive(data);
    await box.put(key, safeData);
  }

  static dynamic getFromCache(String key) {
    final box = Hive.box(dropdownBox);
    return box.get(key);
  }

  // Call this when app is disposed / no longer needed (optional)
  static void dispose() {
    _connectivityTimer?.cancel();
    _connectivitySubscription?.cancel();
    _onlineController.close();
  }

  // Check if device has any network connection
  static Future<bool> isOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((result) => result != ConnectivityResult.none);
    } catch (e) {
      debugPrint('isOnline check failed: $e');
      return _lastKnownOnline; // fallback to cached value on error
    }
  }

  // Add this method to get the current online status immediately
  static bool get currentOnlineStatus => _lastKnownOnline;
}