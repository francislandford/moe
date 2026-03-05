// reset_password_code_page.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pinput/pinput.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/widgets/loading_overlay.dart';
import '../providers/auth_provider.dart';

class ResetPasswordCodePage extends StatefulWidget {
  final String? email;

  const ResetPasswordCodePage({
    super.key,
    this.email,
  });

  @override
  State<ResetPasswordCodePage> createState() => _ResetPasswordCodePageState();
}

class _ResetPasswordCodePageState extends State<ResetPasswordCodePage> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  bool _isResending = false;
  int _resendTimer = 60;
  bool _canResend = true;

  // Get email from widget if available, otherwise from route
  String? get _email => widget.email ?? _routeEmail;
  String? _routeEmail;

  @override
  void initState() {
    super.initState();

    // Use post frame callback to safely access GoRouter
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Access route data after build is complete
      final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
      setState(() {
        _routeEmail = extra?['email'] as String?;
      });

      // Start resend timer only if we have email
      if (_email != null) {
        startResendTimer();
      }
    });
  }

  void startResendTimer() {
    _canResend = false;
    _resendTimer = 60;

    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        setState(() {
          if (_resendTimer > 0) {
            _resendTimer--;
          } else {
            _canResend = true;
          }
        });
      }
      return _resendTimer > 0 && mounted;
    });
  }

  Future<void> _handleSubmit() async {
    if (_email == null) {
      _showError('Email not found. Please go back and try again.');
      return;
    }

    if (_codeController.text.length != 6) {
      _showError('Please enter a valid 6-digit code');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // Call verify reset code API
      final result = await authProvider.verifyResetCode(
        _email!,
        _codeController.text.trim(),
      );

      if (mounted) {
        if (result['success'] == true) {
          // Navigate to new password page with email and code
          context.push('/reset-password-new', extra: {
            'email': _email,
            'code': _codeController.text.trim(),
          });
        } else {
          _showError(result['message'] ?? 'Invalid code');
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

  Future<void> _handleResendCode() async {
    if (!_canResend || _email == null) return;

    setState(() => _isResending = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // Call resend reset code API
      final result = await authProvider.resendResetCode(_email!);

      if (mounted) {
        if (result['success'] == true) {
          _showSuccess(result['message'] ?? 'New code sent');
          startResendTimer(); // Restart timer
        } else {
          _showError(result['message'] ?? 'Failed to resend code');
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Error: ${e.toString()}');
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
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

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.success ?? Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final defaultPinTheme = PinTheme(
      width: 56,
      height: 56,
      textStyle: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Code', style: TextStyle(color: Colors.white)),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: LoadingOverlay(
        isLoading: _isLoading || _isResending,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
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
                      Icons.sms_outlined,
                      size: 50,
                      color: AppColors.primary,
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Title
                Text(
                  'Enter Verification Code',
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
                      ? 'We\'ve sent a 6-digit code to\n$_email'
                      : 'Loading email address...',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: isDark ? Colors.white70 : Colors.grey[700],
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 40),

                // Code Input
                Center(
                  child: Pinput(
                    controller: _codeController,
                    length: 6,
                    defaultPinTheme: defaultPinTheme,
                    focusedPinTheme: defaultPinTheme.copyWith(
                      decoration: defaultPinTheme.decoration!.copyWith(
                        border: Border.all(color: AppColors.primary),
                      ),
                    ),
                    onCompleted: (pin) => _handleSubmit(),
                  ),
                ),

                const SizedBox(height: 24),

                // Resend Code Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _canResend ? "Didn't receive code? " : "Resend code in $_resendTimer seconds ",
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.grey[600],
                      ),
                    ),
                    if (_canResend)
                      GestureDetector(
                        onTap: _handleResendCode,
                        child: Text(
                          'Resend',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 32),

                // Verify Button
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _email == null ? null : _handleSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade400,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Verify Code',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Back to Email
                TextButton(
                  onPressed: () => context.pop(),
                  child: Text(
                    'Back to Email',
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
    );
  }
}