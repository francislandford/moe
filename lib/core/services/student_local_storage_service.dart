import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import '../constants/app_url.dart';

class StudentLocalStorageService {
  static const String boxName = 'pending_student_participation';

  // Lazy-open helper
  static Future<Box> _getBox() async {
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox(boxName);
    }
    return Hive.box(boxName);
  }

  /// Save a new student participation assessment offline
  static Future<void> savePending(Map<String, dynamic> payload) async {
    final box = await _getBox();
    var pending = box.get('pending', defaultValue: <dynamic>[]) as List<dynamic>;

    if (!payload.containsKey('queuedAt')) {
      payload['queuedAt'] = DateTime.now().toIso8601String();
    }

    pending.add(payload);
    await box.put('pending', pending);
    debugPrint('Student participation saved offline');
  }

  /// Get all pending student participation assessments
  static Future<List<Map<String, dynamic>>> getPending() async {
    final box = await _getBox();
    final rawList = box.get('pending', defaultValue: <dynamic>[]) as List<dynamic>;

    return rawList.map((item) {
      if (item is Map) return Map<String, dynamic>.from(item);
      return <String, dynamic>{};
    }).toList();
  }

  /// Remove a specific pending entry after successful sync
  static Future<void> removePending(Map<String, dynamic> toRemove) async {
    final box = await _getBox();
    final current = await getPending();
    final updated = current.where((p) => p['queuedAt'] != toRemove['queuedAt']).toList();

    await box.put('pending', updated);
    debugPrint('Pending student participation removed after sync');
  }

  /// Sync all pending student participation entries with the server
  static Future<void> syncPending(Map<String, String> headers) async {
    final pending = await getPending();
    if (pending.isEmpty) return;

    for (var payload in pending) {
      try {
        final res = await http.post(
          Uri.parse('${AppUrl.url}/student-participation'),
          headers: headers,
          body: jsonEncode(payload),
        );

        if (res.statusCode == 200 || res.statusCode == 201) {
          await removePending(payload);
          debugPrint('Student participation entry synced successfully');
        } else {
          debugPrint('Sync failed for entry: ${res.statusCode} - ${res.body}');
        }
      } catch (e) {
        debugPrint('Student participation sync error: $e');
        // Keep failed items for next attempt
      }
    }
  }

  /// Clear all pending entries (use with caution)
  static Future<void> clearAll() async {
    final box = await _getBox();
    await box.delete('pending');
    debugPrint('All pending student participation cleared');
  }
}