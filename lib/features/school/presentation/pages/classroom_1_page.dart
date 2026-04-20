// import 'dart:convert';
//
// import 'package:flutter/material.dart';
// import 'package:go_router/go_router.dart';
// import 'package:http/http.dart' as http;
// import 'package:provider/provider.dart';
//
// import '../../../../core/constants/app_colors.dart';
// import '../../../../core/constants/app_url.dart';
// import '../../../../core/widgets/custom_app_bar.dart';
// import '../../../../core/widgets/loading_overlay.dart';
// import '../../../../core/services/local_storage_service.dart';
// import '../../../../core/services/data_preloader_service.dart';
// import '../../../auth/presentation/providers/auth_provider.dart';
//
// class ClassroomObservationPage extends StatefulWidget {
//   final String? schoolCode;
//   final String? schoolName;
//   final String? schoolLevel;
//
//   const ClassroomObservationPage({
//     super.key,
//     this.schoolCode,
//     this.schoolName,
//     this.schoolLevel,
//   });
//
//   @override
//   State<ClassroomObservationPage> createState() =>
//       _ClassroomObservationPageState();
// }
//
// class _ClassroomObservationPageState extends State<ClassroomObservationPage> {
//   bool _isLoading = false;
//   bool _isFetchingDropdowns = false;
//   bool _isSubmitting = false;
//
//   late TextEditingController _teacherController;
//   late TextEditingController _nbMaleController;
//   late TextEditingController _nbFemaleController;
//
//   String? _selectedGrade;
//   String? _selectedSubject;
//
//   Map<String, int?> _scores = {};
//
//   List<Map<String, dynamic>> _grades = [];
//   List<Map<String, dynamic>> _subjects = [];
//   List<Map<String, dynamic>> _questions = [];
//
//   String? get schoolCode => widget.schoolCode;
//   String? get schoolName => widget.schoolName;
//   String? get schoolLevel => widget.schoolLevel;
//
//   @override
//   void initState() {
//     super.initState();
//     _initializeControllers();
//     _loadFromCache();
//     _refreshDataIfOnline();
//   }
//
//   void _initializeControllers() {
//     _teacherController = TextEditingController();
//     _nbMaleController = TextEditingController();
//     _nbFemaleController = TextEditingController();
//   }
//
//   @override
//   void dispose() {
//     _teacherController.dispose();
//     _nbMaleController.dispose();
//     _nbFemaleController.dispose();
//     super.dispose();
//   }
//
//   void _loadFromCache() {
//     try {
//       final cachedQuestions =
//       DataPreloaderService.getCachedData('classroom_questions');
//
//       if (cachedQuestions.isNotEmpty) {
//         _questions = cachedQuestions.map((q) {
//           return {
//             'number': q['number']?.toString() ??
//                 (cachedQuestions.indexOf(q) + 1).toString(),
//             'id': q['id']?.toString() ?? '',
//             'name': q['name']?.toString() ?? 'Unnamed Question',
//           };
//         }).toList();
//       } else {
//         _questions = [];
//       }
//
//       _scores = {};
//       for (final q in _questions) {
//         final id = q['id']?.toString() ?? '';
//         if (id.isNotEmpty) {
//           _scores[id] = null;
//         }
//       }
//
//       if (schoolLevel != null) {
//         final cachedGrades = DataPreloaderService.getGradesForLevel(schoolLevel!);
//         _grades = cachedGrades.map((g) {
//           return {
//             'id': g['id']?.toString() ?? '',
//             'name': g['name']?.toString() ?? 'Unnamed',
//           };
//         }).toList();
//
//         final cachedSubjects =
//         DataPreloaderService.getSubjectsForLevel(schoolLevel!);
//         _subjects = cachedSubjects.map((s) {
//           return {
//             'id': s['id']?.toString() ?? '',
//             'name': s['name']?.toString() ?? 'Unnamed',
//           };
//         }).toList();
//       }
//
//       if (mounted) setState(() {});
//     } catch (e) {
//       debugPrint('❌ Error loading from cache: $e');
//       _questions = [];
//       _grades = [];
//       _subjects = [];
//       if (mounted) setState(() {});
//     }
//   }
//
//   Future<void> _refreshDataIfOnline() async {
//     final isOnline = await LocalStorageService.isOnline();
//     if (!isOnline) return;
//
//     if (mounted) {
//       setState(() {
//         _isFetchingDropdowns = true;
//       });
//     }
//
//     final auth = Provider.of<AuthProvider>(context, listen: false);
//     final headers = auth.getAuthHeaders();
//
//     try {
//       final qRes = await http.get(
//         Uri.parse('${AppUrl.url}/questions?cat=Classroom Observation'),
//         headers: headers,
//       );
//
//       if (qRes.statusCode == 200) {
//         final List<dynamic> list = jsonDecode(qRes.body);
//
//         if (mounted) {
//           setState(() {
//             _questions = list.asMap().entries.map((entry) {
//               final index = entry.key;
//               final item = entry.value;
//               return {
//                 'number': (index + 1).toString(),
//                 'id': item['id'].toString(),
//                 'name': item['name'].toString(),
//               };
//             }).toList();
//
//             final newScores = <String, int?>{};
//             for (final q in _questions) {
//               final id = q['id']?.toString() ?? '';
//               if (id.isNotEmpty) {
//                 newScores[id] = _scores.containsKey(id) ? _scores[id] : null;
//               }
//             }
//             _scores = newScores;
//           });
//
//           await LocalStorageService.saveToCache('classroom_questions', list);
//         }
//       }
//     } catch (e) {
//       debugPrint('❌ Background refresh classroom questions failed: $e');
//     }
//
//     if (schoolLevel != null) {
//       try {
//         final gradeRes = await http.get(
//           Uri.parse('${AppUrl.url}/level/grades?level=$schoolLevel'),
//           headers: headers,
//         );
//
//         if (gradeRes.statusCode == 200) {
//           final List<dynamic> gradeList = jsonDecode(gradeRes.body);
//           if (mounted) {
//             setState(() {
//               _grades = gradeList
//                   .map(
//                     (e) => {
//                   'id': e['id']?.toString() ?? '',
//                   'name': e['name']?.toString() ?? 'Unnamed',
//                 },
//               )
//                   .toList();
//             });
//
//             await LocalStorageService.saveToCache(
//               'grades_${schoolLevel!.toLowerCase()}',
//               gradeList,
//             );
//           }
//         }
//
//         final subjectRes = await http.get(
//           Uri.parse('${AppUrl.url}/level/subjects?level=$schoolLevel'),
//           headers: headers,
//         );
//
//         if (subjectRes.statusCode == 200) {
//           final List<dynamic> subjectList = jsonDecode(subjectRes.body);
//           if (mounted) {
//             setState(() {
//               _subjects = subjectList
//                   .map(
//                     (s) => {
//                   'id': s['id']?.toString() ?? '',
//                   'name': s['name']?.toString() ?? 'Unnamed',
//                 },
//               )
//                   .toList();
//             });
//
//             await LocalStorageService.saveToCache(
//               'subjects_${schoolLevel!.toLowerCase()}',
//               subjectList,
//             );
//           }
//         }
//       } catch (e) {
//         debugPrint('❌ Background refresh grades/subjects failed: $e');
//       }
//     }
//
//     if (mounted) {
//       setState(() {
//         _isFetchingDropdowns = false;
//       });
//     }
//   }
//
//   bool _validateForm() {
//     if (_teacherController.text.trim().isEmpty) {
//       _showSnackBar('Teacher name is required');
//       return false;
//     }
//
//     if (_selectedGrade == null) {
//       _showSnackBar('Grade is required');
//       return false;
//     }
//
//     if (_selectedSubject == null) {
//       _showSnackBar('Subject is required');
//       return false;
//     }
//
//     if (_nbMaleController.text.trim().isEmpty) {
//       _showSnackBar('Number of male students is required');
//       return false;
//     }
//
//     if (_nbFemaleController.text.trim().isEmpty) {
//       _showSnackBar('Number of female students is required');
//       return false;
//     }
//
//     for (final q in _questions) {
//       final id = q['id']?.toString() ?? '';
//       if (id.isNotEmpty && _scores[id] == null) {
//         _showSnackBar('Please answer all questions');
//         return false;
//       }
//     }
//
//     return true;
//   }
//
//   void _showSnackBar(String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Text(message),
//         backgroundColor: Colors.orange,
//       ),
//     );
//   }
//
//   Map<String, dynamic> _buildPayload() {
//     final cleanScores = _scores.map((key, value) => MapEntry(key, value ?? 0));
//
//     return {
//       'school': schoolCode ?? 'N/A',
//       'grade': _selectedGrade,
//       'subject': _selectedSubject,
//       'teacher': _teacherController.text.trim(),
//       'nb_male': int.tryParse(_nbMaleController.text.trim()) ?? 0,
//       'nb_female': int.tryParse(_nbFemaleController.text.trim()) ?? 0,
//       'scores': cleanScores,
//     };
//   }
//
//   Future<void> _submit() async {
//     if (!mounted) return;
//
//     if (!_validateForm()) return;
//
//     setState(() {
//       _isLoading = true;
//       _isSubmitting = true;
//     });
//
//     final auth = Provider.of<AuthProvider>(context, listen: false);
//     if (!auth.isAuthenticated || auth.token == null) {
//       _handleError('Not authenticated');
//       return;
//     }
//
//     final headers = auth.getAuthHeaders();
//     final isOnline = await LocalStorageService.isOnline();
//     final payload = _buildPayload();
//
//     try {
//       if (isOnline) {
//         final res = await http.post(
//           Uri.parse('${AppUrl.url}/classroom-observation'),
//           headers: headers,
//           body: jsonEncode(payload),
//         );
//
//         if (res.statusCode == 200 || res.statusCode == 201) {
//           await _syncPendingClassroom();
//           _handleSuccess();
//         } else {
//           final pendingPayload = {
//             ...payload,
//             'queuedAt': DateTime.now().toIso8601String(),
//           };
//           await LocalStorageService.savePendingClassroomObservation(
//             pendingPayload,
//           );
//           _handleOfflineSave();
//         }
//       } else {
//         final pendingPayload = {
//           ...payload,
//           'queuedAt': DateTime.now().toIso8601String(),
//         };
//         await LocalStorageService.savePendingClassroomObservation(pendingPayload);
//         _handleOfflineSave();
//       }
//     } catch (e) {
//       try {
//         final pendingPayload = {
//           ...payload,
//           'queuedAt': DateTime.now().toIso8601String(),
//         };
//         await LocalStorageService.savePendingClassroomObservation(pendingPayload);
//         _handleOfflineSave();
//       } catch (saveErr) {
//         _handleError('Error saving data');
//       }
//     }
//   }
//
//   Future<void> _syncPendingClassroom() async {
//     final pending = LocalStorageService.getPendingClassroomObservation();
//     if (pending.isEmpty) return;
//
//     final auth = Provider.of<AuthProvider>(context, listen: false);
//     if (!auth.isAuthenticated || auth.token == null) return;
//
//     final headers = auth.getAuthHeaders();
//
//     for (final payload in pending) {
//       try {
//         final apiPayload = Map<String, dynamic>.from(payload);
//         apiPayload.remove('queuedAt');
//
//         if (apiPayload['scores'] is Map) {
//           final scoresMap = <String, int>{};
//           (apiPayload['scores'] as Map).forEach((key, value) {
//             if (value is int) {
//               scoresMap[key.toString()] = value;
//             } else if (value is String) {
//               scoresMap[key.toString()] = int.tryParse(value) ?? 0;
//             } else {
//               scoresMap[key.toString()] = 0;
//             }
//           });
//           apiPayload['scores'] = scoresMap;
//         }
//
//         final res = await http.post(
//           Uri.parse('${AppUrl.url}/classroom-observation'),
//           headers: headers,
//           body: jsonEncode(apiPayload),
//         );
//
//         if (res.statusCode == 200 || res.statusCode == 201) {
//           await LocalStorageService.removePendingClassroomObservation(payload);
//           debugPrint('✅ Synced classroom observation');
//         } else {
//           debugPrint('❌ Sync failed: ${res.statusCode}');
//         }
//       } catch (e) {
//         debugPrint('❌ Pending classroom sync error: $e');
//       }
//     }
//   }
//
//   void _handleSuccess() {
//     if (!mounted) return;
//
//     setState(() {
//       _isLoading = false;
//       _isSubmitting = false;
//     });
//
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(
//         content: Text('Classroom observation saved successfully!'),
//         backgroundColor: Colors.green,
//         duration: Duration(seconds: 2),
//       ),
//     );
//
//     Future.delayed(const Duration(seconds: 1), () {
//       if (!mounted) return;
//
//       context.push(
//         '/parents',
//         extra: {
//           'schoolCode': schoolCode,
//           'schoolName': schoolName,
//           'level': schoolLevel,
//         },
//       );
//     });
//   }
//
//   void _handleOfflineSave() {
//     if (!mounted) return;
//
//     setState(() {
//       _isLoading = false;
//       _isSubmitting = false;
//     });
//
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(
//         content: Text('Observation saved offline — will sync later'),
//         backgroundColor: Colors.orange,
//         duration: Duration(seconds: 3),
//       ),
//     );
//
//     Future.delayed(const Duration(seconds: 1), () {
//       if (!mounted) return;
//
//       context.push(
//         '/parents',
//         extra: {
//           'schoolCode': schoolCode,
//           'schoolName': schoolName,
//           'level': schoolLevel,
//         },
//       );
//     });
//   }
//
//   void _handleError(String message) {
//     if (!mounted) return;
//
//     setState(() {
//       _isLoading = false;
//       _isSubmitting = false;
//     });
//
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Text(message),
//         backgroundColor: Colors.red,
//         duration: const Duration(seconds: 3),
//       ),
//     );
//   }
//
//   Widget _radioOption(String qId, int value, String label) {
//     final selected = _scores[qId] == value;
//
//     return Container(
//       decoration: BoxDecoration(
//         border: Border.all(
//           color: selected ? AppColors.primary : Colors.grey.shade300,
//         ),
//         borderRadius: BorderRadius.circular(8),
//         color: selected ? AppColors.primary.withOpacity(0.1) : null,
//       ),
//       child: RadioListTile<int>(
//         title: Text(
//           label,
//           style: TextStyle(
//             fontSize: 14,
//             color: selected ? AppColors.primary : null,
//           ),
//         ),
//         value: value,
//         groupValue: _scores[qId],
//         onChanged: _isSubmitting
//             ? null
//             : (v) {
//           setState(() {
//             _scores[qId] = v;
//           });
//         },
//         dense: true,
//         contentPadding: EdgeInsets.zero,
//         activeColor: AppColors.primary,
//       ),
//     );
//   }
//
//   Widget _buildObservationCard() {
//     return Card(
//       margin: const EdgeInsets.only(bottom: 24),
//       child: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Container(
//               padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
//               decoration: BoxDecoration(
//                 color: AppColors.primary,
//                 borderRadius: BorderRadius.circular(8),
//               ),
//               child: const Row(
//                 children: [
//                   Icon(Icons.class_, color: Colors.white),
//                   SizedBox(width: 12),
//                   Text(
//                     'Classroom Observation Details',
//                     style: TextStyle(
//                       fontSize: 18,
//                       fontWeight: FontWeight.bold,
//                       color: Colors.white,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//             const SizedBox(height: 20),
//
//             TextFormField(
//               controller: _teacherController,
//               decoration: const InputDecoration(
//                 labelText: 'Teacher Name *',
//                 border: OutlineInputBorder(),
//                 prefixIcon: Icon(Icons.person),
//               ),
//             ),
//             const SizedBox(height: 16),
//
//             Row(
//               children: [
//                 Expanded(
//                   child: _grades.isEmpty
//                       ? const Text(
//                     'No grades available',
//                     style: TextStyle(color: Colors.grey),
//                   )
//                       : DropdownButtonFormField<String>(
//                     value: _selectedGrade,
//                     decoration: const InputDecoration(
//                       labelText: 'Grade *',
//                       border: OutlineInputBorder(),
//                       prefixIcon: Icon(Icons.grade),
//                     ),
//                     isExpanded: true,
//                     items: _grades.map((g) {
//                       final name = g['name'] as String?;
//                       return DropdownMenuItem<String>(
//                         value: name,
//                         child: Text(name ?? 'Unnamed Grade'),
//                       );
//                     }).toList(),
//                     onChanged: (value) {
//                       setState(() {
//                         _selectedGrade = value;
//                       });
//                     },
//                   ),
//                 ),
//                 const SizedBox(width: 16),
//                 Expanded(
//                   child: _subjects.isEmpty
//                       ? const Text(
//                     'No subjects available',
//                     style: TextStyle(color: Colors.grey),
//                   )
//                       : DropdownButtonFormField<String>(
//                     value: _selectedSubject,
//                     decoration: const InputDecoration(
//                       labelText: 'Subject *',
//                       border: OutlineInputBorder(),
//                       prefixIcon: Icon(Icons.book),
//                     ),
//                     isExpanded: true,
//                     items: _subjects.map((s) {
//                       final name = s['name'] as String?;
//                       return DropdownMenuItem<String>(
//                         value: name,
//                         child: Text(name ?? 'Unnamed Subject'),
//                       );
//                     }).toList(),
//                     onChanged: (value) {
//                       setState(() {
//                         _selectedSubject = value;
//                       });
//                     },
//                   ),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 16),
//
//             Row(
//               children: [
//                 Expanded(
//                   child: TextFormField(
//                     controller: _nbMaleController,
//                     decoration: const InputDecoration(
//                       labelText: 'Number of Male *',
//                       border: OutlineInputBorder(),
//                       prefixIcon: Icon(Icons.male),
//                     ),
//                     keyboardType: TextInputType.number,
//                   ),
//                 ),
//                 const SizedBox(width: 16),
//                 Expanded(
//                   child: TextFormField(
//                     controller: _nbFemaleController,
//                     decoration: const InputDecoration(
//                       labelText: 'Number of Female *',
//                       border: OutlineInputBorder(),
//                       prefixIcon: Icon(Icons.female),
//                     ),
//                     keyboardType: TextInputType.number,
//                   ),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 24),
//
//             Container(
//               padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
//               decoration: BoxDecoration(
//                 color: AppColors.primary.withOpacity(0.1),
//                 borderRadius: BorderRadius.circular(8),
//               ),
//               child: Row(
//                 children: [
//                   Icon(Icons.help_outline, color: AppColors.primary, size: 20),
//                   const SizedBox(width: 8),
//                   Expanded(
//                     child: Text(
//                       'Observation Questions',
//                       style: TextStyle(
//                         fontSize: 16,
//                         fontWeight: FontWeight.bold,
//                         color: AppColors.primary,
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//             const SizedBox(height: 8),
//             const Text(
//               'All questions are Yes/No (1 pt = Yes, 0 pt = No)',
//               style: TextStyle(
//                 fontSize: 12,
//                 color: Colors.grey,
//                 fontStyle: FontStyle.italic,
//               ),
//             ),
//             const SizedBox(height: 16),
//
//             if (_questions.isEmpty)
//               const Center(child: Text('No questions available'))
//             else
//               ListView.builder(
//                 shrinkWrap: true,
//                 physics: const NeverScrollableScrollPhysics(),
//                 itemCount: _questions.length,
//                 itemBuilder: (context, qIndex) {
//                   final q = _questions[qIndex];
//                   final qId = q['id'] as String;
//                   final number = q['number'] as String;
//
//                   return Container(
//                     margin: const EdgeInsets.only(bottom: 12),
//                     padding: const EdgeInsets.all(12),
//                     decoration: BoxDecoration(
//                       border: Border.all(color: Colors.grey.shade300),
//                       borderRadius: BorderRadius.circular(8),
//                     ),
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Text(
//                           '$number. ${q['name']}',
//                           style: const TextStyle(
//                             fontSize: 14,
//                             fontWeight: FontWeight.w500,
//                           ),
//                         ),
//                         const SizedBox(height: 12),
//                         Row(
//                           children: [
//                             Expanded(child: _radioOption(qId, 1, 'Yes')),
//                             Expanded(child: _radioOption(qId, 0, 'No')),
//                           ],
//                         ),
//                       ],
//                     ),
//                   );
//                 },
//               ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: CustomAppBar(
//         title: 'Classroom Observation',
//         backgroundColor: AppColors.primary,
//         textColor: Colors.white,
//         leading: IconButton(
//           icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
//           onPressed: () => context.pop(),
//         ),
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.sync, color: Colors.white),
//             tooltip: 'Offline Observations',
//             onPressed: () => context.push('/offline-classroom-observation'),
//           ),
//         ],
//       ),
//       body: StreamBuilder<bool>(
//         stream: LocalStorageService.onlineStatusStream,
//         initialData: true,
//         builder: (context, snapshot) {
//           final isOnline = snapshot.data ?? true;
//
//           return Column(
//             children: [
//               if (!isOnline)
//                 Container(
//                   width: double.infinity,
//                   color: Colors.orange.shade100,
//                   padding: const EdgeInsets.all(12),
//                   child: Text(
//                     'Offline Mode — Data will be saved locally',
//                     textAlign: TextAlign.center,
//                     style: TextStyle(
//                       color: Colors.deepOrange.shade700,
//                       fontWeight: FontWeight.w600,
//                     ),
//                   ),
//                 ),
//               Expanded(
//                 child: LoadingOverlay(
//                   isLoading: _isLoading || _isFetchingDropdowns,
//                   child: RefreshIndicator(
//                     onRefresh: _refreshDataIfOnline,
//                     child: SingleChildScrollView(
//                       physics: const AlwaysScrollableScrollPhysics(),
//                       padding: const EdgeInsets.all(16.0),
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           const SizedBox(height: 8),
//
//                           Card(
//                             color: AppColors.primary.withOpacity(0.05),
//                             child: Padding(
//                               padding: const EdgeInsets.all(12),
//                               child: Row(
//                                 children: [
//                                   Icon(Icons.school, color: AppColors.primary),
//                                   const SizedBox(width: 8),
//                                   Expanded(
//                                     child: Column(
//                                       crossAxisAlignment:
//                                       CrossAxisAlignment.start,
//                                       children: [
//                                         Text(
//                                           schoolName ?? 'Unknown School',
//                                           style: const TextStyle(
//                                             fontWeight: FontWeight.bold,
//                                           ),
//                                         ),
//                                         Text(
//                                           'Level: ${schoolLevel ?? 'N/A'} | Code: ${schoolCode ?? 'N/A'}',
//                                           style: TextStyle(
//                                             color: Colors.grey[600],
//                                             fontSize: 12,
//                                           ),
//                                         ),
//                                       ],
//                                     ),
//                                   ),
//                                 ],
//                               ),
//                             ),
//                           ),
//
//                           const SizedBox(height: 24),
//
//                           _buildObservationCard(),
//
//                           SizedBox(
//                             width: double.infinity,
//                             child: ElevatedButton.icon(
//                               icon: const Icon(Icons.check_circle),
//                               label: const Text(
//                                 'Submit Observation',
//                                 style: TextStyle(
//                                   fontSize: 16,
//                                   fontWeight: FontWeight.bold,
//                                 ),
//                               ),
//                               onPressed: _isSubmitting ? null : _submit,
//                               style: ElevatedButton.styleFrom(
//                                 backgroundColor: AppColors.primary,
//                                 foregroundColor: Colors.white,
//                                 shape: RoundedRectangleBorder(
//                                   borderRadius: BorderRadius.circular(12),
//                                 ),
//                                 padding:
//                                 const EdgeInsets.symmetric(vertical: 16),
//                               ),
//                             ),
//                           ),
//
//                           const SizedBox(height: 80),
//                         ],
//                       ),
//                     ),
//                   ),
//                 ),
//               ),
//             ],
//           );
//         },
//       ),
//     );
//   }
// }