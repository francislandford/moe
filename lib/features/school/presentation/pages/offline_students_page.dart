import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:moe/core/widgets/custom_app_bar.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
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
        final result = await provider.createSchool(school, context);

        if (result['success'] == true && result['offline'] != true) {
          successCount++;
          await _removeFromPending(school);
        } else if (result['message']?.contains('already exists') ?? false) {
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
      return s['school_code'] != schoolToRemove['school_code'];
    }).toList();

    final box = Hive.box(LocalStorageService.pendingSchoolsBox);
    await box.put('pending', updated);

    setState(() {
      _pendingSchools = updated;
    });
  }

  Future<void> _updatePendingSchool(Map<String, dynamic> updatedSchool) async {
    final currentPending = LocalStorageService.getPendingSchools();
    final index = currentPending.indexWhere((s) =>
    s['school_code'] == updatedSchool['school_code']);

    if (index != -1) {
      currentPending[index] = updatedSchool;
      final box = Hive.box(LocalStorageService.pendingSchoolsBox);
      await box.put('pending', currentPending);

      setState(() {
        _pendingSchools = currentPending;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('School data updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
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

  Future<void> _syncSingleSchool(Map<String, dynamic> school) async {
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

  // NEW: Show comprehensive edit dialog for offline school data
  void _showEditDialog(Map<String, dynamic> school) {
    // Text Controllers
    final schoolNameController = TextEditingController(text: school['school_name'] ?? '');
    final emisCodeController = TextEditingController(text: school['emis_code'] ?? '');
    final communityController = TextEditingController(text: school['community'] ?? '');
    final principalNameController = TextEditingController(text: school['principal_name'] ?? '');
    final contactController = TextEditingController(text: school['school_contact'] ?? '');
    final emailController = TextEditingController(text: school['email'] ?? '');
    final permitNumberController = TextEditingController(text: school['permit_num'] ?? '');
    final yearEstablishedController = TextEditingController(text: school['year_establish']?.toString() ?? '');
    final noRoomController = TextEditingController(text: school['nb_room']?.toString() ?? '');
    final teachersPresentController = TextEditingController(text: school['all_teacher_present'] ?? 'Yes');
    final verifyCommentController = TextEditingController(text: school['verify_comment'] ?? '');
    final latitudeController = TextEditingController(text: school['latitude']?.toString() ?? '');
    final longitudeController = TextEditingController(text: school['longitude']?.toString() ?? '');

    // Selection values
    String? selectedCounty = school['county'];
    String? selectedDistrict = school['district'];
    String? selectedLevel = school['school_level'];
    String? selectedType = school['school_type'];
    String? selectedOwnership = school['school_ownership'];
    String? permitStatus = school['permit'] ?? 'No';
    String? chargeFees = school['charge_fees'] ?? 'Yes';
    String? schoolClosed = school['school_closed'] ?? 'No';
    String? consent = school['compliance'] ?? 'No';
    String? firstAssessment = school['first_assessment'] ?? 'Yes';

    // Boolean values
    bool isTvet = school['tvet'] == '1' || school['tvet'] == 1 || school['tvet'] == true;
    bool isAccelerated = school['accelerated'] == '1' || school['accelerated'] == 1 || school['accelerated'] == true;
    bool isAlternative = school['alternative'] == '1' || school['alternative'] == 1 || school['alternative'] == true;
    bool isInclusive = school['inclusive'] == '1' || school['inclusive'] == 1 || school['inclusive'] == true;

    bool showCompliance = schoolClosed == 'No';
    bool hasConsent = consent == 'Yes';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('Edit School: ${school['school_name'] ?? 'Unnamed'}'),
            content: Container(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Location Section
                    const Text('Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: TextEditingController(text: selectedCounty ?? ''),
                      decoration: const InputDecoration(
                        labelText: 'County',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => selectedCounty = value,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: TextEditingController(text: selectedDistrict ?? ''),
                      decoration: const InputDecoration(
                        labelText: 'District',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => selectedDistrict = value,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: communityController,
                      decoration: const InputDecoration(
                        labelText: 'Community / Village',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // School Identity Section
                    const Text('School Identity', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: schoolNameController,
                      decoration: const InputDecoration(
                        labelText: 'School Name *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: TextEditingController(text: selectedLevel ?? ''),
                      decoration: const InputDecoration(
                        labelText: 'School Level',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => selectedLevel = value,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: TextEditingController(text: selectedType ?? ''),
                      decoration: const InputDecoration(
                        labelText: 'School Type',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => selectedType = value,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: TextEditingController(text: selectedOwnership ?? ''),
                      decoration: const InputDecoration(
                        labelText: 'School Ownership',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => selectedOwnership = value,
                    ),
                    const SizedBox(height: 8),

                    // School Closed & Compliance
                    DropdownButtonFormField<String>(
                      value: schoolClosed,
                      decoration: const InputDecoration(
                        labelText: 'Is school Closed?',
                        border: OutlineInputBorder(),
                      ),
                      items: const ['Yes', 'No']
                          .map((item) => DropdownMenuItem<String>(
                        value: item,
                        child: Text(item),
                      )).toList(),
                      onChanged: (v) {
                        setState(() {
                          schoolClosed = v;
                          showCompliance = v == 'No';
                          if (v == 'Yes') {
                            consent = 'No';
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 8),

                    if (showCompliance) ...[
                      DropdownButtonFormField<String>(
                        value: consent,
                        decoration: const InputDecoration(
                          labelText: 'Compliant',
                          border: OutlineInputBorder(),
                        ),
                        items: const ['Yes', 'No']
                            .map((item) => DropdownMenuItem<String>(
                          value: item,
                          child: Text(item),
                        )).toList(),
                        onChanged: (v) {
                          setState(() {
                            consent = v;
                            hasConsent = v == 'Yes';
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                    ],

                    if (showCompliance && hasConsent) ...[
                      const SizedBox(height: 16),
                      const Text('Classification', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: emisCodeController,
                        decoration: const InputDecoration(
                          labelText: 'EMIS Code (Optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: noRoomController,
                        decoration: const InputDecoration(
                          labelText: 'Number of Rooms *',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 8),

                      // Program switches
                      Row(
                        children: [
                          Expanded(
                            child: Text('Offers TVET Program'),
                          ),
                          Switch(
                            value: isTvet,
                            onChanged: (v) => setState(() => isTvet = v),
                            activeColor: AppColors.primary,
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text('Accelerated Learning Program'),
                          ),
                          Switch(
                            value: isAccelerated,
                            onChanged: (v) => setState(() => isAccelerated = v),
                            activeColor: AppColors.primary,
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text('Alternative Education'),
                          ),
                          Switch(
                            value: isAlternative,
                            onChanged: (v) => setState(() => isAlternative = v),
                            activeColor: AppColors.primary,
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text('Inclusive and Special School'),
                          ),
                          Switch(
                            value: isInclusive,
                            onChanged: (v) => setState(() => isInclusive = v),
                            activeColor: AppColors.primary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Establishment & Permit
                      const Text('Establishment & Permit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: yearEstablishedController,
                        decoration: const InputDecoration(
                          labelText: 'Year Established',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: permitStatus,
                        decoration: const InputDecoration(
                          labelText: 'Permit Status',
                          border: OutlineInputBorder(),
                        ),
                        items: const ['Yes', 'No', 'Pending']
                            .map((item) => DropdownMenuItem<String>(
                          value: item,
                          child: Text(item),
                        )).toList(),
                        onChanged: (v) => setState(() => permitStatus = v),
                      ),
                      if (permitStatus == 'Yes') ...[
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: permitNumberController,
                          decoration: const InputDecoration(
                            labelText: 'Permit Number *',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Contact Section
                      const Text('Contact', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: principalNameController,
                        decoration: const InputDecoration(
                          labelText: 'Principal / Head Teacher Name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: contactController,
                        decoration: const InputDecoration(
                          labelText: 'School Contact Phone',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: emailController,
                        decoration: const InputDecoration(
                          labelText: 'School Email',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 16),

                      // Assessment Information
                      const Text('Assessment Information', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: firstAssessment,
                        decoration: const InputDecoration(
                          labelText: 'First assessment at this school?',
                          border: OutlineInputBorder(),
                        ),
                        items: const ['Yes', 'No']
                            .map((item) => DropdownMenuItem<String>(
                          value: item,
                          child: Text(item),
                        )).toList(),
                        onChanged: (v) => setState(() => firstAssessment = v),
                      ),
                    ],

                    // Coordinates (always visible)
                    const SizedBox(height: 16),
                    const Text('Coordinates', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: latitudeController,
                            decoration: const InputDecoration(
                              labelText: 'Latitude',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: longitudeController,
                            decoration: const InputDecoration(
                              labelText: 'Longitude',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
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
                  // Build updated school data
                  final updatedSchool = Map<String, dynamic>.from(school);

                  // Update all fields
                  updatedSchool['school_name'] = schoolNameController.text;
                  updatedSchool['emis_code'] = emisCodeController.text;
                  updatedSchool['community'] = communityController.text;
                  updatedSchool['principal_name'] = principalNameController.text;
                  updatedSchool['school_contact'] = contactController.text;
                  updatedSchool['email'] = emailController.text;
                  updatedSchool['permit_num'] = permitNumberController.text;
                  updatedSchool['year_establish'] = int.tryParse(yearEstablishedController.text);
                  updatedSchool['nb_room'] = int.tryParse(noRoomController.text);
                  updatedSchool['all_teacher_present'] = teachersPresentController.text;
                  updatedSchool['verify_comment'] = verifyCommentController.text;
                  updatedSchool['latitude'] = double.tryParse(latitudeController.text);
                  updatedSchool['longitude'] = double.tryParse(longitudeController.text);

                  // Update selections
                  updatedSchool['county'] = selectedCounty;
                  updatedSchool['district'] = selectedDistrict;
                  updatedSchool['school_level'] = selectedLevel;
                  updatedSchool['school_type'] = selectedType;
                  updatedSchool['school_ownership'] = selectedOwnership;
                  updatedSchool['permit'] = permitStatus;
                  updatedSchool['charge_fees'] = chargeFees;
                  updatedSchool['school_closed'] = schoolClosed;
                  updatedSchool['compliance'] = consent;
                  updatedSchool['first_assessment'] = firstAssessment;

                  // Update booleans
                  updatedSchool['tvet'] = isTvet ? '1' : '0';
                  updatedSchool['accelerated'] = isAccelerated ? '1' : '0';
                  updatedSchool['alternative'] = isAlternative ? '1' : '0';
                  updatedSchool['inclusive'] = isInclusive ? '1' : '0';

                  Navigator.pop(context); // Close dialog
                  await _updatePendingSchool(updatedSchool);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Offline Registrations',
        backgroundColor: AppColors.primary,
        leading: IconButton(
          icon: const Icon(Icons.home, color: Colors.white),
          tooltip: 'Back to Home',
          onPressed: () => context.pop(),
        ),
        actions: [
          // Online/Offline Indicator
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
                    Icon(
                      isOnline ? Icons.wifi : Icons.wifi_off,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isOnline ? 'Online' : 'Offline',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh list',
            onPressed: _loadPendingSchools,
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
                        child: InkWell(
                          onTap: () => _showEditDialog(school),
                          borderRadius: BorderRadius.circular(16),
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
                                  icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
                                  tooltip: 'Edit this pending entry',
                                  onPressed: _isSyncing ? null : () => _showEditDialog(school),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                                  tooltip: 'Delete this pending entry',
                                  onPressed: _isSyncing ? null : () => _deletePending(index),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.sync_rounded,
                                    color: isOnline ? AppColors.primary : Colors.grey,
                                  ),
                                  tooltip: isOnline
                                      ? 'Sync now'
                                      : 'Offline - connect to sync',
                                  onPressed: (isOnline && !_isSyncing)
                                      ? () => _syncSingleSchool(school)
                                      : null,
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
      floatingActionButton: _pendingSchools.isNotEmpty
          ? StreamBuilder<bool>(
        stream: LocalStorageService.onlineStatusStream,
        initialData: LocalStorageService.currentOnlineStatus,
        builder: (context, snapshot) {
          final bool isOnline = snapshot.data ?? true;

          return FloatingActionButton.extended(
            heroTag: 'sync_all',
            onPressed: (isOnline && !_isSyncing) ? _syncAll : null,
            backgroundColor: isOnline ? AppColors.primary : Colors.grey,
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