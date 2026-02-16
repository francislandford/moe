import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'dart:convert';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_url.dart';
import '../../../../core/services/local_storage_service.dart';
import '../../../../core/widgets/custom_app_bar.dart';
import '../../../../core/widgets/loading_overlay.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class MySchoolsPage extends StatefulWidget {
  const MySchoolsPage({super.key});

  @override
  State<MySchoolsPage> createState() => _MySchoolsPageState();
}

class _MySchoolsPageState extends State<MySchoolsPage> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _schools = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Load from cache first (offline-first)
    _loadFromCache();
    // Then silently refresh if online (background)
    _refreshSchoolsIfOnline();
  }

  // Load schools from cache (offline-first) — always first
  void _loadFromCache() {
    final cachedSchools = LocalStorageService.getFromCache('my_schools');
    if (cachedSchools != null && cachedSchools is List) {
      _schools = cachedSchools.map((s) => Map<String, dynamic>.from(s)).toList();
    }

    if (mounted) setState(() {});
  }

  // Refresh schools silently if online (background, no blocking UI)
  Future<void> _refreshSchoolsIfOnline() async {
    final isOnline = await LocalStorageService.isOnline();
    if (!isOnline) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!auth.isAuthenticated || auth.token == null) {
      // Log error but don't show to user
      print('Auth error during background refresh');
      return;
    }

    final headers = auth.getAuthHeaders();

    try {
      print('Refreshing my schools from API (background)...');
      final res = await http.get(
        Uri.parse('${AppUrl.url}/my-schools'),
        headers: headers,
      );

      print('My Schools response: ${res.statusCode}');

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> schoolList = data['data'] ?? [];

        if (mounted) {
          setState(() {
            _schools = schoolList.map((s) => Map<String, dynamic>.from(s)).toList();
            _errorMessage = null;
          });

          // Cache fresh data
          await LocalStorageService.saveToCache('my_schools', schoolList);
        }
      }
    } catch (e) {
      // Log error but don't show to user
      print('Background refresh failed: $e → keeping existing cache');
      // No error message shown to user
    }
  }

  // Pull-to-refresh — full refresh (only called when user pulls)
  Future<void> _fetchMySchools() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!auth.isAuthenticated || auth.token == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Please log in to view your schools.';
      });
      return;
    }

    final headers = auth.getAuthHeaders();

    try {
      final isOnline = await LocalStorageService.isOnline();

      if (isOnline) {
        final res = await http.get(
          Uri.parse('${AppUrl.url}/my-schools'),
          headers: headers,
        );

        print('My Schools response: ${res.statusCode}');

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final List<dynamic> schoolList = data['data'] ?? [];

          if (mounted) {
            setState(() {
              _schools = schoolList.map((s) => Map<String, dynamic>.from(s)).toList();
              _errorMessage = null;
            });

            await LocalStorageService.saveToCache('my_schools', schoolList);
          }
        } else {
          // Log error but don't show detailed message to user
          print('Failed to load schools: ${res.statusCode}');
          if (mounted && _schools.isEmpty) {
            setState(() {
              _errorMessage = 'Unable to load schools. Please try again.';
            });
          }
        }
      } else {
        // Offline: already loaded from cache
        if (mounted) {
          setState(() {
            _errorMessage = 'Offline mode — showing cached schools';
          });
        }
      }
    } catch (e) {
      // Log error but don't show to user
      print('My Schools fetch error: $e');
      if (mounted && _schools.isEmpty) {
        setState(() {
          _errorMessage = 'Unable to load schools. Please check your connection.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // SINGLE modal method (no duplicates)
  void _showSchoolModal(Map<String, dynamic> school) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(school['school_name'] ?? 'Unnamed School'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _infoItemRow('School Code', school['school_code'] ?? 'N/A'),
                _infoItemRow('Level', school['school_level'] ?? 'N/A'),
                _infoItemRow('County', school['county'] ?? 'N/A'),
                _infoItemRow('District', school['district'] ?? 'N/A'),
                _infoItemRow('Community', school['community'] ?? 'N/A'),
                _infoItemRow('Principal', school['principal_name'] ?? 'N/A'),
                _infoItemRow('Contact', school['school_contact'] ?? 'N/A'),
                _infoItemRow('Email', school['email'] ?? 'N/A'),
                _infoItemRow('Year Established', school['year_establish']?.toString() ?? 'N/A'),
                _infoItemRow('Permit Status', school['permit'] ?? 'N/A'),
                _infoItemRow('Permit Number', school['permit_num'] ?? 'N/A'),
                _infoItemRow('TVET', school['tvet'] == 1 ? 'Yes' : 'No'),
                _infoItemRow('Accelerated', school['accelerated'] == 1 ? 'Yes' : 'No'),
                _infoItemRow('Alternative', school['alternative'] == 1 ? 'Yes' : 'No'),
                _infoItemRow('All Teachers Present', school['all_teacher_present'] ?? 'N/A'),
                _infoItemRow('Verification Comment', school['verify_comment'] ?? 'N/A'),
                _infoItemRow('Charges Fees', school['charge_fees'] ?? 'N/A'),
                _infoItemRow('Latitude', school['latitude']?.toString() ?? 'N/A'),
                _infoItemRow('Longitude', school['longitude']?.toString() ?? 'N/A'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        );
      },
    );
  }

  Widget _infoItemRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'My Submitted Schools',
        backgroundColor: AppColors.primary,
        textColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.home, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle, color: Colors.white, size: 40),
            onPressed: () => context.go('/sample-dashboard'),
          ),
        ],
      ),
      body: StreamBuilder<bool>(
        stream: LocalStorageService.onlineStatusStream,
        initialData: true,
        builder: (context, snapshot) {
          final bool isOnline = snapshot.data ?? true;

          return Column(
            children: [
              if (!isOnline)
                Container(
                  width: double.infinity,
                  color: Colors.orange.shade100,
                  padding: const EdgeInsets.all(12),
                  child: const Text(
                    'Offline Mode — Showing cached or pending schools',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w600),
                  ),
                ),

              // Mini Dashboard Header
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: AppColors.primary.withOpacity(0.2),
                      child: Icon(
                        Icons.school_rounded,
                        color: AppColors.primary,
                        size: 36,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total Schools Submitted',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                        Text(
                          '${_schools.length}',
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Expanded(
                child: LoadingOverlay(
                  isLoading: _isLoading,
                  child: RefreshIndicator(
                    onRefresh: _fetchMySchools,
                    child: _buildBody(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.red, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_schools.isEmpty && !_isLoading) {
      return const Center(
        child: Text(
          'No schools submitted yet.\nPull down to refresh.',
          style: TextStyle(fontSize: 16, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _schools.length,
      itemBuilder: (context, index) {
        final school = _schools[index];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withOpacity(0.2),
              child: const Icon(
                Icons.school_rounded,
                color: AppColors.primary,
              ),
            ),
            title: Text(
              school['school_name'] ?? 'Unnamed School',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('Code: ${school['school_code'] ?? 'N/A'}'),
                Text('Level: ${school['school_level'] ?? 'N/A'}'),
                Text('County/District: ${school['county'] ?? 'N/A'} / ${school['district'] ?? 'N/A'}'),
              ],
            ),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            onTap: () => _showSchoolModal(school),
          ),
        );
      },
    );
  }
}