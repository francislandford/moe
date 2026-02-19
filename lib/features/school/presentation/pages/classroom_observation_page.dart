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
import '../../../auth/presentation/providers/auth_provider.dart';

class ClassroomObservationPage extends StatefulWidget {
  const ClassroomObservationPage({super.key});

  @override
  State<ClassroomObservationPage> createState() => _ClassroomObservationPageState();
}

class _ClassroomObservationPageState extends State<ClassroomObservationPage> {
  bool _isLoading = false;
  bool _isFetchingDropdowns = false;
  bool _isSubmitting = false;
  String? _schoolName;
  String? _schoolCode;
  String? _schoolLevel;

  // Controllers for each classroom (3 classrooms)
  final List<TextEditingController> _teacherControllers = List.generate(3, (_) => TextEditingController());
  final List<TextEditingController> _nbMaleControllers = List.generate(3, (_) => TextEditingController());
  final List<TextEditingController> _nbFemaleControllers = List.generate(3, (_) => TextEditingController());

  // Selected values for each classroom
  final List<String?> _selectedGrades = List.generate(3, (_) => null);
  final List<String?> _selectedSubjects = List.generate(3, (_) => null);

  // Scores for each classroom (list of maps) - each classroom has its own scores map
  final List<Map<String, int?>> _scores = List.generate(3, (_) => {});

  List<Map<String, dynamic>> _grades = [];
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _questions = [];

  @override
  void initState() {
    super.initState();
    // Load from cache first (offline-first)
    _loadFromCache();
    // Then refresh if online (background)
    _refreshDataIfOnline();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
    _schoolName = extra?['schoolName'] as String?;
    _schoolCode = extra?['schoolCode'] as String?;
    _schoolLevel = extra?['level'] as String?;

    _schoolName ??= 'Unknown School';
    _schoolCode ??= 'N/A';
    _schoolLevel ??= 'ECE';

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (var controller in _teacherControllers) {
      controller.dispose();
    }
    for (var controller in _nbMaleControllers) {
      controller.dispose();
    }
    for (var controller in _nbFemaleControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  // Load questions, grades, subjects from cache (offline-first)
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

      // Re-init scores for all 3 classrooms from cache
      for (int i = 0; i < 3; i++) {
        _scores[i] = {};
        for (var q in _questions) {
          _scores[i][q['id']!] = null;
        }
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

  // Refresh questions, grades & subjects only if online (background)
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

            // Update scores for all classrooms (preserve existing answers if possible)
            for (int i = 0; i < 3; i++) {
              final newScores = <String, int?>{};
              for (var q in _questions) {
                newScores[q['id']!] = _scores[i].containsKey(q['id']) ? _scores[i][q['id']!] : null;
              }
              _scores[i] = newScores;
            }
          });

          await LocalStorageService.saveToCache('classroom_questions', list);
        }
      }
    } catch (e) {
      print('Background refresh classroom questions failed: $e');
    }

    // Refresh grades & subjects (only if level is known)
    if (_schoolLevel != null) {
      try {
        // Grades
        final gradeRes = await http.get(
          Uri.parse('${AppUrl.url}/level/grades?level=$_schoolLevel'),
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
          Uri.parse('${AppUrl.url}/level/subjects?level=$_schoolLevel'),
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

  // Validate all classrooms
  bool _validateAllClassrooms() {
    for (int i = 0; i < 3; i++) {
      // Check teacher name
      if (_teacherControllers[i].text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Teacher name is required for Classroom ${i + 1}'),
            backgroundColor: Colors.orange,
          ),
        );
        return false;
      }

      // Check grade
      if (_selectedGrades[i] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Grade is required for Classroom ${i + 1}'),
            backgroundColor: Colors.orange,
          ),
        );
        return false;
      }

      // Check subject
      if (_selectedSubjects[i] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Subject is required for Classroom ${i + 1}'),
            backgroundColor: Colors.orange,
          ),
        );
        return false;
      }

      // Check male/female counts
      if (_nbMaleControllers[i].text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Number of male students is required for Classroom ${i + 1}'),
            backgroundColor: Colors.orange,
          ),
        );
        return false;
      }

      if (_nbFemaleControllers[i].text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Number of female students is required for Classroom ${i + 1}'),
            backgroundColor: Colors.orange,
          ),
        );
        return false;
      }

      // Check if all questions are answered for this classroom
      for (var q in _questions) {
        if (_scores[i][q['id']!] == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Please answer all questions for Classroom ${i + 1}'),
              backgroundColor: Colors.orange,
            ),
          );
          return false;
        }
      }
    }

    return true;
  }

  Future<void> _submit() async {
    if (!mounted) return;

    if (!_validateAllClassrooms()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _isSubmitting = true;
    });

    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!auth.isAuthenticated || auth.token == null) {
      _handleEnd('Not authenticated', Colors.red);
      return;
    }

    final headers = auth.getAuthHeaders();
    final isOnline = await LocalStorageService.isOnline();

    // Prepare payloads for all 3 classrooms
    List<Map<String, dynamic>> allPayloads = [];

    for (int i = 0; i < 3; i++) {
      final cleanScores = _scores[i].map((key, value) => MapEntry(key, value ?? 0));

      final payload = {
        'school': _schoolCode ?? 'N/A',
        'class_num': i + 1,
        'grade': _selectedGrades[i],
        'subject': _selectedSubjects[i],
        'teacher': _teacherControllers[i].text.trim(),
        'nb_male': int.tryParse(_nbMaleControllers[i].text.trim() ?? '0') ?? 0,
        'nb_female': int.tryParse(_nbFemaleControllers[i].text.trim() ?? '0') ?? 0,
        'scores': cleanScores,
      };

      allPayloads.add(payload);
    }

    print('All Classroom Observations payload:');
    print(jsonEncode(allPayloads));

    String message = 'Unknown status';
    Color color = Colors.grey;

    try {
      if (isOnline) {
        bool allSuccess = true;

        // Submit each classroom observation
        for (var payload in allPayloads) {
          final res = await http.post(
            Uri.parse('${AppUrl.url}/classroom-observation'),
            headers: headers,
            body: jsonEncode(payload),
          );

          if (res.statusCode != 200 && res.statusCode != 201) {
            allSuccess = false;
            print('Failed to submit classroom ${payload['class_num']}: ${res.statusCode} - ${res.body}');
          }
        }

        if (allSuccess) {
          message = 'All 3 classroom observations saved successfully!';
          color = Colors.green;
          await _syncPendingClassroom(context);
        } else {
          // If some failed, save all to pending
          for (var payload in allPayloads) {
            await LocalStorageService.savePendingClassroomObservation(payload);
          }
          message = 'Some observations failed - saved offline for retry';
          color = Colors.orange;
        }
      } else {
        // Save all to pending queue when offline
        for (var payload in allPayloads) {
          await LocalStorageService.savePendingClassroomObservation(payload);
        }
        message = 'All 3 observations saved offline — will sync when online';
        color = Colors.orange;
      }
    } catch (e) {
      print('Submit error: $e');

      // Save all to pending on error
      try {
        for (var payload in allPayloads) {
          await LocalStorageService.savePendingClassroomObservation(payload);
        }
        message = 'Saved offline due to error — will retry later';
        color = Colors.orange;
      } catch (hiveErr) {
        print('Hive failed: $hiveErr');
        message = 'Error: $e';
        color = Colors.red;
      }
    }

    _handleEnd(message, color);
  }

  void _handleEnd(String message, Color color) {
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _isSubmitting = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 5),
      ),
    );

    if (color == Colors.green || color == Colors.orange) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          context.push(
            '/parents',
            extra: {
              'schoolCode': _schoolCode,
              'schoolName': _schoolName,
              'level': _schoolLevel,
            },
          );
        }
      });
    }
  }

  Future<void> _syncPendingClassroom(BuildContext context) async {
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

  // Build a complete classroom card with its own questions
  Widget _buildClassroomCard(int classroomNum) {
    final int index = classroomNum - 1;

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
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$classroomNum',
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
              controller: _teacherControllers[index],
              decoration: const InputDecoration(
                labelText: 'Teacher Name *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
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
                    value: _selectedGrades[index],
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
                    onChanged: (value) => setState(() => _selectedGrades[index] = value),
                    validator: (v) => v == null ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _isFetchingDropdowns
                      ? const SizedBox.shrink()
                      : _subjects.isEmpty
                      ? const Text('No subjects available', style: TextStyle(color: Colors.grey))
                      : DropdownButtonFormField<String>(
                    value: _selectedSubjects[index],
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
                    onChanged: (value) => setState(() => _selectedSubjects[index] = value),
                    validator: (v) => v == null ? 'Required' : null,
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
                    controller: _nbMaleControllers[index],
                    decoration: const InputDecoration(
                      labelText: 'Number of Male *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.male),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _nbFemaleControllers[index],
                    decoration: const InputDecoration(
                      labelText: 'Number of Female *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.female),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
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
                      'Observation Questions for Classroom $classroomNum',
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
                              child: _radioOption(index, qId, 1, 'Yes'),
                            ),
                            Expanded(
                              child: _radioOption(index, qId, 0, 'No'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Module 5: Classroom Observation',
        backgroundColor: AppColors.primary,
        textColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, color: Colors.white),
            tooltip: 'Offline Classroom Observations',
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
                  child: const Text(
                    'Offline Mode — Data will be saved locally and synced later',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w600),
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
                                          _schoolName ?? 'Unknown School',
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        Text(
                                          'Level: ${_schoolLevel ?? 'N/A'} | Code: ${_schoolCode ?? 'N/A'}',
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

                          // Three Classroom Cards with their own questions
                          _buildClassroomCard(1),
                          _buildClassroomCard(2),
                          _buildClassroomCard(3),

                          const SizedBox(height: 24),

                          // Submit Button
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: StreamBuilder<bool>(
                              stream: LocalStorageService.onlineStatusStream,
                              initialData: true,
                              builder: (context, snapshot) {
                                final bool canSubmit = snapshot.data ?? true;
                                return ElevatedButton.icon(
                                  icon: const Icon(Icons.save),
                                  label: const Text(
                                    'Submit All 3 Classroom Observations',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                  onPressed: _isLoading || _isSubmitting || !canSubmit ? null : _submit,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: canSubmit ? AppColors.primary : Colors.grey,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 3,
                                  ),
                                );
                              },
                            ),
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

  Widget _radioOption(int classroomIndex, String qId, int value, String label) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: _scores[classroomIndex][qId] == value
              ? AppColors.primary
              : Colors.grey.shade300,
        ),
        borderRadius: BorderRadius.circular(8),
        color: _scores[classroomIndex][qId] == value
            ? AppColors.primary.withOpacity(0.1)
            : null,
      ),
      child: RadioListTile<int>(
        title: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: _scores[classroomIndex][qId] == value
                ? AppColors.primary
                : null,
          ),
        ),
        value: value,
        groupValue: _scores[classroomIndex][qId],
        onChanged: _isSubmitting ? null : (v) {
          setState(() {
            _scores[classroomIndex][qId] = v;
          });
        },
        dense: true,
        contentPadding: EdgeInsets.zero,
        activeColor: AppColors.primary,
      ),
    );
  }
}