import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_url.dart';
import '../../../../core/services/local_storage_service.dart';
import '../../../../core/widgets/custom_app_bar.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class OfflineDocumentChecksPage extends StatefulWidget {
  const OfflineDocumentChecksPage({super.key});

  @override
  State<OfflineDocumentChecksPage> createState() => _OfflineDocumentChecksPageState();
}

class _OfflineDocumentChecksPageState extends State<OfflineDocumentChecksPage> {
  bool _isSyncing = false;
  List<Map<String, dynamic>> _pendingChecks = [];

  // Cached questions
  List<Map<String, dynamic>> _mainQuestions = [];
  List<Map<String, dynamic>> _additionalQuestions = [];

  @override
  void initState() {
    super.initState();
    _loadPendingChecks();
    _loadQuestionsFromCache();
  }

  Future<void> _loadQuestionsFromCache() async {
    // Load main questions
    final mainCached = LocalStorageService.getFromCache('document_check_questions');
    if (mainCached != null && mainCached is List) {
      _mainQuestions = mainCached.map((item) => Map<String, dynamic>.from(item)).toList();
    }

    // Load additional questions
    final additionalCached = LocalStorageService.getFromCache('additional_document_questions');
    if (additionalCached != null && additionalCached is List) {
      _additionalQuestions = additionalCached.map((item) => Map<String, dynamic>.from(item)).toList();
    }
  }

  Future<void> _loadPendingChecks() async {
    setState(() {
      _pendingChecks = LocalStorageService.getPendingDocumentChecks();
    });
  }

  Future<void> _syncAll() async {
    if (!await LocalStorageService.isOnline()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No internet connection. Connect and try again.'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isSyncing = true);

    int successCount = 0;
    final pendingCopy = List<Map<String, dynamic>>.from(_pendingChecks);

    for (var check in pendingCopy) {
      try {
        final success = await _syncSingleCheck(check);
        if (success) {
          successCount++;
          await _removeFromPending(check);
        }
      } catch (e) {
        debugPrint('Sync failed for one document check: $e');
      }
    }

    await _loadPendingChecks();
    setState(() => _isSyncing = false);

    if (successCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$successCount document check(s) synced successfully!'), backgroundColor: Colors.green),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No document checks were synced.'), backgroundColor: Colors.orange),
      );
    }
  }

  Future<void> _syncSingleCheckFromCard(Map<String, dynamic> check) async {
    if (!await LocalStorageService.isOnline()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No internet connection. Connect and try again.'), backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() => _isSyncing = true);
    final success = await _syncSingleCheck(check);
    if (success) {
      await _removeFromPending(check);
      await _loadPendingChecks();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Synced successfully'), backgroundColor: Colors.green));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sync failed'), backgroundColor: Colors.orange));
    }
    setState(() => _isSyncing = false);
  }

  Future<bool> _syncSingleCheck(Map<String, dynamic> check) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!auth.isAuthenticated || auth.token == null) return false;
    final headers = auth.getAuthHeaders();
    try {
      final res = await http.post(
        Uri.parse('${AppUrl.url}/document-check'),
        headers: headers,
        body: jsonEncode(check),
      );
      return (res.statusCode == 200 || res.statusCode == 201);
    } catch (e) {
      debugPrint('Document check sync error: $e');
      return false;
    }
  }

  Future<void> _removeFromPending(Map<String, dynamic> checkToRemove) async {
    final current = LocalStorageService.getPendingDocumentChecks();
    final updated = current.where((c) => c['queuedAt'] != checkToRemove['queuedAt']).toList();
    final box = Hive.box(LocalStorageService.pendingDocumentChecksBox);
    await box.put('pending', updated);
    setState(() => _pendingChecks = updated);
  }

  Future<void> _updatePendingCheck(Map<String, dynamic> updatedCheck) async {
    final current = LocalStorageService.getPendingDocumentChecks();
    final index = current.indexWhere((c) => c['queuedAt'] == updatedCheck['queuedAt']);

    if (index != -1) {
      current[index] = updatedCheck;
      final box = Hive.box(LocalStorageService.pendingDocumentChecksBox);
      await box.put('pending', current);

      setState(() {
        _pendingChecks = current;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Document check updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _deletePending(int index) async {
    final check = _pendingChecks[index];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Pending Document Check'),
        content: const Text('Are you sure? This unsynced submission will be permanently removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await _removeFromPending(check);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pending document check deleted'), backgroundColor: Colors.red));
    }
  }

  // NEW: Edit dialog for offline document check data with actual questions
  void _showEditDialog(Map<String, dynamic> check) {
    // Create editable copies
    final editableCheck = Map<String, dynamic>.from(check);

    // School code controller
    final schoolCodeController = TextEditingController(text: editableCheck['school'] ?? '');

    // Get scores from the check
    Map<String, int> scores = {};
    if (editableCheck['scores'] != null) {
      final scoresMap = editableCheck['scores'] as Map;
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
            title: Text('Edit Document Check: ${editableCheck['school'] ?? 'Unnamed'}'),
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
                      onChanged: (value) => editableCheck['school'] = value,
                    ),
                    const SizedBox(height: 16),

                    // Main Questions Scores
                    const Text('Document Check Questions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),

                    // Display main questions with their text
                    ..._mainQuestions.asMap().entries.map((entry) {
                      final index = entry.key;
                      final question = entry.value;
                      final questionId = (index + 1).toString(); // Questions are numbered 1,2,3...
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
                                '${index + 1}. $questionText',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _buildScoreOption(
                                    label: 'Yes (up-to-date)',
                                    value: 2,
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
                                    label: 'Yes (not up-to-date)',
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
                                    label: 'No',
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

                    const SizedBox(height: 16),

                    // Additional Questions (if available)
                    if (_additionalQuestions.isNotEmpty) ...[
                      const Text('Additional Questions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary)),
                      const SizedBox(height: 8),

                      ..._additionalQuestions.asMap().entries.map((entry) {
                        final index = entry.key;
                        final question = entry.value;
                        final questionId = (index + _mainQuestions.length + 1).toString();
                        final questionText = question['name'] ?? 'Additional Question ${index + 1}';
                        final currentValue = editedScores[questionId] ?? 0;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${index + 1}. $questionText',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _buildScoreOption(
                                      label: 'Yes (up-to-date)',
                                      value: 2,
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
                                      label: 'Yes (not up-to-date)',
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
                                      label: 'No',
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

                  editableCheck['scores'] = updatedScores;
                  editableCheck['school'] = schoolCodeController.text;

                  Navigator.pop(context);
                  await _updatePendingCheck(editableCheck);
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
                  fontSize: 11,
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
        title: 'Offline Document Checks',
        backgroundColor: AppColors.primary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          tooltip: 'Back to Home',
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
            tooltip: 'Refresh list',
            onPressed: _loadPendingChecks,
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
                child: _pendingChecks.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_done_rounded, size: 90, color: Colors.green.shade300),
                      const SizedBox(height: 20),
                      const Text('No Pending Document Checks', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      const Text('All submissions have been synced or cleared.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                    ],
                  ),
                )
                    : RefreshIndicator(
                  onRefresh: _loadPendingChecks,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _pendingChecks.length,
                    itemBuilder: (context, index) {
                      final check = _pendingChecks[index];
                      final date = check['queuedAt'] != null
                          ? DateFormat('dd MMM yyyy, HH:mm').format(DateTime.parse(check['queuedAt']))
                          : 'Unknown date';
                      final scoreCount = (check['scores'] as Map?)?.length ?? 0;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        elevation: 3,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: InkWell(
                          onTap: () => _showEditDialog(check),
                          borderRadius: BorderRadius.circular(16),
                          child: ListTile(
                            contentPadding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                            leading: CircleAvatar(
                              radius: 30,
                              backgroundColor: AppColors.primary.withOpacity(0.15),
                              child: Icon(Icons.description_rounded, color: AppColors.primary, size: 32),
                            ),
                            title: Text(check['school'] ?? 'Unnamed School', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Code: ${check['school'] ?? 'N/A'}', style: const TextStyle(fontSize: 14)),
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
                                  tooltip: 'Edit this pending check',
                                  onPressed: _isSyncing ? null : () => _showEditDialog(check),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                                  tooltip: 'Delete this pending submission',
                                  onPressed: _isSyncing ? null : () => _deletePending(index),
                                ),
                                IconButton(
                                  icon: Icon(Icons.sync_rounded, color: isOnline ? AppColors.primary : Colors.grey),
                                  tooltip: isOnline ? 'Sync now' : 'Offline - connect to sync',
                                  onPressed: (isOnline && !_isSyncing) ? () => _syncSingleCheckFromCard(check) : null,
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
      floatingActionButton: _pendingChecks.isNotEmpty
          ? StreamBuilder<bool>(
        stream: LocalStorageService.onlineStatusStream,
        initialData: LocalStorageService.currentOnlineStatus,
        builder: (context, snapshot) {
          final bool isOnline = snapshot.data ?? true;
          return FloatingActionButton.extended(
            heroTag: 'sync_all_document_checks',
            onPressed: (isOnline && !_isSyncing) ? _syncAll : null,
            backgroundColor: isOnline ? AppColors.primary : Colors.grey,
            icon: _isSyncing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                : const Icon(Icons.sync_rounded, color: Colors.white),
            label: Text(_isSyncing ? 'Syncing...' : 'Sync All (${_pendingChecks.length})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          );
        },
      )
          : null,
    );
  }
}