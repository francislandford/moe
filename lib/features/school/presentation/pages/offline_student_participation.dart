import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_url.dart';
import '../../../../core/services/student_local_storage_service.dart';
import '../../../../core/services/local_storage_service.dart';
import '../../../../core/widgets/custom_app_bar.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class OfflineStudentParticipationPage extends StatefulWidget {
  const OfflineStudentParticipationPage({super.key});

  @override
  State<OfflineStudentParticipationPage> createState() => _OfflineStudentParticipationPageState();
}

class _OfflineStudentParticipationPageState extends State<OfflineStudentParticipationPage> {
  bool _isSyncing = false;
  List<Map<String, dynamic>> _pendingStudent = [];

  // Cached questions
  List<Map<String, dynamic>> _questions = [];

  @override
  void initState() {
    super.initState();
    _loadPending();
    _loadQuestionsFromCache();
  }

  Future<void> _loadQuestionsFromCache() async {
    final cachedList = LocalStorageService.getFromCache('student_questions');
    if (cachedList != null && cachedList is List) {
      setState(() {
        _questions = cachedList.map((item) => Map<String, dynamic>.from(item)).toList();
      });
    }
  }

  Future<void> _loadPending() async {
    final data = await StudentLocalStorageService.getPending();
    if (mounted) {
      setState(() => _pendingStudent = data);
    }
  }

  Future<void> _syncAll() async {
    if (!await LocalStorageService.isOnline()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No internet. Connect and try again.'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isSyncing = true);
    int successCount = 0;
    final copy = List<Map<String, dynamic>>.from(_pendingStudent);

    for (var item in copy) {
      try {
        final success = await _syncSingle(item);
        if (success) {
          successCount++;
          await _removeFromPending(item);
        }
      } catch (e) {
        debugPrint('Student sync failed: $e');
      }
    }

    await _loadPending();
    setState(() => _isSyncing = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(successCount > 0 ? '$successCount student participation(s) synced!' : 'No entries synced.'),
        backgroundColor: successCount > 0 ? Colors.green : Colors.orange,
      ),
    );
  }

  Future<void> _syncSingleFromCard(Map<String, dynamic> payload) async {
    if (!await LocalStorageService.isOnline()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No internet connection. Connect and try again.'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isSyncing = true);
    final success = await _syncSingle(payload);

    if (success) {
      await _removeFromPending(payload);
      await _loadPending();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Synced successfully'), backgroundColor: Colors.green)
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync failed'), backgroundColor: Colors.orange)
      );
    }

    setState(() => _isSyncing = false);
  }

  Future<bool> _syncSingle(Map<String, dynamic> payload) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!auth.isAuthenticated || auth.token == null) return false;

    final headers = auth.getAuthHeaders();

    try {
      final res = await http.post(
        Uri.parse('${AppUrl.url}/student-participation'),
        headers: headers,
        body: jsonEncode(payload),
      );
      return (res.statusCode == 200 || res.statusCode == 201);
    } catch (e) {
      debugPrint('Student sync error: $e');
      return false;
    }
  }

  Future<void> _removeFromPending(Map<String, dynamic> toRemove) async {
    final current = await StudentLocalStorageService.getPending();
    final updated = current.where((p) => p['queuedAt'] != toRemove['queuedAt']).toList();

    // Save updated list back to storage
    final box = await Hive.openBox<List>('student_pending_box');
    await box.put('pending', updated);

    setState(() => _pendingStudent = updated);
  }

  Future<void> _updatePending(Map<String, dynamic> updatedItem) async {
    final current = await StudentLocalStorageService.getPending();
    final index = current.indexWhere((p) => p['queuedAt'] == updatedItem['queuedAt']);

    if (index != -1) {
      current[index] = updatedItem;

      // Save updated list back to storage
      final box = await Hive.openBox<List>('student_pending_box');
      await box.put('pending', current);

      setState(() {
        _pendingStudent = current;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Student participation updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _deletePending(int index) async {
    final item = _pendingStudent[index];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Pending Entry'),
        content: const Text('Are you sure? This unsynced data will be permanently removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')
          ),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _removeFromPending(item);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pending entry deleted'), backgroundColor: Colors.red)
      );
    }
  }

  String _formatDate(String? iso) {
    if (iso == null) return 'Unknown time';
    final date = DateTime.tryParse(iso);
    return date != null ? DateFormat('dd MMM yyyy, HH:mm').format(date) : 'Invalid date';
  }

  // Edit dialog for offline student data
  void _showEditDialog(Map<String, dynamic> item) {
    // Create editable copy
    final editableItem = Map<String, dynamic>.from(item);

    // School code controller
    final schoolCodeController = TextEditingController(text: editableItem['school'] ?? '');

    // Get scores from the item
    Map<String, int> scores = {};
    if (editableItem['scores'] != null) {
      final scoresMap = editableItem['scores'] as Map;
      scoresMap.forEach((key, value) {
        if (value is int) {
          scores[key.toString()] = value;
        } else if (value is String) {
          scores[key.toString()] = int.tryParse(value) ?? 0;
        } else {
          scores[key.toString()] = 0;
        }
      });
    }

    // Create controllers for each score
    Map<String, TextEditingController> scoreControllers = {};
    scores.forEach((key, value) {
      scoreControllers[key] = TextEditingController(text: value.toString());
    });

    // Track score values
    Map<String, int> editedScores = Map.from(scores);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('Edit Student Participation: ${editableItem['school'] ?? 'Unnamed'}'),
            content: Container(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // School Information
                    const Text('School Information', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: schoolCodeController,
                      decoration: const InputDecoration(
                        labelText: 'School Code',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => editableItem['school'] = value,
                    ),
                    const SizedBox(height: 16),

                    // Student Participation Questions
                    const Text('Student Participation Questions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),

                    // Instructions from original page
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Meet or assemble a group of at least six randomly selected students (50% male and 50% female) without the presence of the principal or teachers.',
                        style: TextStyle(fontSize: 12, color: Colors.blue),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Scoring guide
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'All questions are 1 point each (Yes = 1, No = 0)',
                        style: TextStyle(fontSize: 12, color: Colors.green),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Display questions with their text
                    ..._questions.asMap().entries.map((entry) {
                      final index = entry.key;
                      final question = entry.value;
                      final questionId = question['id']?.toString() ?? (index + 1).toString();
                      final questionNumber = index + 1;
                      final questionText = question['name'] ?? 'Question ${index + 1}';
                      final currentValue = editedScores[questionId] ?? 0;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$questionNumber. $questionText',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _buildScoreOption(
                                    label: 'Yes (1)',
                                    value: 1,
                                    groupValue: currentValue,
                                    onChanged: (v) {
                                      setState(() {
                                        editedScores[questionId] = v;
                                        if (!scoreControllers.containsKey(questionId)) {
                                          scoreControllers[questionId] = TextEditingController(text: v.toString());
                                        } else {
                                          scoreControllers[questionId]?.text = v.toString();
                                        }
                                      });
                                    },
                                  ),
                                  _buildScoreOption(
                                    label: 'No (0)',
                                    value: 0,
                                    groupValue: currentValue,
                                    onChanged: (v) {
                                      setState(() {
                                        editedScores[questionId] = v;
                                        if (!scoreControllers.containsKey(questionId)) {
                                          scoreControllers[questionId] = TextEditingController(text: v.toString());
                                        } else {
                                          scoreControllers[questionId]?.text = v.toString();
                                        }
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  // Update the scores with edited values
                  final updatedScores = <String, int>{};
                  editedScores.forEach((key, value) {
                    updatedScores[key] = value;
                  });

                  editableItem['scores'] = updatedScores;
                  editableItem['school'] = schoolCodeController.text;

                  Navigator.pop(context);
                  await _updatePending(editableItem);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Update'),
              ),
            ],
          );
        },
      ),
    );
  }

  // Helper widget for score radio options
  Widget _buildScoreOption({
    required String label,
    required int value,
    required int groupValue,
    required Function(int) onChanged,
  }) {
    return Expanded(
      child: InkWell(
        onTap: () => onChanged(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: groupValue == value ? AppColors.primary.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: groupValue == value ? AppColors.primary : Colors.grey.shade300,
              width: groupValue == value ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Radio<int>(
                value: value,
                groupValue: groupValue,
                onChanged: (v) => onChanged(v ?? 0),
                activeColor: AppColors.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: groupValue == value ? FontWeight.bold : FontWeight.normal,
                  color: groupValue == value ? AppColors.primary : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Offline Student Participation',
        backgroundColor: AppColors.primary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
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
                    Icon(isOnline ? Icons.wifi : Icons.wifi_off, color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text(isOnline ? 'Online' : 'Offline', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh',
            onPressed: _loadPending,
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
                    'You are offline. Sync buttons are disabled until connected.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w600),
                  ),
                ),
              Expanded(
                child: _pendingStudent.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_done_rounded, size: 90, color: Colors.green.shade300),
                      const SizedBox(height: 20),
                      const Text('No Pending Student Participation Entries', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      const Text('All data synced or cleared.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                    ],
                  ),
                )
                    : RefreshIndicator(
                  onRefresh: _loadPending,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _pendingStudent.length,
                    itemBuilder: (context, index) {
                      final item = _pendingStudent[index];
                      final date = _formatDate(item['queuedAt']);
                      final scoreCount = (item['scores'] as Map?)?.length ?? 0;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        elevation: 3,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: InkWell(
                          onTap: () => _showEditDialog(item),
                          borderRadius: BorderRadius.circular(16),
                          child: ListTile(
                            contentPadding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                            leading: CircleAvatar(
                              radius: 30,
                              backgroundColor: AppColors.primary.withOpacity(0.15),
                              child: Icon(Icons.school_rounded, color: AppColors.primary, size: 32),
                            ),
                            title: Text(item['school'] ?? 'Unnamed School', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Code: ${item['school'] ?? 'N/A'}', style: const TextStyle(fontSize: 14)),
                                  Text('Queued: $date', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                                  const SizedBox(height: 4),
                                  Text('Data: $scoreCount questions answered', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                                ],
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
                                  tooltip: 'Edit this pending entry',
                                  onPressed: _isSyncing ? null : () => _showEditDialog(item),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                                  tooltip: 'Delete pending',
                                  onPressed: _isSyncing ? null : () => _deletePending(index),
                                ),
                                IconButton(
                                  icon: Icon(Icons.sync_rounded, color: isOnline ? AppColors.primary : Colors.grey),
                                  tooltip: isOnline ? 'Sync now' : 'Offline - connect to sync',
                                  onPressed: (isOnline && !_isSyncing) ? () => _syncSingleFromCard(item) : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: _pendingStudent.isNotEmpty
          ? StreamBuilder<bool>(
        stream: LocalStorageService.onlineStatusStream,
        initialData: LocalStorageService.currentOnlineStatus,
        builder: (context, snapshot) {
          final bool isOnline = snapshot.data ?? true;
          return FloatingActionButton.extended(
            heroTag: 'sync_all_student',
            onPressed: (isOnline && !_isSyncing) ? _syncAll : null,
            backgroundColor: isOnline ? AppColors.primary : Colors.grey,
            icon: _isSyncing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                : const Icon(Icons.sync_rounded, color: Colors.white),
            label: Text(_isSyncing ? 'Syncing...' : 'Sync All (${_pendingStudent.length})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          );
        },
      )
          : null,
    );
  }
}