// reset_password_new_page.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/widgets/custom_text_field.dart';
import '../../../../core/widgets/loading_overlay.dart';
import '../providers/auth_provider.dart';

class ResetPasswordNewPage extends StatefulWidget {
  final String? email;
  final String? code;

  const ResetPasswordNewPage({
    super.key,
    this.email,
    this.code,
  });

  @override
  State<ResetPasswordNewPage> createState() => _ResetPasswordNewPageState();
}

class _ResetPasswordNewPageState extends State<ResetPasswordNewPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Route data (as fallback)
  String? _routeEmail;
  String? _routeCode;

  // Get email and code from widget if available, otherwise from route
  String? get _email => widget.email ?? _routeEmail;
  String? get _code => widget.code ?? _routeCode;

  @override
  void initState() {
    super.initState();

    // Use post frame callback to safely access GoRouter
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Access route data after build is complete
      final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
      setState(() {
        _routeEmail = extra?['email'] as String?;
        _routeCode = extra?['code'] as String?;
      });
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    // Check if we have email and code
    if (_email == null || _code == null) {
      _showError('Missing verification data. Please restart the process.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // Call reset password API
      final result = await authProvider.resetPassword(
        _email!,
        _code!,
        _passwordController.text,
        _confirmPasswordController.text,
      );

      if (mounted) {
        if (result['success'] == true) {
          // Show success dialog
          _showSuccessDialog();
        } else {
          _showError(result['message'] ?? 'Failed to reset password');
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Error: ${e.toString()}');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Icon(
          Icons.check_circle,
          color: Colors.green,
          size: 60,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Password Reset Successful!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Your password has been reset successfully. You can now login with your new password.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/login');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Go to Login'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Password', style: TextStyle(color: Colors.white)),
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
                        Icons.lock_reset_outlined,
                        size: 50,
                        color: AppColors.primary,
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Title
                  Text(
                    'Create New Password',
                    style: AppTextStyles.heading1.copyWith(
                      fontSize: 28,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 12),

                  // Subtitle
                  Text(
                    _email != null
                        ? 'Set a new password for\n$_email'
                        : 'Set your new password below',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: isDark ? Colors.white70 : Colors.grey[700],
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 40),

                  // New Password Field
                  CustomTextField(
                    controller: _passwordController,
                    label: 'New Password',
                    obscureText: _obscurePassword,
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Password is required';
                      if (v.length < 4) return 'Password must be at least 4 characters';
                      if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(v)) {
                        return 'Password can only contain letters and numbers';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  // Confirm Password Field
                  CustomTextField(
                    controller: _confirmPasswordController,
                    label: 'Confirm Password',
                    obscureText: _obscureConfirmPassword,
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Please confirm your password';
                      if (v != _passwordController.text) return 'Passwords do not match';
                      return null;
                    },
                  ),

                  const SizedBox(height: 24),

                  // Submit Button
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: (_email == null || _code == null) ? null : _handleSubmit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade400,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Reset Password',
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
                    onPressed: () => context.go('/login'),
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