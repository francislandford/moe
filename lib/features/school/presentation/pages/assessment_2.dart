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
        // ─── FIXED: Automatically set reqLevel = level (from route) ───────
        provider.reqLevel = provider.level;
        provider.fetchGradesForLevel(provider.level, context);
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

  // Focus nodes for dropdowns that might cause jump
  final Map<String, FocusNode> _dropdownFocusNodes = {};

  @override
  void dispose() {
    _scrollController.dispose();
    _dropdownFocusNodes.values.forEach((node) => node.dispose());
    super.dispose();
  }

  void _preventScrollJump(FocusNode node) {
    if (node.hasFocus) {
      // Temporarily disable physics during focus change
      _scrollController.jumpTo(_scrollController.offset);
    }
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
          IconButton(
            icon: const Icon(Icons.sync, color: Colors.white),
            tooltip: 'Offline Assessments',
            onPressed: () => context.push('/offline-assessments'),
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
                        _sectionCard(
                          title: '1.1 Staff Absent on Day of Assessment at ${provider.schoolName}',
                          children: [
                            ...provider.absentRecords.asMap().entries.map((e) {
                              return _absentRow(context, e.key, e.value);
                            }).toList(),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text('Add Absent Teacher'),
                              onPressed: provider.addAbsent,
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),

                        // ─── 1.2 Total Staff ───────────────────────────────────
                        _sectionCard(
                          title: '1.2 Total staff (including all administrative staff), teaching load and qualification',
                          children: [
                            ...provider.staffRecords.asMap().entries.map((e) {
                              return _staffRow(context, e.key, e.value);
                            }).toList(),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text('Add Staff Member'),
                              onPressed: provider.addStaff,
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),

                        // ─── 1.3 Required Teachers – Auto-fill & Disabled ───────
                        _sectionCard(
                          title: '1.3 Teacher Required',
                          subtitle:
                          'The purpose of this section is to check how many teachers are required in different subjects. This data will form the basis for teacher supply or transfer.',
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
                                      labelText: 'Assistant Teachers',
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
                                    onChanged: (v) => provider.reqStudents = v,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: TextFormField(
                                    initialValue: provider.reqNumRequired,
                                    decoration: const InputDecoration(
                                      labelText: 'Required Teachers',
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                    onChanged: (v) => provider.reqNumRequired = v,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),

                        // ─── 1.4 Verify Students – FULLY DYNAMIC ────────
                        _sectionCard(
                          title: '1.4 Verify Students',
                          subtitle:
                          'The purpose of this section is to check whether schools are reporting student numbers accurately. Go around to each of the classrooms and conduct a physical head count.',
                          children: [
                            ...provider.verifyStudentRecords.asMap().entries.map((entry) {
                              final index = entry.key;
                              final record = entry.value;
                              return _verifyStudentRow(context, index, record, provider);
                            }).toList(),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text('Add Class Verification'),
                              onPressed: provider.addVerifyStudent,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),

                        // ─── 1.5 Verify Fees – MULTIPLE ───────────────────────────────────
                        _sectionCard(
                          title: '1.5 Verify Fees',
                          subtitle: 'The purpose of this section is to check actual fees charged to parents and students.',
                          children: [
                            ...provider.feeRecords.asMap().entries.map((entry) {
                              int idx = entry.key;
                              var fee = entry.value;
                              return _feeRow(context, idx, fee);
                            }).toList(),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text('Add Fee Record'),
                              onPressed: provider.addFeeRecord,
                              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 48),

                        // ─── Submit Button ───────────────────────────────────────────────
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
  // Dynamic Verify Student Row – FIXED: no jump
  // ────────────────────────────────────────────────
  Widget _verifyStudentRow(
      BuildContext context,
      int index,
      Map<String, dynamic> record,
      AssessmentProvider provider,
      ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String?>(
              value: record['classGrade'] as String?,
              menuMaxHeight: 240,
              decoration: const InputDecoration(
                labelText: 'Class / Grade *',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    'Select a grade...',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ...provider.gradesForLevel.map((grade) {
                  final id = grade['id']?.toString();
                  final name = grade['name']?.toString() ?? 'Unnamed Grade';
                  return DropdownMenuItem<String?>(
                    value: name,
                    child: Text(name),
                  );
                }).toList(),
              ],
              onChanged: (String? v) {
                provider.updateVerifyStudent(index, 'classGrade', v);
              },
              validator: (v) => v == null ? 'Required' : null,
              dropdownColor: Theme.of(context).scaffoldBackgroundColor,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: record['emisMale'] as TextEditingController,
                    decoration: const InputDecoration(labelText: 'EMIS Male'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: record['countMale'] as TextEditingController,
                    decoration: const InputDecoration(labelText: 'Actual Count Male'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: record['emisFemale'] as TextEditingController,
                    decoration: const InputDecoration(labelText: 'EMIS Female'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: record['countFemale'] as TextEditingController,
                    decoration: const InputDecoration(labelText: 'Actual Count Female'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => provider.removeVerifyStudent(index),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────
  // Section Card (unchanged)
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
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle, style: TextStyle(color: Colors.grey[700])),
            ],
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────
  // Absent Row – FIXED: no jump
  // ────────────────────────────────────────────────
  Widget _absentRow(BuildContext context, int index, Map<String, dynamic> data) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextFormField(
              controller: data['fname'],
              decoration: const InputDecoration(labelText: 'Full Name *'),
              validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(controller: data['bio_id'], decoration: const InputDecoration(labelText: 'Bio ID')),
            const SizedBox(height: 16),
            TextFormField(controller: data['pay_id'], decoration: const InputDecoration(labelText: 'Pay ID')),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: data['excuse'],
              decoration: const InputDecoration(labelText: 'Excuse'),
              items: const ['Yes', 'No']
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) {
                data['excuse'] = v;
                Provider.of<AssessmentProvider>(context, listen: false).notifyListeners();
              },
              menuMaxHeight: 240,
              dropdownColor: Theme.of(context).scaffoldBackgroundColor,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: data['reason'],
              decoration: const InputDecoration(labelText: 'Reason'),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => Provider.of<AssessmentProvider>(context, listen: false).removeAbsent(index),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────
  // Staff Row – FIXED: no jump
  // ────────────────────────────────────────────────
  Widget _staffRow(BuildContext context, int index, Map<String, dynamic> data) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextFormField(
              controller: data['fname'],
              decoration: const InputDecoration(labelText: 'Full Name *'),
              validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: data['gender'],
                    decoration: const InputDecoration(labelText: 'Gender'),
                    items: ['Male', 'Female', 'Other']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) {
                      data['gender'] = v;
                      Provider.of<AssessmentProvider>(context, listen: false).notifyListeners();
                    },
                    menuMaxHeight: 240,
                    dropdownColor: Theme.of(context).scaffoldBackgroundColor,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: data['present'],
                    decoration: const InputDecoration(labelText: 'Present'),
                    items: ['Yes', 'No', 'Partial']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) {
                      data['present'] = v;
                      Provider.of<AssessmentProvider>(context, listen: false).notifyListeners();
                    },
                    menuMaxHeight: 240,
                    dropdownColor: Theme.of(context).scaffoldBackgroundColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(controller: data['position'], decoration: const InputDecoration(labelText: 'Position')),
            const SizedBox(height: 16),
            TextFormField(
              controller: data['week_load'],
              decoration: const InputDecoration(labelText: 'Weekly Load'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextFormField(controller: data['bio_id'], decoration: const InputDecoration(labelText: 'Bio ID')),
            const SizedBox(height: 16),
            TextFormField(controller: data['pay_id'], decoration: const InputDecoration(labelText: 'Pay ID')),
            const SizedBox(height: 16),
            TextFormField(
              controller: data['qualification'],
              decoration: const InputDecoration(labelText: 'Qualification'),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => Provider.of<AssessmentProvider>(context, listen: false).removeStaff(index),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────
  // Fee Row – FIXED: no jump
  // ────────────────────────────────────────────────
  Widget _feeRow(BuildContext context, int index, Map<String, dynamic> feeData) {
    final provider = Provider.of<AssessmentProvider>(context, listen: false);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              value: feeData['fee'],
              isExpanded: true,
              menuMaxHeight: 240,
              decoration: const InputDecoration(labelText: 'Fee Type *', border: OutlineInputBorder()),
              items: const [
                'PTA',
                'Development fees',
                'Registration fees',
                'Tuition fees',
                'WAEC Examination fees',
                'WASSCE Examination',
                'Uniform fees',
                'Other'
              ].map((String value) => DropdownMenuItem<String>(value: value, child: Text(value))).toList(),
              onChanged: (newValue) {
                provider.updateFee(index, 'fee', newValue ?? 'Tuition fees');
              },
              validator: (value) => value == null ? 'Required' : null,
              dropdownColor: Theme.of(context).scaffoldBackgroundColor,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: feeData['pay'],
              menuMaxHeight: 240,
              decoration: const InputDecoration(
                labelText: 'Does the school charge this fee?',
                border: OutlineInputBorder(),
              ),
              items: const ['Yes', 'No']
                  .map((String value) => DropdownMenuItem(value: value, child: Text(value)))
                  .toList(),
              onChanged: (newValue) {
                provider.updateFee(index, 'pay', newValue ?? 'Yes');
              },
              dropdownColor: Theme.of(context).scaffoldBackgroundColor,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: feeData['purpose'],
              decoration: const InputDecoration(
                labelText: 'Purpose / Remark',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: feeData['amount'],
              decoration: const InputDecoration(
                labelText: 'Amount (LRD)',
                border: OutlineInputBorder(),
                prefixText: 'LRD ',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (feeData['pay'] == 'Yes' && (v == null || v.trim().isEmpty)) {
                  return 'Amount required when fee is charged';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => provider.removeFee(index),
              ),
            ),
          ],
        ),
      ),
    );
  }
}