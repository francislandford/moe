import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moe/core/constants/app_url.dart';

class AuthProvider with ChangeNotifier {
  static final String _baseUrl = AppUrl.url;
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'auth_user';

  final _storage = const FlutterSecureStorage();

  String? _token;
  Map<String, dynamic>? _user;
  bool _isLoading = false;
  String? _errorMessage;

  bool get isAuthenticated => _token != null && _token!.isNotEmpty;
  bool get isLoading => _isLoading;
  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  String? get errorMessage => _errorMessage;

  int get userId {
    if (_user != null) {
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

  bool _onboardingCompleted = false;
  bool get isOnboardingCompleted => _onboardingCompleted;

  AuthProvider() {
    _loadData();
  }

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

  // Simplified login method
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      debugPrint('Attempting login with: $email');

      final response = await http.post(
        Uri.parse('$_baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.trim(),
          'password': password,
        }),
      );

      debugPrint('Login response status: ${response.statusCode}');
      debugPrint('Login response body: ${response.body}');

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        _token = responseData['token']?.toString();
        _user = responseData['user'] as Map<String, dynamic>?;

        if (_token != null && _token!.isNotEmpty) {
          await _storage.write(key: _tokenKey, value: _token);
          if (_user != null) {
            await _storage.write(key: _userKey, value: jsonEncode(_user));
          }
          _isLoading = false;
          notifyListeners();
          return true;
        }
      }

      // Extract error message
      if (responseData is Map) {
        if (responseData.containsKey('message')) {
          _errorMessage = responseData['message'].toString();
        } else if (responseData.containsKey('error')) {
          _errorMessage = responseData['error'].toString();
        } else {
          _errorMessage = 'Login failed. Please check your credentials.';
        }
      } else {
        _errorMessage = 'Login failed. Please check your credentials.';
      }

      _isLoading = false;
      notifyListeners();
      return false;

    } catch (e) {
      debugPrint('Login exception: $e');
      _errorMessage = 'Network error. Please check your connection.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

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
    _errorMessage = null;

    _isLoading = false;
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    _onboardingCompleted = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
    notifyListeners();
  }

  Map<String, String> getAuthHeaders() {
    return {
      if (_token != null) 'Authorization': 'Bearer $_token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  String getFormattedUserId() {
    final id = userId;
    if (id < 10) {
      return '00$id';
    } else if (id < 100) {
      return '0$id';
    } else {
      return id.toString();
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}