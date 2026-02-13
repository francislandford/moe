import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import '../constants/app_url.dart';

class ParentLocalStorageService {
  static const String boxName = 'pending_parent_participation';

  static Future<void> init() async {
    await Hive.openBox(boxName);
  }

  /// Save a new parent participation assessment offline
  static Future<void> savePending(Map<String, dynamic> payload) async {
    final box = Hive.box(boxName);
    var pending = box.get('pending', defaultValue: <dynamic>[]) as List<dynamic>;

    // Add timestamp if missing
    if (!payload.containsKey('queuedAt')) {
      payload['queuedAt'] = DateTime.now().toIso8601String();
    }

    pending.add(payload);
    await box.put('pending', pending);
    debugPrint('Parent participation saved offline');
  }

  /// Get all pending parent participation assessments
  static List<Map<String, dynamic>> getPending() {
    final box = Hive.box(boxName);
    final rawList = box.get('pending', defaultValue: <dynamic>[]) as List<dynamic>;

    return rawList.map((item) {
      if (item is Map) return Map<String, dynamic>.from(item);
      return <String, dynamic>{};
    }).toList();
  }

  /// Remove a specific pending entry after successful sync
  static Future<void> removePending(Map<String, dynamic> toRemove) async {
    final current = getPending();
    final updated = current.where((p) => p['queuedAt'] != toRemove['queuedAt']).toList();

    final box = Hive.box(boxName);
    await box.put('pending', updated);
    debugPrint('Pending parent participation removed after sync');
  }

  /// Sync all pending entries — now takes headers instead of context
  static Future<void> syncPending(Map<String, String> headers) async {
    final pending = getPending();
    if (pending.isEmpty) return;

    for (var payload in pending) {
      try {
        final res = await http.post(
          Uri.parse('${AppUrl.url}/parent-participation'),
          headers: headers,
          body: jsonEncode(payload),
        );

        if (res.statusCode == 200 || res.statusCode == 201) {
          await removePending(payload);
          debugPrint('Parent participation entry synced successfully');
        } else {
          debugPrint('Sync failed for entry: ${res.statusCode} - ${res.body}');
        }
      } catch (e) {
        debugPrint('Parent participation sync error: $e');
        // Keep failed items for next attempt
      }
    }
  }

  /// Clear all pending entries (use with caution)
  static Future<void> clearAll() async {
    final box = Hive.box(boxName);
    await box.delete('pending');
    debugPrint('All pending parent participation cleared');
  }
}