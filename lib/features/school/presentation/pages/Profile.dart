import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_url.dart';
import '../../../../core/widgets/custom_app_bar.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/theme/theme_provider.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);

    final user = authProvider.user;

    final name = user?['name']?.toString() ?? 'Unknown User';
    final username = user?['username']?.toString() ?? 'No username';
    final usertype = user?['usertype']?.toString() ?? 'User';
    final phone = user?['phone']?.toString() ?? 'Not provided';
    final project = user?['project']?.toString() ?? 'Not assigned';
    final cat = user?['cat']?.toString() ?? 'N/A';
    final district = user?['district']?.toString() ?? 'Not assigned';
    final id = user?['id']?.toString() ?? '—';

    String? photoUrl = user?['photo_url']?.toString();
    if (photoUrl == null || photoUrl.trim().isEmpty) {
      photoUrl = user?['photo']?.toString();
    }
    if (photoUrl != null && !photoUrl.startsWith('http')) {
      photoUrl = '${AppUrl.photoLink ?? AppUrl.url}/$photoUrl';
    }

    final isDark = themeProvider.isDarkMode;
    final backgroundColor = isDark ? Colors.grey[900]! : Colors.grey[50]!;
    final cardColor = isDark ? Colors.grey[850]! : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.white70 : Colors.grey[700]!;
    final headerTextColor = Colors.white;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: CustomAppBar(
        title: 'Profile',
        backgroundColor: AppColors.primary,
        textColor: headerTextColor,
        leading: IconButton(
          icon: const Icon(Icons.verified_user, color: Colors.white),
          onPressed: () => (),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            // Header (gradient stays the same)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 60),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.primary, AppColors.primary.withOpacity(0.8)],
                ),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 65,
                    backgroundColor: Colors.white,
                    child: CircleAvatar(
                      radius: 60,
                      backgroundColor: AppColors.primary.withOpacity(0.2),
                      backgroundImage: photoUrl != null && photoUrl.trim().isNotEmpty
                          ? NetworkImage(photoUrl)
                          : null,
                      child: photoUrl == null || photoUrl.trim().isEmpty
                          ? const Icon(Icons.person, size: 70, color: Colors.white)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(name,
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: headerTextColor)),
                  const SizedBox(height: 8),
                  Text(usertype,
                      style: TextStyle(fontSize: 18, color: headerTextColor.withOpacity(0.9), fontWeight: FontWeight.w500)),
                  const SizedBox(height: 12),
                  Text(username,
                      style: TextStyle(fontSize: 16, color: headerTextColor.withOpacity(0.85))),
                  const SizedBox(height: 8),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Account Information',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 16),

                  _buildDetailTile(Icons.badge, 'User Type', usertype, textColor, secondaryTextColor, cardColor, context),
                  _buildDetailTile(Icons.phone, 'Phone', phone, textColor, secondaryTextColor, cardColor, context),
                  _buildDetailTile(Icons.work, 'Project', project, textColor, secondaryTextColor, cardColor, context),
                  _buildDetailTile(Icons.category, 'Category', cat, textColor, secondaryTextColor, cardColor, context),
                  _buildDetailTile(Icons.location_on, 'District', district, textColor, secondaryTextColor, cardColor, context),

                  const SizedBox(height: 32),

                  OutlinedButton.icon(
                    icon: const Icon(Icons.logout, color: Colors.redAccent),
                    label: const Text('Logout',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.redAccent)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent, width: 2),
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      backgroundColor: isDark ? Colors.grey[850] : Colors.white,
                    ),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: isDark ? Colors.grey[850] : Colors.white,
                          title: Text('Logout', style: TextStyle(color: textColor)),
                          content: Text('Are you sure you want to log out?', style: TextStyle(color: textColor)),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Logout', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true && context.mounted) {
                        await Provider.of<AuthProvider>(context, listen: false).logout();
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailTile(
      IconData icon,
      String title,
      String value,
      Color textColor,
      Color secondaryTextColor,
      Color cardColor,
      BuildContext context,  // ← added context parameter
      ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary, size: 32),
        title: Text(title, style: TextStyle(fontSize: 15, color: secondaryTextColor)),
        subtitle: Text(
          value.isEmpty ? 'Not provided' : value,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: textColor),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required BuildContext context,         // ← required parameter
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    return ElevatedButton.icon(
      icon: Icon(icon, size: 20),
      label: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.1),
        foregroundColor: color,
        elevation: 0,
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: isDark ? BorderSide(color: color.withOpacity(0.3)) : null,
      ),
    );
  }
}