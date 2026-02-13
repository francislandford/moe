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

class OfflineClassroomObservationPage extends StatefulWidget {
  const OfflineClassroomObservationPage({super.key});

  @override
  State<OfflineClassroomObservationPage> createState() => _OfflineClassroomObservationPageState();
}

class _OfflineClassroomObservationPageState extends State<OfflineClassroomObservationPage> {
  bool _isSyncing = false;
  List<Map<String, dynamic>> _pendingObservations = [];

  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  Future<void> _loadPending() async {
    setState(() {
      _pendingObservations = LocalStorageService.getPendingClassroomObservation();
    });
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
    final copy = List<Map<String, dynamic>>.from(_pendingObservations);

    for (var item in copy) {
      try {
        final success = await _syncSingle(item);
        if (success) {
          successCount++;
          await _removeFromPending(item);
        }
      } catch (e) {
        debugPrint('Sync failed: $e');
      }
    }

    await _loadPending();
    setState(() => _isSyncing = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(successCount > 0
            ? '$successCount classroom observation(s) synced!'
            : 'No observations synced.'),
        backgroundColor: successCount > 0 ? Colors.green : Colors.orange,
      ),
    );
  }

  Future<bool> _syncSingle(Map<String, dynamic> payload) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!auth.isAuthenticated || auth.token == null) return false;

    final headers = auth.getAuthHeaders();

    try {
      final res = await http.post(
        Uri.parse('${AppUrl.url}/classroom-observation'),
        headers: headers,
        body: jsonEncode(payload),
      );

      return (res.statusCode == 200 || res.statusCode == 201);
    } catch (e) {
      debugPrint('Classroom sync error: $e');
      return false;
    }
  }

  Future<void> _removeFromPending(Map<String, dynamic> toRemove) async {
    final current = LocalStorageService.getPendingClassroomObservation();
    final updated = current.where((p) => p['queuedAt'] != toRemove['queuedAt']).toList();
    final box = Hive.box(LocalStorageService.pendingClassroomObservationBox);
    await box.put('pending', updated);
    setState(() => _pendingObservations = updated);
  }

  Future<void> _deletePending(int index) async {
    final item = _pendingObservations[index];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Pending Classroom Observation'),
        content: const Text('Are you sure? This unsynced data will be permanently removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _removeFromPending(item);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pending observation deleted'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Offline Classroom Observations',
        backgroundColor: AppColors.primary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh',
            onPressed: _loadPending,
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
                    'Offline Mode — Sync disabled until connected',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w600),
                  ),
                ),

              Expanded(
                child: _pendingObservations.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_done_rounded, size: 90, color: Colors.green.shade300),
                      const SizedBox(height: 20),
                      const Text('No Pending Classroom Observations', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      const Text('All data synced or cleared.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                    ],
                  ),
                )
                    : RefreshIndicator(
                  onRefresh: _loadPending,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _pendingObservations.length,
                    itemBuilder: (context, index) {
                      final item = _pendingObservations[index];
                      final date = item['queuedAt'] != null
                          ? DateFormat('dd MMM yyyy, HH:mm').format(DateTime.parse(item['queuedAt']))
                          : 'Unknown date';

                      final scoreCount = (item['scores'] as Map?)?.length ?? 0;
                      final classNum = item['class_num'] ?? '?';
                      final teacher = item['teacher'] ?? 'Unknown Teacher';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        elevation: 3,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                          leading: CircleAvatar(
                            radius: 30,
                            backgroundColor: AppColors.primary.withOpacity(0.15),
                            child: Icon(Icons.school_rounded, color: AppColors.primary, size: 32),
                          ),
                          title: Text(
                            'Classroom $classNum - $teacher',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('School Code: ${item['school'] ?? 'N/A'}', style: const TextStyle(fontSize: 14)),
                                Text('Queued: $date', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                                const SizedBox(height: 4),
                                Text(
                                  'Data: $scoreCount questions answered',
                                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                                tooltip: 'Delete pending',
                                onPressed: () => _deletePending(index),
                              ),
                              IconButton(
                                icon: const Icon(Icons.sync_rounded, color: AppColors.primary),
                                tooltip: isOnline ? 'Sync now' : 'Offline - connect to sync',
                                onPressed: isOnline
                                    ? () async {
                                  setState(() => _isSyncing = true);
                                  final success = await _syncSingle(item);
                                  if (success) {
                                    await _removeFromPending(item);
                                    await _loadPending();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Synced successfully'), backgroundColor: Colors.green),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Sync failed'), backgroundColor: Colors.orange),
                                    );
                                  }
                                  setState(() => _isSyncing = false);
                                }
                                    : null,
                              ),
                            ],
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
      floatingActionButton: _pendingObservations.isNotEmpty
          ? StreamBuilder<bool>(
        stream: LocalStorageService.onlineStatusStream,
        initialData: true,
        builder: (context, snapshot) {
          final bool canSync = snapshot.data ?? false;

          return FloatingActionButton.extended(
            heroTag: 'sync_all_classroom',
            onPressed: canSync && !_isSyncing ? _syncAll : null,
            backgroundColor: canSync ? AppColors.primary : Colors.grey,
            icon: _isSyncing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                : const Icon(Icons.sync_rounded, color: Colors.white),
            label: Text(
              _isSyncing ? 'Syncing...' : 'Sync All (${_pendingObservations.length})',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          );
        },
      )
          : null,
    );
  }
}