import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';

class AssessmentCompletePage extends StatelessWidget {
  final bool isOffline;           // true = saved offline, false = submitted online
  final String? schoolName;       // optional - show which school was assessed

  const AssessmentCompletePage({
    super.key,
    required this.isOffline,
    this.schoolName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assessment Completed'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Success icon
                Icon(
                  Icons.check_circle_rounded,
                  size: 100,
                  color: isOffline ? Colors.orange : Colors.green,
                ),
                const SizedBox(height: 32),

                // Main heading
                Text(
                  'Assessment Completed!',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Status message
                Text(
                  isOffline
                      ? 'Your assessment has been saved offline.\nIt will be automatically synced when you are back online.'
                      : 'Your assessment has been successfully submitted.',
                  style: TextStyle(
                    fontSize: 18,
                    height: 1.5,
                    color: theme.brightness == Brightness.dark ? Colors.grey[300] : Colors.grey[800],
                  ),
                  textAlign: TextAlign.center,
                ),
                if (schoolName != null && schoolName!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'for $schoolName',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ],

                const SizedBox(height: 48),

                // Main action button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // Navigate to school list or new assessment flow
                      context.go('/schools'); // ← change to your actual route
                      // OR: context.go('/new-assessment'); // if you have a direct new assessment route
                    },
                    icon: const Icon(Icons.add_circle_outline, size: 28),
                    label: const Text(
                      'Add New Assessment',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Secondary actions
                OutlinedButton.icon(
                  onPressed: () {
                    // Optional: go to dashboard, summary, or home
                    context.go('/home'); // ← change to your preferred route
                  },
                  icon: const Icon(Icons.dashboard),
                  label: const Text('Back to Dashboard'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}