import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../../../core/constants/app_url.dart';
import '../../../../core/services/local_storage_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class SchoolProvider with ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<Map<String, dynamic>> _counties = [];
  List<Map<String, dynamic>> _districts = [];
  List<Map<String, dynamic>> _levels = [];
  List<Map<String, dynamic>> _types = [];
  List<Map<String, dynamic>> _ownerships = [];

  List<Map<String, dynamic>> get counties => _counties;
  List<Map<String, dynamic>> get districts => _districts;
  List<Map<String, dynamic>> get levels => _levels;
  List<Map<String, dynamic>> get types => _types;
  List<Map<String, dynamic>> get ownerships => _ownerships;

  // Helper to safely update loading state
  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  // Fetch dropdowns — offline-first
  Future<void> fetchDropdownData(BuildContext context) async {
    _setLoading(true);

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final headers = auth.getAuthHeaders();
    final isOnline = await LocalStorageService.isOnline();

    if (isOnline) {
      try {
        // Counties
        final countyRes = await http.get(Uri.parse('${AppUrl.url}/counties'), headers: headers);
        if (countyRes.statusCode == 200) {
          _counties = List<Map<String, dynamic>>.from(jsonDecode(countyRes.body));
        }

        // Levels
        final levelRes = await http.get(Uri.parse('${AppUrl.url}/school-levels'), headers: headers);
        if (levelRes.statusCode == 200) {
          _levels = List<Map<String, dynamic>>.from(jsonDecode(levelRes.body));
        }

        // Types
        final typeRes = await http.get(Uri.parse('${AppUrl.url}/school-types'), headers: headers);
        if (typeRes.statusCode == 200) {
          _types = List<Map<String, dynamic>>.from(jsonDecode(typeRes.body));
        }

        // Ownerships
        final ownRes = await http.get(Uri.parse('${AppUrl.url}/school-ownerships'), headers: headers);
        if (ownRes.statusCode == 200) {
          _ownerships = List<Map<String, dynamic>>.from(jsonDecode(ownRes.body));
        }

        // Cache everything
        await LocalStorageService.cacheDropdowns({
          'counties': _counties,
          'districts': _districts,
          'levels': _levels,
          'types': _types,
          'ownerships': _ownerships,
        });
      } catch (e) {
        debugPrint('Online fetch failed: $e → falling back to cache');
        _loadFromCache();
      }
    } else {
      _loadFromCache();
    }

    _setLoading(false);
  }

  void _loadFromCache() {
    final cached = LocalStorageService.getCachedDropdowns();
    _counties = List<Map<String, dynamic>>.from(cached['counties'] ?? []);
    _districts = List<Map<String, dynamic>>.from(cached['districts'] ?? []);
    _levels = List<Map<String, dynamic>>.from(cached['levels'] ?? []);
    _types = List<Map<String, dynamic>>.from(cached['types'] ?? []);
    _ownerships = List<Map<String, dynamic>>.from(cached['ownerships'] ?? []);
    notifyListeners();
  }

  // Fetch districts (offline-aware)
  Future<void> fetchDistricts(String county, BuildContext context) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final headers = auth.getAuthHeaders();
    final isOnline = await LocalStorageService.isOnline();

    if (isOnline) {
      try {
        final res = await http.get(
          Uri.parse('${AppUrl.url}/districts?county=$county'),
          headers: headers,
        );
        if (res.statusCode == 200) {
          _districts = List<Map<String, dynamic>>.from(jsonDecode(res.body));
          notifyListeners();
        }
      } catch (e) {
        debugPrint('District fetch error: $e');
      }
    } else {
      // Offline: use cached (you can filter if stored per-county)
      _districts = List<Map<String, dynamic>>.from(
        LocalStorageService.getCachedDropdowns()['districts'] ?? [],
      );
      notifyListeners();
    }
  }

  // Create school — offline-first with queue

  Future<Map<String, dynamic>> createSchool(Map<String, dynamic> data, BuildContext context) async {
    _setLoading(true);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final headers = auth.getAuthHeaders();
    final isOnline = await LocalStorageService.isOnline();

    try {
      if (isOnline) {
        print('Online submit: $data');
        final res = await http.post(
          Uri.parse('${AppUrl.url}/schools'),
          headers: headers,
          body: jsonEncode(data), // ← now includes 'nb_room'
        );

        if (res.statusCode == 201 || res.statusCode == 200) {
          await _syncPendingSchools(context);
          return {
            'success': true,
            'message': 'School created successfully',
            'data': jsonDecode(res.body),
          };
        } else {
          final errorBody = jsonDecode(res.body);
          return {
            'success': false,
            'message': errorBody['message'] ?? 'Failed to create school (status ${res.statusCode})',
          };
        }
      } else {
        await LocalStorageService.savePendingSchool({
          ...data,
          'queuedAt': DateTime.now().toIso8601String(),
        });
        return {
          'success': true,
          'message': 'Saved offline — will sync when online',
          'offline': true,
        };
      }
    } catch (e) {
      debugPrint('Create school error: $e');
      await LocalStorageService.savePendingSchool({
        ...data,
        'queuedAt': DateTime.now().toIso8601String(),
      });
      return {
        'success': true,
        'message': 'Network error — saved offline for later sync',
        'offline': true,
      };
    } finally {
      _setLoading(false);
    }
  }

  // Sync pending schools when online
  Future<void> _syncPendingSchools(BuildContext context) async {
    final pending = LocalStorageService.getPendingSchools();
    if (pending.isEmpty) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final headers = auth.getAuthHeaders();

    List<Map<String, dynamic>> failed = [];

    for (var school in pending) {
      try {
        final res = await http.post(
          Uri.parse('${AppUrl.url}/schools'),
          headers: headers,
          body: jsonEncode(school),
        );

        if (res.statusCode != 201 && res.statusCode != 200) {
          failed.add(school);
        }
      } catch (e) {
        debugPrint('Sync failed for one school: $e');
        failed.add(school);
      }
    }

    // Update pending list: keep only failed
    await Hive.box(LocalStorageService.pendingSchoolsBox).put('pending', failed);

    // Clear if all succeeded
    if (failed.isEmpty) {
      await LocalStorageService.clearPendingSchools();
    }
  }
}