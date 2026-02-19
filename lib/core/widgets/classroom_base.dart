// classroom_base.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_url.dart';
import '../../../../core/widgets/custom_app_bar.dart';
import '../../../../core/widgets/loading_overlay.dart';
import '../../../../core/services/local_storage_service.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';

abstract class BaseClassroomPage extends StatefulWidget {
  final int classroomNumber;
  final String? schoolCode;
  final String? schoolName;
  final String? schoolLevel;

  const BaseClassroomPage({
    super.key,
    required this.classroomNumber,
    this.schoolCode,
    this.schoolName,
    this.schoolLevel,
  });
}

abstract class BaseClassroomPageState<T extends BaseClassroomPage> extends State<T> {
  bool _isLoading = false;
  bool _isFetchingDropdowns = false;
  bool _isSubmitting = false;

  // Controllers for this classroom
  late TextEditingController _teacherController;
  late TextEditingController _nbMaleController;
  late TextEditingController _nbFemaleController;

  // Selected values for this classroom
  String? _selectedGrade;
  String? _selectedSubject;

  // Scores for this classroom
  Map<String, int?> _scores = {};

  List<Map<String, dynamic>> _grades = [];
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _questions = [];

  String? get schoolCode => widget.schoolCode;
  String? get schoolName => widget.schoolName;
  String? get schoolLevel => widget.schoolLevel;
  int get classroomNumber => widget.classroomNumber;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _loadFromCache();
    _refreshDataIfOnline();
  }

  void _initializeControllers() {
    _teacherController = TextEditingController();
    _nbMaleController = TextEditingController();
    _nbFemaleController = TextEditingController();
  }

  @override
  void dispose() {
    _teacherController.dispose();
    _nbMaleController.dispose();
    _nbFemaleController.dispose();
    super.dispose();
  }

  // Load from cache
  void _loadFromCache() {
    // Questions
    final questionsCached = LocalStorageService.getFromCache('classroom_questions');
    if (questionsCached != null && questionsCached is List) {
      _questions = questionsCached.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        return {
          'number': (index + 1).toString(),
          'id': item['id'].toString(),
          'name': item['name'].toString(),
        };
      }).toList();

      // Re-init scores
      _scores = {};
      for (var q in _questions) {
        _scores[q['id']!] = null;
      }
    }

    // Grades
    final gradesCached = LocalStorageService.getFromCache('classroom_grades');
    if (gradesCached != null && gradesCached is List) {
      _grades = gradesCached.map((e) => {
        'id': e['id']?.toString(),
        'name': e['name']?.toString() ?? 'Unnamed',
        'code': e['code']?.toString() ?? e['id']?.toString(),
      }).toList();
    }

    // Subjects
    final subjectsCached = LocalStorageService.getFromCache('classroom_subjects');
    if (subjectsCached != null && subjectsCached is List) {
      _subjects = subjectsCached.map((s) => {
        'id': s['id']?.toString(),
        'name': s['name']?.toString() ?? 'Unnamed',
      }).toList();
    }

    if (mounted) setState(() {});
  }

  // Refresh data if online
  Future<void> _refreshDataIfOnline() async {
    final isOnline = await LocalStorageService.isOnline();
    if (!isOnline) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final headers = auth.getAuthHeaders();

    // Refresh questions
    try {
      final qRes = await http.get(
        Uri.parse('${AppUrl.url}/questions?cat=Classroom Observation'),
        headers: headers,
      );

      if (qRes.statusCode == 200) {
        final List<dynamic> list = jsonDecode(qRes.body);
        if (mounted) {
          setState(() {
            _questions = list.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return {
                'number': (index + 1).toString(),
                'id': item['id'].toString(),
                'name': item['name'].toString(),
              };
            }).toList();

            // Update scores
            final newScores = <String, int?>{};
            for (var q in _questions) {
              newScores[q['id']!] = _scores.containsKey(q['id']) ? _scores[q['id']!] : null;
            }
            _scores = newScores;
          });

          await LocalStorageService.saveToCache('classroom_questions', list);
        }
      }
    } catch (e) {
      print('Background refresh classroom questions failed: $e');
    }

    // Refresh grades & subjects
    if (schoolLevel != null) {
      try {
        // Grades
        final gradeRes = await http.get(
          Uri.parse('${AppUrl.url}/level/grades?level=$schoolLevel'),
          headers: headers,
        );

        if (gradeRes.statusCode == 200) {
          final List<dynamic> gradeList = jsonDecode(gradeRes.body);
          if (mounted) {
            setState(() {
              _grades = gradeList.map((e) => {
                'id': e['id']?.toString(),
                'name': e['name']?.toString() ?? 'Unnamed',
                'code': e['code']?.toString() ?? e['id']?.toString(),
              }).toList();
            });

            await LocalStorageService.saveToCache('classroom_grades', gradeList);
          }
        }

        // Subjects
        final subjectRes = await http.get(
          Uri.parse('${AppUrl.url}/level/subjects?level=$schoolLevel'),
          headers: headers,
        );

        if (subjectRes.statusCode == 200) {
          final List<dynamic> subjectList = jsonDecode(subjectRes.body);
          if (mounted) {
            setState(() {
              _subjects = subjectList.map((s) => {
                'id': s['id']?.toString(),
                'name': s['name']?.toString() ?? 'Unnamed',
              }).toList();
            });

            await LocalStorageService.saveToCache('classroom_subjects', subjectList);
          }
        }
      } catch (e) {
        print('Background refresh grades/subjects failed: $e');
      }
    }
  }

  // Validate current classroom
  bool _validateCurrentClassroom() {
    if (_teacherController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Teacher name is required for Classroom $classroomNumber'),
          backgroundColor: Colors.orange,
        ),
      );
      return false;
    }

    if (_selectedGrade == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Grade is required for Classroom $classroomNumber'),
          backgroundColor: Colors.orange,
        ),
      );
      return false;
    }

    if (_selectedSubject == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Subject is required for Classroom $classroomNumber'),
          backgroundColor: Colors.orange,
        ),
      );
      return false;
    }

    if (_nbMaleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Number of male students is required for Classroom $classroomNumber'),
          backgroundColor: Colors.orange,
        ),
      );
      return false;
    }

    if (_nbFemaleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Number of female students is required for Classroom $classroomNumber'),
          backgroundColor: Colors.orange,
        ),
      );
      return false;
    }

    for (var q in _questions) {
      if (_scores[q['id']!] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please answer all questions for Classroom $classroomNumber'),
            backgroundColor: Colors.orange,
          ),
        );
        return false;
      }
    }

    return true;
  }

  // Build payload for this classroom
  Map<String, dynamic> _buildPayload() {
    final cleanScores = _scores.map((key, value) => MapEntry(key, value ?? 0));

    return {
      'school': schoolCode ?? 'N/A',
      'class_num': classroomNumber,
      'grade': _selectedGrade,
      'subject': _selectedSubject,
      'teacher': _teacherController.text.trim(),
      'nb_male': int.tryParse(_nbMaleController.text.trim() ?? '0') ?? 0,
      'nb_female': int.tryParse(_nbFemaleController.text.trim() ?? '0') ?? 0,
      'scores': cleanScores,
    };
  }

  // Submit current classroom
  Future<void> _submit() async {
    if (!mounted) return;

    if (!_validateCurrentClassroom()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _isSubmitting = true;
    });

    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!auth.isAuthenticated || auth.token == null) {
      _handleError('Not authenticated');
      return;
    }

    final headers = auth.getAuthHeaders();
    final isOnline = await LocalStorageService.isOnline();
    final payload = _buildPayload();

    print('Classroom $classroomNumber payload:');
    print(jsonEncode(payload));

    try {
      if (isOnline) {
        final res = await http.post(
          Uri.parse('${AppUrl.url}/classroom-observation'),
          headers: headers,
          body: jsonEncode(payload),
        );

        if (res.statusCode == 200 || res.statusCode == 201) {
          await _syncPendingClassroom();
          _handleSuccess();
        } else {
          await LocalStorageService.savePendingClassroomObservation(payload);
          _handleOfflineSave();
        }
      } else {
        await LocalStorageService.savePendingClassroomObservation(payload);
        _handleOfflineSave();
      }
    } catch (e) {
      print('Submit error: $e');
      try {
        await LocalStorageService.savePendingClassroomObservation(payload);
        _handleOfflineSave();
      } catch (hiveErr) {
        print('Hive failed: $hiveErr');
        _handleError('Error saving data');
      }
    }
  }

  Future<void> _syncPendingClassroom() async {
    final pending = LocalStorageService.getPendingClassroomObservation();
    if (pending.isEmpty) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!auth.isAuthenticated || auth.token == null) return;

    final headers = auth.getAuthHeaders();

    for (var payload in pending) {
      try {
        final res = await http.post(
          Uri.parse('${AppUrl.url}/classroom-observation'),
          headers: headers,
          body: jsonEncode(payload),
        );

        if (res.statusCode == 200 || res.statusCode == 201) {
          await LocalStorageService.removePendingClassroomObservation(payload);
        }
      } catch (e) {
        debugPrint('Pending classroom sync failed: $e');
      }
    }
  }

  void _handleSuccess() {
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _isSubmitting = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Classroom $classroomNumber saved successfully!'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );

    // Navigate to next classroom or completion page
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;

      if (classroomNumber < 3) {
        // Navigate to next classroom
        _navigateToNextClassroom();
      } else {
        // All classrooms done, go to next module
        context.push(
          '/parents',
          extra: {
            'schoolCode': schoolCode,
            'schoolName': schoolName,
            'level': schoolLevel,
          },
        );
      }
    });
  }

  void _handleOfflineSave() {
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _isSubmitting = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Classroom $classroomNumber saved offline — will sync later'),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 3),
      ),
    );

    // Navigate to next classroom even when offline
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;

      if (classroomNumber < 3) {
        _navigateToNextClassroom();
      } else {
        context.push(
          '/parents',
          extra: {
            'schoolCode': schoolCode,
            'schoolName': schoolName,
            'level': schoolLevel,
          },
        );
      }
    });
  }

  void _handleError(String message) {
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _isSubmitting = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _navigateToNextClassroom() {
    final nextClassroom = classroomNumber + 1;
    String routeName;

    switch (nextClassroom) {
      case 2:
        routeName = '/classroom-2';
        break;
      case 3:
        routeName = '/classroom-3';
        break;
      default:
        return;
    }

    context.push(
      routeName,
      extra: {
        'schoolCode': schoolCode,
        'schoolName': schoolName,
        'level': schoolLevel,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Classroom $classroomNumber Observation',
        backgroundColor: AppColors.primary,
        textColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, color: Colors.white),
            tooltip: 'Offline Observations',
            onPressed: () => context.push('/offline-classroom-observation'),
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
                  child: Text(
                    'Offline Mode — Data will be saved locally',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.deepOrange.shade700, fontWeight: FontWeight.w600),
                  ),
                ),

              Expanded(
                child: LoadingOverlay(
                  isLoading: _isLoading || _isFetchingDropdowns,
                  child: RefreshIndicator(
                    onRefresh: _refreshDataIfOnline,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),

                          // School Info Card
                          Card(
                            color: AppColors.primary.withOpacity(0.05),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Icon(Icons.school, color: AppColors.primary),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          schoolName ?? 'Unknown School',
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        Text(
                                          'Level: ${schoolLevel ?? 'N/A'} | Code: ${schoolCode ?? 'N/A'}',
                                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Progress Indicator
                          LinearProgressIndicator(
                            value: classroomNumber / 3,
                            backgroundColor: Colors.grey[200],
                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Classroom $classroomNumber of 3',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 24),

                          // Classroom Card
                          _buildClassroomCard(),

                          const SizedBox(height: 24),

                          // Navigation Buttons
                          Row(
                            children: [
                              if (classroomNumber > 1)
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.arrow_back),
                                    label: const Text('Previous'),
                                    onPressed: _isSubmitting ? null : () {
                                      context.pop();
                                    },
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.primary,
                                      side: BorderSide(color: AppColors.primary),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                    ),
                                  ),
                                ),
                              if (classroomNumber > 1) const SizedBox(width: 16),
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: Icon(
                                    classroomNumber == 3 ? Icons.check_circle : Icons.navigate_next,
                                  ),
                                  label: Text(
                                    classroomNumber == 3 ? 'Complete' : 'Next',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                  onPressed: _isSubmitting ? null : _submit,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 80),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // Build classroom card with its own questions
  Widget _buildClassroomCard() {
    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Classroom Header
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$classroomNumber',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Classroom Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Teacher Name
            TextFormField(
              controller: _teacherController,
              decoration: const InputDecoration(
                labelText: 'Teacher Name *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),

            // Grade and Subject Row
            Row(
              children: [
                Expanded(
                  child: _isFetchingDropdowns
                      ? const Center(child: CircularProgressIndicator())
                      : _grades.isEmpty
                      ? const Text('No grades available', style: TextStyle(color: Colors.grey))
                      : DropdownButtonFormField<String>(
                    value: _selectedGrade,
                    decoration: const InputDecoration(
                      labelText: 'Grade *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.grade),
                    ),
                    isExpanded: true,
                    items: _grades.map((g) {
                      final name = g['name'] as String?;
                      return DropdownMenuItem<String>(
                        value: name,
                        child: Text(name ?? 'Unnamed Grade'),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() => _selectedGrade = value),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _isFetchingDropdowns
                      ? const SizedBox.shrink()
                      : _subjects.isEmpty
                      ? const Text('No subjects available', style: TextStyle(color: Colors.grey))
                      : DropdownButtonFormField<String>(
                    value: _selectedSubject,
                    decoration: const InputDecoration(
                      labelText: 'Subject *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.book),
                    ),
                    isExpanded: true,
                    items: _subjects.map((s) {
                      final name = s['name'] as String?;
                      return DropdownMenuItem<String>(
                        value: name,
                        child: Text(name ?? 'Unnamed Subject'),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() => _selectedSubject = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Male and Female Count Row
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _nbMaleController,
                    decoration: const InputDecoration(
                      labelText: 'Number of Male *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.male),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _nbFemaleController,
                    decoration: const InputDecoration(
                      labelText: 'Number of Female *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.female),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Questions Section Header
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.help_outline, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Observation Questions for Classroom $classroomNumber',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'All questions are Yes/No (1 pt = Yes, 0 pt = No)',
              style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 16),

            // Questions for this classroom
            if (_questions.isEmpty)
              const Center(child: Text('No questions available'))
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _questions.length,
                itemBuilder: (context, qIndex) {
                  final q = _questions[qIndex];
                  final qId = q['id'] as String;
                  final number = q['number'] as String;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$number. ${q['name']}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _radioOption(qId, 1, 'Yes'),
                            ),
                            Expanded(
                              child: _radioOption(qId, 0, 'No'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _radioOption(String qId, int value, String label) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: _scores[qId] == value
              ? AppColors.primary
              : Colors.grey.shade300,
        ),
        borderRadius: BorderRadius.circular(8),
        color: _scores[qId] == value
            ? AppColors.primary.withOpacity(0.1)
            : null,
      ),
      child: RadioListTile<int>(
        title: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: _scores[qId] == value
                ? AppColors.primary
                : null,
          ),
        ),
        value: value,
        groupValue: _scores[qId],
        onChanged: _isSubmitting ? null : (v) {
          setState(() {
            _scores[qId] = v;
          });
        },
        dense: true,
        contentPadding: EdgeInsets.zero,
        activeColor: AppColors.primary,
      ),
    );
  }
}