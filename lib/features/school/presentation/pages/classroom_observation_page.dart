import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_url.dart';
import '../../../../core/services/local_storage_service.dart';
import '../../../../core/widgets/custom_app_bar.dart';
import '../../../../core/widgets/loading_overlay.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class ClassroomObservationPage extends StatefulWidget {
  const ClassroomObservationPage({super.key});

  @override
  State<ClassroomObservationPage> createState() => _ClassroomObservationPageState();
}

class _ClassroomObservationPageState extends State<ClassroomObservationPage> {
  bool _isLoading = false;               // for questions fetch
  bool _isFetchingDropdowns = false;     // for grades/subjects fetch
  bool _isSubmitting = false;

  String? _schoolName;
  String? _schoolCode;
  String? _schoolLevel;

  int _selectedClassNum = 1;
  final TextEditingController _teacherController = TextEditingController();

  List<Map<String, dynamic>> _grades = [];
  List<Map<String, dynamic>> _subjects = [];

  String? _selectedGrade;
  String? _selectedSubject;

  // New fields for number of boys and girls in one row
  final TextEditingController _nbMaleController = TextEditingController();
  final TextEditingController _nbFemaleController = TextEditingController();

  List<Map<String, dynamic>> _questions = [];
  Map<String, int?> _scores = {};

  @override
  void initState() {
    super.initState();
    _fetchQuestions();
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

    if (mounted) {
      _fetchDropdowns();
    }
  }

  @override
  void dispose() {
    _teacherController.dispose();
    _nbMaleController.dispose();
    _nbFemaleController.dispose();
    super.dispose();
  }

  Future<void> _fetchDropdowns() async {
    if (!mounted || _schoolLevel == null) return;
    if (_grades.isNotEmpty && _subjects.isNotEmpty) return;

    setState(() => _isFetchingDropdowns = true);

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final headers = auth.getAuthHeaders();

    try {
      print('Fetching dropdowns for level: $_schoolLevel');

      // Grades
      final gradeRes = await http.get(
        Uri.parse('${AppUrl.url}/level/grades?level=$_schoolLevel'),
        headers: headers,
      );
      print('Grades response: ${gradeRes.statusCode}');

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
        }
      }

      // Subjects
      final subjectRes = await http.get(
        Uri.parse('${AppUrl.url}/level/subjects?level=$_schoolLevel'),
        headers: headers,
      );
      print('Subjects response: ${subjectRes.statusCode}');

      if (subjectRes.statusCode == 200) {
        final List<dynamic> subjectList = jsonDecode(subjectRes.body);
        if (mounted) {
          setState(() {
            _subjects = subjectList.map((s) => {
              'id': s['id']?.toString(),
              'name': s['name']?.toString() ?? 'Unnamed',
            }).toList();
          });
        }
      }
    } catch (e) {
      print('Dropdown fetch error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading dropdowns: $e'), backgroundColor: Colors.red),
        );
      }
    }

    if (mounted) {
      setState(() => _isFetchingDropdowns = false);
    }
  }

  Future<void> _fetchQuestions() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final headers = auth.getAuthHeaders();

    try {
      print('Fetching classroom observation questions...');
      final qRes = await http.get(
        Uri.parse('${AppUrl.url}/questions?cat=Classroom Observation'),
        headers: headers,
      );

      print('Questions response: ${qRes.statusCode}');

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

            _scores.clear();
            for (var q in _questions) {
              _scores[q['id']!] = null;
            }
          });
        }
      } else {
        throw Exception('Failed to load questions: ${qRes.statusCode}');
      }
    } catch (e) {
      print('Fetch questions error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading questions: $e'), backgroundColor: Colors.red),
        );
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submit() async {
    if (!mounted) return;

    if (_teacherController.text.trim().isEmpty || _selectedGrade == null || _selectedSubject == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields'), backgroundColor: Colors.orange),
      );
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

    final cleanScores = _scores.map((key, value) => MapEntry(key, value ?? 0));

    final payload = {
      'school': _schoolCode ?? 'N/A',
      'class_num': _selectedClassNum,
      'grade': _selectedGrade,
      'subject': _selectedSubject,
      'teacher': _teacherController.text.trim(),
      'nb_male': int.tryParse(_nbMaleController.text.trim() ?? '0') ?? 0,      // NEW: nb_male
      'nb_female': int.tryParse(_nbFemaleController.text.trim() ?? '0') ?? 0, // NEW: nb_female
      'scores': cleanScores,
    };

    print('Classroom Observation payload:');
    print(jsonEncode(payload));

    String message = 'Unknown status';
    Color color = Colors.grey;

    try {
      final isOnline = await LocalStorageService.isOnline();
      print('Online: $isOnline');

      if (isOnline) {
        final res = await http.post(
          Uri.parse('${AppUrl.url}/classroom-observation'),
          headers: headers,
          body: jsonEncode(payload),
        );

        print('Response: ${res.statusCode} - ${res.body}');

        if (res.statusCode == 200 || res.statusCode == 201) {
          message = 'Classroom $_selectedClassNum observation saved successfully!';
          color = Colors.green;
          await _syncPendingClassroom(context);
        } else {
          message = 'Server error: ${res.statusCode} - ${res.body}';
          color = Colors.red;
        }
      } else {
        await LocalStorageService.savePendingClassroomObservation(payload);
        message = 'Saved offline — will sync when online';
        color = Colors.orange;
      }
    } catch (e) {
      print('Submit error: $e');
      message = 'Error: $e';
      color = Colors.red;

      try {
        await LocalStorageService.savePendingClassroomObservation(payload);
        message = 'Saved offline due to error — will retry later';
        color = Colors.orange;
      } catch (hiveErr) {
        print('Hive failed: $hiveErr');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Module 5: Classroom Observation at ${_schoolName ?? ''}',
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
                    onRefresh: () async {
                      await _fetchQuestions();
                      await _fetchDropdowns();
                    },
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 24),

                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Observing Classroom #$_selectedClassNum',
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 16),

                                  DropdownButtonFormField<int>(
                                    value: _selectedClassNum,
                                    decoration: const InputDecoration(labelText: 'Classroom Number *'),
                                    items: [1, 2, 3]
                                        .map((num) => DropdownMenuItem(value: num, child: Text('Classroom $num')))
                                        .toList(),
                                    onChanged: (v) => setState(() => _selectedClassNum = v!),
                                    validator: (v) => v == null ? 'Required' : null,
                                  ),

                                  const SizedBox(height: 16),

                                  TextFormField(
                                    controller: _teacherController,
                                    decoration: const InputDecoration(labelText: 'Teacher Name *'),
                                    validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
                                  ),

                                  const SizedBox(height: 16),

                                  // Grade Dropdown
                                  if (_isFetchingDropdowns)
                                    const Center(child: CircularProgressIndicator())
                                  else if (_grades.isEmpty)
                                    const Text(
                                      'No grades available for this level',
                                      style: TextStyle(color: Colors.grey),
                                    )
                                  else
                                    DropdownButtonFormField<String>(
                                      value: _selectedGrade,
                                      decoration: const InputDecoration(
                                        labelText: 'Grade *',
                                        border: OutlineInputBorder(),
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
                                      validator: (v) => v == null ? 'Required' : null,
                                    ),

                                  const SizedBox(height: 16),

                                  // Subject Dropdown
                                  if (_isFetchingDropdowns)
                                    const SizedBox.shrink()
                                  else if (_subjects.isEmpty)
                                    const Text(
                                      'No subjects available',
                                      style: TextStyle(color: Colors.grey),
                                    )
                                  else
                                    DropdownButtonFormField<String>(
                                      value: _selectedSubject,
                                      decoration: const InputDecoration(
                                        labelText: 'Subject *',
                                        border: OutlineInputBorder(),
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
                                      validator: (v) => v == null ? 'Required' : null,
                                    ),

                                  const SizedBox(height: 16),

                                  // New row: Number of Male and Female students
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          controller: _nbMaleController,
                                          decoration: const InputDecoration(
                                            labelText: 'Number of Male',
                                            border: OutlineInputBorder(),
                                          ),
                                          keyboardType: TextInputType.number,
                                          validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: TextFormField(
                                          controller: _nbFemaleController,
                                          decoration: const InputDecoration(
                                            labelText: 'Number of Female',
                                            border: OutlineInputBorder(),
                                          ),
                                          keyboardType: TextInputType.number,
                                          validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          const Text(
                            'Observe for 15 minutes. All questions are Yes/No (1 pt = Yes, 0 pt = No)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 16),

                          if (_questions.isEmpty && !_isLoading)
                            const Center(child: Text('No questions loaded. Pull down to refresh.'))
                          else if (_questions.isEmpty)
                            const Center(child: CircularProgressIndicator())
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _questions.length,
                              itemBuilder: (context, index) {
                                final q = _questions[index];
                                final qId = q['id'] as String;
                                final number = q['number'] as String;

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '$number. ${q['name']}',
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                          children: [
                                            _radioOption(qId, 1, 'Yes'),
                                            _radioOption(qId, 0, 'No'),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),

                          const SizedBox(height: 40),

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
                                  label: const Text('Submit Classroom Observation', style: TextStyle(fontSize: 17)),
                                  onPressed: _isLoading || _isSubmitting || !canSubmit ? null : _submit,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: canSubmit ? AppColors.primary : Colors.grey,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  Widget _radioOption(String qId, int value, String label) {
    return Expanded(
      child: RadioListTile<int>(
        title: Text(label, style: const TextStyle(fontSize: 14)),
        value: value,
        groupValue: _scores[qId],
        onChanged: _isSubmitting ? null : (v) => setState(() => _scores[qId] = v),
        dense: true,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}