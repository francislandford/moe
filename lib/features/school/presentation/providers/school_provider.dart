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

  // Track district loading state separately
  bool _isLoadingDistricts = false;
  bool get isLoadingDistricts => _isLoadingDistricts;

  // Track session school count for auto-generation
  int _sessionSchoolCount = 0;
  int get sessionSchoolCount => _sessionSchoolCount;

  List<Map<String, dynamic>> _counties = [];
  List<Map<String, dynamic>> _districts = [];
  List<Map<String, dynamic>> _allDistricts = [];
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

  // Store user's county
  String? _userCounty;
  String? get userCounty => _userCounty;

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setDistrictLoading(bool value) {
    _isLoadingDistricts = value;
    notifyListeners();
  }

  // Public method to load from cache immediately
  void loadFromCache() {
    _loadFromCache();
  }

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

    // Load user county from cache
    final cachedUserCounty = LocalStorageService.getFromCache('user_county');
    if (cachedUserCounty != null) {
      _userCounty = cachedUserCounty as String;
      debugPrint('✅ Loaded user county from cache: $_userCounty');
    }

    _districts = [];
    notifyListeners();
  }

  // ─── Get count of schools submitted by the current user ─────────────
  Future<int> getUserSchoolCount(int userId, String token) async {
    try {
      int totalCount = 0;

      // 1. First, check if we have cached schools
      final cachedSchools = LocalStorageService.getFromCache('my_schools');
      if (cachedSchools != null && cachedSchools is List) {
        totalCount = cachedSchools.length;
        debugPrint('📊 Cached schools count: $totalCount');
      }

      // 2. If online, fetch fresh count from API
      final isOnline = await LocalStorageService.isOnline();
      if (isOnline && token.isNotEmpty) {
        try {
          final headers = {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          };

          final response = await http.get(
            Uri.parse('${AppUrl.url}/my-schools'),
            headers: headers,
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final List<dynamic> schoolList = data['data'] ?? [];
            totalCount = schoolList.length;

            // Update cache with fresh data
            await LocalStorageService.saveToCache('my_schools', schoolList);
            debugPrint('📊 API schools count: $totalCount');
          }
        } catch (e) {
          debugPrint('❌ Error fetching school count: $e');
          // Return cached count if API fails
        }
      }

      // 3. Also include pending schools from offline queue
      final pendingSchools = LocalStorageService.getPendingSchools();
      final userPendingCount = pendingSchools.where((school) {
        return school['user_id'] == userId;
      }).length;

      debugPrint('📊 Pending schools count: $userPendingCount');

      // Total = synced schools + pending schools
      return totalCount + userPendingCount;

    } catch (e) {
      debugPrint('❌ Error in getUserSchoolCount: $e');
      return 0;
    }
  }

  // ─── Get count without making API call (uses cache + pending) ──────
  int getCachedUserSchoolCount(int userId) {
    try {
      // Get from cache
      final cachedSchools = LocalStorageService.getFromCache('my_schools');
      int cachedCount = (cachedSchools != null && cachedSchools is List)
          ? cachedSchools.length
          : 0;

      // Add pending count
      final pendingSchools = LocalStorageService.getPendingSchools();
      final userPendingCount = pendingSchools.where((school) {
        return school['user_id'] == userId;
      }).length;

      return cachedCount + userPendingCount;

    } catch (e) {
      debugPrint('❌ Error in getCachedUserSchoolCount: $e');
      return 0;
    }
  }

  // ─── Refresh my schools cache ───────────────────────────────────────
  Future<void> refreshMySchools(String token) async {
    if (token.isEmpty) return;

    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    try {
      final response = await http.get(
        Uri.parse('${AppUrl.url}/my-schools'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> schoolList = data['data'] ?? [];
        await LocalStorageService.saveToCache('my_schools', schoolList);
        debugPrint('✅ Refreshed my-schools cache with ${schoolList.length} schools');
      }
    } catch (e) {
      debugPrint('❌ Failed to refresh my-schools: $e');
    }
  }

  // ─── Fetch user's county from API ──────────────────────────────────────
  Future<String?> fetchUserCounty(BuildContext context) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!auth.isAuthenticated || auth.token == null) {
      debugPrint('❌ Cannot fetch county: User not authenticated');
      return null;
    }

    final headers = auth.getAuthHeaders();
    final isOnline = await LocalStorageService.isOnline();

    if (!isOnline) {
      if (_userCounty != null) {
        debugPrint('📱 Offline: using cached user county: $_userCounty');
        return _userCounty;
      }
      return null;
    }

    try {
      final response = await http.get(
        Uri.parse('${AppUrl.url}/user/county'),
        headers: headers,
      );

      debugPrint('📥 User county response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        String? county;
        if (data is String) {
          county = data;
        } else if (data is Map && data.containsKey('county')) {
          county = data['county'] as String?;
        } else if (data is Map && data.containsKey('data')) {
          if (data['data'] is Map && data['data'].containsKey('county')) {
            county = data['data']['county'] as String?;
          } else if (data['data'] is String) {
            county = data['data'] as String?;
          }
        }

        if (county != null && county.isNotEmpty) {
          debugPrint('✅ Fetched user county: $county');
          _userCounty = county;
          await LocalStorageService.saveToCache('user_county', county);

          final matchingCounty = _counties.firstWhere(
                (c) => c['county']?.toString().toLowerCase() == county?.toLowerCase(),
            orElse: () => <String, dynamic>{},
          );

          if (matchingCounty.isNotEmpty) {
            _selectedCounty = county;
          }

          notifyListeners();
          return county;
        }
      }
    } catch (e) {
      debugPrint('❌ Error fetching user county: $e');
    }

    return _userCounty;
  }

  // ─── Fetch all dropdowns ─────────────────────────────────────────────
  Future<void> fetchDropdownData(BuildContext context) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final headers = auth.getAuthHeaders();
    final isOnline = await LocalStorageService.isOnline();

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

        // All districts
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

        if (_selectedCounty != null) {
          _filterDistrictsByCounty(_selectedCounty!);
        }

        notifyListeners();
      } catch (e) {
        debugPrint('Online fetch failed: $e → using existing cache');
      }
    }
  }

  // ─── Fetch ALL districts ─────────────────────────────────────────────
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
        debugPrint('✅ Loaded ${_allDistricts.length} districts from API');
      } else {
        debugPrint('Districts fetch failed with status: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('Fetch all districts error: $e');
    }
  }

  void _filterDistrictsByCounty(String county) {
    _districts = _allDistricts
        .where((d) {
      final districtCounty = (d['county'] as String?)?.trim().toLowerCase() ?? '';
      final selectedCounty = county.trim().toLowerCase();
      return districtCounty == selectedCounty;
    })
        .toList();
    debugPrint('✅ Filtered ${_districts.length} districts for county: $county');
  }

  // ─── Fetch districts ─────────────────────────────────────────────────
  Future<void> fetchDistricts(String? county, BuildContext context) async {
    if (county == null || county.isEmpty) {
      _districts = [];
      notifyListeners();
      return;
    }

    _selectedCounty = county;
    _setDistrictLoading(true);
    _filterDistrictsByCounty(county);
    notifyListeners();

    final isOnline = await LocalStorageService.isOnline();
    if (isOnline) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final headers = auth.getAuthHeaders();

      try {
        await fetchAllDistricts(headers);
        _filterDistrictsByCounty(county);
        notifyListeners();

        final updatedCached = LocalStorageService.getCachedDropdowns();
        updatedCached['all_districts'] = _allDistricts;
        await LocalStorageService.cacheDropdowns(updatedCached);
      } catch (e) {
        debugPrint('Background district refresh failed: $e → UI keeps using cache');
      } finally {
        _setDistrictLoading(false);
      }
    } else {
      _setDistrictLoading(false);
    }
  }

  // ─── Create school ───────────────────────────────────────────────────
  Future<Map<String, dynamic>> createSchool(Map<String, dynamic> data, BuildContext context) async {
    _setLoading(true);
    final auth = Provider.of<AuthProvider>(context, listen: false);

    if (!auth.isAuthenticated || auth.token == null) {
      _setLoading(false);
      return {
        'success': false,
        'message': 'Not authenticated',
      };
    }

    final headers = auth.getAuthHeaders();
    final token = auth.token!;
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
          incrementSessionSchoolCount();
          await _syncPendingSchools(context);

          // Refresh my-schools cache using the token
          await refreshMySchools(token);

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
        await LocalStorageService.savePendingSchool({
          ...data,
          'user_id': auth.userId,
          'queuedAt': DateTime.now().toIso8601String(),
        });
        incrementSessionSchoolCount();
        return {
          'success': true,
          'message': 'Saved offline — will sync when online',
          'offline': true,
          'data': data,
        };
      }
    } catch (e) {
      debugPrint('Create school error: $e');
      await LocalStorageService.savePendingSchool({
        ...data,
        'user_id': auth.userId,
        'queuedAt': DateTime.now().toIso8601String(),
      });
      incrementSessionSchoolCount();
      return {
        'success': true,
        'message': 'Network error — saved offline for later sync',
        'offline': true,
        'data': data,
      };
    } finally {
      _setLoading(false);
    }
  }

  // ─── Sync pending schools ────────────────────────────────────────────
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
        final Map<String, dynamic> schoolData = Map.from(school);
        schoolData.remove('queuedAt');
        schoolData.remove('user_id');

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

    await Hive.box(LocalStorageService.pendingSchoolsBox).put('pending', failed);

    if (failed.isEmpty) {
      await LocalStorageService.clearPendingSchools();
      debugPrint('All pending schools synced successfully');
    } else {
      debugPrint('${failed.length} schools failed to sync');
    }
  }

  // ─── Session school count methods ────────────────────────────────────
  void incrementSessionSchoolCount() {
    _sessionSchoolCount++;
    debugPrint('Session school count incremented to: $_sessionSchoolCount');
    notifyListeners();
  }

  void resetSessionSchoolCount() {
    _sessionSchoolCount = 0;
    debugPrint('Session school count reset');
  }

  int getPendingSchoolsCount() {
    return LocalStorageService.getPendingSchools().length;
  }

  Future<void> clearAllPendingSchools() async {
    await LocalStorageService.clearPendingSchools();
  }

  Future<void> retryFailedSyncs(BuildContext context) async {
    final isOnline = await LocalStorageService.isOnline();
    if (!isOnline) return;
    await _syncPendingSchools(context);
  }

  // ─── Refresh methods ─────────────────────────────────────────────────
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

        final cached = LocalStorageService.getCachedDropdowns();
        cached['counties'] = _counties;
        await LocalStorageService.cacheDropdowns(cached);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Refresh counties error: $e');
    }
  }

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

        final cached = LocalStorageService.getCachedDropdowns();
        cached['levels'] = _levels;
        await LocalStorageService.cacheDropdowns(cached);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Refresh levels error: $e');
    }
  }

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

        final cached = LocalStorageService.getCachedDropdowns();
        cached['types'] = _types;
        await LocalStorageService.cacheDropdowns(cached);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Refresh types error: $e');
    }
  }

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