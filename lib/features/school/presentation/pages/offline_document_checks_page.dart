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

  @override
  void initState() {
    super.initState();
    _loadPendingChecks();
  }

  Future<void> _loadPendingChecks() async {
    setState(() {
      _pendingChecks = LocalStorageService.getPendingDocumentChecks();
    });
  }

  Future<void> _syncAll() async {
    if (!await LocalStorageService.isOnline()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No internet connection. Connect and try again.'),
          backgroundColor: Colors.orange,
        ),
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
        SnackBar(
          content: Text('$successCount document check(s) synced successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No document checks were synced.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  /// Syncs one queued document check payload
  Future<bool> _syncSingleCheck(Map<String, dynamic> check) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!auth.isAuthenticated || auth.token == null) {
      debugPrint('Cannot sync document check: not authenticated');
      return false;
    }

    final token = auth.token!;
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    };

    final schoolCode = check['school'] ?? 'unknown';
    debugPrint('Syncing document check for school: $schoolCode (queued: ${check['queuedAt']})');

    try {
      final res = await http.post(
        Uri.parse('${AppUrl.url}/document-check'),
        headers: headers,
        body: jsonEncode(check),
      );

      debugPrint('Document check sync response: ${res.statusCode}');

      if (res.statusCode == 200 || res.statusCode == 201) {
        return true;
      } else {
        debugPrint('Document check sync failed: ${res.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Document check sync error: $e');
      return false;
    }
  }

  Future<void> _removeFromPending(Map<String, dynamic> checkToRemove) async {
    final current = LocalStorageService.getPendingDocumentChecks();
    final updated = current.where((c) {
      return c['queuedAt'] != checkToRemove['queuedAt'];
    }).toList();

    final box = Hive.box(LocalStorageService.pendingDocumentChecksBox);
    await box.put('pending', updated);

    setState(() {
      _pendingChecks = updated;
    });
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
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _removeFromPending(check);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pending document check deleted'), backgroundColor: Colors.red),
      );
    }
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
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh list',
            onPressed: _loadPendingChecks,
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
                    'Offline Mode — Sync buttons disabled until connected',
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
                      const Text(
                        'No Pending Document Checks',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'All submissions have been synced or cleared.',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
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
                        child: ListTile(
                          contentPadding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                          leading: CircleAvatar(
                            radius: 30,
                            backgroundColor: AppColors.primary.withOpacity(0.15),
                            child: Icon(Icons.description_rounded, color: AppColors.primary, size: 32),
                          ),
                          title: Text(
                            check['school'] ?? 'Unnamed School',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Code: ${check['school'] ?? 'N/A'}', style: const TextStyle(fontSize: 14)),
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
                                tooltip: 'Delete this pending submission',
                                onPressed: () => _deletePending(index),
                              ),
                              IconButton(
                                icon: const Icon(Icons.sync_rounded, color: AppColors.primary),
                                tooltip: isOnline ? 'Sync now' : 'Offline - connect to sync',
                                onPressed: isOnline
                                    ? () async {
                                  setState(() => _isSyncing = true);
                                  final success = await _syncSingleCheck(check);
                                  if (success) {
                                    await _removeFromPending(check);
                                    await _loadPendingChecks();
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
      floatingActionButton: _pendingChecks.isNotEmpty
          ? StreamBuilder<bool>(
        stream: LocalStorageService.onlineStatusStream,
        initialData: true,
        builder: (context, snapshot) {
          final bool canSync = snapshot.data ?? false;

          return FloatingActionButton.extended(
            heroTag: 'sync_all_document_checks',
            onPressed: canSync && !_isSyncing ? _syncAll : null,
            backgroundColor: canSync ? AppColors.primary : Colors.grey,
            icon: _isSyncing
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
            )
                : const Icon(Icons.sync_rounded, color: Colors.white),
            label: Text(
              _isSyncing ? 'Syncing...' : 'Sync All (${_pendingChecks.length})',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          );
        },
      )
          : null,
    );
  }
}