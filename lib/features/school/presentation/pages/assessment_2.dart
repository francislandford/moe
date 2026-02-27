import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/custom_app_bar.dart';
import '../providers/assessment_provider.dart';
import '../../../../core/services/local_storage_service.dart';

class SchoolAssessmentFormPage extends StatelessWidget {
  const SchoolAssessmentFormPage({super.key});

  @override
  Widget build(BuildContext context) {
    final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
    final String? schoolCode = extra?['schoolCode'] as String?;
    final String? schoolName = extra?['schoolName'] as String?;
    final String? schoolLevel = extra?['level'] as String?;

    return ChangeNotifierProvider(
      create: (_) {
        final provider = AssessmentProvider();
        provider.schoolName = schoolName ?? 'Unknown School';
        provider.schoolCode = schoolCode ?? '';
        provider.level = schoolLevel ?? 'ECE';
        provider.reqLevel = provider.level;

        // Load grades, positions, and fees from cache first, then refresh silently
        WidgetsBinding.instance.addPostFrameCallback((_) {
          provider.loadGradesFromCache(provider.level);
          provider.loadPositionsFromCache();
          provider.loadFeesFromCache();
          provider.fetchGradesForLevel(provider.level, context);
          provider.fetchPositions(context);
          provider.fetchFees(context);
        });

        return provider;
      },
      child: _SchoolAssessmentFormContent(
        schoolCode: schoolCode,
        schoolName: schoolName,
        schoolLevel: schoolLevel,
      ),
    );
  }
}

class _SchoolAssessmentFormContent extends StatefulWidget {
  final String? schoolCode;
  final String? schoolName;
  final String? schoolLevel;

  const _SchoolAssessmentFormContent({
    this.schoolCode,
    this.schoolName,
    this.schoolLevel,
  });

  @override
  State<_SchoolAssessmentFormContent> createState() => _SchoolAssessmentFormContentState();
}

class _SchoolAssessmentFormContentState extends State<_SchoolAssessmentFormContent> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // Calculate required teachers based on level and update UI
  void _onStudentsChanged(String value, AssessmentProvider provider) {
    provider.reqStudents = value;

    // Calculate required teachers
    final studentsText = value.trim();
    if (studentsText.isNotEmpty) {
      final students = int.tryParse(studentsText) ?? 0;
      if (students > 0) {
        if (provider.level.toUpperCase() == 'ECE') {
          provider.reqNumRequired = (students / 25).ceil().toString();
        } else {
          provider.reqNumRequired = (students / 45).ceil().toString();
        }
      } else {
        provider.reqNumRequired = '';
      }
    } else {
      provider.reqNumRequired = '';
    }

    // Force UI update
    provider.notifyListeners();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AssessmentProvider>(context);

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Assessment for ${provider.schoolName}',
        backgroundColor: AppColors.primary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        actions: [
          Consumer<AssessmentProvider>(
            builder: (context, prov, child) {
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.sync, color: Colors.white),
                    tooltip: 'Offline Assessments',
                    onPressed: () => context.push('/offline-assessments'),
                  ),
                  if (prov.pendingCount > 0)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          '${prov.pendingCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
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
                    'Offline Mode — Assessment will be saved locally and synced when online',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w600),
                  ),
                ),

              Expanded(
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ─── 1.1 Absent Teachers ───────────────────────────────
                        _buildAbsentTeachersSection(provider),
                        const SizedBox(height: 32),

                        // ─── 1.2 Total Staff with Position Dropdown ─────────────
                        _buildTotalStaffSection(provider),
                        const SizedBox(height: 32),

                        // ─── 1.3 Required Teachers ─────────────────────────────
                        _sectionCard(
                          title: '1.3 Teacher Required',
                          subtitle: 'The purpose of this section is to check how many teachers are required in different subjects. This data will form the basis for teacher supply or transfer.',
                          children: [
                            TextFormField(
                              initialValue: widget.schoolLevel ?? 'ECE',
                              decoration: const InputDecoration(
                                labelText: 'Level / Subject / Grade',
                                border: OutlineInputBorder(),
                              ),
                              enabled: false,
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              value: provider.reqSelfContain,
                              decoration: const InputDecoration(
                                labelText: 'Self-contained class?',
                                border: OutlineInputBorder(),
                              ),
                              items: const ['Yes', 'No', 'Partial']
                                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                                  .toList(),
                              onChanged: (v) => provider.reqSelfContain = v ?? 'No',
                              menuMaxHeight: 240,
                              dropdownColor: Theme.of(context).scaffoldBackgroundColor,
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue: provider.reqAssTeacher,
                                    decoration: const InputDecoration(
                                      labelText: 'Assisigned Teachers',
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                    onChanged: (v) => provider.reqAssTeacher = v,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: TextFormField(
                                    initialValue: provider.reqVolunteers,
                                    decoration: const InputDecoration(
                                      labelText: 'Volunteers',
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                    onChanged: (v) => provider.reqVolunteers = v,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue: provider.reqStudents,
                                    decoration: const InputDecoration(
                                      labelText: 'Students',
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                    onChanged: (v) => _onStudentsChanged(v, provider),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: TextFormField(
                                    initialValue: provider.reqNumRequired,
                                    decoration: InputDecoration(
                                      labelText: 'Teachers Required',
                                      border: const OutlineInputBorder(),
                                      filled: true,
                                      fillColor: Colors.grey[100],
                                    ),
                                    keyboardType: TextInputType.number,
                                    enabled: false,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),

                        // ─── 1.4 Verify Students – TABULAR FORM ─────────────────
                        _sectionCard(
                          title: '1.4 Verify Students',
                          subtitle: 'The purpose of this section is to check whether schools are reporting student numbers accurately. Go around to each of the classrooms and conduct a physical head count.',
                          children: [
                            if (provider.isLoadingGrades)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 16),
                                child: Text(
                                  'Loading grades...',
                                  style: TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                              ),
                            if (provider.gradesForLevel.isEmpty && !provider.isLoadingGrades)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.orange.shade200),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
                                      const SizedBox(width: 8),
                                      const Expanded(
                                        child: Text(
                                          'No grades available. Please connect to internet to load grades.',
                                          style: TextStyle(color: Colors.orange, fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (provider.gradesForLevel.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  children: [
                                    Expanded(flex: 2, child: Text('Grade', style: TextStyle(fontWeight: FontWeight.bold))),
                                    Expanded(flex: 1, child: Text('EMIS M*', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                                    Expanded(flex: 1, child: Text('Actual M*', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                                    Expanded(flex: 1, child: Text('EMIS F*', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                                    Expanded(flex: 1, child: Text('Actual F*', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...provider.gradesForLevel.map((grade) {
                                final gradeName = grade['name']?.toString() ?? 'Unknown';
                                return _verifyStudentTableRow(context, gradeName, provider);
                              }).toList(),
                              const SizedBox(height: 8),
                              Text(
                                '* All fields are required',
                                style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontStyle: FontStyle.italic),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 32),

                        // ─── 1.5 Verify Fees – TABULAR FORM FROM API ────────────
                        _sectionCard(
                          title: '1.5 Verify Fees',
                          subtitle: 'The purpose of this section is to check actual fees charged to parents and students.',
                          children: [
                            if (provider.isLoadingFees)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 16),
                                child: Text(
                                  'Loading fees...',
                                  style: TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                              ),
                            if (provider.availableFees.isEmpty && !provider.isLoadingFees)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.orange.shade200),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
                                      const SizedBox(width: 8),
                                      const Expanded(
                                        child: Text(
                                          'No fees available. Please connect to internet to load fees.',
                                          style: TextStyle(color: Colors.orange, fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (provider.availableFees.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  children: [
                                    Expanded(flex: 2, child: Text('Fee Type', style: TextStyle(fontWeight: FontWeight.bold))),
                                    Expanded(flex: 1, child: Text('Charged?*', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                                    Expanded(flex: 2, child: Text('Purpose*', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                                    Expanded(flex: 1, child: Text('Amount*', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...provider.availableFees.map((fee) {
                                final feeName = fee['fee']?.toString() ?? 'Unknown';
                                return _feeTableRow(context, feeName, provider);
                              }).toList(),
                              const SizedBox(height: 8),
                              Text(
                                '* Required fields. Amount and Purpose required only if Charged? is Yes',
                                style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontStyle: FontStyle.italic),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 48),

                        // ─── Submit Button ───────────────────────────────────────
                        Consumer<AssessmentProvider>(
                          builder: (context, prov, child) {
                            return SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton(
                                onPressed: prov.isSubmitting
                                    ? null
                                    : () async {
                                  if (_formKey.currentState!.validate()) {
                                    final success = await prov.submitAllData(context);
                                    if (success && context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(prov.lastOffline
                                              ? 'Assessment saved offline — will sync when online'
                                              : 'Assessment successfully submitted! Redirecting to Document Check...'),
                                          backgroundColor: prov.lastOffline ? Colors.orange : Colors.green,
                                          duration: const Duration(seconds: 4),
                                        ),
                                      );

                                      await Future.delayed(const Duration(seconds: 2));
                                      if (context.mounted) {
                                        context.push(
                                          '/document-check',
                                          extra: {
                                            'schoolCode': widget.schoolCode,
                                            'schoolName': widget.schoolName ?? prov.schoolName,
                                            'level': widget.schoolLevel ?? 'Unknown',
                                          },
                                        );
                                      }
                                    } else if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Error: ${prov.lastError ?? "Unknown error"}'),
                                          backgroundColor: Colors.red,
                                          duration: const Duration(seconds: 5),
                                        ),
                                      );
                                    }
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: prov.isSubmitting ? Colors.grey : AppColors.primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: prov.isSubmitting
                                    ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                                )
                                    : const Text('Submit Full Assessment', style: TextStyle(fontSize: 17)),
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 80),
                      ],
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

  // ────────────────────────────────────────────────
  // Absent Teachers Section - FIXED
  // ────────────────────────────────────────────────
  Widget _buildAbsentTeachersSection(AssessmentProvider provider) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '1.1 Staff Absent on Day of Assessment at ${provider.schoolName}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),

            // Dynamic list of absent records
            ...List.generate(provider.absentRecords.length, (index) {
              return _absentRow(context, index, provider.absentRecords[index], provider);
            }),

            if (provider.absentRecords.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    'No absent teachers recorded. Tap the button below to add.',
                    style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Add button with key to ensure it's rebuildable
            OutlinedButton.icon(
              key: const ValueKey('add_absent_button'),
              icon: const Icon(Icons.add),
              label: const Text('Add Absent Teacher'),
              onPressed: () {
                provider.addAbsent();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────
  // Total Staff Section - FIXED
  // ────────────────────────────────────────────────
  Widget _buildTotalStaffSection(AssessmentProvider provider) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '1.2 Total staff (including all administrative staff), teaching load and qualification',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),

            if (provider.isLoadingPositions)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  'Loading positions...',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),

            // Dynamic list of staff records
            ...List.generate(provider.staffRecords.length, (index) {
              return _staffRowWithPosition(context, index, provider.staffRecords[index], provider);
            }),

            if (provider.staffRecords.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    'No staff records. Tap the button below to add.',
                    style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Add button with key to ensure it's rebuildable
            OutlinedButton.icon(
              key: const ValueKey('add_staff_button'),
              icon: const Icon(Icons.add),
              label: const Text('Add Staff Member'),
              onPressed: () {
                provider.addStaff();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────
  // Staff Row with Position Dropdown - FIXED
  // ────────────────────────────────────────────────
  Widget _staffRowWithPosition(
      BuildContext context,
      int index,
      Map<String, dynamic> data,
      AssessmentProvider provider,
      ) {
    return Card(
      key: ValueKey('staff_row_$index'),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextFormField(
              controller: data['fname'],
              decoration: const InputDecoration(
                labelText: 'Full Name *',
                border: OutlineInputBorder(),
              ),
              validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            // Gender and Present in one row
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: data['gender'],
                    decoration: const InputDecoration(
                      labelText: 'Gender',
                      border: OutlineInputBorder(),
                    ),
                    items: ['Male', 'Female', 'Other']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) {
                      data['gender'] = v;
                      provider.notifyListeners();
                    },
                    menuMaxHeight: 240,
                    dropdownColor: Theme.of(context).scaffoldBackgroundColor,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: data['present'],
                    decoration: const InputDecoration(
                      labelText: 'Present',
                      border: OutlineInputBorder(),
                    ),
                    items: ['Yes', 'No', 'Partial']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) {
                      data['present'] = v;
                      provider.notifyListeners();
                    },
                    menuMaxHeight: 240,
                    dropdownColor: Theme.of(context).scaffoldBackgroundColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Position and Week Load in one row
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: data['position']?.text.isNotEmpty == true ? data['position'].text : null,
                    decoration: const InputDecoration(
                      labelText: 'Position *',
                      border: OutlineInputBorder(),
                    ),
                    items: provider.positions.isEmpty
                        ? [const DropdownMenuItem(
                      value: null,
                      child: Text('Loading positions...'),
                    )]
                        : [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Select a position', style: TextStyle(color: Colors.grey)),
                      ),
                      ...provider.positions.map((position) {
                        return DropdownMenuItem<String>(
                          value: position['name']?.toString() ?? '',
                          child: Text(position['name']?.toString() ?? 'Unknown'),
                        );
                      }).toList(),
                    ],
                    onChanged: (value) {
                      if (value != null && value.isNotEmpty) {
                        data['position'].text = value;
                        provider.notifyListeners();
                      }
                    },
                    validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                    menuMaxHeight: 240,
                    dropdownColor: Theme.of(context).scaffoldBackgroundColor,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: data['week_load'],
                    decoration: const InputDecoration(
                      labelText: 'Weekly Load',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Bio ID and Pay ID in one row
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: data['bio_id'],
                    decoration: const InputDecoration(
                      labelText: 'Bio ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: data['pay_id'],
                    decoration: const InputDecoration(
                      labelText: 'Pay ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Qualification
            TextFormField(
              controller: data['qualification'],
              decoration: const InputDecoration(
                labelText: 'Qualification',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => provider.removeStaff(index),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────
  // Absent Row - FIXED
  // ────────────────────────────────────────────────
  Widget _absentRow(
      BuildContext context,
      int index,
      Map<String, dynamic> data,
      AssessmentProvider provider,
      ) {
    return Card(
      key: ValueKey('absent_row_$index'),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextFormField(
              controller: data['fname'],
              decoration: const InputDecoration(
                labelText: 'Full Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Bio ID and Pay ID in one row
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: data['bio_id'],
                    decoration: const InputDecoration(
                      labelText: 'Bio ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: data['pay_id'],
                    decoration: const InputDecoration(
                      labelText: 'Pay ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Excuse and Reason in one row
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: data['excuse'],
                    decoration: const InputDecoration(
                      labelText: 'Excuse',
                      border: OutlineInputBorder(),
                    ),
                    items: const ['Yes', 'No']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) {
                      data['excuse'] = v;
                      provider.notifyListeners();
                    },
                    menuMaxHeight: 240,
                    dropdownColor: Theme.of(context).scaffoldBackgroundColor,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: data['reason'],
                    decoration: const InputDecoration(
                      labelText: 'Reason',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => provider.removeAbsent(index),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────
  // Verify Student Table Row with validation
  // ────────────────────────────────────────────────
  // ────────────────────────────────────────────────
// Verify Student Table Row with validation - FIXED
// ────────────────────────────────────────────────
  Widget _verifyStudentTableRow(
      BuildContext context,
      String gradeName,
      AssessmentProvider provider,
      ) {
    // Ensure record exists
    if (gradeName.isEmpty || gradeName == 'Unknown') {
      return const SizedBox.shrink();
    }

    provider.ensureVerifyStudentRecord(gradeName);
    final record = provider.getVerifyStudentRecord(gradeName);

    return Container(
      key: ValueKey('verify_row_$gradeName'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                gradeName,
                style: const TextStyle(fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextFormField(
                controller: record['emisMale'] as TextEditingController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  hintText: 'Required',
                  isDense: true,
                  errorStyle: TextStyle(fontSize: 10),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Required';
                  }
                  return null;
                },
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextFormField(
                controller: record['countMale'] as TextEditingController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  hintText: 'Required',
                  isDense: true,
                  errorStyle: TextStyle(fontSize: 10),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Required';
                  }
                  return null;
                },
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextFormField(
                controller: record['emisFemale'] as TextEditingController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  hintText: 'Required',
                  isDense: true,
                  errorStyle: TextStyle(fontSize: 10),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Required';
                  }
                  return null;
                },
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextFormField(
                controller: record['countFemale'] as TextEditingController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  hintText: 'Required',
                  isDense: true,
                  errorStyle: TextStyle(fontSize: 10),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Required';
                  }
                  return null;
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────
  // Fee Table Row with validation
  // ────────────────────────────────────────────────
  Widget _feeTableRow(
      BuildContext context,
      String feeName,
      AssessmentProvider provider,
      ) {
    final record = provider.getFeeRecord(feeName);

    if (record == null) {
      return Container(
        key: ValueKey('fee_loading_$feeName'),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Text('Initializing fee record...'),
        ),
      );
    }

    return Container(
      key: ValueKey('fee_row_$feeName'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                feeName,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: DropdownButtonFormField<String>(
                value: record['pay'],
                menuMaxHeight: 240,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  isDense: true,
                  errorStyle: TextStyle(fontSize: 10),
                ),
                items: const ['Yes', 'No']
                    .map((String value) => DropdownMenuItem<String>(
                  value: value,
                  child: Text(value, style: const TextStyle(fontSize: 12)),
                ))
                    .toList(),
                onChanged: (newValue) {
                  provider.updateFeeRecord(feeName, 'pay', newValue ?? 'Yes');
                },
                validator: (value) {
                  if (value == null) {
                    return 'Required';
                  }
                  return null;
                },
                dropdownColor: Theme.of(context).scaffoldBackgroundColor,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextFormField(
                controller: record['purpose'] as TextEditingController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  hintText: 'Required if Yes',
                  isDense: true,
                  errorStyle: TextStyle(fontSize: 10),
                ),
                maxLines: 1,
                validator: (value) {
                  if (record['pay'] == 'Yes' && (value == null || value.trim().isEmpty)) {
                    return 'Required';
                  }
                  return null;
                },
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextFormField(
                controller: record['amount'] as TextEditingController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  prefixText: 'LRD ',
                  prefixStyle: TextStyle(fontSize: 10),
                  hintText: '0.00',
                  isDense: true,
                  errorStyle: TextStyle(fontSize: 10),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (record['pay'] == 'Yes' && (value == null || value.trim().isEmpty)) {
                    return 'Required';
                  }
                  return null;
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────
  // Section Card
  // ────────────────────────────────────────────────
  Widget _sectionCard({
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 14,
                ),
              ),
            ],
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }
}