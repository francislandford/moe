import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/local_storage_service.dart';
import '../../../../core/widgets/custom_app_bar.dart';
import '../../../../core/widgets/custom_text_field.dart';
import '../../../../core/widgets/loading_overlay.dart';
import '../providers/school_provider.dart';

class AddSchoolPage extends StatefulWidget {
  const AddSchoolPage({super.key});

  @override
  State<AddSchoolPage> createState() => _AddSchoolPageState();
}

class _AddSchoolPageState extends State<AddSchoolPage> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  // Controllers
  final _schoolNameController = TextEditingController();
  final _schoolCodeController = TextEditingController();
  final _communityController = TextEditingController();
  final _principalNameController = TextEditingController();
  final _contactController = TextEditingController();
  final _emailController = TextEditingController();
  final _permitNumberController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _teachersPresentController = TextEditingController();
  final _verifyCommentController = TextEditingController();
  final _yearEstablishedController = TextEditingController();
  final _noRoomController = TextEditingController(); // NEW: Number of Rooms

  // Selections
  String? _selectedCounty;
  String? _selectedDistrict;
  String? _selectedLevel; // ← now stores the CODE (not name)
  String? _selectedType;
  String? _selectedOwnership;
  String? _permitStatus = 'No';
  String? _teachersPresent = 'No';
  String? _chargeFees = 'No';

  bool _isTvet = false;
  bool _isAccelerated = false;
  bool _isAlternative = false;

  bool _isGettingLocation = false;

  @override
  void initState() {
    super.initState();
    // Fetch counties, levels, types, ownerships on page load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SchoolProvider>().fetchDropdownData(context);
    });

    // Get real GPS location from device
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _schoolNameController.dispose();
    _schoolCodeController.dispose();
    _communityController.dispose();
    _principalNameController.dispose();
    _contactController.dispose();
    _emailController.dispose();
    _permitNumberController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _teachersPresentController.dispose();
    _verifyCommentController.dispose();
    _yearEstablishedController.dispose();
    _noRoomController.dispose(); // NEW
    _scrollController.dispose();
    super.dispose();
  }

  /// Get real device GPS location (no fallback, no storage, no default)
  Future<void> _getCurrentLocation() async {
    if (!mounted) return;

    setState(() => _isGettingLocation = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location services are disabled. Please enable them.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permission denied. Cannot get GPS.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission permanently denied. Enable in settings.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() {
          _latitudeController.text = position.latitude.toStringAsFixed(6);
          _longitudeController.text = position.longitude.toStringAsFixed(6);
        });
      }
    } catch (e) {
      debugPrint('GPS error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to get location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGettingLocation = false);
      }
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<SchoolProvider>();

    final schoolData = {
      'county': _selectedCounty,
      'district': _selectedDistrict,
      'school_level': _selectedLevel, // ← now the code
      'school_type': _selectedType,
      'school_ownership': _selectedOwnership,
      'community': _communityController.text.trim(),
      'school_code': _schoolCodeController.text.trim(),
      'school_name': _schoolNameController.text.trim(),
      'tvet': _isTvet ? '1' : '0',
      'accelerated': _isAccelerated ? '1' : '0',
      'alternative': _isAlternative ? '1' : '0',
      'year_establish': int.tryParse(_yearEstablishedController.text.trim()),
      'permit': _permitStatus,
      'permit_num': _permitStatus == 'Yes' ? _permitNumberController.text.trim() : null,
      'principal_name': _principalNameController.text.trim(),
      'school_contact': _contactController.text.trim(),
      'email': _emailController.text.trim(),
      'latitude': double.tryParse(_latitudeController.text.trim()),
      'longitude': double.tryParse(_longitudeController.text.trim()),
      'all_teacher_present': _teachersPresent,
      'verify_comment': _verifyCommentController.text.trim(),
      'charge_fees': _chargeFees,
      'nb_room': int.tryParse(_noRoomController.text.trim() ?? '0') ?? 0, // NEW: added to payload
    };

    final result = await provider.createSchool(schoolData, context);

    if (!mounted) return;

    if (result['success'] == true) {
      final String schoolCode = result['data']?['school_code'] ?? _schoolCodeController.text.trim();
      final String schoolName = result['data']?['school_name'] ?? _schoolNameController.text.trim();
      final String schoolLevel = result['data']?['school_level'] ?? _selectedLevel ?? 'Unknown';

      if (result['offline'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Saved offline — will sync later'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('School registered successfully! Redirecting to Assessment 2...'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }

      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        context.push('/assessment-2', extra: {
          'schoolCode': schoolCode,
          'schoolName': schoolName,
          'level': schoolLevel,
        });
      }
    } else {
      _showErrorDialog(result['message'] ?? 'Failed to create school');
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(Icons.error, color: Colors.red, size: 64),
          title: const Text('Error'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SchoolProvider>();

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Add New School',
        backgroundColor: AppColors.primary,
        textColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, color: Colors.white),
            tooltip: 'Home',
            onPressed: () => context.push('/offline-students'),
          ),
        ],
      ),
      body: LoadingOverlay(
        isLoading: provider.isLoading,
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
            children: [
              FutureBuilder<bool>(
                future: LocalStorageService.isOnline(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done &&
                      snapshot.hasData &&
                      !snapshot.data!) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Chip(
                        label: const Text('Offline Mode — Data will sync later'),
                        backgroundColor: Colors.orange.shade100,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),

              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 1. Location
                        _buildSectionCard(
                          title: 'Location',
                          children: [
                            DropdownButtonFormField<String>(
                              value: _selectedCounty,
                              decoration: const InputDecoration(
                                labelText: 'County *',
                                border: OutlineInputBorder(),
                              ),
                              items: provider.counties.map((m) {
                                return DropdownMenuItem<String>(
                                  value: m['county'] as String,
                                  child: Text(m['county'] as String),
                                );
                              }).toList(),
                              onChanged: (v) {
                                setState(() {
                                  _selectedCounty = v;
                                  _selectedDistrict = null;
                                });
                                if (v != null) provider.fetchDistricts(v, context);
                              },
                              validator: (v) => v == null ? 'Required' : null,
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              value: _selectedDistrict,
                              decoration: const InputDecoration(
                                labelText: 'District *',
                                border: OutlineInputBorder(),
                              ),
                              items: provider.districts.map((m) {
                                return DropdownMenuItem<String>(
                                  value: m['d_name'] as String,
                                  child: Text(m['d_name'] as String),
                                );
                              }).toList(),
                              onChanged: (v) => setState(() => _selectedDistrict = v),
                              validator: (v) => v == null ? 'Required' : null,
                            ),
                          ],
                        ),

                        // 2. School Identity
                        _buildSectionCard(
                          title: 'School Identity',
                          children: [
                            CustomTextField(
                              controller: _schoolNameController,
                              label: 'School Name *',
                              validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
                            ),
                            const SizedBox(height: 16),
                            CustomTextField(
                              controller: _schoolCodeController,
                              label: 'School Code *',
                              validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
                            ),
                            const SizedBox(height: 16),
                            CustomTextField(
                              controller: _communityController,
                              label: 'Community / Village',
                            ),
                          ],
                        ),

                        // 3. Classification – Added Number of Rooms
                        _buildSectionCard(
                          title: 'Classification',
                          children: [
                            DropdownButtonFormField<String>(
                              value: _selectedLevel,
                              decoration: InputDecoration(
                                labelText: 'School Level *',
                                border: const OutlineInputBorder(),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              ),
                              items: provider.levels.map((level) {
                                return DropdownMenuItem<String>(
                                  value: level['code'].toString(),
                                  child: Text(level['name'].toString()),
                                );
                              }).toList(),
                              onChanged: (v) => setState(() => _selectedLevel = v),
                              validator: (v) => v == null ? 'Required' : null,
                            ),
                            const SizedBox(height: 16),
                            _dropdown(
                              label: 'School Type *',
                              value: _selectedType,
                              items: provider.types.map((m) => m['name'] as String).toList(),
                              onChanged: (v) => setState(() => _selectedType = v),
                              validator: (v) => v == null ? 'Required' : null,
                            ),
                            const SizedBox(height: 16),
                            _dropdown(
                              label: 'Ownership *',
                              value: _selectedOwnership,
                              items: provider.ownerships.map((m) => m['name'] as String).toList(),
                              onChanged: (v) => setState(() => _selectedOwnership = v),
                              validator: (v) => v == null ? 'Required' : null,
                            ),
                            const SizedBox(height: 16),
                            CustomTextField(
                              controller: _noRoomController,
                              label: 'Number of Rooms *',
                              keyboardType: TextInputType.number,
                              validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
                            ),
                            const SizedBox(height: 24),
                            SwitchListTile(
                              title: const Text('Offers TVET Program'),
                              value: _isTvet,
                              onChanged: (v) => setState(() => _isTvet = v),
                              activeColor: AppColors.primary,
                            ),
                            SwitchListTile(
                              title: const Text('Accelerated Learning Program'),
                              value: _isAccelerated,
                              onChanged: (v) => setState(() => _isAccelerated = v),
                              activeColor: AppColors.primary,
                            ),
                            SwitchListTile(
                              title: const Text('Alternative Education'),
                              value: _isAlternative,
                              onChanged: (v) => setState(() => _isAlternative = v),
                              activeColor: AppColors.primary,
                            ),
                          ],
                        ),

                        // 4. Establishment & Permit
                        _buildSectionCard(
                          title: 'Establishment & Permit',
                          children: [
                            _yearDropdown(),
                            const SizedBox(height: 16),
                            _dropdown(
                              label: 'Permit Status',
                              value: _permitStatus,
                              items: const ['Yes', 'No', 'Pending'],
                              onChanged: (v) => setState(() => _permitStatus = v),
                            ),
                            if (_permitStatus == 'Yes') ...[
                              const SizedBox(height: 16),
                              CustomTextField(
                                controller: _permitNumberController,
                                label: 'Permit Number *',
                                validator: (v) => v?.trim().isEmpty ?? true ? 'Required when permit is Yes' : null,
                              ),
                            ],
                          ],
                        ),

                        // 5. Contact & Coordinates
                        _buildSectionCard(
                          title: 'Contact & Coordinates',
                          children: [
                            CustomTextField(
                              controller: _principalNameController,
                              label: 'Principal / Head Teacher Name',
                            ),
                            const SizedBox(height: 16),
                            CustomTextField(
                              controller: _contactController,
                              label: 'School Contact Phone',
                              keyboardType: TextInputType.phone,
                            ),
                            const SizedBox(height: 16),
                            CustomTextField(
                              controller: _emailController,
                              label: 'School Email',
                              keyboardType: TextInputType.emailAddress,
                            ),
                            const SizedBox(height: 24),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: CustomTextField(
                                    controller: _latitudeController,
                                    label: 'Latitude',
                                    readOnly: true,
                                    decoration: InputDecoration(
                                      border: const OutlineInputBorder(),
                                      filled: true,
                                      fillColor: Colors.grey.shade100,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: CustomTextField(
                                    controller: _longitudeController,
                                    label: 'Longitude',
                                    readOnly: true,
                                    decoration: InputDecoration(
                                      border: const OutlineInputBorder(),
                                      filled: true,
                                      fillColor: Colors.grey.shade100,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (_isGettingLocation)
                              const Text(
                                'Getting current location...',
                                style: TextStyle(color: Colors.grey, fontSize: 12),
                              )
                            else
                              Text(
                                'Location captured from device GPS',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.grey[600],
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                          ],
                        ),

                        // 6. Verification & Fees
                        _buildSectionCard(
                          title: 'Verification & Fees',
                          children: [
                            const Text(
                              'Were all teachers present during the visit?',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: RadioListTile<String>(
                                    title: const Text('Yes'),
                                    value: 'Yes',
                                    groupValue: _teachersPresent,
                                    onChanged: (v) => setState(() => _teachersPresent = v),
                                    dense: true,
                                  ),
                                ),
                                Expanded(
                                  child: RadioListTile<String>(
                                    title: const Text('No'),
                                    value: 'No',
                                    groupValue: _teachersPresent,
                                    onChanged: (v) => setState(() => _teachersPresent = v),
                                    dense: true,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            CustomTextField(
                              controller: _verifyCommentController,
                              label: 'Verification Comment *',
                              maxLines: 4,
                              validator: (v) {
                                final t = v?.trim() ?? '';
                                if (t.isEmpty) return 'Required';
                                if (t.length < 30) return 'Please be more detailed (min 30 chars)';
                                return null;
                              },
                            ),
                            const SizedBox(height: 24),
                            _dropdown(
                              label: 'Does the school charge fees? *',
                              value: _chargeFees,
                              items: const ['Yes', 'No'],
                              onChanged: (v) => setState(() => _chargeFees = v),
                              validator: (v) => v == null ? 'Required' : null,
                            ),
                          ],
                        ),

                        const SizedBox(height: 40),

                        SizedBox(
                          height: 56,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.save_rounded),
                            label: const Text(
                              'Submit School Registration',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                            ),
                            onPressed: provider.isLoading ? null : _submitForm,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 3,
                            ),
                          ),
                        ),

                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // Card wrapper
  // ────────────────────────────────────────────────────────────────
  Widget _buildSectionCard({required String title, required List<Widget> children}) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.primary,
                fontFamily: 'RobotoSlabBold',
              ),
            ),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // Dropdown helper
  // ────────────────────────────────────────────────────────────────
  Widget _dropdown({
    required String label,
    required String? value,
    List<String> items = const [],
    required ValueChanged<String?> onChanged,
    String? Function(String?)? validator,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      items: items.map((item) {
        return DropdownMenuItem<String>(
          value: item,
          child: Text(item),
        );
      }).toList(),
      onChanged: onChanged,
      validator: validator,
    );
  }

  // ────────────────────────────────────────────────────────────────
  // Year dropdown
  // ────────────────────────────────────────────────────────────────
  Widget _yearDropdown() {
    final currentYear = DateTime.now().year;
    final years = List.generate(currentYear - 1820, (index) => (currentYear - index).toString())
      ..sort((a, b) => b.compareTo(a)); // newest first

    return DropdownButtonFormField<String>(
      value: _yearEstablishedController.text.isNotEmpty ? _yearEstablishedController.text : null,
      decoration: const InputDecoration(
        labelText: 'Year Established *',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      items: years.map((year) {
        return DropdownMenuItem<String>(
          value: year,
          child: Text(year),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) {
          _yearEstablishedController.text = value;
        }
      },
      validator: (v) => v == null ? 'Please select a year' : null,
    );
  }
}