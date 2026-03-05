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
import '../providers/school_provider.dart';

class MySchoolsPage extends StatefulWidget {
  const MySchoolsPage({super.key});

  @override
  State<MySchoolsPage> createState() => _MySchoolsPageState();
}

class _MySchoolsPageState extends State<MySchoolsPage> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _schools = [];
  String? _errorMessage;

  // Map table names to routes and display names
  final Map<String, Map<String, String>> _tableRoutes = {
    'staff': {'route': '/assessment-2', 'name': 'Staff'},
    'doc_check': {'route': '/document-check', 'name': 'Document Check'},
    'fees_paid': {'route': '/assessment-2', 'name': 'Fees Paid'},
    'leadership': {'route': '/leadership', 'name': 'Leadership'},
    'parents': {'route': '/parents', 'name': 'Parents'},
    'req_teachers': {'route': '/assessment-2', 'name': 'Required Teachers'},
    'students': {'route': '/students', 'name': 'Students'},
    'textbooks': {'route': '/textbooks-teaching', 'name': 'Textbooks'},
    'verify_students': {'route': '/assessment-2', 'name': 'Verify Students'},
    'infrastructures': {'route': '/infrastructure', 'name': 'Infrastructure'},
    'classroom': {'route': '/classroom-1', 'name': 'Classroom'},
  };

  @override
  void initState() {
    super.initState();
    // Load from cache first (offline-first)
    _loadFromCache();
    // Then silently refresh if online (background)
    _refreshSchoolsIfOnline();
  }

  @override
  void dispose() {
    // Cancel any pending operations
    super.dispose();
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
    // Check if widget is still mounted before proceeding
    if (!mounted) return;

    final isOnline = await LocalStorageService.isOnline();
    if (!isOnline) return;

    // Get auth provider without using context in async gap
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!auth.isAuthenticated || auth.token == null) {
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

      // Check if widget is still mounted after async operation
      if (!mounted) return;

      print('My Schools response: ${res.statusCode}');

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> schoolList = data['data'] ?? [];

        setState(() {
          _schools = schoolList.map((s) => Map<String, dynamic>.from(s)).toList();
          _errorMessage = null;
        });

        // Cache fresh data
        await LocalStorageService.saveToCache('my_schools', schoolList);
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
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Please log in to view your schools.';
        });
      }
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

        if (!mounted) return;

        print('My Schools response: ${res.statusCode}');

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final List<dynamic> schoolList = data['data'] ?? [];

          setState(() {
            _schools = schoolList.map((s) => Map<String, dynamic>.from(s)).toList();
            _errorMessage = null;
          });

          await LocalStorageService.saveToCache('my_schools', schoolList);
        } else {
          print('Failed to load schools: ${res.statusCode}');
          if (mounted && _schools.isEmpty) {
            setState(() {
              _errorMessage = 'Unable to load schools. Please try again.';
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = 'Offline mode — showing cached schools';
          });
        }
      }
    } catch (e) {
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

  // Check school completeness before showing delete option
  Future<void> _checkSchoolCompleteness(Map<String, dynamic> school) async {
    if (!mounted) return;

    final schoolCode = school['school_code'];
    final schoolName = school['school_name'] ?? 'Unnamed School';
    final schoolLevel = school['school_level'] ?? 'ECE';

    setState(() => _isLoading = true);

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final token = auth.token ?? '';

    final schoolProvider = Provider.of<SchoolProvider>(context, listen: false);
    final result = await schoolProvider.checkSchoolCompleteness(schoolCode, token);

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (!result['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Failed to check school status'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final isComplete = result['is_complete'] == true;
    // FIXED: Handle List<dynamic> properly
    final missingTables = (result['missing_tables'] as List<dynamic>?)?.cast<String>() ?? [];

    if (isComplete) {
      _showCannotDeleteDialog(schoolName);
    } else {
      _showIncompleteSchoolDialog(school, missingTables, schoolCode, schoolName, schoolLevel);
    }
  }

  // Show dialog for complete schools (cannot delete)
  void _showCannotDeleteDialog(String schoolName) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cannot Delete'),
        content: Text('$schoolName has complete data and cannot be deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  // Navigate to the appropriate page for missing data
  void _navigateToMissingPage(String tableName, String schoolCode, String schoolName, String schoolLevel) {
    final routeInfo = _tableRoutes[tableName];
    if (routeInfo == null) return;

    final route = routeInfo['route']!;

    // Handle special cases like classroom which has multiple options
    if (tableName == 'classroom') {
      // For classroom, navigate to classroom-1 by default
      context.push(
        '/classroom-1',
        extra: {
          'schoolCode': schoolCode,
          'schoolName': schoolName,
          'level': schoolLevel,
        },
      );
    } else {
      context.push(
        route,
        extra: {
          'schoolCode': schoolCode,
          'schoolName': schoolName,
          'level': schoolLevel,
        },
      );
    }
  }

  // Show dialog for incomplete schools with tappable missing tables
  void _showIncompleteSchoolDialog(
      Map<String, dynamic> school,
      List<String> missingTables,
      String schoolCode,
      String schoolName,
      String schoolLevel
      ) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Incomplete School: $schoolName'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Code: $schoolCode', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Text(
                'This school is incomplete. Tap on any missing section to add data:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              // Display missing tables as tappable buttons
              ...missingTables.map((table) {
                final displayName = _tableRoutes[table]?['name'] ?? table.replaceAll('_', ' ').toUpperCase();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context); // Close dialog
                      _navigateToMissingPage(table, schoolCode, schoolName, schoolLevel);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 45),
                    ),
                    child: Text('Add $displayName Data'),
                  ),
                );
              }).toList(),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'Or delete this incomplete school:',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // Close this dialog
                  _showDeleteConfirmationDialog(school, missingTables);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 45),
                ),
                child: const Text('Delete School Permanently'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  // Show delete confirmation for incomplete schools
  void _showDeleteConfirmationDialog(Map<String, dynamic> school, List<String> missingTables) {
    if (!mounted) return;

    final schoolCode = school['school_code'];
    final schoolName = school['school_name'] ?? 'Unnamed School';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete School?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('School: $schoolName', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Code: $schoolCode'),
              const SizedBox(height: 16),
              const Text(
                'This school is incomplete. Missing data in:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...missingTables.map((table) => Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.orange, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(table.replaceAll('_', ' '))),
                  ],
                ),
              )).toList(),
              const SizedBox(height: 16),
              const Text(
                'This action cannot be undone. All data related to this school will be permanently deleted.',
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog
              await _performDelete(schoolCode, schoolName);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete Permanently'),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  // Perform the actual deletion
  Future<void> _performDelete(String schoolCode, String schoolName) async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final token = auth.token ?? '';

    final schoolProvider = Provider.of<SchoolProvider>(context, listen: false);
    final result = await schoolProvider.deleteIncompleteSchool(schoolCode, token);

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (result['success'] == true) {
      setState(() {
        _schools.removeWhere((s) => s['school_code'] == schoolCode);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('School deleted successfully'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Failed to delete school'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // Updated modal method with delete button
  void _showSchoolModal(Map<String, dynamic> school) {
    if (!mounted) return;

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
            // Check Completeness Button
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context); // Close the modal first
                _checkSchoolCompleteness(school);
              },
              icon: const Icon(Icons.check_circle_outline, color: AppColors.primary),
              label: const Text(
                'Check Status',
                style: TextStyle(color: AppColors.primary),
              ),
            ),
            const SizedBox(width: 8),
            // Close Button
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
          // Online/Offline Indicator
          StreamBuilder<bool>(
            stream: LocalStorageService.onlineStatusStream,
            initialData: LocalStorageService.currentOnlineStatus,
            builder: (context, snapshot) {
              final bool isOnline = snapshot.data ?? true;
              return Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isOnline ? Colors.green : Colors.orange,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isOnline ? Icons.wifi : Icons.wifi_off,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isOnline ? 'Online' : 'Offline',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add_circle, color: Colors.white, size: 40),
            onPressed: () => context.go('/sample-dashboard'),
          ),
        ],
      ),
      body: StreamBuilder<bool>(
        stream: LocalStorageService.onlineStatusStream,
        initialData: LocalStorageService.currentOnlineStatus, // FIXED: Use current status
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
                    'You are offline. Showing cached or pending schools.',
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