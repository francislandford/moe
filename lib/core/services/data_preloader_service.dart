import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../constants/app_url.dart';
import 'local_storage_service.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';

// Progress model for tracking preload status
class PreloadProgress {
  final String currentTask;
  final double progress;
  final List<String> completedTasks;

  PreloadProgress({
    required this.currentTask,
    required this.progress,
    required this.completedTasks,
  });
}

class DataPreloaderService {
  // Progress notifier for UI updates
  static final ValueNotifier<PreloadProgress> progressNotifier = ValueNotifier<PreloadProgress>(
    PreloadProgress(
      currentTask: 'Initializing...',
      progress: 0.0,
      completedTasks: [],
    ),
  );

  static bool _isPreloading = false;
  static bool _preloadComplete = false;

  static bool get isPreloading => _isPreloading;
  static bool get preloadComplete => _preloadComplete;

  // Exact school levels
  static const List<String> SCHOOL_LEVELS = ['ECE', 'Primary', 'JHS', 'SHS'];

  // Main preload method
  static Future<void> preloadAllData(BuildContext context) async {
    if (_isPreloading) return;

    _isPreloading = true;
    _preloadComplete = false;

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      if (!authProvider.isAuthenticated || authProvider.token == null) {
        debugPrint('User not authenticated, skipping preload');
        _isPreloading = false;
        return;
      }

      final headers = authProvider.getAuthHeaders();
      final token = authProvider.token!;
      final userId = authProvider.userId;

      // Update progress - Starting
      progressNotifier.value = PreloadProgress(
        currentTask: 'Loading school data...',
        progress: 0.1,
        completedTasks: [],
      );

      // Load school data
      await _preloadSchoolData(headers);

      progressNotifier.value = PreloadProgress(
        currentTask: 'Loading assessment data...',
        progress: 0.3,
        completedTasks: ['School data loaded'],
      );

      // Load assessment data
      await _preloadAssessmentData(headers);

      progressNotifier.value = PreloadProgress(
        currentTask: 'Loading grades and subjects...',
        progress: 0.5,
        completedTasks: ['School data loaded', 'Assessment data loaded'],
      );

      // Load level-based data
      await _preloadLevelBasedData(headers);

      progressNotifier.value = PreloadProgress(
        currentTask: 'Loading classroom data...',
        progress: 0.7,
        completedTasks: [
          'School data loaded',
          'Assessment data loaded',
          'Grades & subjects loaded'
        ],
      );

      // Load classroom data
      await _preloadClassroomData(headers);

      progressNotifier.value = PreloadProgress(
        currentTask: 'Loading user data...',
        progress: 0.85,
        completedTasks: [
          'School data loaded',
          'Assessment data loaded',
          'Grades & subjects loaded',
          'Classroom data loaded'
        ],
      );

      // Load user data
      await _preloadUserData(headers, token, userId);

      progressNotifier.value = PreloadProgress(
        currentTask: 'Loading questions...',
        progress: 0.95,
        completedTasks: [
          'School data loaded',
          'Assessment data loaded',
          'Grades & subjects loaded',
          'Classroom data loaded',
          'User data loaded'
        ],
      );

      // Load questions
      await _preloadQuestions(headers);

      // Complete
      _preloadComplete = true;
      progressNotifier.value = PreloadProgress(
        currentTask: 'Complete!',
        progress: 1.0,
        completedTasks: [
          'School data loaded',
          'Assessment data loaded',
          'Grades & subjects loaded',
          'Classroom data loaded',
          'User data loaded',
          'Questions loaded'
        ],
      );

      debugPrint('✅ All data preloaded successfully!');

    } catch (e) {
      debugPrint('❌ Error during preload: $e');
      progressNotifier.value = PreloadProgress(
        currentTask: 'Error during preload',
        progress: 0.0,
        completedTasks: [],
      );
    } finally {
      _isPreloading = false;
    }
  }

  static Future<void> _preloadSchoolData(Map<String, String> headers) async {
    try {
      await Future.wait([
        _fetchAndCache('${AppUrl.url}/counties', headers, 'counties'),
        _fetchAndCache('${AppUrl.url}/districts', headers, 'all_districts'),
        _fetchAndCache('${AppUrl.url}/school-levels', headers, 'levels'),
        _fetchAndCache('${AppUrl.url}/school-types', headers, 'types'),
        _fetchAndCache('${AppUrl.url}/school-ownerships', headers, 'ownerships'),
      ]);
    } catch (e) {
      debugPrint('School data preload error: $e');
    }
  }

  static Future<void> _preloadAssessmentData(Map<String, String> headers) async {
    try {
      await Future.wait([
        _fetchAndCache('${AppUrl.url}/positions', headers, 'positions'),
        _fetchAndCache('${AppUrl.url}/fees', headers, 'fees'),
      ]);
    } catch (e) {
      debugPrint('Assessment data preload error: $e');
    }
  }

  static Future<void> _preloadLevelBasedData(Map<String, String> headers) async {
    try {
      final List<Future> tasks = [];
      for (var level in SCHOOL_LEVELS) {
        tasks.add(_fetchAndCache(
            '${AppUrl.url}/level/grades?level=$level',
            headers,
            'grades_${level.toLowerCase()}'
        ));
        tasks.add(_fetchAndCache(
            '${AppUrl.url}/level/subjects?level=$level',
            headers,
            'subjects_${level.toLowerCase()}'
        ));
      }
      await Future.wait(tasks);
    } catch (e) {
      debugPrint('Level data preload error: $e');
    }
  }

  static Future<void> _preloadClassroomData(Map<String, String> headers) async {
    try {
      await _fetchAndCache(
          '${AppUrl.url}/questions?cat=Classroom Observation',
          headers,
          'classroom_questions'
      );
    } catch (e) {
      debugPrint('Classroom data preload error: $e');
    }
  }

  static Future<void> _preloadUserData(Map<String, String> headers, String token, int userId) async {
    try {
      await Future.wait([
        _fetchAndCache('${AppUrl.url}/my-schools', headers, 'my_schools'),
        _fetchUserCounty(headers),
      ]);
    } catch (e) {
      debugPrint('User data preload error: $e');
    }
  }

  static Future<void> _preloadQuestions(Map<String, String> headers) async {
    final categories = [
      'Document check',
      'Additional data on school documentation',
      'School Physical Infrastructure',
      'Additional data on school infrastructure',
      'School Leadership',
      'Parents',
      'Students',
      'Textbooks',
    ];

    final cacheKeys = [
      'document_check_questions',
      'additional_document_questions',
      'infrastructure_questions',
      'additional_infrastructure_questions',
      'leadership_questions',
      'parent_questions',
      'student_questions',
      'textbooks_questions',
    ];

    try {
      final List<Future> tasks = [];
      for (int i = 0; i < categories.length; i++) {
        tasks.add(_fetchAndCache(
            '${AppUrl.url}/questions?cat=${Uri.encodeComponent(categories[i])}',
            headers,
            cacheKeys[i]
        ));
      }
      await Future.wait(tasks);
    } catch (e) {
      debugPrint('Questions preload error: $e');
    }
  }

  static Future<void> _fetchAndCache(String url, Map<String, String> headers, String cacheKey) async {
    try {
      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = _extractListFromResponse(data);
        if (list.isNotEmpty) {
          await LocalStorageService.saveToCache(cacheKey, list);
        }
      }
    } catch (e) {
      debugPrint('Fetch error for $url: $e');
    }
  }

  static Future<void> _fetchUserCounty(Map<String, String> headers) async {
    try {
      final response = await http.get(
        Uri.parse('${AppUrl.url}/counties'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String? county;
        if (data is String) {
          county = data;
        } else if (data is Map && data.containsKey('county')) {
          county = data['county'] as String?;
        }
        if (county != null) {
          await LocalStorageService.saveToCache('user_county', county);
        }
      }
    } catch (e) {
      debugPrint('User county fetch error: $e');
    }
  }

  static List<dynamic> _extractListFromResponse(dynamic data) {
    if (data is List) return data;
    if (data is Map && data.containsKey('data') && data['data'] is List) {
      return data['data'];
    }
    return [];
  }

  // Public methods for accessing cached data
  static List<Map<String, dynamic>> getCachedData(String cacheKey) {
    try {
      final data = LocalStorageService.getFromCache(cacheKey);
      if (data != null && data is List) {
        return List<Map<String, dynamic>>.from(data);
      }
    } catch (e) {
      debugPrint('Error getting cached data: $e');
    }
    return [];
  }

  static List<Map<String, dynamic>> getGradesForLevel(String level) {
    return getCachedData('grades_${level.toLowerCase()}');
  }

  static List<Map<String, dynamic>> getSubjectsForLevel(String level) {
    return getCachedData('subjects_${level.toLowerCase()}');
  }

  static List<String> getAvailableLevels() => SCHOOL_LEVELS;

  static void resetPreloadStatus() {
    _preloadComplete = false;
    _isPreloading = false;
    progressNotifier.value = PreloadProgress(
      currentTask: 'Initializing...',
      progress: 0.0,
      completedTasks: [],
    );
  }
}