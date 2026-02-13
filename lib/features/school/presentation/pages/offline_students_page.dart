import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:moe/core/widgets/custom_app_bar.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart'; // for nice date formatting
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/local_storage_service.dart';
import '../../../../core/widgets/loading_overlay.dart';
import '../providers/school_provider.dart';

class OfflineStudentsPage extends StatefulWidget {
  const OfflineStudentsPage({super.key});

  @override
  State<OfflineStudentsPage> createState() => _OfflineStudentsPageState();
}

class _OfflineStudentsPageState extends State<OfflineStudentsPage> {
  bool _isSyncing = false;
  List<Map<String, dynamic>> _pendingSchools = [];

  @override
  void initState() {
    super.initState();
    _loadPendingSchools();
  }

  Future<void> _loadPendingSchools() async {
    setState(() {
      _pendingSchools = LocalStorageService.getPendingSchools();
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

    final provider = Provider.of<SchoolProvider>(context, listen: false);
    int successCount = 0;
    int skippedCount = 0;

    final pendingCopy = List<Map<String, dynamic>>.from(_pendingSchools);

    for (var school in pendingCopy) {
      try {
        // Optional: Check if school_code already exists on server
        // (You'd need a GET /schools?code=... endpoint - skip for now if not available)
        final result = await provider.createSchool(school, context);

        if (result['success'] == true && result['offline'] != true) {
          successCount++;
          await _removeFromPending(school);
        } else if (result['message']?.contains('already exists') ?? false) {
          // If server says duplicate, remove from pending
          skippedCount++;
          await _removeFromPending(school);
        }
      } catch (e) {
        debugPrint('Sync failed for one school: $e');
      }
    }

    await _loadPendingSchools();

    setState(() => _isSyncing = false);

    if (successCount > 0 || skippedCount > 0) {
      String msg = '';
      if (successCount > 0) msg += '$successCount synced successfully. ';
      if (skippedCount > 0) msg += '$skippedCount were duplicates and removed.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg.trim()), backgroundColor: Colors.green),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No changes synced. Try again later.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _removeFromPending(Map<String, dynamic> schoolToRemove) async {
    final currentPending = LocalStorageService.getPendingSchools();
    final updated = currentPending.where((s) {
      // Use school_code as unique identifier (adjust if needed)
      return s['school_code'] != schoolToRemove['school_code'];
    }).toList();

    final box = Hive.box(LocalStorageService.pendingSchoolsBox);
    await box.put('pending', updated);

    setState(() {
      _pendingSchools = updated;
    });
  }

  Future<void> _deletePending(int index) async {
    final school = _pendingSchools[index];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Pending Registration'),
        content: const Text('Are you sure you want to delete this unsynced school?'),
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
      await _removeFromPending(school);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pending registration deleted'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(title: 'Offline Registrations',
        backgroundColor: AppColors.primary,
        leading: IconButton(
          icon: const Icon(Icons.home, color: Colors.white),
          tooltip: 'Back to Home',
          onPressed: () => context.pop()

          ,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh list',
            onPressed: _loadPendingSchools,
          ),
        ],
      ),
      body: FutureBuilder<bool>(
        future: LocalStorageService.isOnline(),
        builder: (context, snapshot) {
          final bool isOnline = snapshot.data ?? false;

          return Column(
            children: [
              // Offline warning banner
              if (!isOnline)
                Container(
                  width: double.infinity,
                  color: Colors.orange.shade100,
                  padding: const EdgeInsets.all(12),
                  child: const Text(
                    'You are offline. Sync will be available when connected.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w600),
                  ),
                ),

              Expanded(
                child: _pendingSchools.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_done_rounded, size: 90, color: Colors.green.shade300),
                      const SizedBox(height: 20),
                      const Text(
                        'No Pending Registrations',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'All data has been synced or cleared.',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ],
                  ),
                )
                    : RefreshIndicator(
                  onRefresh: _loadPendingSchools,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _pendingSchools.length,
                    itemBuilder: (context, index) {
                      final school = _pendingSchools[index];
                      final date = school['queuedAt'] != null
                          ? DateFormat('dd MMM yyyy, HH:mm').format(DateTime.parse(school['queuedAt']))
                          : 'Unknown date';

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
                            school['school_name'] ?? 'Unnamed School',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Code: ${school['school_code'] ?? 'N/A'}', style: const TextStyle(fontSize: 14)),
                                Text(
                                  'Location: ${school['county'] ?? '?'} - ${school['district'] ?? '?'}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Queued: $date',
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                ),
                              ],
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                                tooltip: 'Delete this pending entry',
                                onPressed: () => _deletePending(index),
                              ),
                              IconButton(
                                icon: const Icon(Icons.sync_rounded, color: AppColors.primary),
                                tooltip: isOnline ? 'Sync now' : 'Offline - connect to sync',
                                onPressed: isOnline
                                    ? () async {
                                  setState(() => _isSyncing = true);
                                  final provider = Provider.of<SchoolProvider>(context, listen: false);
                                  final result = await provider.createSchool(school, context);
                                  if (result['success'] == true && result['offline'] != true) {
                                    await _removeFromPending(school);
                                    await _loadPendingSchools();
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
      floatingActionButton: _pendingSchools.isNotEmpty
          ? FutureBuilder<bool>(
        future: LocalStorageService.isOnline(),
        builder: (context, snapshot) {
          final bool canSync = snapshot.data ?? false;

          return FloatingActionButton.extended(
            heroTag: 'sync_all',
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
              _isSyncing ? 'Syncing...' : 'Sync All (${_pendingSchools.length})',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          );
        },
      )
          : null,
    );
  }
}