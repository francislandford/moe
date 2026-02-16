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
  List<Map<String, dynamic>> _districts = []; // filtered list for UI (empty until county selected)
  List<Map<String, dynamic>> _allDistricts = []; // full unfiltered list from cache/API
  List<Map<String, dynamic>> _levels = [];
  List<Map<String, dynamic>> _types = [];
  List<Map<String, dynamic>> _ownerships = [];

  List<Map<String, dynamic>> get counties => _counties;
  List<Map<String, dynamic>> get districts => _districts;
  List<Map<String, dynamic>> get levels => _levels;
  List<Map<String, dynamic>> get types => _types;
  List<Map<String, dynamic>> get ownerships => _ownerships;

  // Track selected county for background updates
  String? _selectedCounty;

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  // Public method to load from cache immediately
  void loadFromCache() {
    _loadFromCache();
  }

  // Load from cache without notifying (called internally)
  void _loadFromCache() {
    final cached = LocalStorageService.getCachedDropdowns();

    _counties = (cached['counties'] as List<dynamic>?)
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList() ??
        [];

    _allDistricts = (cached['all_districts'] as List<dynamic>?)
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList() ??
        [];

    _levels = (cached['levels'] as List<dynamic>?)
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList() ??
        [];

    _types = (cached['types'] as List<dynamic>?)
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList() ??
        [];

    _ownerships = (cached['ownerships'] as List<dynamic>?)
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList() ??
        [];

    // Initially no districts shown until county selected
    _districts = [];

    notifyListeners();
  }

  // Fetch all dropdowns — offline-first with background refresh
  Future<void> fetchDropdownData(BuildContext context) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final headers = auth.getAuthHeaders();
    final isOnline = await LocalStorageService.isOnline();

    // 1. Load from cache first (already done by loadFromCache in initState)
    // 2. If online, refresh from API and update cache (background, no loading indicator)
    if (isOnline) {
      try {
        // Counties
        final countyRes = await http.get(Uri.parse('${AppUrl.url}/counties'), headers: headers);
        if (countyRes.statusCode == 200) {
          final dynamic decoded = jsonDecode(countyRes.body);
          if (decoded is List) {
            _counties = decoded
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          } else if (decoded is Map && decoded['data'] is List) {
            _counties = (decoded['data'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
        } else {
          debugPrint('Counties fetch failed with status: ${countyRes.statusCode}');
        }

        // All districts (full list)
        await fetchAllDistricts(headers);

        // Levels
        final levelRes = await http.get(Uri.parse('${AppUrl.url}/school-levels'), headers: headers);
        if (levelRes.statusCode == 200) {
          final dynamic decoded = jsonDecode(levelRes.body);
          if (decoded is List) {
            _levels = decoded
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          } else if (decoded is Map && decoded['data'] is List) {
            _levels = (decoded['data'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
        } else {
          debugPrint('Levels fetch failed with status: ${levelRes.statusCode}');
        }

        // Types
        final typeRes = await http.get(Uri.parse('${AppUrl.url}/school-types'), headers: headers);
        if (typeRes.statusCode == 200) {
          final dynamic decoded = jsonDecode(typeRes.body);
          if (decoded is List) {
            _types = decoded
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          } else if (decoded is Map && decoded['data'] is List) {
            _types = (decoded['data'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
        } else {
          debugPrint('Types fetch failed with status: ${typeRes.statusCode}');
        }

        // Ownerships
        final ownRes = await http.get(Uri.parse('${AppUrl.url}/school-ownerships'), headers: headers);
        if (ownRes.statusCode == 200) {
          final dynamic decoded = jsonDecode(ownRes.body);
          if (decoded is List) {
            _ownerships = decoded
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          } else if (decoded is Map && decoded['data'] is List) {
            _ownerships = (decoded['data'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
        } else {
          debugPrint('Ownerships fetch failed with status: ${ownRes.statusCode}');
        }

        // Cache everything
        await LocalStorageService.cacheDropdowns({
          'counties': _counties,
          'all_districts': _allDistricts,
          'levels': _levels,
          'types': _types,
          'ownerships': _ownerships,
        });

        // If a county was already selected, refresh districts for that county
        if (_selectedCounty != null) {
          _filterDistrictsByCounty(_selectedCounty!);
        }

        notifyListeners();
      } catch (e) {
        debugPrint('Online fetch failed: $e → using existing cache');
      }
    }
  }

  // Fetch ALL districts (not filtered by county)
  Future<void> fetchAllDistricts(Map<String, String> headers) async {
    try {
      final res = await http.get(
        Uri.parse('${AppUrl.url}/districts'),
        headers: headers,
      );

      if (res.statusCode == 200) {
        final dynamic decoded = jsonDecode(res.body);
        if (decoded is List) {
          _allDistricts = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } else if (decoded is Map && decoded['data'] is List) {
          _allDistricts = (decoded['data'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } else {
        debugPrint('Districts fetch failed with status: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('Fetch all districts error: $e');
      // Don't rethrow - keep existing cached data
    }
  }

  // Helper method to filter districts locally
  void _filterDistrictsByCounty(String county) {
    _districts = _allDistricts
        .where((d) {
      final districtCounty = (d['county'] as String?)?.trim().toLowerCase() ?? '';
      final selectedCounty = county.trim().toLowerCase();
      return districtCounty == selectedCounty;
    })
        .toList();
  }

  // Fetch districts — offline-first + local filtering
  Future<void> fetchDistricts(String? county, BuildContext context) async {
    if (county == null || county.isEmpty) {
      _districts = [];
      notifyListeners();
      return;
    }

    // Store selected county for future background updates
    _selectedCounty = county;

    // Step 1: Filter locally from existing _allDistricts (which came from cache)
    _filterDistrictsByCounty(county);
    notifyListeners();

    // Step 2: If online, refresh full list from API in background (no blocking UI)
    final isOnline = await LocalStorageService.isOnline();
    if (isOnline) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final headers = auth.getAuthHeaders();

      try {
        await fetchAllDistricts(headers);

        // Re-apply filter after refresh
        _filterDistrictsByCounty(county);
        notifyListeners();

        // Update cache
        final updatedCached = LocalStorageService.getCachedDropdowns();
        updatedCached['all_districts'] = _allDistricts;
        await LocalStorageService.cacheDropdowns(updatedCached);
      } catch (e) {
        debugPrint('Background district refresh failed: $e → UI keeps using cache');
      }
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
        final res = await http.post(
          Uri.parse('${AppUrl.url}/schools'),
          headers: {
            ...headers,
            'Content-Type': 'application/json',
          },
          body: jsonEncode(data),
        );

        if (res.statusCode == 201 || res.statusCode == 200) {
          // Sync any pending schools after successful creation
          await _syncPendingSchools(context);

          final responseData = jsonDecode(res.body);
          return {
            'success': true,
            'message': 'School created successfully',
            'data': responseData,
          };
        } else {
          final errorBody = jsonDecode(res.body);
          return {
            'success': false,
            'message': errorBody['message'] ?? 'Failed to create school (status ${res.statusCode})',
          };
        }
      } else {
        // Offline: Save to pending queue
        await LocalStorageService.savePendingSchool({
          ...data,
          'queuedAt': DateTime.now().toIso8601String(),
        });
        return {
          'success': true,
          'message': 'Saved offline — will sync when online',
          'offline': true,
          'data': data, // Return the data for local use
        };
      }
    } catch (e) {
      debugPrint('Create school error: $e');
      // Network error - save to pending queue
      await LocalStorageService.savePendingSchool({
        ...data,
        'queuedAt': DateTime.now().toIso8601String(),
      });
      return {
        'success': true,
        'message': 'Network error — saved offline for later sync',
        'offline': true,
        'data': data, // Return the data for local use
      };
    } finally {
      _setLoading(false);
    }
  }

  // Sync pending schools when online
  Future<void> _syncPendingSchools(BuildContext context) async {
    final pending = LocalStorageService.getPendingSchools();
    if (pending.isEmpty) return;

    debugPrint('Syncing ${pending.length} pending schools...');

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final headers = {
      ...auth.getAuthHeaders(),
      'Content-Type': 'application/json',
    };

    List<Map<String, dynamic>> failed = [];

    for (var school in pending) {
      try {
        // Remove queue metadata before sending
        final Map<String, dynamic> schoolData = Map.from(school);
        schoolData.remove('queuedAt');

        final res = await http.post(
          Uri.parse('${AppUrl.url}/schools'),
          headers: headers,
          body: jsonEncode(schoolData),
        );

        if (res.statusCode != 201 && res.statusCode != 200) {
          debugPrint('Sync failed for school: ${res.statusCode}');
          failed.add(school);
        } else {
          debugPrint('Successfully synced school: ${school['school_code']}');
        }
      } catch (e) {
        debugPrint('Sync failed for one school: $e');
        failed.add(school);
      }
    }

    // Update pending queue with failed items
    await Hive.box(LocalStorageService.pendingSchoolsBox).put('pending', failed);

    if (failed.isEmpty) {
      await LocalStorageService.clearPendingSchools();
      debugPrint('All pending schools synced successfully');
    } else {
      debugPrint('${failed.length} schools failed to sync');
    }
  }

  // Get count of pending schools
  int getPendingSchoolsCount() {
    return LocalStorageService.getPendingSchools().length;
  }

  // Clear all pending schools (use with caution)
  Future<void> clearAllPendingSchools() async {
    await LocalStorageService.clearPendingSchools();
  }

  // Manual retry for failed syncs
  Future<void> retryFailedSyncs(BuildContext context) async {
    final isOnline = await LocalStorageService.isOnline();
    if (!isOnline) return;

    await _syncPendingSchools(context);
  }

  // Refresh specific dropdown category
  Future<void> refreshCounties(BuildContext context) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final headers = auth.getAuthHeaders();
    final isOnline = await LocalStorageService.isOnline();

    if (!isOnline) return;

    try {
      final res = await http.get(Uri.parse('${AppUrl.url}/counties'), headers: headers);
      if (res.statusCode == 200) {
        final dynamic decoded = jsonDecode(res.body);
        if (decoded is List) {
          _counties = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } else if (decoded is Map && decoded['data'] is List) {
          _counties = (decoded['data'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }

        // Update cache
        final cached = LocalStorageService.getCachedDropdowns();
        cached['counties'] = _counties;
        await LocalStorageService.cacheDropdowns(cached);

        notifyListeners();
      }
    } catch (e) {
      debugPrint('Refresh counties error: $e');
    }
  }

  // Refresh levels
  Future<void> refreshLevels(BuildContext context) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final headers = auth.getAuthHeaders();
    final isOnline = await LocalStorageService.isOnline();

    if (!isOnline) return;

    try {
      final res = await http.get(Uri.parse('${AppUrl.url}/school-levels'), headers: headers);
      if (res.statusCode == 200) {
        final dynamic decoded = jsonDecode(res.body);
        if (decoded is List) {
          _levels = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } else if (decoded is Map && decoded['data'] is List) {
          _levels = (decoded['data'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }

        // Update cache
        final cached = LocalStorageService.getCachedDropdowns();
        cached['levels'] = _levels;
        await LocalStorageService.cacheDropdowns(cached);

        notifyListeners();
      }
    } catch (e) {
      debugPrint('Refresh levels error: $e');
    }
  }

  // Refresh types
  Future<void> refreshTypes(BuildContext context) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final headers = auth.getAuthHeaders();
    final isOnline = await LocalStorageService.isOnline();

    if (!isOnline) return;

    try {
      final res = await http.get(Uri.parse('${AppUrl.url}/school-types'), headers: headers);
      if (res.statusCode == 200) {
        final dynamic decoded = jsonDecode(res.body);
        if (decoded is List) {
          _types = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } else if (decoded is Map && decoded['data'] is List) {
          _types = (decoded['data'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }

        // Update cache
        final cached = LocalStorageService.getCachedDropdowns();
        cached['types'] = _types;
        await LocalStorageService.cacheDropdowns(cached);

        notifyListeners();
      }
    } catch (e) {
      debugPrint('Refresh types error: $e');
    }
  }

  // Refresh ownerships
  Future<void> refreshOwnerships(BuildContext context) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final headers = auth.getAuthHeaders();
    final isOnline = await LocalStorageService.isOnline();

    if (!isOnline) return;

    try {
      final res = await http.get(Uri.parse('${AppUrl.url}/school-ownerships'), headers: headers);
      if (res.statusCode == 200) {
        final dynamic decoded = jsonDecode(res.body);
        if (decoded is List) {
          _ownerships = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } else if (decoded is Map && decoded['data'] is List) {
          _ownerships = (decoded['data'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }

        // Update cache
        final cached = LocalStorageService.getCachedDropdowns();
        cached['ownerships'] = _ownerships;
        await LocalStorageService.cacheDropdowns(cached);

        notifyListeners();
      }
    } catch (e) {
      debugPrint('Refresh ownerships error: $e');
    }
  }
}