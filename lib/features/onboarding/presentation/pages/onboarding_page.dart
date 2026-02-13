import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.primary.withOpacity(0.08),
                AppColors.background,
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),

            // ── Added SingleChildScrollView here ──
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(), // optional but recommended
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 40),

                  // App/Title
                  Text(
                    'School Quality Assessment Tool',
                    style: AppTextStyles.heading1.copyWith(
                      fontSize: 28,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Liberia Ministry of Education\nECD – Grade 12 & Alternative Education',
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Welcome message
                  Text(
                    'Welcome, Supervisor',
                    style: AppTextStyles.heading2,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'This mobile tool helps District Education Officers, Instructional Supervisors, and Principal Supervisors conduct thorough and standardized school quality assessments. Please follow these mandatory guidelines for every assessment:',
                    style: AppTextStyles.bodyLarge.copyWith(height: 1.5),
                  ),

                  const SizedBox(height: 32),

                  // Key Guidelines – Prominent & numbered
                  _buildGuideline(
                    number: '1',
                    text:
                    'Additional comments must be detailed and specific. Avoid vague phrases such as "on course", "everything was good", or similar. Provide thorough explanations only.',
                  ),
                  const SizedBox(height: 20),
                  _buildGuideline(
                    number: '2',
                    text:
                    'ALL questions must be answered. If any part is incomplete or not observed, mark/score it as "No". Partial or skipped responses are not acceptable.',
                  ),
                  const SizedBox(height: 20),
                  _buildGuideline(
                    number: '3',
                    text:
                    'Staff and student lists must include full first and last names — no initials allowed. Printed lists are acceptable only if they contain ALL required SQA information.',
                  ),

                  const SizedBox(height: 40), // ← replaced Spacer() with fixed space

                  // Action button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        context.read<AuthProvider>().completeOnboarding();
                        context.go('/login');
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        'I Understand – Continue to Sign In',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24), // extra bottom padding (optional)
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGuideline({required String number, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryDark,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.bodyLarge.copyWith(height: 1.45),
          ),
        ),
      ],
    );
  }
}