import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/parent_local_storage_service.dart';
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
    _loadPending();
  }

  Future<void> _loadPending() async {
    final data = await ParentLocalStorageService.getPending();
    if (mounted) {
      setState(() => _pending = data);
    }
  }

  Future<void> _syncAll() async {
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
        title: const Text('Offline Parent Participation'),
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
      body: _pending.isEmpty
          ? const Center(child: Text('No pending parent participation entries'))
          : ListView.builder(
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
    );
  }
}