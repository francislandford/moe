import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moe/core/constants/app_url.dart';
import 'package:moe/core/services/local_storage_service.dart';
import 'package:crypto/crypto.dart';

class AuthProvider with ChangeNotifier {
  static final String _baseUrl = AppUrl.url;
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'auth_user';
  static const String _offlineTokenPrefix = 'offline_';

  final _storage = const FlutterSecureStorage();

  String? _token;
  Map<String, dynamic>? _user;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isOfflineMode = false;

  bool get isAuthenticated => _token != null && _token!.isNotEmpty;
  bool get isLoading => _isLoading;
  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  String? get errorMessage => _errorMessage;
  bool get isOfflineMode => _isOfflineMode;
  bool get isOfflineSession => _token != null && _token!.startsWith(_offlineTokenPrefix);

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

  // Load data from secure storage on app start
  Future<void> _loadData() async {
    _isLoading = true;
    notifyListeners();

    try {
      _token = await _storage.read(key: _tokenKey);
      debugPrint('Loaded token from storage: ${_token != null ? "Token exists" : "No token"}');

      if (_token != null && _token!.startsWith(_offlineTokenPrefix)) {
        _isOfflineMode = true;
        debugPrint('📱 Loaded offline session');
      }

      final userJson = await _storage.read(key: _userKey);
      if (userJson != null) {
        _user = jsonDecode(userJson) as Map<String, dynamic>;
        debugPrint('Loaded user from storage: ${_user!['name'] ?? 'Unknown'}');
      }

      final prefs = await SharedPreferences.getInstance();
      _onboardingCompleted = prefs.getBool('onboarding_completed') ?? false;
    } catch (e) {
      debugPrint('Error loading auth data: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  // Helper method to check internet connection
  Future<bool> _hasInternetConnection() async {
    try {
      final result = await http.get(
        Uri.parse('https://www.google.com'),
      ).timeout(const Duration(seconds: 3));
      return result.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Helper method to hash password with SHA256
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // Main login method with offline support
  // Main login method with offline support
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      debugPrint('Attempting online login with: $email');

      // Try online login first
      final response = await http.post(
        Uri.parse('$_baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.trim(),
          'password': password,
        }),
      ).timeout(const Duration(seconds: 10), onTimeout: () {
        throw Exception('Connection timeout');
      });

      debugPrint('Login response status: ${response.statusCode}');
      debugPrint('Login response body: ${response.body}');

      // Parse response body ONCE
      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        _token = responseData['token']?.toString();
        _user = responseData['user'] as Map<String, dynamic>?;
        _isOfflineMode = false;

        if (_token != null && _token!.isNotEmpty) {
          // ALWAYS store in secure storage
          await _storage.write(key: _tokenKey, value: _token);
          if (_user != null) {
            await _storage.write(key: _userKey, value: jsonEncode(_user));
          }
          debugPrint('✅ Online token persisted to secure storage');
          _isLoading = false;
          notifyListeners();
          return true;
        }
      } else {
        // Extract error message for non-200 responses
        if (responseData is Map) {
          // Handle message format (like your 401 response)
          if (responseData.containsKey('message')) {
            _errorMessage = responseData['message'].toString();
          }
          // Handle errors format (like validation errors)
          else if (responseData.containsKey('errors')) {
            final errors = responseData['errors'];
            if (errors is Map && errors.isNotEmpty) {
              // Get the first error message
              final firstErrorKey = errors.keys.first;
              final firstErrorValue = errors[firstErrorKey];
              if (firstErrorValue is List && firstErrorValue.isNotEmpty) {
                _errorMessage = firstErrorValue.first.toString();
              } else if (firstErrorValue is String) {
                _errorMessage = firstErrorValue;
              } else {
                _errorMessage = 'Validation failed';
              }
            } else {
              _errorMessage = 'Validation failed';
            }
          }
          // Handle error format
          else if (responseData.containsKey('error')) {
            _errorMessage = responseData['error'].toString();
          }
          else {
            _errorMessage = 'Login failed. Please check your credentials.';
          }
        } else {
          _errorMessage = 'Login failed. Please check your credentials.';
        }
      }

      _isLoading = false;
      notifyListeners();
      return false;

    } catch (e) {
      debugPrint('Login exception: $e');

      // Try offline login when network error occurs
      debugPrint('Attempting offline login...');
      final offlineSuccess = await _offlineLogin(email, password);

      if (offlineSuccess) {
        _isLoading = false;
        notifyListeners();
        return true;
      }

      _errorMessage = 'Network error. Please check your connection.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  // Offline login with SHA256 password verification - uses existing token
  Future<bool> _offlineLogin(String email, String password) async {
    try {
      // First check if we already have a token in storage
      final existingToken = await _storage.read(key: _tokenKey);
      final existingUserJson = await _storage.read(key: _userKey);

      // If we have existing credentials, validate them
      if (existingToken != null && existingToken.isNotEmpty && existingUserJson != null) {
        final existingUser = jsonDecode(existingUserJson) as Map<String, dynamic>;

        // Verify the email matches
        final storedEmail = existingUser['email']?.toString().toLowerCase() ?? '';
        final storedUsername = existingUser['username']?.toString().toLowerCase() ?? '';
        final inputEmail = email.trim().toLowerCase();

        if (storedEmail == inputEmail || storedUsername == inputEmail) {
          // Email matches, now verify password against cached users
          final cachedUsers = LocalStorageService.getFromCache('users');

          if (cachedUsers != null && cachedUsers is List) {
            // Find user in cached users to verify password
            final cachedUser = (cachedUsers as List).firstWhere(
                  (user) {
                final userEmail = user['email']?.toString().toLowerCase() ?? '';
                final username = user['username']?.toString().toLowerCase() ?? '';
                return userEmail == inputEmail || username == inputEmail;
              },
              orElse: () => null,
            );

            if (cachedUser != null) {
              final hashedPassword = _hashPassword(password);
              final storedPassword = cachedUser['password']?.toString() ?? '';

              if (storedPassword == hashedPassword) {
                debugPrint('✅ Password verified for existing session');

                // Use the existing token and user data
                _token = existingToken;
                _user = existingUser;
                _isOfflineMode = existingToken.startsWith(_offlineTokenPrefix);

                notifyListeners();
                return true;
              }
            }
          }
        }
      }

      // If no existing token or validation fails, try to find user in cached users
      debugPrint('No existing valid session found, checking cached users...');

      // Get cached users from preloaded data
      final cachedUsers = LocalStorageService.getFromCache('users');

      if (cachedUsers == null || cachedUsers is! List) {
        debugPrint('No cached users found for offline login');
        return false;
      }

      // Hash the input password for comparison
      final hashedPassword = _hashPassword(password);

      // Find user with matching email/username and password hash
      final userData = (cachedUsers as List).firstWhere(
            (user) {
          final userEmail = user['email']?.toString().toLowerCase() ?? '';
          final username = user['username']?.toString().toLowerCase() ?? '';
          final inputEmail = email.trim().toLowerCase();

          // Check if email/username matches
          final emailMatches = userEmail == inputEmail || username == inputEmail;
          if (!emailMatches) return false;

          // Check password hash
          final storedPassword = user['password']?.toString() ?? '';
          return storedPassword == hashedPassword;
        },
        orElse: () => null,
      );

      if (userData == null) {
        debugPrint('User not found or password incorrect in cached data');
        return false;
      }

      debugPrint('✅ Offline login successful for: $email');

      // Check if we already have a token for this user in storage
      if (existingToken != null && existingToken.isNotEmpty && existingUserJson != null) {
        final existingUser = jsonDecode(existingUserJson) as Map<String, dynamic>;
        final existingUserId = existingUser['id']?.toString();
        final newUserId = userData['id']?.toString();

        if (existingUserId == newUserId) {
          // Same user, reuse existing token
          _token = existingToken;
          _user = existingUser;
          _isOfflineMode = existingToken.startsWith(_offlineTokenPrefix);

          debugPrint('✅ Reused existing token for user: $email');
          notifyListeners();
          return true;
        }
      }

      // Create a new session token only if no existing token exists
      // This is a fallback for first-time offline login
      _token = '${_offlineTokenPrefix}${DateTime.now().millisecondsSinceEpoch}';
      _user = Map<String, dynamic>.from(userData);
      _isOfflineMode = true;

      // Remove sensitive data before storing
      _user!.remove('password');

      // Store in secure storage
      await _storage.write(key: _tokenKey, value: _token);
      await _storage.write(key: _userKey, value: jsonEncode(_user));

      debugPrint('✅ New offline token created and persisted for user: $email');

      return true;

    } catch (e) {
      debugPrint('Offline login error: $e');
      return false;
    }
  }
  // Updated logout method - only clears token when online
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    // Check if we have internet connection
    final hasInternet = await _hasInternetConnection();

    if (!hasInternet) {
      // Offline logout - KEEP THE TOKEN IN STORAGE, just clear state
      debugPrint('⚠️ Logging out while offline - keeping token in secure storage');

      // Clear only the in-memory state, NOT secure storage
      _token = null;
      _user = null;
      _errorMessage = null;
      _isOfflineMode = false;

      _isLoading = false;
      notifyListeners();
      return;
    }

    // Online logout - attempt to notify server and clear everything
    try {
      if (_token != null && !_isOfflineMode) {
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
    } finally {
      // Only clear secure storage when online logout succeeds
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _userKey);
      _token = null;
      _user = null;
      _errorMessage = null;
      _isOfflineMode = false;
    }

    _isLoading = false;
    notifyListeners();
  }

  // Method to check if token exists in storage
  Future<bool> hasStoredToken() async {
    final token = await _storage.read(key: _tokenKey);
    return token != null && token.isNotEmpty;
  }

  // Method to restore session from storage (useful after app restart)
  Future<bool> restoreSession() async {
    try {
      final storedToken = await _storage.read(key: _tokenKey);
      final storedUser = await _storage.read(key: _userKey);

      if (storedToken != null && storedToken.isNotEmpty && storedUser != null) {
        _token = storedToken;
        _user = jsonDecode(storedUser) as Map<String, dynamic>;
        _isOfflineMode = _token!.startsWith(_offlineTokenPrefix);
        debugPrint('✅ Session restored for user: ${_user!['name'] ?? 'Unknown'}');
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Error restoring session: $e');
    }
    return false;
  }

  // Method to check if offline login is available
  bool isOfflineLoginAvailable() {
    try {
      final cachedUsers = LocalStorageService.getFromCache('users');
      return cachedUsers != null && cachedUsers is List && cachedUsers.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking offline login availability: $e');
      return false;
    }
  }

  // Method to get cached users (for debugging)
  List<Map<String, dynamic>>? getCachedUsers() {
    try {
      final cachedUsers = LocalStorageService.getFromCache('users');
      if (cachedUsers != null && cachedUsers is List) {
        return cachedUsers.map((user) => Map<String, dynamic>.from(user)).toList();
      }
    } catch (e) {
      debugPrint('Error getting cached users: $e');
    }
    return null;
  }

  // Password reset methods
  Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      final response = await http.post(
        Uri.parse('${AppUrl.url}/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      final data = jsonDecode(response.body);
      debugPrint('Forgot password response: $data');

      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message'] ?? 'Reset code sent'};
      } else {
        String errorMessage = 'Failed to send code';

        if (data is Map) {
          if (data.containsKey('message')) {
            errorMessage = data['message'].toString();
          } else if (data.containsKey('error')) {
            errorMessage = data['error'].toString();
          } else if (data.containsKey('errors')) {
            final errors = data['errors'];
            if (errors is Map && errors.isNotEmpty) {
              final firstError = errors.values.first;
              if (firstError is List && firstError.isNotEmpty) {
                errorMessage = firstError.first.toString();
              }
            }
          }
        }

        return {'success': false, 'message': errorMessage};
      }
    } catch (e) {
      debugPrint('Forgot password exception: $e');
      return {
        'success': false,
        'message': 'Error: ${e.toString()}'
      };
    }
  }

  Future<Map<String, dynamic>> verifyResetCode(String email, String code) async {
    try {
      final response = await http.post(
        Uri.parse('${AppUrl.url}/verify-reset-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'code': code}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Invalid code'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  Future<Map<String, dynamic>> resetPassword(
      String email,
      String code,
      String password,
      String passwordConfirmation
      ) async {
    try {
      debugPrint('🔄 Resetting password for email: $email');

      final response = await http.post(
        Uri.parse('${AppUrl.url}/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'code': code,
          'password': password,
          'password_confirmation': passwordConfirmation,
        }),
      );

      debugPrint('📥 Response status: ${response.statusCode}');

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        debugPrint('✅ Password reset successful');
        return {
          'success': true,
          'message': data['message'] ?? 'Password reset successfully'
        };
      } else {
        String errorMessage = 'Failed to reset password (Status: ${response.statusCode})';

        if (data is Map) {
          if (data.containsKey('message')) {
            errorMessage = data['message'].toString();
          } else if (data.containsKey('error')) {
            errorMessage = data['error'].toString();
          } else if (data.containsKey('errors')) {
            final errors = data['errors'];
            if (errors is Map) {
              final firstErrorKey = errors.keys.first;
              final firstErrorValue = errors[firstErrorKey];
              if (firstErrorValue is List && firstErrorValue.isNotEmpty) {
                errorMessage = firstErrorValue.first.toString();
              } else if (firstErrorValue is String) {
                errorMessage = firstErrorValue;
              }
            }
          }
        }

        debugPrint('❌ Password reset failed: $errorMessage');
        return {'success': false, 'message': errorMessage};
      }
    } on http.ClientException catch (e) {
      debugPrint('🌐 Network error: $e');
      return {
        'success': false,
        'message': 'Connection error: ${e.message}'
      };
    } on FormatException catch (e) {
      debugPrint('📄 JSON parsing error: $e');
      return {
        'success': false,
        'message': 'Invalid response format from server'
      };
    } catch (e) {
      debugPrint('💥 Unexpected error: $e');
      return {
        'success': false,
        'message': 'Error: ${e.toString()}'
      };
    }
  }

  Future<Map<String, dynamic>> resendResetCode(String email) async {
    try {
      final response = await http.post(
        Uri.parse('${AppUrl.url}/resend-reset-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to resend code'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  Future<void> completeOnboarding() async {
    _onboardingCompleted = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
    notifyListeners();
  }

  Map<String, String> getAuthHeaders() {
    return {
      if (_token != null && !_isOfflineMode) 'Authorization': 'Bearer $_token',
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