import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/custom_app_bar.dart';
import '../../../../core/theme/theme_provider.dart'; // ← Import ThemeProvider

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;

    // Adaptive colors
    final backgroundColor = isDark ? Colors.grey[900] : Colors.grey[50];
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.white70 : Colors.grey[700];
    final accentColor = AppColors.primary; // keep brand color

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: CustomAppBar(
        title: 'About',
        backgroundColor: accentColor,
        textColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.info_outline, color: Colors.white),
          onPressed: () => (),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ─── Hero Header ───────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 60),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      accentColor,
                      accentColor.withOpacity(0.85),
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.school_rounded,
                      size: 100,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'School Quality Assessment',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Empowering Education Through Data & Transparency',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white.withOpacity(0.9),
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Version 1.0.0 • Liberia MOE Initiative',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),

              // ─── Content Section ──────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle(context, 'Our Mission'),
                    const SizedBox(height: 12),
                    Text(
                      'The School Mapping, Quality Assessment and Performance App is designed to support the Ministry of Education in monitoring and improving school performance across Liberia. By enabling real-time data collection during school visits, the app helps identify gaps, track progress, and ensure accountability at every level.',
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.6,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 32),

                    _buildSectionTitle(context, 'Key Features'),
                    const SizedBox(height: 16),
                    _buildFeatureItem(Icons.school, 'Comprehensive school modules'),
                    _buildFeatureItem(Icons.assessment, 'Classroom observation tools'),
                    _buildFeatureItem(Icons.people, 'User-friendly for field officers'),
                    _buildFeatureItem(Icons.security, 'Secure & authenticated access'),
                    const SizedBox(height: 32),

                    _buildSectionTitle(context, 'About the Project'),
                    const SizedBox(height: 12),
                    Text(
                      'This mobile application is part of Liberia\'s broader effort to strengthen education monitoring and evaluation systems. It was developed to replace paper-based assessments with a digital, reliable, and efficient solution that works even in low-connectivity areas.',
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.6,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 32),

                    _buildSectionTitle(context, 'Contact & Support'),
                    const SizedBox(height: 12),
                    _buildContactItem(Icons.email, 'Email', 'support@moe.gov.lr'),
                    _buildContactItem(Icons.phone, 'Helpline', '+231 000 000 000'),
                    const SizedBox(height: 40),

                    // Footer
                    Center(
                      child: Column(
                        children: [
                          Text(
                            '© 2025 Ministry of Education, Liberia',
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Built with ❤️ for better education',
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    return Text(
      title,
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: isDark ? Colors.white : Colors.black87,
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String text) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: AppColors.primary,
            size: 28,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 16,
                height: 1.5,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactItem(IconData icon, String label, String value) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(
            icon,
            color: AppColors.primary,
            size: 28,
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.grey[700],
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}