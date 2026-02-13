import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../providers/auth_provider.dart';
import '../../../../core/widgets/custom_text_field.dart';
import '../../../../core/widgets/loading_overlay.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();

    try {
      final success = await auth.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (success && mounted) {
        // context.go('/home'); // ← change to your actual dashboard route

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Login successful'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      } else if (mounted) {
        // Login returned false → show generic failure message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Login failed. Please check your credentials.'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      String msg = 'An error occurred. Please try again.';
      final errorStr = e.toString().toLowerCase();

      if (errorStr.contains('401') ||
          errorStr.contains('422') ||
          errorStr.contains('invalid credentials') ||
          errorStr.contains('unauthorized')) {
        msg = 'Invalid email or password.';
      } else if (errorStr.contains('network') ||
          errorStr.contains('connection') ||
          errorStr.contains('socketexception') ||
          errorStr.contains('timeout')) {
        msg = 'Network error. Please check your internet connection.';
      } else if (errorStr.contains('server')) {
        msg = 'Server error. Please try again later.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, child) {
        return Scaffold(
          body: LoadingOverlay(
            isLoading: auth.isLoading,
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 40),

                      Center(
                        child: Column(
                          children: [
                            Icon(Icons.school_rounded, size: 64, color: AppColors.primary),
                            const SizedBox(height: 16),
                            Text(
                              'School Quality Assessment',
                              style: AppTextStyles.heading1.copyWith(fontSize: 26, color: AppColors.primaryDark),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Liberia Ministry of Education',
                              style: AppTextStyles.bodyMedium.copyWith(fontSize: 15),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 60),

                      Text('Sign In', style: AppTextStyles.heading2.copyWith(fontSize: 28)),
                      const SizedBox(height: 8),
                      Text('District Education Officers & Supervisors', style: AppTextStyles.bodyMedium),

                      const SizedBox(height: 40),

                      CustomTextField(
                        controller: _emailController,
                        label: 'Email',
                        hint: 'email@example.com',
                        keyboardType: TextInputType.emailAddress,
                        prefixIcon: const Icon(Icons.email_outlined),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Email is required';
                          if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v)) return 'Invalid email';
                          return null;
                        },
                      ),

                      const SizedBox(height: 24),

                      CustomTextField(
                        controller: _passwordController,
                        label: 'Password',
                        obscureText: _obscurePassword,
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Password is required';
                          if (v.length < 4) return 'At least 4 characters';
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Forgot password – contact support')),
                            );
                          },
                          child: Text('Forgot password?', style: TextStyle(color: AppColors.primary)),
                        ),
                      ),

                      const SizedBox(height: 32),

                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: auth.isLoading ? null : _handleLogin,
                          child: Text(
                            'Sign In',
                            style: const TextStyle(
                              fontSize: 17,
                              fontFamily: 'RobotoSlabRegular',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 40),

                      Center(
                        child: Text(
                          'Use your official MoE credentials',
                          style: AppTextStyles.bodyMedium.copyWith(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}