// forgot_password_email_page.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/widgets/custom_text_field.dart';
import '../../../../core/widgets/loading_overlay.dart';
import '../providers/auth_provider.dart';

class ForgotPasswordEmailPage extends StatefulWidget {
  const ForgotPasswordEmailPage({super.key});

  @override
  State<ForgotPasswordEmailPage> createState() => _ForgotPasswordEmailPageState();
}

class _ForgotPasswordEmailPageState extends State<ForgotPasswordEmailPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // Call the forgot password API
      final result = await authProvider.forgotPassword(
        _emailController.text.trim(),
      );

      if (mounted) {
        if (result['success'] == true) {
          // Navigate to reset code page with email
          context.push('/reset-password-code', extra: {
            'email': _emailController.text.trim(),
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Reset code sent to your email'),
              backgroundColor: AppColors.success ?? Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          // Show error message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Failed to send reset code'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('An error occurred. Please try again.'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reset Password', style: TextStyle(color: Colors.white)),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: LoadingOverlay(
        isLoading: _isLoading,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40),

                  // Icon
                  Center(
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.email_outlined,
                        size: 50,
                        color: AppColors.primary,
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Title
                  Text(
                    'Forgot Password?',
                    style: AppTextStyles.heading1.copyWith(
                      fontSize: 28,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 12),

                  // Subtitle
                  Text(
                    'Enter your email address and we\'ll send you a verification code to reset your password.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: isDark ? Colors.white70 : Colors.grey[700],
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 40),

                  // Email Field
                  CustomTextField(
                    controller: _emailController,
                    label: 'Email Address',
                    hint: 'Enter your email',
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: const Icon(Icons.email_outlined),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Email is required';
                      if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v)) return 'Invalid email format';
                      return null;
                    },
                  ),

                  const SizedBox(height: 24),

                  // Submit Button
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _handleSubmit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Send Reset Code',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Back to Login
                  TextButton(
                    onPressed: () => context.pop(),
                    child: Text(
                      'Back to Login',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}