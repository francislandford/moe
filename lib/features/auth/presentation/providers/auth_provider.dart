import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moe/core/constants/app_url.dart'; // your AppUrl class

class AuthProvider with ChangeNotifier {
  // ────────────────────────────────────────────────
  // Config
  // ────────────────────────────────────────────────
  static final String _baseUrl = AppUrl.url;
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'auth_user';

  final _storage = const FlutterSecureStorage();

  String? _token;
  Map<String, dynamic>? _user;
  bool _isLoading = false;

  // Getters
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;
  bool get isLoading => _isLoading;
  String? get token => _token;
  Map<String, dynamic>? get user => _user;

  // NEW: Get user ID with proper formatting
  int get userId {
    // Try to get ID from user object - adjust the key based on your API response
    if (_user != null) {
      // Common keys for user ID in API responses
      if (_user!.containsKey('id')) {
        return _user!['id'] as int? ?? 0;
      } else if (_user!.containsKey('user_id')) {
        return _user!['user_id'] as int? ?? 0;
      } else if (_user!.containsKey('userId')) {
        return _user!['userId'] as int? ?? 0;
      }
    }
    return 0;
  }

  // Onboarding flag
  bool _onboardingCompleted = false;
  bool get isOnboardingCompleted => _onboardingCompleted;

  AuthProvider() {
    _loadData();
  }

  // ────────────────────────────────────────────────
  // Load saved auth & onboarding data
  // ────────────────────────────────────────────────
  Future<void> _loadData() async {
    _isLoading = true;
    notifyListeners();

    try {
      _token = await _storage.read(key: _tokenKey);

      final userJson = await _storage.read(key: _userKey);
      if (userJson != null) {
        _user = jsonDecode(userJson) as Map<String, dynamic>;
      }

      final prefs = await SharedPreferences.getInstance();
      _onboardingCompleted = prefs.getBool('onboarding_completed') ?? false;
    } catch (e) {
      debugPrint('Error loading auth data: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  // ────────────────────────────────────────────────
  // Login → returns true on success, false on failure
  // ────────────────────────────────────────────────
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.trim(),
          'password': password,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);

        _token = data['token']?.toString();
        _user = data['user'] as Map<String, dynamic>?;

        if (_token != null && _token!.isNotEmpty) {
          await _storage.write(key: _tokenKey, value: _token);
          if (_user != null) {
            await _storage.write(key: _userKey, value: jsonEncode(_user));
          }
          notifyListeners();
          return true;
        }
      }

      // Failed but no exception → e.g. 401/422
      debugPrint('Login failed with status: ${response.statusCode}');
      return false;

    } catch (e) {
      debugPrint('Login exception: $e');
      rethrow; // Let UI catch and show specific message
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ────────────────────────────────────────────────
  // Logout
  // ────────────────────────────────────────────────
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      if (_token != null) {
        await http.post(
          Uri.parse('$_baseUrl/logout'),
          headers: {
            'Authorization': 'Bearer $_token',
            'Content-Type': 'application/json',
          },
        );
      }
    } catch (e) {
      debugPrint('Logout error: $e');
    }

    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
    _token = null;
    _user = null;

    _isLoading = false;
    notifyListeners();
  }

  // ────────────────────────────────────────────────
  // Onboarding completion
  // ────────────────────────────────────────────────
  Future<void> completeOnboarding() async {
    _onboardingCompleted = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
    notifyListeners();
  }

  // ────────────────────────────────────────────────
  // Auth headers helper for future API calls
  // ────────────────────────────────────────────────
  Map<String, String> getAuthHeaders() {
    return {
      if (_token != null) 'Authorization': 'Bearer $_token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  // Optional: Get formatted user ID as string with leading zeros
  String getFormattedUserId() {
    final id = userId;
    if (id < 10) {
      return '00$id'; // 1 -> 001
    } else if (id < 100) {
      return '0$id'; // 23 -> 023
    } else {
      return id.toString(); // 123 -> 123
    }
  }
}