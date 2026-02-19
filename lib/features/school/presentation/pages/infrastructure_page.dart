import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_url.dart';
import '../../../../core/widgets/custom_app_bar.dart';
import '../../../../core/widgets/loading_overlay.dart';
import '../../../../core/services/local_storage_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class InfrastructurePage extends StatefulWidget {
  const InfrastructurePage({super.key});

  @override
  State<InfrastructurePage> createState() => _InfrastructurePageState();
}

class _InfrastructurePageState extends State<InfrastructurePage> {
  bool _isLoading = false;
  bool _isSubmitting = false;
  String? _schoolName;
  String? _schoolCode;
  String? _schoolLevel;

  // Main scored questions
  List<Map<String, dynamic>> _questions = [];
  // Additional scored questions
  List<Map<String, dynamic>> _additionalQuestions = [];

  // Combined scores for both sets
  Map<String, int?> _scores = {};

  @override
  void initState() {
    super.initState();
    // Load from cache first (offline-first)
    _loadFromCache();
    // Then refresh if online (background)
    _refreshQuestionsIfOnline();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
    _schoolName = extra?['schoolName'] as String?;
    _schoolCode = extra?['schoolCode'] as String?;
    _schoolLevel = extra?['level'] as String?;

    _schoolName ??= 'Unknown School';
    _schoolCode ??= 'N/A';
    _schoolLevel ??= 'Unknown Level';

    if (mounted) setState(() {});
  }

  // Load both sets from cache (offline-first)
  void _loadFromCache() {
    final mainCached = LocalStorageService.getFromCache('infrastructure_questions');
    if (mainCached != null && mainCached is List) {
      _questions = mainCached.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        return {
          'number': (index + 1).toString(),
          'id': item['id'].toString(),
          'name': item['name'].toString(),
        };
      }).toList();

      // Re-init scores from cache
      for (var q in _questions) {
        _scores[q['id']!] = null;
      }
    }

    final additionalCached = LocalStorageService.getFromCache('additional_infrastructure_questions');
    if (additionalCached != null && additionalCached is List) {
      _additionalQuestions = additionalCached.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        return {
          'number': (index + 1).toString(),
          'id': item['id'].toString(),
          'name': item['name'].toString(),
        };
      }).toList();

      // Re-init scores from cache
      for (var q in _additionalQuestions) {
        _scores[q['id']!] = null;
      }
    }

    if (mounted) setState(() {});
  }

  // Refresh questions only if online (background)
  Future<void> _refreshQuestionsIfOnline() async {
    final isOnline = await LocalStorageService.isOnline();
    if (!isOnline) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final headers = auth.getAuthHeaders();

    // Refresh main questions
    try {
      final qRes = await http.get(
        Uri.parse('${AppUrl.url}/questions?cat=School Physical Infrastructure'),
        headers: headers,
      );

      if (qRes.statusCode == 200) {
        final List<dynamic> list = jsonDecode(qRes.body);
        if (mounted) {
          setState(() {
            _questions = list.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return {
                'number': (index + 1).toString(),
                'id': item['id'].toString(),
                'name': item['name'].toString(),
              };
            }).toList();

            // Update scores (preserve existing answers if possible)
            for (var q in _questions) {
              if (!_scores.containsKey(q['id'])) {
                _scores[q['id']!] = null;
              }
            }
          });

          // Cache fresh data
          await LocalStorageService.saveToCache('infrastructure_questions', list);
        }
      }
    } catch (e) {
      print('Background refresh infrastructure questions failed: $e');
    }

    // Refresh additional questions
    try {
      final res = await http.get(
        Uri.parse('${AppUrl.url}/questions?cat=Additional data on school infrastructure'),
        headers: headers,
      );

      if (res.statusCode == 200) {
        final List<dynamic> list = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _additionalQuestions = list.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return {
                'number': (index + 1).toString(),
                'id': item['id'].toString(),
                'name': item['name'].toString(),
              };
            }).toList();

            // Update scores
            for (var q in _additionalQuestions) {
              if (!_scores.containsKey(q['id'])) {
                _scores[q['id']!] = null;
              }
            }
          });

          await LocalStorageService.saveToCache('additional_infrastructure_questions', list);
        }
      }
    } catch (e) {
      print('Background refresh additional infrastructure questions failed: $e');
    }
  }

  Future<void> _submit() async {
    if (!mounted) return;

    if (_scores.values.every((v) => v == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please answer at least one question'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _isSubmitting = true;
    });

    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!auth.isAuthenticated || auth.token == null) {
      _handleEnd('Not authenticated', Colors.red);
      return;
    }

    final headers = auth.getAuthHeaders();

    final cleanScores = _scores.map((key, value) => MapEntry(key, value ?? 0));

    final payload = {
      'school': _schoolCode ?? 'N/A',
      'scores': cleanScores,
    };

    print('Infrastructure payload:');
    print(jsonEncode(payload));

    String message = 'Unknown status';
    Color color = Colors.grey;

    try {
      final isOnline = await LocalStorageService.isOnline();

      if (isOnline) {
        final res = await http.post(
          Uri.parse('${AppUrl.url}/infrastructure'),
          headers: headers,
          body: jsonEncode(payload),
        );

        if (res.statusCode == 200 || res.statusCode == 201) {
          message = 'Physical infrastructure assessment saved successfully!';
          color = Colors.green;
          await _syncPendingInfrastructure(context);
        } else {
          message = 'Server error: ${res.statusCode} - ${res.body}';
          color = Colors.red;
        }
      } else {
        await LocalStorageService.savePendingInfrastructure(payload);
        message = 'Saved offline — will sync when online';
        color = Colors.orange;
      }
    } catch (e) {
      print('Submit error: $e');
      message = 'Error: $e';
      color = Colors.red;

      try {
        await LocalStorageService.savePendingInfrastructure(payload);
        message = 'Saved offline due to error — will retry later';
        color = Colors.orange;
      } catch (hiveErr) {
        print('Hive failed: $hiveErr');
      }
    }

    _handleEnd(message, color);
  }

  void _handleEnd(String message, Color color) {
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _isSubmitting = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 5),
      ),
    );

    if (color == Colors.green || color == Colors.orange) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          context.push(
            '/classroom-1',
            extra: {
              'schoolCode': _schoolCode,
              'schoolName': _schoolName,
              'level': _schoolLevel,
            },
          );
        }
      });
    }
  }

  Future<void> _syncPendingInfrastructure(BuildContext context) async {
    final pending = LocalStorageService.getPendingInfrastructure();
    if (pending.isEmpty) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!auth.isAuthenticated || auth.token == null) return;

    final headers = auth.getAuthHeaders();

    for (var payload in pending) {
      try {
        final res = await http.post(
          Uri.parse('${AppUrl.url}/infrastructure'),
          headers: headers,
          body: jsonEncode(payload),
        );

        if (res.statusCode == 200 || res.statusCode == 201) {
          await LocalStorageService.removePendingInfrastructure(payload);
        }
      } catch (e) {
        debugPrint('Pending infrastructure sync failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Module 4: Physical Infrastructure at ${_schoolName ?? ''}',
        backgroundColor: AppColors.primary,
        textColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, color: Colors.white),
            tooltip: 'Offline Infrastructure',
            onPressed: () => context.push('/offline-infrastructure'),
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
                    'Offline Mode — Data will be saved locally and synced later',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w600),
                  ),
                ),

              Expanded(
                child: LoadingOverlay(
                  isLoading: _isLoading,
                  child: RefreshIndicator(
                    onRefresh: _refreshQuestionsIfOnline,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 24),

                          const Text(
                            'All questions are 1 point each (Yes = 1, No = 0)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 16),

                          if (_questions.isEmpty)
                            const Center(child: Text('No questions available offline. Connect to internet to load.'))
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _questions.length,
                              itemBuilder: (context, index) {
                                final q = _questions[index];
                                final qId = q['id'] as String;
                                final number = q['number'] as String;

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '$number. ${q['name']}',
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                          children: [
                                            _radioOption(qId, 1, 'Yes'),
                                            _radioOption(qId, 0, 'No'),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),

                          const SizedBox(height: 32),

                          Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Additional data on school infrastructure',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  if (_additionalQuestions.isEmpty)
                                    const Center(child: Text('No additional data available offline. Connect to internet to load.'))
                                  else
                                    ListView.builder(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: _additionalQuestions.length,
                                      itemBuilder: (context, index) {
                                        final q = _additionalQuestions[index];
                                        final qId = q['id'] as String;
                                        final number = q['number'] as String;

                                        return Card(
                                          margin: const EdgeInsets.only(bottom: 12),
                                          child: Padding(
                                            padding: const EdgeInsets.all(12.0),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '$number. ${q['name']}',
                                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                                                ),
                                                const SizedBox(height: 12),
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                  children: [
                                                    _radioOption(qId, 1, 'Yes'),
                                                    _radioOption(qId, 0, 'No'),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 40),

                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: StreamBuilder<bool>(
                              stream: LocalStorageService.onlineStatusStream,
                              initialData: true,
                              builder: (context, snapshot) {
                                final bool canSubmit = snapshot.data ?? true;
                                return ElevatedButton.icon(
                                  icon: const Icon(Icons.save),
                                  label: const Text('Submit Infrastructure Assessment', style: TextStyle(fontSize: 17)),
                                  onPressed: _isLoading || _isSubmitting || !canSubmit ? null : _submit,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: canSubmit ? AppColors.primary : Colors.grey,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                );
                              },
                            ),
                          ),

                          const SizedBox(height: 80),
                        ],
                      ),
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

  Widget _radioOption(String qId, int value, String label) {
    return Expanded(
      child: RadioListTile<int>(
        title: Text(label, style: const TextStyle(fontSize: 14)),
        value: value,
        groupValue: _scores[qId],
        onChanged: _isSubmitting ? null : (v) => setState(() => _scores[qId] = v),
        dense: true,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}