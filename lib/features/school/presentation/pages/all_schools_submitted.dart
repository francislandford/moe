import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_url.dart';
import '../../../../core/services/local_storage_service.dart';
import '../../../../core/services/parent_local_storage_service.dart';
import '../../../../core/services/student_local_storage_service.dart';
import '../../../../core/services/textbooks_teaching_local_storage.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../core/widgets/custom_app_bar.dart';
import '../../../../core/widgets/loading_overlay.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/school_provider.dart';

class MySubmittedSchoolsPage extends StatefulWidget {
  const MySubmittedSchoolsPage({super.key});

  @override
  State<MySubmittedSchoolsPage> createState() => _MySubmittedSchoolsPageState();
}

class _MySubmittedSchoolsPageState extends State<MySubmittedSchoolsPage> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _schools = [];
  String? _errorMessage;

  static const Map<String, dynamic> sampleSchoolData = {
    'schoolName': 'St Francis High School',
    'schoolCode': 'MOE-188-011',
    'level': 'ECE',
    'firstAssessment': 'No',
  };

  Map<String, int> _offlineCounts = {
    'schools': 0,
    'assessments': 0,
    'documentChecks': 0,
    'leadership': 0,
    'infrastructure': 0,
    'classroom': 0,
    'parents': 0,
    'students': 0,
    'textbooks': 0,
  };

  final Map<String, Map<String, String>> _tableRoutes = {
    'staff': {'route': '/assessment-2', 'name': 'Staff'},
    'doc_check': {'route': '/document-check', 'name': 'Document Check'},
    'fees_paid': {'route': '/assessment-2', 'name': 'Fees Paid'},
    'leadership': {'route': '/leadership', 'name': 'Leadership'},
    'req_teachers': {'route': '/assessment-2', 'name': 'Required Teachers'},
    'verify_students': {'route': '/assessment-2', 'name': 'Verify Students'},
    'classroom': {'route': '/classroom', 'name': 'Classroom'},
  };

  @override
  void initState() {
    super.initState();
    _loadFromCache();
    _loadOfflineCounts();
    _refreshSchoolsIfOnline();
  }

  void _loadFromCache() {
    final cachedSchools = LocalStorageService.getFromCache('my_schools');
    if (cachedSchools != null && cachedSchools is List) {
      _schools = cachedSchools.map((s) => Map<String, dynamic>.from(s)).toList();
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadOfflineCounts() async {
    final counts = {
      'schools': LocalStorageService.getPendingSchools().length,
      'assessments': LocalStorageService.getPendingAssessments().length,
      'documentChecks': LocalStorageService.getPendingDocumentChecks().length,
      'leadership': LocalStorageService.getPendingLeadership().length,
      'infrastructure': LocalStorageService.getPendingInfrastructure().length,
      'classroom': LocalStorageService.getPendingClassroomObservation().length,
      'parents': (await ParentLocalStorageService.getPending()).length,
      'students': (await StudentLocalStorageService.getPending()).length,
      'textbooks': (await TextbooksTeachingLocalStorageService.getPending()).length,
    };

    if (mounted) {
      setState(() {
        _offlineCounts = counts;
      });
    }
  }

  int get _totalOfflineCount {
    if (_offlineCounts.isEmpty) return 0;
    return _offlineCounts.values.fold(0, (sum, count) => sum + count);
  }

  Future<void> _refreshSchoolsIfOnline() async {
    if (!mounted) return;

    final isOnline = await LocalStorageService.isOnline();
    if (!isOnline) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!auth.isAuthenticated || auth.token == null) {
      debugPrint('Auth error during background refresh');
      return;
    }

    final headers = auth.getAuthHeaders();

    try {
      final res = await http.get(
        Uri.parse('${AppUrl.url}/my-schools'),
        headers: headers,
      );

      if (!mounted) return;

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> schoolList = data['data'] ?? [];

        setState(() {
          _schools = schoolList.map((s) => Map<String, dynamic>.from(s)).toList();
          _errorMessage = null;
        });

        await LocalStorageService.saveToCache('my_schools', schoolList);
      }
    } catch (e) {
      debugPrint('Background refresh failed: $e');
    }
  }

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

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final List<dynamic> schoolList = data['data'] ?? [];

          setState(() {
            _schools = schoolList.map((s) => Map<String, dynamic>.from(s)).toList();
            _errorMessage = null;
          });

          await LocalStorageService.saveToCache('my_schools', schoolList);
        } else {
          if (_schools.isEmpty) {
            setState(() {
              _errorMessage = 'Unable to load schools. Please try again.';
            });
          }
        }
      } else {
        setState(() {
          _errorMessage = 'Offline mode — showing cached schools';
        });
      }
    } catch (e) {
      debugPrint('My Schools fetch error: $e');
      if (_schools.isEmpty) {
        setState(() {
          _errorMessage = 'Unable to load schools. Please check your connection.';
        });
      }
    } finally {
      await _loadOfflineCounts();
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

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
    final missingTables = (result['missing_tables'] as List<dynamic>?)?.cast<String>() ?? [];

    if (isComplete) {
      _showCannotDeleteDialog(schoolName);
    } else {
      _showIncompleteSchoolDialog(
        school,
        missingTables,
        schoolCode,
        schoolName,
        schoolLevel,
      );
    }
  }

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

  void _navigateToMissingPage(
      String tableName,
      String schoolCode,
      String schoolName,
      String schoolLevel,
      ) {
    final routeInfo = _tableRoutes[tableName];
    if (routeInfo == null) return;

    final route = routeInfo['route']!;

    if (tableName == 'classroom') {
      context.push(
        '/classroom',
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

  void _showIncompleteSchoolDialog(
      Map<String, dynamic> school,
      List<String> missingTables,
      String schoolCode,
      String schoolName,
      String schoolLevel,
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
              Text(
                'Code: $schoolCode',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'This school is incomplete. Tap on any missing section to add data:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ...missingTables.map((table) {
                final displayName =
                    _tableRoutes[table]?['name'] ?? table.replaceAll('_', ' ').toUpperCase();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
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
              }),
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
                  Navigator.pop(context);
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

  void _showDeleteConfirmationDialog(
      Map<String, dynamic> school,
      List<String> missingTables,
      ) {
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
              Text(
                'School: $schoolName',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('Code: $schoolCode'),
              const SizedBox(height: 16),
              const Text(
                'This school is incomplete. Missing data in:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...missingTables.map(
                    (table) => Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.warning, color: Colors.orange, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(table.replaceAll('_', ' '))),
                    ],
                  ),
                ),
              ),
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
              Navigator.pop(context);
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
        const SnackBar(
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

  void _showSchoolModal(Map<String, dynamic> school) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _checkSchoolCompleteness(school);
            },
            icon: const Icon(Icons.check_circle_outline, color: AppColors.primary),
            label: const Text(
              'Check Status',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _infoItemRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildDashboardCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required Color color,
    required String route,
    required int badgeCount,
  }) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;

    return GestureDetector(
      onTap: () {
        context.push(route, extra: sampleSchoolData).then((_) => _loadOfflineCounts());
      },
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        color: isDark ? Colors.grey[850] : Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 28, color: color),
              const SizedBox(height: 8),
              Flexible(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              if (badgeCount > 0) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badgeCount > 99 ? '99+' : badgeCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardSection() {
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.primary.withOpacity(0.2),
                child: const Icon(
                  Icons.school_rounded,
                  color: AppColors.primary,
                  size: 32,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total Schools Submitted',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      '${_schools.length}',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Offline: $_totalOfflineCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_errorMessage != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 40),
          Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.red, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    if (_schools.isEmpty && !_isLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: const [
          SizedBox(height: 40),
          Text(
            'No schools submitted yet.\nPull down to refresh.',
            style: TextStyle(fontSize: 16, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh',
            onPressed: () async {
              await _loadOfflineCounts();
              await _fetchMySchools();
            },
          ),
        ],
      ),
      body: StreamBuilder<bool>(
        stream: LocalStorageService.onlineStatusStream,
        initialData: LocalStorageService.currentOnlineStatus,
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
                    style: TextStyle(
                      color: Colors.deepOrange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              _buildDashboardSection(),
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
}