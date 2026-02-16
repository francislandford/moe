import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/parent_local_storage_service.dart';
import '../../../../core/services/local_storage_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class OfflineParentParticipationPage extends StatefulWidget {
  const OfflineParentParticipationPage({super.key});

  @override
  State<OfflineParentParticipationPage> createState() => _OfflineParentParticipationPageState();
}

class _OfflineParentParticipationPageState extends State<OfflineParentParticipationPage> {
  List<Map<String, dynamic>> _pending = [];
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    // Load from storage first (offline-first)
    _loadPending();
  }

  // Load pending items from storage (offline-first) — always first
  Future<void> _loadPending() async {
    final data = await ParentLocalStorageService.getPending();
    if (mounted) {
      setState(() => _pending = data);
    }
  }

  // Sync all pending items (only if online)
  Future<void> _syncAll() async {
    if (!await LocalStorageService.isOnline()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No internet. Connect and try again.'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isSyncing = true);

    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!auth.isAuthenticated || auth.token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not authenticated'), backgroundColor: Colors.red),
      );
      setState(() => _isSyncing = false);
      return;
    }

    final headers = auth.getAuthHeaders();

    await ParentLocalStorageService.syncPending(headers);

    await _loadPending();

    setState(() => _isSyncing = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sync attempted'), backgroundColor: Colors.green),
    );
  }

  // Delete single pending item
  Future<void> _deleteItem(Map<String, dynamic> item) async {
    await ParentLocalStorageService.removePending(item);
    await _loadPending();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Item deleted'), backgroundColor: Colors.orange),
    );
  }

  String _formatDate(String? iso) {
    if (iso == null) return 'Unknown time';
    final date = DateTime.tryParse(iso);
    return date != null ? DateFormat('dd MMM yyyy, HH:mm').format(date) : 'Invalid date';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Parent Participation',style: TextStyle(color: Colors.white)),
        backgroundColor: AppColors.primary,
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
                : const Icon(Icons.sync),
            onPressed: _isSyncing ? null : _syncAll,
            tooltip: 'Sync all',
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
                child: _pending.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_done_rounded, size: 90, color: Colors.green.shade300),
                      const SizedBox(height: 20),
                      const Text('No Pending Parent Participation Entries',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      const Text('All data synced or cleared.',
                          style: TextStyle(color: Colors.grey, fontSize: 16)),
                    ],
                  ),
                )
                    : RefreshIndicator(
                  onRefresh: _loadPending,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _pending.length,
                    itemBuilder: (context, index) {
                      final item = _pending[index];
                      final school = item['school'] ?? 'N/A';
                      final queuedAt = _formatDate(item['queuedAt']);
                      final scoreCount = (item['scores'] as Map?)?.length ?? 0;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: const Icon(Icons.cloud_upload, color: Colors.orange),
                          title: Text('School: $school'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Queued: $queuedAt'),
                              Text('Questions answered: $scoreCount'),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteItem(item),
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
      floatingActionButton: _pending.isNotEmpty
          ? StreamBuilder<bool>(
        stream: LocalStorageService.onlineStatusStream,
        initialData: true,
        builder: (context, snapshot) {
          final bool isOnline = snapshot.data ?? false;
          return FloatingActionButton.extended(
            heroTag: 'sync_all_parent',
            onPressed: _isSyncing || !isOnline ? null : _syncAll,
            backgroundColor: _isSyncing || !isOnline ? Colors.grey : AppColors.primary,
            icon: _isSyncing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                : const Icon(Icons.sync_rounded, color: Colors.white),
            label: Text(
              _isSyncing ? 'Syncing...' : 'Sync All (${_pending.length})',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            tooltip: isOnline ? 'Sync all pending' : 'Offline - connect to sync',
          );
        },
      )
          : null,
    );
  }
}