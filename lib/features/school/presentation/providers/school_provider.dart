import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../../../core/constants/app_url.dart';
import '../../../../core/services/local_storage_service.dart';
import '../../../../core/services/data_preloader_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class SchoolProvider with ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isLoadingDistricts = false;
  bool get isLoadingDistricts => _isLoadingDistricts;

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

  String? _selectedCounty;
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

  // Load from cache using DataPreloaderService
  void loadFromCache() {
    _loadFromCache();
  }

  // Replace the _loadFromCache method with:
  void _loadFromCache() {
    _counties = DataPreloaderService.getCachedData('counties');
    _allDistricts = DataPreloaderService.getCachedData('all_districts');
    _levels = DataPreloaderService.getCachedData('levels');
    _types = DataPreloaderService.getCachedData('types');
    _ownerships = DataPreloaderService.getCachedData('ownerships');

    final cachedUserCounty = LocalStorageService.getFromCache('user_county');
    if (cachedUserCounty != null) {
      _userCounty = cachedUserCounty as String;
    }

    _districts = [];
    notifyListeners();
  }

  // Get user school count
  Future<int> getUserSchoolCount(int userId, String token) async {
    try {
      int totalCount = 0;

      final cachedSchools = LocalStorageService.getFromCache('my_schools');
      if (cachedSchools != null && cachedSchools is List) {
        totalCount = cachedSchools.length;
      }

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
            await LocalStorageService.saveToCache('my_schools', schoolList);
          }
        } catch (e) {
          debugPrint('❌ Error fetching school count: $e');
        }
      }

      final pendingSchools = LocalStorageService.getPendingSchools();
      final userPendingCount = pendingSchools.where((school) {
        return school['user_id'] == userId;
      }).length;

      return totalCount + userPendingCount;

    } catch (e) {
      debugPrint('❌ Error in getUserSchoolCount: $e');
      return 0;
    }
  }

  // Fetch user's county
  Future<String?> fetchUserCounty(BuildContext context) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!auth.isAuthenticated || auth.token == null) {
      return null;
    }

    final isOnline = await LocalStorageService.isOnline();

    if (!isOnline) {
      return _userCounty;
    }

    try {
      final headers = auth.getAuthHeaders();
      final response = await http.get(
        Uri.parse('${AppUrl.url}/user/county'),
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

        if (county != null && county.isNotEmpty) {
          _userCounty = county;
          await LocalStorageService.saveToCache('user_county', county);
          notifyListeners();
          return county;
        }
      }
    } catch (e) {
      debugPrint('❌ Error fetching user county: $e');
    }

    return _userCounty;
  }

  // Fetch all dropdowns (now uses DataPreloaderService cache)
  Future<void> fetchDropdownData(BuildContext context) async {
    final isOnline = await LocalStorageService.isOnline();

    if (isOnline) {
      // Just refresh from API, DataPreloaderService already has the data
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final headers = auth.getAuthHeaders();

      try {
        final countyRes = await http.get(Uri.parse('${AppUrl.url}/counties'), headers: headers);
        if (countyRes.statusCode == 200) {
          final dynamic decoded = jsonDecode(countyRes.body);
          _counties = _extractListFromResponse(decoded);
        }

        await fetchAllDistricts(headers);

        final levelRes = await http.get(Uri.parse('${AppUrl.url}/school-levels'), headers: headers);
        if (levelRes.statusCode == 200) {
          final dynamic decoded = jsonDecode(levelRes.body);
          _levels = _extractListFromResponse(decoded);
        }

        final typeRes = await http.get(Uri.parse('${AppUrl.url}/school-types'), headers: headers);
        if (typeRes.statusCode == 200) {
          final dynamic decoded = jsonDecode(typeRes.body);
          _types = _extractListFromResponse(decoded);
        }

        final ownRes = await http.get(Uri.parse('${AppUrl.url}/school-ownerships'), headers: headers);
        if (ownRes.statusCode == 200) {
          final dynamic decoded = jsonDecode(ownRes.body);
          _ownerships = _extractListFromResponse(decoded);
        }

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

  List<Map<String, dynamic>> _extractListFromResponse(dynamic data) {
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e)).toList();
    } else if (data is Map && data.containsKey('data')) {
      if (data['data'] is List) {
        return (data['data'] as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
    return [];
  }

  Future<void> fetchAllDistricts(Map<String, String> headers) async {
    try {
      final res = await http.get(
        Uri.parse('${AppUrl.url}/districts'),
        headers: headers,
      );

      if (res.statusCode == 200) {
        final dynamic decoded = jsonDecode(res.body);
        _allDistricts = _extractListFromResponse(decoded);
        debugPrint('✅ Loaded ${_allDistricts.length} districts from API');
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
  }

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

  // Create school method remains the same
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
          await _refreshMySchools(token);

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

  Future<void> _refreshMySchools(String token) async {
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
      }
    } catch (e) {
      debugPrint('❌ Failed to refresh my-schools: $e');
    }
  }

  Future<void> _syncPendingSchools(BuildContext context) async {
    final pending = LocalStorageService.getPendingSchools();
    if (pending.isEmpty) return;

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
          failed.add(school);
        }
      } catch (e) {
        debugPrint('Sync failed for one school: $e');
        failed.add(school);
      }
    }

    await Hive.box(LocalStorageService.pendingSchoolsBox).put('pending', failed);

    if (failed.isEmpty) {
      await LocalStorageService.clearPendingSchools();
    }
  }

  void incrementSessionSchoolCount() {
    _sessionSchoolCount++;
    notifyListeners();
  }

  void resetSessionSchoolCount() {
    _sessionSchoolCount = 0;
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
}